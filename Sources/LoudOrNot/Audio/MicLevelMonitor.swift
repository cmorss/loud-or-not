import AVFoundation
import Accelerate
import LoudOrNotCore

enum MicError: LocalizedError {
    case permissionDenied
    case noInputDevice
    case deviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Grant it in System Settings > Privacy & Security > Microphone."
        case .noInputDevice:
            return "No microphone input available."
        case .deviceUnavailable(let name):
            return "Could not listen to \(name)."
        }
    }
}

/// Owns the audio capture. Reports a smoothed loudness in dBFS on the main thread.
///
/// This is a capture session rather than an `AVAudioEngine` because it has to listen to a
/// microphone we name, which the engine cannot do: its input and output share one IO unit, so
/// the input follows whichever device the system is playing through. Asking the unit for a
/// different input device reports success and is then quietly ignored, which showed up as the
/// app listening to a Bluetooth headset it had been told not to touch.
final class MicLevelMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onLevel: ((Double) -> Void)?
    /// Capture can also fail well after it started, when a device is taken away or claimed
    /// exclusively, and that is worth saying out loud rather than showing a dead meter.
    var onFailure: ((Error) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let processor = LevelProcessor()
    private let samples = DispatchQueue(label: "com.cmorss.loudornot.samples")
    /// A capture session is not thread safe, and both configuring it and starting it block for
    /// long enough to be felt on the main thread, so all of it happens here in order.
    private let control = DispatchQueue(label: "com.cmorss.loudornot.session")
    private var runtimeErrorObserver: NSObjectProtocol?
    private(set) var isRunning = false
    /// Which microphone we are listening to, so a change of choice can be noticed.
    private(set) var requestedDevice: AudioInputChoice?

    static var permissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    override init() {
        super.init()
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.fail(error ?? MicError.noInputDevice)
        }
    }

    func start(device: AudioInputChoice?) throws {
        if isRunning {
            guard device?.uid != requestedDevice?.uid else { return }
            stop()
        }
        guard Self.permissionStatus == .authorized else { throw MicError.permissionDenied }

        let input = try captureInput(for: device)
        requestedDevice = device
        isRunning = true
        samples.async { [processor] in processor.reset() }
        control.async { [weak self] in self?.configureAndStart(with: input) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        requestedDevice = nil
        control.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
        samples.async { [processor] in processor.reset() }
        onLevel?(LevelMath.floorDB)
    }

    /// Turns the chosen microphone into something the session can take.
    ///
    /// A microphone we were asked for but cannot open is an error, never a reason to fall back
    /// to the system default input. The default is usually the headset, which is the one device
    /// this app goes out of its way not to touch, and falling back to it silently would look
    /// like the choice had been honoured.
    private func captureInput(for device: AudioInputChoice?) throws -> AVCaptureDeviceInput {
        // A device's uniqueID is its CoreAudio UID, so the choice maps across directly.
        let captureDevice = device.map { AVCaptureDevice(uniqueID: $0.uid) }
            ?? AVCaptureDevice.default(for: .audio)
        guard let captureDevice else {
            throw device.map { MicError.deviceUnavailable($0.name) } ?? .noInputDevice
        }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else {
            throw MicError.deviceUnavailable(captureDevice.localizedName)
        }
        return input
    }

    private func configureAndStart(with input: AVCaptureDeviceInput) {
        session.beginConfiguration()
        for existing in session.inputs {
            session.removeInput(existing)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            fail(MicError.deviceUnavailable(input.device.localizedName))
            return
        }
        session.addInput(input)

        if session.outputs.isEmpty {
            // Plain interleaved floats, so the level maths does not have to care what the
            // microphone natively produces.
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            output.setSampleBufferDelegate(self, queue: samples)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                fail(MicError.noInputDevice)
                return
            }
            session.addOutput(output)
        }
        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }
    }

    private func fail(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.stop()
            self.onFailure?(error)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let db = processor.process(sampleBuffer) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.onLevel?(db)
        }
    }
}

/// Touched only from the capture queue.
private final class LevelProcessor {
    private var smoother = LoudnessSmoother()

    func process(_ sampleBuffer: CMSampleBuffer) -> Double? {
        guard
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        else { return nil }

        let sampleRate = streamDescription.mSampleRate
        guard sampleRate > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        // The samples are interleaved, so one root-mean-square over the whole buffer is the
        // level across every channel, which is what we want anyway.
        var sumOfSquares: Double = 0
        var count: vDSP_Length = 0
        for buffer in UnsafeMutableAudioBufferListPointer(&list) {
            guard let data = buffer.mData else { continue }
            let frames = vDSP_Length(buffer.mDataByteSize) / vDSP_Length(MemoryLayout<Float>.size)
            guard frames > 0 else { continue }

            var meanSquare: Float = 0
            vDSP_measqv(data.assumingMemoryBound(to: Float.self), 1, &meanSquare, frames)
            sumOfSquares += Double(meanSquare) * Double(frames)
            count += frames
        }
        guard count > 0 else { return nil }

        let channels = max(Double(streamDescription.mChannelsPerFrame), 1)
        let instantDB = LevelMath.dBFS(rms: (sumOfSquares / Double(count)).squareRoot())
        let deltaTime = Double(count) / channels / sampleRate
        return smoother.add(instantDB: instantDB, deltaTime: deltaTime)
    }

    func reset() {
        smoother.reset()
    }
}

import AVFoundation
import Accelerate
import LoudOrNotCore

enum MicError: LocalizedError {
    case permissionDenied
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Grant it in System Settings > Privacy & Security > Microphone."
        case .noInputDevice:
            return "No microphone input available."
        }
    }
}

/// Owns the audio tap. Reports a smoothed loudness in dBFS on the main thread.
final class MicLevelMonitor {
    var onLevel: ((Double) -> Void)?

    private let engine = AVAudioEngine()
    private let processor = LevelProcessor()
    private var configurationObserver: NSObjectProtocol?
    private(set) var isRunning = false

    static var permissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        guard !isRunning else { return }
        guard Self.permissionStatus == .authorized else { throw MicError.permissionDenied }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicError.noInputDevice }

        processor.reset()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let db = self.processor.process(buffer) else { return }
            DispatchQueue.main.async { self.onLevel?(db) }
        }

        engine.prepare()
        try engine.start()
        isRunning = true

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.restart()
        }
    }

    func stop() {
        guard isRunning else { return }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        processor.reset()
        onLevel?(LevelMath.floorDB)
    }

    /// Switching input devices invalidates the tap's format, so the engine has to be rebuilt.
    private func restart() {
        guard isRunning else { return }
        stop()
        try? start()
    }
}

/// Touched only from the audio render thread.
private final class LevelProcessor {
    private var smoother = LoudnessSmoother()

    func process(_ buffer: AVAudioPCMBuffer) -> Double? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let frameCount = buffer.frameLength
        guard frameCount > 0, buffer.format.sampleRate > 0 else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameCount))

        let instantDB = LevelMath.dBFS(rms: Double(rms))
        let deltaTime = Double(frameCount) / buffer.format.sampleRate
        return smoother.add(instantDB: instantDB, deltaTime: deltaTime)
    }

    func reset() {
        smoother.reset()
    }
}

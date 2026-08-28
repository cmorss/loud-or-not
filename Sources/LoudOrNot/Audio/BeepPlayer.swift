import AVFoundation
import LoudOrNotCore

/// Plays the warning tone. It runs its own engine rather than sharing the one taking the
/// microphone apart, so that the output device appearing or vanishing cannot interrupt
/// level monitoring.
final class BeepPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var configurationObserver: NSObjectProtocol?

    init() {
        // Headphones disconnecting leaves the engine pointing at a device that is gone, so
        // tear it down and let the next beep build a fresh one around the new output.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.engine.stop()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    func play() {
        guard let buffer = makeBuffer() else { return }
        if !engine.isRunning {
            engine.prepare()
            guard (try? engine.start()) != nil else { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// The tone never changes, so it is rendered once and kept.
    private func makeBuffer() -> AVAudioPCMBuffer? {
        if let buffer { return buffer }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            return nil
        }

        let samples = Tone.warningBeep(sampleRate: format.sampleRate)
        guard
            !samples.isEmpty,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: samples.count)
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.buffer = buffer
        return buffer
    }
}

import AVFoundation
import LoudOrNotCore

/// Plays the warning tone.
///
/// The engine is built for each beep and torn down once the sound has finished. Holding one
/// open was both wasteful, since it keeps a CoreAudio render thread and the output device
/// alive for a quarter of a second of audio, and fragile: an engine started against
/// headphones that have since slept, reconnected, or been swapped stays wedged, and every
/// later beep goes nowhere. Building it fresh binds each beep to whatever you are wearing now.
final class BeepPlayer {
    private let format: AVAudioFormat?
    private let samples: [Float]
    private var engine: AVAudioEngine?
    private var generation = 0

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        self.format = format
        samples = Tone.warningBeep(sampleRate: format?.sampleRate ?? 44_100)
    }

    func play() {
        // Also covers the case where a previous beep's completion never arrived.
        teardown()

        guard let format, let buffer = makeBuffer(format: format) else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        self.engine = engine

        generation += 1
        let token = generation
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            DispatchQueue.main.async { self?.finish(token: token) }
        }
        player.play()
    }

    /// Ignores the completion of a beep that has already been replaced by a newer one.
    private func finish(token: Int) {
        guard token == generation else { return }
        teardown()
    }

    private func teardown() {
        engine?.stop()
        engine = nil
    }

    private func makeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
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
        return buffer
    }
}

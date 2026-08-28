import Foundation

/// Rate limiter for the audible warning. The glow can run continuously because it is easy
/// to ignore, but a beep firing on every audio buffer while you are shouting would be
/// unbearable, so it is held to one per interval.
public struct BeepThrottle {
    public var minimumIntervalSeconds: Double
    private var lastBeepAt: Double?

    public init(minimumIntervalSeconds: Double = 3.5) {
        self.minimumIntervalSeconds = minimumIntervalSeconds
    }

    @discardableResult
    public mutating func shouldBeep(now: Double) -> Bool {
        if let lastBeepAt, now - lastBeepAt < minimumIntervalSeconds { return false }
        lastBeepAt = now
        return true
    }

    public mutating func reset() {
        lastBeepAt = nil
    }
}

public enum Tone {
    /// A short sine pip shaped by a raised cosine. The shaping is not decoration: a sine
    /// switched on and off abruptly clicks, and a click reads as a fault rather than as a
    /// warning.
    public static func pip(
        frequency: Double,
        seconds: Double,
        sampleRate: Double,
        amplitude: Double
    ) -> [Float] {
        let count = Int(seconds * sampleRate)
        guard count > 0, sampleRate > 0 else { return [] }
        let last = Double(max(count - 1, 1))
        return (0..<count).map { index in
            let envelope = 0.5 - 0.5 * cos(2 * .pi * Double(index) / last)
            let phase = 2 * .pi * frequency * Double(index) / sampleRate
            return Float(amplitude * envelope * sin(phase))
        }
    }

    public static func silence(seconds: Double, sampleRate: Double) -> [Float] {
        Array(repeating: 0, count: max(Int(seconds * sampleRate), 0))
    }

    /// Two rising pips: enough to catch you mid-sentence, short enough not to talk over you,
    /// and distinct enough that it is not mistaken for a system alert.
    public static func warningBeep(sampleRate: Double, amplitude: Double = 0.25) -> [Float] {
        pip(frequency: 880, seconds: 0.09, sampleRate: sampleRate, amplitude: amplitude)
            + silence(seconds: 0.06, sampleRate: sampleRate)
            + pip(frequency: 1108, seconds: 0.11, sampleRate: sampleRate, amplitude: amplitude)
    }
}

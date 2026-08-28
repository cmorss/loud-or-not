import Foundation

public enum LevelMath {
    /// Quietest level we ever report. Anything below this is indistinguishable from silence.
    public static let floorDB: Double = -80

    public static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * clamp(t, 0, 1)
    }

    public static func dBFS(rms: Double) -> Double {
        guard rms > 0 else { return floorDB }
        return max(floorDB, 20 * log10(rms))
    }

    /// Maps a loudness reading onto 0...1, where 0 is the warn threshold and 1 is the loud threshold.
    public static func intensity(forDB db: Double, warnDB: Double, loudDB: Double) -> Double {
        let span = loudDB - warnDB
        guard span > 0.5 else { return db >= loudDB ? 1 : 0 }
        return clamp((db - warnDB) / span, 0, 1)
    }

    /// Pulses per second: a lazy throb when you first cross the line, urgent when you are shouting.
    public static func pulseFrequency(intensity: Double) -> Double {
        lerp(0.6, 2.5, intensity)
    }

    /// Position of a dB value on the 0...1 meter scale used by the UI.
    public static func meterPosition(forDB db: Double, minDB: Double = -60, maxDB: Double = 0) -> Double {
        clamp((db - minDB) / (maxDB - minDB), 0, 1)
    }
}

/// Exponential smoother with separate attack and release, gated so that pauses between
/// sentences do not drag the average down but a single cough cannot spike it either.
public struct LoudnessSmoother {
    public var attackSeconds: Double
    public var releaseSeconds: Double
    public var noiseGateDB: Double
    public private(set) var valueDB: Double

    public init(
        attackSeconds: Double = 0.8,
        releaseSeconds: Double = 1.5,
        noiseGateDB: Double = -45
    ) {
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        self.noiseGateDB = noiseGateDB
        self.valueDB = LevelMath.floorDB
    }

    @discardableResult
    public mutating func add(instantDB: Double, deltaTime: Double) -> Double {
        guard deltaTime > 0 else { return valueDB }
        let target = instantDB > noiseGateDB ? instantDB : LevelMath.floorDB
        let tau = target > valueDB ? attackSeconds : releaseSeconds
        let alpha = 1 - exp(-deltaTime / max(tau, 0.001))
        valueDB = max(LevelMath.floorDB, valueDB + (target - valueDB) * alpha)
        return valueDB
    }

    public mutating func reset() {
        valueDB = LevelMath.floorDB
    }
}

/// Latching so the glow does not flicker on and off while you hover right at the threshold.
public struct Hysteresis {
    public var releaseMarginDB: Double
    public private(set) var isEngaged: Bool = false

    public init(releaseMarginDB: Double = 2) {
        self.releaseMarginDB = releaseMarginDB
    }

    @discardableResult
    public mutating func update(db: Double, warnDB: Double) -> Bool {
        if isEngaged {
            if db < warnDB - releaseMarginDB { isEngaged = false }
        } else if db >= warnDB {
            isEngaged = true
        }
        return isEngaged
    }
}

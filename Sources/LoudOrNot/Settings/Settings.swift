import Foundation

enum ActivationMode: String, CaseIterable, Identifiable {
    case meetingsOnly
    case alwaysOn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetingsOnly: return "Only during meetings"
        case .alwaysOn: return "Always on"
        }
    }

    var explanation: String {
        switch self {
        case .meetingsOnly: return "Watches for another app using the microphone."
        case .alwaysOn: return "Listens whenever Loud or Not is enabled."
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    @Published var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Key.activationMode) }
    }
    @Published var warnDB: Double { didSet { defaults.set(warnDB, forKey: Key.warnDB) } }
    @Published var loudDB: Double { didSet { defaults.set(loudDB, forKey: Key.loudDB) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.activationMode: ActivationMode.alwaysOn.rawValue,
            Key.warnDB: -26.0,
            Key.loudDB: -14.0,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        activationMode = ActivationMode(rawValue: defaults.string(forKey: Key.activationMode) ?? "")
            ?? .alwaysOn
        warnDB = defaults.double(forKey: Key.warnDB)
        loudDB = defaults.double(forKey: Key.loudDB)
    }

    /// Thresholds are set by dragging sliders and by grabbing the live level, so they need
    /// to stay ordered and inside the meter's range no matter which path wrote them.
    func setWarnDB(_ value: Double) {
        warnDB = min(max(value, Meter.minDB), loudDB - Meter.minimumSpanDB)
    }

    func setLoudDB(_ value: Double) {
        loudDB = max(min(value, Meter.maxDB), warnDB + Meter.minimumSpanDB)
    }

    enum Meter {
        static let minDB: Double = -60
        static let maxDB: Double = 0
        static let minimumSpanDB: Double = 3
    }

    private enum Key {
        static let isEnabled = "isEnabled"
        static let activationMode = "activationMode"
        static let warnDB = "warnDB"
        static let loudDB = "loudDB"
    }
}

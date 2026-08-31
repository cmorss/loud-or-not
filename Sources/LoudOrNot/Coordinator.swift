import AVFoundation
import AppKit
import Combine
import LoudOrNotCore
import QuartzCore

/// Single owner of runtime state: decides whether we are armed, turns the smoothed mic
/// level into a glow intensity, and pushes that to the overlay and the menu bar panel.
@MainActor
final class Coordinator: ObservableObject {
    enum ArmState: Equatable {
        case disabled
        case needsPermission
        case permissionDenied
        case unavailable(String)
        case idle(String)
        case armed(String)

        var summary: String {
            switch self {
            case .disabled: return "Off"
            case .needsPermission: return "Needs microphone access"
            case .permissionDenied: return "Microphone access denied"
            case .unavailable(let message): return message
            case .idle(let reason): return "Idle - \(reason)"
            case .armed(let reason): return "Listening - \(reason)"
            }
        }

        var isArmed: Bool {
            if case .armed = self { return true }
            return false
        }
    }

    // Only slow-moving state is published here. The level itself goes to `meter`, which the
    // meter view observes on its own, so a new reading does not invalidate the whole panel.
    @Published private(set) var isGlowing = false
    @Published private(set) var state: ArmState = .disabled

    let settings: Settings
    let meter = MeterLevel()

    private let monitor = MicLevelMonitor()
    private let usageWatcher = MicUsageWatcher()
    private let overlay = GlowOverlayController()
    private let beeper = BeepPlayer()
    private let outputRoute = OutputRoute()
    private var beepThrottle = BeepThrottle()
    private var hysteresis = Hysteresis()
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings

        monitor.onLevel = { [weak self] db in
            MainActor.assumeIsolated { self?.handle(levelDB: db) }
        }
        usageWatcher.onChange = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // objectWillChange fires before the new value lands, so read it on the next turn.
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
    }

    func start() {
        let status = MicLevelMonitor.permissionStatus
        log("start: permission=\(status.rawValue)")
        if status == .notDetermined {
            // Show the pending state rather than leaving the panel reading "Off"
            // while the system prompt is waiting for an answer.
            state = .needsPermission
            requestPermission()
        } else {
            refresh()
        }
    }

    private func log(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["LOUDORNOT_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[lon] \(message())\n".utf8))
    }

    func requestPermission() {
        Task { @MainActor in
            _ = await MicLevelMonitor.requestPermission()
            refresh()
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func handle(levelDB db: Double) {
        meter.update(db: db)
        let engaged = hysteresis.update(db: db, warnDB: settings.warnDB)
        let level = LevelMath.intensity(forDB: db, warnDB: settings.warnDB, loudDB: settings.loudDB)
        setGlow(engaged: engaged, intensity: engaged ? level : 0)
        warnAudibly(isLoud: db >= settings.loudDB)
    }

    /// Headphones only. A beep through the speakers would carry into the room, which is the
    /// exact thing this app exists to prevent. The conditions are ordered so the route is
    /// only queried once you are in the red, and the throttle is only spent on a real beep.
    private func warnAudibly(isLoud: Bool) {
        guard isLoud, settings.beepEnabled else { return }
        guard outputRoute.isHeadphones else {
            log("loud, but output is not headphones")
            return
        }
        guard beepThrottle.shouldBeep(now: CACurrentMediaTime()) else { return }
        log("beep")
        beeper.play()
    }

    private func setGlow(engaged: Bool, intensity: Double) {
        // Both are compared before assigning: these run on every audio buffer, and isGlowing
        // is published, so writing it unconditionally would invalidate the UI constantly.
        if isGlowing != engaged { isGlowing = engaged }
        overlay.setState(engaged: engaged, intensity: intensity)
    }

    private func refresh() {
        log("refresh: enabled=\(settings.isEnabled) mode=\(settings.activationMode.rawValue) permission=\(MicLevelMonitor.permissionStatus.rawValue)")
        guard settings.isEnabled else {
            disarm()
            state = .disabled
            return
        }

        switch MicLevelMonitor.permissionStatus {
        case .denied, .restricted:
            disarm()
            state = .permissionDenied
            return
        case .notDetermined:
            disarm()
            state = .needsPermission
            return
        default:
            break
        }

        if settings.activationMode == .meetingsOnly {
            usageWatcher.start()
        } else {
            usageWatcher.stop()
        }

        let shouldArm: Bool
        let reason: String
        switch settings.activationMode {
        case .alwaysOn:
            shouldArm = true
            reason = "always on"
        case .meetingsOnly:
            let usage = usageWatcher.usage
            shouldArm = usage.isActive
            reason = usage.isActive
                ? "\(usage.appName ?? "another app") is using the microphone"
                : "no app is using the microphone"
        }

        guard shouldArm else {
            disarm()
            state = .idle(reason)
            return
        }

        do {
            try monitor.start()
            state = .armed(reason)
            log("armed: \(reason)")
        } catch {
            disarm()
            state = .unavailable(error.localizedDescription)
            log("failed to arm: \(error.localizedDescription)")
        }
    }

    private func disarm() {
        monitor.stop()
        hysteresis = Hysteresis()
        // The next meeting should be able to warn you straight away.
        beepThrottle.reset()
        meter.update(db: LevelMath.floorDB)
        setGlow(engaged: false, intensity: 0)
    }
}

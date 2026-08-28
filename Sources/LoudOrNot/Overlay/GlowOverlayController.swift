import AppKit

final class GlowWindow: NSWindow {
    let glowView: GlowView

    init(screen: NSScreen) {
        glowView = GlowView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        // Joining all spaces plus fullScreenAuxiliary is what puts the glow over a
        // full-screen Zoom window; sharingType none keeps it out of screen shares.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = ProcessInfo.processInfo.environment["LOUDORNOT_CAPTURABLE"] == "1"
            ? .readOnly
            : .none

        contentView = glowView
        glowView.onFadedOut = { [weak self] in self?.orderOut(nil) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class GlowOverlayController {
    private var windows: [GlowWindow] = []
    private var isEngaged = false
    private var intensity: Double = 0

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
    }

    func setState(engaged: Bool, intensity: Double) {
        isEngaged = engaged
        self.intensity = intensity
        for window in windows {
            if engaged, !window.isVisible {
                window.orderFrontRegardless()
            }
            window.glowView.setState(engaged: engaged, intensity: intensity)
        }
    }

    private func rebuild() {
        for window in windows {
            window.orderOut(nil)
        }
        windows = NSScreen.screens.map(GlowWindow.init(screen:))
        setState(engaged: isEngaged, intensity: intensity)
    }
}

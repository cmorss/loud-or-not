import AppKit
import SwiftUI

/// The window the panel lives in: a floating panel anchored under the menu bar icon, the way
/// the system's own menu bar extras work.
///
/// Not an `NSPopover`. A popover's outside-click dismissal and its fully drawn appearance both
/// depend on the app being active, and on current macOS a menu bar click does not activate the
/// app: the items are hosted by Control Center, so the interaction is credited to it and the
/// app's own request to activate is refused. The popover came up looking inactive, half
/// transparent and dim, and stayed open when you clicked elsewhere. This panel becomes key
/// without activating anything, so the controls draw properly, and it watches for the clicks
/// that should close it itself.
@MainActor
final class MenuPanel: NSPanel {
    private let hosting: NSView
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private weak var anchor: NSStatusBarButton?

    init(content: some View) {
        let hosting = NSHostingView(rootView: content)
        self.hosting = hosting
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        // The menu material rather than the popover one: it is made for text and stays legible
        // over a dark window, and it is pinned active so it never fades with the app's focus.
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true

        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func toggle(under button: NSStatusBarButton) {
        if isVisible {
            dismiss()
        } else {
            show(under: button)
        }
    }

    func show(under button: NSStatusBarButton) {
        guard let itemWindow = button.window else { return }
        anchor = button
        setContentSize(hosting.fittingSize)
        position(under: itemWindow.frame, on: itemWindow.screen ?? NSScreen.main)
        makeKeyAndOrderFront(nil)
        button.isHighlighted = true
        watchForDismissal()
    }

    func dismiss() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        anchor?.isHighlighted = false
        orderOut(nil)
    }

    /// Centred under the icon, kept on screen, and hung from the bottom of the menu bar.
    private func position(under item: NSRect, on screen: NSScreen?) {
        var origin = NSPoint(x: item.midX - frame.width / 2, y: item.minY - frame.height)
        if let bounds = screen?.visibleFrame {
            origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - frame.width - 8)
        }
        setFrameOrigin(origin)
    }

    private func watchForDismissal() {
        // Clicks anywhere in another app. A click on the icon itself is left to the icon's own
        // action, which toggles, or the two would cancel each other out.
        let clickedElsewhere = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let item = self.anchor?.window?.frame, item.contains(NSEvent.mouseLocation) {
                        return
                    }
                    self.dismiss()
                }
            }
        )

        let pressedEscape = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard event.keyCode == 53 else { return event }
                MainActor.assumeIsolated { self?.dismiss() }
                return nil
            }
        )

        monitors = [clickedElsewhere, pressedEscape].compactMap { $0 }

        // Switching to another app by keyboard takes key status away without a click. Checked
        // on the next turn so that key status moving to another of our own windows, which is
        // not a reason to close, can be told apart.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isVisible, NSApp.keyWindow == nil else { return }
                    self.dismiss()
                }
            }
        }
    }
}

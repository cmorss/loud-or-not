import AppKit
import Combine
import SwiftUI

/// The menu bar icon and the panel that drops down from it.
///
/// An AppKit status item rather than SwiftUI's `MenuBarExtra`, because this needs a say in
/// where the icon sits, and only the status item exposes the autosave name that position is
/// stored under. That matters because of the notch: on the built-in display the menu bar does
/// not have room for every item, and the ones whose saved position falls left of the notch are
/// silently not drawn. The app kept running with no icon to reach it by whenever the external
/// display went away overnight and the notched menu bar was the only one left.
@MainActor
final class StatusItemController: NSObject {
    private static let autosaveName = "LoudOrNot"
    /// Distance from the right edge of the screen to the icon, as AppKit measures it. Far
    /// enough right to clear the notch on a 16-inch MacBook Pro with a full menu bar.
    private static let seededPosition: Double = 400

    private let coordinator: Coordinator
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: Coordinator, settings: Settings) {
        self.coordinator = coordinator
        Self.seedPositionIfUnset()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.autosaveName = Self.autosaveName
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.toolTip = "Loud or Not"
        updateIcon()

        let panel = NSHostingController(
            rootView: PanelView(coordinator: coordinator, settings: settings)
        )
        panel.sizingOptions = .preferredContentSize
        popover.contentViewController = panel
        popover.behavior = .transient

        coordinator.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateIcon() }
            }
            .store(in: &cancellables)
    }

    /// A brand new item is placed at the far left of the status items, which on a crowded
    /// notched display is under the notch. Seeding a position puts it somewhere visible. Done
    /// only once: after that AppKit owns the value, so dragging the icon somewhere else with
    /// the Command key held sticks.
    private static func seedPositionIfUnset() {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(seededPosition, forKey: key)
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        // A transient popover only dismisses on an outside click while its app is active, and
        // a menu bar click does not activate the app by itself.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateIcon() {
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Loud or Not"
        )
    }

    private var symbolName: String {
        switch coordinator.state {
        case .disabled, .needsPermission, .permissionDenied, .unavailable:
            return "waveform.slash"
        default:
            return coordinator.isGlowing ? "waveform.badge.exclamationmark" : "waveform"
        }
    }
}

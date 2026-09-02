import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var shared: AppDelegate?

    let settings = Settings()
    private lazy var coordinator = Coordinator(settings: settings)
    private var statusItem: StatusItemController?

    /// Plain AppKit rather than a SwiftUI `App`. The only scene this app would have had was
    /// the menu bar item, and that is now managed by hand, so there is nothing left for SwiftUI
    /// to own at the top level.
    static func main() {
        let delegate = AppDelegate()
        shared = delegate
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController(coordinator: coordinator, settings: settings)
        coordinator.start()
    }
}

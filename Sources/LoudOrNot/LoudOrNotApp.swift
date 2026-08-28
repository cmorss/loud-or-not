import AppKit
import SwiftUI

@main
struct LoudOrNotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(coordinator: appDelegate.coordinator, settings: appDelegate.settings)
        } label: {
            MenuBarLabel(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        Image(systemName: symbolName)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = Settings()
    lazy var coordinator = Coordinator(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
    }
}

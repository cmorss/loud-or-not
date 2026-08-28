import ServiceManagement
import SwiftUI

struct PanelView: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject var settings: Settings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            meterSection
            Divider()
            activationSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Loud or Not")
                .font(.headline)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
    }

    private var meterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coordinator.state.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ThresholdMeter(
                levelDB: coordinator.levelDB,
                warnDB: settings.warnDB,
                loudDB: settings.loudDB,
                setWarnDB: { settings.setWarnDB($0) },
                setLoudDB: { settings.setLoudDB($0) }
            )

            Text("Drag the amber and red markers to set your thresholds.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            permissionPrompt
        }
    }

    @ViewBuilder
    private var permissionPrompt: some View {
        switch coordinator.state {
        case .needsPermission:
            Button("Allow microphone access") { coordinator.requestPermission() }
                .controlSize(.small)
        case .permissionDenied:
            Button("Open Privacy Settings") { coordinator.openMicrophoneSettings() }
                .controlSize(.small)
        default:
            EmptyView()
        }
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Listen", selection: $settings.activationMode) {
                ForEach(ActivationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Text(settings.activationMode.explanation)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enabled", isOn: $settings.isEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .armed: return coordinator.isGlowing ? .orange : .green
        case .idle, .disabled: return .secondary
        case .needsPermission, .permissionDenied, .unavailable: return .red
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

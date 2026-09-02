import LoudOrNotCore
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
            MicrophonePicker(devices: coordinator.inputDevices, settings: settings)
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

            MeterRow(level: coordinator.meter, settings: settings)

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

    /// The two modes read as one decision, so they are one checkbox rather than a menu.
    private var meetingsOnly: Binding<Bool> {
        Binding(
            get: { settings.activationMode == .meetingsOnly },
            set: { settings.activationMode = $0 ? .meetingsOnly : .alwaysOn }
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Active during meetings only", isOn: meetingsOnly)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Toggle("Enabled", isOn: $settings.isEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Toggle("Beep when loud (headphones only)", isOn: $settings.beepEnabled)
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

    /// Lists microphones so you can switch without a trip to System Settings. Changing it
    /// only moves this app; it leaves the system's own input device alone, so your meeting
    /// keeps using whichever microphone it was already on.
    private struct MicrophonePicker: View {
        @ObservedObject var devices: AudioInputDevices
        @ObservedObject var settings: Settings

        var body: some View {
            Picker("Microphone", selection: selection) {
                ForEach(devices.devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(devices.devices.isEmpty)
        }

        /// Shows the microphone actually in use, so the default reads as the built-in one
        /// rather than as a blank until you pick something.
        private var selection: Binding<String> {
            Binding(
                get: {
                    InputDeviceSelection.resolve(
                        preferredUID: settings.inputDeviceUID.isEmpty ? nil : settings.inputDeviceUID,
                        available: devices.devices
                    )?.uid ?? ""
                },
                set: { settings.inputDeviceUID = $0 }
            )
        }
    }

    /// Its own view so that a new reading redraws the meter alone, rather than every control
    /// in the panel.
    private struct MeterRow: View {
        @ObservedObject var level: MeterLevel
        @ObservedObject var settings: Settings

        var body: some View {
            ThresholdMeter(
                levelDB: level.db,
                warnDB: settings.warnDB,
                loudDB: settings.loudDB,
                setWarnDB: { settings.setWarnDB($0) },
                setLoudDB: { settings.setLoudDB($0) }
            )
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

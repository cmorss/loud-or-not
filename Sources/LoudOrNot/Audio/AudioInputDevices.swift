import CoreAudio
import LoudOrNotCore
import SwiftUI

/// The list of microphones you can pick from, kept current as devices come and go.
///
/// Devices are remembered by UID rather than by CoreAudio's numeric id, because the number is
/// reassigned when a device is unplugged and reconnected, while the UID is stable.
@MainActor
final class AudioInputDevices: ObservableObject {
    @Published private(set) var devices: [AudioInputChoice] = []

    private var listener: AudioObjectPropertyListenerBlock?

    init() {
        refresh()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        self.listener = listener
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
    }

    func refresh() {
        let found = Self.inputDevices()
        guard found != devices else { return }
        devices = found
    }

    // MARK: - CoreAudio

    private nonisolated static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private nonisolated static func inputDevices() -> [AudioInputChoice] {
        allDeviceIDs().compactMap { device in
            guard hasInput(device), let uid = uid(of: device) else { return nil }
            return AudioInputChoice(
                uid: uid,
                name: name(of: device) ?? uid,
                isBuiltIn: transportType(of: device) == kAudioDeviceTransportTypeBuiltIn
            )
        }
    }

    private nonisolated static func allDeviceIDs() -> [AudioObjectID] {
        var address = self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = self.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private nonisolated static func transportType(of device: AudioObjectID) -> UInt32? {
        var address = self.address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private nonisolated static func uid(of device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    private nonisolated static func name(of device: AudioObjectID) -> String? {
        string(device, kAudioObjectPropertyName)
    }

    private nonisolated static func string(
        _ device: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = self.address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var unmanaged: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = unmanaged?.takeRetainedValue() else { return nil }
        let string = value as String
        return string.isEmpty ? nil : string
    }
}

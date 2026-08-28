import CoreAudio
import QuartzCore

/// Answers "is sound going into my ears right now?", so the audible warning only plays when
/// it will stay private.
///
/// CoreAudio labels what a stream terminates in, so headphones can be asked about directly
/// rather than inferred from how the device is connected. Inferring would be wrong in both
/// directions: a USB headset and a pair of USB desk speakers share a transport type, as do
/// Bluetooth earbuds and a Bluetooth speaker.
final class OutputRoute {
    private let cacheSeconds: Double
    private var cached = false
    private var checkedAt = -Double.infinity

    init(cacheSeconds: Double = 1) {
        self.cacheSeconds = cacheSeconds
    }

    /// Cached briefly, because this is consulted on every audio buffer while you are in the red.
    var isHeadphones: Bool {
        let now = CACurrentMediaTime()
        if now - checkedAt < cacheSeconds { return cached }
        checkedAt = now
        cached = Self.detect()
        return cached
    }

    private static func detect() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return isHeadphones(device: device)
    }

    /// Takes the device rather than reading the default one so it can be checked against
    /// every attached device without changing which one the system is using.
    static func isHeadphones(device: AudioObjectID) -> Bool {
        if outputStreams(of: device).contains(where: { terminalType(of: $0) == headphonesTerminal }) {
            return true
        }
        // The built-in device keeps one stream for both the speakers and the jack, and
        // switches data source rather than relabelling the stream.
        return dataSource(of: device) == headphonesDataSource
    }

    private static let headphonesTerminal = UInt32(kAudioStreamTerminalTypeHeadphones)

    /// 'hdpn'. CoreAudio does not export the built-in device's data source values.
    private static let headphonesDataSource: UInt32 = 0x6864_706E

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func outputStreams(of device: AudioObjectID) -> [AudioObjectID] {
        var address = self.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var streams = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else { return [] }
        return streams
    }

    private static func terminalType(of stream: AudioObjectID) -> UInt32? {
        value(of: stream, kAudioStreamPropertyTerminalType)
    }

    private static func dataSource(of device: AudioObjectID) -> UInt32? {
        value(of: device, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
    }

    private static func value(
        of object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = self.address(selector, scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

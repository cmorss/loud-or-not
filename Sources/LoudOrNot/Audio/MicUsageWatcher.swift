import AppKit
import CoreAudio

/// Answers "is some other app listening to the microphone right now?" by walking CoreAudio's
/// process objects. No extra permission required, and it sees the mic itself rather than
/// guessing from a list of known meeting apps.
final class MicUsageWatcher {
    struct Usage: Equatable {
        var isActive: Bool
        var appName: String?

        static let inactive = Usage(isActive: false, appName: nil)
    }

    var onChange: ((Usage) -> Void)?
    private(set) var usage: Usage = .inactive

    private var timer: Timer?
    private var listener: AudioObjectPropertyListenerBlock?
    private let ownPID = getpid()

    func start() {
        guard timer == nil else { return }

        // IsRunningInput flips without the process list changing, so polling is the
        // workhorse; the list listener just makes newly launched apps register faster.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.poll() }
        }
        self.listener = listener
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )

        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let listener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
            )
            self.listener = nil
        }
        update(.inactive)
    }

    func poll() {
        var found: Usage = .inactive
        for object in Self.processObjectIDs() {
            guard Self.isRunningInput(object) else { continue }
            let pid = Self.pid(of: object)
            guard pid != ownPID, pid > 0 else { continue }
            found = Usage(isActive: true, appName: Self.displayName(pid: pid, object: object))
            break
        }
        update(found)
    }

    private func update(_ new: Usage) {
        guard new != usage else { return }
        usage = new
        onChange?(new)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = self.address(kAudioHardwarePropertyProcessObjectList)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return [] }
        return ids
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var address = self.address(kAudioProcessPropertyIsRunningInput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func pid(of object: AudioObjectID) -> pid_t {
        var address = self.address(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return -1 }
        return value
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = self.address(kAudioProcessPropertyBundleID)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var unmanaged: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = unmanaged?.takeRetainedValue() else { return nil }
        let string = value as String
        return string.isEmpty ? nil : string
    }

    private static func displayName(pid: pid_t, object: AudioObjectID) -> String? {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        guard let bundleID = bundleID(of: object) else { return nil }
        return bundleID.split(separator: ".").last.map(String.init)
    }
}

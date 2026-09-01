import Foundation

public struct AudioInputChoice: Equatable, Identifiable, Sendable {
    public let uid: String
    public let name: String
    public let isBuiltIn: Bool

    public var id: String { uid }

    public init(uid: String, name: String, isBuiltIn: Bool) {
        self.uid = uid
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public enum InputDeviceSelection {
    /// Picks the microphone to listen on: whatever you chose, otherwise the built-in one.
    ///
    /// Falling back to the built-in rather than to the system default input is the whole
    /// point. The system default follows your headset, and opening a Bluetooth headset's
    /// microphone drags the entire device into its low quality call mode, so merely
    /// launching this app would make your music and your meetings sound worse. The built-in
    /// microphone is also the better sensor for the question being asked, since it hears the
    /// room the way the person in it does rather than from an inch off your cheek.
    public static func resolve(
        preferredUID: String?,
        available: [AudioInputChoice]
    ) -> AudioInputChoice? {
        if let preferredUID, let chosen = available.first(where: { $0.uid == preferredUID }) {
            return chosen
        }
        return available.first(where: \.isBuiltIn) ?? available.first
    }
}

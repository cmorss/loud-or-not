import Testing
@testable import LoudOrNotCore

private let builtIn = AudioInputChoice(
    uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", isBuiltIn: true
)
private let headset = AudioInputChoice(
    uid: "B8-84-11-64-5C-6E:input", name: "OpenRun Pro 2 by Shokz", isBuiltIn: false
)
private let webcam = AudioInputChoice(
    uid: "AppleUSBAudioEngine:Logitech StreamCam", name: "Logitech StreamCam", isBuiltIn: false
)

@Test func defaultsToTheBuiltInMicrophoneRatherThanAHeadset() {
    // The headset is listed first on purpose: it is what the system default would hand us.
    let chosen = InputDeviceSelection.resolve(preferredUID: nil, available: [headset, webcam, builtIn])
    #expect(chosen == builtIn)
}

@Test func honoursAnExplicitChoice() {
    let chosen = InputDeviceSelection.resolve(
        preferredUID: webcam.uid, available: [headset, webcam, builtIn]
    )
    #expect(chosen == webcam)
}

@Test func fallsBackToBuiltInWhenTheChosenDeviceIsUnplugged() {
    let chosen = InputDeviceSelection.resolve(
        preferredUID: webcam.uid, available: [headset, builtIn]
    )
    #expect(chosen == builtIn)
}

@Test func usesWhateverExistsWhenThereIsNoBuiltInMicrophone() {
    let chosen = InputDeviceSelection.resolve(preferredUID: nil, available: [headset, webcam])
    #expect(chosen == headset)
}

@Test func copesWithNoInputDevicesAtAll() {
    #expect(InputDeviceSelection.resolve(preferredUID: builtIn.uid, available: []) == nil)
}

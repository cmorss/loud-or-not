import Testing
@testable import LoudOrNotCore

@Test func throttleAllowsTheFirstBeepImmediately() {
    var throttle = BeepThrottle(minimumIntervalSeconds: 3.5)
    #expect(throttle.shouldBeep(now: 100) == true)
}

@Test func throttleSwallowsBeepsInsideTheInterval() {
    var throttle = BeepThrottle(minimumIntervalSeconds: 3.5)
    #expect(throttle.shouldBeep(now: 100) == true)
    #expect(throttle.shouldBeep(now: 100.02) == false)
    #expect(throttle.shouldBeep(now: 102) == false)
    #expect(throttle.shouldBeep(now: 103.4) == false)
}

@Test func throttleAllowsAnotherBeepAfterTheInterval() {
    var throttle = BeepThrottle(minimumIntervalSeconds: 3.5)
    #expect(throttle.shouldBeep(now: 100) == true)
    #expect(throttle.shouldBeep(now: 103.5) == true)
    #expect(throttle.shouldBeep(now: 104) == false)
    #expect(throttle.shouldBeep(now: 107) == true)
}

@Test func resettingLetsTheNextBeepThroughStraightAway() {
    var throttle = BeepThrottle(minimumIntervalSeconds: 3.5)
    #expect(throttle.shouldBeep(now: 100) == true)
    throttle.reset()
    #expect(throttle.shouldBeep(now: 100.1) == true)
}

@Test func pipStartsAndEndsAtSilenceSoItDoesNotClick() {
    let samples = Tone.pip(frequency: 880, seconds: 0.09, sampleRate: 44_100, amplitude: 0.25)
    #expect(samples.count == 3969)
    #expect(abs(samples.first ?? 1) < 0.0001)
    #expect(abs(samples.last ?? 1) < 0.0001)
}

@Test func warningBeepStaysWithinRangeAndHasTwoPips() {
    let samples = Tone.warningBeep(sampleRate: 44_100)
    #expect(samples.allSatisfy { abs($0) <= 0.25 })

    // The gap between the pips should be genuinely silent.
    let gapStart = Int(0.11 * 44_100)
    #expect(samples[gapStart] == 0)
    #expect(samples.contains { abs($0) > 0.2 })
}

@Test func pipCopesWithDegenerateInput() {
    #expect(Tone.pip(frequency: 880, seconds: 0, sampleRate: 44_100, amplitude: 0.25).isEmpty)
    #expect(Tone.pip(frequency: 880, seconds: 0.09, sampleRate: 0, amplitude: 0.25).isEmpty)
}

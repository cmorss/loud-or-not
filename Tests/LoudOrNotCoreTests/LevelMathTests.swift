import Testing
@testable import LoudOrNotCore

@Test func intensityIsZeroAtWarnAndOneAtLoud() {
    #expect(LevelMath.intensity(forDB: -26, warnDB: -26, loudDB: -14) == 0)
    #expect(LevelMath.intensity(forDB: -14, warnDB: -26, loudDB: -14) == 1)
    #expect(abs(LevelMath.intensity(forDB: -20, warnDB: -26, loudDB: -14) - 0.5) < 0.001)
}

@Test func intensityClampsOutsideTheThresholds() {
    #expect(LevelMath.intensity(forDB: -60, warnDB: -26, loudDB: -14) == 0)
    #expect(LevelMath.intensity(forDB: 0, warnDB: -26, loudDB: -14) == 1)
}

@Test func pulseSpeedsUpWithIntensity() {
    #expect(LevelMath.pulseFrequency(intensity: 0) < LevelMath.pulseFrequency(intensity: 1))
}

@Test func silenceReadsAsTheFloor() {
    #expect(LevelMath.dBFS(rms: 0) == LevelMath.floorDB)
    #expect(abs(LevelMath.dBFS(rms: 1) - 0) < 0.001)
}

@Test func smootherIgnoresBriefNoiseButFollowsSustainedSpeech() {
    var cough = LoudnessSmoother()
    cough.add(instantDB: -10, deltaTime: 0.2)
    let afterCough = cough.valueDB

    var speech = LoudnessSmoother()
    for _ in 0..<15 {
        speech.add(instantDB: -10, deltaTime: 0.2)
    }

    #expect(afterCough < -40)
    #expect(speech.valueDB > -12)
}

@Test func smootherDecaysThroughSilence() {
    var smoother = LoudnessSmoother()
    for _ in 0..<15 { smoother.add(instantDB: -10, deltaTime: 0.2) }
    for _ in 0..<25 { smoother.add(instantDB: -70, deltaTime: 0.2) }
    #expect(smoother.valueDB < -60)
}

@Test func publishGateStaysQuietWhenTheLevelIsNotMoving() {
    var gate = LevelPublishGate(updatesPerSecond: 20, minimumChangeDB: 0.25)
    #expect(gate.shouldPublish(db: -80, now: 100) == true)

    // Silence sits at the floor forever, which is exactly when the app used to burn CPU.
    for step in 1...200 {
        #expect(gate.shouldPublish(db: -80, now: 100 + Double(step) * 0.023) == false)
    }
}

@Test func publishGateRateLimitsAChangingLevel() {
    var gate = LevelPublishGate(updatesPerSecond: 20, minimumChangeDB: 0.25)
    #expect(gate.shouldPublish(db: -40, now: 100) == true)
    // Moving, but sooner than the update interval allows.
    #expect(gate.shouldPublish(db: -30, now: 100.02) == false)
    #expect(gate.shouldPublish(db: -30, now: 100.06) == true)
}

@Test func publishGateIgnoresChangesTooSmallToSee() {
    var gate = LevelPublishGate(updatesPerSecond: 20, minimumChangeDB: 0.25)
    #expect(gate.shouldPublish(db: -40, now: 100) == true)
    #expect(gate.shouldPublish(db: -40.1, now: 101) == false)
    #expect(gate.shouldPublish(db: -40.3, now: 102) == true)
}

@Test func publishGateLetsSlowDriftThroughEventually() {
    var gate = LevelPublishGate(updatesPerSecond: 20, minimumChangeDB: 0.25)
    #expect(gate.shouldPublish(db: -40, now: 100) == true)
    // Each step is under the threshold, but they accumulate against the published value.
    #expect(gate.shouldPublish(db: -40.1, now: 101) == false)
    #expect(gate.shouldPublish(db: -40.2, now: 102) == false)
    #expect(gate.shouldPublish(db: -40.26, now: 103) == true)
}

@Test func hysteresisHoldsUntilTheLevelDropsBelowTheMargin() {
    var hysteresis = Hysteresis(releaseMarginDB: 2)
    #expect(hysteresis.update(db: -30, warnDB: -26) == false)
    #expect(hysteresis.update(db: -26, warnDB: -26) == true)
    #expect(hysteresis.update(db: -27, warnDB: -26) == true)
    #expect(hysteresis.update(db: -29, warnDB: -26) == false)
}

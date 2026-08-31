import LoudOrNotCore
import QuartzCore
import SwiftUI

/// Publishes the microphone level for the meter, and nothing else.
///
/// It is kept apart from `Coordinator` because the level changes with every audio buffer.
/// Anything observing the coordinator was being rebuilt at that rate, which meant the menu
/// bar item and every control in the panel were redrawn dozens of times a second to show a
/// number neither of them displays.
@MainActor
final class MeterLevel: ObservableObject {
    @Published private(set) var db: Double = LevelMath.floorDB

    private var gate = LevelPublishGate()

    func update(db: Double) {
        guard gate.shouldPublish(db: db, now: CACurrentMediaTime()) else { return }
        self.db = db
    }
}

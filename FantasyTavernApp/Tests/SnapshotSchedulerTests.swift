import XCTest
@testable import FantasyTavernApp

final class SnapshotSchedulerTests: XCTestCase {
    func test_fire_callsSnapshotOnlyIfDirty() {
        var calls = 0
        let scheduler = SnapshotScheduler(interval: 60) { calls += 1 }
        scheduler.markDirty()
        scheduler.fireForTesting()
        XCTAssertEqual(calls, 1)
        scheduler.fireForTesting()
        XCTAssertEqual(calls, 1, "Second fire without new dirty mark should not snapshot")
        scheduler.markDirty()
        scheduler.fireForTesting()
        XCTAssertEqual(calls, 2)
    }

    func test_isDirty_clearedAfterFire() {
        var calls = 0
        let scheduler = SnapshotScheduler(interval: 60) { calls += 1 }
        scheduler.markDirty()
        XCTAssertTrue(scheduler.isDirty)
        scheduler.fireForTesting()
        XCTAssertFalse(scheduler.isDirty)
    }
}

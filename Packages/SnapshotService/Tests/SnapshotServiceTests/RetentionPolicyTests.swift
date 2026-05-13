import XCTest
@testable import SnapshotService

final class RetentionPolicyTests: XCTestCase {
    private func d(hoursAgo: Double, from now: Date) -> Date {
        now.addingTimeInterval(-hoursAgo * 3600)
    }

    func test_keepEverythingWithin24h() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stamps = [d(hoursAgo: 0.1, from: now),
                      d(hoursAgo: 5,   from: now),
                      d(hoursAgo: 23,  from: now)]
        let decision = RetentionPolicy.decide(stamps: stamps, now: now)
        XCTAssertEqual(Set(decision.keep), Set(stamps))
        XCTAssertTrue(decision.prune.isEmpty)
    }

    func test_hourlyBucketing_betweenDay1And7() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Two stamps in the same hour, ~30h ago → keep newest, prune older
        let newer = d(hoursAgo: 30, from: now)
        let older = newer.addingTimeInterval(-10) // same hour bucket
        let decision = RetentionPolicy.decide(stamps: [newer, older], now: now)
        XCTAssertEqual(decision.keep, [newer])
        XCTAssertEqual(decision.prune, [older])
    }

    func test_dailyBucketing_betweenDay7And30() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Two stamps on the same day ~10 days ago → keep newer, prune older
        let newer = d(hoursAgo: 24*10 + 1, from: now)
        let older = newer.addingTimeInterval(-3600)
        let decision = RetentionPolicy.decide(stamps: [newer, older], now: now)
        XCTAssertEqual(decision.keep, [newer])
        XCTAssertEqual(decision.prune, [older])
    }

    func test_droppedAfter30Days() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ancient = d(hoursAgo: 24*40, from: now)
        let decision = RetentionPolicy.decide(stamps: [ancient], now: now)
        XCTAssertTrue(decision.keep.isEmpty)
        XCTAssertEqual(decision.prune, [ancient])
    }
}

import XCTest
@testable import FantasyTavernApp

final class TimelineGeometryTests: XCTestCase {
    func test_year_parsesPlainYear() {
        XCTAssertEqual(TimelineGeometry.year(fromDateString: "1452"), 1452)
    }
    func test_year_parsesNegative() {
        XCTAssertEqual(TimelineGeometry.year(fromDateString: "-1200"), -1200)
    }
    func test_year_parsesISODate() {
        XCTAssertEqual(TimelineGeometry.year(fromDateString: "1452-04-12"), 1452)
    }
    func test_year_parsesPrefixedLabel() {
        XCTAssertEqual(TimelineGeometry.year(fromDateString: "AE 802"), 802)
    }
    func test_year_emptyReturnsNil() {
        XCTAssertNil(TimelineGeometry.year(fromDateString: ""))
        XCTAssertNil(TimelineGeometry.year(fromDateString: "no digits"))
    }

    func test_tickStep_byGranularity() {
        XCTAssertEqual(TimelineGeometry.tickStep(.year), 1)
        XCTAssertEqual(TimelineGeometry.tickStep(.decade), 10)
        XCTAssertEqual(TimelineGeometry.tickStep(.century), 100)
    }

    func test_xPosition_normalizesWithinRange() {
        XCTAssertEqual(TimelineGeometry.x(forYear: 0, range: -100...100, width: 200), 100, accuracy: 0.001)
        XCTAssertEqual(TimelineGeometry.x(forYear: -100, range: -100...100, width: 200), 0, accuracy: 0.001)
        XCTAssertEqual(TimelineGeometry.x(forYear: 100, range: -100...100, width: 200), 200, accuracy: 0.001)
    }

    func test_yearAtPoint_inverse() {
        XCTAssertEqual(TimelineGeometry.year(atX: 100, range: -100...100, width: 200), 0)
        XCTAssertEqual(TimelineGeometry.year(atX: 0, range: -100...100, width: 200), -100)
    }

    func test_fittedGranularity_small_picksYear() {
        XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 5), .year)
    }
    func test_fittedGranularity_medium_picksDecade() {
        XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 80), .decade)
    }
    func test_fittedGranularity_large_picksCentury() {
        XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 5000), .century)
    }
    func test_fittedGranularity_zero_defaultsToDecade() {
        XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 0), .decade)
    }
}

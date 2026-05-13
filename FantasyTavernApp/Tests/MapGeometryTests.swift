import XCTest
@testable import FantasyTavernApp

final class MapGeometryTests: XCTestCase {
    func test_clampScale_floor() {
        XCTAssertEqual(MapGeometry.clamp(scale: 0.1), 0.5, accuracy: 0.0001)
    }
    func test_clampScale_ceiling() {
        XCTAssertEqual(MapGeometry.clamp(scale: 20), 8.0, accuracy: 0.0001)
    }
    func test_clampScale_passthrough() {
        XCTAssertEqual(MapGeometry.clamp(scale: 2.0), 2.0, accuracy: 0.0001)
    }
    func test_clampNormalized_inRange() {
        XCTAssertEqual(MapGeometry.clampNormalized(-0.5), 0.0)
        XCTAssertEqual(MapGeometry.clampNormalized(1.4), 1.0)
        XCTAssertEqual(MapGeometry.clampNormalized(0.3), 0.3)
    }
    func test_scaleStep_zoomsIn_atDeltaUp() {
        XCTAssertEqual(MapGeometry.scaleStep(current: 1.0, deltaY: 1.0), 1.2, accuracy: 0.0001)
    }
    func test_scaleStep_zoomsOut_atDeltaDown() {
        XCTAssertEqual(MapGeometry.scaleStep(current: 1.0, deltaY: -1.0), 1.0 / 1.2, accuracy: 0.0001)
    }
    func test_scaleStep_clampsAtCeiling() {
        XCTAssertEqual(MapGeometry.scaleStep(current: 8.0, deltaY: 1.0), 8.0, accuracy: 0.0001)
    }
}

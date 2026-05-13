import XCTest
import EntityModel
@testable import WorldStore

final class MapTests: XCTestCase {
    func test_mapDoc_codableRoundTrip() throws {
        let original = MapDoc(image: "overworld.png", pins: [
            MapPin(x: 0.42, y: 0.61, locationId: EntityID("silvermoon"), label: "Silvermoon"),
            MapPin(x: 0.10, y: 0.20, locationId: EntityID("ruins"),       label: nil),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MapDoc.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_mapPin_clampedAccessors() {
        let pin = MapPin(x: 1.5, y: -0.2, locationId: EntityID("a"), label: nil)
        XCTAssertEqual(pin.clampedX, 1.0)
        XCTAssertEqual(pin.clampedY, 0.0)
    }
}

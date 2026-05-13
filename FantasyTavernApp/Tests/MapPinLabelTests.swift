import XCTest
import EntityModel
import WorldStore
@testable import FantasyTavernApp

final class MapPinLabelTests: XCTestCase {
    func test_pinLabel_prefersExplicit() {
        let pin = MapPin(x: 0, y: 0, locationId: EntityID("silver"), label: "Silvermoon")
        XCTAssertEqual(MapView.displayLabel(for: pin, entities: []), "Silvermoon")
    }

    func test_pinLabel_fallsBackToEntityName() {
        let pin = MapPin(x: 0, y: 0, locationId: EntityID("silver"), label: nil)
        let entities = [Entity(id: EntityID("silver"), type: .location, name: "Silvermoon")]
        XCTAssertEqual(MapView.displayLabel(for: pin, entities: entities), "Silvermoon")
    }

    func test_pinLabel_fallsBackToIdWhenNoEntity() {
        let pin = MapPin(x: 0, y: 0, locationId: EntityID("ruins"), label: nil)
        XCTAssertEqual(MapView.displayLabel(for: pin, entities: []), "ruins")
    }
}

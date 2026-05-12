import XCTest
@testable import EntityModel

final class EntityTests: XCTestCase {
    func test_entity_equatable_byID() {
        let a = Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "x")
        let b = Entity(id: EntityID("lyra"), type: .character, name: "Lyra (renamed)", body: "y")
        XCTAssertEqual(a.id, b.id)
        XCTAssertNotEqual(a, b) // full equality differs because body differs
    }

    func test_entityID_isStringRawValue() {
        let id = EntityID("lyra-stormwind")
        XCTAssertEqual(id.rawValue, "lyra-stormwind")
    }

    func test_entityType_rawStrings() {
        XCTAssertEqual(EntityType.character.rawValue, "character")
        XCTAssertEqual(EntityType.location.rawValue, "location")
    }
}

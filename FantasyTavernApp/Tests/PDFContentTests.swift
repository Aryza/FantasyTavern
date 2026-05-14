import XCTest
import EntityModel
import WorldStore
@testable import FantasyTavernApp

final class PDFContentTests: XCTestCase {
    private func sampleWorld() -> World {
        World(name: "Aetheria", folder: URL(fileURLWithPath: "/tmp/world"), color: nil)
    }

    func test_entityDocument_includesNameAndBody() {
        let entity = Entity(id: EntityID("lyra"), type: .character, name: "Lyra Stormwind",
                            body: "Half-elven ranger from Silvermoon.")
        let str = PDFContent.entityDocument(entity).string
        XCTAssertTrue(str.contains("Lyra Stormwind"))
        XCTAssertTrue(str.contains("character"))
        XCTAssertTrue(str.contains("Half-elven ranger from Silvermoon."))
    }

    func test_worldDocument_groupsByType_andIncludesTitle() {
        let world = sampleWorld()
        let entities = [
            Entity(id: EntityID("lyra"),    type: .character, name: "Lyra",    body: "char body"),
            Entity(id: EntityID("magnus"),  type: .character, name: "Magnus",  body: "char body 2"),
            Entity(id: EntityID("silver"),  type: .location,  name: "Silver",  body: "loc body"),
        ]
        let str = PDFContent.worldDocument(world: world, entities: entities).string
        XCTAssertTrue(str.contains("Aetheria"))
        XCTAssertTrue(str.contains("Characters"))
        XCTAssertTrue(str.contains("Locations"))
        XCTAssertTrue(str.contains("Lyra"))
        XCTAssertTrue(str.contains("Magnus"))
        XCTAssertTrue(str.contains("Silver"))
        // characters section appears before locations
        let charIdx = str.range(of: "Characters")!.lowerBound
        let locIdx  = str.range(of: "Locations")!.lowerBound
        XCTAssertLessThan(charIdx, locIdx)
    }

    func test_worldDocument_skipsEmptyTypes() {
        let world = sampleWorld()
        let entities = [
            Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "x"),
        ]
        let str = PDFContent.worldDocument(world: world, entities: entities).string
        XCTAssertFalse(str.contains("Locations"))
        XCTAssertFalse(str.contains("Lore"))
    }
}

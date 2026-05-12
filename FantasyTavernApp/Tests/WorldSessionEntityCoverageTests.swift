import XCTest
import EntityModel
import WorldStore
import SchemaRegistry
@testable import FantasyTavernApp

final class WorldSessionEntityCoverageTests: XCTestCase {
    private func makeTempWorld() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try #"{"name":"Test"}"#.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
        return url
    }

    func test_createEntity_supportsAllSevenTypes() throws {
        let session = WorldSession()
        try session.openWorld(at: makeTempWorld())
        for type in EntityType.allCases {
            let entity = try session.createEntity(type: type, name: "Untitled \(type.rawValue)")
            XCTAssertEqual(entity.type, type)
        }
        XCTAssertEqual(session.store?.entities.count, EntityType.allCases.count)
    }

    func test_session_exposesSchemaFromStore() throws {
        let session = WorldSession()
        try session.openWorld(at: makeTempWorld())
        XCTAssertEqual(session.fields(for: .character).map(\.key),
                       ["race", "age", "alignment", "status"])
    }

    func test_createCharacter_stillWorks_callsCreateEntity() throws {
        let session = WorldSession()
        try session.openWorld(at: makeTempWorld())
        let e = try session.createCharacter(name: "Lyra")
        XCTAssertEqual(e.type, .character)
    }
}

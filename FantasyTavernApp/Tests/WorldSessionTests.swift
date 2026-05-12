import XCTest
import EntityModel
import WorldStore
@testable import FantasyTavernApp

final class WorldSessionTests: XCTestCase {
    private func makeTempWorld() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try #"{"name":"Test"}"#.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
        return url
    }

    func test_openWorld_loadsZeroEntities() throws {
        let session = WorldSession()
        let url = try makeTempWorld()
        try session.openWorld(at: url)
        XCTAssertEqual(session.store?.world.name, "Test")
        XCTAssertEqual(session.store?.entities.count, 0)
    }

    func test_createCharacter_appearsInEntities() throws {
        let session = WorldSession()
        try session.openWorld(at: makeTempWorld())
        let created = try session.createCharacter(name: "Lyra")
        XCTAssertEqual(created.id.rawValue, "lyra")
        XCTAssertEqual(session.store?.entities.count, 1)
    }

    func test_backlinks_updateAfterSave() throws {
        let session = WorldSession()
        try session.openWorld(at: makeTempWorld())
        let a = try session.createCharacter(name: "A")
        let b = try session.createCharacter(name: "B")
        var aEdited = a
        aEdited.body = "see [[B]]"
        try session.save(aEdited)
        XCTAssertEqual(session.backlinks(to: b.id), [a.id])
    }
}

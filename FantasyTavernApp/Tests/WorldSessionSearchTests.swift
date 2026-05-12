import XCTest
import EntityModel
import SearchIndex
@testable import FantasyTavernApp

final class WorldSessionSearchTests: XCTestCase {
    private func makeWorld() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try #"{"name":"T"}"#.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
        return url
    }

    func test_search_returnsCreatedEntity() throws {
        let s = WorldSession()
        try s.openWorld(at: makeWorld())
        let e = try s.createEntity(type: .character, name: "Lyra Stormwind")
        XCTAssertEqual(s.search("lyra").map(\.id), [e.id])
    }

    func test_search_emptyBeforeOpen() {
        let s = WorldSession()
        XCTAssertTrue(s.search("anything").isEmpty)
    }

    func test_save_updatesIndex() throws {
        let s = WorldSession()
        try s.openWorld(at: makeWorld())
        let e = try s.createEntity(type: .character, name: "Lyra")
        var renamed = e
        renamed.name = "Lyra Stormwind"
        try s.save(renamed)
        XCTAssertEqual(s.search("stormwind").map(\.id), [e.id])
    }
}

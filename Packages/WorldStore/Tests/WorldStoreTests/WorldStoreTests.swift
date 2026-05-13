import XCTest
import EntityModel
import SchemaRegistry
@testable import WorldStore

final class WorldStoreTests: XCTestCase {
    var tmpRoot: URL!

    override func setUpWithError() throws {
        tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpRoot) }

    private func copyFixtureWorld() throws -> URL {
        let src = Bundle.module.url(forResource: "Aetheria", withExtension: nil, subdirectory: "Fixtures")!
        let dst = tmpRoot.appendingPathComponent("Aetheria")
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    func test_open_loadsAllCharacters() throws {
        let url = try copyFixtureWorld()
        let store = try WorldStore.open(url)
        XCTAssertEqual(store.world.name, "Aetheria")
        XCTAssertEqual(store.entities.count, 2)
        XCTAssertEqual(Set(store.entities.map(\.id.rawValue)), ["lyra-stormwind", "magnus-blackthorn"])
    }

    func test_save_writesEntityFileAndUpdatesEntities() throws {
        let url = try copyFixtureWorld()
        let store = try WorldStore.open(url)
        guard var lyra = store.entities.first(where: { $0.id.rawValue == "lyra-stormwind" }) else {
            return XCTFail("missing lyra")
        }
        lyra.body = "Updated body"
        try store.save(lyra)

        let reread = try WorldStore.open(url)
        let updated = reread.entities.first(where: { $0.id.rawValue == "lyra-stormwind" })
        XCTAssertEqual(updated?.body, "Updated body")
    }

    func test_create_writesNewCharacterFile() throws {
        let url = try copyFixtureWorld()
        let store = try WorldStore.open(url)
        let created = try store.create(name: "Sister Aelith", type: .character)
        XCTAssertEqual(created.id.rawValue, "sister-aelith")

        let reread = try WorldStore.open(url)
        XCTAssertTrue(reread.entities.contains(where: { $0.id == created.id }))
    }

    func test_open_loadsSchemaWithDefaults() throws {
        let url = try copyFixtureWorld()
        let store = try WorldStore.open(url)
        XCTAssertEqual(store.schema.fields(for: .character).map(\.key),
                       ["race", "age", "alignment", "status"])
    }

    func test_open_appliesSchemaOverridesFromWorldJSON() throws {
        let url = try copyFixtureWorld()
        let overrideJSON = """
        {
          "name": "Aetheria",
          "schemaOverrides": {
            "character": [
              { "key": "house", "label": "House", "type": "string" }
            ]
          }
        }
        """
        try overrideJSON.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
        let store = try WorldStore.open(url)
        XCTAssertEqual(store.schema.fields(for: .character).map(\.key), ["house"])
    }

    func test_open_loadsMaps() throws {
        let url = try copyFixtureWorld()
        let mapsDir = url.appendingPathComponent("maps")
        try FileManager.default.createDirectory(at: mapsDir, withIntermediateDirectories: true)
        try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
        let store = try WorldStore.open(url)
        XCTAssertEqual(store.mapNames, ["overworld"])
    }

    func test_open_loadsCalendar() throws {
        let url = try copyFixtureWorld()
        let json = """
        {
          "name": "Aetheria",
          "calendar": {
            "yearZeroLabel": "AE",
            "eras": [{ "id":"first-age", "name":"First Age", "start":-1000, "end":0 }]
          }
        }
        """
        try json.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
        let store = try WorldStore.open(url)
        XCTAssertEqual(store.calendar.yearZeroLabel, "AE")
        XCTAssertEqual(store.calendar.eras.map(\.id), ["first-age"])
    }

    func test_saveMap_roundTrip() throws {
        let url = try copyFixtureWorld()
        let mapsDir = url.appendingPathComponent("maps")
        try FileManager.default.createDirectory(at: mapsDir, withIntermediateDirectories: true)
        try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
        let store = try WorldStore.open(url)
        var doc = try store.loadMap(named: "overworld")
        doc.layers[0].pins.append(MapPin(x: 0.3, y: 0.4, locationId: EntityID("ruins"), label: nil))
        try store.saveMap(doc, name: "overworld")
        let reread = try store.loadMap(named: "overworld")
        XCTAssertEqual(reread.allPins.count, 1)
    }
}

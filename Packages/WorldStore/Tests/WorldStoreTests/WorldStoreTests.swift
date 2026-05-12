import XCTest
import EntityModel
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
}

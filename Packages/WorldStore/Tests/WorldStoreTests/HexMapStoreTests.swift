import XCTest
import EntityModel
@testable import WorldStore

final class HexMapStoreTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_listNames_findsFiles() throws {
        let dir = tmp.appendingPathComponent("hexmaps")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("overworld.json"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("dungeon.json"))
        try Data("nope".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(Set(HexMapStore.listNames(in: tmp)), Set(["overworld", "dungeon"]))
    }

    func test_save_thenLoad_roundTrip() throws {
        var doc = HexMapDoc.make(cols: 4, rows: 3)
        doc.setTerrain("forest", col: 1, row: 1)
        try HexMapStore.save(doc, name: "overworld", in: tmp)
        let reread = try HexMapStore.load(name: "overworld", in: tmp)
        XCTAssertEqual(reread, doc)
    }

    func test_load_missing_throws() {
        XCTAssertThrowsError(try HexMapStore.load(name: "nope", in: tmp))
    }
}

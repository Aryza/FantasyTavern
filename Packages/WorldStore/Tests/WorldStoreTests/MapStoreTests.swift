import XCTest
import EntityModel
@testable import WorldStore

final class MapStoreTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("maps"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_listNames_findsImages() throws {
        let mapsDir = tmp.appendingPathComponent("maps")
        try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
        try Data([0]).write(to: mapsDir.appendingPathComponent("east.jpg"))
        try Data([0]).write(to: mapsDir.appendingPathComponent("notes.txt"))
        let names = MapStore.listNames(in: tmp)
        XCTAssertEqual(Set(names), ["overworld", "east"])
    }

    func test_load_returnsEmptyPinsWhenJSONMissing() throws {
        let mapsDir = tmp.appendingPathComponent("maps")
        try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
        let doc = try MapStore.load(name: "overworld", in: tmp)
        XCTAssertEqual(doc.image, "overworld.png")
        XCTAssertEqual(doc.pins, [])
    }

    func test_load_readsPinsFromJSON() throws {
        let mapsDir = tmp.appendingPathComponent("maps")
        try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
        let json = """
        { "image":"overworld.png", "pins":[{"x":0.5,"y":0.5,"locationId":"silvermoon","label":"Silvermoon"}] }
        """
        try json.write(to: mapsDir.appendingPathComponent("overworld.json"),
                       atomically: true, encoding: .utf8)
        let doc = try MapStore.load(name: "overworld", in: tmp)
        XCTAssertEqual(doc.pins.count, 1)
        XCTAssertEqual(doc.pins.first?.locationId.rawValue, "silvermoon")
    }

    func test_save_writesJSONAtomically() throws {
        let mapsDir = tmp.appendingPathComponent("maps")
        try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
        var doc = MapDoc(image: "overworld.png")
        doc.pins.append(MapPin(x: 0.2, y: 0.3, locationId: EntityID("ruins"), label: nil))
        try MapStore.save(doc, name: "overworld", in: tmp)
        let reread = try MapStore.load(name: "overworld", in: tmp)
        XCTAssertEqual(reread, doc)
    }

    func test_load_missingImage_throws() {
        XCTAssertThrowsError(try MapStore.load(name: "nope", in: tmp))
    }
}

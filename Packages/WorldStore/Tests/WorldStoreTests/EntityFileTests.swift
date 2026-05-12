import XCTest
import EntityModel
@testable import WorldStore

final class EntityFileTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_writeThenRead_roundTrip() throws {
        let entity = Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "Hello [[Silvermoon]]")
        let url = tmp.appendingPathComponent("lyra.md")
        try EntityFile.write(entity, to: url)
        let read = try EntityFile.read(from: url, fallbackType: .character)
        XCTAssertEqual(read.id, entity.id)
        XCTAssertEqual(read.body, entity.body)
    }

    func test_write_isAtomic_noPartialFile() throws {
        let entity = Entity(id: EntityID("a"), type: .character, name: "A", body: "x")
        let url = tmp.appendingPathComponent("a.md")
        try EntityFile.write(entity, to: url)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
        // only the final file should remain — no .tmp-* leftovers
        XCTAssertEqual(siblings, ["a.md"])
    }

    func test_read_missingFrontMatter_throws() throws {
        let url = tmp.appendingPathComponent("bad.md")
        try "just body".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try EntityFile.read(from: url, fallbackType: .character))
    }
}

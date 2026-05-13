import XCTest
import EntityModel
import WorldStore
@testable import FantasyTavernApp

final class ExportServiceTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_writeEntityMarkdown() throws {
        let entity = Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "Hello")
        let target = tmp.appendingPathComponent("lyra.md")
        try ExportService.writeEntity(entity, to: target)
        let text = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(text.contains("name: Lyra"))
        XCTAssertTrue(text.contains("Hello"))
    }

    func test_zipFolder_roundTrip() throws {
        let src = tmp.appendingPathComponent("characters")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "x".write(to: src.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let zip = tmp.appendingPathComponent("characters.zip")
        try ExportService.zipFolder(src, to: zip, exclude: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
    }
}

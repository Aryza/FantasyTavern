import XCTest
@testable import SnapshotService

final class ZipTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_createAndExtract_roundTrip() throws {
        let src = tmp.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "world".write(to: src.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let archive = tmp.appendingPathComponent("out.zip")
        try Zip.create(folder: src, to: archive, exclude: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

        let dest = tmp.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Zip.extract(archive: archive, to: dest)
        let aText = try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(aText, "hello")
    }

    func test_create_excludesGlob() throws {
        let src = tmp.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("keep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: src.appendingPathComponent(".fantasytavern/snapshots"), withIntermediateDirectories: true)
        try "x".write(to: src.appendingPathComponent("keep/y.txt"), atomically: true, encoding: .utf8)
        try "secret".write(to: src.appendingPathComponent(".fantasytavern/snapshots/old.zip"), atomically: true, encoding: .utf8)

        let archive = tmp.appendingPathComponent("out.zip")
        try Zip.create(folder: src, to: archive, exclude: [".fantasytavern/*"])

        let dest = tmp.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Zip.extract(archive: archive, to: dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("keep/y.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".fantasytavern/snapshots/old.zip").path))
    }

    func test_extract_missingArchive_throws() {
        let missing = tmp.appendingPathComponent("nope.zip")
        let dest = tmp.appendingPathComponent("dest")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Zip.extract(archive: missing, to: dest))
    }
}

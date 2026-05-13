import XCTest
@testable import SnapshotService

final class SnapshotServiceTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeWorld() throws -> URL {
        let w = tmp.appendingPathComponent("world")
        try FileManager.default.createDirectory(at: w.appendingPathComponent("characters"), withIntermediateDirectories: true)
        try "hello".write(to: w.appendingPathComponent("characters/lyra.md"), atomically: true, encoding: .utf8)
        return w
    }

    func test_snapshot_writesArchive_andListed() throws {
        let world = try makeWorld()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try SnapshotService.snapshot(world: world, now: date)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let listed = SnapshotService.list(in: world)
        XCTAssertEqual(listed.map(\.url), [url])
    }

    func test_snapshot_excludesDotFantasytavern() throws {
        let world = try makeWorld()
        let dotDir = world.appendingPathComponent(".fantasytavern/snapshots")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        try "old".write(to: dotDir.appendingPathComponent("old.zip"), atomically: true, encoding: .utf8)

        let url = try SnapshotService.snapshot(world: world)
        let dest = tmp.appendingPathComponent("extract")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Zip.extract(archive: url, to: dest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".fantasytavern/snapshots/old.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("characters/lyra.md").path))
    }

    func test_restore_archivesCurrentAndReplaces() throws {
        let world = try makeWorld()
        let snap = try SnapshotService.snapshot(world: world)
        // Modify world after snapshot
        try "changed".write(to: world.appendingPathComponent("characters/lyra.md"), atomically: true, encoding: .utf8)
        try SnapshotService.restore(snapshot: snap, world: world)
        let after = try String(contentsOf: world.appendingPathComponent("characters/lyra.md"), encoding: .utf8)
        XCTAssertEqual(after, "hello")
        let listed = SnapshotService.list(in: world)
        XCTAssertTrue(listed.contains { $0.url.lastPathComponent.hasPrefix("pre-restore-") })
    }

    func test_prune_removesAccordingToPolicy() throws {
        let world = try makeWorld()
        let dir = world.appendingPathComponent(".fantasytavern/snapshots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Plant fake-old file
        let oldURL = dir.appendingPathComponent("2020-01-01T00-00-00Z.zip")
        try Data().write(to: oldURL)
        try SnapshotService.prune(world: world, now: Date())
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
    }
}

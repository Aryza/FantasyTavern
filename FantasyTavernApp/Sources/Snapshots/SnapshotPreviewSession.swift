import Foundation
import Observation
import EntityModel
import WorldStore
import SnapshotService

@Observable
final class SnapshotPreviewSession {
    private(set) var store: WorldStore?
    let archiveName: String
    private let tempFolder: URL

    init(snapshot url: URL) throws {
        self.archiveName = url.lastPathComponent
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ft-snapshot-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.tempFolder = tmp
        try Zip.extract(archive: url, to: tmp)
        self.store = try WorldStore.open(tmp)
    }

    func close() {
        try? FileManager.default.removeItem(at: tempFolder)
        store = nil
    }

    deinit { close() }
}

import Foundation
import EntityModel
import WorldStore
import SnapshotService

enum ExportService {
    static func writeEntity(_ entity: Entity, to target: URL) throws {
        let serialized = try FrontMatter.serialize(entity)
        try serialized.data(using: .utf8)!.write(to: target, options: .atomic)
    }

    static func zipFolder(_ folder: URL, to target: URL, exclude: [String] = []) throws {
        try Zip.create(folder: folder, to: target, exclude: exclude)
    }
}

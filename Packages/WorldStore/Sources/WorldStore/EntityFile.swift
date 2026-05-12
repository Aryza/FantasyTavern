import Foundation
import EntityModel

public enum EntityFileError: Error {
    case readFailed(URL, underlying: Error)
    case writeFailed(URL, underlying: Error)
}

public enum EntityFile {
    public static func read(from url: URL, fallbackType: EntityType) throws -> Entity {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw EntityFileError.readFailed(url, underlying: error) }
        let parsed = try FrontMatter.parse(text)
        return parsed.entity
    }

    public static func write(_ entity: Entity, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: String
        do { payload = try FrontMatter.serialize(entity) }
        catch { throw EntityFileError.writeFailed(url, underlying: error) }

        let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try payload.data(using: .utf8)!.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw EntityFileError.writeFailed(url, underlying: error)
        }
    }
}

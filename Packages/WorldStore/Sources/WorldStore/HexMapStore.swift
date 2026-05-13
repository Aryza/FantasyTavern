import Foundation

public enum HexMapStoreError: Error {
    case missing(String)
}

public enum HexMapStore {
    public static func listNames(in worldFolder: URL) -> [String] {
        let dir = worldFolder.appendingPathComponent("hexmaps")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public static func load(name: String, in worldFolder: URL) throws -> HexMapDoc {
        let url = worldFolder.appendingPathComponent("hexmaps").appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else {
            throw HexMapStoreError.missing(name)
        }
        return try JSONDecoder().decode(HexMapDoc.self, from: data)
    }

    public static func save(_ doc: HexMapDoc, name: String, in worldFolder: URL) throws {
        let dir = worldFolder.appendingPathComponent("hexmaps")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("\(name).json")
        let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(doc)
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: target)
        }
    }
}

import Foundation
import EntityModel

public enum MapStoreError: Error {
    case imageNotFound(String)
}

public enum MapStore {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

    public static func listNames(in worldFolder: URL) -> [String] {
        let dir = worldFolder.appendingPathComponent("maps")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        let names = files.compactMap { url -> String? in
            imageExtensions.contains(url.pathExtension.lowercased())
                ? url.deletingPathExtension().lastPathComponent
                : nil
        }
        return names.sorted()
    }

    public static func load(name: String, in worldFolder: URL) throws -> MapDoc {
        let dir = worldFolder.appendingPathComponent("maps")
        guard let imageFile = findImage(named: name, in: dir) else {
            throw MapStoreError.imageNotFound(name)
        }
        let jsonURL = dir.appendingPathComponent("\(name).json")
        if let data = try? Data(contentsOf: jsonURL) {
            var doc = try JSONDecoder().decode(MapDoc.self, from: data)
            // ensure the stored image filename matches the actual one on disk
            doc.image = imageFile.lastPathComponent
            return doc
        }
        return MapDoc(image: imageFile.lastPathComponent)
    }

    public static func save(_ doc: MapDoc, name: String, in worldFolder: URL) throws {
        let dir = worldFolder.appendingPathComponent("maps")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(doc)
        let target = dir.appendingPathComponent("\(name).json")
        let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: target)
        }
    }

    private static func findImage(named name: String, in dir: URL) -> URL? {
        for ext in imageExtensions {
            let candidate = dir.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

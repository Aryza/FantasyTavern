import Foundation
import EntityModel

public struct World: Equatable, Sendable {
    public var name: String
    public var folder: URL
    public var color: String?
}

public final class WorldStore {
    public private(set) var world: World
    public private(set) var entities: [Entity]

    private init(world: World, entities: [Entity]) {
        self.world = world
        self.entities = entities
    }

    public static func open(_ folder: URL) throws -> WorldStore {
        let worldJSON = folder.appendingPathComponent("world.json")
        let name: String
        let color: String?
        if let data = try? Data(contentsOf: worldJSON),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            name = (obj["name"] as? String) ?? folder.lastPathComponent
            color = obj["color"] as? String
        } else {
            name = folder.lastPathComponent
            color = nil
        }

        var loaded: [Entity] = []
        for type in EntityType.allCases {
            let dir = folder.appendingPathComponent(type.folderName)
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "md" {
                do {
                    let entity = try EntityFile.read(from: file, fallbackType: type)
                    loaded.append(entity)
                } catch {
                    print("WorldStore: skip \(file.lastPathComponent): \(error)")
                }
            }
        }

        let world = World(name: name, folder: folder, color: color)
        return WorldStore(world: world, entities: loaded.sorted { $0.name < $1.name })
    }

    public func save(_ entity: Entity) throws {
        var stored = entity
        stored.updated = Date()
        let url = path(for: stored)
        try EntityFile.write(stored, to: url)
        if let idx = entities.firstIndex(where: { $0.id == stored.id }) {
            entities[idx] = stored
        } else {
            entities.append(stored)
            entities.sort { $0.name < $1.name }
        }
    }

    @discardableResult
    public func create(name: String, type: EntityType) throws -> Entity {
        let slug = uniqueSlug(for: name, type: type)
        let entity = Entity(id: EntityID(slug), type: type, name: name)
        try save(entity)
        return entity
    }

    public func entities(of type: EntityType) -> [Entity] {
        entities.filter { $0.type == type }
    }

    public func path(for entity: Entity) -> URL {
        world.folder
            .appendingPathComponent(entity.type.folderName)
            .appendingPathComponent("\(entity.id.rawValue).md")
    }

    private func uniqueSlug(for name: String, type: EntityType) -> String {
        let base = Slug.make(name)
        let existing = Set(entities(of: type).map(\.id.rawValue))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}

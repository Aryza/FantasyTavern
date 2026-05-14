import Foundation
import Observation
import EntityModel
import SchemaRegistry

public struct World: Equatable, Sendable {
    public var name: String
    public var folder: URL
    public var color: String?

    public init(name: String, folder: URL, color: String? = nil) {
        self.name = name
        self.folder = folder
        self.color = color
    }
}

@Observable
public final class WorldStore {
    public private(set) var world: World
    public private(set) var entities: [Entity]
    public private(set) var schema: Schema
    public private(set) var mapNames: [String]
    public private(set) var hexMapNames: [String]
    public private(set) var calendar: WorldCalendar

    private init(world: World, entities: [Entity], schema: Schema,
                 mapNames: [String], hexMapNames: [String], calendar: WorldCalendar) {
        self.world = world
        self.entities = entities
        self.schema = schema
        self.mapNames = mapNames
        self.hexMapNames = hexMapNames
        self.calendar = calendar
    }

    public static func open(_ folder: URL) throws -> WorldStore {
        let worldJSON = folder.appendingPathComponent("world.json")
        let worldData: Data? = try? Data(contentsOf: worldJSON)

        let name: String
        let color: String?
        if let data = worldData,
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

        let schema = SchemaLoader.load(overridesJSON: worldData)
        let calendar = WorldCalendar.load(from: worldData)
        let mapNames = MapStore.listNames(in: folder)
        let hexMapNames = HexMapStore.listNames(in: folder)
        let world = World(name: name, folder: folder, color: color)
        return WorldStore(
            world: world,
            entities: loaded.sorted { $0.name < $1.name },
            schema: schema,
            mapNames: mapNames,
            hexMapNames: hexMapNames,
            calendar: calendar
        )
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

    public func loadMap(named name: String) throws -> MapDoc {
        try MapStore.load(name: name, in: world.folder)
    }

    public func saveMap(_ doc: MapDoc, name: String) throws {
        try MapStore.save(doc, name: name, in: world.folder)
        if !mapNames.contains(name) {
            mapNames.append(name)
            mapNames.sort()
        }
    }

    public func reloadMapNames() {
        mapNames = MapStore.listNames(in: world.folder)
    }

    public func loadHexMap(named name: String) throws -> HexMapDoc {
        try HexMapStore.load(name: name, in: world.folder)
    }

    public func saveHexMap(_ doc: HexMapDoc, name: String) throws {
        try HexMapStore.save(doc, name: name, in: world.folder)
        if !hexMapNames.contains(name) {
            hexMapNames.append(name)
            hexMapNames.sort()
        }
    }

    public func reloadHexMapNames() {
        hexMapNames = HexMapStore.listNames(in: world.folder)
    }
}

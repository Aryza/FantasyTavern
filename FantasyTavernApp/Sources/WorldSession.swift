import Foundation
import Observation
import EntityModel
import WorldStore
import WikiLinks
import SchemaRegistry

@Observable
public final class WorldSession {
    public var store: WorldStore?
    public private(set) var backlinkIndex = BacklinkIndex(entities: [])

    public init() {}

    public func openWorld(at url: URL) throws {
        let store = try WorldStore.open(url)
        self.store = store
        rebuildLinks()
    }

    @discardableResult
    public func createEntity(type: EntityType, name: String) throws -> Entity {
        guard let store else { throw SessionError.noWorldOpen }
        let entity = try store.create(name: name, type: type)
        rebuildLinks()
        return entity
    }

    @discardableResult
    public func createCharacter(name: String) throws -> Entity {
        try createEntity(type: .character, name: name)
    }

    public func save(_ entity: Entity) throws {
        guard let store else { throw SessionError.noWorldOpen }
        try store.save(entity)
        rebuildLinks()
    }

    public func backlinks(to target: EntityID) -> [EntityID] {
        backlinkIndex.sources(linkingTo: target)
    }

    public func fields(for type: EntityType) -> [FieldDefinition] {
        store?.schema.fields(for: type) ?? []
    }

    private func rebuildLinks() {
        backlinkIndex = BacklinkIndex(entities: store?.entities ?? [])
    }

    public enum SessionError: Error { case noWorldOpen }
}

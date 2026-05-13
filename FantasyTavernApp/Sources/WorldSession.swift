import Foundation
import Observation
import EntityModel
import WorldStore
import WikiLinks
import SchemaRegistry
import SearchIndex

@Observable
public final class WorldSession {
    public var store: WorldStore?
    public private(set) var backlinkIndex = BacklinkIndex(entities: [])
    public private(set) var searchIndex = SearchIndex()

    private var watcher: FolderWatcher?

    public init() {}

    public func openWorld(at url: URL) throws {
        let store = try WorldStore.open(url)
        self.store = store
        rebuildLinks()
        rebuildSearch()
        startWatching(url: url)
    }

    @discardableResult
    public func createEntity(type: EntityType, name: String) throws -> Entity {
        guard let store else { throw SessionError.noWorldOpen }
        let entity = try store.create(name: name, type: type)
        rebuildLinks()
        searchIndex.upsert(entity)
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
        if let updated = store.entities.first(where: { $0.id == entity.id }) {
            searchIndex.upsert(updated)
        } else {
            searchIndex.upsert(entity)
        }
    }

    public func backlinks(to target: EntityID) -> [EntityID] {
        backlinkIndex.sources(linkingTo: target)
    }

    public func fields(for type: EntityType) -> [FieldDefinition] {
        store?.schema.fields(for: type) ?? []
    }

    public func search(_ query: String) -> [SearchHit] {
        searchIndex.query(query)
    }

    // MARK: - watcher

    private func startWatching(url: URL) {
        watcher?.stop()
        let w = FolderWatcher(url: url, debounce: 0.5) { [weak self] _ in
            DispatchQueue.main.async { self?.reloadFromDisk(url: url) }
        }
        do {
            try w.start()
            watcher = w
        } catch {
            print("WorldSession: watcher failed: \(error)")
            watcher = nil
        }
    }

    private func reloadFromDisk(url: URL) {
        guard let newStore = try? WorldStore.open(url) else { return }
        store = newStore
        rebuildLinks()
        rebuildSearch()
    }

    private func rebuildLinks() {
        backlinkIndex = BacklinkIndex(entities: store?.entities ?? [])
    }

    private func rebuildSearch() {
        searchIndex.build(from: store?.entities ?? [])
    }

    public enum SessionError: Error { case noWorldOpen }
}

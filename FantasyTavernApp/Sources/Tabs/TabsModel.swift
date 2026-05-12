import Foundation
import Observation
import EntityModel

@Observable
public final class TabsModel {
    public private(set) var openTabs: [EntityID] = []
    public var selected: EntityID?
    public private(set) var recents: [EntityID] = []
    private let recentsCap = 10

    public init() {}

    public func open(_ id: EntityID) {
        if !openTabs.contains(id) { openTabs.append(id) }
        selected = id
        pushRecent(id)
    }

    public func close(_ id: EntityID) {
        guard let idx = openTabs.firstIndex(of: id) else { return }
        openTabs.remove(at: idx)
        if selected == id {
            if openTabs.isEmpty { selected = nil }
            else { selected = openTabs[min(idx, openTabs.count - 1)] }
        }
    }

    private func pushRecent(_ id: EntityID) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > recentsCap { recents.removeLast(recents.count - recentsCap) }
    }
}

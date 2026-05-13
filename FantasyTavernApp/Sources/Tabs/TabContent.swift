import Foundation
import EntityModel

public enum TabContent: Hashable, Sendable {
    case entity(EntityID)
    case timeline
    case map(String)
    case hexMap(String)

    public var entityID: EntityID? {
        if case .entity(let id) = self { return id } else { return nil }
    }
}

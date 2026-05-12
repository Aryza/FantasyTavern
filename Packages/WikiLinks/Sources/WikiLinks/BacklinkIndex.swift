import Foundation
import EntityModel

public struct BacklinkIndex {
    private let incoming: [EntityID: [EntityID]]

    public init(entities: [Entity]) {
        let resolver = WikiLinkResolver(entities: entities)
        var map: [EntityID: Set<EntityID>] = [:]
        for source in entities {
            for match in WikiLinkParser.findLinks(in: source.body) {
                guard let target = resolver.resolve(name: match.name) else { continue }
                map[target, default: []].insert(source.id)
            }
        }
        self.incoming = map.mapValues { Array($0).sorted { $0.rawValue < $1.rawValue } }
    }

    public func sources(linkingTo target: EntityID) -> [EntityID] {
        incoming[target] ?? []
    }
}

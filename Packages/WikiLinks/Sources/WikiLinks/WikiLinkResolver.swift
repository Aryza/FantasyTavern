import Foundation
import EntityModel

public struct WikiLinkResolver {
    private let nameToID: [String: EntityID]

    public init(entities: [Entity]) {
        var map: [String: EntityID] = [:]
        for e in entities { map[Self.normalize(e.name)] = e.id }
        self.nameToID = map
    }

    public func resolve(name: String) -> EntityID? {
        nameToID[Self.normalize(name)]
    }

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let collapsed = lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed
    }
}

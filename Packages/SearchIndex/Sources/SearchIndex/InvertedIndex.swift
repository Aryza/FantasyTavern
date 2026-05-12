import Foundation
import EntityModel

public struct InvertedIndex: Equatable {
    private var termToIDs: [String: Set<EntityID>] = [:]
    private var idToTerms: [EntityID: Set<String>] = [:]

    public init() {}

    public mutating func add(_ terms: [String], for id: EntityID) {
        let setOfTerms = Set(terms)
        for term in setOfTerms {
            termToIDs[term, default: []].insert(id)
        }
        idToTerms[id, default: []].formUnion(setOfTerms)
    }

    public mutating func remove(_ id: EntityID) {
        guard let terms = idToTerms.removeValue(forKey: id) else { return }
        for term in terms {
            termToIDs[term]?.remove(id)
            if termToIDs[term]?.isEmpty == true { termToIDs.removeValue(forKey: term) }
        }
    }

    public mutating func replace(_ id: EntityID, withTerms terms: [String]) {
        remove(id)
        add(terms, for: id)
    }

    /// All entity ids whose term set contains a term that starts with `prefix`.
    public func ids(matchingTermPrefix prefix: String) -> Set<EntityID> {
        guard !prefix.isEmpty else { return Set(idToTerms.keys) }
        var result: Set<EntityID> = []
        for (term, ids) in termToIDs where term.hasPrefix(prefix) {
            result.formUnion(ids)
        }
        return result
    }
}

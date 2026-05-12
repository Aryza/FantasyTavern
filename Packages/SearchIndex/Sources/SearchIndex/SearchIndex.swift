import Foundation
import EntityModel

public struct SearchHit: Equatable {
    public let id: EntityID
    public let type: EntityType
    public let name: String
    public let score: Int

    public init(id: EntityID, type: EntityType, name: String, score: Int) {
        self.id = id
        self.type = type
        self.name = name
        self.score = score
    }
}

/// In-memory index over all entities of one world.
public struct SearchIndex {
    // entityID -> snapshot of indexed text
    private struct Record {
        var name: String
        var nameLowered: String
        var type: EntityType
        var indexedTokens: [String]
        var tagTexts: [String]
        var extraTexts: [String]
        var fieldKVs: [(key: String, value: String)]
    }

    private var byID: [EntityID: Record] = [:]
    private var prefixIndex = InvertedIndex()

    public init() {}

    public mutating func build(from entities: [Entity]) {
        byID.removeAll(keepingCapacity: true)
        prefixIndex = InvertedIndex()
        for e in entities { upsert(e) }
    }

    public mutating func upsert(_ entity: Entity) {
        let record = makeRecord(for: entity)
        byID[entity.id] = record
        prefixIndex.replace(entity.id, withTerms: record.indexedTokens)
    }

    public mutating func remove(_ id: EntityID) {
        byID.removeValue(forKey: id)
        prefixIndex.remove(id)
    }

    public func query(_ raw: String) -> [SearchHit] {
        let parsed = QueryParser.parse(raw)
        var candidates = byID.keys.map { $0 } // start with all

        // Apply filters
        if !parsed.filters.isEmpty {
            candidates = candidates.filter { id in
                guard let r = byID[id] else { return false }
                return parsed.filters.allSatisfy { f in passesFilter(f, record: r) }
            }
        }

        // Score free terms
        if parsed.freeTerms.isEmpty {
            var pairs: [(id: EntityID, r: Record)] = []
            for id in candidates {
                if let r = byID[id] { pairs.append((id, r)) }
            }
            pairs.sort { $0.r.nameLowered < $1.r.nameLowered }
            return pairs.map { SearchHit(id: $0.id, type: $0.r.type, name: $0.r.name, score: 0) }
        }

        var scored: [SearchHit] = []
        for id in candidates {
            guard let r = byID[id] else { continue }
            var total = 0
            var allMatched = true
            for term in parsed.freeTerms {
                let s = FuzzyScorer.score(term: term,
                                          inName: r.name,
                                          indexed: r.indexedTokens,
                                          tagTexts: r.tagTexts,
                                          extraTexts: r.extraTexts)
                if s == 0 { allMatched = false; break }
                total += s
            }
            guard allMatched else { continue }
            scored.append(SearchHit(id: id, type: r.type, name: r.name, score: total))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name.lowercased() < $1.name.lowercased()
        }
        return scored
    }

    // MARK: - helpers

    private func passesFilter(_ f: Filter, record r: Record) -> Bool {
        switch f.key {
        case "type":
            return r.type.rawValue == f.value
        case "tag":
            return r.tagTexts.contains(where: { $0.contains(f.value) })
        default:
            // schema field filter
            return r.fieldKVs.contains { kv in
                kv.key == f.key && kv.value.contains(f.value)
            }
        }
    }

    private func makeRecord(for entity: Entity) -> Record {
        let nameLower = entity.name.lowercased()
        let tagTexts = entity.tags.map { $0.lowercased() }
        let bodyExcerpt = String(entity.body.prefix(200)).lowercased()
        let fieldKVs: [(String, String)] = entity.fields.map { (k, v) in
            (k.lowercased(), Self.renderFieldValue(v).lowercased())
        }
        let extraTexts = [bodyExcerpt] + fieldKVs.map { $0.1 }
        var tokens = Tokenizer.tokens(in: entity.name)
        tokens.append(contentsOf: Tokenizer.tokens(in: bodyExcerpt))
        for tag in tagTexts { tokens.append(contentsOf: Tokenizer.tokens(in: tag)) }
        for kv in fieldKVs  { tokens.append(contentsOf: Tokenizer.tokens(in: kv.1)) }
        tokens.append(entity.type.rawValue)
        // dedupe preserving order
        var seen = Set<String>()
        tokens = tokens.filter { seen.insert($0).inserted }
        return Record(name: entity.name, nameLowered: nameLower, type: entity.type,
                      indexedTokens: tokens, tagTexts: tagTexts,
                      extraTexts: extraTexts, fieldKVs: fieldKVs)
    }

    static func renderFieldValue(_ v: FieldValue) -> String {
        switch v {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .bool(let b):   return String(b)
        case .date(let d):   return ISO8601DateFormatter().string(from: d)
        case .ref(let id):   return id.rawValue
        case .list:          return ""
        }
    }
}

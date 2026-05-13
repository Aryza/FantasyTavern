import Foundation
import EntityModel

enum ConflictDecision: Equatable {
    /// New entity matches what user has — nothing to do.
    case inSync
    /// User had no local changes; reload silently.
    case silentReload
    /// User has local changes that differ from new disk state — prompt.
    case conflict

    typealias Drafts = (name: String, body: String, tags: [String], fields: [String: FieldValue])

    static func decide(baseline: Entity, newDisk: Entity, drafts: Drafts) -> ConflictDecision {
        let matches: (Entity) -> Bool = { e in
            e.name == drafts.name &&
            e.body == drafts.body &&
            e.tags == drafts.tags &&
            e.fields == drafts.fields
        }
        let sameContent: (Entity, Entity) -> Bool = { a, b in
            a.name == b.name && a.body == b.body && a.tags == b.tags && a.fields == b.fields
        }
        // Disk unchanged → user's local edits stand; nothing to do.
        if sameContent(baseline, newDisk) { return .inSync }
        if matches(newDisk) { return .inSync }
        if matches(baseline) { return .silentReload }
        return .conflict
    }
}

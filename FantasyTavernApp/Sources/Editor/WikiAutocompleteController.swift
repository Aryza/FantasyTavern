import Foundation
import Observation
import EntityModel

@Observable
final class WikiAutocompleteController {
    private(set) var isActive: Bool = false
    private(set) var query: String = ""
    private(set) var suggestions: [Entity] = []
    var selectionIndex: Int = 0

    /// The NSRange in the source string covered by `[[` + the partial query — used to splice in a full link.
    private(set) var triggerRange: NSRange = NSRange(location: 0, length: 0)

    struct Insertion: Equatable {
        let range: NSRange
        let replacement: String
    }

    func update(text: String, caret: Int, entities: [Entity]) {
        let ns = text as NSString
        guard caret >= 2, caret <= ns.length else { deactivate(); return }
        let prefix = ns.substring(with: NSRange(location: 0, length: caret))
        // find last unmatched "[["
        guard let openLoc = lastOpenBracketPair(in: prefix) else { deactivate(); return }
        let queryStart = openLoc + 2
        let q = (prefix as NSString).substring(from: queryStart)
        if q.contains("]") || q.contains("\n") { deactivate(); return }
        let lowerQ = q.lowercased()
        let filtered = entities.filter { lowerQ.isEmpty || $0.name.lowercased().contains(lowerQ) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        isActive = true
        query = q
        suggestions = filtered
        selectionIndex = min(selectionIndex, max(0, suggestions.count - 1))
        triggerRange = NSRange(location: openLoc, length: caret - openLoc)
    }

    func move(by delta: Int) {
        guard !suggestions.isEmpty else { selectionIndex = 0; return }
        let max = suggestions.count - 1
        selectionIndex = Swift.min(max, Swift.max(0, selectionIndex + delta))
    }

    func acceptCurrent() -> Insertion? {
        guard isActive, !suggestions.isEmpty else { return nil }
        let entity = suggestions[selectionIndex]
        let replacement = "[[\(entity.name)]]"
        return Insertion(range: triggerRange, replacement: replacement)
    }

    func deactivate() {
        isActive = false
        query = ""
        suggestions = []
        selectionIndex = 0
    }

    private func lastOpenBracketPair(in prefix: String) -> Int? {
        // Scan from the end for the last "[[" not preceded by a "]" intervening between the caret and the brackets.
        let ns = prefix as NSString
        var i = ns.length - 1
        while i >= 1 {
            if ns.character(at: i - 1) == 0x5B /* '[' */ && ns.character(at: i) == 0x5B {
                return i - 1
            }
            if ns.character(at: i) == 0x5D /* ']' */ { return nil }
            i -= 1
        }
        return nil
    }
}

import Foundation

public enum FuzzyScorer {
    /// Score one free term against a candidate entity's text fragments.
    /// - Parameters:
    ///   - term: already lowercased single term.
    ///   - inName: entity name (will be lowercased here).
    ///   - indexed: tokens already extracted from the entity's name+body+fields (lowercased).
    ///   - tagTexts: lowercased tag strings (whole tag matches, not tokenized).
    ///   - extraTexts: lowercased body/field text (substring matches against this gives the lowest non-subsequence score).
    /// - Returns: 0 if no match; otherwise a positive integer score.
    public static func score(term: String,
                             inName name: String,
                             indexed tokens: [String],
                             tagTexts: [String] = [],
                             extraTexts: [String] = []) -> Int {
        let n = name.lowercased()
        if n == term { return 100 }
        if n.contains(term) { return 60 }
        for tag in tagTexts where tag.contains(term) { return 25 }
        for extra in extraTexts where extra.contains(term) { return 10 }
        for token in tokens where token.contains(term) { return 10 }
        if isSubsequence(term, of: n) { return 5 }
        return 0
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var i = needle.startIndex
        for ch in haystack {
            if i == needle.endIndex { return true }
            if ch == needle[i] { i = needle.index(after: i) }
        }
        return i == needle.endIndex
    }
}

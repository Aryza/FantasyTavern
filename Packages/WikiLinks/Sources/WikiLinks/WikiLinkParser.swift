import Foundation

public struct WikiLinkMatch: Equatable {
    public let name: String
    public let alias: String?
    public let range: Range<String.Index>
}

public enum WikiLinkParser {
    public static func findLinks(in text: String) -> [WikiLinkMatch] {
        var results: [WikiLinkMatch] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            guard let openStart = text.range(of: "[[", range: idx..<text.endIndex) else { break }
            guard let closeRange = text.range(of: "]]", range: openStart.upperBound..<text.endIndex) else { break }
            let inner = text[openStart.upperBound..<closeRange.lowerBound]
            if inner.contains("\n") || inner.contains("[[") {
                idx = openStart.upperBound
                continue
            }
            let (name, alias) = split(inner: String(inner))
            if !name.isEmpty {
                results.append(.init(name: name, alias: alias, range: openStart.lowerBound..<closeRange.upperBound))
            }
            idx = closeRange.upperBound
        }
        return results
    }

    private static func split(inner: String) -> (name: String, alias: String?) {
        if let pipe = inner.firstIndex(of: "|") {
            let name = inner[..<pipe].trimmingCharacters(in: .whitespaces)
            let alias = inner[inner.index(after: pipe)...].trimmingCharacters(in: .whitespaces)
            return (String(name), alias.isEmpty ? nil : String(alias))
        }
        return (inner.trimmingCharacters(in: .whitespaces), nil)
    }
}

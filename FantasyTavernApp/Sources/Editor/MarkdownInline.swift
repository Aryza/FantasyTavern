import Foundation

enum MarkdownInline {
    enum Kind { case bold, italic, strike, code }

    struct Span: Equatable {
        let outer: NSRange   // includes markers
        let inner: NSRange   // inside markers
    }

    struct HeadingLine: Equatable {
        let level: Int
        let marker: NSRange  // "# " / "## " / "### "
        let content: NSRange // rest of line
    }

    struct ListLine: Equatable {
        let marker: NSRange  // "- " or "* "
        let content: NSRange
    }

    static func spans(in source: String, kind: Kind) -> [Span] {
        let pattern: String
        let markerLen: Int
        switch kind {
        case .bold:   pattern = #"\*\*([^*\n]+?)\*\*"#; markerLen = 2
        case .italic: pattern = #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#; markerLen = 1
        case .strike: pattern = #"~~([^~\n]+?)~~"#; markerLen = 2
        case .code:   pattern = #"`([^`\n]+?)`"#; markerLen = 1
        }
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(location: 0, length: (source as NSString).length)
        return re.matches(in: source, range: full).map { m in
            let outer = m.range
            let inner = NSRange(location: outer.location + markerLen,
                                length: outer.length - 2 * markerLen)
            return Span(outer: outer, inner: inner)
        }
    }

    static func headingLines(in source: String) -> [HeadingLine] {
        guard let re = try? NSRegularExpression(pattern: #"(?m)^(#{1,3})\s+(.*)$"#) else { return [] }
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        return re.matches(in: source, range: full).compactMap { m in
            guard m.numberOfRanges == 3 else { return nil }
            let hashes = m.range(at: 1)
            let content = m.range(at: 2)
            let level = hashes.length
            let markerLen = (content.location - hashes.location)
            let marker = NSRange(location: hashes.location, length: markerLen)
            return HeadingLine(level: level, marker: marker, content: content)
        }
    }

    static func listMarkerLines(in source: String) -> [ListLine] {
        guard let re = try? NSRegularExpression(pattern: #"(?m)^([-*])\s+(.*)$"#) else { return [] }
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        return re.matches(in: source, range: full).compactMap { m in
            guard m.numberOfRanges == 3 else { return nil }
            let symbol = m.range(at: 1)
            let content = m.range(at: 2)
            let marker = NSRange(location: symbol.location, length: content.location - symbol.location)
            return ListLine(marker: marker, content: content)
        }
    }
}

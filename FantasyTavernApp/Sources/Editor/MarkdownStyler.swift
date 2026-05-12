import AppKit
import EntityModel
import WikiLinks

public extension NSAttributedString.Key {
    static let fantasyWikiLink = NSAttributedString.Key("FantasyWikiLink")          // value: EntityID.rawValue String
    static let fantasyWikiLinkDangling = NSAttributedString.Key("FantasyWikiLinkDangling") // value: name String
}

public enum MarkdownStyler {
    public static func attributedString(for body: String, resolver: WikiLinkResolver) -> NSAttributedString {
        let result = NSMutableAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ])
        for match in WikiLinkParser.findLinks(in: body) {
            guard let nsRange = nsRange(of: match.range, in: body) else { continue }
            if let id = resolver.resolve(name: match.name) {
                result.addAttributes([
                    .fantasyWikiLink: id.rawValue,
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: nsRange)
            } else {
                result.addAttributes([
                    .fantasyWikiLinkDangling: match.name,
                    .foregroundColor: NSColor.systemRed,
                    .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue,
                ], range: nsRange)
            }
        }
        return result
    }

    private static func nsRange(of range: Range<String.Index>, in source: String) -> NSRange? {
        NSRange(range, in: source)
    }
}

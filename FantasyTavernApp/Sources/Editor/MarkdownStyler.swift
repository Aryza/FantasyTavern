import AppKit
import EntityModel
import WikiLinks

public extension NSAttributedString.Key {
    static let fantasyWikiLink = NSAttributedString.Key("FantasyWikiLink")
    static let fantasyWikiLinkDangling = NSAttributedString.Key("FantasyWikiLinkDangling")
}

public enum MarkdownStyler {
    private static let baseFontSize: CGFloat = 14
    private static let h1Size: CGFloat = 22
    private static let h2Size: CGFloat = 18
    private static let h3Size: CGFloat = 15

    public static func attributedString(for body: String, resolver: WikiLinkResolver) -> NSAttributedString {
        let result = NSMutableAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        applyHeadings(to: result, body: body)
        applyListMarkers(to: result, body: body)
        applyCode(to: result, body: body)
        applyStrike(to: result, body: body)
        applyBold(to: result, body: body)
        applyItalic(to: result, body: body)
        applyWikiLinks(to: result, body: body, resolver: resolver)
        return result
    }

    // MARK: - blocks

    private static func applyHeadings(to s: NSMutableAttributedString, body: String) {
        for h in MarkdownInline.headingLines(in: body) {
            let size: CGFloat = h.level == 1 ? h1Size : (h.level == 2 ? h2Size : h3Size)
            let lineRange = NSUnionRange(h.marker, h.content)
            s.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: h.marker)
        }
    }

    private static func applyListMarkers(to s: NSMutableAttributedString, body: String) {
        for l in MarkdownInline.listMarkerLines(in: body) {
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: l.marker)
        }
    }

    // MARK: - inline

    private static func applyBold(to s: NSMutableAttributedString, body: String) {
        for span in MarkdownInline.spans(in: body, kind: .bold) {
            setFontTrait(.bold, in: span.inner, on: s)
            dimMarkers(span: span, length: 2, on: s)
        }
    }

    private static func applyItalic(to s: NSMutableAttributedString, body: String) {
        for span in MarkdownInline.spans(in: body, kind: .italic) {
            setFontTrait(.italic, in: span.inner, on: s)
            dimMarkers(span: span, length: 1, on: s)
        }
    }

    private static func applyStrike(to s: NSMutableAttributedString, body: String) {
        for span in MarkdownInline.spans(in: body, kind: .strike) {
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.inner)
            dimMarkers(span: span, length: 2, on: s)
        }
    }

    private static func applyCode(to s: NSMutableAttributedString, body: String) {
        for span in MarkdownInline.spans(in: body, kind: .code) {
            s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular), range: span.outer)
            s.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: span.outer)
        }
    }

    private static func applyWikiLinks(to s: NSMutableAttributedString, body: String, resolver: WikiLinkResolver) {
        for match in WikiLinkParser.findLinks(in: body) {
            let nsRange = NSRange(match.range, in: body)
            if let id = resolver.resolve(name: match.name) {
                s.addAttributes([
                    .fantasyWikiLink: id.rawValue,
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: nsRange)
            } else {
                s.addAttributes([
                    .fantasyWikiLinkDangling: match.name,
                    .foregroundColor: NSColor.systemRed,
                    .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue,
                ], range: nsRange)
            }
        }
    }

    // MARK: - helpers

    private static func setFontTrait(_ trait: NSFontDescriptor.SymbolicTraits,
                                     in range: NSRange,
                                     on s: NSMutableAttributedString) {
        let existing = (s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: baseFontSize)
        let merged = existing.fontDescriptor.symbolicTraits.union(trait)
        let desc = existing.fontDescriptor.withSymbolicTraits(merged)
        if let font = NSFont(descriptor: desc, size: 0) {
            s.addAttribute(.font, value: font, range: range)
        }
    }

    private static func dimMarkers(span: MarkdownInline.Span, length: Int, on s: NSMutableAttributedString) {
        let leading = NSRange(location: span.outer.location, length: length)
        let trailing = NSRange(location: span.outer.location + span.outer.length - length, length: length)
        s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: leading)
        s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: trailing)
    }
}

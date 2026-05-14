import AppKit
import EntityModel
import WorldStore

enum PDFContent {
    private static let titleFont   = NSFont.boldSystemFont(ofSize: 32)
    private static let typeFont    = NSFont.boldSystemFont(ofSize: 22)
    private static let nameFont    = NSFont.boldSystemFont(ofSize: 16)
    private static let captionFont = NSFont.systemFont(ofSize: 11)
    private static let bodyFont    = NSFont.systemFont(ofSize: 12)

    static func entityDocument(_ entity: Entity) -> NSAttributedString {
        let out = NSMutableAttributedString()
        appendName(entity.name, into: out)
        appendCaption(entity.type.rawValue, into: out)
        appendBody(entity.body, into: out)
        return out
    }

    static func worldDocument(world: World, entities: [Entity]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        appendTitle(world.name, into: out)

        for type in EntityType.allCases {
            let inType = entities.filter { $0.type == type }.sorted { $0.name.lowercased() < $1.name.lowercased() }
            guard !inType.isEmpty else { continue }
            appendTypeHeading(label(for: type), into: out)
            for entity in inType {
                appendName(entity.name, into: out)
                appendBody(entity.body, into: out)
            }
        }
        return out
    }

    // MARK: - sections

    private static func appendTitle(_ text: String, into s: NSMutableAttributedString) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacing = 32
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .paragraphStyle: para]
        s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
    }

    private static func appendTypeHeading(_ text: String, into s: NSMutableAttributedString) {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 24
        para.paragraphSpacing = 8
        let attrs: [NSAttributedString.Key: Any] = [.font: typeFont, .paragraphStyle: para]
        s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
    }

    private static func appendName(_ text: String, into s: NSMutableAttributedString) {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 8
        let attrs: [NSAttributedString.Key: Any] = [.font: nameFont, .paragraphStyle: para]
        s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
    }

    private static func appendCaption(_ text: String, into s: NSMutableAttributedString) {
        let attrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: NSColor.secondaryLabelColor]
        s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
    }

    private static func appendBody(_ text: String, into s: NSMutableAttributedString) {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 4
        para.paragraphSpacing = 6
        let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .paragraphStyle: para]
        s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
    }

    private static func label(for type: EntityType) -> String {
        switch type {
        case .character:     return "Characters"
        case .location:      return "Locations"
        case .lore:          return "Lore"
        case .item:          return "Items"
        case .language:      return "Languages"
        case .journal:       return "Journal"
        case .timelineEvent: return "Timeline"
        }
    }
}

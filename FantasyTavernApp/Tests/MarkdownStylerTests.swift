import XCTest
import EntityModel
import WikiLinks
@testable import FantasyTavernApp

final class MarkdownStylerTests: XCTestCase {
    func test_styleAttachesLinkAttributeOnResolvedLinks() {
        let entities = [Entity(id: EntityID("b"), type: .character, name: "B")]
        let resolver = WikiLinkResolver(entities: entities)
        let styled = MarkdownStyler.attributedString(for: "see [[B]] and [[Unknown]]", resolver: resolver)

        let plain = styled.string
        let bRange = (plain as NSString).range(of: "[[B]]")
        let unknownRange = (plain as NSString).range(of: "[[Unknown]]")

        let resolvedAttr = styled.attribute(.fantasyWikiLink, at: bRange.location, effectiveRange: nil) as? String
        XCTAssertEqual(resolvedAttr, "b")

        let danglingAttr = styled.attribute(.fantasyWikiLinkDangling, at: unknownRange.location, effectiveRange: nil) as? String
        XCTAssertEqual(danglingAttr, "Unknown")
    }
}

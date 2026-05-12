import XCTest
import EntityModel
@testable import WikiLinks

final class WikiLinkResolverTests: XCTestCase {
    let entities: [Entity] = [
        Entity(id: EntityID("lyra-stormwind"), type: .character, name: "Lyra Stormwind"),
        Entity(id: EntityID("magnus-blackthorn"), type: .character, name: "Magnus Blackthorn"),
    ]

    func test_resolveExact() {
        let r = WikiLinkResolver(entities: entities)
        XCTAssertEqual(r.resolve(name: "Lyra Stormwind")?.rawValue, "lyra-stormwind")
    }

    func test_resolveCaseInsensitive() {
        let r = WikiLinkResolver(entities: entities)
        XCTAssertEqual(r.resolve(name: "lyra stormwind")?.rawValue, "lyra-stormwind")
    }

    func test_resolveDangling_returnsNil() {
        let r = WikiLinkResolver(entities: entities)
        XCTAssertNil(r.resolve(name: "Unknown"))
    }

    func test_resolveCollapsedWhitespace() {
        let r = WikiLinkResolver(entities: entities)
        XCTAssertEqual(r.resolve(name: "  Lyra   Stormwind  ")?.rawValue, "lyra-stormwind")
    }
}

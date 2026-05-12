import XCTest
@testable import WikiLinks

final class WikiLinkParserTests: XCTestCase {
    func test_findsSingleLink() {
        let matches = WikiLinkParser.findLinks(in: "Hi [[Lyra]]!")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].name, "Lyra")
        XCTAssertNil(matches[0].alias)
    }

    func test_findsAlias() {
        let matches = WikiLinkParser.findLinks(in: "see [[Lyra Stormwind|Lyra]]")
        XCTAssertEqual(matches.first?.name, "Lyra Stormwind")
        XCTAssertEqual(matches.first?.alias, "Lyra")
    }

    func test_findsMultiple() {
        let matches = WikiLinkParser.findLinks(in: "[[A]] then [[B|b]]")
        XCTAssertEqual(matches.map(\.name), ["A", "B"])
    }

    func test_ignoresNewlinesInsideLink() {
        let matches = WikiLinkParser.findLinks(in: "[[Bad\nLink]] [[Good]]")
        XCTAssertEqual(matches.map(\.name), ["Good"])
    }

    func test_returnsByteRanges() {
        let text = "x [[Lyra]] y"
        let matches = WikiLinkParser.findLinks(in: text)
        let r = matches[0].range
        XCTAssertEqual(text[r], "[[Lyra]]")
    }
}

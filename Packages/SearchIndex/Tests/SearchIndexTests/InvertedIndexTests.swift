import XCTest
import EntityModel
@testable import SearchIndex

final class InvertedIndexTests: XCTestCase {
    func test_addAndQuery_singleTerm() {
        var idx = InvertedIndex()
        idx.add(["lyra", "stormwind"], for: EntityID("lyra"))
        XCTAssertEqual(idx.ids(matchingTermPrefix: "lyra"), Set([EntityID("lyra")]))
    }

    func test_prefixMatch() {
        var idx = InvertedIndex()
        idx.add(["stormwind"], for: EntityID("a"))
        idx.add(["storm"],     for: EntityID("b"))
        XCTAssertEqual(idx.ids(matchingTermPrefix: "storm"),
                       Set([EntityID("a"), EntityID("b")]))
    }

    func test_removeEntity_dropsItsTerms() {
        var idx = InvertedIndex()
        idx.add(["lyra"], for: EntityID("a"))
        idx.add(["lyra"], for: EntityID("b"))
        idx.remove(EntityID("a"))
        XCTAssertEqual(idx.ids(matchingTermPrefix: "lyra"), Set([EntityID("b")]))
    }

    func test_replaceEntity_refreshesTerms() {
        var idx = InvertedIndex()
        idx.add(["foo"], for: EntityID("a"))
        idx.replace(EntityID("a"), withTerms: ["bar"])
        XCTAssertTrue(idx.ids(matchingTermPrefix: "foo").isEmpty)
        XCTAssertEqual(idx.ids(matchingTermPrefix: "bar"), Set([EntityID("a")]))
    }
}

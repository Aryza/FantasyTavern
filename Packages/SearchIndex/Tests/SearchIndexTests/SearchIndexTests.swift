import XCTest
import EntityModel
@testable import SearchIndex

final class SearchIndexTests: XCTestCase {
    private func entities() -> [Entity] {
        [
            Entity(id: EntityID("lyra"),    type: .character, name: "Lyra Stormwind",
                   tags: ["noble", "ranger"],
                   fields: ["race": .string("half-elf")],
                   body: "Born in Silvermoon. Friend of [[Magnus Blackthorn]]."),
            Entity(id: EntityID("magnus"),  type: .character, name: "Magnus Blackthorn",
                   tags: ["mage"],
                   fields: ["race": .string("human")],
                   body: "Sorcerer."),
            Entity(id: EntityID("silvermoon"), type: .location, name: "Silvermoon",
                   tags: [],
                   fields: ["kind": .string("city")],
                   body: "Capital of the realm."),
        ]
    }

    func test_build_thenQueryByFreeTerm() {
        var idx = SearchIndex()
        idx.build(from: entities())
        let result = idx.query("lyra")
        XCTAssertEqual(result.map(\.id.rawValue), ["lyra"])
    }

    func test_typeFilter_narrows() {
        var idx = SearchIndex()
        idx.build(from: entities())
        let result = idx.query("type:character")
        XCTAssertEqual(Set(result.map(\.id.rawValue)), ["lyra", "magnus"])
    }

    func test_tagFilter_hashSyntax() {
        var idx = SearchIndex()
        idx.build(from: entities())
        let result = idx.query("#noble")
        XCTAssertEqual(result.map(\.id.rawValue), ["lyra"])
    }

    func test_fieldFilter() {
        var idx = SearchIndex()
        idx.build(from: entities())
        let result = idx.query("race:elf")
        XCTAssertEqual(result.map(\.id.rawValue), ["lyra"])
    }

    func test_freeTerm_rankingPrefersNameOverBody() {
        var idx = SearchIndex()
        idx.build(from: entities())
        // "silvermoon" appears as Lyra's body AND as the Silvermoon entity's name.
        // Silvermoon should rank above Lyra.
        let result = idx.query("silvermoon")
        XCTAssertEqual(result.map(\.id.rawValue), ["silvermoon", "lyra"])
    }

    func test_upsert_replacesEntityIndex() {
        var idx = SearchIndex()
        idx.build(from: entities())
        var lyra = entities()[0]
        lyra.name = "Renamed Person"
        lyra.tags = []
        idx.upsert(lyra)
        XCTAssertTrue(idx.query("lyra").isEmpty)
        XCTAssertEqual(idx.query("renamed").map(\.id.rawValue), ["lyra"])
    }

    func test_empty_query_returnsAll() {
        var idx = SearchIndex()
        idx.build(from: entities())
        let result = idx.query("")
        XCTAssertEqual(Set(result.map(\.id.rawValue)), ["lyra", "magnus", "silvermoon"])
    }
}

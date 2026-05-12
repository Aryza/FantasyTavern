import XCTest
@testable import SearchIndex

final class QueryParserTests: XCTestCase {
    func test_emptyString_emptyQuery() {
        let q = QueryParser.parse("")
        XCTAssertTrue(q.filters.isEmpty)
        XCTAssertTrue(q.freeTerms.isEmpty)
        XCTAssertFalse(q.isActionMode)
    }

    func test_freeTerms_lowercased() {
        let q = QueryParser.parse("Lyra Stormwind")
        XCTAssertEqual(q.freeTerms, ["lyra", "stormwind"])
    }

    func test_typeFilter() {
        let q = QueryParser.parse("type:character lyra")
        XCTAssertEqual(q.filters, [.init(key: "type", value: "character")])
        XCTAssertEqual(q.freeTerms, ["lyra"])
    }

    func test_hashTag_becomesTagFilter() {
        let q = QueryParser.parse("#noble")
        XCTAssertEqual(q.filters, [.init(key: "tag", value: "noble")])
        XCTAssertTrue(q.freeTerms.isEmpty)
    }

    func test_fieldFilter() {
        let q = QueryParser.parse("race:elf")
        XCTAssertEqual(q.filters, [.init(key: "race", value: "elf")])
    }

    func test_mixed() {
        let q = QueryParser.parse("type:character race:elf #noble Lyra")
        XCTAssertEqual(Set(q.filters), Set([
            .init(key: "type", value: "character"),
            .init(key: "race", value: "elf"),
            .init(key: "tag",  value: "noble"),
        ]))
        XCTAssertEqual(q.freeTerms, ["lyra"])
    }

    func test_actionMode_prefix() {
        let q = QueryParser.parse("> new char")
        XCTAssertTrue(q.isActionMode)
        XCTAssertEqual(q.freeTerms, ["new", "char"])
    }

    func test_actionMode_noSpaceAfterAngle() {
        let q = QueryParser.parse(">open")
        XCTAssertTrue(q.isActionMode)
        XCTAssertEqual(q.freeTerms, ["open"])
    }
}

import XCTest
@testable import SearchIndex

final class FuzzyScorerTests: XCTestCase {
    func test_exactNameMatch_highest() {
        XCTAssertEqual(FuzzyScorer.score(term: "lyra", inName: "lyra", indexed: ["lyra"]), 100)
    }

    func test_nameSubstring() {
        XCTAssertEqual(FuzzyScorer.score(term: "storm", inName: "lyra stormwind", indexed: ["lyra","stormwind"]), 60)
    }

    func test_tagSubstring() {
        XCTAssertEqual(FuzzyScorer.score(term: "nob", inName: "lyra", indexed: ["lyra"], tagTexts: ["noble"]), 25)
    }

    func test_bodyOrFieldSubstring() {
        XCTAssertEqual(FuzzyScorer.score(term: "elf", inName: "magnus", indexed: ["magnus"], extraTexts: ["half-elf"]), 10)
    }

    func test_subsequenceFallback() {
        // term letters appear in order inside name but not contiguous
        XCTAssertEqual(FuzzyScorer.score(term: "lsw", inName: "lyra stormwind", indexed: ["lyra","stormwind"]), 5)
    }

    func test_noMatch_returnsZero() {
        XCTAssertEqual(FuzzyScorer.score(term: "xyz", inName: "lyra", indexed: ["lyra"]), 0)
    }
}

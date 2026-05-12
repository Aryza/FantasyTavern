import XCTest
@testable import SearchIndex

final class TokenizerTests: XCTestCase {
    func test_lowercase_splitsOnWhitespace() {
        XCTAssertEqual(Tokenizer.tokens(in: "Lyra Stormwind"), ["lyra", "stormwind"])
    }

    func test_splitsOnPunctuation() {
        XCTAssertEqual(Tokenizer.tokens(in: "half-elf, ranger!"), ["half", "elf", "ranger"])
    }

    func test_foldsDiacritics() {
        XCTAssertEqual(Tokenizer.tokens(in: "Étienne"), ["etienne"])
    }

    func test_empty_returnsEmpty() {
        XCTAssertEqual(Tokenizer.tokens(in: ""), [])
        XCTAssertEqual(Tokenizer.tokens(in: "   "), [])
    }

    func test_dedupesPreserveOrder() {
        XCTAssertEqual(Tokenizer.tokens(in: "Lyra Lyra Stormwind"), ["lyra", "stormwind"])
    }
}

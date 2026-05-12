import XCTest
@testable import WorldStore

final class SlugTests: XCTestCase {
    func test_basicLowercase() {
        XCTAssertEqual(Slug.make("Lyra"), "lyra")
    }
    func test_replacesWhitespaceWithHyphen() {
        XCTAssertEqual(Slug.make("Lyra Stormwind"), "lyra-stormwind")
    }
    func test_collapsesRuns() {
        XCTAssertEqual(Slug.make("Lyra   Stormwind!!"), "lyra-stormwind")
    }
    func test_asciiFoldsAccents() {
        XCTAssertEqual(Slug.make("Étienne"), "etienne")
    }
    func test_emptyBecomesUntitled() {
        XCTAssertEqual(Slug.make("   "), "untitled")
        XCTAssertEqual(Slug.make(""), "untitled")
    }
    func test_trimsLeadingTrailingHyphens() {
        XCTAssertEqual(Slug.make("--hi--"), "hi")
    }
}

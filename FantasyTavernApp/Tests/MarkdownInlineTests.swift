import XCTest
@testable import FantasyTavernApp

final class MarkdownInlineTests: XCTestCase {
    func test_boldSpans() {
        let s = "hello **world** ok **two**"
        let ranges = MarkdownInline.spans(in: s, kind: .bold)
        XCTAssertEqual(ranges.count, 2)
        let str = s as NSString
        XCTAssertEqual(str.substring(with: ranges[0].outer), "**world**")
        XCTAssertEqual(str.substring(with: ranges[0].inner), "world")
        XCTAssertEqual(str.substring(with: ranges[1].outer), "**two**")
    }

    func test_italic_doesNotMatchInsideBold() {
        let s = "**not italic** but *yes*"
        let italics = MarkdownInline.spans(in: s, kind: .italic)
        XCTAssertEqual(italics.map { (s as NSString).substring(with: $0.outer) }, ["*yes*"])
    }

    func test_strike() {
        let s = "~~gone~~"
        let r = MarkdownInline.spans(in: s, kind: .strike)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual((s as NSString).substring(with: r[0].inner), "gone")
    }

    func test_code() {
        let s = "before `let x = 1` after"
        let r = MarkdownInline.spans(in: s, kind: .code)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual((s as NSString).substring(with: r[0].inner), "let x = 1")
    }

    func test_headings_levelDetection() {
        let body = "# H1 line\n## H2\n###  H3\nnot heading"
        let h1 = MarkdownInline.headingLines(in: body)
        XCTAssertEqual(h1.count, 3)
        XCTAssertEqual(h1[0].level, 1)
        XCTAssertEqual(h1[1].level, 2)
        XCTAssertEqual(h1[2].level, 3)
        XCTAssertEqual((body as NSString).substring(with: h1[0].marker), "# ")
        XCTAssertEqual((body as NSString).substring(with: h1[0].content), "H1 line")
    }

    func test_listMarkers() {
        let body = "- one\n* two\nthree"
        let lists = MarkdownInline.listMarkerLines(in: body)
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual((body as NSString).substring(with: lists[0].marker), "- ")
        XCTAssertEqual((body as NSString).substring(with: lists[1].marker), "* ")
    }
}

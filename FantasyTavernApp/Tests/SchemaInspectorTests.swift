import XCTest
import EntityModel
import SchemaRegistry
@testable import FantasyTavernApp

final class SchemaInspectorTests: XCTestCase {
    func test_displayString_forValue() {
        XCTAssertEqual(FieldFormatter.display(.string("half-elf"), type: .string), "half-elf")
        XCTAssertEqual(FieldFormatter.display(.int(42),           type: .int),    "42")
        XCTAssertEqual(FieldFormatter.display(.bool(true),        type: .bool),   "true")
        XCTAssertEqual(FieldFormatter.display(nil,                type: .string), "")
    }

    func test_parseString_coercesToFieldValue() {
        XCTAssertEqual(FieldFormatter.parse("half-elf", as: .string), .string("half-elf"))
        XCTAssertEqual(FieldFormatter.parse("42",       as: .int),    .int(42))
        XCTAssertEqual(FieldFormatter.parse("true",     as: .bool),   .bool(true))
        XCTAssertEqual(FieldFormatter.parse("",         as: .string), nil)
        XCTAssertEqual(FieldFormatter.parse("not-a-number", as: .int), nil)
    }

    func test_parseDate_iso8601() {
        let d = FieldFormatter.parse("2026-05-12T10:00:00Z", as: .date)
        if case .date(let date) = d {
            XCTAssertEqual(Int(date.timeIntervalSince1970), 1778580000)
        } else {
            XCTFail("expected .date")
        }
    }
}

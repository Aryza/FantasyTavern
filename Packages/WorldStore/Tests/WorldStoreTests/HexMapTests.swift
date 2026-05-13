import XCTest
import EntityModel
@testable import WorldStore

final class HexMapTests: XCTestCase {
    func test_defaultPalette_hasEightEntries() {
        XCTAssertEqual(HexMapDoc.defaultPalette.map(\.key),
                       ["empty","plains","forest","hills","mountain","water","desert","town"])
    }

    func test_make_filledWithEmpty() {
        let doc = HexMapDoc.make(cols: 3, rows: 2)
        XCTAssertEqual(doc.cols, 3)
        XCTAssertEqual(doc.rows, 2)
        XCTAssertEqual(doc.cells.count, 2)
        XCTAssertEqual(doc.cells[0].count, 3)
        XCTAssertTrue(doc.cells.flatMap { $0 }.allSatisfy { $0.terrain == "empty" })
    }

    func test_setTerrain_updatesCell() {
        var doc = HexMapDoc.make(cols: 2, rows: 2)
        doc.setTerrain("forest", col: 1, row: 0)
        XCTAssertEqual(doc.cell(col: 1, row: 0)?.terrain, "forest")
    }

    func test_setTerrain_outOfBounds_isNoOp() {
        var doc = HexMapDoc.make(cols: 1, rows: 1)
        doc.setTerrain("forest", col: 5, row: 5)
        doc.setTerrain("forest", col: -1, row: 0)
        XCTAssertEqual(doc.cell(col: 0, row: 0)?.terrain, "empty")
    }

    func test_codable_roundTrip() throws {
        var doc = HexMapDoc.make(cols: 2, rows: 2)
        doc.setTerrain("forest", col: 0, row: 0)
        doc.setTerrain("water",  col: 1, row: 1)
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(HexMapDoc.self, from: data)
        XCTAssertEqual(decoded, doc)
    }
}

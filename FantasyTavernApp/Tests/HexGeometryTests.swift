import XCTest
@testable import FantasyTavernApp

final class HexGeometryTests: XCTestCase {
    func test_centerForOrigin() {
        let p = HexGeometry.center(col: 0, row: 0, size: 24)
        XCTAssertEqual(p.x, 0, accuracy: 0.001)
        XCTAssertEqual(p.y, 0, accuracy: 0.001)
    }

    func test_oddRowOffsetX() {
        // row 1 (odd) is shifted right by hexWidth/2
        let p0 = HexGeometry.center(col: 0, row: 0, size: 24)
        let p1 = HexGeometry.center(col: 0, row: 1, size: 24)
        let hexWidth = 24.0 * sqrt(3.0)
        XCTAssertEqual(p1.x - p0.x, hexWidth / 2, accuracy: 0.001)
    }

    func test_columnSpacing() {
        let a = HexGeometry.center(col: 0, row: 0, size: 24)
        let b = HexGeometry.center(col: 1, row: 0, size: 24)
        let hexWidth = 24.0 * sqrt(3.0)
        XCTAssertEqual(b.x - a.x, hexWidth, accuracy: 0.001)
    }

    func test_rowSpacing() {
        let a = HexGeometry.center(col: 0, row: 0, size: 24)
        let b = HexGeometry.center(col: 0, row: 1, size: 24)
        XCTAssertEqual(b.y - a.y, 24.0 * 1.5, accuracy: 0.001)
    }

    func test_cellAtPoint_centerHits() {
        let c = HexGeometry.center(col: 2, row: 3, size: 24)
        let result = HexGeometry.cellAt(point: c, size: 24, cols: 6, rows: 6)
        XCTAssertEqual(result?.col, 2)
        XCTAssertEqual(result?.row, 3)
    }

    func test_cellAtPoint_outsideAllCells_nil() {
        let result = HexGeometry.cellAt(point: CGPoint(x: -1000, y: -1000), size: 24, cols: 6, rows: 6)
        XCTAssertNil(result)
    }

    func test_totalSize_growsWithGrid() {
        let s1 = HexGeometry.totalSize(cols: 1, rows: 1, size: 24)
        let s10 = HexGeometry.totalSize(cols: 10, rows: 10, size: 24)
        XCTAssertGreaterThan(s10.width, s1.width)
        XCTAssertGreaterThan(s10.height, s1.height)
    }
}

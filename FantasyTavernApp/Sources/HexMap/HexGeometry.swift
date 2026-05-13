import CoreGraphics
import Foundation

enum HexGeometry {
    struct Coord: Equatable { let col: Int; let row: Int }

    static func center(col: Int, row: Int, size: Double) -> CGPoint {
        let hexWidth = size * sqrt(3.0)
        let xOffset = row.isMultiple(of: 2) ? 0.0 : hexWidth / 2.0
        let x = hexWidth * Double(col) + xOffset
        let y = size * 1.5 * Double(row)
        return CGPoint(x: x, y: y)
    }

    static func cellAt(point: CGPoint, size: Double, cols: Int, rows: Int) -> Coord? {
        guard cols > 0, rows > 0 else { return nil }
        var best: (dist: Double, coord: Coord)?
        for r in 0..<rows {
            for c in 0..<cols {
                let center = HexGeometry.center(col: c, row: r, size: size)
                let dx = point.x - center.x
                let dy = point.y - center.y
                let d = sqrt(Double(dx * dx + dy * dy))
                if d <= size && (best == nil || d < best!.dist) {
                    best = (d, Coord(col: c, row: r))
                }
            }
        }
        return best?.coord
    }

    static func totalSize(cols: Int, rows: Int, size: Double) -> CGSize {
        guard cols > 0, rows > 0 else { return .zero }
        let hexWidth = size * sqrt(3.0)
        let hexHeight = size * 2
        let width = hexWidth * (Double(cols) + (rows > 1 ? 0.5 : 0))
        let height = hexHeight * (1 + Double(rows - 1) * 0.75)
        return CGSize(width: width, height: height)
    }

    static func hexPath(centerX cx: Double, centerY cy: Double, size: Double) -> CGPath {
        // pointy-top: vertices at angles 90°, 150°, 210°, 270°, 330°, 30°
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = (Double.pi / 180.0) * (60.0 * Double(i) - 30.0)
            let x = cx + size * cos(angle)
            let y = cy + size * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

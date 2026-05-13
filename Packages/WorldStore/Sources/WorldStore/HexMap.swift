import Foundation
import EntityModel

public struct HexCell: Equatable, Codable, Sendable {
    public var terrain: String
    public var label: String?
    public var locationId: EntityID?

    public init(terrain: String = "empty", label: String? = nil, locationId: EntityID? = nil) {
        self.terrain = terrain
        self.label = label
        self.locationId = locationId
    }
}

public struct HexPaletteEntry: Equatable, Codable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var colorHex: String

    public var id: String { key }

    public init(key: String, name: String, colorHex: String) {
        self.key = key
        self.name = name
        self.colorHex = colorHex
    }
}

public struct HexMapDoc: Equatable, Codable, Sendable {
    public var cols: Int
    public var rows: Int
    public var orientation: String
    public var palette: [HexPaletteEntry]
    public var cells: [[HexCell]]

    public init(cols: Int, rows: Int, orientation: String = "pointy",
                palette: [HexPaletteEntry] = HexMapDoc.defaultPalette,
                cells: [[HexCell]]) {
        self.cols = cols
        self.rows = rows
        self.orientation = orientation
        self.palette = palette
        self.cells = cells
    }

    public static let defaultPalette: [HexPaletteEntry] = [
        .init(key: "empty",    name: "Empty",    colorHex: "#F5F5F5"),
        .init(key: "plains",   name: "Plains",   colorHex: "#C8E6A0"),
        .init(key: "forest",   name: "Forest",   colorHex: "#3F7D3F"),
        .init(key: "hills",    name: "Hills",    colorHex: "#A78A5D"),
        .init(key: "mountain", name: "Mountain", colorHex: "#7E7E7E"),
        .init(key: "water",    name: "Water",    colorHex: "#5085C5"),
        .init(key: "desert",   name: "Desert",   colorHex: "#E4C97A"),
        .init(key: "town",     name: "Town",     colorHex: "#B85C4A"),
    ]

    public static func make(cols: Int, rows: Int) -> HexMapDoc {
        let row = Array(repeating: HexCell(), count: max(0, cols))
        let cells = Array(repeating: row, count: max(0, rows))
        return HexMapDoc(cols: max(0, cols), rows: max(0, rows), cells: cells)
    }

    public func cell(col: Int, row: Int) -> HexCell? {
        guard row >= 0, row < cells.count, col >= 0, col < cells[row].count else { return nil }
        return cells[row][col]
    }

    public mutating func setTerrain(_ terrain: String, col: Int, row: Int) {
        guard row >= 0, row < cells.count, col >= 0, col < cells[row].count else { return }
        cells[row][col].terrain = terrain
    }
}

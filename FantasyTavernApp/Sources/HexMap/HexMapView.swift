import SwiftUI
import AppKit
import WorldStore

struct HexMapView: View {
    @Environment(WorldSession.self) private var session
    let name: String

    @State private var doc: HexMapDoc?
    @State private var loadError: String?
    @State private var activeBrush: String = "plains"
    @State private var saveTask: Task<Void, Never>?

    private let cellSize: Double = 24

    var body: some View {
        Group {
            if let doc {
                VStack(spacing: 0) {
                    palette(doc: doc)
                    Divider()
                    ScrollView([.horizontal, .vertical]) {
                        canvas(doc: doc)
                            .padding(20)
                    }
                }
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView().task { load() }
            }
        }
    }

    private func palette(doc: HexMapDoc) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(doc.palette) { entry in
                    Button {
                        activeBrush = entry.key
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: entry.colorHex))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.primary.opacity(0.4)))
                            Text(entry.name).font(.caption)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(activeBrush == entry.key ? Color.accentColor.opacity(0.25) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private func canvas(doc: HexMapDoc) -> some View {
        let total = HexGeometry.totalSize(cols: doc.cols, rows: doc.rows, size: cellSize)
        let pad = cellSize
        return Canvas { context, _ in
            let colorByKey = Dictionary(uniqueKeysWithValues: doc.palette.map { ($0.key, Color(hex: $0.colorHex)) })
            for r in 0..<doc.rows {
                for c in 0..<doc.cols {
                    let cell = doc.cells[r][c]
                    let center = HexGeometry.center(col: c, row: r, size: cellSize)
                    let path = Path(HexGeometry.hexPath(centerX: center.x + pad, centerY: center.y + pad, size: cellSize))
                    context.fill(path, with: .color(colorByKey[cell.terrain] ?? .gray))
                    context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
                }
            }
        }
        .frame(width: total.width + pad * 2, height: total.height + pad * 2)
        .gesture(paintGesture(pad: pad))
    }

    private func paintGesture(pad: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                paintAt(point: value.location, pad: pad, terrain: activeBrush)
            }
            .onEnded { _ in scheduleSave() }
    }

    private func paintAt(point: CGPoint, pad: Double, terrain: String) {
        guard var d = doc else { return }
        let translated = CGPoint(x: point.x - pad, y: point.y - pad)
        guard let coord = HexGeometry.cellAt(point: translated, size: cellSize, cols: d.cols, rows: d.rows) else { return }
        if d.cells[coord.row][coord.col].terrain == terrain { return }
        d.setTerrain(terrain, col: coord.col, row: coord.row)
        doc = d
    }

    private func load() {
        guard let store = session.store else { loadError = "No world open"; return }
        do {
            doc = try store.loadHexMap(named: name)
        } catch {
            loadError = "Failed to load hex map: \(error)"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = doc
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            guard let d = snapshot, let store = session.store else { return }
            try? store.saveHexMap(d, name: name)
        }
    }
}

// MARK: - Color from #hex helper

extension Color {
    init(hex: String) {
        var hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if hexString.count == 3 {
            hexString = hexString.map { "\($0)\($0)" }.joined()
        }
        guard hexString.count == 6, let intVal = UInt64(hexString, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

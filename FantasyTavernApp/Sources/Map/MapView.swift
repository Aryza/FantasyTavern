import SwiftUI
import AppKit
import EntityModel
import WorldStore

struct MapView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    let name: String

    @State private var doc: MapDoc?
    @State private var loadError: String?
    @State private var pendingPinNormalized: CGPoint?
    @State private var image: NSImage?

    @State private var scale: Double = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var pinDragBaseline: [Int: CGPoint] = [:]

    var body: some View {
        Group {
            if let doc, let image {
                GeometryReader { geo in
                    let fit = aspectFit(imageSize: image.size, container: geo.size)
                    ZStack(alignment: .topLeading) {
                        imageLayer(doc: doc, image: image, fit: fit)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(panGesture(fit: fit))
                    .gesture(magnifyGesture())
                    .background(WheelZoomCatcher(scale: $scale))
                }
                .popover(isPresented: Binding(
                    get: { pendingPinNormalized != nil },
                    set: { if !$0 { pendingPinNormalized = nil } }
                )) {
                    AddPinPopover { locationID in
                        if let p = pendingPinNormalized {
                            addPin(at: p, locationID: locationID)
                            pendingPinNormalized = nil
                        }
                    }
                }
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView().task { load() }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Reset") { resetView() }
            }
        }
    }

    // MARK: - layers

    @ViewBuilder
    private func imageLayer(doc: MapDoc, image: NSImage, fit: FitRect) -> some View {
        let totalOffset = CGSize(width: committedOffset.width + dragOffset.width,
                                 height: committedOffset.height + dragOffset.height)
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fit.size.width, height: fit.size.height)
                .offset(x: fit.origin.x, y: fit.origin.y)
                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).modifiers(.command).onEnded { event in
                    pendingPinNormalized = normalize(event.location, in: fit)
                })
            ForEach(Array(doc.pins.enumerated()), id: \.offset) { idx, pin in
                pinView(idx: idx, pin: pin, fit: fit)
            }
        }
        .scaleEffect(scale, anchor: .center)
        .offset(totalOffset)
        .animation(.snappy, value: scale)
    }

    private func pinView(idx: Int, pin: MapPin, fit: FitRect) -> some View {
        let px = fit.origin.x + CGFloat(pin.clampedX) * fit.size.width
        let py = fit.origin.y + CGFloat(pin.clampedY) * fit.size.height
        return Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .position(x: px, y: py)
            .help(pin.label ?? pin.locationId.rawValue)
            .onTapGesture { tabs.open(.entity(pin.locationId)) }
            .gesture(pinDragGesture(idx: idx, fit: fit))
            .contextMenu {
                Button(role: .destructive) { deletePin(idx: idx) } label: { Text("Delete pin") }
            }
    }

    // MARK: - gestures

    private func panGesture(fit: FitRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                committedOffset = CGSize(width: committedOffset.width + value.translation.width,
                                         height: committedOffset.height + value.translation.height)
                dragOffset = .zero
            }
    }

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = MapGeometry.clamp(scale: value.magnification * scale)
            }
            .onEnded { _ in /* leave scale as-is */ }
    }

    private func pinDragGesture(idx: Int, fit: FitRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard var d = doc, idx < d.pins.count else { return }
                if pinDragBaseline[idx] == nil {
                    pinDragBaseline[idx] = CGPoint(x: d.pins[idx].x, y: d.pins[idx].y)
                }
                guard let base = pinDragBaseline[idx] else { return }
                let dx = Double(value.translation.width) / fit.size.width / scale
                let dy = Double(value.translation.height) / fit.size.height / scale
                d.pins[idx].x = MapGeometry.clampNormalized(Double(base.x) + dx)
                d.pins[idx].y = MapGeometry.clampNormalized(Double(base.y) + dy)
                doc = d
            }
            .onEnded { _ in
                pinDragBaseline[idx] = nil
                if let d = doc, let store = session.store {
                    try? store.saveMap(d, name: name)
                }
            }
    }

    // MARK: - helpers (load/add/delete)

    private func load() {
        guard let store = session.store else { loadError = "No world open"; return }
        do {
            let d = try store.loadMap(named: name)
            doc = d
            let imageURL = store.world.folder.appendingPathComponent("maps").appendingPathComponent(d.image)
            image = NSImage(contentsOf: imageURL)
            if image == nil { loadError = "Image \(d.image) could not be loaded" }
        } catch {
            loadError = "Failed to load map: \(error)"
        }
    }

    private func addPin(at normalized: CGPoint, locationID: EntityID) {
        guard var d = doc, let store = session.store else { return }
        let label = store.entities.first(where: { $0.id == locationID })?.name
        d.pins.append(MapPin(x: Double(normalized.x), y: Double(normalized.y),
                             locationId: locationID, label: label))
        try? store.saveMap(d, name: name)
        doc = d
    }

    private func deletePin(idx: Int) {
        guard var d = doc, idx < d.pins.count, let store = session.store else { return }
        d.pins.remove(at: idx)
        try? store.saveMap(d, name: name)
        doc = d
    }

    private func resetView() {
        scale = 1.0
        committedOffset = .zero
        dragOffset = .zero
    }

    // MARK: - layout

    struct FitRect {
        let origin: CGPoint
        let size: CGSize
    }

    private func aspectFit(imageSize: CGSize, container: CGSize) -> FitRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return FitRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (container.width - size.width) / 2,
                             y: (container.height - size.height) / 2)
        return FitRect(origin: origin, size: size)
    }

    private func normalize(_ point: CGPoint, in fit: FitRect) -> CGPoint {
        let relX = (point.x - fit.origin.x) / fit.size.width
        let relY = (point.y - fit.origin.y) / fit.size.height
        return CGPoint(x: MapGeometry.clampNormalized(relX), y: MapGeometry.clampNormalized(relY))
    }
}

// MARK: - ⌘scroll wheel catcher

private struct WheelZoomCatcher: NSViewRepresentable {
    @Binding var scale: Double

    func makeNSView(context: Context) -> NSView {
        let v = WheelView()
        v.onWheel = { event in
            guard event.modifierFlags.contains(.command) else { return false }
            let delta = event.scrollingDeltaY
            if abs(delta) < 0.01 { return false }
            scale = MapGeometry.scaleStep(current: scale, deltaY: Double(delta))
            return true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WheelView: NSView {
    var onWheel: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        if onWheel?(event) == true { return }
        super.scrollWheel(with: event)
    }
}

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

    var body: some View {
        Group {
            if let doc, let image {
                GeometryReader { geo in
                    let fit = aspectFit(imageSize: image.size, container: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: fit.size.width, height: fit.size.height)
                            .offset(x: fit.origin.x, y: fit.origin.y)
                            .gesture(
                                SpatialTapGesture(coordinateSpace: .local)
                                    .modifiers(.command)
                                    .onEnded { event in
                                        pendingPinNormalized = normalize(event.location, in: fit)
                                    }
                            )
                        ForEach(Array(doc.pins.enumerated()), id: \.offset) { _, pin in
                            pinView(pin: pin, fit: fit)
                        }
                    }
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
    }

    // MARK: - data

    private func load() {
        guard let store = session.store else { loadError = "No world open"; return }
        do {
            let d = try store.loadMap(named: name)
            doc = d
            let imageURL = store.world.folder
                .appendingPathComponent("maps")
                .appendingPathComponent(d.image)
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

    // MARK: - layout

    private struct FitRect {
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
        return CGPoint(x: min(1, max(0, relX)), y: min(1, max(0, relY)))
    }

    private func pinView(pin: MapPin, fit: FitRect) -> some View {
        let px = fit.origin.x + CGFloat(pin.clampedX) * fit.size.width
        let py = fit.origin.y + CGFloat(pin.clampedY) * fit.size.height
        return Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .position(x: px, y: py)
            .help(pin.label ?? pin.locationId.rawValue)
            .onTapGesture { tabs.open(.entity(pin.locationId)) }
    }
}

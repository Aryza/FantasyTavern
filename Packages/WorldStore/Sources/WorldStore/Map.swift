import Foundation
import EntityModel

public struct MapPin: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var locationId: EntityID
    public var label: String?

    public init(x: Double, y: Double, locationId: EntityID, label: String? = nil) {
        self.x = x
        self.y = y
        self.locationId = locationId
        self.label = label
    }

    public var clampedX: Double { min(1.0, max(0.0, x)) }
    public var clampedY: Double { min(1.0, max(0.0, y)) }
}

public struct MapLayer: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var visible: Bool
    public var pins: [MapPin]

    public init(id: String, name: String, visible: Bool = true, pins: [MapPin] = []) {
        self.id = id
        self.name = name
        self.visible = visible
        self.pins = pins
    }
}

public struct MapDoc: Equatable, Sendable {
    public var image: String
    public var layers: [MapLayer]

    public init(image: String, layers: [MapLayer] = [MapLayer(id: "default", name: "Default")]) {
        self.image = image
        self.layers = layers.isEmpty
            ? [MapLayer(id: "default", name: "Default")]
            : layers
    }

    public var allPins: [MapPin] { layers.flatMap(\.pins) }
    public var visiblePins: [MapPin] { layers.filter(\.visible).flatMap(\.pins) }
}

extension MapDoc: Codable {
    private enum CodingKeys: String, CodingKey {
        case image, layers, pins
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let image = try c.decode(String.self, forKey: .image)
        if let layers = try c.decodeIfPresent([MapLayer].self, forKey: .layers), !layers.isEmpty {
            self.init(image: image, layers: layers)
            return
        }
        if let legacyPins = try c.decodeIfPresent([MapPin].self, forKey: .pins) {
            self.init(image: image, layers: [MapLayer(id: "default", name: "Default", visible: true, pins: legacyPins)])
            return
        }
        self.init(image: image)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(image, forKey: .image)
        try c.encode(layers, forKey: .layers)
    }
}

public extension MapDoc {
    func layer(id: String) -> MapLayer? {
        layers.first { $0.id == id }
    }

    @discardableResult
    mutating func addLayer() -> String {
        let id = UUID().uuidString
        let n = layers.count + 1
        layers.append(MapLayer(id: id, name: "Layer \(n)"))
        return id
    }

    @discardableResult
    mutating func removeLayer(id: String) -> Bool {
        guard layers.count > 1, let idx = layers.firstIndex(where: { $0.id == id }) else { return false }
        layers.remove(at: idx)
        return true
    }

    mutating func renameLayer(id: String, to newName: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].name = newName
    }

    mutating func setVisibility(id: String, visible: Bool) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].visible = visible
    }

    mutating func addPin(_ pin: MapPin, toLayer id: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].pins.append(pin)
    }
}

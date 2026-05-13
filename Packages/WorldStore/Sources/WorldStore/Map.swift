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

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

public struct MapDoc: Equatable, Codable, Sendable {
    public var image: String
    public var pins: [MapPin]

    public init(image: String, pins: [MapPin] = []) {
        self.image = image
        self.pins = pins
    }
}

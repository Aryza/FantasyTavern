import XCTest
import EntityModel
@testable import WorldStore

final class MapTests: XCTestCase {
    func test_mapPin_clampedAccessors() {
        let pin = MapPin(x: 1.5, y: -0.2, locationId: EntityID("a"), label: nil)
        XCTAssertEqual(pin.clampedX, 1.0)
        XCTAssertEqual(pin.clampedY, 0.0)
    }

    func test_mapDoc_codableRoundTrip_layers() throws {
        let pin = MapPin(x: 0.4, y: 0.6, locationId: EntityID("silvermoon"), label: "Silvermoon")
        let layer = MapLayer(id: "default", name: "Default", visible: true, pins: [pin])
        let original = MapDoc(image: "overworld.png", layers: [layer])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MapDoc.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_mapDoc_legacyPinsDecode_intoDefaultLayer() throws {
        let json = #"{"image":"overworld.png","pins":[{"x":0.5,"y":0.5,"locationId":"silvermoon","label":"Silvermoon"}]}"#
        let decoded = try JSONDecoder().decode(MapDoc.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.layers.count, 1)
        XCTAssertEqual(decoded.layers[0].id, "default")
        XCTAssertEqual(decoded.layers[0].pins.count, 1)
        XCTAssertEqual(decoded.layers[0].pins[0].locationId.rawValue, "silvermoon")
    }

    func test_mapDoc_emptyDecode_singleEmptyDefaultLayer() throws {
        let json = #"{"image":"overworld.png"}"#
        let decoded = try JSONDecoder().decode(MapDoc.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.layers.count, 1)
        XCTAssertTrue(decoded.layers[0].pins.isEmpty)
    }

    func test_mapDoc_encode_omitsLegacyPinsKey() throws {
        let doc = MapDoc(image: "x.png", layers: [MapLayer(id: "default", name: "Default", visible: true, pins: [])])
        let data = try JSONEncoder().encode(doc)
        // Re-decode as a generic dictionary and assert there is no top-level "pins" key.
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertNil(obj?["pins"], "Top-level legacy 'pins' key must not be emitted")
        XCTAssertNotNil(obj?["layers"])
    }

    func test_mapDoc_allPins_flattens() {
        let l1 = MapLayer(id: "a", name: "A", visible: true,
                          pins: [MapPin(x: 0, y: 0, locationId: EntityID("p1"))])
        let l2 = MapLayer(id: "b", name: "B", visible: false,
                          pins: [MapPin(x: 0, y: 0, locationId: EntityID("p2"))])
        let doc = MapDoc(image: "x.png", layers: [l1, l2])
        XCTAssertEqual(doc.allPins.map(\.locationId.rawValue), ["p1", "p2"])
        XCTAssertEqual(doc.visiblePins.map(\.locationId.rawValue), ["p1"])
    }
}

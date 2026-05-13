import XCTest
import EntityModel
import WorldStore
@testable import FantasyTavernApp

final class MapLayerMutationTests: XCTestCase {
    private func makeDoc() -> MapDoc {
        MapDoc(image: "x.png", layers: [MapLayer(id: "default", name: "Default")])
    }

    func test_addLayer_appendsAndUniqueName() {
        var doc = makeDoc()
        let id1 = doc.addLayer()
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.layers.last?.name, "Layer 2")
        XCTAssertEqual(doc.layers.last?.id, id1)
        let id2 = doc.addLayer()
        XCTAssertEqual(doc.layers.last?.name, "Layer 3")
        XCTAssertNotEqual(id1, id2)
    }

    func test_removeLayer_blockedWhenLast() {
        var doc = makeDoc()
        let removed = doc.removeLayer(id: "default")
        XCTAssertFalse(removed)
        XCTAssertEqual(doc.layers.count, 1)
    }

    func test_removeLayer_succeedsForExtra() {
        var doc = makeDoc()
        let added = doc.addLayer()
        XCTAssertTrue(doc.removeLayer(id: added))
        XCTAssertEqual(doc.layers.count, 1)
    }

    func test_renameLayer_updatesName() {
        var doc = makeDoc()
        doc.renameLayer(id: "default", to: "Political")
        XCTAssertEqual(doc.layers.first?.name, "Political")
    }

    func test_addPin_intoSpecificLayer() {
        var doc = makeDoc()
        let added = doc.addLayer()
        let pin = MapPin(x: 0.5, y: 0.5, locationId: EntityID("loc"))
        doc.addPin(pin, toLayer: added)
        XCTAssertEqual(doc.layer(id: added)?.pins.count, 1)
    }

    func test_setVisibility_togglesLayer() {
        var doc = makeDoc()
        doc.setVisibility(id: "default", visible: false)
        XCTAssertFalse(doc.layer(id: "default")?.visible ?? true)
    }
}

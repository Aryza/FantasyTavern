import XCTest
import EntityModel
import SearchIndex
@testable import FantasyTavernApp

final class PaletteControllerTests: XCTestCase {
    private func makeController() -> (PaletteController, WorldSession, TabsModel, () -> URL) {
        let session = WorldSession()
        let tabs = TabsModel()
        let controller = PaletteController(session: session, tabs: tabs)
        let tmp = { () -> URL in
            let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            try? #"{"name":"T"}"#.write(to: u.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
            return u
        }
        return (controller, session, tabs, tmp)
    }

    func test_show_clearsQueryAndSelection() {
        let (c, _, _, _) = makeController()
        c.query = "stale"
        c.show()
        XCTAssertTrue(c.isVisible)
        XCTAssertEqual(c.query, "")
        XCTAssertEqual(c.selectionIndex, 0)
    }

    func test_dismiss_hides() {
        let (c, _, _, _) = makeController()
        c.show()
        c.dismiss()
        XCTAssertFalse(c.isVisible)
    }

    func test_findResults_searchesSession() throws {
        let (c, session, _, tmp) = makeController()
        try session.openWorld(at: tmp())
        _ = try session.createEntity(type: .character, name: "Lyra Stormwind")
        c.show()
        c.query = "lyra"
        XCTAssertEqual(c.findResults.map(\.name), ["Lyra Stormwind"])
    }

    func test_actionResults_filter() {
        let (c, _, _, _) = makeController()
        c.show()
        c.query = "> new char"
        XCTAssertTrue(c.isActionMode)
        XCTAssertEqual(c.actionResults.map(\.title), ["New Character"])
    }

    func test_moveSelection_clamps() {
        let (c, session, _, tmp) = makeController()
        try? session.openWorld(at: tmp())
        _ = try? session.createEntity(type: .character, name: "A")
        _ = try? session.createEntity(type: .character, name: "B")
        c.show()
        c.query = "" // returns 2 results
        c.moveSelection(by: 1)
        XCTAssertEqual(c.selectionIndex, 1)
        c.moveSelection(by: 5)
        XCTAssertEqual(c.selectionIndex, 1) // clamped to last
        c.moveSelection(by: -10)
        XCTAssertEqual(c.selectionIndex, 0)
    }

    func test_activateFind_opensSelectedInNewTab() throws {
        let (c, session, tabs, tmp) = makeController()
        try session.openWorld(at: tmp())
        let e = try session.createEntity(type: .character, name: "Lyra")
        c.show()
        c.query = "lyra"
        c.activate(openInPlace: false)
        XCTAssertEqual(tabs.selected, .entity(e.id))
        XCTAssertFalse(c.isVisible)
    }
}

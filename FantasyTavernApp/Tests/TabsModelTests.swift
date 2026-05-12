import XCTest
import EntityModel
@testable import FantasyTavernApp

final class TabsModelTests: XCTestCase {
    func test_open_addsTabAndSelects() {
        let model = TabsModel()
        model.open(EntityID("a"))
        XCTAssertEqual(model.openTabs, [EntityID("a")])
        XCTAssertEqual(model.selected, EntityID("a"))
    }

    func test_openExisting_doesNotDuplicate_andSelects() {
        let model = TabsModel()
        model.open(EntityID("a"))
        model.open(EntityID("b"))
        model.open(EntityID("a"))
        XCTAssertEqual(model.openTabs, [EntityID("a"), EntityID("b")])
        XCTAssertEqual(model.selected, EntityID("a"))
    }

    func test_close_removesAndPicksNeighbor() {
        let model = TabsModel()
        model.open(EntityID("a"))
        model.open(EntityID("b"))
        model.open(EntityID("c"))
        model.close(EntityID("b"))
        XCTAssertEqual(model.openTabs, [EntityID("a"), EntityID("c")])
        XCTAssertEqual(model.selected, EntityID("c"))
    }

    func test_closeLast_clearsSelection() {
        let model = TabsModel()
        model.open(EntityID("a"))
        model.close(EntityID("a"))
        XCTAssertEqual(model.openTabs, [])
        XCTAssertNil(model.selected)
    }

    func test_open_pushesToRecents_mostRecentFirst() {
        let m = TabsModel()
        m.open(EntityID("a"))
        m.open(EntityID("b"))
        m.open(EntityID("c"))
        XCTAssertEqual(m.recents, [EntityID("c"), EntityID("b"), EntityID("a")])
    }

    func test_open_existing_movesItToFrontOfRecents() {
        let m = TabsModel()
        m.open(EntityID("a"))
        m.open(EntityID("b"))
        m.open(EntityID("a"))
        XCTAssertEqual(m.recents, [EntityID("a"), EntityID("b")])
    }

    func test_recents_cappedAtTen() {
        let m = TabsModel()
        for i in 0..<15 { m.open(EntityID("e\(i)")) }
        XCTAssertEqual(m.recents.count, 10)
        XCTAssertEqual(m.recents.first, EntityID("e14"))
    }
}

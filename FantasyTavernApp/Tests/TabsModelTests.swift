import XCTest
import EntityModel
@testable import FantasyTavernApp

final class TabsModelTests: XCTestCase {
    private func e(_ s: String) -> TabContent { .entity(EntityID(s)) }

    func test_open_addsTabAndSelects() {
        let model = TabsModel()
        model.open(e("a"))
        XCTAssertEqual(model.openTabs, [e("a")])
        XCTAssertEqual(model.selected, e("a"))
    }

    func test_openExisting_doesNotDuplicate_andSelects() {
        let model = TabsModel()
        model.open(e("a")); model.open(e("b")); model.open(e("a"))
        XCTAssertEqual(model.openTabs, [e("a"), e("b")])
        XCTAssertEqual(model.selected, e("a"))
    }

    func test_close_removesAndPicksNeighbor() {
        let model = TabsModel()
        model.open(e("a")); model.open(e("b")); model.open(e("c"))
        model.close(e("b"))
        XCTAssertEqual(model.openTabs, [e("a"), e("c")])
        XCTAssertEqual(model.selected, e("c"))
    }

    func test_closeLast_clearsSelection() {
        let model = TabsModel()
        model.open(e("a"))
        model.close(e("a"))
        XCTAssertEqual(model.openTabs, [])
        XCTAssertNil(model.selected)
    }

    func test_open_pushesToRecents_mostRecentFirst() {
        let m = TabsModel()
        m.open(e("a")); m.open(e("b")); m.open(e("c"))
        XCTAssertEqual(m.recents, [e("c"), e("b"), e("a")])
    }

    func test_open_existing_movesItToFrontOfRecents() {
        let m = TabsModel()
        m.open(e("a")); m.open(e("b")); m.open(e("a"))
        XCTAssertEqual(m.recents, [e("a"), e("b")])
    }

    func test_recents_cappedAtTen() {
        let m = TabsModel()
        for i in 0..<15 { m.open(e("e\(i)")) }
        XCTAssertEqual(m.recents.count, 10)
        XCTAssertEqual(m.recents.first, e("e14"))
    }

    func test_open_timelineAndMap_distinctTabs() {
        let m = TabsModel()
        m.open(.timeline)
        m.open(.map("overworld"))
        XCTAssertEqual(m.openTabs, [.timeline, .map("overworld")])
        XCTAssertEqual(m.selected, .map("overworld"))
    }
}

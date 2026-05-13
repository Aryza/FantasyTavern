import XCTest
import EntityModel
@testable import FantasyTavernApp

final class WikiAutocompleteControllerTests: XCTestCase {
    private func entities() -> [Entity] {
        [
            Entity(id: EntityID("lyra"),    type: .character, name: "Lyra Stormwind"),
            Entity(id: EntityID("magnus"),  type: .character, name: "Magnus Blackthorn"),
            Entity(id: EntityID("silver"),  type: .location,  name: "Silvermoon"),
        ]
    }

    func test_noTrigger_inactive() {
        let c = WikiAutocompleteController()
        c.update(text: "hello world", caret: 5, entities: entities())
        XCTAssertFalse(c.isActive)
        XCTAssertTrue(c.suggestions.isEmpty)
    }

    func test_triggerActive_afterDoubleBracket() {
        let c = WikiAutocompleteController()
        c.update(text: "see [[ly", caret: 8, entities: entities())
        XCTAssertTrue(c.isActive)
        XCTAssertEqual(c.query, "ly")
        XCTAssertEqual(c.suggestions.map(\.id.rawValue), ["lyra"])
    }

    func test_emptyQuery_listsAll() {
        let c = WikiAutocompleteController()
        c.update(text: "[[", caret: 2, entities: entities())
        XCTAssertEqual(c.suggestions.count, 3)
    }

    func test_closingBracket_deactivates() {
        let c = WikiAutocompleteController()
        c.update(text: "[[lyra]", caret: 7, entities: entities())
        XCTAssertFalse(c.isActive)
    }

    func test_moveSelection_clamps() {
        let c = WikiAutocompleteController()
        c.update(text: "[[", caret: 2, entities: entities())
        c.move(by: 1)
        XCTAssertEqual(c.selectionIndex, 1)
        c.move(by: 10)
        XCTAssertEqual(c.selectionIndex, 2)
        c.move(by: -100)
        XCTAssertEqual(c.selectionIndex, 0)
    }

    func test_acceptCurrent_returnsInsertion() {
        let c = WikiAutocompleteController()
        c.update(text: "see [[ly", caret: 8, entities: entities())
        let insertion = c.acceptCurrent()
        XCTAssertEqual(insertion?.replacement, "[[Lyra Stormwind]]")
        // replacement range covers the existing "[[ly" trigger (4..<8)
        XCTAssertEqual(insertion?.range, NSRange(location: 4, length: 4))
    }
}

import XCTest
import EntityModel
@testable import WikiLinks

final class BacklinkIndexTests: XCTestCase {
    func test_buildsIncomingLinks() {
        let entities = [
            Entity(id: EntityID("a"), type: .character, name: "A", body: "see [[B]] and [[C]]"),
            Entity(id: EntityID("b"), type: .character, name: "B", body: "back to [[A]]"),
            Entity(id: EntityID("c"), type: .character, name: "C", body: ""),
        ]
        let index = BacklinkIndex(entities: entities)
        XCTAssertEqual(index.sources(linkingTo: EntityID("a")), [EntityID("b")])
        XCTAssertEqual(index.sources(linkingTo: EntityID("b")), [EntityID("a")])
        XCTAssertEqual(index.sources(linkingTo: EntityID("c")), [EntityID("a")])
    }

    func test_ignoresDanglingLinks() {
        let entities = [
            Entity(id: EntityID("a"), type: .character, name: "A", body: "[[Nobody]]"),
        ]
        let index = BacklinkIndex(entities: entities)
        XCTAssertEqual(index.sources(linkingTo: EntityID("nobody")), [])
    }
}

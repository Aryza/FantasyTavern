import XCTest
import EntityModel
@testable import SchemaRegistry

final class DefaultSchemasTests: XCTestCase {
    func test_character_hasRaceAgeAlignmentStatus() {
        let fields = DefaultSchemas.fields(for: .character)
        XCTAssertEqual(fields.map(\.key), ["race", "age", "alignment", "status"])
        XCTAssertEqual(fields.first(where: { $0.key == "alignment" })?.type, .enum)
        XCTAssertEqual(fields.first(where: { $0.key == "age" })?.type, .int)
    }

    func test_location_hasKindPopulationClimate() {
        let keys = DefaultSchemas.fields(for: .location).map(\.key)
        XCTAssertEqual(keys, ["kind", "population", "climate"])
    }

    func test_item_hasRarityAttunement() {
        let keys = DefaultSchemas.fields(for: .item).map(\.key)
        XCTAssertEqual(keys, ["rarity", "attunement"])
    }

    func test_lore_hasEmptySchema() {
        XCTAssertEqual(DefaultSchemas.fields(for: .lore), [])
    }

    func test_language_hasFamily() {
        XCTAssertEqual(DefaultSchemas.fields(for: .language).map(\.key), ["family"])
    }

    func test_journal_hasDate() {
        let f = DefaultSchemas.fields(for: .journal)
        XCTAssertEqual(f.map(\.key), ["date"])
        XCTAssertEqual(f.first?.type, .date)
    }

    func test_timelineEvent_hasDate() {
        XCTAssertEqual(DefaultSchemas.fields(for: .timelineEvent).map(\.key), ["date"])
    }

    func test_schema_aliasIsDictionary() {
        let schema: Schema = [:]
        XCTAssertEqual(schema.count, 0)
    }
}

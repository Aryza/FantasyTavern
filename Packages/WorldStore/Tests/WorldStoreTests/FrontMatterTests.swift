import XCTest
import EntityModel
@testable import WorldStore

final class FrontMatterTests: XCTestCase {
    let sample = """
    ---
    id: lyra-stormwind
    type: character
    name: Lyra Stormwind
    tags: [noble, ranger]
    fields:
      race: half-elf
      age: 87
    created: 2026-05-12T10:00:00Z
    updated: 2026-05-12T11:30:00Z
    ---
    Half-elven ranger from [[Silvermoon]].
    """

    func test_parse_extractsBodyAndFrontMatter() throws {
        let parsed = try FrontMatter.parse(sample)
        XCTAssertEqual(parsed.entity.id.rawValue, "lyra-stormwind")
        XCTAssertEqual(parsed.entity.type, .character)
        XCTAssertEqual(parsed.entity.name, "Lyra Stormwind")
        XCTAssertEqual(parsed.entity.tags, ["noble", "ranger"])
        XCTAssertEqual(parsed.entity.fields["race"], .string("half-elf"))
        XCTAssertEqual(parsed.entity.fields["age"], .int(87))
        XCTAssertEqual(parsed.entity.body, "Half-elven ranger from [[Silvermoon]].")
    }

    func test_parse_missingFrontMatter_throws() {
        XCTAssertThrowsError(try FrontMatter.parse("no front matter here"))
    }

    func test_serialize_roundTrip() throws {
        let parsed = try FrontMatter.parse(sample)
        let serialized = try FrontMatter.serialize(parsed.entity)
        let again = try FrontMatter.parse(serialized)
        XCTAssertEqual(parsed.entity, again.entity)
    }

    func test_serialize_includesFrontMatterDelimiters() throws {
        let entity = Entity(
            id: EntityID("x"), type: .character, name: "X",
            created: Date(timeIntervalSince1970: 0), updated: Date(timeIntervalSince1970: 0)
        )
        let out = try FrontMatter.serialize(entity)
        XCTAssertTrue(out.hasPrefix("---\n"))
        XCTAssertTrue(out.contains("\n---\n"))
    }
}

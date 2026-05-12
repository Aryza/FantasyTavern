import XCTest
import EntityModel
@testable import SchemaRegistry

final class SchemaLoaderTests: XCTestCase {
    func test_emptyOverrides_returnsDefault() {
        let loaded = SchemaLoader.load(overridesJSON: nil)
        XCTAssertEqual(loaded.fields(for: .character).map(\.key),
                       DefaultSchemas.fields(for: .character).map(\.key))
    }

    func test_overrideReplacesTypeFieldsEntirely() throws {
        let json = """
        {
          "schemaOverrides": {
            "character": [
              { "key": "house", "label": "House", "type": "string" }
            ]
          }
        }
        """
        let data = json.data(using: .utf8)!
        let loaded = SchemaLoader.load(overridesJSON: data)
        XCTAssertEqual(loaded.fields(for: .character).map(\.key), ["house"])
        XCTAssertEqual(loaded.fields(for: .location).map(\.key),
                       DefaultSchemas.fields(for: .location).map(\.key))
    }

    func test_overrideWithoutSchemaOverridesKey_returnsDefault() throws {
        let data = #"{"name":"Test"}"#.data(using: .utf8)!
        let loaded = SchemaLoader.load(overridesJSON: data)
        XCTAssertEqual(loaded.fields(for: .character).map(\.key),
                       DefaultSchemas.fields(for: .character).map(\.key))
    }

    func test_malformedJSON_returnsDefault() {
        let data = "not json".data(using: .utf8)!
        let loaded = SchemaLoader.load(overridesJSON: data)
        XCTAssertEqual(loaded, DefaultSchemas.schema)
    }
}

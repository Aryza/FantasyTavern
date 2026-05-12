import XCTest
@testable import SchemaRegistry

final class FieldDefinitionTests: XCTestCase {
    func test_stringField() {
        let f = FieldDefinition(key: "race", label: "Race", type: .string)
        XCTAssertEqual(f.key, "race")
        XCTAssertEqual(f.label, "Race")
        XCTAssertEqual(f.type, .string)
        XCTAssertNil(f.options)
    }

    func test_enumField_carriesOptions() {
        let f = FieldDefinition(key: "alignment", label: "Alignment", type: .enum, options: ["LG","NG","CG"])
        XCTAssertEqual(f.options, ["LG","NG","CG"])
    }

    func test_fieldType_codable_rawValues() throws {
        let types: [FieldType] = [.string, .int, .bool, .date, .enum, .ref]
        let encoded = try JSONEncoder().encode(types)
        let decoded = try JSONDecoder().decode([FieldType].self, from: encoded)
        XCTAssertEqual(types, decoded)
    }
}

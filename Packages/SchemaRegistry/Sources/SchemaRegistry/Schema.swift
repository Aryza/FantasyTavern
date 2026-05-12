import Foundation
import EntityModel

/// A schema maps an entity type's raw value (e.g. "character") to its ordered field definitions.
public typealias Schema = [String: [FieldDefinition]]

public extension Schema {
    func fields(for type: EntityType) -> [FieldDefinition] {
        self[type.rawValue] ?? []
    }
}

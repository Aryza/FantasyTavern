import Foundation
import EntityModel

public enum SchemaLoader {
    private struct Envelope: Decodable {
        let schemaOverrides: [String: [FieldDefinition]]?
    }

    /// Override rule: if a type key is present in `schemaOverrides`, it replaces the default
    /// field list for that type entirely. Missing keys fall back to defaults.
    public static func load(overridesJSON data: Data?) -> Schema {
        var result = DefaultSchemas.schema
        guard let data,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let overrides = envelope.schemaOverrides
        else { return result }
        for (key, defs) in overrides {
            result[key] = defs
        }
        return result
    }
}

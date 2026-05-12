import Foundation
import EntityModel

public enum DefaultSchemas {
    public static let schema: Schema = [
        EntityType.character.rawValue: [
            FieldDefinition(key: "race",      label: "Race",      type: .string),
            FieldDefinition(key: "age",       label: "Age",       type: .int),
            FieldDefinition(key: "alignment", label: "Alignment", type: .enum,
                            options: ["LG","NG","CG","LN","TN","CN","LE","NE","CE"]),
            FieldDefinition(key: "status",    label: "Status",    type: .enum,
                            options: ["alive","dead","unknown"]),
        ],
        EntityType.location.rawValue: [
            FieldDefinition(key: "kind",       label: "Kind",       type: .enum,
                            options: ["city","town","village","dungeon","region","landmark"]),
            FieldDefinition(key: "population", label: "Population", type: .int),
            FieldDefinition(key: "climate",    label: "Climate",    type: .string),
        ],
        EntityType.item.rawValue: [
            FieldDefinition(key: "rarity",     label: "Rarity",     type: .enum,
                            options: ["common","uncommon","rare","very-rare","legendary","artifact"]),
            FieldDefinition(key: "attunement", label: "Attunement", type: .bool),
        ],
        EntityType.lore.rawValue: [],
        EntityType.language.rawValue: [
            FieldDefinition(key: "family", label: "Family", type: .string),
        ],
        EntityType.journal.rawValue: [
            FieldDefinition(key: "date", label: "Date", type: .date),
        ],
        EntityType.timelineEvent.rawValue: [
            FieldDefinition(key: "date", label: "Date", type: .date),
        ],
    ]

    public static func fields(for type: EntityType) -> [FieldDefinition] {
        schema.fields(for: type)
    }
}

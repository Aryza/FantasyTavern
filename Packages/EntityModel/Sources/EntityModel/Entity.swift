import Foundation

public struct Entity: Equatable, Codable, Sendable {
    public var id: EntityID
    public var type: EntityType
    public var name: String
    public var tags: [String]
    public var fields: [String: FieldValue]
    public var body: String
    public var created: Date
    public var updated: Date

    public init(
        id: EntityID,
        type: EntityType,
        name: String,
        tags: [String] = [],
        fields: [String: FieldValue] = [:],
        body: String = "",
        created: Date = Date(),
        updated: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.tags = tags
        self.fields = fields
        self.body = body
        self.created = created
        self.updated = updated
    }
}

public enum FieldValue: Equatable, Codable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case date(Date)
    case ref(EntityID)
    case list([FieldValue])
}

import Foundation

public enum FieldType: String, Codable, Equatable, Sendable, CaseIterable {
    case string
    case int
    case bool
    case date
    case `enum`
    case ref
}

public struct FieldDefinition: Equatable, Codable, Sendable {
    public let key: String
    public let label: String
    public let type: FieldType
    public let options: [String]?

    public init(key: String, label: String, type: FieldType, options: [String]? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.options = options
    }
}

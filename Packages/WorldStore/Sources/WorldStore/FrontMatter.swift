import Foundation
import Yams
import EntityModel

public enum FrontMatterError: Error {
    case missingDelimiters
    case malformedYAML(String)
    case missingRequiredField(String)
}

public struct ParsedEntityFile {
    public let entity: Entity
}

public enum FrontMatter {
    private static let delimiter = "---"
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ source: String) throws -> ParsedEntityFile {
        guard source.hasPrefix("\(delimiter)\n") else { throw FrontMatterError.missingDelimiters }
        let afterOpen = source.dropFirst(delimiter.count + 1)
        guard let endRange = afterOpen.range(of: "\n\(delimiter)\n") ?? afterOpen.range(of: "\n\(delimiter)") else {
            throw FrontMatterError.missingDelimiters
        }
        let yamlText = String(afterOpen[..<endRange.lowerBound])
        let body = String(afterOpen[endRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let yamlNode: Any
        do { yamlNode = try Yams.load(yaml: yamlText) ?? [:] }
        catch { throw FrontMatterError.malformedYAML("\(error)") }

        guard let dict = yamlNode as? [String: Any] else {
            throw FrontMatterError.malformedYAML("front matter is not a mapping")
        }

        let idStr = try required(dict, "id") as String
        let typeStr = try required(dict, "type") as String
        guard let type = EntityType(rawValue: typeStr) else {
            throw FrontMatterError.malformedYAML("unknown type \(typeStr)")
        }
        let name = try required(dict, "name") as String
        let tags = (dict["tags"] as? [Any])?.compactMap({ $0 as? String })
            ?? (dict["tags"] as? [String])
            ?? []
        let fields = parseFields(dict["fields"] as? [String: Any] ?? [:])
        let created = parseDate(dict["created"]) ?? Date()
        let updated = parseDate(dict["updated"]) ?? created

        let entity = Entity(
            id: EntityID(idStr), type: type, name: name,
            tags: tags, fields: fields, body: body,
            created: created, updated: updated
        )
        return ParsedEntityFile(entity: entity)
    }

    public static func serialize(_ entity: Entity) throws -> String {
        var dict: [String: Any] = [
            "id": entity.id.rawValue,
            "type": entity.type.rawValue,
            "name": entity.name,
            "tags": entity.tags,
            "fields": serializeFields(entity.fields),
            "created": iso.string(from: entity.created),
            "updated": iso.string(from: entity.updated),
        ]
        if (dict["tags"] as? [String])?.isEmpty == true { dict["tags"] = [] }
        let yamlString = try Yams.dump(object: dict, sortKeys: true)
        let trimmedYaml = yamlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return "---\n\(trimmedYaml)\n---\n\(entity.body)\n"
    }

    // MARK: - helpers

    private static func required<T>(_ dict: [String: Any], _ key: String) throws -> T {
        guard let any = dict[key], let value = any as? T else {
            throw FrontMatterError.missingRequiredField(key)
        }
        return value
    }

    private static func parseDate(_ any: Any?) -> Date? {
        if let d = any as? Date { return d }
        if let s = any as? String { return iso.date(from: s) }
        return nil
    }

    private static func parseFields(_ raw: [String: Any]) -> [String: FieldValue] {
        var out: [String: FieldValue] = [:]
        for (k, v) in raw {
            if let s = v as? String { out[k] = .string(s) }
            else if let i = v as? Int { out[k] = .int(i) }
            else if let b = v as? Bool { out[k] = .bool(b) }
            else if let d = v as? Date { out[k] = .date(d) }
        }
        return out
    }

    private static func serializeFields(_ fields: [String: FieldValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in fields {
            switch v {
            case .string(let s): out[k] = s
            case .int(let i): out[k] = i
            case .bool(let b): out[k] = b
            case .date(let d): out[k] = iso.string(from: d)
            case .ref(let id): out[k] = id.rawValue
            case .list: continue // Plan 1: skip list fields in serialization
            }
        }
        return out
    }
}

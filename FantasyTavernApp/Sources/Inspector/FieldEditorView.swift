import SwiftUI
import EntityModel
import SchemaRegistry

/// Pure-logic helper: convert FieldValue <-> String for inspector forms.
enum FieldFormatter {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func display(_ value: FieldValue?, type: FieldType) -> String {
        guard let value else { return "" }
        switch (value, type) {
        case (.string(let s), .string), (.string(let s), .enum): return s
        case (.int(let i), .int):                                return String(i)
        case (.bool(let b), .bool):                              return String(b)
        case (.date(let d), .date):                              return iso.string(from: d)
        case (.ref(let id), .ref):                               return id.rawValue
        default: return ""
        }
    }

    static func parse(_ text: String, as type: FieldType) -> FieldValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        switch type {
        case .string, .enum: return .string(trimmed)
        case .int:           return Int(trimmed).map(FieldValue.int)
        case .bool:          return Bool(trimmed).map(FieldValue.bool)
        case .date:          return iso.date(from: trimmed).map(FieldValue.date)
        case .ref:           return .ref(EntityID(trimmed))
        }
    }
}

/// SwiftUI widget for one schema field. Reads/writes the entity's `fields` dict by key.
struct FieldEditorView: View {
    let definition: FieldDefinition
    @Binding var value: FieldValue?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(definition.label).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
            switch definition.type {
            case .string:
                TextField("", text: stringBinding).textFieldStyle(.roundedBorder)
            case .int:
                TextField("", text: stringBinding).textFieldStyle(.roundedBorder)
            case .bool:
                Toggle("", isOn: boolBinding).labelsHidden()
            case .date:
                TextField("YYYY-MM-DDThh:mm:ssZ", text: stringBinding).textFieldStyle(.roundedBorder)
            case .enum:
                Picker("", selection: stringBinding) {
                    Text("—").tag("")
                    ForEach(definition.options ?? [], id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .labelsHidden()
            case .ref:
                TextField("entity id", text: stringBinding).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { FieldFormatter.display(value, type: definition.type) },
            set: { value = FieldFormatter.parse($0, as: definition.type) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: {
                if case .bool(let b) = value { return b }
                return false
            },
            set: { value = .bool($0) }
        )
    }
}

import SwiftUI
import EntityModel
import SchemaRegistry

struct InspectorView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    @Binding var tags: [String]
    @Binding var fields: [String: FieldValue]

    let entity: Entity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let defs = session.fields(for: entity.type)
                if !defs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fields").font(.headline)
                        ForEach(defs, id: \.key) { def in
                            FieldEditorView(definition: def, value: fieldBinding(def.key))
                        }
                    }
                }

                TagsEditorView(tags: $tags)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Backlinks").font(.headline)
                    let ids = session.backlinks(to: entity.id)
                    if ids.isEmpty {
                        Text("No incoming links yet.").foregroundStyle(.secondary).font(.caption)
                    } else {
                        ForEach(ids, id: \.self) { id in
                            Button(name(for: id)) { tabs.open(id) }.buttonStyle(.link)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
    }

    private func fieldBinding(_ key: String) -> Binding<FieldValue?> {
        Binding(
            get: { fields[key] },
            set: { newValue in
                if let newValue { fields[key] = newValue }
                else { fields.removeValue(forKey: key) }
            }
        )
    }

    private func name(for id: EntityID) -> String {
        session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
    }
}

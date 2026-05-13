import SwiftUI
import EntityModel

struct SnapshotPreviewWindow: View {
    @Bindable var session: SnapshotPreviewSession
    @State private var selectedID: EntityID?

    var body: some View {
        NavigationSplitView {
            List {
                if let world = session.store?.world {
                    Section("\(world.name) — \(session.archiveName)") {
                        ForEach(EntityType.allCases, id: \.self) { type in
                            let entries = session.store?.entities(of: type) ?? []
                            DisclosureGroup(title(for: type, count: entries.count)) {
                                ForEach(entries, id: \.id) { entity in
                                    Button(entity.name) { selectedID = entity.id }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
        } detail: {
            if let id = selectedID, let entity = session.store?.entities.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entity.name).font(.title)
                        Text("Type: \(entity.type.rawValue)").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text(entity.body).textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Pick an entity to preview", systemImage: "doc.text")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onDisappear { session.close() }
    }

    private func title(for type: EntityType, count: Int) -> String {
        let base: String
        switch type {
        case .character:     base = "Characters"
        case .location:      base = "Locations"
        case .lore:          base = "Lore"
        case .item:          base = "Items"
        case .language:      base = "Languages"
        case .journal:       base = "Journal"
        case .timelineEvent: base = "Timeline"
        }
        return "\(base) (\(count))"
    }
}

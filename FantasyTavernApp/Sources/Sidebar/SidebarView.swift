import SwiftUI
import EntityModel

struct SidebarView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        List {
            if let world = session.store?.world {
                Section(world.name) {
                    ForEach(EntityType.allCases, id: \.self) { type in
                        let entries = session.store?.entities(of: type) ?? []
                        DisclosureGroup(title(for: type, count: entries.count)) {
                            if entries.isEmpty {
                                Text("No entries yet")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                ForEach(entries, id: \.id) { entity in
                                    Button(entity.name) { tabs.open(.entity(entity.id)) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No world open", systemImage: "globe")
            }
        }
        .listStyle(.sidebar)
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

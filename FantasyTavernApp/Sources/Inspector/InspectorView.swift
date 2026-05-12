import SwiftUI
import EntityModel

struct InspectorView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    let entity: Entity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backlinks").font(.headline)
            let ids = session.backlinks(to: entity.id)
            if ids.isEmpty {
                Text("No incoming links yet.").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(ids, id: \.self) { id in
                    Button(name(for: id)) { tabs.open(id) }.buttonStyle(.link)
                }
            }
            Spacer()
        }
        .padding()
    }

    private func name(for id: EntityID) -> String {
        session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
    }
}

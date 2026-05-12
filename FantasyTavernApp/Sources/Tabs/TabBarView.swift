import SwiftUI
import EntityModel

struct TabBarView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(tabs.openTabs, id: \.self) { id in
                    EditorTab(id: id, label: name(for: id), isSelected: tabs.selected == id,
                              onSelect: { tabs.selected = id },
                              onClose: { tabs.close(id) })
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(height: 32)
    }

    private func name(for id: EntityID) -> String {
        session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
    }
}

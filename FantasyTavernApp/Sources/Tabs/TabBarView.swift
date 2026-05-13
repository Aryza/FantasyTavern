import SwiftUI
import EntityModel

struct TabBarView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(tabs.openTabs, id: \.self) { content in
                    EditorTab(content: content,
                              label: label(for: content),
                              isSelected: tabs.selected == content,
                              onSelect: { tabs.selected = content },
                              onClose: { tabs.close(content) })
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(height: 32)
    }

    private func label(for content: TabContent) -> String {
        switch content {
        case .entity(let id):
            return session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
        case .timeline:
            return "Timeline"
        case .map(let name):
            return "Map: \(name)"
        }
    }
}

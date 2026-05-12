import SwiftUI
import EntityModel

struct ContentView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                TabBarView()
                Divider()
                if let id = tabs.selected, let entity = entity(for: id) {
                    EditorView(entity: entity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No tab open", systemImage: "doc.text",
                                           description: Text("Open an entity from the sidebar."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func entity(for id: EntityID) -> Entity? {
        session.store?.entities.first(where: { $0.id == id })
    }
}

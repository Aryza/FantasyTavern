import SwiftUI
import EntityModel

struct ContentView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 200)
        } detail: {
            VStack(spacing: 0) {
                TabBarView()
                Divider()
                if let id = tabs.selected, let entity = entity(for: id) {
                    HStack(spacing: 0) {
                        EditorView(entity: entity).frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        InspectorView(entity: entity).frame(width: 260)
                    }
                } else {
                    ContentUnavailableView("No tab open", systemImage: "doc.text",
                                           description: Text("Open a character from the sidebar."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func entity(for id: EntityID) -> Entity? {
        session.store?.entities.first(where: { $0.id == id })
    }
}

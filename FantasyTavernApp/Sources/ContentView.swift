import SwiftUI
import EntityModel

struct ContentView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    @Environment(PaletteController.self) private var palette

    var body: some View {
        ZStack {
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
                                               description: Text("Open an entity from the sidebar or press ⌘K."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            CommandPaletteView(controller: palette)
        }
    }

    private func entity(for id: EntityID) -> Entity? {
        session.store?.entities.first(where: { $0.id == id })
    }
}

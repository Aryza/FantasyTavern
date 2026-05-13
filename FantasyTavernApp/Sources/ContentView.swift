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
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            CommandPaletteView(controller: palette)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch tabs.selected {
        case .entity(let id):
            if let entity = session.store?.entities.first(where: { $0.id == id }) {
                EditorView(entity: entity)
            } else {
                ContentUnavailableView("Entity unavailable", systemImage: "exclamationmark.triangle")
            }
        case .timeline:
            TimelineView()
        case .map(let name):
            MapView(name: name)
        case .hexMap(let name):
            HexMapView(name: name)
        case .none:
            ContentUnavailableView("No tab open", systemImage: "doc.text",
                                   description: Text("Open an entity from the sidebar or press ⌘K."))
        }
    }
}

import SwiftUI
import EntityModel

struct SidebarView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        List {
            if let world = session.store?.world {
                Section(world.name) {
                    DisclosureGroup("Characters") {
                        ForEach(session.store?.entities(of: .character) ?? [], id: \.id) { entity in
                            Button(entity.name) { tabs.open(entity.id) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No world open", systemImage: "globe")
            }
        }
        .listStyle(.sidebar)
    }
}

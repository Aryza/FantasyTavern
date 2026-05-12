import SwiftUI
import AppKit
import EntityModel

struct AppCommands: Commands {
    @Binding var session: WorldSession
    @Binding var tabs: TabsModel
    @Bindable var recents = RecentWorlds.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open World…") { openWorld() }
                .keyboardShortcut("o", modifiers: [.command])
            Menu("Open Recent") {
                if recents.urls.isEmpty {
                    Text("No Recent Worlds")
                } else {
                    ForEach(recents.urls, id: \.self) { url in
                        Button(url.lastPathComponent) { tryOpen(url) }
                    }
                    Divider()
                    Button("Clear Menu") { recents.clear() }
                }
            }
            Divider()
            Menu("New") {
                ForEach(EntityType.allCases, id: \.self) { type in
                    Button(label(for: type)) { newEntity(type: type) }
                        .disabled(session.store == nil)
                }
            }
            Button("New Character") { newEntity(type: .character) }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(session.store == nil)
        }
    }

    private func label(for type: EntityType) -> String {
        switch type {
        case .character:     return "Character"
        case .location:      return "Location"
        case .lore:          return "Lore Entry"
        case .item:          return "Item"
        case .language:      return "Language"
        case .journal:       return "Journal Entry"
        case .timelineEvent: return "Timeline Event"
        }
    }

    private func openWorld() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            tryOpen(url)
        }
    }

    private func tryOpen(_ url: URL) {
        do {
            try session.openWorld(at: url)
            recents.add(url)
        } catch {
            NSSound.beep()
        }
    }

    private func newEntity(type: EntityType) {
        if let entity = try? session.createEntity(type: type, name: "Untitled \(label(for: type))") {
            tabs.open(entity.id)
        }
    }
}

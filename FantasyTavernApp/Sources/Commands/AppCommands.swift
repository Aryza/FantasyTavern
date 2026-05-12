import SwiftUI
import AppKit

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
            Button("New Character") { newCharacter() }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(session.store == nil)
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

    private func newCharacter() {
        if let entity = try? session.createCharacter(name: "Untitled Character") {
            tabs.open(entity.id)
        }
    }
}

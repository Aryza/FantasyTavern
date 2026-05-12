import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppCommands: Commands {
    @Binding var session: WorldSession
    @Binding var tabs: TabsModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open World…") { openWorld() }
                .keyboardShortcut("o", modifiers: [.command])
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
            try? session.openWorld(at: url)
        }
    }

    private func newCharacter() {
        if let entity = try? session.createCharacter(name: "Untitled Character") {
            tabs.open(entity.id)
        }
    }
}

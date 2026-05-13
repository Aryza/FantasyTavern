import SwiftUI
import AppKit
import EntityModel
import UniformTypeIdentifiers

struct AppCommands: Commands {
    @Binding var session: WorldSession
    @Binding var tabs: TabsModel
    @Bindable var recents = RecentWorlds.shared
    @Bindable var presenter: SnapshotsPresenter
    @Bindable var hexPresenter: HexMapPresenter

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
                Divider()
                Button("Hex Map…") { hexPresenter.isShowingNew = true }
                    .disabled(session.store == nil)
            }
            Button("New Character") { newEntity(type: .character) }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(session.store == nil)
            Divider()
            Button("Snapshot Now") { session.snapshotNow() }
                .disabled(session.store == nil)
            Button("Show Snapshots…") { presenter.isShowing = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(session.store == nil)
            Divider()
            Menu("Export") {
                Button("Current Entity…") { exportCurrentEntity() }
                    .disabled(currentEntity() == nil)
                Button("Current Entity Type Folder…") { exportCurrentType() }
                    .disabled(currentEntity() == nil)
                Button("Whole World…") { exportWholeWorld() }
                    .disabled(session.store == nil)
            }
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
            tabs.open(.entity(entity.id))
        }
    }

    // MARK: - export

    private func currentEntity() -> Entity? {
        guard case .entity(let id) = tabs.selected else { return nil }
        return session.store?.entities.first(where: { $0.id == id })
    }

    private func exportCurrentEntity() {
        guard let e = currentEntity() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "\(e.id.rawValue).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ExportService.writeEntity(e, to: url)
    }

    private func exportCurrentType() {
        guard let e = currentEntity(), let folder = session.store?.world.folder else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(e.type.folderName).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let src = folder.appendingPathComponent(e.type.folderName)
        try? ExportService.zipFolder(src, to: url)
    }

    private func exportWholeWorld() {
        guard let folder = session.store?.world.folder else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(folder.lastPathComponent).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ExportService.zipFolder(folder, to: url, exclude: [".fantasytavern/*"])
    }
}

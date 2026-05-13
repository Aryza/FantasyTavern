import SwiftUI

@main
struct FantasyTavernAppApp: App {
    @State private var session = WorldSession()
    @State private var tabs = TabsModel()
    @State private var palette: PaletteController
    @State private var snapshots = SnapshotsPresenter()
    @State private var hexPresenter = HexMapPresenter()

    init() {
        let s = WorldSession()
        let t = TabsModel()
        _session = State(initialValue: s)
        _tabs = State(initialValue: t)
        _palette = State(initialValue: PaletteController(session: s, tabs: t))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(tabs)
                .environment(palette)
                .environment(snapshots)
                .environment(hexPresenter)
                .sheet(isPresented: Binding(
                    get: { snapshots.isShowing },
                    set: { snapshots.isShowing = $0 }
                )) {
                    SnapshotsView()
                        .environment(session)
                }
                .sheet(isPresented: Binding(
                    get: { hexPresenter.isShowingNew },
                    set: { hexPresenter.isShowingNew = $0 }
                )) {
                    NewHexMapSheet()
                        .environment(session)
                        .environment(tabs)
                }
        }
        .commands {
            AppCommands(session: $session, tabs: $tabs, presenter: snapshots, hexPresenter: hexPresenter)
            CommandGroup(after: .toolbar) {
                Button("Show Command Palette") { palette.show() }
                    .keyboardShortcut("k", modifiers: [.command])
            }
        }

        WindowGroup("Snapshot Preview", for: URL.self) { $url in
            if let url, let session = try? SnapshotPreviewSession(snapshot: url) {
                SnapshotPreviewWindow(session: session)
                    .navigationTitle("Preview — \(url.lastPathComponent)")
            } else {
                ContentUnavailableView("Failed to load preview", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

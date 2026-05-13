import SwiftUI

@main
struct FantasyTavernAppApp: App {
    @State private var session = WorldSession()
    @State private var tabs = TabsModel()
    @State private var palette: PaletteController
    @State private var snapshots = SnapshotsPresenter()

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
                .sheet(isPresented: Binding(
                    get: { snapshots.isShowing },
                    set: { snapshots.isShowing = $0 }
                )) {
                    SnapshotsView()
                        .environment(session)
                }
        }
        .commands {
            AppCommands(session: $session, tabs: $tabs, presenter: snapshots)
            CommandGroup(after: .toolbar) {
                Button("Show Command Palette") { palette.show() }
                    .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

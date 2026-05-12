import SwiftUI

@main
struct FantasyTavernAppApp: App {
    @State private var session = WorldSession()
    @State private var tabs = TabsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(tabs)
        }
        .commands { AppCommands(session: $session, tabs: $tabs) }
    }
}

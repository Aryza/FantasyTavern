import SwiftUI
import EntityModel

struct AddPinPopover: View {
    @Environment(WorldSession.self) private var session
    let onPick: (EntityID) -> Void

    var body: some View {
        let locations = session.store?.entities(of: .location) ?? []
        VStack(alignment: .leading) {
            Text("Pin location").font(.headline)
            if locations.isEmpty {
                Text("No locations yet.").foregroundStyle(.secondary)
            } else {
                List(locations, id: \.id) { loc in
                    Button(loc.name) { onPick(loc.id) }.buttonStyle(.plain)
                }
                .frame(width: 220, height: 200)
            }
        }
        .padding(12)
    }
}

import SwiftUI

struct MapView: View {
    let name: String
    var body: some View {
        ContentUnavailableView("Map: \(name)", systemImage: "map")
    }
}

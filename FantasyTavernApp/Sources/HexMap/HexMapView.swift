import SwiftUI

struct HexMapView: View {
    let name: String
    var body: some View {
        ContentUnavailableView("Hex Map: \(name) (coming soon)", systemImage: "hexagon")
    }
}

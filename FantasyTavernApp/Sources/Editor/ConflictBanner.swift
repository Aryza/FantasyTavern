import SwiftUI

struct ConflictBanner: View {
    let onReload: () -> Void
    let onKeepMine: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("File changed on disk while you were editing.")
                .font(.callout)
            Spacer()
            Button("Reload from disk", action: onReload)
            Button("Keep my changes", action: onKeepMine)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

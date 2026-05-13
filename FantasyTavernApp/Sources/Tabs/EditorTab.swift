import SwiftUI

struct EditorTab: View {
    let content: TabContent
    let label: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) { Text(label).lineLimit(1) }
                .buttonStyle(.plain)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

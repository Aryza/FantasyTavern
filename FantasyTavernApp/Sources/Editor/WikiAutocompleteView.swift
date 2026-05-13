import SwiftUI
import EntityModel

struct WikiAutocompleteView: View {
    @Bindable var controller: WikiAutocompleteController
    let onAccept: () -> Void

    var body: some View {
        if controller.isActive && !controller.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(controller.suggestions.enumerated()), id: \.element.id) { idx, entity in
                    HStack {
                        Text(entity.name)
                        Spacer()
                        Text(entity.type.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(idx == controller.selectionIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.selectionIndex = idx
                        onAccept()
                    }
                }
            }
            .frame(width: 280)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 8)
        }
    }
}

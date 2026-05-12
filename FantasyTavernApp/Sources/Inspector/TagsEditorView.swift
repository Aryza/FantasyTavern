import SwiftUI

/// Comma-separated tags editor. Stores lower-cased, trimmed, deduped tags.
struct TagsEditorView: View {
    @Binding var tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags").font(.headline)
            TextField("comma, separated", text: textBinding)
                .textFieldStyle(.roundedBorder)
            if !tags.isEmpty {
                HStack {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { tags.joined(separator: ", ") },
            set: { newRaw in
                let parts = newRaw.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                var seen = Set<String>()
                tags = parts.filter { seen.insert($0).inserted }
            }
        )
    }
}

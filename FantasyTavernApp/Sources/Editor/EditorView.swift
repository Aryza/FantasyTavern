import SwiftUI
import EntityModel
import WikiLinks

struct EditorView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    let entity: Entity

    @State private var bodyText: String = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: nameBinding)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(.top, 8).padding(.horizontal, 12)
            Divider()
            MarkdownTextView(
                text: $bodyText,
                resolver: WikiLinkResolver(entities: session.store?.entities ?? []),
                onOpenLink: { tabs.open($0) }
            )
            .onChange(of: bodyText) { _, _ in scheduleSave() }
        }
        .onAppear { bodyText = entity.body }
        .onChange(of: entity.id) { _, _ in bodyText = entity.body }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { entity.name }, set: { new in
            var copy = entity
            copy.name = new
            try? session.save(copy)
        })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let newBody = bodyText
        let target = entity
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            var copy = target
            copy.body = newBody
            try? session.save(copy)
        }
    }
}

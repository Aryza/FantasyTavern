import SwiftUI
import EntityModel
import WikiLinks

struct EditorView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    let entity: Entity

    @State private var nameDraft: String = ""
    @State private var bodyText: String = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(.top, 8).padding(.horizontal, 12)
                .onChange(of: nameDraft) { _, _ in scheduleSave() }
            Divider()
            MarkdownTextView(
                text: $bodyText,
                resolver: WikiLinkResolver(entities: session.store?.entities ?? []),
                onOpenLink: { tabs.open($0) }
            )
            .onChange(of: bodyText) { _, _ in scheduleSave() }
        }
        .onAppear {
            nameDraft = entity.name
            bodyText = entity.body
        }
        .onChange(of: entity.id) { _, _ in
            nameDraft = entity.name
            bodyText = entity.body
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let newName = nameDraft
        let newBody = bodyText
        let target = entity
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            var copy = target
            copy.name = newName
            copy.body = newBody
            try? session.save(copy)
        }
    }
}

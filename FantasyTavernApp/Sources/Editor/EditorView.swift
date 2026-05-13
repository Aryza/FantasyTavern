import SwiftUI
import EntityModel
import WikiLinks

struct EditorView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    let entity: Entity

    @State private var nameDraft: String = ""
    @State private var bodyText: String = ""
    @State private var tags: [String] = []
    @State private var fields: [String: FieldValue] = [:]
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
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
                    onOpenLink: { tabs.open(.entity($0)) }
                )
                .onChange(of: bodyText) { _, _ in scheduleSave() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            InspectorView(tags: $tags, fields: $fields, entity: entity)
                .frame(width: 280)
                .onChange(of: tags) { _, _ in scheduleSave() }
                .onChange(of: fields) { _, _ in scheduleSave() }
        }
        .onAppear { loadDrafts() }
        .onChange(of: entity.id) { _, _ in loadDrafts() }
    }

    private func loadDrafts() {
        nameDraft = entity.name
        bodyText = entity.body
        tags = entity.tags
        fields = entity.fields
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = (nameDraft, bodyText, tags, fields)
        let target = entity
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            var copy = target
            copy.name = snapshot.0
            copy.body = snapshot.1
            copy.tags = snapshot.2
            copy.fields = snapshot.3
            try? session.save(copy)
        }
    }
}

import SwiftUI
import AppKit
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
    @State private var caretLocation: Int = 0
    @State private var autocomplete = WikiAutocompleteController()

    @State private var baseline: Entity? = nil
    @State private var showConflict: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if showConflict {
                    ConflictBanner(
                        onReload: { reloadFromDisk() },
                        onKeepMine: { keepMyChanges() }
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .padding(.top, 8).padding(.horizontal, 12)
                        .onChange(of: nameDraft) { _, _ in scheduleSave() }
                    Divider()
                    ZStack(alignment: .topLeading) {
                        MarkdownTextView(
                            text: $bodyText,
                            resolver: WikiLinkResolver(entities: session.store?.entities ?? []),
                            onOpenLink: { tabs.open(.entity($0)) },
                            onSelectionChange: { range in
                                caretLocation = range.location
                                refreshAutocomplete()
                            }
                        )
                        .onChange(of: bodyText) { _, _ in
                            scheduleSave()
                            refreshAutocomplete()
                        }
                        .onKeyPress(.upArrow) {
                            if autocomplete.isActive { autocomplete.move(by: -1); return .handled }
                            return .ignored
                        }
                        .onKeyPress(.downArrow) {
                            if autocomplete.isActive { autocomplete.move(by: 1); return .handled }
                            return .ignored
                        }
                        .onKeyPress(.return) {
                            if autocomplete.isActive { acceptAutocomplete(); return .handled }
                            return .ignored
                        }
                        .onKeyPress(.escape) {
                            if autocomplete.isActive { autocomplete.deactivate(); return .handled }
                            return .ignored
                        }

                        WikiAutocompleteView(controller: autocomplete, onAccept: acceptAutocomplete)
                            .padding(.top, 32).padding(.leading, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: entity) { old, new in handleEntityChange(old: old, new: new) }
    }

    private func loadDrafts() {
        nameDraft = entity.name
        bodyText = entity.body
        tags = entity.tags
        fields = entity.fields
        autocomplete.deactivate()
        baseline = entity
        showConflict = false
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

    private func refreshAutocomplete() {
        let all = session.store?.entities ?? []
        autocomplete.update(text: bodyText, caret: caretLocation, entities: all)
    }

    private func acceptAutocomplete() {
        guard let insertion = autocomplete.acceptCurrent() else { return }
        let ns = bodyText as NSString
        bodyText = ns.replacingCharacters(in: insertion.range, with: insertion.replacement)
        caretLocation = insertion.range.location + (insertion.replacement as NSString).length
        autocomplete.deactivate()
    }

    // MARK: - conflict

    private func handleEntityChange(old: Entity, new: Entity) {
        guard old.id == new.id else { return }
        guard let baseline else { return }
        let drafts: ConflictDecision.Drafts = (nameDraft, bodyText, tags, fields)
        switch ConflictDecision.decide(baseline: baseline, newDisk: new, drafts: drafts) {
        case .inSync:
            self.baseline = new
            showConflict = false
        case .silentReload:
            nameDraft = new.name
            bodyText = new.body
            tags = new.tags
            fields = new.fields
            self.baseline = new
            showConflict = false
        case .conflict:
            showConflict = true
        }
    }

    private func reloadFromDisk() {
        nameDraft = entity.name
        bodyText = entity.body
        tags = entity.tags
        fields = entity.fields
        baseline = entity
        showConflict = false
    }

    private func keepMyChanges() {
        showConflict = false
        // Cancel any pending debounce then save immediately.
        saveTask?.cancel()
        var copy = entity
        copy.name = nameDraft
        copy.body = bodyText
        copy.tags = tags
        copy.fields = fields
        try? session.save(copy)
        baseline = copy
    }
}

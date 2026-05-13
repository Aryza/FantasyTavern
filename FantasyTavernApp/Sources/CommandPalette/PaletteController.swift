import Foundation
import Observation
import AppKit
import EntityModel
import SearchIndex

@Observable
final class PaletteController {
    private let session: WorldSession
    private let tabs: TabsModel

    var isVisible: Bool = false
    var query: String = ""
    var selectionIndex: Int = 0

    init(session: WorldSession, tabs: TabsModel) {
        self.session = session
        self.tabs = tabs
    }

    func show() {
        query = ""
        selectionIndex = 0
        isVisible = true
    }

    func dismiss() {
        isVisible = false
    }

    var isActionMode: Bool { query.trimmingCharacters(in: .whitespaces).hasPrefix(">") }

    var findResults: [SearchHit] {
        guard !isActionMode else { return [] }
        // empty query: show recents first, then everything sorted by name (limit 50)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            let recentHits: [SearchHit] = tabs.recents.compactMap { content in
                guard case .entity(let id) = content,
                      let e = session.store?.entities.first(where: { $0.id == id })
                else { return nil }
                return SearchHit(id: e.id, type: e.type, name: e.name, score: 0)
            }
            let recentEntityIDs = Set(tabs.recents.compactMap { $0.entityID })
            let remaining = session.search("").filter { !recentEntityIDs.contains($0.id) }
            return Array((recentHits + remaining).prefix(50))
        }
        return Array(session.search(query).prefix(50))
    }

    var actionResults: [PaletteAction] {
        guard isActionMode else { return [] }
        let parsed = QueryParser.parse(query)
        return PaletteActions.filter(allActions, by: parsed.freeTerms)
    }

    var allActions: [PaletteAction] {
        PaletteActions.standard(
            newEntity: { [weak self] type in
                if let entity = try? self?.session.createEntity(type: type, name: "Untitled \(type.rawValue)") {
                    self?.tabs.open(.entity(entity.id))
                }
            },
            openWorld: { [weak self] in
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    try? self?.session.openWorld(at: url)
                    RecentWorlds.shared.add(url)
                }
            },
            closeCurrentTab: { [weak self] in
                if let s = self?.tabs.selected { self?.tabs.close(s) }
            },
            clearRecents: { RecentWorlds.shared.clear() }
        )
    }

    func moveSelection(by delta: Int) {
        let max = currentResultCount - 1
        if max < 0 { selectionIndex = 0; return }
        selectionIndex = min(max, Swift.max(0, selectionIndex + delta))
    }

    private var currentResultCount: Int {
        isActionMode ? actionResults.count : findResults.count
    }

    /// Open selection. `openInPlace = true` means reuse current tab; otherwise new tab.
    func activate(openInPlace: Bool) {
        if isActionMode {
            let actions = actionResults
            guard selectionIndex < actions.count else { return }
            actions[selectionIndex].perform()
            dismiss()
            return
        }
        let results = findResults
        guard selectionIndex < results.count else { return }
        let id = results[selectionIndex].id
        let content = TabContent.entity(id)
        if openInPlace, let current = tabs.selected, current != content {
            tabs.close(current)
        }
        tabs.open(content)
        dismiss()
    }
}

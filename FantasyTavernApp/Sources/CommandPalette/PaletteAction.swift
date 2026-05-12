import Foundation
import EntityModel

struct PaletteAction: Identifiable, Equatable {
    let id: String
    let title: String
    let perform: () -> Void

    static func == (lhs: PaletteAction, rhs: PaletteAction) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}

enum PaletteActions {
    /// Build the standard action list given the runtime callbacks.
    static func standard(
        newEntity: @escaping (EntityType) -> Void,
        openWorld: @escaping () -> Void,
        closeCurrentTab: @escaping () -> Void,
        clearRecents: @escaping () -> Void
    ) -> [PaletteAction] {
        var list: [PaletteAction] = []
        for type in EntityType.allCases {
            let label: String
            switch type {
            case .character:     label = "Character"
            case .location:      label = "Location"
            case .lore:          label = "Lore Entry"
            case .item:          label = "Item"
            case .language:      label = "Language"
            case .journal:       label = "Journal Entry"
            case .timelineEvent: label = "Timeline Event"
            }
            list.append(PaletteAction(id: "new-\(type.rawValue)",
                                      title: "New \(label)",
                                      perform: { newEntity(type) }))
        }
        list.append(PaletteAction(id: "open-world",     title: "Open World…",      perform: openWorld))
        list.append(PaletteAction(id: "close-tab",      title: "Close Current Tab", perform: closeCurrentTab))
        list.append(PaletteAction(id: "clear-recents",  title: "Clear Recent Worlds", perform: clearRecents))
        return list
    }

    /// Substring filter against title (lowercased).
    static func filter(_ list: [PaletteAction], by freeTerms: [String]) -> [PaletteAction] {
        guard !freeTerms.isEmpty else { return list }
        return list.filter { action in
            let lowered = action.title.lowercased()
            return freeTerms.allSatisfy { lowered.contains($0) }
        }
    }
}

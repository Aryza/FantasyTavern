import Foundation
import Observation
import EntityModel

@Observable
public final class TabsModel {
    public private(set) var openTabs: [TabContent] = []
    public var selected: TabContent?
    public private(set) var recents: [TabContent] = []
    private let recentsCap = 10

    public init() {}

    public func open(_ content: TabContent) {
        if !openTabs.contains(content) { openTabs.append(content) }
        selected = content
        pushRecent(content)
    }

    public func close(_ content: TabContent) {
        guard let idx = openTabs.firstIndex(of: content) else { return }
        openTabs.remove(at: idx)
        if selected == content {
            if openTabs.isEmpty { selected = nil }
            else { selected = openTabs[min(idx, openTabs.count - 1)] }
        }
    }

    private func pushRecent(_ content: TabContent) {
        recents.removeAll { $0 == content }
        recents.insert(content, at: 0)
        if recents.count > recentsCap { recents.removeLast(recents.count - recentsCap) }
    }
}

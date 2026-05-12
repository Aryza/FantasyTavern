import Foundation
import Observation

@Observable
final class RecentWorlds {
    static let shared = RecentWorlds()
    private let key = "FantasyTavern.recentWorlds"
    private let maxCount = 10

    private(set) var urls: [URL] = []

    private init() {
        load()
    }

    func add(_ url: URL) {
        var list = urls.filter { $0 != url }
        list.insert(url, at: 0)
        urls = Array(list.prefix(maxCount))
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func load() {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        urls = strings
            .compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() {
        UserDefaults.standard.set(urls.map(\.absoluteString), forKey: key)
    }
}

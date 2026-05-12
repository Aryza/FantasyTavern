import Foundation

public struct Filter: Equatable, Hashable {
    public let key: String
    public let value: String
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct ParsedQuery: Equatable {
    public let isActionMode: Bool
    public let filters: [Filter]
    public let freeTerms: [String]

    public init(isActionMode: Bool, filters: [Filter], freeTerms: [String]) {
        self.isActionMode = isActionMode
        self.filters = filters
        self.freeTerms = freeTerms
    }
}

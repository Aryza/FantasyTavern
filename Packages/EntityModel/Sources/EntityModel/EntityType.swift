import Foundation

public enum EntityType: String, CaseIterable, Codable, Sendable {
    case character
    case location
    case lore
    case item
    case language
    case journal
    case timelineEvent

    public var folderName: String {
        switch self {
        case .character: return "characters"
        case .location:  return "locations"
        case .lore:      return "lore"
        case .item:      return "items"
        case .language:  return "languages"
        case .journal:   return "journal"
        case .timelineEvent: return "timeline"
        }
    }
}

import Foundation

public struct Era: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let start: Int
    public let end: Int
}

public struct WorldCalendar: Equatable, Sendable {
    public let yearZeroLabel: String?
    public let eras: [Era]

    public init(yearZeroLabel: String? = nil, eras: [Era] = []) {
        self.yearZeroLabel = yearZeroLabel
        self.eras = eras
    }

    private struct Envelope: Decodable {
        struct Calendar: Decodable {
            let yearZeroLabel: String?
            let eras: [Era]?
        }
        let calendar: Calendar?
    }

    public static func load(from data: Data?) -> WorldCalendar {
        guard let data,
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              let cal = env.calendar
        else { return WorldCalendar() }
        return WorldCalendar(yearZeroLabel: cal.yearZeroLabel, eras: cal.eras ?? [])
    }
}

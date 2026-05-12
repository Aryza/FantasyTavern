import Foundation

public enum QueryParser {
    public static func parse(_ raw: String) -> ParsedQuery {
        var s = raw.trimmingCharacters(in: .whitespaces)
        let actionMode: Bool
        if s.hasPrefix(">") {
            actionMode = true
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else {
            actionMode = false
        }

        let pieces = s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var filters: [Filter] = []
        var freeTerms: [String] = []
        for piece in pieces {
            if piece.hasPrefix("#"), piece.count > 1 {
                filters.append(Filter(key: "tag", value: String(piece.dropFirst()).lowercased()))
                continue
            }
            if let colon = piece.firstIndex(of: ":"), colon != piece.startIndex {
                let key = String(piece[..<colon]).lowercased()
                let value = String(piece[piece.index(after: colon)...]).lowercased()
                if !key.isEmpty, !value.isEmpty {
                    filters.append(Filter(key: key, value: value))
                    continue
                }
            }
            freeTerms.append(piece.lowercased())
        }
        return ParsedQuery(isActionMode: actionMode, filters: filters, freeTerms: freeTerms)
    }
}

import Foundation

public enum Tokenizer {
    public static func tokens(in source: String) -> [String] {
        let folded = source.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                    locale: .init(identifier: "en_US_POSIX"))
        var out: [String] = []
        var seen = Set<String>()
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(Character(scalar))
            } else if !current.isEmpty {
                if seen.insert(current).inserted { out.append(current) }
                current = ""
            }
        }
        if !current.isEmpty, seen.insert(current).inserted { out.append(current) }
        return out
    }
}

import Foundation

public enum Slug {
    public static func make(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
        var out = ""
        var lastWasHyphen = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.append(Character(scalar))
                lastWasHyphen = false
            } else if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "untitled" : out
    }
}

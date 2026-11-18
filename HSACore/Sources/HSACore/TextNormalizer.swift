import Foundation

enum TextNormalizer {
    /// Lowercases and replaces every run of non-alphanumerics with a single space.
    /// "ADVIL Liqui-Gels 80CT" -> "advil liqui gels 80ct"
    static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in s.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }

    /// Normalized text padded with spaces so word-boundary checks are simple `contains` calls.
    static func padded(_ s: String) -> String { " \(normalize(s)) " }

    /// Short keywords (<= 4 chars) must match a whole word; longer ones match a word prefix
    /// ("ibupro" matches "ibuprofen"). A trailing "*" forces prefix matching ("spf*" matches "spf50").
    static func matches(keyword: String, inPadded padded: String) -> Bool {
        if keyword.hasSuffix("*") {
            return padded.contains(" " + String(keyword.dropLast()))
        }
        if keyword.count <= 4 {
            return padded.contains(" \(keyword) ")
        }
        return padded.contains(" " + keyword)
    }

    static func letterCount(_ s: String) -> Int {
        s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }
}

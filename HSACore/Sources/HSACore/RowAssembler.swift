import Foundation

/// A piece of recognized text with its position on the page.
/// Coordinates are normalized 0...1 with the origin at the TOP-left (y grows downward).
public struct TextFragment: Hashable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var height: Double

    public init(text: String, x: Double, y: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.height = height
    }
}

/// OCR engines often return an item name and its price as separate observations.
/// This groups fragments that sit on the same visual row back into a single line,
/// so "ADVIL 24CT" and "8.99" become "ADVIL 24CT  8.99".
public enum RowAssembler {
    public static func lines(from fragments: [TextFragment]) -> [String] {
        let sorted = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.y < $1.y }
        var rows: [[TextFragment]] = []
        var rowY = 0.0
        var rowHeight = 0.0

        for fragment in sorted {
            let tolerance = max(min(rowHeight, fragment.height), 0.004) * 0.5
            if !rows.isEmpty, abs(fragment.y - rowY) < tolerance {
                rows[rows.count - 1].append(fragment)
                let row = rows[rows.count - 1]
                rowY = row.reduce(0) { $0 + $1.y } / Double(row.count)
                rowHeight = max(rowHeight, fragment.height)
            } else {
                rows.append([fragment])
                rowY = fragment.y
                rowHeight = fragment.height
            }
        }
        return rows.map { row in
            row.sorted { $0.x < $1.x }.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: "  ")
        }
    }
}

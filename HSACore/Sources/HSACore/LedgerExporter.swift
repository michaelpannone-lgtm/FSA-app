import Foundation

/// Builds the "HSA Ledger.csv" spreadsheet kept next to the receipts in iCloud Drive.
public enum LedgerExporter {
    public static let header = ["Date", "Merchant", "For", "Total", "HSA Eligible Amount", "Eligibility",
                                "Reimbursed", "Reimbursed On", "Added By", "Notes", "Files", "Eligible Items"]

    public static func csv(for receipts: [Receipt]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var rows = [header.map(escape).joined(separator: ",")]
        for r in receipts.sorted(by: { $0.date < $1.date }) {
            let fields = [
                dateFormatter.string(from: r.date),
                r.merchant,
                r.patient,
                r.total?.plainString ?? "",
                r.eligibleAmount.plainString,
                label(for: r.eligibility),
                r.reimbursed ? "Yes" : "No",
                r.reimbursedOn.map { dateFormatter.string(from: $0) } ?? "",
                r.addedBy,
                r.notes,
                r.attachments.joined(separator: "; "),
                r.isSplit ? r.eligibleItems.map { "\($0.text) \($0.amount.plainString)" }.joined(separator: "; ") : ""
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func label(for e: Eligibility) -> String {
        switch e {
        case .likely: return "Likely eligible"
        case .maybe: return "Maybe (LMN)"
        case .notEligible: return "Not eligible"
        case .unknown: return "Needs review"
        }
    }

    static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

/// Totals for the dashboard.
public struct YearSummary: Identifiable, Hashable, Sendable {
    public var id: Int { year }
    public let year: Int
    public let eligible: Decimal
    public let reimbursed: Decimal
    public let receiptCount: Int
    public var unreimbursed: Decimal { eligible - reimbursed }

    public static func summarize(_ receipts: [Receipt]) -> [YearSummary] {
        let byYear = Dictionary(grouping: receipts.filter { $0.eligibleAmount > 0 }, by: \.year)
        return byYear.map { year, list in
            YearSummary(
                year: year,
                eligible: list.reduce(Decimal(0)) { $0 + $1.eligibleAmount },
                reimbursed: list.filter(\.reimbursed).reduce(Decimal(0)) { $0 + $1.eligibleAmount },
                receiptCount: list.count
            )
        }.sorted { $0.year > $1.year }
    }
}

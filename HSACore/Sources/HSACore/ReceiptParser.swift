import Foundation

public struct ParsedReceipt: Sendable {
    public var merchant: String?
    public var date: Date?
    public var total: Decimal?
    public var subtotal: Decimal?
    public var tax: Decimal?
    public var storeReportedEligibleTotal: Decimal?
    public var items: [(text: String, amount: Decimal)] = []
}

/// Heuristic parser for OCR'd receipt text (US formats).
public enum ReceiptParser {
    enum LineKind { case subtotal, tax, total, eligibleTotal, payment, other }

    // Price at the end of a line, optionally followed by a 1-2 letter tax flag ("T", "FT", "N") or "*".
    // Groups: 1 leading minus, 2 dollars, 3 cents, 4 trailing minus.
    static let amountRegex = try! NSRegularExpression(
        pattern: #"(-)?\$?\s?(\d{1,3}(?:,\d{3})+|\d{1,6})[.,](\d{2})(?!\d)\s*(-)?\s*(?:[A-Za-z]{1,2}|\*|USD)?\s*$"#)
    static let longNumberRegex = try! NSRegularExpression(pattern: #"\b\d{6,}\b"#)
    static let numericDateRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b"#)
    static let isoDateRegex = try! NSRegularExpression(pattern: #"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b"#)
    static let textDateRegex = try! NSRegularExpression(
        pattern: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(20\d{2})\b"#,
        options: [.caseInsensitive])

    static let monthNames = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8,
                             "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]

    static let knownMerchants: [(String, String)] = [
        ("cvs", "CVS Pharmacy"), ("minuteclinic", "CVS MinuteClinic"), ("walgreens", "Walgreens"),
        ("rite aid", "Rite Aid"), ("walmart", "Walmart"), ("wal mart", "Walmart"), ("target", "Target"),
        ("costco", "Costco"), ("sam s club", "Sam's Club"), ("kroger", "Kroger"), ("safeway", "Safeway"),
        ("publix", "Publix"), ("h e b", "H-E-B"), ("meijer", "Meijer"), ("amazon", "Amazon"),
        ("whole foods", "Whole Foods"), ("trader joe", "Trader Joe's"), ("albertsons", "Albertsons"),
        ("wegmans", "Wegmans"), ("duane reade", "Duane Reade"), ("1 800 contacts", "1-800 Contacts"),
        ("warby parker", "Warby Parker"), ("lenscrafters", "LensCrafters"), ("labcorp", "Labcorp"),
        ("quest diagnostics", "Quest Diagnostics"), ("bj s", "BJ's"), ("hy vee", "Hy-Vee"), ("giant", "Giant"),
        ("stop shop", "Stop & Shop"), ("shoprite", "ShopRite"), ("heb", "H-E-B")
    ]

    static let paymentWords = [
        "visa", "mastercard", "master card", "amex", "american express", "discover", "debit", "credit", "cash",
        "change", "tender", "payment", "approved", "approval", "auth", "ref", "chip", "contactless", "you saved",
        "savings", "saved", "reward", "rewards", "points", "balance remaining", "acct", "account", "card ending",
        "hsa card", "fsa card", "tip", "gratuity", "items sold", "item count", "number of items"
    ]

    // MARK: Public API

    public static func parse(lines rawLines: [String], now: Date = Date(), calendar: Calendar = .current) -> ParsedReceipt {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var result = ParsedReceipt()
        result.merchant = merchant(in: lines)
        result.date = date(in: lines, now: now, calendar: calendar)

        var pendingDescription: String?
        var awaiting: LineKind?
        var totalFound = false
        var taxSum: Decimal = 0
        var sawTax = false

        for line in lines {
            let padded = TextNormalizer.padded(line)
            let kind = lineKind(padded)
            let amountMatch = amount(in: line)

            // Summary label on one row, value on the next ("TOTAL" / "23.45").
            if let waiting = awaiting {
                awaiting = nil
                if let m = amountMatch, TextNormalizer.letterCount(m.remainder) < 2 {
                    apply(kind: waiting, amount: m.amount, to: &result, totalFound: &totalFound, taxSum: &taxSum, sawTax: &sawTax)
                    continue
                }
            }

            switch kind {
            case .subtotal, .tax, .total, .eligibleTotal:
                if let m = amountMatch {
                    apply(kind: kind, amount: m.amount, to: &result, totalFound: &totalFound, taxSum: &taxSum, sawTax: &sawTax)
                } else {
                    awaiting = kind
                }
                pendingDescription = nil
                continue
            case .payment:
                pendingDescription = nil
                continue
            case .other:
                break
            }

            if totalFound { continue } // everything after TOTAL is payment info

            if let m = amountMatch {
                let description = cleanDescription(m.remainder)
                if TextNormalizer.letterCount(description) >= 2 {
                    result.items.append((description, m.amount))
                    pendingDescription = nil
                } else if let pending = pendingDescription {
                    // Price landed on its own row (or a "2 @ 3.99" quantity row) under the item name.
                    result.items.append((pending, m.amount))
                    pendingDescription = nil
                }
            } else if TextNormalizer.letterCount(line) >= 3, !line.contains(":") {
                pendingDescription = cleanDescription(line)
            }
        }

        if sawTax { result.tax = taxSum.rounded2 }
        if result.total == nil {
            if let sub = result.subtotal {
                result.total = (sub + (result.tax ?? 0)).rounded2
            } else if !result.items.isEmpty {
                result.total = (result.items.reduce(Decimal(0)) { $0 + $1.amount } + (result.tax ?? 0)).rounded2
            }
        }
        return result
    }

    // MARK: Pieces

    static func apply(kind: LineKind, amount: Decimal, to result: inout ParsedReceipt,
                      totalFound: inout Bool, taxSum: inout Decimal, sawTax: inout Bool) {
        switch kind {
        case .subtotal: if result.subtotal == nil { result.subtotal = amount }
        case .tax: taxSum += amount; sawTax = true
        case .total:
            if result.total == nil { result.total = amount }
            totalFound = true
        case .eligibleTotal: result.storeReportedEligibleTotal = amount
        case .payment, .other: break
        }
    }

    static func lineKind(_ padded: String) -> LineKind {
        func has(_ k: String) -> Bool { TextNormalizer.matches(keyword: k, inPadded: padded) }

        if (has("fsa") || has("hsa") || has("flex spend") || has("iias")) &&
            (has("total") || has("elig") || has("amount") || has("qualified")) {
            return .eligibleTotal
        }
        if has("subtotal") || has("sub total") || has("merchandise total") { return .subtotal }
        if has("tax") || has("sales tax") || has("taxes") || has("hst") || has("gst") { return .tax }
        if has("total") && !has("saving") && !has("savings") && !has("items") && !has("discount") && !has("you saved") {
            return .total
        }
        if has("balance due") || has("amount due") || has("amount paid") || has("total paid") ||
            has("patient responsibility") || has("patient balance") || has("you owe") || has("amount you owe") {
            return .total
        }
        if paymentWords.contains(where: { has($0) }) { return .payment }
        return .other
    }

    struct AmountMatch { let amount: Decimal; let remainder: String }

    static func amount(in line: String) -> AmountMatch? {
        let ns = line as NSString
        guard let m = amountRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let dollars = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ",", with: "")
        let cents = ns.substring(with: m.range(at: 3))
        guard var value = Decimal(string: "\(dollars).\(cents)", locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if m.range(at: 1).location != NSNotFound || m.range(at: 4).location != NSNotFound { value = -value }
        let remainder = ns.substring(to: m.range.location)
        return AmountMatch(amount: value, remainder: remainder)
    }

    static func cleanDescription(_ s: String) -> String {
        let ns = s as NSString
        var cleaned = longNumberRegex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "$-*#:")))
    }

    static func merchant(in lines: [String]) -> String? {
        let head = Array(lines.prefix(10))
        for line in head {
            let padded = TextNormalizer.padded(line)
            if let hit = knownMerchants.first(where: { TextNormalizer.matches(keyword: $0.0, inPadded: padded) }) {
                return hit.1
            }
        }
        let skip = ["receipt", "welcome", "thank", "store", "invoice", "order", "date", "tel", "phone", "www", "http"]
        for line in head.prefix(6) {
            let letters = TextNormalizer.letterCount(line)
            guard letters >= 3, Double(letters) / Double(max(line.count, 1)) > 0.5 else { continue }
            let padded = TextNormalizer.padded(line)
            if skip.contains(where: { TextNormalizer.matches(keyword: $0, inPadded: padded) }) { continue }
            if amount(in: line) != nil { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == trimmed.uppercased() ? trimmed.capitalized : trimmed
        }
        return nil
    }

    static func date(in lines: [String], now: Date, calendar: Calendar) -> Date? {
        let latestAllowed = now.addingTimeInterval(2 * 86_400)
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            var year = y
            if year < 100 { year += 2000 }
            guard (1...12).contains(m), (1...31).contains(d), (2000...2100).contains(year) else { return nil }
            var comps = DateComponents()
            comps.year = year; comps.month = m; comps.day = d; comps.hour = 12
            guard let date = calendar.date(from: comps), date <= latestAllowed,
                  calendar.component(.day, from: date) == d else { return nil }
            return date
        }
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = isoDateRegex.firstMatch(in: line, range: range),
               let date = make(Int(ns.substring(with: m.range(at: 1)))!, Int(ns.substring(with: m.range(at: 2)))!,
                               Int(ns.substring(with: m.range(at: 3)))!) {
                return date
            }
            if let m = numericDateRegex.firstMatch(in: line, range: range),
               let date = make(Int(ns.substring(with: m.range(at: 3)))!, Int(ns.substring(with: m.range(at: 1)))!,
                               Int(ns.substring(with: m.range(at: 2)))!) {
                return date
            }
            if let m = textDateRegex.firstMatch(in: line, range: range),
               let month = monthNames[ns.substring(with: m.range(at: 1)).lowercased()],
               let date = make(Int(ns.substring(with: m.range(at: 3)))!, month, Int(ns.substring(with: m.range(at: 2)))!) {
                return date
            }
        }
        return nil
    }
}

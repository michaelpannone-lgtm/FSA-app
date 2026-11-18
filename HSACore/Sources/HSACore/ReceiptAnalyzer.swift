import Foundation

/// Turns OCR text into a draft `Receipt` with every line item classified.
public enum ReceiptAnalyzer {
    public static func analyze(lines: [String], classifier: EligibilityClassifier = EligibilityClassifier(),
                               now: Date = Date(), calendar: Calendar = .current) -> Receipt {
        let parsed = ReceiptParser.parse(lines: lines, now: now, calendar: calendar)
        let fullText = lines.joined(separator: "\n")
        let merchant = parsed.merchant ?? ""
        let kind = classifier.merchantKind(merchant: merchant, fullText: fullText)

        var receipt = Receipt(
            merchant: merchant,
            merchantKind: kind,
            date: parsed.date ?? now,
            total: parsed.total,
            subtotal: parsed.subtotal,
            tax: parsed.tax,
            storeReportedEligibleTotal: parsed.storeReportedEligibleTotal,
            items: parsed.items.map { LineItem(text: $0.text, amount: $0.amount) },
            rawText: fullText,
            createdAt: now,
            updatedAt: now
        )
        reclassify(&receipt, classifier: classifier)
        return receipt
    }

    /// Re-runs classification for items the user hasn't overridden and refreshes the receipt-level verdict.
    public static func reclassify(_ receipt: inout Receipt, classifier: EligibilityClassifier = EligibilityClassifier()) {
        if receipt.merchantKind != .medicalProvider {
            let kind = classifier.merchantKind(merchant: receipt.merchant, fullText: receipt.rawText)
            if kind == .medicalProvider || receipt.merchantKind == .general { receipt.merchantKind = kind }
        }
        var previous: Eligibility?
        var previousReason: String?
        for i in receipt.items.indices {
            if receipt.items[i].userOverride {
                previous = receipt.items[i].eligibility
                previousReason = receipt.items[i].reason
                continue
            }
            var result = classifier.classify(item: receipt.items[i].text, context: receipt.merchantKind)
            // A coupon/discount line usually belongs to the item just above it.
            if receipt.items[i].amount < 0, result.matchedKeyword == nil, let prev = previous {
                result = ItemClassification(eligibility: prev, reason: previousReason.map { "Discount on: \($0)" },
                                            matchedKeyword: nil)
            }
            receipt.items[i].eligibility = result.eligibility
            receipt.items[i].reason = result.reason
            previous = result.eligibility
            previousReason = result.reason
        }
        let verdict = verdict(for: receipt, classifier: classifier)
        receipt.eligibility = verdict.0
        receipt.eligibilityReason = verdict.1
    }

    static func verdict(for receipt: Receipt, classifier: EligibilityClassifier) -> (Eligibility, String) {
        if receipt.merchantKind == .medicalProvider {
            return (.likely, "Looks like a bill from a medical, dental or vision provider.")
        }
        if let store = receipt.storeReportedEligibleTotal, store > 0 {
            return (.likely, "The store printed an FSA/HSA-eligible total of $\(store.plainString).")
        }
        let positive = receipt.items.filter { $0.amount > 0 }
        if positive.isEmpty {
            // No line items: classify from the whole text (e.g. a short "Copay" slip).
            let whole = classifier.classify(item: receipt.merchant + " " + receipt.rawText, context: receipt.merchantKind)
            switch whole.eligibility {
            case .likely: return (.likely, whole.reason.map { "Matched: \($0)." } ?? "Likely eligible.")
            case .maybe: return (.maybe, "Possibly eligible — may need a Letter of Medical Necessity.")
            default: return (.unknown, "Couldn't find line items. Review and set eligibility by hand.")
            }
        }
        let likely = positive.filter { $0.eligibility == .likely }
        let maybe = positive.filter { $0.eligibility == .maybe }
        let notEligible = positive.filter { $0.eligibility == .notEligible }
        if !likely.isEmpty {
            let categories = Array(Set(likely.compactMap(\.reason))).sorted().prefix(3).joined(separator: ", ")
            let detail = categories.isEmpty ? "" : " (\(categories))"
            return (.likely, "\(likely.count) of \(positive.count) items look HSA-eligible\(detail).")
        }
        if !maybe.isEmpty {
            return (.maybe, "\(maybe.count) item(s) may qualify with a Letter of Medical Necessity.")
        }
        if notEligible.count == positive.count {
            return (.notEligible, "No HSA-eligible items found.")
        }
        return (.unknown, "Some items weren't recognized — review them below.")
    }
}

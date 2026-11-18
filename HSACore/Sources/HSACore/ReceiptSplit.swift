import Foundation

/// How a receipt's money divides between eligible, possibly eligible, ineligible and unreviewed items.
/// Sales tax is prorated across the groups in proportion to their item totals.
public struct SplitTotals: Hashable, Sendable {
    public var eligible: Decimal = 0
    public var maybe: Decimal = 0
    public var notEligible: Decimal = 0
    public var review: Decimal = 0

    public var total: Decimal { eligible + maybe + notEligible + review }

    public func amount(for eligibility: Eligibility) -> Decimal {
        switch eligibility {
        case .likely: return eligible
        case .maybe: return maybe
        case .notEligible: return notEligible
        case .unknown: return review
        }
    }
}

/// One family member's eligible share of a split receipt.
public struct PatientShare: Hashable, Sendable {
    public let patient: String
    public let amount: Decimal
}

public extension Receipt {
    /// Totals per eligibility group, including each group's share of sales tax.
    var splitTotals: SplitTotals {
        var result = SplitTotals()
        let positive = items.filter { $0.amount != 0 }
        guard !positive.isEmpty else {
            let amount = total ?? 0
            switch eligibility {
            case .likely: result.eligible = amount
            case .maybe: result.maybe = amount
            case .notEligible: result.notEligible = amount
            case .unknown: result.review = amount
            }
            return result
        }
        let all = positive.reduce(Decimal(0)) { $0 + $1.amount }
        func share(_ e: Eligibility) -> Decimal {
            let sum = positive.filter { $0.eligibility == e }.reduce(Decimal(0)) { $0 + $1.amount }
            guard let tax, tax > 0, all > 0 else { return max(0, sum).rounded2 }
            return max(0, sum + tax * sum / all).rounded2
        }
        result.eligible = share(.likely)
        result.maybe = share(.maybe)
        result.notEligible = share(.notEligible)
        result.review = share(.unknown)
        return result
    }

    /// True when the receipt mixes eligible items with anything else (the usual pharmacy/Target trip).
    var isSplit: Bool {
        let positive = items.filter { $0.amount > 0 }
        let hasEligible = positive.contains { $0.eligibility == .likely }
        let hasOther = positive.contains { $0.eligibility != .likely }
        return hasEligible && hasOther
    }

    /// Eligible line items, the ones being claimed on a split receipt.
    var eligibleItems: [LineItem] { items.filter { $0.eligibility == .likely && $0.amount != 0 } }

    /// Eligible amount per family member (items without a person fall back to the receipt's "For").
    var eligibleByPatient: [PatientShare] {
        let eligible = eligibleItems
        guard !eligible.isEmpty else {
            return eligibleAmount > 0 ? [PatientShare(patient: patient, amount: eligibleAmount)] : []
        }
        let all = items.filter { $0.amount != 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        var sums: [String: Decimal] = [:]
        var order: [String] = []
        for item in eligible {
            let who = item.patient.isEmpty ? patient : item.patient
            var amount = item.amount
            if let tax, tax > 0, all > 0 { amount += tax * item.amount / all }
            if sums[who] == nil { order.append(who) }
            sums[who, default: 0] += amount
        }
        return order.map { PatientShare(patient: $0, amount: max(0, sums[$0]!).rounded2) }
    }

    /// For receipts without readable line items: splits the pre-tax total into an eligible
    /// item of `eligibleAmount` and a "Not eligible" remainder. Existing items are replaced.
    mutating func quickSplit(eligibleAmount amount: Decimal, eligibleLabel: String = "HSA-eligible items",
                             otherLabel: String = "Other items") {
        let preTax = (subtotal ?? ((total ?? amount) - (tax ?? 0))).rounded2
        let eligiblePart = min(max(0, amount), max(preTax, amount)).rounded2
        var newItems = [LineItem(text: eligibleLabel, amount: eligiblePart, eligibility: .likely,
                                 reason: "Split by hand", userOverride: true)]
        let remainder = (preTax - eligiblePart).rounded2
        if remainder > 0 {
            newItems.append(LineItem(text: otherLabel, amount: remainder, eligibility: .notEligible,
                                     reason: "Split by hand", userOverride: true))
        }
        items = newItems
        if merchantKind == .medicalProvider { merchantKind = .general }
        eligibility = .likely
        eligibilityReason = "Split by hand: \(eligiblePart.plainString) of \(preTax.plainString) before tax is eligible."
        eligibleAmountOverride = nil
        storeReportedEligibleTotal = nil
    }

    /// Sets every item currently in `from` to `to` (e.g. all "Review" items -> "Not eligible").
    mutating func setEligibility(of from: Eligibility, to: Eligibility) {
        for i in items.indices where items[i].eligibility == from {
            items[i].eligibility = to
            items[i].userOverride = true
        }
    }
}

import Foundation

/// How likely an expense is to qualify for HSA reimbursement.
public enum Eligibility: String, Codable, CaseIterable, Sendable {
    /// Matches a well-known eligible category (Rx, OTC medicine, medical provider, etc.).
    case likely
    /// Dual-purpose item that may need a Letter of Medical Necessity (vitamins, massage, etc.).
    case maybe
    /// Clearly not a medical expense (groceries, cosmetics, toothpaste, etc.).
    case notEligible
    /// No rule matched — review by hand.
    case unknown
}

/// What kind of business issued the receipt.
public enum MerchantKind: String, Codable, Sendable {
    case medicalProvider
    case pharmacy
    case general
}

public struct LineItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var amount: Decimal
    public var eligibility: Eligibility
    /// Human readable reason, e.g. "OTC medicine (CARES Act)".
    public var reason: String?
    /// True once the user changed eligibility by hand; re-classification leaves it alone.
    public var userOverride: Bool
    /// Family member this item was for. Empty means "same as the receipt".
    public var patient: String

    public init(id: UUID = UUID(), text: String, amount: Decimal, eligibility: Eligibility = .unknown,
                reason: String? = nil, userOverride: Bool = false, patient: String = "") {
        self.id = id
        self.text = text
        self.amount = amount
        self.eligibility = eligibility
        self.reason = reason
        self.userOverride = userOverride
        self.patient = patient
    }

    enum CodingKeys: String, CodingKey { case id, text, amount, eligibility, reason, userOverride, patient }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        amount = (try c.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0).rounded2
        eligibility = try c.decodeIfPresent(Eligibility.self, forKey: .eligibility) ?? .unknown
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        userOverride = try c.decodeIfPresent(Bool.self, forKey: .userOverride) ?? false
        patient = try c.decodeIfPresent(String.self, forKey: .patient) ?? ""
    }
}

/// One saved receipt. Stored as a pretty-printed JSON file next to its images/PDF in iCloud Drive.
public struct Receipt: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var merchant: String
    public var merchantKind: MerchantKind
    public var date: Date
    public var total: Decimal?
    public var subtotal: Decimal?
    public var tax: Decimal?
    /// Some pharmacies (IIAS systems) print an "FSA/HSA eligible total".
    public var storeReportedEligibleTotal: Decimal?
    public var items: [LineItem]
    public var eligibility: Eligibility
    public var eligibilityReason: String
    /// Set by the user to force the eligible amount.
    public var eligibleAmountOverride: Decimal?
    /// File names (in the same folder as the JSON) of the scanned images / PDFs.
    public var attachments: [String]
    /// File name stem shared by the JSON and attachments.
    public var baseName: String
    /// Family member the expense was for.
    public var patient: String
    /// Who scanned it (e.g. "Michael" or spouse's name).
    public var addedBy: String
    public var notes: String
    public var reimbursed: Bool
    public var reimbursedOn: Date?
    public var rawText: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), merchant: String = "", merchantKind: MerchantKind = .general, date: Date = Date(),
                total: Decimal? = nil, subtotal: Decimal? = nil, tax: Decimal? = nil,
                storeReportedEligibleTotal: Decimal? = nil, items: [LineItem] = [],
                eligibility: Eligibility = .unknown, eligibilityReason: String = "",
                eligibleAmountOverride: Decimal? = nil, attachments: [String] = [], baseName: String = "",
                patient: String = "", addedBy: String = "", notes: String = "", reimbursed: Bool = false,
                reimbursedOn: Date? = nil, rawText: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.merchant = merchant
        self.merchantKind = merchantKind
        self.date = date
        self.total = total
        self.subtotal = subtotal
        self.tax = tax
        self.storeReportedEligibleTotal = storeReportedEligibleTotal
        self.items = items
        self.eligibility = eligibility
        self.eligibilityReason = eligibilityReason
        self.eligibleAmountOverride = eligibleAmountOverride
        self.attachments = attachments
        self.baseName = baseName
        self.patient = patient
        self.addedBy = addedBy
        self.notes = notes
        self.reimbursed = reimbursed
        self.reimbursedOn = reimbursedOn
        self.rawText = rawText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, merchant, merchantKind, date, total, subtotal, tax, storeReportedEligibleTotal, items
        case eligibility, eligibilityReason, eligibleAmountOverride, attachments, baseName, patient, addedBy
        case notes, reimbursed, reimbursedOn, rawText, createdAt, updatedAt
    }

    // Tolerant decoding so two phones on slightly different app versions can read each other's files.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        merchantKind = try c.decodeIfPresent(MerchantKind.self, forKey: .merchantKind) ?? .general
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        total = try c.decodeIfPresent(Decimal.self, forKey: .total)?.rounded2
        subtotal = try c.decodeIfPresent(Decimal.self, forKey: .subtotal)?.rounded2
        tax = try c.decodeIfPresent(Decimal.self, forKey: .tax)?.rounded2
        storeReportedEligibleTotal = try c.decodeIfPresent(Decimal.self, forKey: .storeReportedEligibleTotal)?.rounded2
        items = try c.decodeIfPresent([LineItem].self, forKey: .items) ?? []
        eligibility = try c.decodeIfPresent(Eligibility.self, forKey: .eligibility) ?? .unknown
        eligibilityReason = try c.decodeIfPresent(String.self, forKey: .eligibilityReason) ?? ""
        eligibleAmountOverride = try c.decodeIfPresent(Decimal.self, forKey: .eligibleAmountOverride)?.rounded2
        attachments = try c.decodeIfPresent([String].self, forKey: .attachments) ?? []
        baseName = try c.decodeIfPresent(String.self, forKey: .baseName) ?? ""
        patient = try c.decodeIfPresent(String.self, forKey: .patient) ?? ""
        addedBy = try c.decodeIfPresent(String.self, forKey: .addedBy) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        reimbursed = try c.decodeIfPresent(Bool.self, forKey: .reimbursed) ?? false
        reimbursedOn = try c.decodeIfPresent(Date.self, forKey: .reimbursedOn)
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// Eligible amount derived from line items (with tax prorated) or from the receipt as a whole.
    public var computedEligibleAmount: Decimal {
        if merchantKind == .medicalProvider, let total { return max(0, total) }
        if !items.isEmpty {
            let all = items.reduce(Decimal(0)) { $0 + $1.amount }
            let eligible = items.filter { $0.eligibility == .likely }.reduce(Decimal(0)) { $0 + $1.amount }
            var result = eligible
            if let tax, tax > 0, all > 0, eligible > 0 {
                result += tax * eligible / all
            }
            return max(0, result).rounded2
        }
        return eligibility == .likely ? max(0, total ?? 0) : 0
    }

    /// The amount this receipt can be reimbursed for: manual override > store-printed eligible total > computed.
    public var eligibleAmount: Decimal {
        eligibleAmountOverride ?? storeReportedEligibleTotal ?? computedEligibleAmount
    }

    public var year: Int { Calendar.current.component(.year, from: date) }
}

public extension Decimal {
    /// Rounded to cents.
    var rounded2: Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    /// Whole cents as an Int (used by the reimbursement planner).
    var cents: Int {
        NSDecimalNumber(decimal: (self * 100).rounded2).intValue
    }

    init(cents: Int) {
        self = Decimal(cents) / 100
    }

    /// "23.45" style string, always two decimals, locale independent (for CSV).
    var plainString: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.minimumIntegerDigits = 1
        f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: self)) ?? "0.00"
    }
}

public extension JSONEncoder {
    static var hsa: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

public extension JSONDecoder {
    static var hsa: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

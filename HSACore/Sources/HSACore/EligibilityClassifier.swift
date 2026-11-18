import Foundation

public struct ItemClassification: Hashable, Sendable {
    public var eligibility: Eligibility
    public var reason: String?
    public var matchedKeyword: String?
}

/// Keyword-based classifier. Deterministic, on-device, and easy to extend:
/// add keywords to `EligibilityRules` (or pass custom rules) to teach it new items.
public struct EligibilityClassifier: Sendable {
    struct Entry: Sendable {
        let keyword: String
        let rule: EligibilityRule
    }

    private let entries: [Entry]

    public init(rules: [EligibilityRule] = EligibilityRules.all) {
        var list: [Entry] = []
        for rule in rules {
            for kw in rule.keywords {
                let star = kw.hasSuffix("*")
                let norm = TextNormalizer.normalize(star ? String(kw.dropLast()) : kw)
                guard !norm.isEmpty else { continue }
                list.append(Entry(keyword: star ? norm + "*" : norm, rule: rule))
            }
        }
        // Longest keyword wins; on ties, prefer the more favorable eligibility.
        entries = list.enumerated().sorted { a, b in
            let rankA = a.element.keyword.count + a.element.rule.priority
            let rankB = b.element.keyword.count + b.element.rule.priority
            if rankA != rankB { return rankA > rankB }
            return a.offset < b.offset
        }.map(\.element)
    }

    public func classify(item text: String, context: MerchantKind = .general) -> ItemClassification {
        let padded = TextNormalizer.padded(text)
        for entry in entries where TextNormalizer.matches(keyword: entry.keyword, inPadded: padded) {
            return ItemClassification(eligibility: entry.rule.eligibility, reason: entry.rule.category,
                                      matchedKeyword: entry.keyword)
        }
        if context == .medicalProvider {
            return ItemClassification(eligibility: .likely, reason: "Charge from a medical provider", matchedKeyword: nil)
        }
        return ItemClassification(eligibility: .unknown, reason: nil, matchedKeyword: nil)
    }

    // MARK: Merchant detection

    static let medicalMerchantWords = [
        "dental", "dentist", "dds", "dmd", "orthodont", "pediatric", "pediatrics", "clinic", "hospital", "medical",
        "health center", "health system", "healthcare", "urgent care", "physician", "physicians", "md", "family practice",
        "family medicine", "internal medicine", "dermatolog", "optometr", "ophthalm", "vision center", "eye care",
        "eyecare", "optical", "chiropract", "physical therapy", "rehab", "labcorp", "quest diagnostic", "radiology",
        "imaging", "counseling", "psychiatr", "psycholog", "therapist", "hearing", "audiolog", "podiatr", "ob gyn",
        "obgyn", "women s health", "surgery center", "surgical", "anesthesia", "minuteclinic", "minute clinic",
        "lenscrafters", "warby parker", "1 800 contacts", "visionworks", "america s best"
    ]

    static let medicalDocumentWords = [
        "patient", "date of service", "dos", "provider", "copay", "co pay", "insurance", "guarantor", "procedure",
        "cpt", "diagnosis", "visit", "statement date", "account number", "amount you owe", "patient responsibility",
        "adjustment", "npi"
    ]

    static let pharmacyWords = [
        "cvs", "walgreens", "rite aid", "pharmacy", "pharmacist", "drug", "drugs", "duane reade", "health mart",
        "good neighbor pharmacy", "rx"
    ]

    public func merchantKind(merchant: String, fullText: String) -> MerchantKind {
        let merchantPadded = TextNormalizer.padded(merchant)
        let textPadded = TextNormalizer.padded(fullText)

        if Self.medicalMerchantWords.contains(where: { TextNormalizer.matches(keyword: $0, inPadded: merchantPadded) }) {
            // "CVS MinuteClinic" is medical, "CVS Pharmacy" is a pharmacy.
            return .medicalProvider
        }
        let docHits = Self.medicalDocumentWords.filter { TextNormalizer.matches(keyword: $0, inPadded: textPadded) }.count
        if docHits >= 3 { return .medicalProvider }

        if Self.pharmacyWords.contains(where: {
            TextNormalizer.matches(keyword: $0, inPadded: merchantPadded) || TextNormalizer.matches(keyword: $0, inPadded: textPadded)
        }) {
            return .pharmacy
        }
        return .general
    }
}

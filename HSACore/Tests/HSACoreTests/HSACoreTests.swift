import XCTest
@testable import HSACore

final class ClassifierTests: XCTestCase {
    let classifier = EligibilityClassifier()

    func testOTCMedicine() {
        XCTAssertEqual(classifier.classify(item: "ADVIL LIQ GELS 80CT").eligibility, .likely)
        XCTAssertEqual(classifier.classify(item: "CVS IBUPROFEN 200MG").eligibility, .likely)
        XCTAssertEqual(classifier.classify(item: "ZYRTEC 24HR ALLERGY").eligibility, .likely)
    }

    func testLongestKeywordWins() {
        XCTAssertEqual(classifier.classify(item: "DESITIN DIAPER RASH CRM").eligibility, .likely)
        XCTAssertEqual(classifier.classify(item: "PAMPERS DIAPERS SZ 4").eligibility, .notEligible)
        XCTAssertEqual(classifier.classify(item: "MILK STORAGE BAGS").eligibility, .likely)
        XCTAssertEqual(classifier.classify(item: "WHOLE MILK GAL").eligibility, .notEligible)
    }

    func testShortKeywordsNeedWholeWord() {
        XCTAssertEqual(classifier.classify(item: "RX 1234567 LISINOPRIL").eligibility, .likely)
        XCTAssertNotEqual(classifier.classify(item: "RXBAR CHOC SEA SALT").eligibility, .likely)
    }

    func testSunscreenPrefix() {
        XCTAssertEqual(classifier.classify(item: "BANANA BOAT SPF50 LOTION").eligibility, .likely)
    }

    func testMaybeAndNot() {
        XCTAssertEqual(classifier.classify(item: "NATURE MADE VITAMIN D3").eligibility, .maybe)
        XCTAssertEqual(classifier.classify(item: "COLGATE TOOTHPASTE").eligibility, .notEligible)
    }

    func testMerchantKinds() {
        XCTAssertEqual(classifier.merchantKind(merchant: "Bright Smiles Dental", fullText: ""), .medicalProvider)
        XCTAssertEqual(classifier.merchantKind(merchant: "CVS Pharmacy", fullText: ""), .pharmacy)
        XCTAssertEqual(classifier.merchantKind(merchant: "Trader Joe's", fullText: "BANANAS 0.99"), .general)
    }
}

final class ParserTests: XCTestCase {
    let sample = [
        "CVS/pharmacy",
        "123 MAIN ST, SPRINGFIELD",
        "11/02/2026 10:14 AM",
        "ADVIL LIQ GELS 80CT        12.99 F",
        "CVS SPF50 SUNSCREEN         9.49 F",
        "COUPON                      1.00-",
        "COCA COLA 20OZ              2.29",
        "SUBTOTAL                   23.77",
        "TAX                         1.43",
        "TOTAL                      25.20",
        "FSA ELIGIBLE TOTAL         21.48",
        "VISA                       25.20",
        "CHANGE                      0.00"
    ]

    func testParsesSummaryAndItems() throws {
        let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!
        let p = ReceiptParser.parse(lines: sample, now: now)
        XCTAssertEqual(p.merchant, "CVS Pharmacy")
        XCTAssertEqual(p.total, Decimal(string: "25.20"))
        XCTAssertEqual(p.subtotal, Decimal(string: "23.77"))
        XCTAssertEqual(p.tax, Decimal(string: "1.43"))
        XCTAssertEqual(p.storeReportedEligibleTotal, Decimal(string: "21.48"))
        XCTAssertEqual(p.items.count, 4)
        XCTAssertEqual(p.items[2].amount, Decimal(-1))
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: try XCTUnwrap(p.date))
        XCTAssertEqual(comps.year, 2026); XCTAssertEqual(comps.month, 11); XCTAssertEqual(comps.day, 2)
    }

    func testAnalyzerCouponInheritsEligibility() {
        let r = ReceiptAnalyzer.analyze(lines: sample)
        XCTAssertEqual(r.items[2].eligibility, .likely) // coupon follows sunscreen
        XCTAssertEqual(r.items[3].eligibility, .notEligible) // soda
        XCTAssertEqual(r.eligibility, .likely)
        XCTAssertEqual(r.eligibleAmount, Decimal(string: "21.48")) // store-printed total wins
    }

    func testPriceOnSeparateRow() {
        let p = ReceiptParser.parse(lines: ["TARGET", "CLARITIN 30CT", "24.99", "TOTAL", "24.99"])
        XCTAssertEqual(p.items.count, 1)
        XCTAssertEqual(p.items.first?.text, "CLARITIN 30CT")
        XCTAssertEqual(p.total, Decimal(string: "24.99"))
    }

    func testRowAssembler() {
        let lines = RowAssembler.lines(from: [
            TextFragment(text: "8.99", x: 0.8, y: 0.301, height: 0.02),
            TextFragment(text: "ADVIL", x: 0.1, y: 0.300, height: 0.02),
            TextFragment(text: "TOTAL", x: 0.1, y: 0.4, height: 0.02)
        ])
        XCTAssertEqual(lines, ["ADVIL  8.99", "TOTAL"])
    }
}

final class PlannerTests: XCTestCase {
    func testFindsExactCombination() {
        let ids = (0..<5).map { _ in UUID() }
        let cents = [12_500, 4_000, 7_525, 30_000, 1_999]
        let candidates = zip(ids, cents).map { ReimbursementPlanner.Candidate(id: $0, cents: $1) }
        let plan = ReimbursementPlanner.plan(candidates: candidates, targetCents: 13_524) // 7,525 + 4,000 + 1,999
        XCTAssertTrue(plan.isExact)
        XCTAssertEqual(Set(plan.ids), Set([ids[1], ids[2], ids[4]]))
    }

    func testClosestUnderByDefault() {
        let a = UUID(), b = UUID()
        let plan = ReimbursementPlanner.plan(candidates: [.init(id: a, cents: 10_000), .init(id: b, cents: 6_000)],
                                             targetCents: 9_000)
        XCTAssertEqual(plan.totalCents, 6_000)
        let over = ReimbursementPlanner.plan(candidates: [.init(id: a, cents: 10_000), .init(id: b, cents: 6_000)],
                                             targetCents: 9_000, allowOver: true)
        XCTAssertEqual(over.totalCents, 10_000)
    }

    func testEverythingWhenTargetExceedsBalance() {
        let plan = ReimbursementPlanner.plan(candidates: [.init(id: UUID(), cents: 500)], targetCents: 10_000)
        XCTAssertEqual(plan.totalCents, 500)
    }
}

final class SplitTests: XCTestCase {
    func receipt() -> Receipt {
        Receipt(merchant: "Target", total: Decimal(string: "33.00"), subtotal: 30, tax: 3, items: [
            LineItem(text: "Claritin", amount: 20, eligibility: .likely, patient: "Emma"),
            LineItem(text: "Advil", amount: 5, eligibility: .likely),
            LineItem(text: "Paper towels", amount: 5, eligibility: .notEligible)
        ], eligibility: .likely, patient: "Michael")
    }

    func testSplitTotalsProrateTax() {
        let t = receipt().splitTotals
        XCTAssertEqual(t.eligible, Decimal(string: "27.5"))   // 25 + 25/30 * 3
        XCTAssertEqual(t.notEligible, Decimal(string: "5.5"))
        XCTAssertEqual(t.total, 33)
        XCTAssertTrue(receipt().isSplit)
    }

    func testEligibleByPatient() {
        let shares = receipt().eligibleByPatient
        XCTAssertEqual(shares.map(\.patient), ["Emma", "Michael"])
        XCTAssertEqual(shares[0].amount, 22)                  // 20 + 2 tax
        XCTAssertEqual(shares[1].amount, Decimal(string: "5.5"))
    }

    func testQuickSplit() {
        var r = Receipt(merchant: "Costco", total: Decimal(string: "107.00"), tax: 7, eligibility: .unknown)
        r.quickSplit(eligibleAmount: 40)
        XCTAssertEqual(r.items.count, 2)
        XCTAssertEqual(r.items[1].amount, 60)
        XCTAssertEqual(r.eligibleAmount, Decimal(string: "42.8")) // 40 + 40/100 * 7
    }

    func testBulkSetEligibility() {
        var r = receipt()
        r.items.append(LineItem(text: "Mystery", amount: 1, eligibility: .unknown))
        r.setEligibility(of: .unknown, to: .notEligible)
        XCTAssertFalse(r.items.contains { $0.eligibility == .unknown })
    }
}

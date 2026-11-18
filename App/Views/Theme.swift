import SwiftUI
import HSACore

extension Eligibility {
    var label: String {
        switch self {
        case .likely: return "Likely eligible"
        case .maybe: return "Maybe (needs LMN)"
        case .notEligible: return "Not eligible"
        case .unknown: return "Needs review"
        }
    }

    var shortLabel: String {
        switch self {
        case .likely: return "Eligible"
        case .maybe: return "Maybe"
        case .notEligible: return "Not eligible"
        case .unknown: return "Review"
        }
    }

    var symbol: String {
        switch self {
        case .likely: return "checkmark.seal.fill"
        case .maybe: return "questionmark.circle.fill"
        case .notEligible: return "xmark.circle.fill"
        case .unknown: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .likely: return .green
        case .maybe: return .orange
        case .notEligible: return .secondary
        case .unknown: return .yellow
        }
    }
}

extension Decimal {
    var currency: String { formatted(.currency(code: "USD")) }
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

struct EligibilityBadge: View {
    let eligibility: Eligibility
    var compact = true

    var body: some View {
        // Icon + text, never color alone.
        Label(compact ? eligibility.shortLabel : eligibility.label, systemImage: eligibility.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(eligibility.color)
            .labelStyle(.titleAndIcon)
    }
}

struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.merchant.isEmpty ? "Receipt" : receipt.merchant)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
                    if !receipt.patient.isEmpty { Text("· \(receipt.patient)") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    EligibilityBadge(eligibility: receipt.eligibility)
                    if receipt.isSplit {
                        Label("Split", systemImage: "square.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(receipt.eligibleAmount.currency)
                    .font(.headline.monospacedDigit())
                if let total = receipt.total, total != receipt.eligibleAmount {
                    Text("of \(total.currency)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if receipt.reimbursed {
                    Label("Reimbursed", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
            Text(value)
                .font(prominent ? .system(size: 38, weight: .bold, design: .rounded).monospacedDigit()
                                : .title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(prominent ? .white : .primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
        )
    }
}

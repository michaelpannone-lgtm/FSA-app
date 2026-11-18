import SwiftUI
import Charts
import HSACore

struct DashboardView: View {
    @EnvironmentObject private var store: ReceiptStore
    @EnvironmentObject private var scanner: ScanCoordinator

    private var summaries: [YearSummary] { YearSummary.summarize(store.receipts) }
    private var reimbursedAllTime: Decimal { summaries.reduce(Decimal(0)) { $0 + $1.reimbursed } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    balanceTile
                    HStack(spacing: 12) {
                        StatTile(title: "Reimbursed", value: reimbursedAllTime.currency, caption: "All time")
                        StatTile(title: "Needs review", value: "\(store.needsReviewCount)",
                                 caption: store.needsReviewCount == 1 ? "receipt" : "receipts")
                    }
                    if !summaries.isEmpty {
                        yearChart
                        yearTable
                    }
                    recent
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HSA Dashboard")
            .toolbar { ToolbarItem(placement: .primaryAction) { AddReceiptMenu() } }
            .refreshable { await store.reload() }
            .navigationDestination(for: UUID.self) { id in
                if let receipt = store.receipt(id: id) {
                    ReceiptEditorView(receipt: receipt, isNew: false)
                }
            }
        }
    }

    private var balanceTile: some View {
        let reimbursable = store.reimbursable
        let oldest = reimbursable.map(\.date).min()
        let caption: String = {
            guard !reimbursable.isEmpty else { return "Scan receipts to start building your balance" }
            var text = "\(reimbursable.count) receipt\(reimbursable.count == 1 ? "" : "s")"
            if let oldest { text += " · oldest \(oldest.formatted(.dateTime.month(.abbreviated).year()))" }
            return text
        }()
        return Button {
            scanner.selectedTab = .reimburse
        } label: {
            StatTile(title: "Available to reimburse", value: store.unreimbursedBalance.currency,
                     caption: caption, prominent: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the reimbursement planner")
    }

    private struct BarDatum: Identifiable {
        let id = UUID()
        let year: String
        let status: String
        let amount: Double
    }

    private var yearChart: some View {
        let data = summaries.reversed().flatMap { s in [
            BarDatum(year: String(s.year), status: "Available", amount: s.unreimbursed.doubleValue),
            BarDatum(year: String(s.year), status: "Reimbursed", amount: s.reimbursed.doubleValue)
        ] }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Eligible expenses by year").font(.headline)
            Chart(data) { d in
                BarMark(x: .value("Year", d.year), y: .value("Amount", d.amount), width: .ratio(0.5))
                    .foregroundStyle(by: .value("Status", d.status))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(["Available": Color.accentColor, "Reimbursed": Color.gray.opacity(0.45)])
            .chartLegend(position: .top, alignment: .leading)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(v, format: .currency(code: "USD").precision(.fractionLength(0))) }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var yearTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Year").frame(width: 50, alignment: .leading)
                Spacer()
                Text("Eligible").frame(width: 92, alignment: .trailing)
                Text("Reimbursed").frame(width: 92, alignment: .trailing)
                Text("Available").frame(width: 92, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
            ForEach(summaries) { s in
                Divider()
                HStack {
                    Text(String(s.year)).frame(width: 50, alignment: .leading)
                    Spacer()
                    Text(s.eligible.currency).frame(width: 92, alignment: .trailing)
                    Text(s.reimbursed.currency).frame(width: 92, alignment: .trailing).foregroundStyle(.secondary)
                    Text(s.unreimbursed.currency).frame(width: 92, alignment: .trailing).fontWeight(.semibold)
                }
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private var recent: some View {
        if store.receipts.isEmpty {
            ContentUnavailableView {
                Label("No receipts yet", systemImage: "doc.viewfinder")
            } description: {
                Text("Tap + to scan a pharmacy receipt, doctor's bill, or eyeglasses invoice.")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.headline)
                ForEach(store.receipts.prefix(5)) { receipt in
                    NavigationLink(value: receipt.id) {
                        ReceiptRow(receipt: receipt)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

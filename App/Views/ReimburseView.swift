import SwiftUI
import HSACore

/// "I want to pull $X out of my HSA — which receipts should I use?"
struct ReimburseView: View {
    @EnvironmentObject private var store: ReceiptStore

    @State private var target: Decimal?
    @State private var yearFilter: Int? = nil
    @State private var allowOver = false
    @State private var selected: Set<UUID> = []
    @State private var plan: ReimbursementPlanner.Plan?
    @State private var isPlanning = false
    @State private var showExport = false
    @FocusState private var amountFocused: Bool

    private var candidates: [Receipt] {
        store.reimbursable
            .filter { yearFilter == nil || $0.year == yearFilter }
            .sorted { $0.date < $1.date } // oldest first: ties go to older receipts
    }

    private var years: [Int] { Array(Set(store.reimbursable.map(\.year))).sorted(by: >) }
    private var available: Decimal { candidates.reduce(Decimal(0)) { $0 + $1.eligibleAmount } }
    private var selectedReceipts: [Receipt] { candidates.filter { selected.contains($0.id) } }
    private var selectedTotal: Decimal { selectedReceipts.reduce(Decimal(0)) { $0 + $1.eligibleAmount } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Available", value: available.currency)
                        .font(.headline)
                    LabeledContent("Amount to reimburse") {
                        TextField("$0.00", value: $target, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .font(.title3.monospacedDigit())
                    }
                    Picker("Use receipts from", selection: $yearFilter) {
                        Text("All years").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                    Toggle("Allow going slightly over", isOn: $allowOver)
                    Button {
                        runPlanner()
                    } label: {
                        HStack {
                            Label("Find best combination", systemImage: "wand.and.stars")
                            if isPlanning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled((target ?? 0) <= 0 || candidates.isEmpty || isPlanning)
                } footer: {
                    Text("Finds the set of unreimbursed receipts whose eligible amounts add up closest to your target. You can adjust the picks below.")
                }

                if let plan {
                    Section {
                        resultSummary(plan)
                    }
                }

                Section {
                    if candidates.isEmpty {
                        Text("No unreimbursed eligible receipts.").foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { receipt in
                        Button {
                            if selected.contains(receipt.id) { selected.remove(receipt.id) } else { selected.insert(receipt.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(receipt.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(receipt.id) ? Color.accentColor : .secondary)
                                    .font(.title3)
                                ReceiptRow(receipt: receipt)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Receipts")
                        Spacer()
                        Button(selected.count == candidates.count && !candidates.isEmpty ? "Clear" : "Select all") {
                            if selected.count == candidates.count { selected = [] } else { selected = Set(candidates.map(\.id)) }
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Reimburse")
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export \(selected.count) receipt\(selected.count == 1 ? "" : "s") · \(selectedTotal.currency)",
                              systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(receipts: selectedReceipts) { selected = []; plan = nil }
            }
            .onChange(of: yearFilter) { _, _ in selected = []; plan = nil }
        }
    }

    @ViewBuilder
    private func resultSummary(_ plan: ReimbursementPlanner.Plan) -> some View {
        let diff = Decimal(cents: plan.differenceCents)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: plan.isExact ? "checkmark.seal.fill" : "scope")
                    .foregroundStyle(plan.isExact ? .green : Color.accentColor)
                Text(plan.isExact ? "Exact match" : "Closest match").font(.headline)
            }
            Text("\(plan.ids.count) receipts totaling \(Decimal(cents: plan.totalCents).currency)")
            if !plan.isExact {
                Text(diff < 0 ? "\((-diff).currency) under your target" : "\(diff.currency) over your target")
                    .foregroundStyle(.secondary)
            }
            if selectedTotal != Decimal(cents: plan.totalCents) {
                Text("Your current selection: \(selectedTotal.currency)").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func runPlanner() {
        amountFocused = false
        guard let target, target > 0 else { return }
        let items = candidates.map { ReimbursementPlanner.Candidate(id: $0.id, cents: $0.eligibleAmount.cents) }
        let targetCents = target.cents
        let over = allowOver
        isPlanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ReimbursementPlanner.plan(candidates: items, targetCents: targetCents, allowOver: over)
            }.value
            plan = result
            selected = Set(result.ids)
            isPlanning = false
        }
    }
}

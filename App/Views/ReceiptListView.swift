import SwiftUI
import HSACore

struct ReceiptListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", available = "Available", reimbursed = "Reimbursed", review = "Review"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: ReceiptStore
    @State private var filter: Filter = .all
    @State private var search = ""

    private var filtered: [Receipt] {
        store.receipts.filter { r in
            let passes: Bool
            switch filter {
            case .all: passes = true
            case .available: passes = !r.reimbursed && r.eligibleAmount > 0
            case .reimbursed: passes = r.reimbursed
            case .review: passes = r.eligibility == .unknown || r.eligibility == .maybe
            }
            guard passes else { return false }
            guard !search.isEmpty else { return true }
            return r.merchant.localizedCaseInsensitiveContains(search)
                || r.patient.localizedCaseInsensitiveContains(search)
                || r.notes.localizedCaseInsensitiveContains(search)
                || r.items.contains { $0.text.localizedCaseInsensitiveContains(search) }
        }
    }

    private var years: [Int] { Array(Set(filtered.map(\.year))).sorted(by: >) }

    var body: some View {
        NavigationStack {
            List {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                ForEach(years, id: \.self) { year in
                    let list = filtered.filter { $0.year == year }
                    Section {
                        ForEach(list) { receipt in
                            NavigationLink(value: receipt.id) { ReceiptRow(receipt: receipt) }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        var updated = receipt
                                        updated.reimbursed.toggle()
                                        updated.reimbursedOn = updated.reimbursed ? Date() : nil
                                        Task { await store.save(updated) }
                                    } label: {
                                        Label(receipt.reimbursed ? "Unmark" : "Reimbursed", systemImage: "checkmark.circle")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await store.delete(receipt) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        HStack {
                            Text(String(year))
                            Spacer()
                            Text(list.reduce(Decimal(0)) { $0 + $1.eligibleAmount }.currency)
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty && !store.isLoading {
                    ContentUnavailableView(search.isEmpty ? "No receipts" : "No matches",
                                           systemImage: "doc.text.magnifyingglass",
                                           description: Text(search.isEmpty ? "Tap + to add one." : "Try a different search."))
                }
            }
            .searchable(text: $search, prompt: "Merchant, item, family member")
            .navigationTitle("Receipts")
            .toolbar { ToolbarItem(placement: .primaryAction) { AddReceiptMenu() } }
            .refreshable { await store.reload() }
            .navigationDestination(for: UUID.self) { id in
                if let receipt = store.receipt(id: id) {
                    ReceiptEditorView(receipt: receipt, isNew: false)
                }
            }
        }
    }
}

import SwiftUI
import QuickLook
import HSACore

/// Review/edit screen used both right after scanning (isNew) and when opening a saved receipt.
struct ReceiptEditorView: View {
    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("household") private var household = ""

    @State private var receipt: Receipt
    private let pendingAttachments: [PendingAttachment]
    private let isNew: Bool

    @State private var manualAmount: Bool
    @State private var previewURL: URL?
    @State private var confirmDelete = false
    @State private var showExport = false
    @State private var isSaving = false

    init(receipt: Receipt, pendingAttachments: [PendingAttachment] = [], isNew: Bool) {
        _receipt = State(initialValue: receipt)
        _manualAmount = State(initialValue: receipt.eligibleAmountOverride != nil)
        self.pendingAttachments = pendingAttachments
        self.isNew = isNew
    }

    private var familyMembers: [String] {
        household.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            verdictSection
            attachmentsSection
            detailsSection
            itemsSection
            amountSection
            reimbursementSection
            Section("Notes") {
                TextField("e.g. Emma's ear infection, Rx for amoxicillin", text: $receipt.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
            if !receipt.rawText.isEmpty {
                Section {
                    DisclosureGroup("Recognized text") {
                        Text(receipt.rawText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            if !isNew {
                Section {
                    Button { showExport = true } label: { Label("Export for HSA upload", systemImage: "square.and.arrow.up") }
                    Button("Delete receipt", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "New receipt" : (receipt.merchant.isEmpty ? "Receipt" : receipt.merchant))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(isSaving)
            }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Delete this receipt and its files?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(receipt)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(receipts: [receipt])
        }
    }

    // MARK: Sections

    private var verdictSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    EligibilityBadge(eligibility: receipt.eligibility, compact: false)
                    Spacer()
                    Menu {
                        ForEach(Eligibility.allCases, id: \.self) { e in
                            Button(e.label) { receipt.eligibility = e }
                        }
                    } label: {
                        Text("Change").font(.caption)
                    }
                }
                Text(receipt.eligibleAmount.currency)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text("HSA-eligible amount" + (receipt.total.map { " of \($0.currency)" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !receipt.eligibilityReason.isEmpty {
                    Text(receipt.eligibilityReason).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var attachmentsSection: some View {
        Section("Receipt") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pendingAttachments) { attachment in
                        if let preview = attachment.preview {
                            Image(uiImage: preview).resizable().scaledToFill()
                                .frame(width: 90, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    ForEach(store.attachmentURLs(for: receipt), id: \.self) { url in
                        Button { previewURL = url } label: { AttachmentThumbnail(url: url) }
                            .buttonStyle(.plain)
                    }
                    if pendingAttachments.isEmpty && receipt.attachments.isEmpty {
                        Text("No image attached").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Merchant or provider", text: $receipt.merchant)
            DatePicker("Date", selection: $receipt.date, displayedComponents: .date)
            LabeledContent("Total") {
                TextField("0.00", value: $receipt.total, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if familyMembers.isEmpty {
                TextField("For (family member)", text: $receipt.patient)
            } else {
                Picker("For", selection: $receipt.patient) {
                    Text("—").tag("")
                    ForEach(familyMembers, id: \.self) { Text($0).tag($0) }
                    if !receipt.patient.isEmpty && !familyMembers.contains(receipt.patient) {
                        Text(receipt.patient).tag(receipt.patient)
                    }
                }
            }
            Picker("Type", selection: $receipt.merchantKind) {
                Text("Store").tag(MerchantKind.general)
                Text("Pharmacy").tag(MerchantKind.pharmacy)
                Text("Doctor / dentist / vision").tag(MerchantKind.medicalProvider)
            }
            if !receipt.addedBy.isEmpty {
                LabeledContent("Added by", value: receipt.addedBy)
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach($receipt.items) { $item in
                LineItemRow(item: $item)
            }
            .onDelete { receipt.items.remove(atOffsets: $0) }
            Button {
                receipt.items.append(LineItem(text: "", amount: 0, eligibility: .likely, userOverride: true))
            } label: {
                Label("Add line item", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("Items (\(receipt.items.count))")
                Spacer()
                Button("Re-check") { ReceiptAnalyzer.reclassify(&receipt) }
                    .font(.caption)
            }
        } footer: {
            Text("Tap a badge to change it. Only “Eligible” items count toward the HSA amount; sales tax is prorated.")
        }
    }

    private var amountSection: some View {
        Section {
            Toggle("Set eligible amount manually", isOn: $manualAmount)
                .onChange(of: manualAmount) { _, on in
                    receipt.eligibleAmountOverride = on ? receipt.eligibleAmount : nil
                }
            if manualAmount {
                LabeledContent("Eligible amount") {
                    TextField("0.00", value: $receipt.eligibleAmountOverride, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let printed = receipt.storeReportedEligibleTotal {
                LabeledContent("Store-printed FSA/HSA total", value: printed.currency)
            }
            LabeledContent("Calculated from items", value: receipt.computedEligibleAmount.currency)
        } header: {
            Text("Eligible amount")
        }
    }

    private var reimbursementSection: some View {
        Section("Reimbursement") {
            Toggle("Reimbursed from HSA", isOn: Binding(
                get: { receipt.reimbursed },
                set: { receipt.reimbursed = $0; receipt.reimbursedOn = $0 ? (receipt.reimbursedOn ?? Date()) : nil }
            ))
            if receipt.reimbursed {
                DatePicker("Reimbursed on", selection: Binding(
                    get: { receipt.reimbursedOn ?? Date() },
                    set: { receipt.reimbursedOn = $0 }
                ), displayedComponents: .date)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let ok = await store.save(receipt, newAttachments: isNew ? pendingAttachments : [])
            isSaving = false
            if ok { dismiss() }
        }
    }
}

struct LineItemRow: View {
    @Binding var item: LineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Item", text: $item.text)
                TextField("0.00", value: $item.amount, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .monospacedDigit()
            }
            HStack {
                Menu {
                    ForEach(Eligibility.allCases, id: \.self) { e in
                        Button {
                            item.eligibility = e
                            item.userOverride = true
                        } label: { Label(e.label, systemImage: e.symbol) }
                    }
                } label: {
                    EligibilityBadge(eligibility: item.eligibility)
                }
                if let reason = item.reason {
                    Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

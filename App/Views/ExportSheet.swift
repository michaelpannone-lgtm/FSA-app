import SwiftUI
import HSACore

/// Creates the files you upload to your HSA provider, then optionally marks the receipts reimbursed.
struct ExportSheet: View {
    enum Format: String, CaseIterable, Identifiable {
        case combined = "One combined PDF"
        case individual = "One PDF per receipt"
        var id: String { rawValue }
    }

    let receipts: [Receipt]
    var onMarkedReimbursed: (() -> Void)? = nil

    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    @AppStorage("accountHolder") private var accountHolder = ""

    @State private var format: Format = .combined
    @State private var files: [URL] = []
    @State private var reimbursedOn = Date()
    @State private var didMark = false
    @State private var errorText: String?

    private var total: Decimal { receipts.reduce(Decimal(0)) { $0 + $1.eligibleAmount } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Receipts", value: "\(receipts.count)")
                    LabeledContent("Total eligible", value: total.currency).font(.headline)
                    TextField("Account holder name", text: $accountHolder)
                }

                Section {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: format) { _, _ in files = [] }
                } header: {
                    Text("Format")
                } footer: {
                    Text("Each PDF starts with a summary page (dates, providers, amounts, total) followed by the itemized receipt images. Most HSA providers accept PDF uploads for “reimburse myself” claims.")
                }

                Section {
                    if files.isEmpty {
                        Button {
                            build()
                        } label: {
                            Label("Create PDF\(format == .individual && receipts.count > 1 ? "s" : "")", systemImage: "doc.richtext")
                        }
                    } else {
                        ShareLink(items: files) {
                            Label("Share, save to Files, or upload", systemImage: "square.and.arrow.up")
                        }
                        ForEach(files, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "doc.fill")
                                .font(.footnote)
                                .lineLimit(1)
                        }
                    }
                    if let errorText {
                        Text(errorText).foregroundStyle(.red).font(.footnote)
                    }
                } footer: {
                    if !files.isEmpty {
                        Text("A copy is also saved in the Exports folder next to your receipts.")
                    }
                }

                if receipts.contains(where: { !$0.reimbursed }) {
                    Section {
                        DatePicker("Reimbursed on", selection: $reimbursedOn, displayedComponents: .date)
                        Button {
                            Task {
                                await store.markReimbursed(ids: receipts.map(\.id), on: reimbursedOn)
                                didMark = true
                                onMarkedReimbursed?()
                            }
                        } label: {
                            Label(didMark ? "Marked as reimbursed" : "Mark these as reimbursed",
                                  systemImage: didMark ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .disabled(didMark)
                    } footer: {
                        Text("Do this after your HSA provider accepts the claim so your available balance stays accurate.")
                    }
                }
            }
            .navigationTitle("Export for HSA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if accountHolder.isEmpty { accountHolder = userName } }
        }
    }

    private func build() {
        errorText = nil
        let options = ClaimPacketExporter.Options(claimant: accountHolder)
        do {
            switch format {
            case .combined:
                files = [try ClaimPacketExporter.combinedPacket(for: receipts, store: store, options: options)]
            case .individual:
                files = try ClaimPacketExporter.individualFiles(for: receipts, store: store, options: options)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

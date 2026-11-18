import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import HSACore

struct SettingsView: View {
    @EnvironmentObject private var store: ReceiptStore
    @AppStorage("userName") private var userName = ""
    @AppStorage("accountHolder") private var accountHolder = ""
    @AppStorage("household") private var household = ""
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Saving to", value: store.folderDisplayName)
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label(store.isUsingChosenFolder ? "Choose a different folder" : "Choose iCloud Drive folder",
                              systemImage: "icloud")
                    }
                    if store.isUsingChosenFolder {
                        Button("Stop using this folder", role: .destructive) { store.useLocalStorage() }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Receipts are saved as normal files (images/PDFs + a small .json each) plus an “HSA Ledger.csv” spreadsheet, so you can browse them in the Files app even without this app.")
                }

                Section {
                    TextField("Your name (shown as “Added by”)", text: $userName)
                    TextField("HSA account holder (for exports)", text: $accountHolder)
                    TextField("Family members, comma separated", text: $household)
                } header: {
                    Text("Household")
                } footer: {
                    Text("Family members appear in the “For” picker on each receipt.")
                }

                Section("Export") {
                    ShareLink(item: LedgerExport(csv: LedgerExporter.csv(for: store.receipts)),
                              preview: SharePreview("HSA Ledger.csv")) {
                        Label("Share full ledger (CSV)", systemImage: "tablecells")
                    }
                }

                Section("Sharing with your spouse") {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "On your iPhone, open Files › iCloud Drive and create a folder named “HSA Receipts”.")
                        step(2, "Long-press the folder › Share › Collaborate. Set “Who can access” to Only invited people and “Permission” to Can make changes, then invite your spouse.")
                        step(3, "Your spouse accepts the invite; the folder appears in their iCloud Drive.")
                        step(4, "On both phones: Settings › Choose iCloud Drive folder › pick “HSA Receipts”.")
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                }

                Section {
                    Text("Eligibility is an estimate from keyword rules based on IRS Publication 502 and the CARES Act (OTC medicine and menstrual products qualify without a prescription). “Maybe” items usually need a Letter of Medical Necessity. Always keep receipts and check with your HSA provider or tax advisor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("IRS Publication 502", destination: URL(string: "https://www.irs.gov/publications/p502")!)
                } header: {
                    Text("About eligibility")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.useFolder(url) }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}

struct LedgerExport: Transferable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("HSA Ledger.csv")
            try Data(export.csv.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

import Foundation
import SwiftUI
import HSACore

/// A file waiting to be written alongside a new receipt.
struct PendingAttachment: Identifiable {
    let id = UUID()
    var data: Data
    var fileExtension: String
    var preview: UIImage?
}

/// Owns the list of receipts and reads/writes them in the chosen folder.
///
/// Layout inside the chosen (ideally shared iCloud Drive) folder:
///   HSA Receipts/
///     Receipts/2026/2026-11-02 CVS Pharmacy 25.20 a1b2c3.json
///     Receipts/2026/2026-11-02 CVS Pharmacy 25.20 a1b2c3-1.jpg
///     HSA Ledger.csv
///     Exports/  (claim packets you generated)
@MainActor
final class ReceiptStore: ObservableObject {
    @Published private(set) var receipts: [Receipt] = []
    @Published private(set) var rootURL: URL
    @Published private(set) var isUsingChosenFolder = false
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private var locations: [UUID: URL] = [:]
    private var accessedURL: URL?
    private let bookmarkKey = "storageFolderBookmark"

    init() {
        rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        restoreBookmark()
    }

    var receiptsDirectory: URL { rootURL.appendingPathComponent("Receipts", isDirectory: true) }
    var exportsDirectory: URL { rootURL.appendingPathComponent("Exports", isDirectory: true) }
    var ledgerURL: URL { rootURL.appendingPathComponent("HSA Ledger.csv") }
    var folderDisplayName: String { isUsingChosenFolder ? rootURL.lastPathComponent : "This iPhone only (not shared)" }

    // MARK: Folder selection

    func useFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "iOS didn't grant access to that folder. Try choosing it again."
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            lastError = "Couldn't remember that folder: \(error.localizedDescription)"
        }
        if let old = accessedURL, old != url { old.stopAccessingSecurityScopedResource() }
        accessedURL = url
        rootURL = url
        isUsingChosenFolder = true
        Task { await reload() }
    }

    func useLocalStorage() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        isUsingChosenFolder = false
        Task { await reload() }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else {
                lastError = "Lost access to your receipts folder. Choose it again in Settings."
                return
            }
            if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            accessedURL = url
            rootURL = url
            isUsingChosenFolder = true
        } catch {
            lastError = "Couldn't reopen your receipts folder. Choose it again in Settings."
        }
    }

    // MARK: Loading & saving

    func reload() async {
        isLoading = true
        let dir = receiptsDirectory
        let loaded = await Task.detached(priority: .userInitiated) { FileIO.loadReceipts(in: dir) }.value
        locations = Dictionary(loaded.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a })
        receipts = loaded.map(\.0).sorted { $0.date > $1.date }
        isLoading = false
    }

    func receipt(id: UUID) -> Receipt? { receipts.first { $0.id == id } }

    func attachmentURL(for receipt: Receipt, name: String) -> URL? {
        locations[receipt.id]?.deletingLastPathComponent().appendingPathComponent(name)
    }

    func attachmentURLs(for receipt: Receipt) -> [URL] {
        receipt.attachments.compactMap { attachmentURL(for: receipt, name: $0) }
    }

    @discardableResult
    func save(_ input: Receipt, newAttachments: [PendingAttachment] = []) async -> Bool {
        var receipt = input
        receipt.updatedAt = Date()
        if receipt.baseName.isEmpty { receipt.baseName = FileIO.baseName(for: receipt) }

        let folder: URL
        if let existing = locations[receipt.id] {
            folder = existing.deletingLastPathComponent()
        } else {
            folder = receiptsDirectory.appendingPathComponent(String(receipt.year), isDirectory: true)
        }

        let startIndex = receipt.attachments.count
        let newNames = newAttachments.enumerated().map { "\(receipt.baseName)-\(startIndex + $0.offset + 1).\($0.element.fileExtension)" }
        receipt.attachments += newNames
        let payloads = newAttachments.map(\.data)
        let jsonURL = locations[receipt.id] ?? folder.appendingPathComponent("\(receipt.baseName).json")
        let toWrite = receipt

        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (index, data) in payloads.enumerated() {
                    try FileIO.coordinatedWrite(data, to: folder.appendingPathComponent(newNames[index]))
                }
                try FileIO.coordinatedWrite(try JSONEncoder.hsa.encode(toWrite), to: jsonURL)
            }.value
        } catch {
            lastError = "Couldn't save the receipt: \(error.localizedDescription)"
            return false
        }

        locations[receipt.id] = jsonURL
        if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
            receipts[index] = receipt
        } else {
            receipts.append(receipt)
        }
        receipts.sort { $0.date > $1.date }
        await writeLedger()
        return true
    }

    func delete(_ receipt: Receipt) async {
        guard let jsonURL = locations[receipt.id] else { return }
        let urls = [jsonURL] + attachmentURLs(for: receipt)
        await Task.detached { urls.forEach(FileIO.coordinatedDelete) }.value
        locations[receipt.id] = nil
        receipts.removeAll { $0.id == receipt.id }
        await writeLedger()
    }

    /// Marks receipts reimbursed (used after exporting a claim packet).
    func markReimbursed(ids: [UUID], on date: Date = Date()) async {
        for id in ids {
            guard var item = self.receipt(id: id), !item.reimbursed else { continue }
            item.reimbursed = true
            item.reimbursedOn = date
            await save(item)
        }
    }

    func writeLedger() async {
        let csv = LedgerExporter.csv(for: receipts)
        let url = ledgerURL
        let root = rootURL
        await Task.detached {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? FileIO.coordinatedWrite(Data(csv.utf8), to: url)
        }.value
    }

    // MARK: Dashboard numbers

    var reimbursable: [Receipt] { receipts.filter { !$0.reimbursed && $0.eligibleAmount > 0 } }
    var unreimbursedBalance: Decimal { reimbursable.reduce(Decimal(0)) { $0 + $1.eligibleAmount } }
    var needsReviewCount: Int { receipts.filter { $0.eligibility == .unknown || $0.eligibility == .maybe }.count }
}

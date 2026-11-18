import Foundation
import HSACore

/// Coordinated file access so reads/writes cooperate with iCloud Drive syncing
/// (and trigger downloads of files that are still only in the cloud).
enum FileIO {
    static func coordinatedRead(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            result = try? Data(contentsOf: readURL)
        }
        return result
    }

    static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing,
                                                         error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func coordinatedDelete(_ url: URL) {
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &error) { deleteURL in
            try? FileManager.default.removeItem(at: deleteURL)
        }
    }

    /// Finds every receipt JSON under `directory` (any year sub-folder).
    static func loadReceipts(in directory: URL) -> [(Receipt, URL)] {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil, options: []) else { return [] }

        var found: [(Receipt, URL)] = []
        let decoder = JSONDecoder.hsa
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            // Older iCloud placeholder format: ".Name.json.icloud" — ask iCloud to download it.
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let realName = String(name.dropFirst().dropLast(".icloud".count))
                try? fm.startDownloadingUbiquitousItem(at: url.deletingLastPathComponent().appendingPathComponent(realName))
                continue
            }
            guard url.pathExtension.lowercased() == "json", !name.hasPrefix(".") else { continue }
            if let data = coordinatedRead(url), let receipt = try? decoder.decode(Receipt.self, from: data) {
                found.append((receipt, url))
            }
        }
        return found
    }

    /// "2026-11-02 CVS Pharmacy 25.20 a1b2c3"
    static func baseName(for receipt: Receipt) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -&'"))
        let merchant = String(String.UnicodeScalarView(receipt.merchant.unicodeScalars.filter { allowed.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        let parts = [f.string(from: receipt.date),
                     merchant.isEmpty ? "Receipt" : String(merchant.prefix(40)),
                     receipt.total?.plainString,
                     String(receipt.id.uuidString.prefix(6)).lowercased()]
        return parts.compactMap { $0 }.joined(separator: " ")
    }
}

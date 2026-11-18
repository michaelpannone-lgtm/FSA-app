import Foundation
import UIKit
import PDFKit
import HSACore

/// Builds PDFs to upload to an HSA provider's "reimburse myself" / "submit documentation" page.
///
/// - Combined packet: a summary page (claimant, date range, each receipt and its eligible amount, total)
///   followed by every receipt image/PDF page, each stamped with its line number.
/// - Individual files: one PDF per receipt for portals that want one document per claim.
@MainActor
enum ClaimPacketExporter {
    struct Options {
        var claimant: String
        var title: String = "HSA Reimbursement Documentation"
    }

    static func combinedPacket(for receipts: [Receipt], store: ReceiptStore, options: Options) throws -> URL {
        let sorted = receipts.sorted { $0.date < $1.date }
        let attachmentURLs = sorted.map { store.attachmentURLs(for: $0) }
        let total = sorted.reduce(Decimal(0)) { $0 + $1.eligibleAmount }

        let document = PDFDocument()
        if let summary = PDFDocument(data: summaryPage(for: sorted, total: total, options: options)) {
            append(summary, to: document)
        }
        for (index, receipt) in sorted.enumerated() {
            appendReceipt(receipt, number: index + 1, files: attachmentURLs[index], to: document)
        }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let name = "HSA Claim \(f.string(from: Date())) $\(total.plainString).pdf"
        return try write(document, named: name, store: store)
    }

    static func individualFiles(for receipts: [Receipt], store: ReceiptStore, options: Options) throws -> [URL] {
        try receipts.sorted { $0.date < $1.date }.map { receipt in
            let document = PDFDocument()
            if let summary = PDFDocument(data: summaryPage(for: [receipt], total: receipt.eligibleAmount, options: options)) {
                append(summary, to: document)
            }
            appendReceipt(receipt, number: 1, files: store.attachmentURLs(for: receipt), to: document)
            let safeName = receipt.baseName.isEmpty ? receipt.id.uuidString : receipt.baseName
            return try write(document, named: "\(safeName).pdf", store: store)
        }
    }

    // MARK: Building blocks

    private static func appendReceipt(_ receipt: Receipt, number: Int, files: [URL], to document: PDFDocument) {
        let label = "#\(number)  \(receipt.merchant)  \(receipt.date.formatted(date: .abbreviated, time: .omitted))  eligible $\(receipt.eligibleAmount.plainString)"
        for url in files {
            guard let data = FileIO.coordinatedRead(url) else { continue }
            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(data: data) {
                append(pdf, to: document)
            } else if let image = UIImage(data: data),
                      let pagePDF = PDFDocument(data: imagePage(image, label: label)) {
                append(pagePDF, to: document)
            }
        }
    }

    private static func append(_ source: PDFDocument, to target: PDFDocument) {
        for index in 0..<source.pageCount {
            if let page = source.page(at: index)?.copy() as? PDFPage {
                target.insert(page, at: target.pageCount)
            }
        }
    }

    private static func write(_ document: PDFDocument, named name: String, store: ReceiptStore) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        guard let data = document.dataRepresentation() else {
            throw NSError(domain: "HSAReceipts", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't build the PDF."])
        }
        try data.write(to: url, options: .atomic)
        // Keep a copy next to the receipts so you (and your spouse) have a record of what was submitted.
        let archive = store.exportsDirectory
        Task.detached {
            try? FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try? FileIO.coordinatedWrite(data, to: archive.appendingPathComponent(url.lastPathComponent))
        }
        return url
    }

    nonisolated static let pageSize = CGSize(width: 612, height: 792) // US Letter

    nonisolated private static func summaryPage(for receipts: [Receipt], total: Decimal, options: Options) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let margin: CGFloat = 48
        let width = pageSize.width - margin * 2

        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let boldFont = UIFont.boldSystemFont(ofSize: 11)
        let small = UIFont.systemFont(ofSize: 9)

        func draw(_ text: String, font: UIFont, at point: CGPoint, width: CGFloat = 0, align: NSTextAlignment = .left,
                  color: UIColor = .black) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
            if width > 0 {
                (text as NSString).draw(in: CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight + 2),
                                        withAttributes: attributes)
            } else {
                (text as NSString).draw(at: point, withAttributes: attributes)
            }
        }

        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("#", 24, .left), ("Date", 78, .left), ("Merchant / provider", 190, .left), ("For", 80, .left),
            ("Receipt total", 72, .right), ("Eligible", 72, .right)
        ]

        return renderer.pdfData { context in
            var y: CGFloat = 0
            func newPage(first: Bool) {
                context.beginPage()
                y = margin
                if first {
                    draw(options.title, font: titleFont, at: CGPoint(x: margin, y: y))
                    y += 30
                    let dates = receipts.map(\.date)
                    let range: String
                    if let lo = dates.min(), let hi = dates.max() {
                        range = "\(lo.formatted(date: .abbreviated, time: .omitted)) – \(hi.formatted(date: .abbreviated, time: .omitted))"
                    } else { range = "—" }
                    draw("Account holder: \(options.claimant.isEmpty ? "—" : options.claimant)", font: bodyFont, at: CGPoint(x: margin, y: y)); y += 16
                    draw("Prepared: \(Date().formatted(date: .long, time: .omitted))", font: bodyFont, at: CGPoint(x: margin, y: y)); y += 16
                    draw("Dates of service/purchase: \(range)", font: bodyFont, at: CGPoint(x: margin, y: y)); y += 16
                    draw("Receipts: \(receipts.count)    Total requested: $\(total.plainString)", font: boldFont, at: CGPoint(x: margin, y: y)); y += 28
                }
                var x = margin
                for column in columns {
                    draw(column.0, font: boldFont, at: CGPoint(x: x, y: y), width: column.1, align: column.2)
                    x += column.1
                }
                y += 18
                context.cgContext.setStrokeColor(UIColor.gray.cgColor)
                context.cgContext.stroke(CGRect(x: margin, y: y - 3, width: width, height: 0.5))
            }

            newPage(first: true)
            for (index, receipt) in receipts.enumerated() {
                if y > pageSize.height - margin - 60 { newPage(first: false) }
                let values = [
                    "\(index + 1)",
                    receipt.date.formatted(date: .numeric, time: .omitted),
                    receipt.merchant.isEmpty ? "Receipt" : receipt.merchant,
                    receipt.patient,
                    receipt.total.map { "$\($0.plainString)" } ?? "",
                    "$\(receipt.eligibleAmount.plainString)"
                ]
                var x = margin
                for (column, value) in zip(columns, values) {
                    draw(value, font: bodyFont, at: CGPoint(x: x, y: y), width: column.1, align: column.2)
                    x += column.1
                }
                y += 16
            }
            context.cgContext.stroke(CGRect(x: margin, y: y, width: width, height: 0.5))
            y += 6
            draw("Total", font: boldFont, at: CGPoint(x: margin, y: y))
            draw("$\(total.plainString)", font: boldFont, at: CGPoint(x: margin + width - 72, y: y), width: 72, align: .right)
            y += 30
            draw("Itemized receipts follow. Eligible amounts include prorated sales tax on qualifying items.",
                 font: small, at: CGPoint(x: margin, y: y), color: .darkGray)
        }
    }

    nonisolated private static func imagePage(_ image: UIImage, label: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            let margin: CGFloat = 36
            let header: CGFloat = 24
            (label as NSString).draw(at: CGPoint(x: margin, y: margin - 12),
                                     withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black])
            let box = CGRect(x: margin, y: margin + header - 12, width: pageSize.width - margin * 2,
                             height: pageSize.height - margin * 2 - header + 12)
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.minY, width: size.width, height: size.height))
        }
    }
}

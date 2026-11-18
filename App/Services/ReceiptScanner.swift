import Foundation
import UIKit
import Vision
import PDFKit
import UniformTypeIdentifiers
import HSACore

/// On-device OCR (Apple Vision) + analysis. Nothing leaves the phone.
enum ReceiptScanner {
    struct Draft: Identifiable {
        let id = UUID()
        var receipt: Receipt
        var attachments: [PendingAttachment]
    }

    /// Camera scans or photos.
    static func analyze(images: [UIImage], addedBy: String) async -> Draft {
        var lines: [String] = []
        var attachments: [PendingAttachment] = []
        for image in images {
            let normalized = image.normalizedForUpload()
            if let cg = normalized.cgImage, let fragments = try? await recognize(cg) {
                lines += RowAssembler.lines(from: fragments)
            }
            if let jpeg = normalized.jpegData(compressionQuality: 0.75) {
                attachments.append(PendingAttachment(data: jpeg, fileExtension: "jpg", preview: normalized))
            }
        }
        var receipt = ReceiptAnalyzer.analyze(lines: lines)
        receipt.addedBy = addedBy
        return Draft(receipt: receipt, attachments: attachments)
    }

    /// PDFs (e.g. emailed receipts, provider statements) or image files from the Files app.
    static func analyze(fileAt url: URL, addedBy: String) async throws -> Draft {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = FileIO.coordinatedRead(url) else {
            throw NSError(domain: "HSAReceipts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't read that file."])
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data

        if type.conforms(to: .pdf), let document = PDFDocument(data: data) {
            var lines = (document.string ?? "").components(separatedBy: .newlines)
            let preview = document.page(at: 0)?.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
            if lines.joined().trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                // Scanned PDF with no text layer: render pages and OCR them.
                lines = []
                for index in 0..<min(document.pageCount, 5) {
                    guard let page = document.page(at: index) else { continue }
                    let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
                    if let cg = image.cgImage, let fragments = try? await recognize(cg) {
                        lines += RowAssembler.lines(from: fragments)
                    }
                }
            }
            var receipt = ReceiptAnalyzer.analyze(lines: lines)
            receipt.addedBy = addedBy
            return Draft(receipt: receipt, attachments: [PendingAttachment(data: data, fileExtension: "pdf", preview: preview)])
        }

        guard let image = UIImage(data: data) else {
            throw NSError(domain: "HSAReceipts", code: 2, userInfo: [NSLocalizedDescriptionKey: "That file isn't an image or PDF."])
        }
        return await analyze(images: [image], addedBy: addedBy)
    }

    static func recognize(_ image: CGImage) async throws -> [TextFragment] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                    let observations = request.results ?? []
                    let fragments = observations.compactMap { observation -> TextFragment? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let box = observation.boundingBox // origin bottom-left
                        return TextFragment(text: candidate.string, x: Double(box.minX),
                                            y: Double(1 - box.midY), height: Double(box.height))
                    }
                    continuation.resume(returning: fragments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension UIImage {
    /// Applies EXIF orientation and caps the long edge so files stay small in iCloud.
    func normalizedForUpload(maxDimension: CGFloat = 2400) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

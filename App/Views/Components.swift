import SwiftUI
import VisionKit
import PDFKit
import HSACore

/// Apple's document camera: auto edge detection, perspective correction, multi-page.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

/// Thumbnail for a saved attachment (image or PDF), loaded off the main thread.
struct AttachmentThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(width: 90, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: url) {
            let target = url
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let data = FileIO.coordinatedRead(target) else { return nil }
                if target.pathExtension.lowercased() == "pdf" {
                    return PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 270, height: 360), for: .mediaBox)
                }
                return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 270, height: 360))
            }.value
        }
    }
}

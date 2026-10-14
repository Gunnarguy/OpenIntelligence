//
//  SystemDocumentScanner.swift
//  OpenIntelligence
//

#if os(iOS)
    import PDFKit
    import SwiftUI
    import UIKit
    import VisionKit

    /// Apple's document scanner, the one Notes and Files use, for "Scan a Document" (5.7).
    ///
    /// 5.7's first version of that action opened `CameraVisionOverlayView`, the app's own camera,
    /// which the owner keeps to Debug builds (decided 2026-09-13; `ChatScreen.visionCaptureAction`).
    /// That made the held camera reachable in a Release build from the action, the Home Screen
    /// quick action and `openintelligence://chat/scan`. The system scanner finds the page edges,
    /// straightens them and runs its own camera session, so the action works without releasing
    /// the app's camera. The pages are saved as one PDF and imported like any file.
    struct SystemDocumentScanner: UIViewControllerRepresentable {
        /// The scan, whose pages are read one at a time when it is saved.
        let onScan: (VNDocumentCameraScan) -> Void
        /// Cancelled, or the scanner failed (the error says which).
        let onDismiss: (Error?) -> Void

        static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let controller = VNDocumentCameraViewController()
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_: VNDocumentCameraViewController, context _: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onDismiss: onDismiss) }

        final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            let onScan: (VNDocumentCameraScan) -> Void
            let onDismiss: (Error?) -> Void

            init(onScan: @escaping (VNDocumentCameraScan) -> Void, onDismiss: @escaping (Error?) -> Void) {
                self.onScan = onScan
                self.onDismiss = onDismiss
            }

            func documentCameraViewController(
                _: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
            ) {
                onScan(scan)
            }

            func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
                onDismiss(nil)
            }

            func documentCameraViewController(_: VNDocumentCameraViewController, didFailWithError error: Error) {
                onDismiss(error)
            }
        }
    }

    /// Scanned pages as one PDF in the imported-documents folder, where the import queue reads.
    nonisolated enum ScannedDocument {
        enum StoreError: LocalizedError {
            case noPages

            var errorDescription: String? { "The scan had no pages that could be saved." }
        }

        /// JPEG quality for each page. A full-quality 12-megapixel page is several megabytes, and
        /// the text is read from the image by OCR either way.
        static let compressionQuality = 0.75

        static func storePDF(pages: [UIImage], title: String, now: Date = Date()) throws -> URL {
            let document = PDFDocument()
            for image in pages {
                autoreleasepool { append(image, to: document) }
            }
            return try store(document, title: title, now: now)
        }

        /// One page, compressed, at the end of the document.
        static func append(_ image: UIImage, to document: PDFDocument) {
            if let page = PDFPage(image: image, options: [.compressionQuality: compressionQuality]) {
                document.insert(page, at: document.pageCount)
            }
        }

        static func store(_ document: PDFDocument, title: String, now: Date = Date()) throws -> URL {
            guard document.pageCount > 0, let data = document.dataRepresentation() else {
                throw StoreError.noPages
            }
            return try IntentSupport.store(data, preferredFileName: fileName(title: title, now: now))
        }

        /// The scanner's title when it has one of its own, then the date, so two scans of a day
        /// are told apart in the library: "Lease 2026-10-14 10.32.pdf".
        static func fileName(title: String, now: Date) -> String {
            let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
            let stem = title.components(separatedBy: forbidden).joined(separator: " ")
                .split(separator: " ").joined(separator: " ")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH.mm"
            return "\(stem.isEmpty ? "Scan" : stem) \(formatter.string(from: now)).pdf"
        }
    }
#endif

//
//  ScannedDocumentTests.swift
//  OpenIntelligenceTests
//
//  "Scan a Document" saves the system scanner's pages as one PDF and imports it (5.7).
//

#if os(iOS)
    import PDFKit
    import UIKit
    import XCTest

    @testable import OpenIntelligence

    final class ScannedDocumentTests: XCTestCase {
        private func page(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 850, height: 1100)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 850, height: 1100))
            }
        }

        func testPagesBecomeOnePDFInTheImportFolder() throws {
            let file = try ScannedDocument.storePDF(pages: [page(.white), page(.lightGray)], title: "Lease")
            defer { try? FileManager.default.removeItem(at: file) }
            XCTAssertEqual(file.pathExtension, "pdf")
            XCTAssertEqual(
                file.deletingLastPathComponent().standardizedFileURL,
                AppSupportPaths.importedDocumentsDirectoryURL().standardizedFileURL)
            let document = try XCTUnwrap(PDFDocument(url: file))
            XCTAssertEqual(document.pageCount, 2)
        }

        func testAScanWithNoPagesIsRefused() {
            XCTAssertThrowsError(try ScannedDocument.storePDF(pages: [], title: "Empty"))
        }

        func testNameIsTheScannersTitleThenTheTime() {
            var components = DateComponents()
            (components.year, components.month, components.day, components.hour, components.minute) = (2026, 10, 14, 10, 32)
            let now = try! XCTUnwrap(Calendar.current.date(from: components))
            XCTAssertEqual(ScannedDocument.fileName(title: "Lease", now: now), "Lease 2026-10-14 10.32.pdf")
            XCTAssertEqual(ScannedDocument.fileName(title: "a/b: c", now: now), "a b c 2026-10-14 10.32.pdf")
            XCTAssertEqual(ScannedDocument.fileName(title: "  ", now: now), "Scan 2026-10-14 10.32.pdf")
        }
    }
#endif

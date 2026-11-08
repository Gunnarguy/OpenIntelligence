//
//  ExtractionPageProgressTests.swift
//  OpenIntelligenceTests
//
//  A PDF's extraction reports the pages it has finished (5.8). On the owner's iPhone on 2026-11-07 the import's
//  background task stayed at 4% for 71 s while nine of ten pages were read, because every report during a batch named
//  the batch's first page, and one named its last before any page was read; iOS ended the task. These read a real
//  six-page PDF through `DocumentProcessor` and look at what its rich progress handler was told.
//

import XCTest

@testable import OpenIntelligence

#if canImport(UIKit)
    import UIKit

    @MainActor
    final class ExtractionPageProgressTests: XCTestCase {
        private func sixPagePDF() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "progress-test-\(UUID().uuidString.prefix(8)).pdf")
            let marker = UUID().uuidString  // a new fingerprint, so no saved pages are loaded
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            let data = renderer.pdfData { context in
                for page in 1...6 {
                    context.beginPage()
                    let text = (1...12).map {
                        "Page \(page), paragraph \($0): the tenant pays rent of 1,250 dollars on the first day of each month. \(marker)"
                    }.joined(separator: "\n\n")
                    (text as NSString).draw(
                        in: CGRect(x: 40, y: 40, width: 532, height: 700),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                }
            }
            try data.write(to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
            return url
        }

        func testExtractionReportsEachFinishedPageAndNeverClaimsTheEndFirst() async throws {
            let processor = DocumentProcessor()
            var reports: [(stage: String, page: Int)] = []
            processor.richProgressHandler = { progress in
                if let page = progress.currentPage, progress.totalPages == 6 {
                    reports.append((progress.stage, page))
                }
            }
            _ = try await processor.processDocument(at: try sixPagePDF())

            let extraction = reports.filter { ["vision", "render", "layout", "structure"].contains($0.stage) }
            try XCTSkipIf(extraction.isEmpty, "this PDF did not take the structured-parsing path here")
            XCTAssertLessThan(
                extraction[0].page, 6, "the first report said all six pages were done: \(extraction.map(\.page))")
            let pagesRead = extraction.filter { $0.stage == "structure" }.map(\.page)
            XCTAssertTrue(
                pagesRead.contains { (1..<6).contains($0) },
                "no report between the first page and the last: \(extraction.map { "\($0.stage):\($0.page)" })")
            XCTAssertEqual(pagesRead.max(), 6)
        }
    }
#endif

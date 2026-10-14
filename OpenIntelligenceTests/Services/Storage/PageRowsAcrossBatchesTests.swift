//
//  PageRowsAcrossBatchesTests.swift
//  OpenIntelligenceTests
//
//  A PDF imported in batches keeps a page row for every page (5.7). Through 5.6 each batch's text
//  store deleted the page rows of the batches before it; `DocumentProcessor.storeText` keeps them.
//

import XCTest

@testable import OpenIntelligence

final class PageRowsAcrossBatchesTests: XCTestCase {
    func testEveryBatchKeepsItsPagesAndAResumedBatchIsNotDoubled() async {
        let library = UUID()
        let document = UUID()
        // One word no other test or document uses, on every page.
        let marker = "q" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        func storeBatch(_ batch: Int) async {
            let pages = (1...3).map { index in
                (pageNumber: (batch - 1) * 3 + index, content: "\(marker) page \((batch - 1) * 3 + index) text")
            }
            // What `processDocument(pageRange:)` calls for each batch of a large PDF.
            await DocumentProcessor.storeText(
                pages.map(\.content).joined(separator: "\n"), pages: pages, for: document, containerId: library,
                append: true)
        }

        for batch in 1...3 { await storeBatch(batch) }
        var found = await SQLiteFullTextService.shared.searchPages(query: marker, containerId: library, limit: 50)
        XCTAssertEqual(Set(found.map(\.pageNumber)), Set(1...9))
        XCTAssertEqual(found.count, 9)

        // An import resumed from its checkpoint stores batch 2 again.
        await storeBatch(2)
        found = await SQLiteFullTextService.shared.searchPages(query: marker, containerId: library, limit: 50)
        XCTAssertEqual(found.count, 9, "one row per page")

        await SQLiteFullTextService.shared.delete(for: document)
        found = await SQLiteFullTextService.shared.searchPages(query: marker, containerId: library, limit: 50)
        XCTAssertTrue(found.isEmpty, "deleting the document removes its pages")
    }

    func testPagesAreNumberedByThePagesThatHaveText() {
        // Pages 1, 3 and 4 of a batch that starts at page 16 had text; page 2 was blank, and a
        // blank page gets no page break, so the second piece is page 18.
        let pages = DocumentProcessor.numberedPages(
            splitting: "one|three|four", separator: "|", pagesWithText: [1, 3, 4], firstPageIndex: 15)
        XCTAssertEqual(pages.map(\.pageNumber), [16, 18, 19])
        XCTAssertEqual(pages.map(\.content), ["one", "three", "four"])
        // The last batch of a 31-page PDF holds one page and keeps its number.
        let last = DocumentProcessor.numberedPages(
            splitting: "thirty-one", separator: "|", pagesWithText: [1], firstPageIndex: 30)
        XCTAssertEqual(last.map(\.pageNumber), [31])
        // With no page numbers to go by, a piece's place is its number, as before 5.7.
        let unknown = DocumentProcessor.numberedPages(
            splitting: "a||b", separator: "|", pagesWithText: [], firstPageIndex: 0)
        XCTAssertEqual(unknown.map(\.pageNumber), [1, 2])
        XCTAssertEqual(unknown.map(\.content), ["a", "b"])
    }

    func testABatchsPagesReplaceTheSamePagesAndKeepTheRest() {
        let earlier = [(pageNumber: 1, content: "old one"), (pageNumber: 2, content: "old two")]
        let batch = [(pageNumber: 2, content: "new two"), (pageNumber: 3, content: "new three")]
        let rows = DocumentProcessor.pageRows(keeping: earlier, adding: batch)
        XCTAssertEqual(rows.map(\.pageNumber), [1, 2, 3])
        XCTAssertEqual(rows.map(\.content), ["old one", "new two", "new three"])
    }
}

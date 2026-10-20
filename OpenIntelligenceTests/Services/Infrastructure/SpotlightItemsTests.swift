//
//  SpotlightItemsTests.swift
//  OpenIntelligenceTests
//
//  Documents and libraries are Spotlight's app items, and their entries last (5.7).
//

import AppIntents
import CoreSpotlight
import XCTest

@testable import OpenIntelligence

@MainActor
final class SpotlightItemsTests: XCTestCase {
    func testADocumentsEntryDescribesWhereItIsAndHowBigItIs() {
        let document = OIDocumentEntity(
            id: UUID(), filename: "Lease.pdf", totalChunks: 48, kind: "pdf", pageCount: 12, libraryName: "Home")
        let attributes = document.attributeSet
        XCTAssertEqual(attributes.title, "Lease.pdf")
        XCTAssertEqual(attributes.contentDescription, "In Home, 12 pages, 48 passages")

        let single = OIDocumentEntity(id: UUID(), filename: "Note.txt", totalChunks: 1)
        XCTAssertEqual(single.attributeSet.contentDescription, "1 passage")
    }

    func testALibrarysEntryCountsItsDocumentsAndPassages() {
        let library = OILibraryEntity(id: UUID(), name: "Home", totalDocuments: 3, totalChunks: 120)
        XCTAssertEqual(library.attributeSet.title, "Home")
        XCTAssertEqual(library.attributeSet.contentDescription, "3 documents, 120 passages")
    }

    /// Entries no longer expire, so a load removes those of documents that left, and leaves alone
    /// an import whose record is not written yet.
    func testALoadRemovesTheDocumentsThatLeftAndKeepsAnImportInProgress() {
        let home = UUID()
        let work = UUID()
        let kept = UUID()
        let deletedElsewhere = UUID()
        let importing = UUID()
        let arrived = UUID()
        let known = [kept: home, deletedElsewhere: home, importing: work]
        let present = [kept: home, arrived: work]

        let change = SpotlightIndexService.change(known: known, present: present, importing: [importing])
        XCTAssertEqual(change.gone, [deletedElsewhere: home], "only the document that left, with its library")
        XCTAssertEqual(change.arrived, [arrived])
        XCTAssertEqual(change.known, [kept: home, arrived: work, importing: work])

        // The import's record is written by the next load: nothing is gone or new.
        let next = SpotlightIndexService.change(
            known: change.known, present: [kept: home, arrived: work, importing: work], importing: [])
        XCTAssertTrue(next.gone.isEmpty)
        XCTAssertTrue(next.arrived.isEmpty)

        // An import that never finished is gone at the first load after the launch it ran in.
        let afterRelaunch = SpotlightIndexService.change(known: change.known, present: present, importing: [])
        XCTAssertEqual(afterRelaunch.gone, [importing: work])
    }

    func testAPreviewDropsTheStoresOwnTruncationLine() {
        let stored = "Lease agreement between the parties.\n\n--- Preview truncated (12,000 of 12,000 characters stored) ---"
        XCTAssertEqual(SpotlightIndexService.previewText(fromStored: stored), "Lease agreement between the parties.")
        XCTAssertEqual(SpotlightIndexService.previewText(fromStored: "Short note"), "Short note")
        XCTAssertNil(SpotlightIndexService.previewText(fromStored: "  \n "))
    }

    /// A passage's title names its document and its page, and nothing internal (5.7): it read
    /// "Juniper Flats Lease - Unit 4B.pdf — Page 3 [Chunk 13]", and "Page 1" for a text file.
    func testAPassagesTitleNamesItsDocumentAndPage() {
        XCTAssertEqual(
            SpotlightIndexService.passageTitle(documentName: "Juniper Flats Lease - Unit 4B.pdf", pageNumber: 3),
            "Juniper Flats Lease - Unit 4B.pdf, page 3")
        XCTAssertEqual(SpotlightIndexService.passageTitle(documentName: "Notes.txt", pageNumber: nil), "Notes.txt")
        XCTAssertEqual(SpotlightIndexService.passageTitle(documentName: "Notes.txt", pageNumber: 0), "Notes.txt")
    }
}

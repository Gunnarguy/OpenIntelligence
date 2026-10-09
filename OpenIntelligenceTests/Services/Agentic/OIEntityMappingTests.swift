//
//  OIEntityMappingTests.swift
//  OpenIntelligenceTests
//
//  What a shortcut can read from the app's items. Through 5.6 a document and a library carried a
//  title and nothing else, and answers, passages and conversations were not items at all. These pin
//  the values each item is built with and the text another app receives when one is handed over.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class OIEntityMappingTests: XCTestCase {
    private let added = Date(timeIntervalSince1970: 1_791_522_000)

    private func chunk(_ text: String, _ document: String, page: Int?, section: String? = nil) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: page,
            sectionTitle: section,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.75,
            rank: 1,
            sourceDocument: document,
            pageNumber: page
        )
    }

    // MARK: - Documents and libraries

    func testADocumentCarriesItsTypeDateAndLibrary() {
        let libraryId = UUID()
        let document = Document(
            filename: "Lease.pdf",
            fileURL: URL(fileURLWithPath: "/tmp/Lease.pdf"),
            contentType: .pdf,
            addedAt: added,
            totalChunks: 42,
            containerId: libraryId
        )
        let entity = OIDocumentEntityQuery.entity(for: document, libraryNames: [libraryId: "Home"])

        XCTAssertEqual(entity.id, document.id)
        XCTAssertEqual(entity.filename, "Lease.pdf")
        XCTAssertEqual(entity.kind, "pdf")
        XCTAssertEqual(entity.addedAt, added)
        XCTAssertEqual(entity.totalChunks, 42)
        XCTAssertEqual(entity.libraryName, "Home")
        XCTAssertNil(entity.pageCount, "a document with no processing record has no page count to report")
    }

    func testADocumentWhoseLibraryIsGoneHasNoLibraryName() {
        let document = Document(
            filename: "Notes.txt",
            fileURL: URL(fileURLWithPath: "/tmp/Notes.txt"),
            contentType: .text,
            containerId: UUID()
        )
        XCTAssertNil(OIDocumentEntityQuery.entity(for: document, libraryNames: [:]).libraryName)
    }

    func testALibraryCarriesItsCountsAndDates() {
        let container = KnowledgeContainer(
            name: "Home", createdAt: added, totalDocuments: 3, totalChunks: 120, lastIndexedAt: added)
        let entity = OILibraryEntityQuery.entity(for: container)

        XCTAssertEqual(entity.id, container.id)
        XCTAssertEqual(entity.name, "Home")
        XCTAssertEqual(entity.totalDocuments, 3)
        XCTAssertEqual(entity.totalChunks, 120)
        XCTAssertEqual(entity.createdAt, added)
        XCTAssertEqual(entity.lastIndexedAt, added)
    }

    // MARK: - Passages and answers

    func testAPassageCarriesItsTextAndWhereItCameFrom() {
        let passage = OIPassageEntity(
            chunk("Rent is late after 11:59 p.m. on the 5th.", "Lease.pdf", page: 3, section: "Rent"))

        XCTAssertEqual(passage.text, "Rent is late after 11:59 p.m. on the 5th.")
        XCTAssertEqual(passage.documentName, "Lease.pdf")
        XCTAssertEqual(passage.page, 3)
        XCTAssertEqual(passage.section, "Rent")
        XCTAssertEqual(passage.score, 0.75, accuracy: 0.0001)
        XCTAssertEqual(passage.sourceLine, "Lease.pdf, page 3")
        XCTAssertEqual(passage.textWithSource, "Rent is late after 11:59 p.m. on the 5th.\n\nLease.pdf, page 3")
    }

    func testAPassageWithoutAPageNamesOnlyItsDocument() {
        let passage = OIPassageEntity(chunk("role: user", "chat.jsonl", page: nil))
        XCTAssertEqual(passage.sourceLine, "chat.jsonl")
    }

    func testAnAnswerListsEachDocumentOnceWithItsPages() {
        let chunks = [
            chunk("Rent is late after the 5th.", "Lease.pdf", page: 7),
            chunk("Quiet hours start at 10:00 p.m.", "Rules.pdf", page: nil),
            chunk("A late charge of $75.00 applies.", "Lease.pdf", page: 3),
        ]
        XCTAssertEqual(
            OIAnswerEntity.sourceList(for: chunks),
            "- Lease.pdf, pages 3, 7\n- Rules.pdf"
        )
    }

    func testAnAnswerHandedToAnotherAppArrivesWithItsSources() {
        let answer = OIAnswerEntity()
        answer.text = "Rent is late after the 5th."
        XCTAssertEqual(answer.textWithSources, "Rent is late after the 5th.", "no sources, no heading")

        answer.sourceList = "- Lease.pdf, page 3"
        XCTAssertEqual(answer.textWithSources, "Rent is late after the 5th.\n\nSources:\n- Lease.pdf, page 3")
    }

    // MARK: - Mode menu

    func testTheMenuHasThreeModesAndEachMapsToItsEngineMode() {
        XCTAssertEqual(OIAnswerMode.allCases, [.standard, .deepThink, .maximum])
        XCTAssertEqual(Set(OIAnswerMode.caseDisplayRepresentations.keys), Set(OIAnswerMode.allCases))
        XCTAssertEqual(OIAnswerMode.standard.qualityMode, .standard)
        XCTAssertEqual(OIAnswerMode.deepThink.qualityMode, .deepThink)
        XCTAssertEqual(OIAnswerMode.maximum.qualityMode, .maximum)
    }

    func testOlderModeNamesLandOnOneOfTheThree() {
        XCTAssertEqual(OIAnswerMode(.fast), .standard)
        XCTAssertEqual(OIAnswerMode(.balanced), .standard)
        XCTAssertEqual(OIAnswerMode(.thorough), .standard)
        XCTAssertEqual(OIAnswerMode(.agentic), .deepThink)
        XCTAssertEqual(OIAnswerMode(.maximum), .maximum)
    }

    // MARK: - Saving text

    func testSavedTextIsNamedFromItsFirstWordsOrTheGivenName() {
        let day = Date(timeIntervalSince1970: 1_791_522_000)
        XCTAssertEqual(
            IntentSupport.noteFileName(for: "Quiet hours: 10 p.m. to 7 a.m.\nNo grills on balconies.", name: nil),
            "Quiet hours 10 p.m. to 7 a.m..txt")
        XCTAssertEqual(IntentSupport.noteFileName(for: "anything", name: "House rules"), "House rules.txt")
        XCTAssertEqual(IntentSupport.noteFileName(for: "anything", name: "rules.md"), "rules.md")
        XCTAssertEqual(
            IntentSupport.noteFileName(for: "anything", name: "Report.pdf"), "Report.pdf.txt",
            "saved text must not be named as a PDF")
        XCTAssertTrue(
            IntentSupport.noteFileName(for: "ok", name: "  ", now: day).hasPrefix("Note 2026-10-0"),
            "text too short to name itself is named by the day")
    }
}

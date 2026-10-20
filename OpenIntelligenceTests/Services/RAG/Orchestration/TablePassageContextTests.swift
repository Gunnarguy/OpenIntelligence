//
//  TablePassageContextTests.swift
//  OpenIntelligenceTests
//
//  A table's passage is read as its rows, not as its title (5.7, `DocumentChunk.contextText`). A
//  structured passage stores its section's title as `parentContent`, and every reader took
//  `parentContent ?? content`, so on 2026-10-19 the model was given "Field log page 60 of 60: the
//  harbor survey." for a question whose answer was a row of that page's table, and said no document
//  mentioned it. These use passages shaped like the ones that PDF produced in the iOS 27.0 Simulator.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class TablePassageContextTests: XCTestCase {
    private let title = "Field log page 60 of 60: the harbor survey."
    private let rows = """
        [Part 1]
        [Part 2]
        Section Path: Field log page 60 of 60: the harbor survey.
        ROW 19: The final instruction | the harbor lantern code is VERMILION-4417, kept in the blue ledger.
        [Specifications]
        Entry 1: at the harbor the crew measured 8787 units and noted the weather as wet.
        Entry 2: at the harbor the crew measured 4991 units and noted the weather as foggy.
        """

    private func chunk(_ content: String, parent: String?) -> DocumentChunk {
        DocumentChunk(
            documentId: UUID(), content: content, parentContent: parent, embedding: [0],
            metadata: ChunkMetadata(
                chunkIndex: 295,
                pageNumber: 60,
                sectionTitle: title,
                keywords: [],
                hasNumericData: true,
                hasListStructure: false,
                wordCount: content.split(separator: " ").count,
                characterCount: content.count
            ))
    }

    func testATablePassageIsReadAsItsRowsNotItsTitle() {
        XCTAssertEqual(chunk(rows, parent: title).contextText, rows)
    }

    func testAProsePassageIsReadWithTheWindowAroundIt() {
        let passage = "The warranty covers parts and labour for two years."
        let window = "Dishwasher Manual\n\nThe warranty covers parts and labour for two years. It does not cover misuse."
        XCTAssertEqual(chunk(passage, parent: window).contextText, window)
    }

    func testAPassageWithNoParentIsReadAsItself() {
        XCTAssertEqual(chunk(rows, parent: nil).contextText, rows)
    }

    func testAShortPassageUnderALongerTitleIsReadAsItself() {
        let passage = "Yes, both."
        XCTAssertEqual(chunk(passage, parent: "Are pets and smoking allowed in the unit?").contextText, passage)
    }

    func testAPassageCutIntoPartsStillReadsItsWindow() {
        let passage = "[Part 2]\nin the first column and only as the next one due."
        let window =
            "The records are joined with a blank line, which goes\nin the first column and only as the next one due. It returns nil otherwise."
        XCTAssertEqual(chunk(passage, parent: window).contextText, window)
    }

    /// The step that builds the model's context from the passages (`extractRelevantSentences`), with the
    /// table passage ranked first, as it was on 2026-10-19.
    func testTheModelIsGivenTheRowThatAnswersTheQuestion() async {
        let lead = RetrievedChunk(
            chunk: chunk(rows, parent: title), similarityScore: 0.9, rank: 1, sourceDocument: "Field Survey Log.pdf",
            pageNumber: 60)
        let result = await RAGService().extractRelevantSentences(
            from: [lead], query: "Where is VERMILION-4417 kept?", maxChars: 2_000, compact: true,
            isExtractiveFirst: true, leadingCandidateWhole: true)
        XCTAssertTrue(result.context.contains("VERMILION-4417, kept in the blue ledger"), result.context)
    }
}

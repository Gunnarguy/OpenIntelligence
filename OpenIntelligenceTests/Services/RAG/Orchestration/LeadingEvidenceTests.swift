//
//  LeadingEvidenceTests.swift
//  OpenIntelligenceTests
//
//  The passage retrieval ranks first reaches the model whole, however the question is worded (5.7).
//  On 2026-10-15 "What happened on September 30" had the September 30 section of a monthly log
//  ranked first by the reranker, and the answer came from September 24 and 25: the extractive path
//  sorted the passages by the question's words and then chose sentences that repeat them, and the
//  section's lines name people and events, not "happened". These use written passages shaped like
//  that log.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class LeadingEvidenceTests: XCTestCase {
    private func passage(_ text: String, section: String, rank: Int) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: rank,
            pageNumber: 1,
            sectionTitle: section,
            keywords: [],
            hasNumericData: false,
            hasListStructure: true,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: rank == 1 ? 0.9 : 0.5,
            rank: rank,
            sourceDocument: "September Highlights.md",
            pageNumber: 1
        )
    }

    private var log: [RetrievedChunk] {
        [
            passage(
                "## September 30 — Workplace Culture\n- Confirmed equipment needs with Kristen by text for an upcoming case.\n- Jeff shared plans to relocate to Michigan.",
                section: "September 30 — Workplace Culture", rank: 1),
            passage(
                "## September 24 — Elevator\nWhat happened on September 24: Casey was stuck in the elevator for an hour. It happened during the afternoon turnover.",
                section: "September 24 — Elevator", rank: 2),
            passage(
                "## September 25 — Loaner\nWhat happened on September 25: a loaner tray was sent to the wrong site. It happened twice that week in September.",
                section: "September 25 — Loaner", rank: 3),
        ]
    }

    func testTheTopRankedPassageLeadsTheContextWhole() async {
        let result = await RAGService().extractRelevantSentences(
            from: log, query: "What happened on September 30", maxChars: 700, compact: true,
            isExtractiveFirst: true, leadingCandidateWhole: true)

        XCTAssertTrue(result.context.hasPrefix("[S1]"), result.context)
        XCTAssertTrue(result.context.contains("Kristen"), "the September 30 section is in: \(result.context)")
        XCTAssertTrue(result.context.contains("Jeff"), result.context)
        XCTAssertEqual(result.usedSourceIndices.first, 0)
    }

    func testOtherPassagesStillFillTheRoomLeft() async {
        let result = await RAGService().extractRelevantSentences(
            from: log, query: "What happened on September 30", maxChars: 2_000, compact: true,
            isExtractiveFirst: true, leadingCandidateWhole: true)

        XCTAssertTrue(result.context.contains("Kristen"), result.context)
        XCTAssertGreaterThan(result.usedSourceIndices.count, 1, "chosen sentences from the others follow")
    }

    func testTheKeywordOrderingKeepsRetrievalsBestPassageFirst() {
        let passages = log
        let byKeyword = [passages[1], passages[2], passages[0]]
        let ordered = RAGService.leadingWithTopRanked(passages[0], then: byKeyword)
        XCTAssertEqual(ordered.map(\.chunk.id), [passages[0].chunk.id, passages[1].chunk.id, passages[2].chunk.id])
        XCTAssertEqual(RAGService.leadingWithTopRanked(nil, then: byKeyword).count, 3)
    }
}

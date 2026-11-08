//
//  SummaryContextTests.swift
//  OpenIntelligenceTests
//
//  The summary-detail step puts document summaries at the front of the context. Until 5.8 every summary in the library
//  was eligible and the first was always taken, so "Summarize my lease" opened its context with another document's
//  flight table when the lease had no summary passage.
//

import XCTest

@testable import OpenIntelligence

final class SummaryContextTests: XCTestCase {
    private func chunk(_ documentId: UUID, summary: Bool) -> DocumentChunk {
        DocumentChunk(
            documentId: documentId, content: summary ? "Summary." : "Detail.", embedding: [],
            metadata: ChunkMetadata(chunkIndex: 0, abstractionLevel: summary ? .documentSummary : .detail))
    }

    private func candidate(_ chunk: DocumentChunk) -> RetrievedChunk {
        RetrievedChunk(chunk: chunk, similarityScore: 0.8, rank: 0, sourceDocument: "x", pageNumber: nil)
    }

    func testOnlySummariesOfRetrievedDocumentsAreAdded() {
        let lease = UUID(), flights = UUID()
        let leaseDetail = chunk(lease, summary: false)
        let all = [chunk(flights, summary: true), leaseDetail]
        // The lease has no summary passage: nothing is added, and the flights summary is not.
        XCTAssertTrue(RAGService.documentSummariesForContext(allChunks: all, candidates: [candidate(leaseDetail)]).isEmpty)
    }

    func testSummariesFollowTheOrderTheirDocumentsWereRetrieved() {
        let a = UUID(), b = UUID(), c = UUID()
        let aSummary = chunk(a, summary: true), bSummary = chunk(b, summary: true), cSummary = chunk(c, summary: true)
        let candidates = [candidate(chunk(b, summary: false)), candidate(chunk(a, summary: false))]
        let picked = RAGService.documentSummariesForContext(
            allChunks: [aSummary, cSummary, bSummary], candidates: candidates)
        XCTAssertEqual(picked.map(\.documentId), [b, a])
    }

    func testASummaryAlreadyInTheContextIsNotAddedAgain() {
        let a = UUID()
        let summary = chunk(a, summary: true)
        XCTAssertTrue(
            RAGService.documentSummariesForContext(allChunks: [summary], candidates: [candidate(summary)]).isEmpty)
    }
}

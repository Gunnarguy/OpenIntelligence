//
//  MMRStoredVectorsTests.swift
//  OpenIntelligenceTests
//
//  MMR picks passages that are relevant and unlike the ones it has already picked. It measures
//  "unlike" with the passages' vectors, and the vector store hands passages back without them, so
//  through 5.6 every pair measured 0 alike and MMR kept passages in score order whatever λ said, in
//  every answer mode, while Settings said MMR diversified. From 5.7 the callers fetch the vectors by
//  id (`RAGService.storedVectors`) and pass them in. These tests run MMR on passages without vectors,
//  as the store returns them, once with the vectors and once without.
//
//  Also here: a two-character code such as "E1" counts as a keyword when evidence lines are matched
//  to a question (`RAGService.isEvidenceKeyword`). Through 5.6 every two-character word was dropped,
//  which is the likely cause of the sample library's wrong air fryer answer.
//

import XCTest

@testable import OpenIntelligence

final class MMRStoredVectorsTests: XCTestCase {
    private let manual = UUID()

    private func passage(_ text: String, score: Float, rank: Int) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: manual, content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: rank)),
            similarityScore: score, rank: rank, sourceDocument: "Manual.pdf", pageNumber: nil)
    }

    func testANearCopyOfAPickedPassageGivesWayWhenTheVectorsAreKnown() async {
        let first = passage("The E1 code means the temperature sensor failed.", score: 0.90, rank: 1)
        let copy = passage("Code E1 means the temperature sensor has failed.", score: 0.85, rank: 2)
        let other = passage("To reset the fryer, unplug it for ten minutes.", score: 0.60, rank: 3)
        let sensor: [Float] = [1, 0, 0]
        let vectors: [UUID: [Float]] = [
            first.chunk.id: sensor, copy.chunk.id: sensor, other.chunk.id: [0, 1, 0],
        ]

        let picked = await RAGEngine.shared.applyMMR(
            candidates: [first, copy, other], queryEmbedding: [], topK: 2, lambda: 0.5, vectors: vectors)

        XCTAssertEqual(picked.map(\.chunk.id), [first.chunk.id, other.chunk.id])
    }

    func testWithoutTheVectorsEveryPairCountsAsUnlike() async {
        let first = passage("The E1 code means the temperature sensor failed.", score: 0.90, rank: 1)
        let copy = passage("Code E1 means the temperature sensor has failed.", score: 0.85, rank: 2)
        let other = passage("To reset the fryer, unplug it for ten minutes.", score: 0.60, rank: 3)

        let picked = await RAGEngine.shared.applyMMR(
            candidates: [first, copy, other], queryEmbedding: [], topK: 2, lambda: 0.5)

        XCTAssertEqual(
            picked.map(\.chunk.id), [first.chunk.id, copy.chunk.id], "what every answer got through 5.6")
    }

    func testAShortCodeCountsAsAKeyword() {
        XCTAssertTrue(RAGService.isEvidenceKeyword("e1"))
        XCTAssertTrue(RAGService.isEvidenceKeyword("3d"))
        XCTAssertTrue(RAGService.isEvidenceKeyword("fryer"))
        XCTAssertFalse(RAGService.isEvidenceKeyword("on"), "a two-letter word is still dropped")
        XCTAssertFalse(RAGService.isEvidenceKeyword("12"), "a two-digit number is still dropped")
        XCTAssertFalse(RAGService.isEvidenceKeyword("e"))
    }
}

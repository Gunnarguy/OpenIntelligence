import XCTest
@testable import OpenIntelligence

final class HybridSearchServiceTests: XCTestCase {

    func testReciprocalRankFusionBoostsKeywordLeaderWhenWeighted() async {
        let engine = RAGEngine()

        let chunkA = DocumentChunk(
            documentId: UUID(),
            content: "Alpha section",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let chunkB = DocumentChunk(
            documentId: UUID(),
            content: "Beta section",
            embedding: [0, 1, 0],
            metadata: ChunkMetadata(chunkIndex: 1)
        )

        let vectorResults = [
            RetrievedChunk(chunk: chunkA, similarityScore: 0.9, rank: 1),
            RetrievedChunk(chunk: chunkB, similarityScore: 0.8, rank: 2),
        ]
        let keywordResults: [(chunk: RetrievedChunk, score: Float)] = [
            (chunk: vectorResults[1], score: 2.0), // chunkB wins keyword search
            (chunk: vectorResults[0], score: 0.1)
        ]

        let fused = await engine.reciprocalRankFusion(
            vectorResults: vectorResults,
            keywordResults: keywordResults,
            k: 1,
            vectorWeight: 0.2,
            keywordWeight: 1.0
        )

        XCTAssertEqual(fused.first?.chunk.id, chunkB.id)
    }

    func testBM25SnapshotUsesCandidatesWhenNotIndexed() {
        let scorer = BM25Scorer()
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "swift ai swift",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let retrieved = RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)
        let snapshot = scorer.snapshot(from: [retrieved])
        XCTAssertEqual(snapshot.totalDocuments, 1)
        XCTAssertTrue(snapshot.documentFrequencies.keys.contains("swift"))
    }
}

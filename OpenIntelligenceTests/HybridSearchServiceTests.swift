import XCTest
@testable import OpenIntelligence

final class HybridSearchServiceTests: XCTestCase {

    // MARK: - RRF Tests

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
    
    func testRRFWithEmptyVectorResultsUsesKeywordOnly() async {
        let engine = RAGEngine()
        
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "Only keyword result",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let retrieved = RetrievedChunk(chunk: chunk, similarityScore: 0.8, rank: 1)
        
        let fused = await engine.reciprocalRankFusion(
            vectorResults: [],  // Empty vector results
            keywordResults: [(chunk: retrieved, score: 1.5)],
            k: 60,
            vectorWeight: 0.5,
            keywordWeight: 0.5
        )
        
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused.first?.chunk.id, chunk.id)
    }
    
    func testRRFWithEmptyKeywordResultsUsesVectorOnly() async {
        let engine = RAGEngine()
        
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "Only vector result",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let vectorResult = RetrievedChunk(chunk: chunk, similarityScore: 0.9, rank: 1)
        
        let fused = await engine.reciprocalRankFusion(
            vectorResults: [vectorResult],
            keywordResults: [],  // Empty keyword results
            k: 60,
            vectorWeight: 0.5,
            keywordWeight: 0.5
        )
        
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused.first?.chunk.id, chunk.id)
    }
    
    func testRRFWithBothEmptyReturnsEmpty() async {
        let engine = RAGEngine()
        
        let fused = await engine.reciprocalRankFusion(
            vectorResults: [],
            keywordResults: [],
            k: 60,
            vectorWeight: 0.5,
            keywordWeight: 0.5
        )
        
        XCTAssertTrue(fused.isEmpty)
    }
    
    func testRRFDeduplicatesOverlappingResults() async {
        let engine = RAGEngine()
        
        let sharedId = UUID()
        let chunk = DocumentChunk(
            id: sharedId,
            documentId: UUID(),
            content: "Appears in both searches",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        
        let vectorResult = RetrievedChunk(chunk: chunk, similarityScore: 0.9, rank: 1)
        let keywordResult = RetrievedChunk(chunk: chunk, similarityScore: 0.9, rank: 1)
        
        let fused = await engine.reciprocalRankFusion(
            vectorResults: [vectorResult],
            keywordResults: [(chunk: keywordResult, score: 2.0)],
            k: 60,
            vectorWeight: 0.5,
            keywordWeight: 0.5
        )
        
        // Should only appear once, with boosted score from both sources
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused.first?.chunk.id, sharedId)
    }

    // MARK: - BM25 Tests

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
    
    func testBM25ScoresHigherForTermFrequency() {
        let scorer = BM25Scorer()
        
        let chunkHighTF = DocumentChunk(
            documentId: UUID(),
            content: "swift swift swift programming",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let chunkLowTF = DocumentChunk(
            documentId: UUID(),
            content: "swift programming language",
            embedding: [0, 1, 0],
            metadata: ChunkMetadata(chunkIndex: 1)
        )
        
        let candidates = [
            RetrievedChunk(chunk: chunkHighTF, similarityScore: 0.5, rank: 1),
            RetrievedChunk(chunk: chunkLowTF, similarityScore: 0.5, rank: 2)
        ]
        
        let snapshot = scorer.snapshot(from: candidates)
        let highTFScore = scorer.score(document: chunkHighTF.content, query: "swift", snapshot: snapshot)
        let lowTFScore = scorer.score(document: chunkLowTF.content, query: "swift", snapshot: snapshot)
        
        XCTAssertGreaterThan(highTFScore, lowTFScore, "Higher term frequency should produce higher BM25 score")
    }
    
    func testBM25WithEmptyQueryReturnsZero() {
        let scorer = BM25Scorer()
        
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "some document content",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let candidates = [RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)]
        let snapshot = scorer.snapshot(from: candidates)
        
        let score = scorer.score(document: chunk.content, query: "", snapshot: snapshot)
        XCTAssertEqual(score, 0.0, "Empty query should return zero score")
    }
    
    func testBM25WithNoMatchingTermsReturnsZero() {
        let scorer = BM25Scorer()
        
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "document about cats and dogs",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let candidates = [RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)]
        let snapshot = scorer.snapshot(from: candidates)
        
        let score = scorer.score(document: chunk.content, query: "programming swift", snapshot: snapshot)
        XCTAssertEqual(score, 0.0, "Query with no matching terms should return zero score")
    }
    
    func testBM25HandlesSpecialCharacters() {
        let scorer = BM25Scorer()
        
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "C++ and C# are programming languages! @swift #coding",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let candidates = [RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)]
        let snapshot = scorer.snapshot(from: candidates)
        
        // Should not crash and should handle special chars gracefully
        let score = scorer.score(document: chunk.content, query: "C++ programming", snapshot: snapshot)
        XCTAssertGreaterThanOrEqual(score, 0.0, "BM25 should handle special characters without crashing")
    }
    
    // MARK: - Edge Cases
    
    func testVeryLongDocumentDoesNotOverflow() {
        let scorer = BM25Scorer()
        
        // Create a very long document
        let longContent = String(repeating: "word ", count: 10000)
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: longContent,
            embedding: Array(repeating: Float(0.1), count: 512),
            metadata: ChunkMetadata(chunkIndex: 0, wordCount: 10000, characterCount: longContent.count)
        )
        
        let candidates = [RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)]
        let snapshot = scorer.snapshot(from: candidates)
        
        let score = scorer.score(document: chunk.content, query: "word", snapshot: snapshot)
        XCTAssertFalse(score.isNaN, "Score should not be NaN for long documents")
        XCTAssertFalse(score.isInfinite, "Score should not be infinite for long documents")
    }
    
    func testUnicodeContentHandledCorrectly() {
        let scorer = BM25Scorer()
        
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "日本語のテキスト Swift プログラミング 中文内容 🚀",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let candidates = [RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)]
        let snapshot = scorer.snapshot(from: candidates)
        
        // Should handle Unicode without crashing
        let score = scorer.score(document: chunk.content, query: "Swift", snapshot: snapshot)
        XCTAssertGreaterThan(score, 0.0, "Should find 'Swift' in Unicode content")
    }
    
    func testChunkMetadataWithPageNumber() {
        // Test that page numbers are properly stored and retrieved
        let metadata = ChunkMetadata(
            chunkIndex: 5,
            startPosition: 1000,
            endPosition: 2000,
            pageNumber: 3,
            sectionTitle: "Introduction",
            keywords: ["swift", "programming"],
            semanticDensity: 0.75,
            hasNumericData: true,
            hasListStructure: false,
            wordCount: 150,
            characterCount: 900
        )
        
        XCTAssertEqual(metadata.pageNumber, 3)
        XCTAssertEqual(metadata.sectionTitle, "Introduction")
        XCTAssertEqual(metadata.keywords, ["swift", "programming"])
        XCTAssertEqual(metadata.startPosition, 1000)
        XCTAssertEqual(metadata.endPosition, 2000)
    }
}

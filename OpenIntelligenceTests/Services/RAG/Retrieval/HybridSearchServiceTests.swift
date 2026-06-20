import XCTest
@testable import OpenIntelligenceEngine

// A dummy vector database to satisfy the HybridSearchService init
class DummyVectorDatabase: VectorDatabase {
    var dimension: Int { return 384 }
    func store(chunk: DocumentChunk) async throws {}
    func storeBatch(chunks: [DocumentChunk]) async throws {}
    func search(queryEmbedding: [Float], limit: Int, containerId: UUID?) async throws -> [DocumentChunk] { return [] }
    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] { return [] }
    func allChunks() async throws -> [DocumentChunk] { return [] }
    func documentCount() async throws -> Int { return 0 }
    func chunkCount() async throws -> Int { return 0 }
    func chunks(for documentId: UUID) async throws -> [DocumentChunk] { return [] }
    func deleteDocument(_ id: UUID) async throws {}
    func deleteChunks(forDocument documentId: UUID) async throws {}
    func deleteAll() async throws {}
    func clear() async throws {}
    func count() async throws -> Int { return 0 }
    func updateChunk(_ chunk: DocumentChunk) async throws {}
    func exists(chunkId: UUID) async -> Bool { return false }
    func statistics() async -> VectorDatabaseStats { return VectorDatabaseStats(chunkCount: 0, dimension: 384, uniqueDocuments: 0, estimatedMemoryBytes: 0, backend: "dummy") }
}

final class HybridSearchServiceTests: XCTestCase {

    var service: HybridSearchService!

    override func setUp() {
        super.setUp()
        let db = DummyVectorDatabase()
        service = HybridSearchService(vectorDatabase: db)
    }

    // Helper to create a basic retrieved chunk for testing
    func makeRetrievedChunk(id: UUID = UUID(), content: String, similarityScore: Float) -> RetrievedChunk {
        let chunkMetadata = ChunkMetadata(
            chunkIndex: 0,
            startPosition: 0,
            endPosition: content.count,
            pageNumber: nil,
            sectionTitle: nil,
            keywords: [],
            semanticDensity: nil,
            hasNumericData: false,
            hasListStructure: false,
            wordCount: content.split(separator: " ").count,
            characterCount: content.count,
            createdAt: Date(),
            structureType: nil
        )

        let docChunk = DocumentChunk(
            id: id,
            documentId: UUID(),
            content: content,
            parentContent: nil,
            contextualPrefix: nil,
            embedding: [],
            metadata: chunkMetadata
        )

        return RetrievedChunk(
            chunk: docChunk,
            similarityScore: similarityScore,
            rank: 0,
            sourceDocument: "test.txt",
            pageNumber: nil
        )
    }

    func testApplyKeywordMatchBoost_NoKeywords_ReturnsOriginalResults() {
        let chunk1 = makeRetrievedChunk(content: "This is a simple text", similarityScore: 0.5)
        let chunk2 = makeRetrievedChunk(content: "Another simple text", similarityScore: 0.4)

        let results = service.applyKeywordMatchBoost(query: "the a is", results: [chunk1, chunk2])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].similarityScore, 0.5)
        XCTAssertEqual(results[1].similarityScore, 0.4)
    }

    func testApplyKeywordMatchBoost_KeywordPresent_BoostsScore() {
        let chunk1 = makeRetrievedChunk(content: "This document mentions insulin and diabetes.", similarityScore: 0.5)
        let chunk2 = makeRetrievedChunk(content: "This one is about diet only.", similarityScore: 0.4)
        let chunk3 = makeRetrievedChunk(content: "Other random text.", similarityScore: 0.3)

        let results = service.applyKeywordMatchBoost(query: "insulin treatment", results: [chunk1, chunk2, chunk3])

        XCTAssertEqual(results.count, 3)

        let boostedChunk = results.first(where: { $0.chunk.content.contains("insulin") })
        XCTAssertNotNil(boostedChunk)

        // hit rate for 'insulin' is 1/3 = 33%.
        // decayCeiling is 0.50. scaleFactor = max(0, 1.0 - (0.333/0.50)) = 0.333
        // match score = 1.0. exact boundary match gives another +1.0. Total match score = 2.0
        // Total weighted match score = 2.0 * 0.333 = 0.666
        // Boost = min(0.20, 0.666 * 0.05) = 0.0333
        // Original score = 0.5. New score = 0.533
        XCTAssertEqual(boostedChunk!.similarityScore, 0.533, accuracy: 0.005)
    }

    func testApplyKeywordMatchBoost_HitRateScaling() {
        // We'll create 4 chunks. 1 has the keyword, 3 do not. Hit rate = 25%.
        let chunk1 = makeRetrievedChunk(content: "The treatment involves insulin.", similarityScore: 0.5)
        let chunk2 = makeRetrievedChunk(content: "Different content.", similarityScore: 0.4)
        let chunk3 = makeRetrievedChunk(content: "Some other content.", similarityScore: 0.3)
        let chunk4 = makeRetrievedChunk(content: "Nothing related.", similarityScore: 0.2)

        // The query "insulin"
        let results = service.applyKeywordMatchBoost(query: "insulin", results: [chunk1, chunk2, chunk3, chunk4])

        // Hit rate = 1/4 = 0.25. Decay ceiling = 0.50. Scale factor = 1.0 - (0.25/0.50) = 0.5.
        // Base boost = 1.0 * 0.5 = 0.5. Boundary match = +1.0 * 0.5 = +0.5. Total weighted match score = 1.0.
        // Boost = min(0.20, 1.0 * 0.05) = 0.05.
        // Original score = 0.5. New score = 0.55.

        guard let boostedChunk = results.first(where: { $0.chunk.content.contains("insulin") }) else {
            XCTFail("Missing boosted chunk")
            return
        }

        XCTAssertEqual(boostedChunk.similarityScore, 0.55, accuracy: 0.001)
    }

    func testApplyKeywordMatchBoost_HitRateTooHigh_NoBoost() {
        // 3 out of 4 chunks have the keyword. Hit rate = 75%. This is > 50% decay ceiling.
        let chunk1 = makeRetrievedChunk(content: "The treatment involves insulin.", similarityScore: 0.5)
        let chunk2 = makeRetrievedChunk(content: "Here is insulin again.", similarityScore: 0.4)
        let chunk3 = makeRetrievedChunk(content: "More insulin.", similarityScore: 0.3)
        let chunk4 = makeRetrievedChunk(content: "Nothing related.", similarityScore: 0.2)

        let results = service.applyKeywordMatchBoost(query: "insulin", results: [chunk1, chunk2, chunk3, chunk4])

        // No boost should be applied.
        let c1 = results.first(where: { $0.similarityScore == 0.5 })
        XCTAssertNotNil(c1)
    }

    func testApplyKeywordMatchBoost_ExactWordBoundaryBoost() {
        let chunk1 = makeRetrievedChunk(content: "The insulin level.", similarityScore: 0.5) // Exact boundary
        let chunk2 = makeRetrievedChunk(content: "High insuline level.", similarityScore: 0.4) // Prefix but no boundary
        let chunk3 = makeRetrievedChunk(content: "Nothing related 1.", similarityScore: 0.3)
        let chunk4 = makeRetrievedChunk(content: "Nothing related 2.", similarityScore: 0.2)
        let chunk5 = makeRetrievedChunk(content: "Nothing related 3.", similarityScore: 0.1)

        let results = service.applyKeywordMatchBoost(query: "insulin", results: [chunk1, chunk2, chunk3, chunk4, chunk5])

        // hit rate = 2/5 = 40%. decayCeiling = 50%. scale = 1.0 - (0.4/0.5) = 0.2

        // chunk1 has exact match -> weightedMatchScore = 1.0 (base) + 1.0 (boundary) = 2.0. Boost = min(0.20, 2.0 * 0.2 * 0.05) = 0.02
        let c1 = results.first(where: { $0.chunk.content.contains("The insulin") })
        XCTAssertEqual(c1?.similarityScore ?? 0.0, 0.52, accuracy: 0.001)

        // chunk2 has prefix match -> weightedMatchScore = 1.0 (base) = 1.0. Boost = min(0.20, 1.0 * 0.2 * 0.05) = 0.01
        let c2 = results.first(where: { $0.chunk.content.contains("insuline") })
        XCTAssertEqual(c2?.similarityScore ?? 0.0, 0.41, accuracy: 0.001)
    }
}

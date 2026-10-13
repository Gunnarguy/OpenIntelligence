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

    // MARK: - Word-boundary term matching
    //
    // These pin the defect that made a psychiatry review read as a parts catalogue:
    // `specPatterns` and `measurementUnits` were matched with `query.contains(term)`,
    // and both lists carry entries short enough to appear inside ordinary words.

    /// The one that cost a device session. `specPatterns` contains bare "min".
    func testContainsTerm_DopamineDoesNotContainMin() {
        XCTAssertFalse(HybridSearchService.containsTerm("what role does dopamine deficiency play in depression", "min"))
        XCTAssertTrue(HybridSearchService.containsTerm("what is the min operating temperature", "min"))
    }

    /// `measurementUnits` contains "ft", "oz" and "amp".
    func testContainsTerm_ShortUnitsDoNotMatchInsideWords() {
        XCTAssertFalse(HybridSearchService.containsTerm("how often does this occur", "ft"))
        XCTAssertFalse(HybridSearchService.containsTerm("what happens after the dose", "ft"))
        XCTAssertFalse(HybridSearchService.containsTerm("give me a dozen examples", "oz"))
        XCTAssertFalse(HybridSearchService.containsTerm("for example the sample size", "amp"))
        XCTAssertTrue(HybridSearchService.containsTerm("what is the rated amp draw", "amp"))
        XCTAssertTrue(HybridSearchService.containsTerm("12 ft of clearance", "ft"))
    }

    /// Multi-word entries such as "type of" must still match as phrases.
    func testContainsTerm_MultiWordPhrasesStillMatch() {
        XCTAssertTrue(HybridSearchService.containsTerm("what type of oil does it take", "type of"))
        XCTAssertTrue(HybridSearchService.containsTerm("how many liters", "how many"))
        // Not a phrase match: the words are present but not adjacent in order.
        XCTAssertFalse(HybridSearchService.containsTerm("the type is different of course", "type of"))
    }

    /// Punctuation and case must not defeat a genuine match.
    func testContainsTerm_NormalisesPunctuationAndCase() {
        XCTAssertTrue(HybridSearchService.containsTerm("What is the MAX torque?", "max"))
        XCTAssertTrue(HybridSearchService.containsTerm("dosage, please", "dosage"))
        XCTAssertFalse(HybridSearchService.containsTerm("maximise throughput", "max"))
    }


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

    // MARK: - A question limited to named documents

    /// A question limited to a document is ranked by how close each of its passages is to the
    /// question as well as by the words they share. The vector store hands passages back
    /// without their vectors, and the scoped search compared the question with that empty
    /// vector, so every similarity was 0 and only the words counted. Neither passage here
    /// shares a word with the question: the one that points the question's way has to win, and
    /// a passage outside the named document is not returned however close it is.
    func testAQuestionLimitedToADocumentIsRankedByVectorsFromTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BNNSVectorDatabase(
            dimension: 4, storageURL: directory.appendingPathComponent("vector_database_scope.json"))

        let lease = UUID()
        let rules = UUID()
        func passage(_ document: UUID, _ index: Int, _ text: String, _ vector: [Float]) -> DocumentChunk {
            DocumentChunk(
                documentId: document, content: text, embedding: vector, metadata: ChunkMetadata(chunkIndex: index))
        }
        let far = passage(lease, 0, "Quiet hours begin at ten in the evening.", [0, 1, 0, 0])
        let near = passage(lease, 1, "The deposit comes back within sixty days.", [0.9, 0.1, 0, 0])
        let between = passage(lease, 2, "Pets need written permission.", [0.5, 0.5, 0, 0])
        let outside = passage(rules, 0, "refund timing refund timing", [1, 0, 0, 0])
        try await store.storeBatch(chunks: [far, near, outside])
        try await store.persist()
        // One passage no save has written yet: its vector is still in memory.
        try await store.storeBatch(chunks: [between])

        let handedBack = try await store.chunks(forDocument: lease)
        XCTAssertTrue(handedBack.allSatisfy { $0.embedding.isEmpty }, "the store hands passages back without vectors")

        let search = HybridSearchService(vectorDatabase: store)
        let results = try await RAGQueryScope.$documentIds.withValue([lease]) {
            try await search.search(query: "refund timing", embedding: [1, 0, 0, 0], topK: 3)
        }
        XCTAssertEqual(results.map(\.chunk.id), [near.id, between.id, far.id])
        XCTAssertEqual(results.map(\.rank), [1, 2, 3])
        XCTAssertGreaterThan(results[0].similarityScore, results[1].similarityScore)
        XCTAssertGreaterThan(results[1].similarityScore, results[2].similarityScore)
        XCTAssertEqual(results[2].similarityScore, 0, accuracy: 0.0001, "nothing in common: no words, a right angle")

        // The scores are the similarity times the search's vector weight, and no words matched.
        let nearExpected: Float = 0.7 * 0.9 / Float(0.9 * 0.9 + 0.1 * 0.1).squareRoot()
        let betweenExpected: Float = 0.7 * 0.5 / Float(0.5).squareRoot()
        XCTAssertEqual(results[0].similarityScore, nearExpected, accuracy: 0.0001)
        XCTAssertEqual(results[1].similarityScore, betweenExpected, accuracy: 0.0001)
    }

    /// A document with more passages than are asked for at a time is scored in several
    /// requests, and each passage still gets its own vector's score.
    func testAQuestionLimitedToALongDocumentScoresEveryPassageByItsOwnVector() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BNNSVectorDatabase(
            dimension: 4, storageURL: directory.appendingPathComponent("vector_database_long.json"))
        let manual = UUID()
        let total = 5_000
        // Passage n sits at an angle from the question that grows with n, so the closest is
        // passage 0 and the order by score is the order by number. The angles run from 22.5 to
        // 67.5 degrees, where one step changes the cosine by far more than a Float rounds off.
        let passages = (0..<total).map { number -> DocumentChunk in
            let angle = Float.pi / 8 + Float(number) / Float(total) * (Float.pi / 4)
            return DocumentChunk(
                documentId: manual, content: "passage \(number)", embedding: [cos(angle), sin(angle), 0, 0],
                metadata: ChunkMetadata(chunkIndex: number))
        }
        try await store.storeBatch(chunks: passages.shuffled())
        try await store.persist()

        let search = HybridSearchService(vectorDatabase: store)
        let results = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zzz", embedding: [1, 0, 0, 0], topK: total)
        }
        XCTAssertEqual(results.count, total)
        XCTAssertEqual(results.prefix(40).map(\.chunk.metadata.chunkIndex), Array(0..<40))
        XCTAssertEqual(results.suffix(3).map(\.chunk.metadata.chunkIndex), [total - 3, total - 2, total - 1])
        XCTAssertEqual(results[0].similarityScore, 0.7 * cos(Float.pi / 8), accuracy: 0.0001)
        for index in 1..<total {
            XCTAssertLessThan(results[index].similarityScore, results[index - 1].similarityScore, "at \(index)")
        }
    }

    /// A store that hands passages back with their vectors (the one kept in memory) is ranked
    /// from those, as it was.
    func testAQuestionLimitedToADocumentIsRankedByVectorsOnThePassages() async throws {
        let store = InMemoryVectorDatabase(dimension: 4)
        let lease = UUID()
        let far = DocumentChunk(
            documentId: lease, content: "Quiet hours begin at ten.", embedding: [0, 1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0))
        let near = DocumentChunk(
            documentId: lease, content: "The deposit comes back within sixty days.", embedding: [1, 0, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 1))
        try await store.storeBatch(chunks: [far, near])
        let search = HybridSearchService(vectorDatabase: store)
        let results = try await RAGQueryScope.$documentIds.withValue([lease]) {
            try await search.search(query: "refund timing", embedding: [1, 0, 0, 0], topK: 2)
        }
        XCTAssertEqual(results.map(\.chunk.id), [near.id, far.id])
        XCTAssertGreaterThan(results[0].similarityScore, 0.5)
    }
}

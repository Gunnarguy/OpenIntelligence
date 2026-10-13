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

    /// A document of several thousand passages, stored in shuffled order: each passage gets its
    /// own vector's score, and the ranking is by those.
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

    /// The store's own answer: each passage's similarity worked out where its vector is. It has
    /// to be what copying the vectors out and comparing them gives, for a saved passage and for
    /// one no save has written yet, and nil for an id the store does not hold.
    func testTheStoreScoresPassagesWhereTheirVectorsAre() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BNNSVectorDatabase(
            dimension: 4, storageURL: directory.appendingPathComponent("vector_database_scores.json"))
        let document = UUID()
        func vector(_ number: Int) -> [Float] {
            let angle = Float(number) * 0.41
            return [cos(angle), sin(angle), cos(angle * 1.3 + 0.2), Float(number % 13) / 13 - 0.5]
        }
        let passages = (0..<400).map {
            DocumentChunk(
                documentId: document, content: "passage \($0)", embedding: vector($0),
                metadata: ChunkMetadata(chunkIndex: $0))
        }
        try await store.storeBatch(chunks: Array(passages[0..<300]))
        try await store.persist()
        try await store.storeBatch(chunks: Array(passages[300..<400]))  // not saved

        let question: [Float] = [0.3, -0.8, 0.5, 0.1]
        var asked = passages.shuffled().map(\.id)
        asked.insert(UUID(), at: 17)
        let scores = await store.similarities(to: question, forChunkIDs: asked)
        XCTAssertEqual(scores.count, asked.count)
        XCTAssertNil(scores[17])

        let byId = Dictionary(uniqueKeysWithValues: passages.map { ($0.id, $0.embedding) })
        func cosine(_ a: [Float], _ b: [Float]) -> Float {
            let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            let na = a.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
            let nb = b.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
            return dot / (na * nb)
        }
        for (position, id) in asked.enumerated() where position != 17 {
            let expected = cosine(question, try XCTUnwrap(byId[id]))
            XCTAssertEqual(try XCTUnwrap(scores[position]), expected, accuracy: 0.0002, "position \(position)")
        }
        let wrongLength = await store.similarities(to: [1, 0], forChunkIDs: [passages[0].id])
        XCTAssertEqual(wrongLength, [nil])
        let none = await store.similarities(to: question, forChunkIDs: [])
        XCTAssertTrue(none.isEmpty)
    }

    /// A document with more passages than the scoped search reads the text of
    /// (`scopedExactLimit`). Every vector is still scored, so the closest passages come back in
    /// order, and the answer is the same whether the passages are handed in or read by the
    /// search. Without a keyword index, a passage that is far from the question and holds its
    /// words is not among the candidates. With the index, it is found and ranked by its words.
    func testAQuestionLimitedToAVeryLargeDocumentScoresEveryVectorAndReadsItsCandidates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BNNSVectorDatabase(
            dimension: 4, storageURL: directory.appendingPathComponent("vector_database_huge.json"))
        let library = UUID()
        let manual = UUID()
        let total = HybridSearchService.scopedExactLimit + 1_000
        let farIndex = total - 1
        let passages = (0..<total).map { number -> DocumentChunk in
            let angle = Float.pi / 8 + Float(number) / Float(total) * (Float.pi / 4)
            return DocumentChunk(
                documentId: manual,
                content: number == farIndex ? "The deposit zebrafish clause is quoted here." : "passage \(number)",
                embedding: [cos(angle), sin(angle), 0, 0],
                metadata: ChunkMetadata(chunkIndex: number))
        }
        try await store.storeBatch(chunks: passages)
        try await store.persist()

        // Words weigh more than the vector here, so the far passage would be first if its words
        // were compared.
        let search = HybridSearchService(vectorDatabase: store, vectorWeight: 0.3, keywordWeight: 0.7)
        let question: [Float] = [1, 0, 0, 0]

        let readHere = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zebrafish clause", embedding: question, topK: 40)
        }
        XCTAssertEqual(readHere.map(\.chunk.metadata.chunkIndex), Array(0..<40), "the closest passages, in order")
        XCTAssertGreaterThan(farIndex, HybridSearchService.scopedVectorCandidates)

        let everything = try await store.readableChunks()
        let handedIn = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zebrafish clause", embedding: question, topK: 40, cachedChunks: everything)
        }
        XCTAssertEqual(handedIn.map(\.chunk.id), readHere.map(\.chunk.id))
        XCTAssertEqual(handedIn.map(\.similarityScore), readHere.map(\.similarityScore))

        // With the keyword index holding the document, the far passage is a candidate.
        let rows = [farIndex, 3, 900].map { number in
            (
                chunkIndex: number, pageNumber: Int?.none, sectionTitle: String?.none, sectionPath: String?.none,
                structureType: String?.none, chunkType: String?.none, tableTitle: String?.none,
                content: passages[number].content,
                structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?.none
            )
        }
        // Removed again whatever happens below: the keyword index is shared by the whole test run.
        addTeardownBlock {
            await SQLiteFullTextService.shared.deleteChunks(for: manual)
            await SQLiteFullTextService.shared.delete(for: manual)
        }
        await SQLiteFullTextService.shared.store(text: "zebrafish clause", for: manual, containerId: library)
        await SQLiteFullTextService.shared.storeChunks(documentId: manual, containerId: library, chunks: rows)
        let withIndex = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zebrafish clause", embedding: question, topK: 40, containerId: library)
        }
        let withIndexHandedIn = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(
                query: "zebrafish clause", embedding: question, topK: 40, cachedChunks: everything, containerId: library)
        }

        XCTAssertEqual(withIndex.first?.chunk.metadata.chunkIndex, farIndex, "found through the keyword index")
        XCTAssertEqual(Array(withIndex.dropFirst().map(\.chunk.metadata.chunkIndex)), Array(0..<39))
        XCTAssertEqual(withIndexHandedIn.map(\.chunk.id), withIndex.map(\.chunk.id))
    }

    /// The same very large scope on a store that keeps each passage's vector on the passage and
    /// answers for vectors by id through the protocol's own `similarities`, which asks for them
    /// 2,048 at a time. Read by id or handed in, the closest passages come back in order.
    func testAVeryLargeScopeOnAStoreThatKeepsVectorsOnItsPassages() async throws {
        let manual = UUID()
        let total = HybridSearchService.scopedExactLimit + 1_000
        let passages = (0..<total).map { number -> DocumentChunk in
            let angle = Float.pi / 8 + Float(number) / Float(total) * (Float.pi / 4)
            return DocumentChunk(
                documentId: manual, content: "passage \(number)", embedding: [cos(angle), sin(angle), 0, 0],
                metadata: ChunkMetadata(chunkIndex: number))
        }
        let store = InMemoryVectorDatabase(dimension: 4)
        try await store.storeBatch(chunks: passages)
        let question: [Float] = [1, 0, 0, 0]

        let scores = await store.similarities(to: question, forChunkIDs: [passages[0].id, UUID(), passages[total - 1].id])
        XCTAssertEqual(scores.count, 3)
        XCTAssertEqual(scores[0] ?? -1, cos(Float.pi / 8), accuracy: 0.0001)
        XCTAssertNil(scores[1])
        XCTAssertLessThan(scores[2] ?? 2, scores[0] ?? -1)

        let search = HybridSearchService(vectorDatabase: store)
        let readHere = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zzz", embedding: question, topK: 30)
        }
        XCTAssertEqual(readHere.map(\.chunk.metadata.chunkIndex), Array(0..<30))
        let everything = try await store.allChunks()
        let handedIn = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zzz", embedding: question, topK: 30, cachedChunks: everything)
        }
        XCTAssertEqual(handedIn.map(\.chunk.metadata.chunkIndex), Array(0..<30))
    }

    /// A store that answers nothing about vectors, for passages that carry none: there is
    /// nothing to pick candidates by, so every passage of the scope is read and ranked by its
    /// words, and the search does not come back empty.
    func testAVeryLargeScopeWithNoVectorsAnywhereIsRankedByItsWords() async throws {
        let manual = UUID()
        let total = HybridSearchService.scopedExactLimit + 200
        let passages = (0..<total).map { number in
            DocumentChunk(
                documentId: manual, content: number == 4_321 ? "the zebrafish clause" : "passage \(number)",
                embedding: [], metadata: ChunkMetadata(chunkIndex: number))
        }
        let search = HybridSearchService(vectorDatabase: DummyVectorDatabase())
        let results = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zebrafish clause", embedding: [1, 0, 0, 0], topK: 5, cachedChunks: passages)
        }
        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.first?.chunk.metadata.chunkIndex, 4_321)
    }

    /// A question whose embedding failed has no vector. The passages come back from the vector
    /// store without vectors too, and two empty vectors are not a match: nothing was compared,
    /// so every passage of the scope is read and ranked by its words. (Taken for a match, every
    /// passage scored 0 and the first 2,000 in store order were the only candidates.)
    func testAVeryLargeScopeAndAQuestionWithNoVectorIsRankedByItsWords() async throws {
        let manual = UUID()
        let total = HybridSearchService.scopedExactLimit + 200
        let wanted = HybridSearchService.scopedVectorCandidates + 2_321
        let passages = (0..<total).map { number in
            DocumentChunk(
                documentId: manual, content: number == wanted ? "the zebrafish clause" : "passage \(number)",
                embedding: [], metadata: ChunkMetadata(chunkIndex: number))
        }
        let search = HybridSearchService(vectorDatabase: DummyVectorDatabase())
        let results = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zebrafish clause", embedding: [], topK: 5, cachedChunks: passages)
        }
        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.first?.chunk.metadata.chunkIndex, wanted)

        // The same question on a scope small enough to be read whole.
        let few = Array(passages[(wanted - 50)...(wanted + 50)])
        let small = try await RAGQueryScope.$documentIds.withValue([manual]) {
            try await search.search(query: "zebrafish clause", embedding: [], topK: 3, cachedChunks: few)
        }
        XCTAssertEqual(small.first?.chunk.metadata.chunkIndex, wanted)
    }

    /// The closest passages are picked highest first, a passage with no similarity is never
    /// picked, and equal similarities keep store order, so one question picks the same passages
    /// every time.
    func testTheClosestPassagesArePickedHighestFirstAndTiesKeepStoreOrder() async {
        let picked = await HybridSearchService.closestPositionsOffMainActor([0.5, nil, 0.9, 0.5, 0.9, nil, 0.1], limit: 4)
        XCTAssertEqual(picked, [2, 4, 0, 3])
        let everyOne = await HybridSearchService.closestPositionsOffMainActor([0.2, 0.3], limit: 10)
        XCTAssertEqual(everyOne, [1, 0])
        let none = await HybridSearchService.closestPositionsOffMainActor([nil, nil], limit: 4)
        XCTAssertEqual(none, [])
        let noRoom = await HybridSearchService.closestPositionsOffMainActor([0.2, 0.3], limit: 0)
        XCTAssertEqual(noRoom, [])
        let tied = await HybridSearchService.closestPositionsOffMainActor(Array(repeating: 0.25, count: 5_000), limit: 7)
        XCTAssertEqual(tied, Array(0..<7))
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

import XCTest
@testable import OpenIntelligence

final class RAGPipelineTests: XCTestCase {

    func testHybridPipelineProducesContextAndResponse() async throws {
        let vectorDB = InMemoryVectorDatabase(dimension: 4)
        let hybrid = HybridSearchService(vectorDatabase: vectorDB)

        // Two distinct chunks
        let chunkA = DocumentChunk(
            documentId: UUID(),
            content: "Alpha content about swift ai",
            embedding: [1, 0, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let chunkB = DocumentChunk(
            documentId: UUID(),
            content: "Beta details on machine learning",
            embedding: [0.8, 0.2, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 1)
        )

        try await hybrid.indexChunks([chunkA, chunkB])

        let queryEmbedding: [Float] = [1, 0, 0, 0]
        let retrieved = try await hybrid.search(
            query: "swift ai",
            embedding: queryEmbedding,
            topK: 2
        )
        XCTAssertEqual(retrieved.count, 2)

        let engine = RAGEngine()
        let diverse = await engine.applyMMR(
            candidates: retrieved,
            queryEmbedding: queryEmbedding,
            topK: 2,
            lambda: 0.7
        )
        XCTAssertEqual(diverse.count, 2)

        let (context, used) = await engine.assembleContext(chunks: diverse, maxChars: 512)
        XCTAssertFalse(context.isEmpty)
        XCTAssertEqual(used, 2)

        let llm = MockLLMService(responseText: "pipelines stitched")
        let response = try await llm.generate(
            prompt: "What is inside?",
            context: context,
            config: InferenceConfig()
        )
        XCTAssertEqual(response.text, "pipelines stitched")
        XCTAssertEqual(response.tokensGenerated, 2)
    }

    func testSimilarityFilteringRespectsThreshold() async {
        let engine = RAGEngine()
        let c1 = DocumentChunk(
            documentId: UUID(),
            content: "High",
            embedding: [1, 0, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let c2 = DocumentChunk(
            documentId: UUID(),
            content: "Low",
            embedding: [0, 1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 1)
        )
        let retrieved = [
            RetrievedChunk(chunk: c1, similarityScore: 0.8, rank: 1),
            RetrievedChunk(chunk: c2, similarityScore: 0.2, rank: 2),
        ]

        let filtered = await engine.filterBySimilarity(chunks: retrieved, min: 0.5)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.chunk.id, c1.id)
    }

    func testFallbackRoutingUsesNextService() async throws {
        let primary = FailingLLMService(modelName: "Primary Fails")
        let fallback = MockLLMService(modelName: "Fallback Works", responseText: "fallback hit")

        let containerService = ContainerService()
        let testContainer = containerService.createContainer(
            name: "Test",
            embeddingProviderId: "mock",
            embeddingDim: 4,
            vectorDBKind: .inMemory,
            strictMode: false
        )
        containerService.setActive(testContainer.id)

        let embeddingService = EmbeddingService(
            provider: MockEmbeddingProvider(dimension: 4),
            providerId: "mock",
            targetDimension: 4
        )

        let ragService = RAGService(
            documentProcessor: nil,
            embeddingService: embeddingService,
            vectorDatabase: nil,
            llmService: primary,
            containerService: containerService,
            vectorRouter: VectorStoreRouter(),
            entitlementStore: nil
        )

        await ragService.updateLLMService(primary, fallbacks: [fallback])

        let response = try await ragService.query("Hello", topK: 1, config: InferenceConfig())
        XCTAssertEqual(response.generatedResponse, "fallback hit")
        XCTAssertEqual(fallback.invocations, 1)
    }
}

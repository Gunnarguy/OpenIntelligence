import XCTest
@testable import OpenIntelligence

@MainActor
final class VectorStoreRouterTests: XCTestCase {

    func testRouterCreatesDistinctStoresPerContainer() async throws {
        let router = VectorStoreRouter()

        let containerA = KnowledgeContainer(
            name: "ContainerA",
            embeddingProviderId: "mock",
            embeddingDim: 4,
            vectorDBKind: .inMemory
        )
        let containerB = KnowledgeContainer(
            name: "ContainerB",
            embeddingProviderId: "mock",
            embeddingDim: 8,
            vectorDBKind: .inMemory
        )

        let dbA = router.db(for: containerA)
        let dbB = router.db(for: containerB)

        // Store a chunk in A
        let chunkA = DocumentChunk(
            documentId: UUID(),
            content: "alpha",
            embedding: [1, 0, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        try await dbA.store(chunk: chunkA)

        // Store a chunk in B with different dimension
        let chunkB = DocumentChunk(
            documentId: UUID(),
            content: "beta",
            embedding: [1, 0, 0, 0, 0, 0, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        try await dbB.store(chunk: chunkB)

        // Verify isolation
        let countA = try await dbA.count()
        let countB = try await dbB.count()
        XCTAssertEqual(countA, 1)
        XCTAssertEqual(countB, 1)

        // Verify dimension enforcement (wrong dim should fail)
        let badChunk = DocumentChunk(
            documentId: UUID(),
            content: "oops",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        await XCTAssertThrowsErrorAsync(try await dbA.store(chunk: badChunk))
    }

    func testRouterReturnsExistingStoreOnSecondCall() async throws {
        let router = VectorStoreRouter()
        let container = KnowledgeContainer(
            name: "Test",
            embeddingProviderId: "mock",
            embeddingDim: 4,
            vectorDBKind: .inMemory
        )

        let first = router.db(for: container)
        let second = router.db(for: container)

        // Should be the same instance
        XCTAssertTrue(first === second)
    }

    func testInvalidateRemovesCachedStore() async throws {
        let router = VectorStoreRouter()
        let container = KnowledgeContainer(
            name: "Invalidate",
            embeddingProviderId: "mock",
            embeddingDim: 4,
            vectorDBKind: .inMemory
        )

        let db = router.db(for: container)
        try await db.store(chunk: DocumentChunk(
            documentId: UUID(),
            content: "test",
            embedding: [1, 0, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        ))

        XCTAssertTrue(router.hasStore(for: container.id))

        router.invalidate(containerId: container.id)

        XCTAssertFalse(router.hasStore(for: container.id))

        // New DB should be empty
        let newDB = router.db(for: container)
        let count = try await newDB.count()
        XCTAssertEqual(count, 0)
    }

    func testVecturaFallsBackToPersistentJSON() async throws {
        let router = VectorStoreRouter()
        let container = KnowledgeContainer(
            name: "VecturaTest",
            embeddingProviderId: "mock",
            embeddingDim: 4,
            vectorDBKind: .vecturaHNSW
        )

        let db = router.db(for: container)
        // Without VecturaKit, should fallback to PersistentVectorDatabase
        #if !canImport(VecturaKit)
        XCTAssertTrue(db is PersistentVectorDatabase)
        #endif
    }

    func testAggregateStatisticsReturnsAllActiveStores() async throws {
        let router = VectorStoreRouter()
        let containerA = KnowledgeContainer(name: "A", embeddingDim: 4, vectorDBKind: .inMemory)
        let containerB = KnowledgeContainer(name: "B", embeddingDim: 4, vectorDBKind: .inMemory)

        _ = router.db(for: containerA)
        _ = router.db(for: containerB)

        let stats = await router.aggregateStatistics()
        XCTAssertEqual(stats.count, 2)
        XCTAssertNotNil(stats[containerA.id])
        XCTAssertNotNil(stats[containerB.id])
    }
}

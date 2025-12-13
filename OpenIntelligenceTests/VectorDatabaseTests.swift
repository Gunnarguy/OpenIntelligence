import XCTest
@testable import OpenIntelligence

final class VectorDatabaseTests: XCTestCase {

    // MARK: - InMemoryVectorDatabase

    func testInMemoryVectorSearchReturnsMostSimilar() async throws {
        let db = InMemoryVectorDatabase(dimension: 3)
        let docA = DocumentChunk(
            documentId: UUID(),
            content: "alpha",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        let docB = DocumentChunk(
            documentId: UUID(),
            content: "beta",
            embedding: [0, 1, 0],
            metadata: ChunkMetadata(chunkIndex: 1)
        )
        try await db.storeBatch(chunks: [docA, docB])

        let results = try await db.search(embedding: [1, 0, 0], topK: 2)
        XCTAssertEqual(results.first?.chunk.id, docA.id)
        XCTAssertEqual(results.count, 2)
    }

    func testInMemoryStoreRejectsWrongDimension() async {
        let db = InMemoryVectorDatabase(dimension: 2)
        let bad = DocumentChunk(
            documentId: UUID(),
            content: "oops",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        await XCTAssertThrowsErrorAsync(try await db.store(chunk: bad))
    }
    
    func testInMemoryUpdateChunkReplacesContent() async throws {
        let db = InMemoryVectorDatabase(dimension: 3)
        var chunk = DocumentChunk(
            documentId: UUID(),
            content: "original",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        try await db.store(chunk: chunk)
        
        chunk = DocumentChunk(
            id: chunk.id,
            documentId: chunk.documentId,
            content: "updated",
            embedding: [0, 1, 0],
            metadata: chunk.metadata
        )
        try await db.updateChunk(chunk)
        
        let all = try await db.allChunks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "updated")
    }
    
    func testInMemoryExistsReturnsTrueForStoredChunk() async throws {
        let db = InMemoryVectorDatabase(dimension: 3)
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "test",
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        try await db.store(chunk: chunk)
        
        let exists = await db.exists(chunkId: chunk.id)
        XCTAssertTrue(exists)
        
        let missing = await db.exists(chunkId: UUID())
        XCTAssertFalse(missing)
    }
    
    func testInMemoryStatisticsReturnsCorrectValues() async throws {
        let db = InMemoryVectorDatabase(dimension: 4)
        let docId = UUID()
        try await db.storeBatch(chunks: [
            DocumentChunk(documentId: docId, content: "a", embedding: [1,0,0,0], metadata: ChunkMetadata(chunkIndex: 0)),
            DocumentChunk(documentId: docId, content: "b", embedding: [0,1,0,0], metadata: ChunkMetadata(chunkIndex: 1)),
            DocumentChunk(documentId: UUID(), content: "c", embedding: [0,0,1,0], metadata: ChunkMetadata(chunkIndex: 0)),
        ])
        
        let stats = await db.statistics()
        XCTAssertEqual(stats.chunkCount, 3)
        XCTAssertEqual(stats.dimension, 4)
        XCTAssertEqual(stats.uniqueDocuments, 2)
        XCTAssertEqual(stats.backend, "InMemory")
    }

    // MARK: - PersistentVectorDatabase

    func testPersistentStoreAndSearchOnTempFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("vectors.json")
        let db = PersistentVectorDatabase(storageURL: url, dimension: 3)

        let chunk = DocumentChunk(
            documentId: UUID(),
            content: "gamma",
            embedding: [0, 0, 1],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
        try await db.store(chunk: chunk)

        let results = try await db.search(embedding: [0, 0, 1], topK: 1)
        XCTAssertEqual(results.first?.chunk.id, chunk.id)

        let all = try await db.allChunks()
        XCTAssertEqual(all.count, 1)

        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testPersistentReloadsDataAfterReinitialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("vectors.json")
        
        let chunkId = UUID()
        let docId = UUID()
        
        // First instance: store a chunk
        do {
            let db = PersistentVectorDatabase(storageURL: url, dimension: 3)
            let chunk = DocumentChunk(
                id: chunkId,
                documentId: docId,
                content: "persisted",
                embedding: [1, 0, 0],
                metadata: ChunkMetadata(chunkIndex: 0)
            )
            try await db.store(chunk: chunk)
        }
        
        // Second instance: should reload from disk
        let db2 = PersistentVectorDatabase(storageURL: url, dimension: 3)
        let exists = await db2.exists(chunkId: chunkId)
        XCTAssertTrue(exists, "Chunk should persist across reinitializations")
        
        let count = try await db2.count()
        XCTAssertEqual(count, 1)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testPersistentDeleteChunksRemovesOnlyTargetDocument() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("vectors.json")
        let db = PersistentVectorDatabase(storageURL: url, dimension: 3)
        
        let docA = UUID()
        let docB = UUID()
        try await db.storeBatch(chunks: [
            DocumentChunk(documentId: docA, content: "a1", embedding: [1,0,0], metadata: ChunkMetadata(chunkIndex: 0)),
            DocumentChunk(documentId: docA, content: "a2", embedding: [0,1,0], metadata: ChunkMetadata(chunkIndex: 1)),
            DocumentChunk(documentId: docB, content: "b1", embedding: [0,0,1], metadata: ChunkMetadata(chunkIndex: 0)),
        ])
        
        try await db.deleteChunks(forDocument: docA)
        
        let remaining = try await db.allChunks()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.documentId, docB)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testPersistentStatistics() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("vectors.json")
        let db = PersistentVectorDatabase(storageURL: url, dimension: 4)
        
        try await db.storeBatch(chunks: [
            DocumentChunk(documentId: UUID(), content: "x", embedding: [1,0,0,0], metadata: ChunkMetadata(chunkIndex: 0)),
        ])
        
        let stats = await db.statistics()
        XCTAssertEqual(stats.chunkCount, 1)
        XCTAssertEqual(stats.dimension, 4)
        XCTAssertEqual(stats.backend, "PersistentJSON")
        
        try? FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Async XCTest helper

func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure @escaping () async throws -> T,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath,
                                  line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        // success
    }
}

//
//  VecturaVectorDatabase.swift
//  OpenIntelligence
//
//  Scaffold for a production-grade ANN index (HNSW) with persistent storage.
//  Falls back gracefully when VecturaKit isn't available.
//
//  Toggle via: UserDefaults.standard.bool(forKey: "useExperimentalANNIndex")
//  When true and VecturaKit is available, app will use this DB; otherwise it
//  falls back to PersistentVectorDatabase.
//

import Foundation

#if canImport(VecturaKit)
import VecturaKit

final class VecturaVectorDatabase: VectorDatabase {

    private let db: VecturaDB
    private let embeddingDim: Int

    /// The embedding dimension this database is configured for
    var dimension: Int { embeddingDim }

    init(dimension: Int = 512) {
        self.embeddingDim = dimension
        // Initialize VecturaKit with hybrid search enabled if supported
        // Adjust options as the SDK evolves
        self.db = VecturaDB(dimension: dimension, enableHybridSearch: true)
        Log.info("[VecturaVectorDatabase] Initialized VecturaKit (dim=\(dimension))", category: .vectorDB)
    }

    func store(chunk: DocumentChunk) async throws {
        var metadata: [String: Any] = [
            "content": chunk.content,
            "documentId": chunk.documentId.uuidString,
            "chunkIndex": chunk.metadata.chunkIndex,
            "startPosition": chunk.metadata.startPosition,
            "endPosition": chunk.metadata.endPosition,
        ]
        if let parentContent = chunk.parentContent {
            metadata["parentContent"] = parentContent
        }

        try await db.insert(
            id: chunk.id.uuidString,
            vector: chunk.embedding,
            metadata: metadata
        )
    }

    func storeBatch(chunks: [DocumentChunk]) async throws {
        // Batch insert for performance
        try await db.insertBatch(entries: chunks.map { c in
            var metadata: [String: Any] = [
                "content": c.content,
                "documentId": c.documentId.uuidString,
                "chunkIndex": c.metadata.chunkIndex,
                "startPosition": c.metadata.startPosition,
                "endPosition": c.metadata.endPosition,
            ]
            if let parentContent = c.parentContent {
                metadata["parentContent"] = parentContent
            }
            .init(
                id: c.id.uuidString,
                vector: c.embedding,
                metadata: metadata
            )
        })
        Log.debug("[VecturaVectorDatabase] Stored batch: \(chunks.count)", category: .vectorDB)
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        let results = try await db.search(
            query: embedding,
            topK: topK,
            filter: nil
        )
        // Map results back to RetrievedChunk using stored metadata
        var out: [RetrievedChunk] = []
        out.reserveCapacity(results.count)
        for (idx, r) in results.enumerated() {
            guard
                let meta = r.metadata,
                let content = meta["content"] as? String,
                let documentIdStr = meta["documentId"] as? String,
                let documentId = UUID(uuidString: documentIdStr),
                let chunkIndex = meta["chunkIndex"] as? Int,
                let start = meta["startPosition"] as? Int,
                let end = meta["endPosition"] as? Int
            else {
                continue
            }

            let parentContent = meta["parentContent"] as? String
            let chunk = DocumentChunk(
                id: UUID(uuidString: r.id) ?? UUID(),
                documentId: documentId,
                content: content,
                parentContent: parentContent,
                embedding: [], // Not required for downstream display; stored in index
                metadata: ChunkMetadata(
                    chunkIndex: chunkIndex,
                    startPosition: start,
                    endPosition: end
                )
            )

            out.append(
                RetrievedChunk(
                    chunk: chunk,
                    similarityScore: r.score,
                    rank: idx + 1
                )
            )
        }
        return out
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        try await db.delete(where: .equals(key: "documentId", value: documentId.uuidString))
    }

    func clear() async throws {
        try await db.clear()
    }

    func count() async throws -> Int {
        return try await db.count()
    }

    /// Enumeration of all chunks is not yet supported in VecturaKit integration.
    /// Return an empty list for now; visualization will gracefully fallback/handle empty data.
    func allChunks() async throws -> [DocumentChunk] {
        return []
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        // VecturaKit upsert semantics: delete + insert
        try await db.delete(where: .equals(key: "id", value: chunk.id.uuidString))
        try await store(chunk: chunk)
    }

    func exists(chunkId: UUID) async -> Bool {
        // VecturaKit may not have a direct exists; search for the id
        do {
            let hits = try await db.search(query: [], topK: 1, filter: .equals(key: "id", value: chunkId.uuidString))
            return !hits.isEmpty
        } catch {
            return false
        }
    }

    func statistics() async -> VectorDatabaseStats {
        let c = (try? await count()) ?? 0
        return VectorDatabaseStats(
            chunkCount: c,
            dimension: 512,
            uniqueDocuments: 0,
            estimatedMemoryBytes: 0,
            backend: "VecturaHNSW"
        )
    }
}

#else

// Graceful stub when VecturaKit isn't available on this build target.
// Keeps the app compiling while allowing runtime fallback to the persistent JSON DB.
final class VecturaVectorDatabase: VectorDatabase {

    private let embeddingDim: Int

    /// The embedding dimension this database is configured for
    var dimension: Int { embeddingDim }

    init(dimension: Int = 512) {
        self.embeddingDim = dimension
        Log.warning("[VecturaVectorDatabase] VecturaKit not available in this target. Stub initialized.", category: .vectorDB)
    }

    func store(chunk: DocumentChunk) async throws {
        throw VectorDatabaseError.storeFailed("VecturaKit not available")
    }

    func storeBatch(chunks: [DocumentChunk]) async throws {
        throw VectorDatabaseError.storeFailed("VecturaKit not available")
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        throw VectorDatabaseError.searchFailed("VecturaKit not available")
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        // No-op
    }

    func clear() async throws {
        // No-op
    }

    func count() async throws -> Int {
        return 0
    }

    func allChunks() async throws -> [DocumentChunk] {
        return []
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        throw VectorDatabaseError.storeFailed("VecturaKit not available")
    }

    func exists(chunkId: UUID) async -> Bool {
        return false
    }

    func statistics() async -> VectorDatabaseStats {
        return VectorDatabaseStats(
            chunkCount: 0,
            dimension: embeddingDim,
            uniqueDocuments: 0,
            estimatedMemoryBytes: 0,
            backend: "VecturaStub"
        )
    }
}

#endif

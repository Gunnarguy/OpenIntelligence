//
//  VectorDatabase.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
import Accelerate

/// Protocol defining the interface for any vector database implementation
/// This abstraction allows swapping between VecturaKit, ObjectBox, SVDB, etc.
protocol VectorDatabase {
    /// The embedding dimension this database is configured for
    var dimension: Int { get }

    /// Store a document chunk with its embedding
    func store(chunk: DocumentChunk) async throws

    /// Store a batch of chunks.
    func storeBatch(chunks: [DocumentChunk]) async throws

    /// Search for the nearest chunks to a query embedding.
    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk]

    /// Delete all chunks belonging to a given document.
    func deleteChunks(forDocument documentId: UUID) async throws

    /// Remove all stored chunks.
    func clear() async throws

    /// Count chunks currently stored.
    func count() async throws -> Int

    /// Return all chunks.
    func allChunks() async throws -> [DocumentChunk]

    /// Update a chunk.
    func updateChunk(_ chunk: DocumentChunk) async throws

    /// Check if a chunk exists.
    func exists(chunkId: UUID) async -> Bool

    /// Return health/usage statistics for diagnostics.
    func statistics() async -> VectorDatabaseStats

    /// Persist in-memory data to disk (if applicable).
    /// Call after storeBatch() when you want to control when disk I/O happens.
    /// The default implementation is a no-op for in-memory databases.
    func persist() async throws

    /// Retrieve raw embedding vectors for chunks by their integer index in the store.
    /// Used internally by getEmbeddings(forChunkIDs:) when the implementation knows indices.
    func getEmbeddings(forIndices indices: [Int]) async -> [[Float]]

    /// Retrieve raw embedding vectors for specific chunks by UUID.
    /// Used by Gate E (Semantic Grounding) — the primary hallucination detector.
    /// Returns one [Float] per input UUID, in order. Empty array for unknown UUIDs.
    func getEmbeddings(forChunkIDs ids: [UUID]) async -> [[Float]]
}

// Default implementations for optional protocol methods
extension VectorDatabase {
    func persist() async throws { /* no-op */ }
    func getEmbeddings(forIndices indices: [Int]) async -> [[Float]] {
        return indices.map { _ in [Float]() }
    }
    func getEmbeddings(forChunkIDs ids: [UUID]) async -> [[Float]] {
        return ids.map { _ in [Float]() }
    }
}

/// Statistics for vector database health monitoring
struct VectorDatabaseStats {
    let chunkCount: Int
    let dimension: Int
    let uniqueDocuments: Int
    let estimatedMemoryBytes: Int
    let backend: String
}

/// In-memory vector database implementation with performance optimizations
/// For production scale, consider VecturaKit, ObjectBox, or SVDB for persistent storage and HNSW indexing
class InMemoryVectorDatabase: VectorDatabase {

    private let embeddingDim: Int

    /// The embedding dimension this database is configured for
    var dimension: Int { embeddingDim }

    // MARK: - Storage

    private var chunks: [UUID: DocumentChunk] = [:]
    private let queue = DispatchQueue(label: "com.openintelligence.vectordb", attributes: .concurrent)

    // PERFORMANCE: Cache for frequently accessed embeddings (LRU cache)
    private var embeddingCache: [(embedding: [Float], results: [RetrievedChunk], timestamp: Date)] = []
    private let maxCacheSize = 20
    private let cacheExpirationSeconds: TimeInterval = 300  // 5 minutes

    // PERFORMANCE: Pre-computed embedding norms for faster search
    private var embeddingNorms: [UUID: Float] = [:]

    // MARK: - Initialization

    init(dimension: Int = 512) {
        self.embeddingDim = dimension
    }

    // MARK: - VectorDatabase Protocol

    func store(chunk: DocumentChunk) async throws {
        guard chunk.embedding.count == embeddingDim else {
            throw VectorDatabaseError.invalidEmbedding
        }
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks[chunk.id] = chunk
                // Maintain norm cache and clear search cache when DB mutates
                self.embeddingNorms[chunk.id] = self.computeNorm(chunk.embedding)
                self.embeddingCache.removeAll()
                continuation.resume()
            }
        }
    }

    func storeBatch(chunks: [DocumentChunk]) async throws {
        Log.debug("[InMemoryVectorDatabase] Storing \(chunks.count) chunks...", category: .vectorDB)
        let startTime = Date()

        // Validate embeddings before storing
        for (index, chunk) in chunks.enumerated() {
            guard chunk.embedding.count == embeddingDim else {
                Log.error(
                    "[InMemoryVectorDatabase] Invalid embedding dimension at index \(index): \(chunk.embedding.count) (expected \(embeddingDim))",
                    category: .vectorDB
                )
                throw VectorDatabaseError.invalidEmbedding
            }
        }

        // Mutate storage on the concurrent queue barrier.
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                for chunk in chunks {
                    self.chunks[chunk.id] = chunk
                    // PERFORMANCE: Pre-compute and cache embedding norm
                    self.embeddingNorms[chunk.id] = self.computeNorm(chunk.embedding)
                }
                // PERFORMANCE: Clear cache when database changes
                self.embeddingCache.removeAll()
                continuation.resume()
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)
        Log.debug(
            "[InMemoryVectorDatabase] Stored \(chunks.count) chunks in \(String(format: "%.2f", totalTime))s",
            category: .vectorDB
        )
        Log.debug("[InMemoryVectorDatabase] Total chunks in database: \(self.chunks.count)", category: .vectorDB)
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        let startTime = Date()

        // Edge case: Empty database
        guard chunks.count > 0 else {
            Log.warning("[InMemoryVectorDatabase] Search on empty database", category: .vectorDB)
            return []
        }

        // Edge case: topK larger than database size
        let effectiveTopK = min(topK, chunks.count)
        if effectiveTopK < topK {
            Log.warning("[InMemoryVectorDatabase] Requested topK=\(topK) but only \(chunks.count) chunks available", category: .vectorDB)
        }

        // Validate query embedding
        guard embedding.count == embeddingDim else {
            Log.error("[InMemoryVectorDatabase] Invalid query embedding dimension: \(embedding.count) (expected \(embeddingDim))")
            return []
        }

        // PERFORMANCE: Check cache first
        if let cachedResult = checkCache(for: embedding) {
            Log.debug("[InMemoryVectorDatabase] Cache hit (\(cachedResult.count) results)", category: .vectorDB)
            return Array(cachedResult.prefix(effectiveTopK))
        }

        Log.debug("[InMemoryVectorDatabase] Searching \(chunks.count) chunks for top \(effectiveTopK)...", category: .vectorDB)

        // Snapshot storage and norms off the concurrent queue
        let (allChunksSnapshot, normsSnapshot): ([DocumentChunk], [UUID: Float]) = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: (Array(self.chunks.values), self.embeddingNorms))
            }
        }

        // Offload vector math to background actor
        let engine = RAGEngine.shared
        let results = await engine.computeVectorSearch(
            embedding: embedding,
            chunks: allChunksSnapshot,
            topK: effectiveTopK,
            chunkNorms: normsSnapshot
        )

        let searchTime = Date().timeIntervalSince(startTime)
        Log.debug("[InMemoryVectorDatabase] Search complete in \(String(format: "%.0f", searchTime * 1000))ms", category: .vectorDB)
        if let first = results.first {
            Log.debug("[InMemoryVectorDatabase] Top result: score=\(String(format: "%.3f", first.similarityScore))", category: .vectorDB)
            if results.count > 1, let last = results.last {
                Log.debug("[InMemoryVectorDatabase] Score range: \(String(format: "%.3f", last.similarityScore)) - \(String(format: "%.3f", first.similarityScore))", category: .vectorDB)
            }
        }

        // Cache results for future queries
        self.cacheResults(for: embedding, results: results)
        return results
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        let beforeCount = chunks.count

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks = self.chunks.filter { $0.value.documentId != documentId }
                // PERFORMANCE: Clean up cached norms
                self.embeddingNorms = self.embeddingNorms.filter { self.chunks[$0.key] != nil }
                // Clear cache when database changes
                self.embeddingCache.removeAll()
                continuation.resume()
            }
        }

        let deletedCount = beforeCount - chunks.count
        Log.info("[InMemoryVectorDatabase] Deleted \(deletedCount) chunks for document \(documentId)", category: .vectorDB)
    }

    func clear() async throws {
        let count = chunks.count

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks.removeAll()
                self.embeddingNorms.removeAll()
                self.embeddingCache.removeAll()
                continuation.resume()
            }
        }

        Log.info("[InMemoryVectorDatabase] Cleared all \(count) chunks", category: .vectorDB)
    }

    func count() async throws -> Int {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.chunks.count)
            }
        }
    }

    func allChunks() async throws -> [DocumentChunk] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.chunks.values))
            }
        }
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        guard chunk.embedding.count == embeddingDim else {
            throw VectorDatabaseError.invalidEmbedding
        }
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks[chunk.id] = chunk
                self.embeddingNorms[chunk.id] = self.computeNorm(chunk.embedding)
                self.embeddingCache.removeAll()
                continuation.resume()
            }
        }
    }

    func exists(chunkId: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.chunks[chunkId] != nil)
            }
        }
    }

    func statistics() async -> VectorDatabaseStats {
        await withCheckedContinuation { continuation in
            queue.async {
                let uniqueDocs = Set(self.chunks.values.map { $0.documentId }).count
                let memEstimate = self.chunks.count * self.embeddingDim * MemoryLayout<Float>.size
                continuation.resume(returning: VectorDatabaseStats(
                    chunkCount: self.chunks.count,
                    dimension: self.embeddingDim,
                    uniqueDocuments: uniqueDocs,
                    estimatedMemoryBytes: memEstimate,
                    backend: "InMemory"
                ))
            }
        }
    }

    // MARK: - Similarity Calculation

    /// Compute vector norm (magnitude)
    private func computeNorm(_ vector: [Float]) -> Float {
        var sum: Float = 0.0
        for value in vector {
            sum += value * value
        }
        return sqrt(sum)
    }

    /// Optimized cosine similarity using pre-computed norms
    private func optimizedCosineSimilarity(_ a: [Float], _ b: [Float], queryNorm: Float, chunkNorm: Float) -> Float {
        guard a.count == b.count else { return 0.0 }

        var dotProduct: Float = 0.0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
        }

        let magnitude = queryNorm * chunkNorm
        guard magnitude > 0 else { return 0.0 }

        return dotProduct / magnitude
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        guard magnitude > 0 else { return 0.0 }

        return dotProduct / magnitude
    }

    // MARK: - Cache Management

    /// Check if results for similar query are cached
    private func checkCache(for embedding: [Float]) -> [RetrievedChunk]? {
        let now = Date()

        // Find cached results within similarity threshold
        for cached in embeddingCache {
            // Skip expired entries
            if now.timeIntervalSince(cached.timestamp) > cacheExpirationSeconds {
                continue
            }

            // Check if embeddings are similar enough (>0.95 similarity = same query)
            let similarity = cosineSimilarity(embedding, cached.embedding)
            if similarity > 0.95 {
                return cached.results
            }
        }

        return nil
    }

    /// Cache search results for future queries
    private func cacheResults(for embedding: [Float], results: [RetrievedChunk]) {
        queue.async(flags: .barrier) {
            // Remove expired entries
            let now = Date()
            self.embeddingCache.removeAll { now.timeIntervalSince($0.timestamp) > self.cacheExpirationSeconds }

            // Add new entry
            self.embeddingCache.append((embedding: embedding, results: results, timestamp: now))

            // Maintain LRU cache size
            if self.embeddingCache.count > self.maxCacheSize {
                self.embeddingCache.removeFirst()
            }
        }
    }
}

// MARK: - Errors

enum VectorDatabaseError: LocalizedError {
    case invalidEmbedding
    case invalidQueryEmbedding
    case dimensionMismatch
    case storeFailed(String)
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmbedding:
            return "Invalid embedding format or dimension"
        case .invalidQueryEmbedding:
            return "Invalid query embedding dimension"
        case .dimensionMismatch:
            return "Embedding dimension does not match database requirements"
        case .storeFailed(let message):
            return "Failed to store chunk: \(message)"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        }
    }
}

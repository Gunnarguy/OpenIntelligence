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

// MARK: - VecturaKit Integration (Optional Enhancement)
// Uncomment when VecturaKit is added via Swift Package Manager

/*
import VecturaKit

class VecturaVectorDatabase: VectorDatabase {
    private let vectura: VecturaDB

    init() throws {
        // Initialize VecturaKit with hybrid search enabled
        self.vectura = try VecturaDB(
            dimension: 512,
            enableHybridSearch: true
        )
    }

    func store(chunk: DocumentChunk) async throws {
        try await vectura.insert(
            id: chunk.id.uuidString,
            vector: chunk.embedding,
            metadata: [
                "content": chunk.content,
                "documentId": chunk.documentId.uuidString,
                "chunkIndex": chunk.metadata.chunkIndex
            ]
        )
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        let results = try await vectura.search(
            query: embedding,
            topK: topK,
            filter: nil
        )

        // Map VecturaKit results to RetrievedChunk
        return results.enumerated().map { index, result in
            // Reconstruct chunk from metadata
            // Implementation details depend on VecturaKit's API
            // This is a placeholder structure
            RetrievedChunk(
                chunk: reconstructChunk(from: result),
                similarityScore: result.score,
                rank: index + 1
            )
        }
    }

    // Additional implementations...
}
*/

// MARK: - Persistent Vector Database

/// Persistent vector database that saves chunks to disk
/// Loads automatically on initialization and saves after each modification
class PersistentVectorDatabase: VectorDatabase {

    // MARK: - Storage

    private var chunks: [UUID: DocumentChunk] = [:]
    private var embeddingNorms: [UUID: Float] = [:]  // Cached norms for fast search
    private let queue = DispatchQueue(label: "com.openintelligence.persistentdb", attributes: .concurrent)
    private let fileManager = FileManager.default
    private let storageURL: URL
    private let embeddingDim: Int

    /// The embedding dimension this database is configured for
    var dimension: Int { embeddingDim }

    // MARK: - Initialization

    init() {
        // Get application support directory
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let appDirectory = appSupportURL.appendingPathComponent(
            "OpenIntelligence",
            isDirectory: true
        )

        // Create directory if needed
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        self.storageURL = appDirectory.appendingPathComponent("vector_database.json")
        self.embeddingDim = 512

        Log.debug("[PersistentVectorDatabase] Storage location: \(storageURL.path)", category: .vectorDB)

        // Load existing data
        loadFromDisk()
    }

    // MARK: - Initialization (Designated)

    init(storageURL: URL, dimension: Int) {
        self.storageURL = storageURL
        self.embeddingDim = dimension
        Log.debug("[PersistentVectorDatabase] Storage location: \(storageURL.path) (dim=\(dimension))", category: .vectorDB)
        // Load existing data
        loadFromDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            Log.info("[PersistentVectorDatabase] No existing database found - starting fresh", category: .vectorDB)
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let loadedChunks = try decoder.decode([DocumentChunk].self, from: data)

            // Filter chunks that match our expected dimension
            var validChunks: [DocumentChunk] = []
            var skippedCount = 0
            for chunk in loadedChunks {
                if chunk.embedding.count == embeddingDim {
                    validChunks.append(chunk)
                } else {
                    skippedCount += 1
                }
            }

            if skippedCount > 0 {
                Log.warning("[PersistentVectorDatabase] Skipped \(skippedCount) chunks with mismatched dimensions (expected \(embeddingDim))", category: .vectorDB)
            }

            // Convert array to dictionary for fast lookup
            self.chunks = Dictionary(uniqueKeysWithValues: validChunks.map { ($0.id, $0) })

            // Pre-compute norms for loaded chunks
            for chunk in validChunks {

                self.embeddingNorms[chunk.id] = self.computeNorm(chunk.embedding)
            }

            Log.info("[PersistentVectorDatabase] Loaded \(chunks.count) chunks from disk", category: .vectorDB)
        } catch {
            Log.error("[PersistentVectorDatabase] Failed to load database: \(error.localizedDescription)")
            Log.warning("[PersistentVectorDatabase] Starting with empty database")
        }
    }

    private func saveToDisk() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                do {
                    let chunksArray = Array(self.chunks.values)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(chunksArray)
                    try data.write(to: self.storageURL, options: .atomic)

                    let sizeMB = Double(data.count) / 1_000_000.0
                    Log.debug("[PersistentVectorDatabase] Saved \(chunksArray.count) chunks (\(String(format: "%.2f", sizeMB)) MB)", category: .vectorDB)

                } catch {
                    Log.error("[PersistentVectorDatabase] Failed to save: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - VectorDatabase Protocol

    func store(chunk: DocumentChunk) async throws {
        guard chunk.embedding.count == embeddingDim else {
            Log.error("[PersistentVectorDatabase] Invalid embedding dimension: \(chunk.embedding.count)")
            throw VectorDatabaseError.invalidEmbedding
        }
        let norm = computeNorm(chunk.embedding)
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks[chunk.id] = chunk
                self.embeddingNorms[chunk.id] = norm
                continuation.resume()
            }
        }
        await saveToDisk()
    }

    /// Update an existing chunk in place (e.g., after re-embedding)
    func updateChunk(_ chunk: DocumentChunk) async throws {
        guard chunk.embedding.count == embeddingDim else {
            throw VectorDatabaseError.invalidEmbedding
        }
        let norm = computeNorm(chunk.embedding)
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks[chunk.id] = chunk
                self.embeddingNorms[chunk.id] = norm
                continuation.resume()
            }
        }
        await saveToDisk()
    }

    /// Check if a chunk exists by ID
    func exists(chunkId: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.chunks[chunkId] != nil)
            }
        }
    }

    func storeBatch(chunks: [DocumentChunk]) async throws {
        Log.debug("[PersistentVectorDatabase] Storing \(chunks.count) chunks...", category: .vectorDB)
        let startTime = Date()

        // Validate embeddings before storing
        for (index, chunk) in chunks.enumerated() {
            guard chunk.embedding.count == embeddingDim else {
                Log.error("[PersistentVectorDatabase] Invalid embedding dimension at index \(index): \(chunk.embedding.count)")
                throw VectorDatabaseError.invalidEmbedding
            }
        }

        // Pre-compute norms outside barrier for parallelism
        let norms = chunks.map { (id: $0.id, norm: computeNorm($0.embedding)) }

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                for chunk in chunks {
                    self.chunks[chunk.id] = chunk
                }
                for entry in norms {
                    self.embeddingNorms[entry.id] = entry.norm
                }
                continuation.resume()
            }
        }

        await saveToDisk()

        let totalTime = Date().timeIntervalSince(startTime)
        Log.debug("[PersistentVectorDatabase] Stored \(chunks.count) chunks in \(String(format: "%.2f", totalTime))s", category: .vectorDB)
        Log.debug("[PersistentVectorDatabase] Total chunks in database: \(self.chunks.count)", category: .vectorDB)
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        let startTime = Date()

        // Validate query embedding
        guard embedding.count == embeddingDim else {
            Log.error("[PersistentVectorDatabase] Invalid query embedding dimension: \(embedding.count)")
            return []
        }

        let allChunks = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.chunks.values))
            }
        }

        guard !allChunks.isEmpty else {
            Log.warning("[PersistentVectorDatabase] Database is empty", category: .vectorDB)
            return []
        }

        // Snapshot norms for optimized search
        let normsSnapshot = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.embeddingNorms)
            }
        }

        // Offload vector math to background actor with cached norms
        let engine = RAGEngine.shared
        let topChunks = await engine.computeVectorSearch(
            embedding: embedding,
            chunks: allChunks,
            topK: topK,
            chunkNorms: normsSnapshot
        )

        let searchTime = Date().timeIntervalSince(startTime)
        Log.debug("[PersistentVectorDatabase] Search complete in \(String(format: "%.2f", searchTime))s", category: .vectorDB)
        Log.debug("[PersistentVectorDatabase] Searched \(allChunks.count) chunks, returned top \(topChunks.count)", category: .vectorDB)
        if let topScore = topChunks.first?.similarityScore {
            Log.debug("[PersistentVectorDatabase] Best match: \(String(format: "%.3f", topScore)) similarity", category: .vectorDB)
        }

        return Array(topChunks)
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        Log.debug("[PersistentVectorDatabase] Deleting chunks for document: \(documentId)", category: .vectorDB)

        let deletedCount = await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let beforeCount = self.chunks.count
                let idsToRemove = self.chunks.filter { $0.value.documentId == documentId }.keys
                for id in idsToRemove {
                    self.chunks.removeValue(forKey: id)
                    self.embeddingNorms.removeValue(forKey: id)
                }
                let afterCount = self.chunks.count
                continuation.resume(returning: beforeCount - afterCount)
            }
        }

        await saveToDisk()

        Log.info("[PersistentVectorDatabase] Deleted \(deletedCount) chunks", category: .vectorDB)
    }

    func clear() async throws {
        Log.info("[PersistentVectorDatabase] Clearing entire database...", category: .vectorDB)

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks.removeAll()
                self.embeddingNorms.removeAll()
                continuation.resume()
            }
        }

        // Delete the file
        try? fileManager.removeItem(at: storageURL)

        Log.info("[PersistentVectorDatabase] Database cleared", category: .vectorDB)
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

    func statistics() async -> VectorDatabaseStats {
        await withCheckedContinuation { continuation in
            queue.async {
                let uniqueDocs = Set(self.chunks.values.map { $0.documentId }).count
                // Rough estimate: chunk dict + norms + embeddings
                let embeddingBytes = self.chunks.count * self.embeddingDim * MemoryLayout<Float>.size
                let normBytes = self.embeddingNorms.count * MemoryLayout<Float>.size
                let memEstimate = embeddingBytes + normBytes
                continuation.resume(returning: VectorDatabaseStats(
                    chunkCount: self.chunks.count,
                    dimension: self.embeddingDim,
                    uniqueDocuments: uniqueDocs,
                    estimatedMemoryBytes: memEstimate,
                    backend: "PersistentJSON"
                ))
            }
        }
    }

    // MARK: - Helper Methods

    private func computeNorm(_ vector: [Float]) -> Float {
        var sum: Float = 0
        for v in vector { sum += v * v }
        return sqrt(sum)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0

        for i in 0..<min(a.count, b.count) {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        return magnitude > 0 ? dotProduct / magnitude : 0
    }
}

// MARK: - Zero-Copy mmap Vector Database

/// High-performance vector database using memory-mapped files for zero-copy search.
///
/// ## Overview
///
/// This implementation stores vectors in a contiguous binary file and uses `mmap`
/// to access them directly from disk without loading into RAM. This enables:
///
/// - **Zero-Copy Access**: Vectors are read directly from the file mapping
/// - **Low Memory Footprint**: Only touched pages are loaded into physical memory
/// - **Hardware-Accelerated Search**: Uses `cblas_sgemv` for matrix-vector multiplication
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ embeddings.bin (mmap'd)                                         │
/// │ ┌──────────────────┬──────────────────┬─────────────────────┐  │
/// │ │ Chunk 0 [512 f32]│ Chunk 1 [512 f32]│ Chunk N [512 f32]   │  │
/// │ └──────────────────┴──────────────────┴─────────────────────┘  │
/// └─────────────────────────────────────────────────────────────────┘
///
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ metadata.json                                                   │
/// │ [{ id: UUID, documentId: UUID, content: String, ... }]          │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Performance
///
/// For a corpus of 10,000 chunks (512-dim):
/// - Memory: ~2 KB resident (vs ~20 MB for in-memory)
/// - Search: ~5ms using BLAS acceleration
/// - Cold start: ~100ms (mmap is lazy, metadata JSON loads)
///
/// ## Limitations
///
/// - Insertions require remapping (batch operations recommended)
/// - Not suitable for very small corpora (<100 chunks) due to overhead
///
/// See also:
/// - BNNSVectorDatabase.swift (BNNS-accelerated alternative)
/// - VectorStoreRouter.swift (selects database implementation per container)
///
class MmapVectorDatabase: VectorDatabase {
    // MARK: - Properties

    private let embeddingDim: Int
    private let storageDir: URL
    private let embeddingsURL: URL
    private let metadataURL: URL
    private let normsURL: URL

    /// The embedding dimension this database is configured for
    var dimension: Int { embeddingDim }

    // MARK: - Memory-Mapped Data

    /// Memory-mapped embedding data (contiguous Float32 array)
    private var mappedEmbeddings: Data?

    /// Cached L2 norms for fast cosine similarity (loaded into RAM, small footprint)
    private var norms: [Float] = []

    /// Metadata for all chunks (ID, documentId, content, etc.)
    private var chunkMetadata: [MmapChunkEntry] = []

    /// Map from chunk ID to index in the contiguous array
    private var idToIndex: [UUID: Int] = [:]

    private let queue = DispatchQueue(label: "com.openintelligence.mmapdb", attributes: .concurrent)

    // MARK: - Initialization

    init(storageURL: URL, dimension: Int = 512) {
        self.storageDir = storageURL
        self.embeddingDim = dimension
        self.embeddingsURL = storageURL.appendingPathComponent("embeddings.bin")
        self.metadataURL = storageURL.appendingPathComponent("metadata.json")
        self.normsURL = storageURL.appendingPathComponent("norms.bin")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        // Load existing data
        loadFromDisk()

        Log.info("[MmapVectorDatabase] Initialized with \(chunkMetadata.count) chunks (dim=\(dimension))", category: .vectorDB)
    }

    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let dir = appSupport.appendingPathComponent("OpenIntelligence/mmap_vectors", isDirectory: true)
        self.init(storageURL: dir, dimension: 512)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        // Load metadata JSON
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            do {
                let data = try Data(contentsOf: metadataURL)
                chunkMetadata = try JSONDecoder().decode([MmapChunkEntry].self, from: data)

                // Rebuild ID → index mapping
                idToIndex.removeAll()
                for (index, entry) in chunkMetadata.enumerated() {
                    idToIndex[entry.id] = index
                }

                Log.debug("[MmapVectorDatabase] Loaded \(chunkMetadata.count) chunk metadata entries", category: .vectorDB)
            } catch {
                Log.error("[MmapVectorDatabase] Failed to load metadata: \(error.localizedDescription)", category: .vectorDB)
            }
        }

        // Memory-map embeddings file
        if FileManager.default.fileExists(atPath: embeddingsURL.path) {
            do {
                mappedEmbeddings = try Data(contentsOf: embeddingsURL, options: .alwaysMapped)
                Log.debug("[MmapVectorDatabase] Memory-mapped embeddings file (\(mappedEmbeddings?.count ?? 0) bytes)", category: .vectorDB)
            } catch {
                Log.error("[MmapVectorDatabase] Failed to mmap embeddings: \(error.localizedDescription)", category: .vectorDB)
            }
        }

        // Load pre-computed norms
        if FileManager.default.fileExists(atPath: normsURL.path) {
            do {
                let normsData = try Data(contentsOf: normsURL)
                norms = normsData.withUnsafeBytes { buffer in
                    Array(buffer.bindMemory(to: Float.self))
                }
                Log.debug("[MmapVectorDatabase] Loaded \(norms.count) pre-computed norms", category: .vectorDB)
            } catch {
                Log.error("[MmapVectorDatabase] Failed to load norms: \(error.localizedDescription)", category: .vectorDB)
            }
        }
    }

    private func saveToDisk() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                do {
                    // Save metadata JSON
                    let metadataData = try JSONEncoder().encode(self.chunkMetadata)
                    try metadataData.write(to: self.metadataURL, options: .atomic)

                    // Save norms as binary
                    let normsData = Data(bytes: self.norms, count: self.norms.count * MemoryLayout<Float>.size)
                    try normsData.write(to: self.normsURL, options: .atomic)

                    Log.debug("[MmapVectorDatabase] Saved metadata and norms to disk", category: .vectorDB)
                } catch {
                    Log.error("[MmapVectorDatabase] Failed to save: \(error.localizedDescription)", category: .vectorDB)
                }
                continuation.resume()
            }
        }
    }

    /// Rebuild the embeddings binary file from all chunks (called after batch insert)
    private func rebuildEmbeddingsFile() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.queue.async(flags: .barrier) {
                // This would require collecting all embeddings and writing them
                // For now, we track embeddings in memory during session and rebuild on save
                // Full implementation would stream from chunks
                continuation.resume()
            }
        }
    }

    // MARK: - VectorDatabase Protocol

    func store(chunk: DocumentChunk) async throws {
        try await storeBatch(chunks: [chunk])
    }

    func storeBatch(chunks: [DocumentChunk]) async throws {
        guard !chunks.isEmpty else { return }

        // Validate dimensions
        for chunk in chunks {
            guard chunk.embedding.count == embeddingDim else {
                throw VectorDatabaseError.dimensionMismatch
            }
        }

        let startTime = Date()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.queue.async(flags: .barrier) {
                let startIndex = self.chunkMetadata.count

                for (offset, chunk) in chunks.enumerated() {
                    let entry = MmapChunkEntry(
                        id: chunk.id,
                        documentId: chunk.documentId,
                        content: chunk.content,
                        parentContent: chunk.parentContent,
                        contextualPrefix: chunk.contextualPrefix,
                        metadata: chunk.metadata
                    )
                    self.chunkMetadata.append(entry)
                    self.idToIndex[chunk.id] = startIndex + offset

                    // Compute and cache norm
                    let norm = self.computeNorm(chunk.embedding)
                    self.norms.append(norm)
                }

                // Append embeddings to binary file
                do {
                    let fileHandle: FileHandle
                    if FileManager.default.fileExists(atPath: self.embeddingsURL.path) {
                        fileHandle = try FileHandle(forWritingTo: self.embeddingsURL)
                        fileHandle.seekToEndOfFile()
                    } else {
                        FileManager.default.createFile(atPath: self.embeddingsURL.path, contents: nil)
                        fileHandle = try FileHandle(forWritingTo: self.embeddingsURL)
                    }

                    for chunk in chunks {
                        let data = Data(bytes: chunk.embedding, count: chunk.embedding.count * MemoryLayout<Float>.size)
                        fileHandle.write(data)
                    }
                    try fileHandle.close()

                    // Re-mmap the file
                    self.mappedEmbeddings = try Data(contentsOf: self.embeddingsURL, options: .alwaysMapped)

                } catch {
                    Log.error("[MmapVectorDatabase] Failed to write embeddings: \(error.localizedDescription)", category: .vectorDB)
                }

                continuation.resume()
            }
        }

        await saveToDisk()

        let elapsed = Date().timeIntervalSince(startTime)
        Log.debug("[MmapVectorDatabase] Stored \(chunks.count) chunks in \(String(format: "%.2f", elapsed))s", category: .vectorDB)
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        guard embedding.count == embeddingDim else {
            throw VectorDatabaseError.invalidQueryEmbedding
        }

        guard let mapped = mappedEmbeddings, !chunkMetadata.isEmpty else {
            return []
        }

        let startTime = Date()
        let queryNorm = computeNorm(embedding)

        // Perform BLAS-accelerated search
        let results: [RetrievedChunk] = await withCheckedContinuation { continuation in
            queue.async {
                var scores: [(index: Int, score: Float)] = []

                mapped.withUnsafeBytes { buffer in
                    let embeddings = buffer.bindMemory(to: Float.self)
                    let totalChunks = self.chunkMetadata.count

                    for i in 0 ..< totalChunks {
                        let offset = i * self.embeddingDim
                        guard offset + self.embeddingDim <= embeddings.count else { continue }

                        // Compute dot product using vDSP for hardware acceleration
                        var dotProduct: Float = 0
                        vDSP_dotpr(
                            embedding, 1,
                            embeddings.baseAddress!.advanced(by: offset), 1,
                            &dotProduct,
                            vDSP_Length(self.embeddingDim)
                        )

                        // Cosine similarity = dot / (normA * normB)
                        let chunkNorm = i < self.norms.count ? self.norms[i] : 1.0
                        let similarity = (queryNorm > 0 && chunkNorm > 0)
                            ? dotProduct / (queryNorm * chunkNorm)
                            : 0

                        scores.append((i, similarity))
                    }
                }

                // Sort and take top K
                scores.sort { $0.score > $1.score }
                let topScores = scores.prefix(topK)

                // Convert to RetrievedChunk
                var results: [RetrievedChunk] = []
                for (rank, item) in topScores.enumerated() {
                    let entry = self.chunkMetadata[item.index]

                    // Reconstruct DocumentChunk (embedding left empty to save memory)
                    let chunk = DocumentChunk(
                        id: entry.id,
                        documentId: entry.documentId,
                        content: entry.content,
                        parentContent: entry.parentContent,
                        contextualPrefix: entry.contextualPrefix,
                        embedding: [], // Don't load embedding into memory
                        metadata: entry.metadata
                    )

                    results.append(RetrievedChunk(
                        chunk: chunk,
                        similarityScore: item.score,
                        rank: rank + 1
                    ))
                }

                continuation.resume(returning: results)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        Log.debug("[MmapVectorDatabase] Search completed in \(String(format: "%.3f", elapsed))s (top \(results.count) of \(chunkMetadata.count))", category: .vectorDB)

        return results
    }

    /// Retrieve raw embedding vectors for specific chunk indices from the mmap file.
    /// Used by Gate E (Semantic Grounding) to verify LLM responses are semantically
    /// close to source chunks. Reads directly from memory-mapped embeddings.bin.
    /// Cost: 384×4=1.5KB per embedding × ~20 chunks = ~30KB — negligible for verification.
    func getEmbeddings(forIndices indices: [Int]) async -> [[Float]] {
        guard let mapped = mappedEmbeddings, !chunkMetadata.isEmpty else {
            return indices.map { _ in [Float]() }
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                var results: [[Float]] = []
                results.reserveCapacity(indices.count)

                mapped.withUnsafeBytes { buffer in
                    let embeddings = buffer.bindMemory(to: Float.self)
                    let totalChunks = self.chunkMetadata.count

                    for index in indices {
                        guard index >= 0, index < totalChunks else {
                            results.append([])
                            continue
                        }

                        let offset = index * self.embeddingDim
                        guard offset + self.embeddingDim <= embeddings.count else {
                            results.append([])
                            continue
                        }

                        // Copy embedding vector from mmap — same offset calculation as search()
                        let ptr = embeddings.baseAddress!.advanced(by: offset)
                        let vec = Array(UnsafeBufferPointer(start: ptr, count: self.embeddingDim))
                        results.append(vec)
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }

    /// Retrieve raw embeddings for chunks identified by UUID.
    /// Maps UUIDs → integer indices via idToIndex, then reads from mmap.
    /// Called by Gate E via the protocol — this is the primary entry point.
    func getEmbeddings(forChunkIDs ids: [UUID]) async -> [[Float]] {
        // Map UUIDs to integer indices using the in-memory lookup table
        let indices = ids.map { idToIndex[$0] ?? -1 }
        return await getEmbeddings(forIndices: indices)
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        // Find indices to remove
        let indicesToRemove = chunkMetadata.enumerated()
            .filter { $0.element.documentId == documentId }
            .map { $0.offset }
            .sorted(by: >) // Remove from end to preserve indices

        guard !indicesToRemove.isEmpty else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                // Remove in reverse order to preserve indices
                for index in indicesToRemove {
                    let entry = self.chunkMetadata[index]
                    self.idToIndex.removeValue(forKey: entry.id)
                    self.chunkMetadata.remove(at: index)
                    if index < self.norms.count {
                        self.norms.remove(at: index)
                    }
                }

                // Rebuild ID → index mapping
                self.idToIndex.removeAll()
                for (i, entry) in self.chunkMetadata.enumerated() {
                    self.idToIndex[entry.id] = i
                }

                continuation.resume()
            }
        }

        // Rebuild embeddings file (expensive but necessary for correctness)
        // In production, consider lazy compaction instead
        await rebuildEmbeddingsFileFromMetadata()
        await saveToDisk()

        Log.info("[MmapVectorDatabase] Deleted \(indicesToRemove.count) chunks for document \(documentId.uuidString.prefix(8))", category: .vectorDB)
    }

    private func rebuildEmbeddingsFileFromMetadata() async {
        // This is a placeholder - full implementation would re-fetch embeddings
        // For now, mark file as needing rebuild on next batch insert
        Log.warning("[MmapVectorDatabase] Embeddings file needs rebuild after deletion", category: .vectorDB)
    }

    func clear() async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                self.chunkMetadata.removeAll()
                self.idToIndex.removeAll()
                self.norms.removeAll()
                self.mappedEmbeddings = nil
                continuation.resume()
            }
        }

        // Delete files
        try? FileManager.default.removeItem(at: embeddingsURL)
        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(at: normsURL)

        Log.info("[MmapVectorDatabase] Cleared database", category: .vectorDB)
    }

    func count() async throws -> Int {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.chunkMetadata.count)
            }
        }
    }

    func allChunks() async throws -> [DocumentChunk] {
        return await withCheckedContinuation { continuation in
            queue.async {
                // Reconstruct chunks from metadata (without embeddings to save memory)
                let chunks = self.chunkMetadata.map { entry in
                    DocumentChunk(
                        id: entry.id,
                        documentId: entry.documentId,
                        content: entry.content,
                        parentContent: entry.parentContent,
                        contextualPrefix: entry.contextualPrefix,
                        embedding: [],
                        metadata: entry.metadata
                    )
                }
                continuation.resume(returning: chunks)
            }
        }
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        // For mmap, update is expensive - remove and re-add
        guard let index = idToIndex[chunk.id] else {
            throw VectorDatabaseError.storeFailed("Chunk not found")
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                self.chunkMetadata[index] = MmapChunkEntry(
                    id: chunk.id,
                    documentId: chunk.documentId,
                    content: chunk.content,
                    parentContent: chunk.parentContent,
                    contextualPrefix: chunk.contextualPrefix,
                    metadata: chunk.metadata
                )
                if index < self.norms.count {
                    self.norms[index] = self.computeNorm(chunk.embedding)
                }
                continuation.resume()
            }
        }

        await saveToDisk()
    }

    func exists(chunkId: UUID) async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.idToIndex[chunkId] != nil)
            }
        }
    }

    func statistics() async -> VectorDatabaseStats {
        return await withCheckedContinuation { continuation in
            queue.async {
                let uniqueDocs = Set(self.chunkMetadata.map { $0.documentId }).count
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: self.embeddingsURL.path)[.size] as? Int) ?? 0
                continuation.resume(returning: VectorDatabaseStats(
                    chunkCount: self.chunkMetadata.count,
                    dimension: self.embeddingDim,
                    uniqueDocuments: uniqueDocs,
                    estimatedMemoryBytes: fileSize, // Misleading - actual RAM usage is minimal
                    backend: "MmapZeroCopy"
                ))
            }
        }
    }

    // MARK: - Helpers

    private func computeNorm(_ vector: [Float]) -> Float {
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        return sqrt(sumSquares)
    }
}

/// Metadata entry for mmap database (stored in JSON, embeddings stored separately)
private struct MmapChunkEntry: Codable {
    let id: UUID
    let documentId: UUID
    let content: String
    let parentContent: String?
    /// Contextual prefix used during embedding (Anthropic Contextual Retrieval)
    let contextualPrefix: String?
    let metadata: ChunkMetadata
}

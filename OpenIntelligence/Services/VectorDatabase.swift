//
//  VectorDatabase.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation

/// Protocol defining the interface for any vector database implementation
/// This abstraction allows swapping between VecturaKit, ObjectBox, SVDB, etc.
protocol VectorDatabase {
    /// Store a document chunk with its embedding
    func store(chunk: DocumentChunk) async throws
    
    /// Store multiple chunks in batch
    func storeBatch(chunks: [DocumentChunk]) async throws
    
    /// Search for the k most similar chunks to a query embedding
    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk]
    
    /// Delete all chunks for a specific document
    func deleteChunks(forDocument documentId: UUID) async throws
    
    /// Clear the entire database
    func clear() async throws
    
    /// Get total count of stored chunks
    func count() async throws -> Int
    
    /// Enumerate all chunks (used for analytics/visualization)
    /// Implementations should be efficient and may downsample internally if needed.
    func allChunks() async throws -> [DocumentChunk]
}

/// In-memory vector database implementation with performance optimizations
/// For production scale, consider VecturaKit, ObjectBox, or SVDB for persistent storage and HNSW indexing
class InMemoryVectorDatabase: VectorDatabase {
    
    private let embeddingDim: Int
    
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
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks[chunk.id] = chunk
                continuation.resume()
            }
        }
    }
    
    func storeBatch(chunks: [DocumentChunk]) async throws {
        print("💾 [VectorDatabase] Storing \(chunks.count) chunks...")
        let startTime = Date()
        
        // Validate embeddings before storing
        for (index, chunk) in chunks.enumerated() {
            guard chunk.embedding.count == embeddingDim else {
                print("❌ [VectorDatabase] Invalid embedding dimension at index \(index): \(chunk.embedding.count) (expected \(embeddingDim))")
                throw VectorDatabaseError.invalidEmbedding
            }
        }
        
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                for chunk in chunks {
                    self.chunks[chunk.id] = chunk
                    // PERFORMANCE: Pre-compute and cache embedding norm
                    let norm = self.computeNorm(chunk.embedding)
                    self.embeddingNorms[chunk.id] = norm
                }
                // PERFORMANCE: Clear cache when database changes
                self.embeddingCache.removeAll()
                continuation.resume()
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("✅ [VectorDatabase] Stored \(chunks.count) chunks in \(String(format: "%.2f", totalTime))s")
        print("   Total chunks in database: \(self.chunks.count)")
    }
    
    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        let startTime = Date()
        
        // Edge case: Empty database
        guard chunks.count > 0 else {
            print("⚠️  [VectorDatabase] Search on empty database")
            return []
        }
        
        // Edge case: topK larger than database size
        let effectiveTopK = min(topK, chunks.count)
        if effectiveTopK < topK {
            print("⚠️  [VectorDatabase] Requested topK=\(topK) but only \(chunks.count) chunks available")
        }
        
        // Validate query embedding
        guard embedding.count == embeddingDim else {
            print("❌ [VectorDatabase] Invalid query embedding dimension: \(embedding.count) (expected \(embeddingDim))")
            throw VectorDatabaseError.invalidEmbedding
        }
        
        // PERFORMANCE: Check cache first
        if let cachedResult = checkCache(for: embedding) {
            print("⚡️ [VectorDatabase] Cache hit! Returning \(cachedResult.count) cached results")
            return Array(cachedResult.prefix(effectiveTopK))
        }
        
        print("🔍 [VectorDatabase] Searching \(chunks.count) chunks for top \(effectiveTopK)...")
        
        // Snapshot storage and norms off the concurrent queue
        let (allChunksSnapshot, normsSnapshot): ([DocumentChunk], [UUID: Float]) = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: (Array(self.chunks.values), self.embeddingNorms))
            }
        }
        
        // Offload vector math to background actor
        let engine = RAGEngine()
        let results = await engine.computeVectorSearch(
            embedding: embedding,
            chunks: allChunksSnapshot,
            topK: effectiveTopK,
            chunkNorms: normsSnapshot
        )
        
        let searchTime = Date().timeIntervalSince(startTime)
        print("✅ [VectorDatabase] Search complete in \(String(format: "%.0f", searchTime * 1000))ms")
        if let first = results.first {
            print("   Top result: score=\(String(format: "%.3f", first.similarityScore))")
            if results.count > 1, let last = results.last {
                print("   Score range: \(String(format: "%.3f", last.similarityScore)) - \(String(format: "%.3f", first.similarityScore))")
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
        print("🗑️  [VectorDatabase] Deleted \(deletedCount) chunks for document \(documentId)")
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
        
        print("🗑️  [VectorDatabase] Cleared all \(count) chunks")
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
    private let queue = DispatchQueue(label: "com.openintelligence.persistentdb", attributes: .concurrent)
    private let fileManager = FileManager.default
    private let storageURL: URL
    private let embeddingDim: Int
    
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
        
        print("💾 [PersistentVectorDatabase] Storage location: \(storageURL.path)")
        
        // Load existing data
        loadFromDisk()
    }
    
    // MARK: - Initialization (Designated)
    
    init(storageURL: URL, dimension: Int) {
        self.storageURL = storageURL
        self.embeddingDim = dimension
        print("💾 [PersistentVectorDatabase] Storage location: \(storageURL.path) (dim=\(dimension))")
        // Load existing data
        loadFromDisk()
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            print("ℹ️  [PersistentVectorDatabase] No existing database found - starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let loadedChunks = try decoder.decode([DocumentChunk].self, from: data)
            
            // Convert array to dictionary for fast lookup
            self.chunks = Dictionary(uniqueKeysWithValues: loadedChunks.map { ($0.id, $0) })
            
            print("✅ [PersistentVectorDatabase] Loaded \(chunks.count) chunks from disk")
        } catch {
            print("❌ [PersistentVectorDatabase] Failed to load database: \(error.localizedDescription)")
            print("   Starting with empty database")
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
                    print("💾 [PersistentVectorDatabase] Saved \(chunksArray.count) chunks (\(String(format: "%.2f", sizeMB)) MB)")
                    
                } catch {
                    print("❌ [PersistentVectorDatabase] Failed to save: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - VectorDatabase Protocol
    
    func store(chunk: DocumentChunk) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks[chunk.id] = chunk
                continuation.resume()
            }
        }
        await saveToDisk()
    }
    
    func storeBatch(chunks: [DocumentChunk]) async throws {
        print("💾 [PersistentVectorDatabase] Storing \(chunks.count) chunks...")
        let startTime = Date()
        
        // Validate embeddings before storing
        for (index, chunk) in chunks.enumerated() {
            guard chunk.embedding.count == embeddingDim else {
                print("❌ [PersistentVectorDatabase] Invalid embedding dimension at index \(index): \(chunk.embedding.count)")
                throw VectorDatabaseError.invalidEmbedding
            }
        }
        
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                for chunk in chunks {
                    self.chunks[chunk.id] = chunk
                }
                continuation.resume()
            }
        }
        
        await saveToDisk()
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("✅ [PersistentVectorDatabase] Stored \(chunks.count) chunks in \(String(format: "%.2f", totalTime))s")
        print("   Total chunks in database: \(self.chunks.count)")
    }
    
    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        let startTime = Date()
        
        // Validate query embedding
        guard embedding.count == embeddingDim else {
            print("❌ [PersistentVectorDatabase] Invalid query embedding dimension: \(embedding.count)")
            throw VectorDatabaseError.invalidQueryEmbedding
        }
        
        let allChunks = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.chunks.values))
            }
        }
        
        guard !allChunks.isEmpty else {
            print("⚠️  [PersistentVectorDatabase] Database is empty")
            return []
        }
        
        // Offload vector math to background actor
        let engine = RAGEngine()
        let topChunks = await engine.computeVectorSearch(
            embedding: embedding,
            chunks: allChunks,
            topK: topK,
            chunkNorms: nil
        )
        
        let searchTime = Date().timeIntervalSince(startTime)
        print("🔍 [PersistentVectorDatabase] Search complete in \(String(format: "%.2f", searchTime))s")
        print("   Searched \(allChunks.count) chunks, returned top \(topChunks.count)")
        if let topScore = topChunks.first?.similarityScore {
            print("   Best match: \(String(format: "%.3f", topScore)) similarity")
        }
        
        return Array(topChunks)
    }
    
    func deleteChunks(forDocument documentId: UUID) async throws {
        print("🗑️  [PersistentVectorDatabase] Deleting chunks for document: \(documentId)")
        
        let deletedCount = await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let beforeCount = self.chunks.count
                self.chunks = self.chunks.filter { $0.value.documentId != documentId }
                let afterCount = self.chunks.count
                continuation.resume(returning: beforeCount - afterCount)
            }
        }
        
        await saveToDisk()
        
        print("✅ [PersistentVectorDatabase] Deleted \(deletedCount) chunks")
    }
    
    func clear() async throws {
        print("�️  [PersistentVectorDatabase] Clearing entire database...")
        
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.chunks.removeAll()
                continuation.resume()
            }
        }
        
        // Delete the file
        try? fileManager.removeItem(at: storageURL)
        
        print("✅ [PersistentVectorDatabase] Database cleared")
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
    
    // MARK: - Helper Methods
    
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

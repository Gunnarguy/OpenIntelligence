//
//  BNNSVectorDatabase.swift
//  OpenIntelligence
//
//  The "Native Intelligence" Vault.
//  Uses Apple's Accelerate (vDSP/BNNS) for hardware-accelerated brute-force vector search.
//  Performance: O(N) scan but extremely fast due to AMX/Neural Engine utilization.
//  Optimized for datasets < 100k chunks.
//  Now with Persistence support (JSON).
//

import Accelerate
import Foundation

/// ANE-friendly brute-force vector store using Accelerate.
/// Uses actor isolation for async safety in Swift 6.
actor BNNSVectorDatabase: VectorDatabase {
    // MARK: - Properties

    let dimension: Int
    private let storageURL: URL? // Optional for in-memory only use cases

    // Contiguous memory storage for max performance
    // We store embeddings in a flat array: [e1_0, e1_1... e2_0...]
    // Chunk metadata is stored in a parallel array
    private var flatEmbeddings: [Float] = []
    private var chunks: [DocumentChunk] = []

    // MARK: - Init

    init(dimension: Int = 512, storageURL: URL? = nil) {
        self.dimension = dimension
        self.storageURL = storageURL
        
        if let url = storageURL {
            Task {
                await self.loadFromDisk(url: url)
            }
        }
    }

    // MARK: - Persistence

    private func loadFromDisk(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let loadedChunks = try decoder.decode([DocumentChunk].self, from: data)
            
            // Filter mismatched dimensions
            let validChunks = loadedChunks.filter { $0.embedding.count == dimension }
            if validChunks.count != loadedChunks.count {
                Log.warning("[BNNSVectorDatabase] Skipped \(loadedChunks.count - validChunks.count) chunks due to dimension mismatch", category: .vectorDB)
            }
            
            self.chunks = validChunks
            
            // Rebuild flat buffer
            self.flatEmbeddings.reserveCapacity(validChunks.count * dimension)
            for chunk in validChunks {
                self.flatEmbeddings.append(contentsOf: chunk.embedding)
            }
            
            Log.info("[BNNSVectorDatabase] Loaded \(validChunks.count) chunks from disk (Accelerate-ready)", category: .vectorDB)
        } catch {
            Log.error("[BNNSVectorDatabase] Failed to load: \(error)", category: .vectorDB)
        }
    }
    
    private func saveToDisk() throws {
        guard let url = storageURL else { return }
        let encoder = JSONEncoder()
        // Optional: outputFormatting = .prettyPrinted if debugging, but compact is faster
        let data = try encoder.encode(chunks)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - VectorDatabase Protocol

    func store(chunk: DocumentChunk) async throws {
        // Ensure dimension matches
        guard chunk.embedding.count == dimension else {
            Log.error("[BNNSVectorDatabase] Dimension mismatch: Got \(chunk.embedding.count), expected \(dimension)", category: .vectorDB)
            throw VectorDatabaseError.invalidEmbedding
        }

        // Append to storage
        flatEmbeddings.append(contentsOf: chunk.embedding)
        chunks.append(chunk)
        
        try saveToDisk()
    }

    func storeBatch(chunks inputChunks: [DocumentChunk]) async throws {
        let validChunks = inputChunks.filter { $0.embedding.count == dimension }
        if validChunks.count != inputChunks.count {
            Log.warning("[BNNSVectorDatabase] Skipped \(inputChunks.count - validChunks.count) chunks due to dimension mismatch", category: .vectorDB)
        }

        for chunk in validChunks {
            flatEmbeddings.append(contentsOf: chunk.embedding)
            chunks.append(chunk)
        }
        Log.debug("[BNNSVectorDatabase] Batch stored \(validChunks.count) chunks", category: .vectorDB)
        
        try saveToDisk()
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        guard embedding.count == dimension else {
            throw VectorDatabaseError.invalidEmbedding
        }
        let count = chunks.count
        if count == 0 { return [] }
        var scores = [Float](repeating: 0.0, count: count)

        // Hardware-accelerated Matrix Multiplication
        // Scores = Embeddings * Query
        flatEmbeddings.withUnsafeBufferPointer { embPtr in
            embedding.withUnsafeBufferPointer { queryPtr in
                scores.withUnsafeMutableBufferPointer { outPtr in
                    // vDSP_mmul: C = A (m x n) * B (n x p)
                    // A = Embeddings (Count x Dimension)
                    // B = Query (Dimension x 1)
                    // C = Scores (Count x 1)
                    vDSP_mmul(embPtr.baseAddress!, 1,
                              queryPtr.baseAddress!, 1,
                              outPtr.baseAddress!, 1,
                              vDSP_Length(count), 1, vDSP_Length(dimension))
                }
            }
        }

        // Find top K indices
        // For small K, a partial sort or heap is better, but full sort is simple for <10k
        let sortedIndices = (0 ..< count).sorted { scores[$0] > scores[$1] }
        let topIndices = sortedIndices.prefix(topK)

        return topIndices.map { idx in
            RetrievedChunk(
                chunk: chunks[idx],
                similarityScore: scores[idx],
                rank: idx + 1
            )
        }
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        // Reconstruct arrays (O(N) memory move, but infrequent)
        var newChunks: [DocumentChunk] = []
        var newFlat: [Float] = []
        newChunks.reserveCapacity(chunks.count)
        newFlat.reserveCapacity(flatEmbeddings.count)

        for i in 0 ..< chunks.count {
            if chunks[i].documentId != documentId {
                newChunks.append(chunks[i])
                let start = i * dimension
                newFlat.append(contentsOf: flatEmbeddings[start ..< (start + dimension)])
            }
        }

        chunks = newChunks
        flatEmbeddings = newFlat
        
        try saveToDisk()
    }

    func clear() async throws {
        chunks.removeAll()
        flatEmbeddings.removeAll()
        try saveToDisk()
    }

    func count() async throws -> Int {
        return chunks.count
    }

    func allChunks() async throws -> [DocumentChunk] {
        return chunks
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        if let idx = chunks.firstIndex(where: { $0.id == chunk.id }) {
            // Overwrite metadata
            chunks[idx] = chunk
            // Overwrite embedding
            let start = idx * dimension
            for i in 0 ..< dimension {
                flatEmbeddings[start + i] = chunk.embedding[i]
            }
        } else {
            // Treat as new
            try await store(chunk: chunk)
            return // store() saves, so we return early
        }
        
        try saveToDisk()
    }

    func exists(chunkId: UUID) async -> Bool {
        return chunks.contains(where: { $0.id == chunkId })
    }

    func statistics() async -> VectorDatabaseStats {
        let bytes = flatEmbeddings.count * MemoryLayout<Float>.size
        let uniqueDocs = Set(chunks.map { $0.documentId }).count
        return VectorDatabaseStats(
            chunkCount: chunks.count,
            dimension: dimension,
            uniqueDocuments: uniqueDocs,
            estimatedMemoryBytes: bytes,
            backend: "BNNS/Accelerate"
        )
    }
}
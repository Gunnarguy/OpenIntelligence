//
//  BNNSVectorDatabase.swift
//  OpenIntelligence
//
//  The "Native Intelligence" Vault — Production Vector Store.
//
//  ## Architecture (Feb 2026)
//
//  Memory-mapped embeddings with Accelerate/Metal search.
//  Inspired by FAISS, Annoy, and Qdrant — production vector databases
//  never load embeddings into heap. They mmap the index file and let
//  the OS manage paging.
//
//  **Memory Layout:**
//  - `mappedVectors: Data` — memory-mapped via `.alwaysMapped`. The OS pages in
//    only the 16 KB pages touched during search. Under memory pressure, pages are
//    evicted automatically. **0 bytes heap** for 73 MB of embeddings.
//  - `embeddingNorms: [Float]` — 200 KB for 50K chunks. Kept in RAM because
//    every search touches every norm exactly once (random access).
//  - `chunks: [DocumentChunk]` — metadata only, embedding:[] stripped.
//
//  **Persistence (3 files, binary format):**
//  - `_meta.json` — chunk metadata (content, IDs, etc.) ~5-10 MB
//  - `_vectors.bin` — raw Float32 contiguous, memory-mapped on load
//  - `_norms.bin` — pre-computed L2 norms, raw Float32
//
//  **Search:**
//  - GPU path (≥1000 chunks): Metal compute shader via UnsafeBufferPointer
//    from mmap for near-zero-copy GPU access.
//  - CPU path (<1000 chunks): vDSP_dotpr directly on mmap'd pointer.
//  - Partial heap sort for top-K: O(n log k) vs O(n log n).
//
//  **Peak Memory:**
//  - Load: ~10 MB (metadata JSON) + 0 MB (mmap) + 200 KB (norms) = ~10 MB
//  - Search: ~200 KB (scores array) + GPU buffers (managed by Metal)
//  - Previous: ~650 MB peak (JSON decode), then ~83 MB steady (binary [Float])
//
//  See also:
//  - https://developer.apple.com/documentation/accelerate/vdsp
//  - https://developer.apple.com/documentation/accelerate/bnns
//  - https://developer.apple.com/documentation/foundation/data/readingoptions/alwaysmapped
//

import Accelerate
import Foundation
import Metal

/// Production vector store using memory-mapped embeddings + Accelerate/Metal GPU.
/// Actor-isolated for Swift 6 concurrency safety.
actor BNNSVectorDatabase: VectorDatabase {
    // MARK: - Properties

    let dimension: Int
    nonisolated let persistenceKind: VectorDBKind
    private let storageURL: URL?

    /// GPU compute service (lazy)
    private var gpuCompute: GPUComputeService?

    // MARK: Memory-Mapped Vectors (0 bytes heap)

    /// Memory-mapped embedding data. The OS pages in 16 KB chunks on demand,
    /// evicts under pressure. For 50K × 384 × 4 = 73 MB, heap usage is 0.
    private var mappedVectors: Data?

    /// In-memory write buffer for new embeddings during ingestion.
    /// Flushed to disk (and re-mmap'd) on persist()/saveToDisk().
    private var pendingEmbeddings: [Float] = []

    /// Number of chunks whose embeddings are persisted in the mmap file
    private var persistedChunkCount: Int = 0

    // MARK: Metadata + Norms (lightweight)

    /// Chunk metadata WITHOUT embeddings. ~5-10 MB for 50K chunks.
    private var chunks: [DocumentChunk] = []

    /// Pre-computed L2 norms. 200 KB for 50K chunks — acceptable in RAM.
    private var embeddingNorms: [Float] = []

    /// Dirty flag for deferred persistence
    private var isDirty = false

    /// Load-completion task — all public methods await this before accessing data.
    /// Prevents returning empty results while loadFromDisk is in progress.
    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: - Init

    init(dimension: Int = 384, storageURL: URL? = nil) {
        self.dimension = dimension
        self.storageURL = storageURL
        persistenceKind = storageURL == nil ? .inMemory : .persistentJSON

        if let url = storageURL {
            loadTask = Task {
                await self.loadFromDisk(url: url)
            }
        }
    }

    /// Wait for initial load to complete before serving queries
    private func awaitLoad() async {
        await loadTask?.value
        loadTask = nil
    }

    /// Lazily get GPU compute service
    private func getGPUCompute() async -> GPUComputeService {
        if let compute = gpuCompute { return compute }
        let compute = await MainActor.run { GPUComputeService.shared }
        gpuCompute = compute
        return compute
    }

    // MARK: - Persistence (Binary + mmap)

    /// Derive binary file URLs from the legacy JSON storage URL
    private func binaryURLs(from url: URL) -> (meta: URL, vectors: URL, norms: URL) {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        return (
            meta: dir.appendingPathComponent("\(base)_meta.json"),
            vectors: dir.appendingPathComponent("\(base)_vectors.bin"),
            norms: dir.appendingPathComponent("\(base)_norms.bin")
        )
    }

    /// File URLs for cleanup (used by VectorStoreRouter)
    static func binaryFileURLs(from legacyURL: URL) -> [URL] {
        let dir = legacyURL.deletingLastPathComponent()
        let base = legacyURL.deletingPathExtension().lastPathComponent
        return [
            dir.appendingPathComponent("\(base)_meta.json"),
            dir.appendingPathComponent("\(base)_vectors.bin"),
            dir.appendingPathComponent("\(base)_norms.bin"),
            legacyURL
        ]
    }

    // MARK: Load

    private func loadFromDisk(url: URL) {
        let fm = FileManager.default
        let bin = binaryURLs(from: url)

        func resetLoadedState() {
            self.chunks.removeAll()
            self.embeddingNorms.removeAll()
            self.pendingEmbeddings.removeAll(keepingCapacity: false)
            self.mappedVectors = nil
            self.persistedChunkCount = 0
        }

        // === BINARY FORMAT: mmap vectors, load lightweight metadata ===
        if fm.fileExists(atPath: bin.meta.path), fm.fileExists(atPath: bin.vectors.path) {
            do {
                // 1. Chunk metadata — small JSON, embedding:[] (~5-10 MB)
                let metaData = try Data(contentsOf: bin.meta)
                let decodedChunks = try JSONDecoder().decode([DocumentChunk].self, from: metaData)

                // 2. Memory-map vectors — 0 bytes heap, OS pages on demand
                let expectedBytes = decodedChunks.count * dimension * MemoryLayout<Float>.size
                var mapped = try Data(contentsOf: bin.vectors, options: .alwaysMapped)
                if mapped.count != expectedBytes {
                    if expectedBytes > 0,
                       mapped.count > expectedBytes,
                       mapped.count % expectedBytes == 0 {
                        Log.warning(
                            "[BNNS] Repairing oversized vector file: \(mapped.count) -> \(expectedBytes)",
                            category: .vectorDB
                        )
                        let repairedData = Data(mapped.prefix(expectedBytes))
                        try repairedData.write(to: bin.vectors, options: .atomic)
                        mapped = try Data(contentsOf: bin.vectors, options: .alwaysMapped)
                    }

                    guard mapped.count == expectedBytes else {
                        Log.error("[BNNS] Vector file size mismatch: \(mapped.count) vs expected \(expectedBytes)", category: .vectorDB)
                        resetLoadedState()
                        return
                    }
                }

                self.chunks = decodedChunks
                self.mappedVectors = mapped
                self.persistedChunkCount = decodedChunks.count
                self.pendingEmbeddings.removeAll(keepingCapacity: false)

                // 3. Norms — 200 KB in RAM (acceptable)
                if let normData = try? Data(contentsOf: bin.norms),
                   normData.count == decodedChunks.count * MemoryLayout<Float>.size {
                    self.embeddingNorms = [Float](unsafeUninitializedCapacity: decodedChunks.count) { buf, count in
                        _ = normData.copyBytes(to: buf)
                        count = decodedChunks.count
                    }
                } else {
                    recomputeNorms()
                }

                Log.info("[BNNS] Loaded \(decodedChunks.count) chunks (mmap'd \(mapped.count / 1_048_576)MB vectors, 0 bytes heap)", category: .vectorDB)
                return
            } catch {
                resetLoadedState()
                Log.error("[BNNS] Binary load failed: \(error). Trying legacy.", category: .vectorDB)
            }
        }

        // === LEGACY: JSON with embedded floats (one-time migration) ===
        guard fm.fileExists(atPath: url.path) else { return }

        do {
            Log.warning("[BNNS] Migrating legacy JSON → binary + mmap (one-time)", category: .vectorDB)
            let data = try Data(contentsOf: url)
            let loadedChunks = try JSONDecoder().decode([DocumentChunk].self, from: data)

            let validChunks = loadedChunks.filter { $0.embedding.count == dimension }
            if validChunks.count != loadedChunks.count {
                Log.warning("[BNNS] Skipped \(loadedChunks.count - validChunks.count) chunks (dim mismatch)", category: .vectorDB)
            }

            // Write vectors directly to binary file — avoid holding all in memory
            let vectorsBin = bin.vectors
            fm.createFile(atPath: vectorsBin.path, contents: nil)
            let handle = try FileHandle(forWritingTo: vectorsBin)
            var norms: [Float] = []
            norms.reserveCapacity(validChunks.count)

            for chunk in validChunks {
                let emb = chunk.embedding
                emb.withUnsafeBytes { handle.write(Data($0)) }
                norms.append(sqrt(vDSP.sumOfSquares(emb)))
            }
            try handle.close()

            self.chunks = validChunks.map { chunk in
                DocumentChunk(
                    id: chunk.id, documentId: chunk.documentId,
                    content: chunk.content, parentContent: chunk.parentContent,
                    contextualPrefix: chunk.contextualPrefix,
                    embedding: [], metadata: chunk.metadata
                )
            }
            self.embeddingNorms = norms
            self.persistedChunkCount = chunks.count

            // Save metadata + norms, mmap vectors
            let metaEnc = try JSONEncoder().encode(chunks)
            try metaEnc.write(to: bin.meta, options: .atomic)
            let normData = norms.withUnsafeBytes { Data($0) }
            try normData.write(to: bin.norms, options: .atomic)
            self.mappedVectors = try Data(contentsOf: vectorsBin, options: .alwaysMapped)

            // Delete legacy JSON
            try? fm.removeItem(at: url)
            Log.info("[BNNS] Migration complete: \(validChunks.count) chunks → binary + mmap", category: .vectorDB)
        } catch {
            Log.error("[BNNS] Legacy load failed: \(error)", category: .vectorDB)
        }
    }

    /// Recompute L2 norms from mmap'd vectors
    private func recomputeNorms() {
        self.embeddingNorms = (0..<chunks.count).map { computeNormFromMmap(index: $0) }
    }

    /// Compute norm for a single vector at given index from mmap'd data
    private func computeNormFromMmap(index: Int) -> Float {
        guard let mapped = mappedVectors else { return 1.0 }
        let byteOffset = index * dimension * MemoryLayout<Float>.size
        let byteCount = dimension * MemoryLayout<Float>.size
        guard byteOffset + byteCount <= mapped.count else { return 1.0 }

        return mapped.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.baseAddress!.advanced(by: byteOffset)
                .assumingMemoryBound(to: Float.self)
            var sumSq: Float = 0
            vDSP_svesq(ptr, 1, &sumSq, vDSP_Length(dimension))
            return sqrt(sumSq)
        }
    }

    // MARK: Save

    private func saveToDisk() throws {
        guard let url = storageURL else { return }
        let bin = binaryURLs(from: url)

        // 1. Metadata JSON (chunks have embedding:[], lightweight)
        let metaData = try JSONEncoder().encode(chunks)
        try metaData.write(to: bin.meta, options: .atomic)

        // 2. Append pending embeddings to vectors file and re-mmap
        if !pendingEmbeddings.isEmpty {
            let fm = FileManager.default
            if !fm.fileExists(atPath: bin.vectors.path) {
                fm.createFile(atPath: bin.vectors.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: bin.vectors)
            handle.seekToEndOfFile()
            pendingEmbeddings.withUnsafeBytes { handle.write(Data($0)) }
            try handle.close()

            pendingEmbeddings.removeAll(keepingCapacity: false)
            self.mappedVectors = try Data(contentsOf: bin.vectors, options: .alwaysMapped)
            self.persistedChunkCount = chunks.count
        }

        // 3. Norms binary
        let normData = embeddingNorms.withUnsafeBytes { Data($0) }
        try normData.write(to: bin.norms, options: .atomic)

        if url.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
           !WorkspaceSyncService.isSyncWriteInProgress {
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
        }
    }

    // MARK: - Silicon-Native Vector Math

    @inline(__always)
    private func computeNormAccelerated(_ vector: [Float]) -> Float {
        sqrt(vDSP.sumOfSquares(vector))
    }

    /// Cosine similarity reading directly from mmap'd data — zero heap allocation
    @inline(__always)
    private func cosineSimilarityMmap(_ queryEmbedding: [Float], queryNorm: Float, chunkIndex: Int) -> Float {
        let chunkNorm = embeddingNorms[chunkIndex]
        guard queryNorm > 1e-9, chunkNorm > 1e-9 else { return 0 }

        if chunkIndex < persistedChunkCount, let mapped = mappedVectors {
            let byteOffset = chunkIndex * dimension * MemoryLayout<Float>.size
            return mapped.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.baseAddress!.advanced(by: byteOffset)
                    .assumingMemoryBound(to: Float.self)
                var dotProduct: Float = 0
                queryEmbedding.withUnsafeBufferPointer { queryPtr in
                    vDSP_dotpr(ptr, 1, queryPtr.baseAddress!, 1, &dotProduct, vDSP_Length(dimension))
                }
                return dotProduct / (queryNorm * chunkNorm)
            }
        } else {
            // Pending (not yet flushed)
            let pendingIdx = chunkIndex - persistedChunkCount
            let start = pendingIdx * dimension
            var dotProduct: Float = 0
            pendingEmbeddings.withUnsafeBufferPointer { pendPtr in
                queryEmbedding.withUnsafeBufferPointer { queryPtr in
                    vDSP_dotpr(pendPtr.baseAddress! + start, 1, queryPtr.baseAddress!, 1, &dotProduct, vDSP_Length(dimension))
                }
            }
            return dotProduct / (queryNorm * chunkNorm)
        }
    }

    /// Access ALL vector data (mmap + pending) via a single contiguous pointer.
    /// Fast path (most common): pure mmap, zero copy.
    /// Mixed path (during ingestion before persist): materializes temporary combined buffer.
    private func withAllVectorBytes<R>(_ body: (UnsafeRawBufferPointer, Int) -> R) -> R {
        let totalCount = chunks.count

        if pendingEmbeddings.isEmpty, let mapped = mappedVectors {
            // FAST PATH: everything is mmap'd — true zero copy
            return mapped.withUnsafeBytes { body($0, totalCount) }
        } else if persistedChunkCount == 0 {
            // All in pending buffer (fresh database)
            return pendingEmbeddings.withUnsafeBytes { body($0, totalCount) }
        } else {
            // Mixed: combine mmap + pending (only during active ingestion)
            let totalFloats = totalCount * dimension
            let combined = [Float](unsafeUninitializedCapacity: totalFloats) { buf, count in
                count = totalFloats
                if let mapped = mappedVectors {
                    mapped.withUnsafeBytes { rawBuf in
                        let src = rawBuf.baseAddress!.assumingMemoryBound(to: Float.self)
                        buf.baseAddress!.update(from: src, count: persistedChunkCount * dimension)
                    }
                }
                if !pendingEmbeddings.isEmpty {
                    let offset = persistedChunkCount * dimension
                    pendingEmbeddings.withUnsafeBufferPointer { pendBuf in
                        buf.baseAddress!.advanced(by: offset)
                            .update(from: pendBuf.baseAddress!, count: pendBuf.count)
                    }
                }
            }
            return combined.withUnsafeBytes { body($0, totalCount) }
        }
    }

    // MARK: - VectorDatabase Protocol

    func store(chunk: DocumentChunk) async throws {
        await awaitLoad()
        guard chunk.embedding.count == dimension else {
            Log.error("[BNNS] Dimension mismatch: \(chunk.embedding.count) vs \(dimension)", category: .vectorDB)
            throw VectorDatabaseError.invalidEmbedding
        }

        pendingEmbeddings.append(contentsOf: chunk.embedding)
        let stripped = DocumentChunk(
            id: chunk.id, documentId: chunk.documentId,
            content: chunk.content, parentContent: chunk.parentContent,
            contextualPrefix: chunk.contextualPrefix,
            embedding: [], metadata: chunk.metadata
        )
        chunks.append(stripped)
        embeddingNorms.append(computeNormAccelerated(chunk.embedding))

        try saveToDisk()
    }

    func storeBatch(chunks inputChunks: [DocumentChunk]) async throws {
        await awaitLoad()
        let validChunks = inputChunks.filter { $0.embedding.count == dimension }
        if validChunks.count != inputChunks.count {
            Log.warning("[BNNS] Skipped \(inputChunks.count - validChunks.count) chunks (dim mismatch)", category: .vectorDB)
        }

        pendingEmbeddings.reserveCapacity(pendingEmbeddings.count + validChunks.count * dimension)
        embeddingNorms.reserveCapacity(embeddingNorms.count + validChunks.count)

        for chunk in validChunks {
            pendingEmbeddings.append(contentsOf: chunk.embedding)
            let stripped = DocumentChunk(
                id: chunk.id, documentId: chunk.documentId,
                content: chunk.content, parentContent: chunk.parentContent,
                contextualPrefix: chunk.contextualPrefix,
                embedding: [], metadata: chunk.metadata
            )
            chunks.append(stripped)
            embeddingNorms.append(computeNormAccelerated(chunk.embedding))
        }

        isDirty = true
        Log.debug("[BNNS] Batch buffered \(validChunks.count) chunks (persist deferred)", category: .vectorDB)
    }

    /// Persist pending data to disk + re-mmap
    func persist() async throws {
        await awaitLoad()
        guard isDirty || !pendingEmbeddings.isEmpty else { return }
        try saveToDisk()
        isDirty = false
        Log.debug("[BNNS] Persisted \(chunks.count) chunks (\(persistedChunkCount) mmap'd)", category: .vectorDB)
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        await awaitLoad()
        guard embedding.count == dimension else {
            throw VectorDatabaseError.invalidEmbedding
        }
        let count = chunks.count
        if count == 0 { return [] }

        let queryNorm = computeNormAccelerated(embedding)
        guard queryNorm > 1e-9 else {
            Log.warning("[BNNS] Near-zero query norm", category: .vectorDB)
            return []
        }

        var scores: [Float]
        let gpuThreshold = 1000
        let gpu = await getGPUCompute()

        if count >= gpuThreshold, gpu.isGPUAvailable {
            // GPU: read from mmap via withAllVectorBytes — zero copy when pure mmap
            scores = withAllVectorBytes { rawBuf, docCount in
                let floatBuf = UnsafeBufferPointer(
                    start: rawBuf.baseAddress!.assumingMemoryBound(to: Float.self),
                    count: docCount * dimension
                )
                return gpu.batchCosineSimilarityFlatBuffer(
                    query: embedding,
                    flatDocuments: floatBuf,
                    documentCount: docCount,
                    dimension: dimension
                )
            }
            Log.debug("[BNNS] GPU mmap search: \(count) vectors", category: .vectorDB)
        } else {
            // CPU: vDSP on mmap pointers
            scores = [Float](repeating: 0, count: count)
            let batchThreshold = await DeviceCapabilityService.shared.batchMatrixMultiplyThreshold

            if count >= batchThreshold {
                // vDSP_mmul computes raw dot products — must normalize to cosine similarity.
                // Our embeddings are L2-normalized by CoreMLSentenceEmbeddingProvider,
                // but we normalize here defensively for correctness regardless of provider.
                withAllVectorBytes { rawBuf, docCount in
                    let embPtr = rawBuf.baseAddress!.assumingMemoryBound(to: Float.self)
                    embedding.withUnsafeBufferPointer { queryPtr in
                        scores.withUnsafeMutableBufferPointer { outPtr in
                            vDSP_mmul(embPtr, 1, queryPtr.baseAddress!, 1,
                                      outPtr.baseAddress!, 1,
                                      vDSP_Length(docCount), 1, vDSP_Length(dimension))
                        }
                    }
                    // Post-normalize: dot_product / (queryNorm * docNorm) = cosine similarity
                    for i in 0..<docCount {
                        let docNorm = embeddingNorms[i]
                        if docNorm > 1e-9 {
                            scores[i] /= (queryNorm * docNorm)
                        } else {
                            scores[i] = 0
                        }
                    }
                }
            } else {
                for i in 0..<count {
                    scores[i] = cosineSimilarityMmap(embedding, queryNorm: queryNorm, chunkIndex: i)
                }
            }
        }

        // Top-K via partial heap sort
        let effectiveTopK = min(topK, count)
        let topIndices: [Int]

        if effectiveTopK <= 20, count > 100 {
            topIndices = partialSort(scores: scores, k: effectiveTopK)
        } else {
            topIndices = Array((0..<count).sorted { scores[$0] > scores[$1] }.prefix(effectiveTopK))
        }

        return topIndices.enumerated().map { rank, idx in
            RetrievedChunk(chunk: chunks[idx], similarityScore: scores[idx], rank: rank + 1)
        }
    }

    /// Partial sort using min-heap — O(n log k) for top-K
    private func partialSort(scores: [Float], k: Int) -> [Int] {
        guard k > 0, !scores.isEmpty else { return [] }
        var heap: [(index: Int, score: Float)] = []
        heap.reserveCapacity(k + 1)

        for i in 0..<scores.count {
            let score = scores[i]
            if heap.count < k {
                heap.append((i, score))
                var j = heap.count - 1
                while j > 0 {
                    let parent = (j - 1) / 2
                    if heap[j].score < heap[parent].score {
                        heap.swapAt(j, parent)
                        j = parent
                    } else { break }
                }
            } else if score > heap[0].score {
                heap[0] = (i, score)
                var j = 0
                while true {
                    let left = 2 * j + 1
                    let right = 2 * j + 2
                    var smallest = j
                    if left < heap.count, heap[left].score < heap[smallest].score { smallest = left }
                    if right < heap.count, heap[right].score < heap[smallest].score { smallest = right }
                    if smallest == j { break }
                    heap.swapAt(j, smallest)
                    j = smallest
                }
            }
        }
        return heap.sorted { $0.score > $1.score }.map(\.index)
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        await awaitLoad()
        var newChunks: [DocumentChunk] = []
        var newNorms: [Float] = []
        var keepIndices: [Int] = []
        newChunks.reserveCapacity(chunks.count)
        newNorms.reserveCapacity(embeddingNorms.count)

        for i in 0..<chunks.count {
            if chunks[i].documentId != documentId {
                newChunks.append(chunks[i])
                newNorms.append(embeddingNorms[i])
                keepIndices.append(i)
            }
        }

        let deletedCount = chunks.count - newChunks.count

        // Rebuild vectors file with kept indices only
        if let url = storageURL {
            let bin = binaryURLs(from: url)
            let fm = FileManager.default
            let tempURL = bin.vectors.appendingPathExtension("tmp")
            fm.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            let bytesPerVector = dimension * MemoryLayout<Float>.size

            for idx in keepIndices {
                if idx < persistedChunkCount, let mapped = mappedVectors {
                    let byteOffset = idx * bytesPerVector
                    guard byteOffset + bytesPerVector <= mapped.count else { continue }
                    mapped.withUnsafeBytes { rawBuf in
                        let ptr = rawBuf.baseAddress!.advanced(by: byteOffset)
                        handle.write(Data(bytes: ptr, count: bytesPerVector))
                    }
                } else {
                    let pendingIdx = idx - persistedChunkCount
                    let start = pendingIdx * dimension
                    let end = start + dimension
                    guard end <= pendingEmbeddings.count else { continue }
                    pendingEmbeddings[start..<end].withUnsafeBytes { handle.write(Data($0)) }
                }
            }
            try handle.close()

            try? fm.removeItem(at: bin.vectors)
            try fm.moveItem(at: tempURL, to: bin.vectors)
            self.mappedVectors = try Data(contentsOf: bin.vectors, options: .alwaysMapped)
        }

        chunks = newChunks
        embeddingNorms = newNorms
        pendingEmbeddings.removeAll(keepingCapacity: false)
        persistedChunkCount = chunks.count

        Log.debug("[BNNS] Deleted \(deletedCount) chunks for document \(documentId)", category: .vectorDB)
        try saveToDisk()
    }

    func clear() async throws {
        await awaitLoad()
        chunks.removeAll()
        embeddingNorms.removeAll()
        pendingEmbeddings.removeAll()
        mappedVectors = nil
        persistedChunkCount = 0

        if let url = storageURL {
            let bin = binaryURLs(from: url)
            let fm = FileManager.default
            try? fm.removeItem(at: bin.meta)
            try? fm.removeItem(at: bin.vectors)
            try? fm.removeItem(at: bin.norms)

            if url.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
               !WorkspaceSyncService.isSyncWriteInProgress {
                NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
            }
        }
    }

    func count() async throws -> Int {
        await awaitLoad()
        return chunks.count
    }

    func allChunks() async throws -> [DocumentChunk] {
        await awaitLoad()
        return chunks
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        await awaitLoad()
        guard let idx = chunks.firstIndex(where: { $0.id == chunk.id }) else {
            try await store(chunk: chunk)
            return
        }

        chunks[idx] = DocumentChunk(
            id: chunk.id, documentId: chunk.documentId,
            content: chunk.content, parentContent: chunk.parentContent,
            contextualPrefix: chunk.contextualPrefix,
            embedding: [], metadata: chunk.metadata
        )
        embeddingNorms[idx] = computeNormAccelerated(chunk.embedding)

        // Rewrite vectors file with updated embedding at idx
        if let url = storageURL {
            let bin = binaryURLs(from: url)
            let fm = FileManager.default
            let tempURL = bin.vectors.appendingPathExtension("tmp")
            fm.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            let bytesPerVector = dimension * MemoryLayout<Float>.size

            for i in 0..<chunks.count {
                if i == idx {
                    chunk.embedding.withUnsafeBytes { handle.write(Data($0)) }
                } else if i < persistedChunkCount, let mapped = mappedVectors {
                    let byteOffset = i * bytesPerVector
                    guard byteOffset + bytesPerVector <= mapped.count else { continue }
                    mapped.withUnsafeBytes { rawBuf in
                        let ptr = rawBuf.baseAddress!.advanced(by: byteOffset)
                        handle.write(Data(bytes: ptr, count: bytesPerVector))
                    }
                } else {
                    let pendingIdx = i - persistedChunkCount
                    let start = pendingIdx * dimension
                    let end = start + dimension
                    guard end <= pendingEmbeddings.count else { continue }
                    pendingEmbeddings[start..<end].withUnsafeBytes { handle.write(Data($0)) }
                }
            }
            try handle.close()

            try? fm.removeItem(at: bin.vectors)
            try fm.moveItem(at: tempURL, to: bin.vectors)
            self.mappedVectors = try Data(contentsOf: bin.vectors, options: .alwaysMapped)
            self.pendingEmbeddings.removeAll(keepingCapacity: false)
            self.persistedChunkCount = chunks.count
        }

        try saveToDisk()
    }

    func exists(chunkId: UUID) async -> Bool {
        chunks.contains { $0.id == chunkId }
    }

    /// Retrieve embeddings for Gate E Semantic Grounding
    func getEmbeddings(forChunkIDs ids: [UUID]) async -> [[Float]] {
        ids.map { id in
            guard let idx = chunks.firstIndex(where: { $0.id == id }) else { return [Float]() }
            return readEmbedding(at: idx)
        }
    }

    func getEmbeddings(forIndices indices: [Int]) async -> [[Float]] {
        indices.map { readEmbedding(at: $0) }
    }

    /// Read embedding from mmap or pending — O(d) copy, only for the chunks needed
    private func readEmbedding(at index: Int) -> [Float] {
        guard index >= 0, index < chunks.count else { return [] }

        if index < persistedChunkCount {
            guard let mapped = mappedVectors else { return [] }
            let byteOffset = index * dimension * MemoryLayout<Float>.size
            let byteCount = dimension * MemoryLayout<Float>.size
            guard byteOffset + byteCount <= mapped.count else { return [] }
            return mapped.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.baseAddress!.advanced(by: byteOffset)
                    .assumingMemoryBound(to: Float.self)
                return Array(UnsafeBufferPointer(start: ptr, count: dimension))
            }
        } else {
            let pendingIdx = index - persistedChunkCount
            guard pendingIdx >= 0 else { return [] }
            let start = pendingIdx * dimension
            let end = start + dimension
            guard end <= pendingEmbeddings.count else { return [] }
            return Array(pendingEmbeddings[start..<end])
        }
    }

    func statistics() async -> VectorDatabaseStats {
        let mmapBytes = mappedVectors?.count ?? 0
        let pendingBytes = pendingEmbeddings.count * MemoryLayout<Float>.size
        let normBytes = embeddingNorms.count * MemoryLayout<Float>.size
        let heapBytes = normBytes + pendingBytes  // mmap doesn't count as heap
        let uniqueDocs = Set(chunks.map(\.documentId)).count
        return VectorDatabaseStats(
            chunkCount: chunks.count,
            dimension: dimension,
            uniqueDocuments: uniqueDocs,
            estimatedMemoryBytes: heapBytes,
            backend: "BNNS/Accelerate (mmap + Metal, \(mmapBytes / 1_048_576)MB mmap'd)"
        )
    }
}

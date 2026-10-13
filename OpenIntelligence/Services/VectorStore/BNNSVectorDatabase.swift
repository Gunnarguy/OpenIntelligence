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
//  - `slots: [PassageSlot]` — one small record per passage (ids, its number in its
//    document, page, level, and where its JSON object is in the metadata file).
//    72 bytes each. Since 5.7 this replaces `chunks: [DocumentChunk]`, which held
//    every passage's text in memory after decoding the whole metadata file at load.
//  - `mappedMeta: Data` — the metadata file, memory-mapped. A passage is decoded
//    from its own bytes when it is asked for (`PassageFileIndex.swift`).
//
//  **Persistence (3 files, binary format, unchanged by 5.7):**
//  - `_meta.json` — one JSON array of passages (content, IDs, metadata, `embedding: []`)
//  - `_vectors.bin` — raw Float32 contiguous, memory-mapped on load
//  - `_norms.bin` — pre-computed L2 norms, raw Float32
//
//  **Saving (5.7):** each file is still written whole to a temporary file and moved
//  into place, vectors first. What changed is where the bytes come from: passages
//  already in the metadata file are copied as they are instead of being encoded
//  again, and the vectors are streamed from the mapping instead of being gathered
//  in memory first.
//
//  **Search:**
//  - GPU path (≥1000 chunks): Metal compute shader via UnsafeBufferPointer
//    from mmap for near-zero-copy GPU access.
//  - CPU path (<1000 chunks): vDSP_dotpr directly on mmap'd pointer.
//  - Partial heap sort for top-K: O(n log k) vs O(n log n).
//
//  **Memory, measured (5.7, 144,247 passages of about 1.5 KB of JSON each, on the Mac):**
//  - After a load: 11 MB. That is the slots and the norms. No passage text is held.
//  - After the first `allChunks()`: about 330 MB, the same as a plain decode of the file.
//    The store keeps the decoded passages from then on and lets go of them under memory
//    pressure (`releaseDecodedPassages`).
//  - Through 5.6 a load decoded every passage, so the second figure was reached at launch.
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

    // MARK: Passages

    /// One record per passage, in store order. The vectors and the norms are in the same order.
    private var slots: [PassageSlot] = []

    /// The metadata file, memory-mapped. A slot whose `offset` is not `PassageSlot.inMemory`
    /// points into it.
    private var mappedMeta: Data?

    /// The passages that are not in the metadata file yet, embeddings stripped. They are always
    /// the last `pendingChunks.count` slots: a batch is appended, a delete keeps the order, and
    /// a save writes them out and empties this.
    private var pendingChunks: [DocumentChunk] = []

    /// Every passage decoded, once a caller has asked for all of them. Aligned with `slots`.
    /// While this is nil the store holds no passage text except `pendingChunks` and a small
    /// cache of recently decoded passages.
    private var everyChunkCache: [DocumentChunk]?

    /// The decode of every passage that is under way, and the passage generation it started at.
    private var everyChunkTask: (generation: Int, task: Task<[DocumentChunk]?, Never>)?

    /// The passage generation at which a decode of every passage found one it could not read.
    /// The store does not try again until the passages change.
    private var unreadableGeneration: Int?

    /// What `readableChunks()` handed back while a passage could not be read, and the passage
    /// generation it belongs to, so a library in that state does not decode every passage
    /// again for each question. Not aligned with `slots`. Let go under memory pressure.
    private var readableFallback: (generation: Int, chunks: [DocumentChunk])?

    /// Passages decoded one at a time (search results, lookups), by position. Emptied when it
    /// reaches `decodedCacheLimit` and whenever positions change.
    private var decodedByIndex: [Int: DocumentChunk] = [:]
    private static let decodedCacheLimit = 4_096

    /// Goes up whenever the passages change. A decode of every passage that started before a
    /// change is still returned to whoever asked for it, and not kept.
    private var passageGeneration = 0

    private let passageDecoder = JSONDecoder()

    /// Tells the store when the system is short of memory, once it holds every passage decoded.
    nonisolated(unsafe) private var memoryPressure: DispatchSourceMemoryPressure?

    /// Pre-computed L2 norms. 200 KB for 50K chunks — acceptable in RAM.
    private var embeddingNorms: [Float] = []

    /// Dirty flag for deferred persistence
    private var isDirty = false

    /// The vectors file on disk is not exactly this store's vectors: a load found more or fewer
    /// than the metadata lists, or a delete could not finish. The next save writes the file
    /// again even when no new passages are waiting.
    private var vectorsFileNeedsRewrite = false

    /// Load-completion task — all public methods await this before accessing data.
    /// Prevents returning empty results while loadFromDisk is in progress.
    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    #if DEBUG
    /// For tests. Called before each write of the metadata file with how many there have been
    /// since it was set. Throwing ends the save there, which leaves the files the way they are
    /// when the app is ended between the vectors and the metadata that names them.
    private var beforeMetadataWrite: (@Sendable (Int) throws -> Void)?
    private var metadataWritesSeen = 0

    func interruptMetadataWrites(_ body: (@Sendable (Int) throws -> Void)?) {
        beforeMetadataWrite = body
        metadataWritesSeen = 0
    }
    #endif

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

    deinit {
        memoryPressure?.cancel()
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
    nonisolated static func binaryFileURLs(from legacyURL: URL) -> [URL] {
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
        // Timed because switching libraries is reported slow and four readings of the
        // Documents tab have failed to explain it. This is the one place a switch pays
        // for disk: `VectorStoreRouter.db(for:)` only constructs, and the vectors are
        // read lazily on first access — which for a library switch is immediately.
        // `.vectorDB` is not in `LoggingConfiguration.fileLogCategories`, so this logs
        // to `.pipeline` deliberately: a number nobody can share settles nothing.
        let loadStarted = Date()
        defer {
            let elapsedMs = Date().timeIntervalSince(loadStarted) * 1000
            Log.info(
                "[VectorLoad] \(url.deletingPathExtension().lastPathComponent): "
                    + "\(String(format: "%.0f", elapsedMs))ms for \(self.slots.count) chunk(s)",
                category: .pipeline
            )
        }

        let fm = FileManager.default
        let bin = binaryURLs(from: url)

        // === BINARY FORMAT: mmap vectors, index the metadata file ===
        if fm.fileExists(atPath: bin.meta.path), fm.fileExists(atPath: bin.vectors.path) {
            do {
                // Loaded, or loaded empty because the vectors did not match the metadata.
                _ = try loadBinary(bin)
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

            let stripped = validChunks.map { chunk in
                DocumentChunk(
                    id: chunk.id, documentId: chunk.documentId,
                    content: chunk.content, parentContent: chunk.parentContent,
                    contextualPrefix: chunk.contextualPrefix,
                    embedding: [], metadata: chunk.metadata
                )
            }

            // Save metadata + norms, then open the three files the way any later launch will.
            let metaEnc = try JSONEncoder().encode(stripped)
            try metaEnc.write(to: bin.meta, options: .atomic)
            let normData = norms.withUnsafeBytes { Data($0) }
            try normData.write(to: bin.norms, options: .atomic)
            guard try loadBinary(bin) else { return }

            // Delete legacy JSON
            try? fm.removeItem(at: url)
            Log.info("[BNNS] Migration complete: \(validChunks.count) chunks → binary + mmap", category: .vectorDB)
        } catch {
            Log.error("[BNNS] Legacy load failed: \(error)", category: .vectorDB)
        }
    }

    private func resetLoadedState() {
        slots.removeAll()
        mappedMeta = nil
        pendingChunks.removeAll()
        everyChunkCache = nil
        everyChunkTask = nil
        readableFallback = nil
        decodedByIndex.removeAll()
        passageGeneration &+= 1
        embeddingNorms.removeAll()
        pendingEmbeddings.removeAll(keepingCapacity: false)
        mappedVectors = nil
        persistedChunkCount = 0
        // Whatever is on disk is not this (empty) store. Its first save writes every file.
        vectorsFileNeedsRewrite = true
    }

    /// Opens the three binary files. True when the store is loaded from them. False when the
    /// vectors file did not match the metadata and the store was loaded empty. Throws when the
    /// metadata file is not a passage array at all. It reads and never writes: a second store
    /// may be opened on files the first is in the middle of saving.
    private func loadBinary(_ bin: (meta: URL, vectors: URL, norms: URL)) throws -> Bool {
        let fm = FileManager.default

        // 1. The metadata file, mapped and walked once for each passage's place and record.
        //    Through 5.6 this was `Data(contentsOf:)` and a decode of the whole array.
        let meta = try Data(contentsOf: bin.meta, options: .alwaysMapped)
        var loadedSlots: [PassageSlot]
        var loadedInMemory: [DocumentChunk] = []
        var loadedMeta: Data? = meta
        if let walked = PassageFileIndex.scan(meta) {
            loadedSlots = walked
        } else {
            // Not a file the walk can follow. Decode it whole, as before, and hold the passages
            // in memory. The next save writes them in a form the walk can follow. A file that
            // is not a passage array throws here, which is what a load did before.
            let decoded = try JSONDecoder().decode([DocumentChunk].self, from: meta)
            Log.warning(
                "[BNNS] Metadata file could not be indexed; decoded whole (\(decoded.count) chunks)",
                category: .vectorDB)
            loadedInMemory = decoded
            loadedSlots = decoded.map { PassageSlot(inMemory: $0) }
            loadedMeta = nil
        }

        // 2. Memory-map vectors — 0 bytes heap, OS pages on demand
        let expectedBytes = loadedSlots.count * dimension * MemoryLayout<Float>.size
        var mapped = Data()
        if expectedBytes > 0 {
            mapped = try Data(contentsOf: bin.vectors, options: .alwaysMapped)
        }
        var surplusIgnored = false
        if mapped.count != expectedBytes {
            // More whole vectors than the metadata lists is what a save that was cut off leaves.
            // `saveToDisk` writes the vectors before the metadata that names them, and a save
            // only ever adds vectors at the end, so the first `expectedBytes` are the listed
            // passages' vectors and the rest belong to passages that were never recorded. The
            // store loads as it was before that save. A delete is the one operation that takes
            // vectors out of the middle, and it writes out anything unsaved first, so a delete
            // that is cut off always leaves FEWER vectors than the metadata lists, never more.
            //
            // The surplus is ignored here, not cut off the file, and the next save by this
            // store writes the file at its right length. A load used to rewrite the vectors
            // file, and a second store opened on the same files (sync opens one to read a
            // library) could do that in the middle of the first one's save.
            // (Through 5.6 a file that was not an exact multiple of the expected size deleted
            // the whole store.)
            let bytesPerVector = dimension * MemoryLayout<Float>.size
            if expectedBytes > 0,
               mapped.count > expectedBytes,
               bytesPerVector > 0,
               (mapped.count - expectedBytes) % bytesPerVector == 0 {
                Log.warning(
                    "[BNNS] Vector file holds \((mapped.count - expectedBytes) / bytesPerVector) more vector(s) than the metadata lists; ignoring them (a save was cut off)",
                    category: .pipeline
                )
                mapped = mapped.prefix(expectedBytes)
                surplusIgnored = true
            }

            guard mapped.count == expectedBytes else {
                // Fewer vectors than passages, or part of a vector: there is no telling which
                // passages lost theirs. The store loads empty and the library's empty-index
                // repair takes over, as before. The three files are left as they are (a load
                // used to remove them): this may be a second store looking at files the first
                // is in the middle of writing, and the first save of a store that loaded empty
                // writes all three again.
                Log.error("[BNNS] Vector file size mismatch: \(mapped.count) vs expected \(expectedBytes). Loading this library's vector store empty.", category: .pipeline)
                resetLoadedState()
                return false
            }
        }

        self.slots = loadedSlots
        self.mappedMeta = loadedMeta
        self.pendingChunks = loadedInMemory
        self.everyChunkCache = nil
        self.everyChunkTask = nil
        self.readableFallback = nil
        self.decodedByIndex.removeAll()
        self.passageGeneration &+= 1
        self.mappedVectors = mapped
        self.persistedChunkCount = loadedSlots.count
        self.pendingEmbeddings.removeAll(keepingCapacity: false)
        self.vectorsFileNeedsRewrite = surplusIgnored

        // 3. Norms — 200 KB in RAM (acceptable)
        if let normData = try? Data(contentsOf: bin.norms),
           normData.count == loadedSlots.count * MemoryLayout<Float>.size {
            let count = loadedSlots.count
            self.embeddingNorms = [Float](unsafeUninitializedCapacity: count) { buf, initialized in
                _ = normData.copyBytes(to: buf)
                initialized = count
            }
        } else {
            recomputeNorms()
        }

        Log.info("[BNNS] Loaded \(loadedSlots.count) chunks (mmap'd \(mapped.count / 1_048_576)MB vectors, \(meta.count / 1_048_576)MB metadata indexed, not decoded)", category: .vectorDB)
        return true
    }

    /// Recompute L2 norms from mmap'd vectors
    private func recomputeNorms() {
        self.embeddingNorms = (0..<slots.count).map { computeNormFromMmap(index: $0) }
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

        // 1. New vectors first, written atomically to prevent mmap corruption.
        //
        // The order matters when the app is ended between the two writes. Through 5.6 the
        // metadata went first: a save cut off there left metadata for more chunks than the
        // vectors file held, and the next load answered that mismatch by deleting the whole
        // store, every document's vectors in the library. With the vectors first, a save cut
        // off there leaves more vectors than the metadata lists, which the loader ignores, and
        // the store comes back as it was before the save. The file layout is unchanged.
        //
        // Since 5.7 the file is streamed: what is already mapped, then what is pending. Before,
        // both were copied into one `Data` first, which for 144,247 passages was 221 MB of
        // memory for every save of an import.
        if !pendingEmbeddings.isEmpty || vectorsFileNeedsRewrite {
            let mapped = mappedVectors
            try Self.replaceFile(at: bin.vectors) { handle in
                if let mapped, !mapped.isEmpty {
                    try handle.write(contentsOf: mapped)
                }
                if !pendingEmbeddings.isEmpty {
                    try pendingEmbeddings.withUnsafeBytes { rawBuf in
                        try handle.write(contentsOf: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: rawBuf.baseAddress!), count: rawBuf.count, deallocator: .none))
                    }
                }
            }

            // The new file is mapped before what was pending is let go. If the mapping fails,
            // the store still holds every vector it needs, and the next save writes them again.
            let remapped = try Self.mapOrRead(bin.vectors)
            pendingEmbeddings.removeAll(keepingCapacity: false)
            self.mappedVectors = remapped
            self.persistedChunkCount = slots.count
            vectorsFileNeedsRewrite = false
        }

        // 2. Metadata JSON (chunks have embedding:[]).
        #if DEBUG
        if let beforeMetadataWrite {
            metadataWritesSeen += 1
            try beforeMetadataWrite(metadataWritesSeen)
        }
        #endif
        try writeMetadataFile(to: bin.meta)

        // 3. Norms binary
        let normData = embeddingNorms.withUnsafeBytes { Data($0) }
        try normData.write(to: bin.norms, options: .atomic)

        if url.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
           !WorkspaceSyncService.isSyncWriteInProgress {
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
        }
    }

    /// A file's bytes, memory-mapped when that works and read into memory when it does not.
    nonisolated private static func mapOrRead(_ url: URL) throws -> Data {
        if let mapped = try? Data(contentsOf: url, options: .alwaysMapped) { return mapped }
        return try Data(contentsOf: url)
    }

    /// Writes a file whole to a temporary file and moves that into place, which is what
    /// `Data.write(to:options: .atomic)` does, without needing the whole file in memory.
    ///
    /// The temporary file is made where the system prepares replacements for the destination
    /// (`.itemReplacementDirectory`): on the same volume, in a folder of its own, outside the
    /// library's folder and so outside what iCloud Drive watches when the store is the shared
    /// copy. Its name is unique, because more than one store can be open on a library's files
    /// (sync opens its own), and two saves must not write into one temporary file. The bytes
    /// are synchronised to disk before the move, so a power loss just after it cannot leave
    /// the store's name on blocks that were never written.
    nonisolated private static func replaceFile(at destination: URL, body: (FileHandle) throws -> Void) throws {
        let fm = FileManager.default
        var folder = destination.deletingLastPathComponent()
        var folderIsOurs = false
        if let prepared = try? fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        {
            folder = prepared
            folderIsOurs = true
        }
        let temporary = folder.appendingPathComponent("\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            // After the move the temporary file is gone and only the folder is left to remove.
            try? fm.removeItem(at: folderIsOurs ? folder : temporary)
        }
        guard fm.createFile(atPath: temporary.path, contents: nil) else {
            throw VectorDatabaseError.storeFailed("could not create a temporary file for \(destination.lastPathComponent)")
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try body(handle)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard rename(temporary.path, destination.path) == 0 else {
            throw VectorDatabaseError.storeFailed(
                "could not move the new \(destination.lastPathComponent) into place (errno \(errno))")
        }
    }

    /// Bytes gathered before a write. Passages are small, and one write for each would be
    /// 144,247 system calls.
    private static let metadataWriteBuffer = 4 * 1_048_576

    /// Writes the metadata file: one JSON array of every passage, in store order.
    ///
    /// A passage that is already in the file is copied from the mapping, byte for byte. Only
    /// the passages that are not in the file yet are encoded. Through 5.6 a save encoded every
    /// passage of the library again. The file that results is the same kind of file: an older
    /// build decodes it as it always has.
    private func writeMetadataFile(to url: URL) throws {
        let inFile = slots.count - pendingChunks.count
        guard inFile >= 0 else {
            throw VectorDatabaseError.storeFailed("the passage records and the passages in memory disagree")
        }
        let meta = mappedMeta
        if inFile > 0, meta == nil {
            throw VectorDatabaseError.storeFailed("the metadata file is not mapped")
        }
        var newOffsets = [Int](repeating: 0, count: slots.count)
        var newLengths = [Int](repeating: 0, count: slots.count)
        let comma = UInt8(ascii: ",")
        let encoder = JSONEncoder()

        try Self.replaceFile(at: url) { handle in
            var written = 0
            var buffer = Data()
            buffer.reserveCapacity(Self.metadataWriteBuffer)
            func flush() throws {
                guard !buffer.isEmpty else { return }
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            func append(_ byte: UInt8) {
                buffer.append(byte)
                written += 1
            }

            append(UInt8(ascii: "["))

            // Passages already in the file. Neighbours in the old file with one comma between
            // them are one run, and a file this store wrote is a single run until a document
            // is deleted from the middle of it.
            var index = 0
            while index < inFile, let meta {
                let runStart = slots[index].offset
                var last = index
                while last + 1 < inFile {
                    let end = slots[last].offset + slots[last].length
                    guard slots[last + 1].offset == end + 1, meta[meta.startIndex + end] == comma else { break }
                    last += 1
                }
                let runEnd = slots[last].offset + slots[last].length
                guard runStart >= 0, runEnd <= meta.count, runStart < runEnd else {
                    throw VectorDatabaseError.storeFailed("a passage's place in the metadata file is out of range")
                }
                if index > 0 { append(comma) }
                let shift = written - runStart
                for moved in index...last {
                    newOffsets[moved] = slots[moved].offset + shift
                    newLengths[moved] = slots[moved].length
                }
                let bytes = meta[(meta.startIndex + runStart)..<(meta.startIndex + runEnd)]
                if bytes.count >= Self.metadataWriteBuffer / 4 {
                    try flush()
                    try handle.write(contentsOf: bytes)
                } else {
                    buffer.append(bytes)
                    if buffer.count >= Self.metadataWriteBuffer { try flush() }
                }
                written += bytes.count
                index = last + 1
            }

            // Passages that are not in the file yet.
            for (position, chunk) in pendingChunks.enumerated() {
                let slotIndex = inFile + position
                if slotIndex > 0 { append(comma) }
                let encoded = try encoder.encode(chunk)
                newOffsets[slotIndex] = written
                newLengths[slotIndex] = encoded.count
                buffer.append(encoded)
                written += encoded.count
                if buffer.count >= Self.metadataWriteBuffer { try flush() }
            }

            append(UInt8(ascii: "]"))
            try flush()
        }

        // The file is in place. Point every slot at its new place in it.
        let remapped = try Self.mapOrRead(url)
        for index in slots.indices {
            slots[index].offset = newOffsets[index]
            slots[index].length = newLengths[index]
        }
        mappedMeta = remapped
        if everyChunkCache == nil, !pendingChunks.isEmpty {
            // Keep the passages just written within reach: an import asks for them again when
            // it writes the search index.
            if decodedByIndex.count + pendingChunks.count > Self.decodedCacheLimit {
                decodedByIndex.removeAll(keepingCapacity: true)
            }
            if pendingChunks.count <= Self.decodedCacheLimit {
                for (position, chunk) in pendingChunks.enumerated() {
                    decodedByIndex[inFile + position] = chunk
                }
            }
        }
        pendingChunks.removeAll(keepingCapacity: false)
        // Positions did not change, so a decode of every passage that is under way stays valid.
    }

    // MARK: Reading Passages

    /// One passage from its bytes in the metadata file. Nil when the bytes do not decode, or
    /// decode to a passage other than the one the slot records, which would mean the slots and
    /// the file no longer belong together.
    nonisolated private static func decodePassage(_ slot: PassageSlot, in meta: Data, with decoder: JSONDecoder) -> DocumentChunk? {
        guard slot.offset >= 0, slot.length > 0, slot.offset + slot.length <= meta.count else { return nil }
        let start = meta.startIndex + slot.offset
        guard let chunk = try? decoder.decode(DocumentChunk.self, from: meta[start..<(start + slot.length)]),
            chunk.id == slot.id
        else { return nil }
        return chunk
    }

    /// The passage at a position, decoded if it has to be.
    private func chunk(at index: Int) -> DocumentChunk? {
        guard index >= 0, index < slots.count else { return nil }
        if let all = everyChunkCache { return all[index] }
        let firstInMemory = slots.count - pendingChunks.count
        if index >= firstInMemory { return pendingChunks[index - firstInMemory] }
        if let cached = decodedByIndex[index] { return cached }
        guard let meta = mappedMeta,
            let chunk = Self.decodePassage(slots[index], in: meta, with: passageDecoder)
        else {
            Log.error("[BNNS] Passage \(index) could not be read from the metadata file", category: .pipeline)
            return nil
        }
        if decodedByIndex.count >= Self.decodedCacheLimit {
            decodedByIndex.removeAll(keepingCapacity: true)
        }
        decodedByIndex[index] = chunk
        return chunk
    }

    /// More passages than this are decoded on several threads, away from the actor.
    private static let parallelDecodeThreshold = 2_000

    /// Passages at the given positions, in the order asked. A position that cannot be read is
    /// left out. A large request is decoded on several threads from a snapshot taken now.
    private func chunks(atPositions positions: [Int]) async -> [DocumentChunk] {
        if let all = everyChunkCache {
            return positions.compactMap { $0 >= 0 && $0 < all.count ? all[$0] : nil }
        }
        let firstInMemory = slots.count - pendingChunks.count
        let toDecode = positions.reduce(0) { $0 + (($1 >= 0 && $1 < firstInMemory && decodedByIndex[$1] == nil) ? 1 : 0) }
        guard toDecode > Self.parallelDecodeThreshold, let meta = mappedMeta else {
            return positions.compactMap { chunk(at: $0) }
        }
        let snapshot = slots
        let inMemory = pendingChunks
        let found = await Self.decode(positions: positions, slots: snapshot, inMemory: inMemory, meta: meta)
        let asked = positions.reduce(0) { $0 + (($1 >= 0 && $1 < snapshot.count) ? 1 : 0) }
        if found.count < asked {
            Log.error(
                "[BNNS] \(asked - found.count) passage(s) could not be read from the metadata file and were left out",
                category: .pipeline)
        }
        return found
    }

    /// Decodes passages on several threads. `positions` index into `slots`, whose last
    /// `inMemory.count` passages are held in `inMemory` and the rest in `meta`.
    nonisolated private static func decode(
        positions: [Int], slots: [PassageSlot], inMemory: [DocumentChunk], meta: Data
    ) async -> [DocumentChunk] {
        let firstInMemory = slots.count - inMemory.count
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, positions.count / 1_000 + 1))
        let step = (positions.count + workers - 1) / workers
        let parts: [[DocumentChunk]] = await withTaskGroup(of: (Int, [DocumentChunk]).self) { group in
            for worker in 0..<workers {
                let lower = worker * step
                let upper = min(positions.count, lower + step)
                guard lower < upper else { continue }
                group.addTask {
                    let decoder = JSONDecoder()
                    var decoded: [DocumentChunk] = []
                    decoded.reserveCapacity(upper - lower)
                    for position in positions[lower..<upper] {
                        guard position >= 0, position < slots.count else { continue }
                        if position >= firstInMemory {
                            decoded.append(inMemory[position - firstInMemory])
                        } else if let chunk = decodePassage(slots[position], in: meta, with: decoder) {
                            decoded.append(chunk)
                        }
                    }
                    return (worker, decoded)
                }
            }
            var collected = [[DocumentChunk]](repeating: [], count: workers)
            for await (worker, decoded) in group {
                collected[worker] = decoded
            }
            return collected
        }
        var result: [DocumentChunk] = []
        result.reserveCapacity(positions.count)
        for part in parts { result.append(contentsOf: part) }
        return result
    }

    /// Threads for the decode of every passage: all but two of the processors, so the main
    /// thread and whatever else the app is doing keep one each. (Measured on the Mac with
    /// 144,247 passages: 0.43 s on eleven threads, 1.19 s on four, and the same memory held
    /// afterwards either way.)
    private static var everyChunkThreads: Int { max(2, ProcessInfo.processInfo.activeProcessorCount - 2) }

    /// What each thread of `decodeEvery` managed, so that a failure can be undone.
    private final class DecodeProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var initialized: [Range<Int>] = []
        private var failed = false

        func finished(_ range: Range<Int>, complete: Bool) {
            lock.lock()
            initialized.append(range)
            if !complete { failed = true }
            lock.unlock()
        }

        var result: (ranges: [Range<Int>], failed: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (initialized, failed)
        }
    }

    /// Every passage of a snapshot, decoded on several threads straight into the array that is
    /// returned, so the decode needs no second copy of 144,247 passages on the way. Nil when a
    /// passage could not be read, with nothing left behind.
    nonisolated private static func decodeEvery(slots: [PassageSlot], inMemory: [DocumentChunk], meta: Data) -> [DocumentChunk]? {
        let total = slots.count
        let inFile = total - inMemory.count
        guard inFile > 0 else { return inMemory }
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, Self.everyChunkThreads, inFile / 1_000 + 1))
        let step = (inFile + workers - 1) / workers
        let progress = DecodeProgress()
        var succeeded = true
        let result = [DocumentChunk](unsafeUninitializedCapacity: total) { buffer, initializedCount in
            initializedCount = 0
            guard let base = buffer.baseAddress else {
                succeeded = false
                return
            }
            let address = UInt(bitPattern: base)
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                let lower = worker * step
                let upper = min(inFile, lower + step)
                guard lower < upper, let target = UnsafeMutablePointer<DocumentChunk>(bitPattern: address) else { return }
                let decoder = JSONDecoder()
                var index = lower
                while index < upper {
                    guard let chunk = decodePassage(slots[index], in: meta, with: decoder) else { break }
                    (target + index).initialize(to: chunk)
                    index += 1
                }
                progress.finished(lower..<index, complete: index == upper)
            }
            let outcome = progress.result
            if outcome.failed {
                for range in outcome.ranges where !range.isEmpty {
                    (base + range.lowerBound).deinitialize(count: range.count)
                }
                succeeded = false
                return
            }
            for (offset, chunk) in inMemory.enumerated() {
                (base + inFile + offset).initialize(to: chunk)
            }
            initializedCount = total
        }
        return succeeded ? result : nil
    }

    /// Every passage, decoded and in store order, or nil when one of them cannot be read. The
    /// first call decodes the metadata file on several threads and the result is kept, so from
    /// then on the store holds every passage's text, as it did from load through 5.6. Callers
    /// that need a count, a sample, one document or a few passages use the methods that do not
    /// come here.
    private func everyChunkIfWhole() async -> [DocumentChunk]? {
        if let cached = everyChunkCache { return cached }
        let inFile = slots.count - pendingChunks.count
        if inFile <= 0 { return pendingChunks }
        let generation = passageGeneration
        guard let meta = mappedMeta, unreadableGeneration != generation else { return nil }

        let task: Task<[DocumentChunk]?, Never>
        if let running = everyChunkTask, running.generation == generation {
            task = running.task
        } else {
            let snapshot = slots
            let inMemory = pendingChunks
            let started = Date()
            task = Task.detached(priority: .userInitiated) {
                guard let filled = Self.decodeEvery(slots: snapshot, inMemory: inMemory, meta: meta) else {
                    return nil
                }
                // Each thread of the decode keeps what it freed for its own next use. Hand
                // that back, or it stays counted against the app for a decode that runs once.
                malloc_zone_pressure_relief(nil, 0)
                Log.info(
                    "[VectorLoad] decoded every passage: \(filled.count) in "
                        + "\(String(format: "%.0f", Date().timeIntervalSince(started) * 1000))ms",
                    category: .pipeline)
                return filled
            }
            everyChunkTask = (generation, task)
        }
        guard let decoded = await task.value else {
            if passageGeneration == generation {
                everyChunkTask = nil
                unreadableGeneration = generation
            }
            return nil
        }
        if passageGeneration == generation {
            everyChunkTask = nil
            if decoded.count == slots.count {
                everyChunkCache = decoded
                readableFallback = nil
                decodedByIndex.removeAll(keepingCapacity: false)
                watchMemoryPressure()
            }
        }
        return decoded
    }

    /// Every passage, or an error. It never hands back fewer passages than the store holds:
    /// a caller of `allChunks()` may pair the array with the vectors by position (sync does, to
    /// write both copies of a library), and an array with one passage missing would give every
    /// passage after it its neighbour's vector.
    private func everyChunk() async throws -> [DocumentChunk] {
        if let all = await everyChunkIfWhole() { return all }
        Log.error(
            "[BNNS] A passage in the metadata file could not be read, so the library's passages were not handed over whole. "
                + "Searches, questions and reads of one document go on without that passage.",
            category: .pipeline)
        throw VectorDatabaseError.searchFailed("a passage in this library's vector store could not be read")
    }

    /// Lets go of every decoded passage the store is holding. Nothing is lost: the passages are
    /// in the metadata file, and whoever asks next has them decoded again. The store calls this
    /// itself when the system reports memory pressure, because the decoded passages are the
    /// largest thing it holds (276 MB for 144,247 passages in the scale benchmark) and the one
    /// thing it can rebuild.
    ///
    /// A caller that is still holding the array it was given keeps those passages alive until
    /// it is done, so memory comes back when the last holder lets go, and a caller that asks
    /// again while another still holds the old array has both in memory for that time.
    func releaseDecodedPassages() {
        guard everyChunkCache != nil || readableFallback != nil || !decodedByIndex.isEmpty else { return }
        let held = everyChunkCache?.count ?? readableFallback?.chunks.count ?? decodedByIndex.count
        everyChunkCache = nil
        readableFallback = nil
        decodedByIndex.removeAll(keepingCapacity: false)
        Log.info("[BNNS] Released \(held) decoded passage(s) under memory pressure", category: .pipeline)
    }

    private func watchMemoryPressure() {
        guard memoryPressure == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.releaseDecodedPassages() }
        }
        source.resume()
        memoryPressure = source
    }

    /// The passages changed in a way that moves positions (a delete, an update, a clear).
    private func positionsChanged() {
        passageGeneration &+= 1
        everyChunkTask = nil
        readableFallback = nil
        decodedByIndex.removeAll(keepingCapacity: false)
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
        let totalCount = slots.count

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

    /// The passage as the store holds it: without its embedding, which lives in the vectors file.
    private func stripped(_ chunk: DocumentChunk) -> DocumentChunk {
        DocumentChunk(
            id: chunk.id, documentId: chunk.documentId,
            content: chunk.content, parentContent: chunk.parentContent,
            contextualPrefix: chunk.contextualPrefix,
            embedding: [], metadata: chunk.metadata
        )
    }

    /// Adds a passage after the others: its vector, its norm, its record and its text.
    private func append(_ chunk: DocumentChunk) {
        pendingEmbeddings.append(contentsOf: chunk.embedding)
        let kept = stripped(chunk)
        slots.append(PassageSlot(inMemory: kept))
        pendingChunks.append(kept)
        everyChunkCache?.append(kept)
        embeddingNorms.append(computeNormAccelerated(chunk.embedding))
        // Positions of the passages already here did not move, so the per-position cache
        // stays. A decode of every passage that is under way no longer covers the store.
        passageGeneration &+= 1
        everyChunkTask = nil
        readableFallback = nil
    }

    func store(chunk: DocumentChunk) async throws {
        await awaitLoad()
        guard chunk.embedding.count == dimension else {
            Log.error("[BNNS] Dimension mismatch: \(chunk.embedding.count) vs \(dimension)", category: .vectorDB)
            throw VectorDatabaseError.invalidEmbedding
        }

        append(chunk)

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
        slots.reserveCapacity(slots.count + validChunks.count)

        for chunk in validChunks {
            append(chunk)
        }

        isDirty = true
        Log.debug("[BNNS] Batch buffered \(validChunks.count) chunks (persist deferred)", category: .vectorDB)
    }

    /// Persist pending data to disk + re-mmap
    func persist() async throws {
        await awaitLoad()
        // Passages can be waiting when their vectors are not (a save wrote the vectors and
        // failed on the metadata), and a delete that could not finish leaves `isDirty` set.
        guard isDirty || !pendingEmbeddings.isEmpty || !pendingChunks.isEmpty || vectorsFileNeedsRewrite else { return }
        try saveToDisk()
        isDirty = false
        Log.debug("[BNNS] Persisted \(slots.count) chunks (\(persistedChunkCount) mmap'd)", category: .vectorDB)
    }

    /// Reload the database from disk (if applicable).
    func reload() async throws {
        await awaitLoad()
        if let url = storageURL {
            loadTask = Task {
                self.loadFromDisk(url: url)
            }
            await awaitLoad()
        }
    }

    func search(embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        await awaitLoad()
        guard embedding.count == dimension else {
            throw VectorDatabaseError.invalidEmbedding
        }
        if slots.isEmpty { return [] }

        let queryNorm = computeNormAccelerated(embedding)
        guard queryNorm > 1e-9 else {
            Log.warning("[BNNS] Near-zero query norm", category: .vectorDB)
            return []
        }

        var scores: [Float]
        let gpuThreshold = 1000
        let gpu = await getGPUCompute()
        let metalVectorOpsEnabled = await DeviceCapabilityService.shared.useMetalForVectorOps
        // Every await lets other calls into the actor, and one of them can add or remove
        // passages. The count is read after the last await on each path, so the scores, the
        // ranking and the passages handed back all describe the same store.
        var count = slots.count
        if count == 0 { return [] }
        let useGPU = count >= gpuThreshold && metalVectorOpsEnabled && gpu.isGPUAvailable
        var batchThreshold = 0
        if !useGPU {
            batchThreshold = await DeviceCapabilityService.shared.batchMatrixMultiplyThreshold
            count = slots.count
            if count == 0 { return [] }
        }

        if useGPU {
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

        // Only the passages that came out on top are decoded.
        var results: [RetrievedChunk] = []
        results.reserveCapacity(topIndices.count)
        for idx in topIndices {
            guard let found = chunk(at: idx) else { continue }
            results.append(RetrievedChunk(chunk: found, similarityScore: scores[idx], rank: results.count + 1))
        }
        return results
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

        // Anything not yet saved is written out first. A delete takes vectors out of the middle
        // of the vectors file and writes that file before the metadata. With unsaved passages
        // waiting, a delete cut off between the two could leave as many vectors as the metadata
        // lists, or more, in a different order, and the loader would have paired them with the
        // wrong passages without a sign. After this save a cut-off delete can only leave fewer
        // vectors than passages, which the loader sees and answers by loading the store empty.
        if storageURL != nil,
           isDirty || !pendingEmbeddings.isEmpty || !pendingChunks.isEmpty || vectorsFileNeedsRewrite {
            try saveToDisk()
            isDirty = false
        }

        // Which passages stay is read from the records. Through 5.6 this compared every decoded
        // passage, and it still does the same work on the files: the vectors of the passages
        // that stay are written out again, and so is the metadata.
        var keepIndices: [Int] = []
        keepIndices.reserveCapacity(slots.count)
        for index in slots.indices where slots[index].documentId != documentId {
            keepIndices.append(index)
        }
        let deletedCount = slots.count - keepIndices.count
        // Nothing of that document is here, and what was unsaved has been saved.
        guard deletedCount > 0 else { return }

        // Rebuild vectors file with kept indices only
        if let url = storageURL {
            let bin = binaryURLs(from: url)
            let bytesPerVector = dimension * MemoryLayout<Float>.size
            let mapped = mappedVectors
            let remapped: Data
            do {
                try Self.replaceFile(at: bin.vectors) { handle in
                    // Vectors that stay and sit next to each other in the mapped file are
                    // written as one run. Through 5.6 each vector was its own write, 143,747
                    // of them to take one small document out of the benchmark's library.
                    var run: Range<Int>?
                    func writeRun() throws {
                        guard let mapped, let pending = run else { return }
                        let lower = mapped.startIndex + pending.lowerBound * bytesPerVector
                        let upper = mapped.startIndex + pending.upperBound * bytesPerVector
                        try handle.write(contentsOf: mapped[lower..<upper])
                        run = nil
                    }
                    for idx in keepIndices {
                        if idx < persistedChunkCount, let mapped {
                            guard (idx + 1) * bytesPerVector <= mapped.count else { continue }
                            if let current = run, current.upperBound == idx {
                                run = current.lowerBound..<(idx + 1)
                            } else {
                                try writeRun()
                                run = idx..<(idx + 1)
                            }
                        } else {
                            try writeRun()
                            let pendingIdx = idx - persistedChunkCount
                            let start = pendingIdx * dimension
                            let end = start + dimension
                            guard pendingIdx >= 0, end <= pendingEmbeddings.count else { continue }
                            try pendingEmbeddings[start..<end].withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
                        }
                    }
                    try writeRun()
                }
                remapped = try Self.mapOrRead(bin.vectors)
            } catch {
                // The store in memory is still the store before the delete. If the vectors file
                // was already replaced, the next save writes it again from here.
                vectorsFileNeedsRewrite = true
                isDirty = true
                throw error
            }
            self.mappedVectors = remapped
            pendingEmbeddings.removeAll(keepingCapacity: false)
        } else {
            // A store with no files holds every vector in `pendingEmbeddings`. Keep the ones
            // that stay. (Through 5.6 a delete emptied it, and the store with it.)
            var keptVectors: [Float] = []
            keptVectors.reserveCapacity(keepIndices.count * dimension)
            for idx in keepIndices {
                let start = (idx - persistedChunkCount) * dimension
                let end = start + dimension
                guard start >= 0, end <= pendingEmbeddings.count else { continue }
                keptVectors.append(contentsOf: pendingEmbeddings[start..<end])
            }
            pendingEmbeddings = keptVectors
        }

        let firstInMemory = slots.count - pendingChunks.count
        var newSlots: [PassageSlot] = []
        var newPending: [DocumentChunk] = []
        var newNorms: [Float] = []
        newSlots.reserveCapacity(keepIndices.count)
        newNorms.reserveCapacity(keepIndices.count)
        for index in keepIndices {
            newSlots.append(slots[index])
            newNorms.append(embeddingNorms[index])
            if index >= firstInMemory { newPending.append(pendingChunks[index - firstInMemory]) }
        }
        if let all = everyChunkCache { everyChunkCache = keepIndices.map { all[$0] } }
        slots = newSlots
        pendingChunks = newPending
        embeddingNorms = newNorms
        persistedChunkCount = storageURL == nil ? 0 : slots.count
        positionsChanged()

        Log.debug("[BNNS] Deleted \(deletedCount) chunks for document \(documentId)", category: .vectorDB)
        // Until the metadata is written the files disagree. If this save fails, `isDirty` stays
        // set and the next `persist()` writes the metadata again. Through 5.6, and until this
        // was added, nothing retried it and the next launch found the mismatch.
        isDirty = true
        try saveToDisk()
        isDirty = false
    }

    func clear() async throws {
        await awaitLoad()
        slots.removeAll()
        mappedMeta = nil
        pendingChunks.removeAll()
        everyChunkCache = nil
        positionsChanged()
        embeddingNorms.removeAll()
        pendingEmbeddings.removeAll()
        mappedVectors = nil
        persistedChunkCount = 0
        isDirty = false
        vectorsFileNeedsRewrite = false

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
        return slots.count
    }

    func allChunks() async throws -> [DocumentChunk] {
        await awaitLoad()
        return try await everyChunk()
    }

    func readableChunks() async throws -> [DocumentChunk] {
        await awaitLoad()
        if let all = await everyChunkIfWhole() { return all }
        if let fallback = readableFallback, fallback.generation == passageGeneration { return fallback.chunks }
        // One passage or more cannot be read. Every other passage is handed over, which is what
        // a search or a read of one document does too. `chunks(atPositions:)` logs how many
        // were left out.
        let generation = passageGeneration
        let found = await chunks(atPositions: Array(slots.indices))
        if passageGeneration == generation {
            readableFallback = (generation, found)
            watchMemoryPressure()
        }
        return found
    }

    // MARK: Passages Without Decoding All Of Them (5.7)

    func passageRecords() async throws -> [PassageRecord] {
        await awaitLoad()
        return slots.map(\.record)
    }

    func chunks(forDocument documentId: UUID, limit: Int?) async throws -> [DocumentChunk] {
        await awaitLoad()
        var positions: [Int] = []
        for index in slots.indices where slots[index].documentId == documentId {
            if let limit, positions.count >= limit { break }
            positions.append(index)
        }
        return await chunks(atPositions: positions)
    }

    func chunkCount(forDocument documentId: UUID) async throws -> Int {
        await awaitLoad()
        return slots.reduce(0) { $0 + ($1.documentId == documentId ? 1 : 0) }
    }

    /// Where each of these ids is in the store, found in one pass over the records. An id the
    /// store does not hold has no entry. Good until the next await.
    private func positions(of ids: [UUID]) -> [UUID: Int] {
        let wanted = Set(ids)
        var positionById: [UUID: Int] = [:]
        positionById.reserveCapacity(wanted.count)
        for index in slots.indices where wanted.contains(slots[index].id) {
            if positionById[slots[index].id] == nil { positionById[slots[index].id] = index }
        }
        return positionById
    }

    func chunks(withIDs ids: [UUID]) async throws -> [DocumentChunk] {
        await awaitLoad()
        guard !ids.isEmpty else { return [] }
        let positionById = positions(of: ids)
        return await chunks(atPositions: ids.compactMap { positionById[$0] })
    }

    func updateChunk(_ chunk: DocumentChunk) async throws {
        await awaitLoad()
        guard let idx = slots.firstIndex(where: { $0.id == chunk.id }) else {
            try await store(chunk: chunk)
            return
        }
        guard chunk.embedding.count == dimension else {
            throw VectorDatabaseError.invalidEmbedding
        }
        // As for a delete: what is unsaved goes out first, so the files agree before one
        // vector in the middle of them is changed.
        if storageURL != nil,
           isDirty || !pendingEmbeddings.isEmpty || !pendingChunks.isEmpty || vectorsFileNeedsRewrite {
            try saveToDisk()
            isDirty = false
        }

        // Nothing calls this today. It changes one passage in the middle of the file, so every
        // passage is brought into memory, as the store held them through 5.6, and the save
        // below writes the whole file from there.
        var all: [DocumentChunk] = []
        all.reserveCapacity(slots.count)
        for index in slots.indices {
            guard let existing = self.chunk(at: index) else {
                throw VectorDatabaseError.storeFailed("a passage could not be read from the metadata file")
            }
            all.append(existing)
        }
        let kept = stripped(chunk)
        all[idx] = kept

        // The vectors file first, with the one vector changed. The store in memory is not
        // touched until that file is in place.
        if let url = storageURL {
            let bin = binaryURLs(from: url)
            let bytesPerVector = dimension * MemoryLayout<Float>.size
            let mapped = mappedVectors
            let total = slots.count
            let remapped: Data
            do {
                try Self.replaceFile(at: bin.vectors) { handle in
                    for i in 0..<total {
                        if i == idx {
                            try chunk.embedding.withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
                        } else if i < persistedChunkCount, let mapped {
                            let byteOffset = i * bytesPerVector
                            guard byteOffset + bytesPerVector <= mapped.count else { continue }
                            try handle.write(contentsOf: mapped[(mapped.startIndex + byteOffset)..<(mapped.startIndex + byteOffset + bytesPerVector)])
                        } else {
                            let pendingIdx = i - persistedChunkCount
                            let start = pendingIdx * dimension
                            let end = start + dimension
                            guard pendingIdx >= 0, end <= pendingEmbeddings.count else { continue }
                            try pendingEmbeddings[start..<end].withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
                        }
                    }
                }
                remapped = try Self.mapOrRead(bin.vectors)
            } catch {
                vectorsFileNeedsRewrite = true
                isDirty = true
                throw error
            }
            self.mappedVectors = remapped
            self.pendingEmbeddings.removeAll(keepingCapacity: false)
            self.persistedChunkCount = slots.count
        } else {
            let start = (idx - persistedChunkCount) * dimension
            if start >= 0, start + dimension <= pendingEmbeddings.count {
                pendingEmbeddings.replaceSubrange(start..<(start + dimension), with: chunk.embedding)
            }
        }

        for index in slots.indices { slots[index] = PassageSlot(inMemory: all[index]) }
        pendingChunks = all
        everyChunkCache = nil
        positionsChanged()
        embeddingNorms[idx] = computeNormAccelerated(chunk.embedding)

        isDirty = true
        try saveToDisk()
        isDirty = false
    }

    func exists(chunkId: UUID) async -> Bool {
        slots.contains { $0.id == chunkId }
    }

    /// Retrieve embeddings for Gate E Semantic Grounding
    func getEmbeddings(forChunkIDs ids: [UUID]) async -> [[Float]] {
        // A few ids (the grounding check asks for three to ten) are each looked up in the
        // records. Many ids (the Atlas asks for thousands) are found in one pass over them.
        guard ids.count > 16 else {
            return ids.map { id in
                guard let idx = slots.firstIndex(where: { $0.id == id }) else { return [Float]() }
                return readEmbedding(at: idx)
            }
        }
        let positionById = positions(of: ids)
        return ids.map { id in
            guard let idx = positionById[id] else { return [Float]() }
            return readEmbedding(at: idx)
        }
    }

    func getEmbeddings(forIndices indices: [Int]) async -> [[Float]] {
        indices.map { readEmbedding(at: $0) }
    }

    /// Read embedding from mmap or pending — O(d) copy, only for the chunks needed
    private func readEmbedding(at index: Int) -> [Float] {
        guard index >= 0, index < slots.count else { return [] }

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
        let slotBytes = slots.count * MemoryLayout<PassageSlot>.stride
        let heapBytes = normBytes + pendingBytes + slotBytes  // mmap doesn't count as heap
        var documents = Set<UUID>()
        for slot in slots { documents.insert(slot.documentId) }
        return VectorDatabaseStats(
            chunkCount: slots.count,
            dimension: dimension,
            uniqueDocuments: documents.count,
            estimatedMemoryBytes: heapBytes,
            backend: "BNNS/Accelerate (mmap + Metal, \(mmapBytes / 1_048_576)MB mmap'd)"
        )
    }
}

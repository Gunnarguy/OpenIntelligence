//
//  RAGService+TextStreaming.swift
//  OpenIntelligence
//

import CryptoKit
import Foundation

// MARK: - Large text and JSON Lines, imported in pieces

/// What an import in pieces has committed. It is saved beside the pieces, so a restart, a locked
/// phone or a background window that ran out continues from the last piece and not from the start.
nonisolated struct TextStreamingIngestionState: Codable, Equatable, Sendable {
    static let fileName = "text_ingestion_state.json"

    /// Everything that changes when a piece is committed.
    nonisolated struct Progress: Codable, Equatable, Sendable {
        /// The first byte of the file not yet imported. Always the start of a line.
        var completedBytes = 0
        var completedPieces = 0
        /// JSON Lines: records numbered so far.
        var recordsDone = 0
        var totalChunks = 0
        var totalWords = 0
        var totalChars = 0
        /// Bytes and characters of the kept document text that belong to the committed pieces.
        var keptTextBytes = 0
        var keptTextChars = 0
    }

    var documentId: UUID
    /// The library the committed pieces are in. An import picks its library when it starts, and
    /// a resumed one starts again, so the library on screen may have changed in between. nil in
    /// a state file written before this was recorded, which is read as "the same library".
    var containerId: UUID?
    /// The file's size when the import began. A file of another size starts again.
    var fileBytes: Int
    /// Bytes a piece aims for. A restart with another figure would cut different pieces.
    var pieceBytes: Int
    /// The longest single line kept whole. nil in an older state file means the reader's default.
    var longestLineBytes: Int?
    /// Pieces in the whole file.
    var totalPieces: Int
    /// JSON Lines: records in the whole file. nil for plain text.
    var totalRecords: Int?
    var committed = Progress()
    /// Set just before a piece's chunks go to the vector store and the search index, to what
    /// `committed` becomes once both have them, and cleared when they do. Found set at a restart,
    /// the two stores are counted to learn whether that piece went in.
    var pending: Progress?

    /// What to do about a piece that was being stored when the app stopped.
    nonisolated enum Recovery: Equatable, Sendable {
        /// No piece was being stored.
        case nothingPending
        /// Neither store has the piece. It is imported again.
        case redoPiece
        /// Both stores have all of the piece. It counts as committed.
        case pieceWentIn
        /// The vector store has all of the piece and the search index has none of it: the app
        /// stopped between the two saves. The piece's index rows are written from the chunks the
        /// vector store holds, and then it counts as committed. Through the first two device
        /// runs this state started the document over, and on 2026-10-10 it threw away 16 parts.
        case finishIndex
        /// The stores disagree in some other way. Chunks cannot be taken out of either store one
        /// piece at a time, so the document starts again.
        case startOver
    }

    static func recovery(committedChunks: Int, pendingChunks: Int?, vectorChunks: Int, indexChunks: Int) -> Recovery {
        guard let pendingChunks else { return .nothingPending }
        if vectorChunks == pendingChunks, indexChunks == pendingChunks { return .pieceWentIn }
        if vectorChunks == committedChunks, indexChunks == committedChunks { return .redoPiece }
        if vectorChunks == pendingChunks, indexChunks == committedChunks { return .finishIndex }
        return .startOver
    }

    static func read(at url: URL) -> TextStreamingIngestionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TextStreamingIngestionState.self, from: data)
    }

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// The vectors of the piece being embedded, kept beside the checkpoint as they are made.
///
/// A piece is a few thousand passages and minutes of embedding, and a checkpoint is only saved
/// when the whole piece is in both stores. Without this, stopping in the middle of a piece threw
/// its embedding away, and a person who left the app every minute or two never got past the
/// first piece (an iPhone, 2026-10-09). The file holds raw 32-bit floats in passage order, and a
/// second file says what they belong to.
nonisolated enum TextPieceVectors {
    static let fileName = "piece_vectors.bin"

    /// What a file of kept vectors belongs to: the piece, the passages' exact texts, the vector
    /// size and the embedder. A file written for anything else is not read.
    static func key(pieceNumber: Int, texts: [String], dimension: Int, providerId: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("v1|\(pieceNumber)|\(dimension)|\(providerId)|\(texts.count)".utf8))
        for text in texts {
            hasher.update(data: Data(text.utf8))
            hasher.update(data: Data([0x1F]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The whole vectors a stopped run kept for this piece, or none when the file is for
    /// something else. Bytes of a vector that was being written when the app stopped are not
    /// counted, and `append` cuts them off.
    @concurrent
    static func read(at url: URL, key: String, dimension: Int, limit: Int) async -> [[Float]] {
        let keyURL = url.appendingPathExtension("key")
        guard dimension > 0, let savedKey = try? String(contentsOf: keyURL, encoding: .utf8), savedKey == key,
            let data = try? Data(contentsOf: url)
        else { return [] }
        let bytesPerVector = dimension * MemoryLayout<Float>.size
        let count = min(limit, data.count / bytesPerVector)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            var vector = [Float](repeating: 0, count: dimension)
            vector.withUnsafeMutableBytes { target in
                _ = data.copyBytes(to: target, from: (index * bytesPerVector)..<((index + 1) * bytesPerVector))
            }
            return vector
        }
    }

    /// Adds a slice's vectors to the kept file. The first slice of a piece starts the file over
    /// and writes what it belongs to.
    @concurrent
    static func append(_ vectors: [[Float]], to url: URL, key: String, startsFile: Bool) async throws {
        guard let dimension = vectors.first?.count, dimension > 0 else { return }
        if startsFile || !FileManager.default.fileExists(atPath: url.path) {
            try Data(key.utf8).write(to: url.appendingPathExtension("key"), options: .atomic)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = Data()
        data.reserveCapacity(vectors.count * dimension * MemoryLayout<Float>.size)
        for vector in vectors {
            vector.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        let bytesPerVector = UInt64(dimension * MemoryLayout<Float>.size)
        if end % bytesPerVector != 0 {
            try handle.truncate(atOffset: end - end % bytesPerVector)
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: data)
    }
}

/// An import in pieces that could not go on.
nonisolated struct TextStreamingImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension RAGService {
    /// The text of every committed piece, kept until the last one is in and then stored once.
    private static let keptTextFileName = "document_text.txt"

    /// Imports a large text or JSON Lines file a piece at a time.
    ///
    /// Each piece is a few megabytes of whole lines (`TextPieceReader`). It is cleaned, cut into
    /// passages and embedded by the same code a small file goes through, its chunks are written
    /// to the vector store and the search index, and a checkpoint is saved. Memory stays near
    /// what one piece needs whatever the file's size, and an interruption costs one piece.
    ///
    /// A JSON Lines file keeps its record numbers across pieces ("Record 2000 of 189579"), and
    /// its short records share passages (`JSONRecordExtractor.packedRanges`). The document's own
    /// text is stored once at the end: appending it piece by piece rewrote all of it each time.
    func importLargeTextStreamed(
        at url: URL,
        trackingId: UUID,
        filename: String,
        activeContainerId: UUID,
        documentType: DocumentType,
        chunkOverride: DocumentProcessor.ChunkingOverride?,
        providerId: String,
        containerEmbeddingService: EmbeddingService
    ) async throws {
        let startedAt = Date()
        let reader = try TextPieceReader(url: url)
        let fileExtension = url.pathExtension.lowercased()
        let holdsRecords = JSONRecordExtractor.isLineDelimited(fileExtension)

        let fingerprint = documentProcessor.computeDocumentFingerprint(at: url)
        let checkpointDir = documentProcessor.checkpointDirectoryURL(for: fingerprint)
        let stateURL = checkpointDir.appendingPathComponent(TextStreamingIngestionState.fileName)
        let keptTextURL = checkpointDir.appendingPathComponent(Self.keptTextFileName)
        let pieceDir = checkpointDir.appendingPathComponent("piece", isDirectory: true)
        try FileManager.default.createDirectory(at: pieceDir, withIntermediateDirectories: true)
        // The piece has the file's own name, so the processor reads it as the same kind of file.
        // A `.json` file this large is read as text already, and a piece of it is not JSON.
        let pieceName = holdsRecords || documentType != .json ? url.lastPathComponent : url.lastPathComponent + ".txt"
        let pieceURL = pieceDir.appendingPathComponent(pieceName)

        let db = try await dbForContainer(activeContainerId)

        updateIngestionItem(
            id: trackingId, filename: filename, stage: .loading, detail: "Measuring the file", progress: 0)

        // An import picks its library when it starts, and a resumed import starts again. If the
        // library on screen changed in between, the pieces already in are in the other one. A
        // document cannot be half in each, so those are removed and the file starts over here.
        if let earlier = TextStreamingIngestionState.read(at: stateURL), let earlierLibrary = earlier.containerId,
            earlierLibrary != activeContainerId
        {
            Log.warning(
                "[RAGService] \(filename): \(earlier.committed.completedPieces) part(s) were imported into another library; "
                    + "removing them and starting over in this one",
                category: .ingestion)
            if let earlierDB = try? await dbForContainer(earlierLibrary) {
                try? await removeStreamedTextChunks(documentId: earlier.documentId, from: earlierDB)
            }
            try? FileManager.default.removeItem(at: stateURL)
        }

        var state: TextStreamingIngestionState
        if var saved = TextStreamingIngestionState.read(at: stateURL), saved.fileBytes == reader.count,
            saved.pieceBytes == TextPieceReader.pieceBytes
        {
            if let pending = saved.pending {
                let vectorChunks = try await db.chunkCount(forDocument: saved.documentId)
                let indexChunks = await SQLiteFullTextService.shared.retrieveChunks(for: saved.documentId).count
                var recovery = TextStreamingIngestionState.recovery(
                    committedChunks: saved.committed.totalChunks, pendingChunks: pending.totalChunks,
                    vectorChunks: vectorChunks, indexChunks: indexChunks)
                var missingIndexRows: [SearchIndexRow] = []
                if recovery == .finishIndex {
                    let stored = try await db.chunks(forDocument: saved.documentId)
                    if let rows = Self.searchIndexRows(
                        forStored: stored, first: saved.committed.totalChunks,
                        count: pending.totalChunks - saved.committed.totalChunks)
                    {
                        missingIndexRows = rows
                    } else {
                        recovery = .startOver
                    }
                }
                Log.warning(
                    "[RAGService] \(filename): the app stopped while part \(pending.completedPieces) was being stored "
                        + "(vector store \(vectorChunks), search index \(indexChunks), committed \(saved.committed.totalChunks)): \(recovery)",
                    category: .ingestion)
                switch recovery {
                case .pieceWentIn:
                    saved.committed = pending
                    saved.pending = nil
                case .finishIndex:
                    await SQLiteFullTextService.shared.storeChunks(
                        documentId: saved.documentId,
                        containerId: activeContainerId,
                        chunks: missingIndexRows,
                        append: true
                    )
                    saved.committed = pending
                    saved.pending = nil
                case .redoPiece, .nothingPending:
                    saved.pending = nil
                case .startOver:
                    try await removeStreamedTextChunks(documentId: saved.documentId, from: db)
                    saved = try await Self.newTextStreamingState(
                        reader: reader, holdsRecords: holdsRecords, containerId: activeContainerId)
                }
                try saved.write(to: stateURL)
            }
            state = saved
            state.containerId = state.containerId ?? activeContainerId
            Log.info(
                "[RAGService] Resuming \(filename) at part \(state.committed.completedPieces + 1) of \(state.totalPieces) "
                    + "(\(state.committed.totalChunks) chunks committed)",
                category: .ingestion)
        } else {
            state = try await Self.newTextStreamingState(
                reader: reader, holdsRecords: holdsRecords, containerId: activeContainerId)
            try state.write(to: stateURL)
            Log.info(
                "[RAGService] Importing \(filename) in \(state.totalPieces) parts"
                    + (state.totalRecords.map { " (\($0) records)" } ?? ""),
                category: .ingestion)
        }

        do {
            try await importTextPieces(
                reader: reader, state: &state, stateURL: stateURL, keptTextURL: keptTextURL, pieceURL: pieceURL,
                trackingId: trackingId, filename: filename, activeContainerId: activeContainerId,
                chunkOverride: chunkOverride, providerId: providerId,
                containerEmbeddingService: containerEmbeddingService, db: db)
        } catch {
            // Once the task is cancelled, whatever comes back is the cancellation.
            let wasCancelled = error is CancellationError || Task.isCancelled
            if wasCancelled, isIngestionCancellationRequested(trackingId) {
                // The person cancelled. Nothing of the document is kept, and the same file
                // imported later starts from its first line.
                try? await removeStreamedTextChunks(documentId: state.documentId, from: db)
                documentProcessor.cleanCheckpoints(for: url)
                Log.info("[RAGService] \(filename): cancelled; its parts were removed", category: .ingestion)
            }
            if wasCancelled { throw CancellationError() }
            throw error
        }

        guard state.committed.totalChunks > 0 else {
            documentProcessor.cleanCheckpoints(for: url)
            throw DocumentProcessingError.emptyDocument
        }

        // The document's own text, stored once now that every piece is in.
        updateIngestionItem(
            id: trackingId, filename: filename, stage: .storing, detail: "Saving the document's text", progress: 0.97)
        let fullText = try await Self.readKeptText(at: keptTextURL)
        await SQLiteFullTextService.shared.store(text: fullText, for: state.documentId, containerId: activeContainerId)

        let document = Document(
            id: state.documentId,
            filename: filename,
            fileURL: url,
            contentType: documentType,
            totalChunks: state.committed.totalChunks,
            containerId: activeContainerId
        )
        if !documents.contains(where: { $0.id == document.id }) {
            documents.append(document)
        }
        syncContainerStats(for: activeContainerId, lastIndexedAt: Date())
        noteStreamedImportFinished(in: activeContainerId)
        await saveDocumentsToDisk()

        // The document is in the catalog. The pieces, the checkpoint and the kept text go now,
        // before the questions, which can take a while and are not worth a restart.
        documentProcessor.cleanCheckpoints(for: url)

        updateIngestionItem(
            id: trackingId, filename: filename, stage: .storing, detail: "Generating suggested questions...",
            progress: 0.99)
        let sample = try await db.chunks(forDocument: document.id, limit: Self.suggestedQuestionSample)
        await SuggestedQuestionsService.shared.generateQuestionsForIngestedDocument(
            document, chunks: sample, in: activeContainerId)

        let committed = state.committed
        let pieces = state.totalPieces
        let elapsed = Date().timeIntervalSince(startedAt)
        updateIngestionItem(
            id: trackingId, filename: filename, stage: .complete,
            detail: "Imported in \(pieces) part\(pieces == 1 ? "" : "s")", progress: 1.0
        ) { metrics in
            metrics.totalWords = committed.totalWords
            metrics.chunkCount = committed.totalChunks
            metrics.extractionTimeMs = Int(elapsed * 1000)
        }
        Log.info(
            "[RAGService] \(filename): imported \(committed.totalChunks) chunks from \(pieces) parts in "
                + "\(String(format: "%.0f", elapsed))s",
            category: .ingestion)

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.removeIngestionItem(id: trackingId)
        }
    }

    /// Chunks handed to the suggested-questions step. It reads a document's opening, and a
    /// document imported in pieces can hold tens of thousands of chunks.
    private static let suggestedQuestionSample = 60

    // MARK: Pieces

    private func importTextPieces(
        reader: TextPieceReader,
        state: inout TextStreamingIngestionState,
        stateURL: URL,
        keptTextURL: URL,
        pieceURL: URL,
        trackingId: UUID,
        filename: String,
        activeContainerId: UUID,
        chunkOverride: DocumentProcessor.ChunkingOverride?,
        providerId: String,
        containerEmbeddingService: EmbeddingService,
        db: VectorDatabase
    ) async throws {
        // The processor's own progress reports are per piece and would move the bar back to the
        // start of "extracting" for each one. The bar here is the share of the file that is in.
        documentProcessor.progressHandler = nil
        documentProcessor.richProgressHandler = nil

        let holdsRecords = state.totalRecords != nil
        let prefix = "\(filename): "
        let embeddingWindow = containerEmbeddingService.maxSafeTokens
        let totalBytes = max(1, reader.count)

        // Whatever a stopped run appended for a piece it did not commit is cut off.
        try await Self.truncateKeptText(at: keptTextURL, toBytes: state.committed.keptTextBytes)

        while state.committed.completedBytes < reader.count {
            try Task.checkCancellation()

            let start = state.committed.completedBytes
            let end = reader.pieceEnd(
                from: start, targetBytes: state.pieceBytes,
                longestLine: state.longestLineBytes ?? TextPieceReader.longestLineBytes)
            let pieceNumber = state.committed.completedPieces + 1
            let label = "Part \(pieceNumber) of \(state.totalPieces)"
            let pieceWeight = Double(end - start) / Double(totalBytes)
            let fraction = Double(start) / Double(totalBytes)

            updateIngestionItem(
                id: trackingId, filename: filename, stage: Self.pieceStage, detail: "\(label): reading",
                progress: fraction * 0.96)

            let recordsInPiece = try await Self.writePiece(
                of: reader, range: start..<end, to: pieceURL, countsRecords: holdsRecords)

            var pieceText = ""
            let piece = DocumentProcessor.TextPiece(
                numbering: .init(first: state.committed.recordsDone + 1, total: state.totalRecords),
                keepText: { pieceText = $0 })
            // A piece that holds only blank lines has nothing to import and is not an error.
            let processedChunks: [DocumentProcessor.ProcessedChunk]
            do {
                processedChunks = try await documentProcessor.processDocument(
                    at: pieceURL,
                    chunkOverride: chunkOverride,
                    containerId: activeContainerId,
                    documentId: state.documentId,
                    textPiece: piece
                ).1
            } catch DocumentProcessingError.emptyDocument {
                processedChunks = []
            }
            try Task.checkCancellation()

            // The piece's numbers become the document's: chunk indexes go on from the piece
            // before, and positions are offsets into the document's kept text.
            let isFirstPiece = state.committed.keptTextBytes == 0
            let chunkBase = state.committed.totalChunks
            let positionBase = state.committed.keptTextChars + (isFirstPiece ? 0 : Self.pieceSeparator.count)
            let metadata = Self.documentNumbered(
                processedChunks.map(\.metadata), chunkBase: chunkBase, positionBase: positionBase)

            updateIngestionItem(
                id: trackingId, filename: filename, stage: Self.pieceStage,
                detail: "\(label): embedding \(processedChunks.count.formatted(.number)) passages",
                progress: (fraction + pieceWeight * 0.3) * 0.96)

            var textsToEmbed: [String] = []
            textsToEmbed.reserveCapacity(processedChunks.count)
            var passagesAtTheWindow = 0
            for chunk in processedChunks {
                let forEmbedding = Self.embeddingText(
                    prefix: prefix, passage: chunk.text, window: embeddingWindow,
                    countTokens: { containerEmbeddingService.countTokens($0) })
                if forEmbedding.reachesWindow { passagesAtTheWindow += 1 }
                textsToEmbed.append(forEmbedding.text)
            }
            if passagesAtTheWindow > 0 {
                Log.warning(
                    "[RAGService] \(filename): \(label): \(passagesAtTheWindow) of \(processedChunks.count) passages "
                        + "reach the embedding model's \(embeddingWindow)-token window; the vector of each covers "
                        + "its first \(embeddingWindow) tokens and the stored text is whole",
                    category: .ingestion)
            }
            // The passages are embedded a slice at a time, and each slice's vectors are written
            // beside the checkpoint as soon as they exist. A piece of the file that prompted this
            // is 3,000 to 4,000 passages and one to three minutes of embedding on an iPhone. As one
            // call it showed no progress for that long, a cancel was not seen until it returned,
            // and an interruption threw all of it away, so a person who left the app every minute
            // never got past the first piece. Now a piece that is started again reads back what it
            // had embedded and goes on from there.
            let passageCount = processedChunks.count
            let vectorsURL = keptTextURL.deletingLastPathComponent().appendingPathComponent(TextPieceVectors.fileName)
            let vectorsKey = TextPieceVectors.key(
                pieceNumber: pieceNumber, texts: textsToEmbed, dimension: containerEmbeddingService.outputDimension,
                providerId: providerId)
            var embeddings = await TextPieceVectors.read(
                at: vectorsURL, key: vectorsKey, dimension: containerEmbeddingService.outputDimension,
                limit: passageCount)
            if !embeddings.isEmpty {
                Log.info(
                    "[RAGService] \(filename): \(label) had \(embeddings.count) of \(passageCount) passages embedded before it was stopped; going on from there",
                    category: .ingestion)
            }
            let embeddingStarted = Date()
            let embeddedBefore = embeddings.count
            var reportSeconds = 0.0
            while embeddings.count < passageCount {
                try Task.checkCancellation()
                let sliceEnd = min(embeddings.count + Self.passagesInASlice, passageCount)
                let slice = Array(textsToEmbed[embeddings.count..<sliceEnd])
                let vectors = try await containerEmbeddingService.generateEmbeddings(for: slice)
                guard vectors.count == slice.count else {
                    throw TextStreamingImportError(
                        message: "\(label) of \(filename): \(vectors.count) embeddings came back for \(slice.count) passages")
                }
                try EmbeddingVectorCheck.requireUsable(vectors, of: filename)
                try await TextPieceVectors.append(vectors, to: vectorsURL, key: vectorsKey, startsFile: embeddings.isEmpty)
                embeddings.append(contentsOf: vectors)

                let reportStarted = Date()
                let share = Double(embeddings.count) / Double(max(1, passageCount))
                updateIngestionItem(
                    id: trackingId, filename: filename, stage: Self.pieceStage,
                    detail:
                        "\(label): embedding \(embeddings.count.formatted(.number)) of \(passageCount.formatted(.number)) passages",
                    progress: (fraction + pieceWeight * (0.3 + 0.6 * share)) * 0.96,
                    savesQueue: false)
                reportSeconds += Date().timeIntervalSince(reportStarted)
            }
            let embeddingSeconds = Date().timeIntervalSince(embeddingStarted)
            let embeddedNow = passageCount - embeddedBefore
            if embeddedNow > 0 {
                // Where a piece's time goes, for the trace: the rate, and how much of it was the
                // progress reports themselves.
                Log.info(
                    "[RAGService] \(filename): \(label) embedded \(embeddedNow) passages in "
                        + "\(String(format: "%.1f", embeddingSeconds))s (\(String(format: "%.1f", Double(embeddedNow) / max(0.01, embeddingSeconds))) a second; "
                        + "progress reports took \(String(format: "%.1f", reportSeconds))s of it)",
                    category: .ingestion)
            }
            try Task.checkCancellation()
            guard embeddings.count == processedChunks.count else {
                throw TextStreamingImportError(
                    message:
                        "\(label) of \(filename): \(embeddings.count) embeddings came back for \(processedChunks.count) passages")
            }

            var vectorChunks: [DocumentChunk] = []
            vectorChunks.reserveCapacity(processedChunks.count)
            for index in processedChunks.indices {
                vectorChunks.append(
                    DocumentChunk(
                        id: UUID(),
                        documentId: state.documentId,
                        content: processedChunks[index].text,
                        parentContent: processedChunks[index].parentText,
                        contextualPrefix: prefix,
                        embedding: embeddings[index],
                        metadata: metadata[index]
                    ))
            }
            let indexChunks = Self.searchIndexRows(for: processedChunks, metadata: metadata)

            // From here to the second state write nothing checks for cancellation: a piece is
            // either committed or not started, unless the app is ended in between, which is what
            // `pending` is for.
            let kept = try await Self.appendKeptText(
                pieceText, to: keptTextURL, afterBytes: state.committed.keptTextBytes, isFirst: isFirstPiece)

            var next = state.committed
            next.completedBytes = end
            next.completedPieces += 1
            next.recordsDone += recordsInPiece
            next.totalChunks += processedChunks.count
            // The piece's own text, not its passages: passages overlap, so their counts summed counted
            // the overlap twice (5.7).
            next.totalWords += DocumentProcessor.wordCount(of: pieceText)
            next.totalChars += processedChunks.reduce(0) { $0 + $1.metadata.characterCount }
            next.keptTextBytes += kept.bytes
            next.keptTextChars += kept.characters

            updateIngestionItem(
                id: trackingId, filename: filename, stage: Self.pieceStage,
                detail: "\(label): saving \(next.totalChunks.formatted(.number)) passages so far",
                progress: (fraction + pieceWeight * 0.9) * 0.96)

            if !vectorChunks.isEmpty {
                state.pending = next
                try state.write(to: stateURL)

                // The vector store first, and all the way to disk, then the search index. The two
                // saves run in a task of their own, so a cancellation (iOS taking the background
                // task back) cannot land between them. The app being ended can, and the restart
                // then finishes the index from the stored chunks (`Recovery.finishIndex`).
                let documentId = state.documentId
                try await Task { [vectorChunks] in
                    try await db.storeBatch(chunks: vectorChunks)
                    try await db.persist()
                    await SQLiteFullTextService.shared.storeChunks(
                        documentId: documentId,
                        containerId: activeContainerId,
                        chunks: indexChunks,
                        append: true
                    )
                }.value
            }

            state.committed = next
            state.pending = nil
            try state.write(to: stateURL)

            Log.info(
                "[RAGService] \(filename): \(label) committed, \(processedChunks.count) chunks (\(next.totalChunks) in all)",
                category: .ingestion)
        }
    }

    /// The queue stage shown for every piece. One stage for the whole loop: each change of
    /// stage is a haptic, a save of the queue and a Live Activity update, and a file of forty
    /// pieces that went reading, embedding, saving for each would do all three 120 times.
    private static let pieceStage = IngestionStage.embedding

    /// Passages embedded in one call. After each slice its vectors are kept and progress is
    /// reported, so this is also the most embedding an interruption costs.
    private static let passagesInASlice = 96

    /// A blank line between one piece's text and the next in the document's stored text.
    nonisolated private static let pieceSeparator = "\n\n"

    // MARK: Off the main actor

    /// A new import: a new document id, the number of pieces, and for JSON Lines the number of
    /// records in the file. Both counts are a pass over the mapped file.
    @concurrent
    private static func newTextStreamingState(
        reader: TextPieceReader, holdsRecords: Bool, containerId: UUID
    ) async throws -> TextStreamingIngestionState {
        // A record is one line and is never cut while it is a size the record reader takes:
        // cut in two, its halves would be two lines that are not JSON, and every record after
        // them would be numbered one too high.
        let longestLine = holdsRecords ? JSONRecordExtractor.maxFileBytes : TextPieceReader.longestLineBytes
        return TextStreamingIngestionState(
            documentId: UUID(),
            containerId: containerId,
            fileBytes: reader.count,
            pieceBytes: TextPieceReader.pieceBytes,
            longestLineBytes: longestLine,
            totalPieces: reader.pieceRanges(longestLine: longestLine).count,
            totalRecords: holdsRecords ? reader.nonBlankLineCount(in: 0..<reader.count) : nil
        )
    }

    /// Writes one piece to its own file and returns the records in it (0 unless asked).
    @concurrent
    private static func writePiece(
        of reader: TextPieceReader, range: Range<Int>, to url: URL, countsRecords: Bool
    ) async throws -> Int {
        try reader.bytes(in: range).write(to: url, options: .atomic)
        return countsRecords ? reader.nonBlankLineCount(in: range) : 0
    }

    /// Appends a piece's text to the kept document text, at `afterBytes` exactly, so a piece that
    /// is imported a second time replaces what its first try wrote.
    @concurrent
    private static func appendKeptText(
        _ text: String, to url: URL, afterBytes: Int, isFirst: Bool
    ) async throws -> (bytes: Int, characters: Int) {
        let addition = isFirst ? text : pieceSeparator + text
        let data = Data(addition.utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(afterBytes))
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        return (data.count, addition.count)
    }

    @concurrent
    private static func truncateKeptText(at url: URL, toBytes bytes: Int) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(bytes))
    }

    @concurrent
    private static func readKeptText(at url: URL) async throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Stores

    /// Takes every chunk of a document imported in pieces out of both stores.
    func removeStreamedTextChunks(documentId: UUID, from db: VectorDatabase) async throws {
        try await db.deleteChunks(forDocument: documentId)
        try await db.persist()
        await SQLiteFullTextService.shared.deleteChunks(for: documentId)
        await SQLiteFullTextService.shared.delete(for: documentId)
    }

    /// For a queue item that is being discarded: if the file was part-way through an import in
    /// pieces, its committed chunks are removed. They belong to a document id that no document
    /// will have. Call it before the checkpoint folder is deleted, which is where the id is.
    func purgeStreamedTextImport(for url: URL, containerId: UUID?) {
        let fingerprint = documentProcessor.computeDocumentFingerprint(at: url)
        let stateURL = documentProcessor.checkpointDirectoryURL(for: fingerprint)
            .appendingPathComponent(TextStreamingIngestionState.fileName)
        guard let state = TextStreamingIngestionState.read(at: stateURL),
            let containerId = state.containerId ?? containerId
        else { return }
        Task {
            do {
                let db = try await self.dbForContainer(containerId)
                try await self.removeStreamedTextChunks(documentId: state.documentId, from: db)
                Log.info(
                    "[RAGService] Removed the committed parts of \(url.lastPathComponent), whose import was discarded",
                    category: .ingestion)
            } catch {
                Log.error(
                    "[RAGService] Could not remove the committed parts of \(url.lastPathComponent): \(error)",
                    category: .ingestion)
            }
        }
    }

    typealias SearchIndexRow = (
        chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
        sectionPath: String?, structureType: String?, chunkType: String?,
        tableTitle: String?, content: String,
        structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?
    )

    /// A piece's chunk metadata with the document's numbers: chunks are numbered by place, on
    /// from `chunkBase`, as the whole-file path numbers them by place in the document, and
    /// positions move by `positionBase`. The processor's own numbers repeat: a passage split for
    /// the token limit gives its parts the parent's number plus 0, 1, 2 (`createSubChunk`),
    /// which are the numbers of the passages after it, and a search-index hit finds its vector
    /// by document and number.
    static func documentNumbered(
        _ metadata: [ChunkMetadata], chunkBase: Int, positionBase: Int
    ) -> [ChunkMetadata] {
        metadata.enumerated().map { place, meta in
            meta.moved(chunkIndexBy: chunkBase + place - meta.chunkIndex, positionBy: positionBase)
        }
    }

    /// The search-index rows for a piece whose chunks are read back from the vector store: the
    /// piece's vectors were saved and its index rows were not. `chunks` is every stored chunk of
    /// the document in the order the store holds them, which is the order they were added, so
    /// the piece is the last `count` of them after the `first` that were committed. Nil when the
    /// store does not hold exactly that many, or when one of the piece's chunks is a table,
    /// whose row needs a payload the vector store does not keep.
    nonisolated static func searchIndexRows(
        forStored chunks: [DocumentChunk], first: Int, count: Int
    ) -> [SearchIndexRow]? {
        guard count > 0, first >= 0, chunks.count == first + count else { return nil }
        var rows: [SearchIndexRow] = []
        rows.reserveCapacity(count)
        for chunk in chunks.suffix(count) {
            let meta = chunk.metadata
            guard meta.tableTitle == nil else { return nil }
            rows.append(
                (
                    chunkIndex: meta.chunkIndex,
                    pageNumber: meta.pageNumber,
                    sectionTitle: meta.sectionTitle,
                    sectionPath: meta.sectionPath?.joined(separator: " > "),
                    structureType: meta.structureType,
                    chunkType: meta.chunkType?.rawValue,
                    tableTitle: nil,
                    content: chunk.content,
                    structuredMetadata: nil
                ))
        }
        return rows
    }

    /// The search-index rows for a piece's chunks, with the document's chunk numbers.
    private static func searchIndexRows(
        for chunks: [DocumentProcessor.ProcessedChunk], metadata: [ChunkMetadata]
    ) -> [SearchIndexRow] {
        var rows: [SearchIndexRow] = []
        rows.reserveCapacity(chunks.count)
        for (chunk, meta) in zip(chunks, metadata) {
            var structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?
            if let tableTitle = meta.tableTitle, let payload = chunk.structuredTable {
                structuredMetadata = SQLiteFullTextService.StructuredChunkMetadata(
                    chunkType: meta.chunkType?.rawValue,
                    tableTitle: tableTitle,
                    headers: payload.headers,
                    rows: payload.rows,
                    searchText: payload.title,
                    extractionQuality: payload.extractionQuality,
                    extractionSource: payload.extractionSource,
                    lowQualityRowIndices: payload.lowQualityRowIndices
                )
            }
            rows.append(
                (
                    chunkIndex: meta.chunkIndex,
                    pageNumber: meta.pageNumber,
                    sectionTitle: meta.sectionTitle,
                    sectionPath: meta.sectionPath?.joined(separator: " > "),
                    structureType: meta.structureType,
                    chunkType: meta.chunkType?.rawValue,
                    tableTitle: meta.tableTitle,
                    content: chunk.text,
                    structuredMetadata: structuredMetadata
                ))
        }
        return rows
    }
}

extension RAGService {
    /// The text one passage is embedded from: the document's prefix and the passage, whole
    /// whenever the embedding model can read all of it.
    ///
    /// Until 2026-10-10 both large-file paths cut any passage over 500 tokens to its first 1,500
    /// characters before embedding and logged nothing. That is about 350 tokens, so a passage a
    /// few tokens over lost a third of what the model could have read from it. The stored text
    /// and the keyword index were always whole; only the vector was short. Now a passage goes to
    /// the model whole when it fits the window, and one that does not is cut at the last
    /// character that still fits. `reachesWindow` is true for a passage at or over the window,
    /// because a tokenizer that stops counting at the window gives a longer passage the same
    /// count as one that fits exactly.
    nonisolated static func embeddingText(
        prefix: String, passage: String, window: Int, countTokens: (String) -> Int
    ) -> (text: String, reachesWindow: Bool) {
        let whole = prefix + passage
        let count = countTokens(whole)
        guard window > 0, count > window else { return (whole, window > 0 && count >= window) }
        var low = 0
        var high = whole.count
        while low < high {
            let middle = (low + high + 1) / 2
            if countTokens(String(whole.prefix(middle))) <= window {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return (String(whole.prefix(low)), true)
    }
}

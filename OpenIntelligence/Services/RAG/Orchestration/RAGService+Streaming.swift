import Foundation
import OSLog
import CoreML
import NaturalLanguage
import PDFKit

// MARK: - Large Document Streaming Ingestion
struct StreamingIngestionState: Codable {
    let documentId: UUID
    let lastCompletedPage: Int
    let totalChunks: Int
    let totalWords: Int
    let totalChars: Int
}

extension RAGService {

    /// Streams large PDFs in batches of pages to prevent OOM crashes during extraction and embedding.
    func importLargePDFStreamed(
        at url: URL,
        trackingId: UUID,
        filename: String,
        activeContainerId: UUID,
        chunkOverride: DocumentProcessor.ChunkingOverride?,
        providerId: String,
        embeddingDim: Int,
        containerEmbeddingService: EmbeddingService
    ) async throws {
        Log.info("[RAGService] Streaming large PDF ingestion for \(filename)", category: .ingestion)
        
        let extractionStartTime = Date()
        
        // Compute fingerprint and checkpoint path
        let fingerprint = documentProcessor.computeDocumentFingerprint(at: url)
        let checkpointDir = documentProcessor.checkpointDirectoryURL(for: fingerprint)
        let stateURL = checkpointDir.appendingPathComponent("ingestion_state.json")
        
        var documentId = UUID()
        var lastCompletedPage: Int? = nil
        var totalChunks = 0
        var totalWords = 0
        var totalChars = 0
        
        // Restore session state if it exists
        if let stateData = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(StreamingIngestionState.self, from: stateData) {
            documentId = state.documentId
            lastCompletedPage = state.lastCompletedPage
            totalChunks = state.totalChunks
            totalWords = state.totalWords
            totalChars = state.totalChars
            Log.info("[RAGService] Restored streaming ingestion session for \(filename): documentId=\(documentId), lastCompletedPage=\(state.lastCompletedPage), chunks=\(totalChunks)", category: .ingestion)
        } else {
            let initialState = StreamingIngestionState(
                documentId: documentId,
                lastCompletedPage: -1,
                totalChunks: 0,
                totalWords: 0,
                totalChars: 0
            )
            if let initialData = try? JSONEncoder().encode(initialState) {
                try? initialData.write(to: stateURL, options: .atomic)
            }
        }
        
        // Find total pages
        let pdfDoc = PDFDocument(url: url)
        let totalPages = pdfDoc?.pageCount ?? 100 // fallback if unknown
        
        let batchSize = 15 // 15 pages per batch to keep memory strictly under 300MB
        // The container this import targets, not whichever one is on screen when the loop runs.
        // This function already takes `activeContainerId` and uses it for every other write; the
        // vector store was the one place it read the live value instead, and a streamed import is
        // the longest-running kind, so it had the widest window to diverge. See `dbForContainer`.
        let db = await dbForContainer(activeContainerId)
        
        for startPage in stride(from: 0, to: totalPages, by: batchSize) {
            let endPage = min(startPage + batchSize - 1, totalPages - 1)
            let pageRange = startPage...endPage
            
            // Skip already fully processed batches
            if let lastPage = lastCompletedPage, endPage <= lastPage {
                Log.info("[RAGService] Skipping already ingested batch: Pages \(startPage+1)-\(endPage+1)", category: .ingestion)
                continue
            }
            
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .extracting,
                    detail: "Batch \((startPage / batchSize) + 1): Pages \(startPage+1)-\(endPage+1) of \(totalPages)...",
                    progress: Double(startPage) / Double(totalPages)
                )
            }
            
            try Task.checkCancellation()
            
            // 1. Process Batch
            let (doc, processedChunks) = try await documentProcessor.processDocument(
                at: url,
                chunkOverride: chunkOverride,
                containerId: activeContainerId,
                pageRange: pageRange,
                documentId: documentId
            )
            
            guard !processedChunks.isEmpty else { continue }
            
            let batchWordCount = processedChunks.reduce(0) { $0 + $1.metadata.wordCount }
            totalChunks += processedChunks.count
            totalWords += batchWordCount
            totalChars += processedChunks.reduce(0) { $0 + $1.metadata.characterCount }
            
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .embedding,
                    detail: "Vectorizing batch \((startPage / batchSize) + 1) (\(processedChunks.count) chunks)",
                    progress: (Double(startPage) / Double(totalPages)) + 0.05
                )
            }
            
            // 2. Embed Batch
            var textsToEmbed: [String] = []
            let prefix = "\(doc.filename): "
            let maxTokens = containerEmbeddingService.outputDimension == 384 ? 500 : 8000
            
            for chunk in processedChunks {
                var textForEmbedding = prefix + chunk.text
                if containerEmbeddingService.countTokens(textForEmbedding) > maxTokens {
                    textForEmbedding = String(textForEmbedding.prefix(1500))
                }
                textsToEmbed.append(textForEmbedding)
            }
            
            let batchEmbeddings = try await containerEmbeddingService.generateEmbeddings(for: textsToEmbed)
            
            // 3. Store in DB
            var dbChunks: [DocumentChunk] = []
            for (chunk, embedding) in zip(processedChunks, batchEmbeddings) {
                let uniqueChunkId = UUID()
                dbChunks.append(DocumentChunk(
                    id: uniqueChunkId,
                    documentId: documentId,
                    content: chunk.text,
                    parentContent: chunk.parentText,
                    contextualPrefix: prefix,
                    embedding: embedding,
                    metadata: chunk.metadata
                ))
            }
            
            try await db.storeBatch(chunks: dbChunks)
            
            // 4. Store Chunks in FTS5 Index
            let fts5ChunkData = processedChunks.map { chunk -> (
                chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
                sectionPath: String?, structureType: String?, chunkType: String?,
                tableTitle: String?, content: String,
                structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?
            ) in
                let pathStr = chunk.metadata.sectionPath?.joined(separator: " > ")
                var structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata? = nil
                if let rawTable = chunk.metadata.tableTitle, let payload = chunk.structuredTable {
                    structuredMetadata = SQLiteFullTextService.StructuredChunkMetadata(
                        chunkType: chunk.metadata.chunkType?.rawValue,
                        tableTitle: rawTable,
                        headers: payload.headers,
                        rows: payload.rows,
                        searchText: payload.title,
                        extractionQuality: payload.extractionQuality,
                        extractionSource: payload.extractionSource,
                        lowQualityRowIndices: payload.lowQualityRowIndices
                    )
                }
                return (
                    chunkIndex: chunk.metadata.chunkIndex,
                    pageNumber: chunk.metadata.pageNumber,
                    sectionTitle: chunk.metadata.sectionTitle,
                    sectionPath: pathStr,
                    structureType: chunk.metadata.structureType,
                    chunkType: chunk.metadata.chunkType?.rawValue,
                    tableTitle: chunk.metadata.tableTitle,
                    content: chunk.text,
                    structuredMetadata: structuredMetadata
                )
            }
            
            await SQLiteFullTextService.shared.storeChunks(
                documentId: documentId,
                containerId: activeContainerId,
                chunks: fts5ChunkData,
                append: true
            )
            
            // Flush to vector DB binary files immediately for crash and sleep resilience
            try await db.persist()
            
            // Save state progress after successful DB and FTS commits
            let state = StreamingIngestionState(
                documentId: documentId,
                lastCompletedPage: endPage,
                totalChunks: totalChunks,
                totalWords: totalWords,
                totalChars: totalChars
            )
            if let stateData = try? JSONEncoder().encode(state) {
                try? stateData.write(to: stateURL, options: .atomic)
            }
            
            Log.info("[RAGService] Streamed and persisted batch \((startPage / batchSize) + 1): \(processedChunks.count) chunks", category: .ingestion)
        }
        
        let extractionTime = Date().timeIntervalSince(extractionStartTime)
        
        // Finalize metadata and cache refresh
        let document = Document(
            id: documentId,
            filename: filename,
            fileURL: url,
            contentType: .pdf,
            totalChunks: totalChunks,
            containerId: activeContainerId
        )
        
        await MainActor.run {
            self.documents.append(document)
            self.syncContainerStats(for: activeContainerId, lastIndexedAt: Date())
        }
        
        // Synchronously save document metadata to disk before yielding/generating suggested questions
        await saveDocumentsToDisk()
        
        // Generate suggested questions for the document using its ingested chunks
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .storing,
                detail: "Generating suggested questions...",
                progress: 0.99
            )
        }
        
        let documentChunks = (try? await db.allChunks())?.filter { $0.documentId == documentId } ?? []
        await SuggestedQuestionsService.shared.generateQuestionsForIngestedDocument(
            document,
            chunks: documentChunks,
            in: activeContainerId
        )
        
        await MainActor.run {
            updateIngestionItem(id: trackingId, filename: filename, stage: .complete, detail: "Ingested \(totalPages) pages in batches") { metrics in
                metrics.totalWords = totalWords
                metrics.chunkCount = totalChunks
                metrics.extractionTimeMs = Int(extractionTime * 1000)
            }
            
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.removeIngestionItem(id: trackingId)
            }
        }
        
        // Clean up temporary page checkpoints and session state files on successful ingestion completion
        documentProcessor.cleanCheckpoints(for: url)
    }
}

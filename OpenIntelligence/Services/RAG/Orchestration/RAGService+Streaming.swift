import Foundation
import OSLog
import CoreML
import NaturalLanguage
import PDFKit

// MARK: - Large Document Streaming Ingestion
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
        Log.info("[RAGService] Streaming large PDF ingestion for \\(filename)", category: .ingestion)
        
        let extractionStartTime = Date()
        let documentId = UUID()
        
        // Find total pages
        let pdfDoc = PDFDocument(url: url)
        let totalPages = pdfDoc?.pageCount ?? 100 // fallback if unknown
        
        var totalChunks = 0
        var totalWords = 0
        var totalChars = 0
        
        let batchSize = 15 // 15 pages per batch to keep memory strictly under 300MB
        
        let db = await dbForActiveContainer()
        
        
        for startPage in stride(from: 0, to: totalPages, by: batchSize) {
            let endPage = min(startPage + batchSize - 1, totalPages - 1)
            let pageRange = startPage...endPage
            
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .extracting,
                    detail: "Batch \\((startPage / batchSize) + 1): Pages \\(startPage+1)-\\(endPage+1) of \\(totalPages)...",
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
            
            Log.info("[RAGService] Streamed batch \((startPage / batchSize) + 1): \(processedChunks.count) chunks saved and indexed in FTS5", category: .ingestion)
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
            
            // Generate content tags asynchronously if iOS 26
            Task {
                await self.saveDocumentsToDisk()
            }
            updateIngestionItem(id: trackingId, filename: filename, stage: .complete, detail: "Ingested \\(totalPages) pages in batches") { metrics in
                metrics.totalWords = totalWords
                metrics.chunkCount = totalChunks
                metrics.extractionTimeMs = Int(extractionTime * 1000)
            }
            
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.removeIngestionItem(id: trackingId)
            }
        }
    }
}

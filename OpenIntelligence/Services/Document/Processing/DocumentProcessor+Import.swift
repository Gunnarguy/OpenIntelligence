//
//  DocumentProcessor+Import.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved unchanged from DocumentProcessor.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os
import CryptoKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision
import CoreImage
import Metal
import Tokenizers
import Compression
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif


extension DocumentProcessor {
    // MARK: - Public API

    /// Process a document and extract text chunks
    /// Also stores the full original text for exact queries:
    /// - SQLiteFullTextService (FTS5) when containerId is provided (10-100X faster search)
    /// - FullTextStorageService (file-based) as fallback when containerId is nil
    /// A text file over this many bytes is imported in pieces of whole lines
    /// (`RAGService.importLargeTextStreamed`) instead of being read, cleaned and chunked in one
    /// go. In one go the cost is many times the file: 88 MB held 2.8 GB on an iPhone on
    /// 2026-10-09 and the import never finished.
    nonisolated static let piecewiseTextBytes = 8 * 1_048_576

    /// Whether a file is imported in pieces. JSON Lines by its extension, plain text and Markdown;
    /// a `.json` file only above the size at which it is read as text already, because below it
    /// the whole file is one parsed value and a piece of that is not JSON.
    nonisolated static func importsInPieces(fileExtension: String, documentType: DocumentType, fileBytes: Int) -> Bool {
        guard fileBytes > piecewiseTextBytes else { return false }
        if JSONRecordExtractor.isLineDelimited(fileExtension.lowercased()) { return true }
        switch documentType {
        case .text, .markdown:
            return true
        case .json:
            return fileBytes > JSONRecordExtractor.maxFileBytes
        default:
            return false
        }
    }

    /// One piece of a large text or JSON Lines file that is imported in pieces
    /// (`RAGService.importLargeTextStreamed`). The piece is a file of its own that holds whole
    /// lines of the original and has the original's name.
    struct TextPiece {
        /// JSON Lines: the number of this piece's first record and the records in the whole file.
        var numbering = JSONRecordExtractor.Numbering()
        /// Takes the piece's cleaned text. The processor stores no document text for a piece: the
        /// caller keeps each piece's text and stores the document's once, when the last piece is
        /// in. Appending to the stored text piece by piece would rewrite all of it every time.
        var keepText: (String) throws -> Void = { _ in }
    }

    func processDocument(at url: URL, chunkOverride: ChunkingOverride? = nil, containerId: UUID? = nil, pageRange: ClosedRange<Int>? = nil, documentId: UUID? = nil, textPiece: TextPiece? = nil) async throws -> (Document, [ProcessedChunk]) {
        let __spProcessDocument = PipelineSignposts.ingestion.beginInterval("ProcessDocument")
        defer { PipelineSignposts.ingestion.endInterval("ProcessDocument", __spProcessDocument) }
        try Task.checkCancellation()
        // Reset ALL per-document state to prevent vocabulary/entity leaks between documents
        lastDetectedEntities = []
        currentDocumentCustomWords = OCRConfiguration.universalCustomWords
        currentDocumentRecognitionLanguages = nil
        // Reset StructuredDocumentParser singleton state
        if #available(iOS 26.0, *) {
            await StructuredDocumentParser.shared.setDocumentCustomWords(OCRConfiguration.universalCustomWords)
        }

        let filename = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let fileSizeMB = Double(fileSize) / 1_048_576.0

        Log.info("[DocumentProcessor] Processing \(filename) (\(String(format: "%.2f", fileSizeMB)) MB)", category: .ingestion)

    let startTime = Date()
    let documentId = documentId ?? UUID()
    var pagesProcessed: Int? = nil
    var ocrPagesCount: Int? = nil

        // Determine document type
        let documentType = detectDocumentType(url: url)
        try Task.checkCancellation()

        // ═══════════════════════════════════════════════════════════════
        // STREAMING PATH: Large XML files (>50 MB)
        // Uses SAX parser — never loads full file into memory.
        // Apple Health export.xml (2.4 GB) → ~100 dense aggregated chunks.
        // ═══════════════════════════════════════════════════════════════
        if documentType == .xml && fileSizeMB > 50 {
            Log.info("[DocumentProcessor] Large XML detected (\(String(format: "%.0f", fileSizeMB)) MB) — using streaming SAX parser", category: .ingestion)
            progressHandler?("streaming large XML…")
            let processor = StreamingXMLProcessor()
            processor.progressHandler = { [weak self] msg in
                self?.progressHandler?(msg)
            }
            let xmlChunks = try processor.processLargeXML(at: url)

            guard !xmlChunks.isEmpty else {
                throw DocumentProcessingError.emptyDocument
            }

            // Convert streaming chunks → ProcessedChunk
            let processedChunks: [ProcessedChunk] = xmlChunks.enumerated().map { index, chunk in
                let metadata = ChunkMetadata(
                    chunkIndex: index,
                    startPosition: 0,
                    endPosition: chunk.text.count,
                    pageNumber: nil,
                    sectionTitle: chunk.section,
                    keywords: [],
                    semanticDensity: 0.5,
                    hasNumericData: chunk.text.rangeOfCharacter(from: .decimalDigits) != nil,
                    hasListStructure: chunk.text.contains("\n•") || chunk.text.contains("\n-"),
                    wordCount: Self.wordCount(of: chunk.text),
                    characterCount: chunk.text.count,
                    structureType: "streamed_xml",
                    sectionPath: chunk.section.map { [$0] }
                )
                return ProcessedChunk(text: chunk.text, parentText: nil, metadata: metadata)
            }

            // Store aggregated text in FTS5 for full-text search
            let storedText = xmlChunks.map { chunk in
                let header = chunk.section.map { "--- \($0) ---\n" } ?? ""
                return header + chunk.text
            }.joined(separator: "\n\n")

            if let containerId = containerId {
                await SQLiteFullTextService.shared.store(text: storedText, for: documentId, containerId: containerId)
            } else {
                await FullTextStorageService.shared.store(text: storedText, for: documentId)
            }

            let totalTime = Date().timeIntervalSince(startTime)
            Log.info("[DocumentProcessor] Streaming XML complete: \(processedChunks.count) chunks in \(String(format: "%.1f", totalTime))s", category: .ingestion)

            let chunkLengths = processedChunks.map { $0.metadata.characterCount }
            let streamChunkStats = ChunkStatistics(
                averageChars: chunkLengths.isEmpty ? 0 : chunkLengths.reduce(0, +) / chunkLengths.count,
                minChars: chunkLengths.min() ?? 0,
                maxChars: chunkLengths.max() ?? 0
            )

            let metadata = ProcessingMetadata(
                fileSizeMB: fileSizeMB,
                totalCharacters: storedText.count,
                totalWords: Self.wordCount(of: storedText),
                extractionTimeSeconds: totalTime,
                chunkingTimeSeconds: 0,
                embeddingTimeSeconds: 0,
                totalProcessingTimeSeconds: totalTime,
                pagesProcessed: 1,
                ocrPagesCount: nil,
                chunkStats: streamChunkStats
            )

            let document = Document(
                id: documentId,
                filename: filename,
                fileURL: url,
                contentType: documentType,
                totalChunks: processedChunks.count,
                processingMetadata: metadata
            )

            return (document, processedChunks)
        }

        // ═══════════════════════════════════════════════════════════════
        // FILE SIZE GUARD: Reject non-streamable files > 500 MB
        // Loading a 500MB+ file into a String would consume 1.5-2 GB
        // with normalization copies — guaranteed OOM on 8 GB devices.
        // ═══════════════════════════════════════════════════════════════
        //
        // A PDF read in page ranges (`pageRange`, from `RAGService.importLargePDFStreamed`, which takes every PDF over
        // 10 MB) never holds the whole file as text, so the guard does not apply to it (5.7). It measured the whole
        // file on every page batch, so no PDF over 500 MB could be imported at all.
        let maxNonStreamableSizeMB: Double = 500
        if pageRange == nil, fileSizeMB > maxNonStreamableSizeMB && documentType != .xml {
            Log.error("[DocumentProcessor] File too large: \(String(format: "%.0f", fileSizeMB)) MB (limit: \(String(format: "%.0f", maxNonStreamableSizeMB)) MB)", category: .ingestion)
            throw DocumentProcessingError.fileTooLarge(sizeMB: fileSizeMB, limitMB: maxNonStreamableSizeMB)
        }
        Log.debug("[DocumentProcessor] Document type: \(documentType)", category: .ingestion)

        // Track structured elements for structure-aware chunking (iOS 26+ PDFs)
        var structuredElements: [StructuredElementWrapper] = []
        var usedStructuredParsing = false
        /// Set when a JSON or JSON Lines file was read as records; chunking then gives each its own passage.
        var jsonRecordCount: Int? = nil

        // Extract text based on document type
        progressHandler?("reading file")
        await Task.yield() // Yield to UI without blocking (was 0.5s sleep)
        try Task.checkCancellation()

        let extractedText: String
        let pageInfo: PageInfo

        // Use structured parsing for PDFs on iOS 26+ (preserves table/list structure)
        if documentType == .pdf {
            let structuredResult = try await extractStructuredPDFContent(url: url, pageRange: pageRange)
            extractedText = structuredResult.text
            pageInfo = structuredResult.pageInfo
            structuredElements = structuredResult.structuredElements
            usedStructuredParsing = structuredResult.usedStructuredParsing

            if usedStructuredParsing {
                let tableCount = structuredElements.filter { $0.elementType == "table" }.count
                let listCount = structuredElements.filter { $0.elementType == "list" }.count
                Log.info("[DocumentProcessor] Structured parsing: \(tableCount) tables, \(listCount) lists extracted", category: .ingestion)
            }
        } else {
            let result: (text: String, pageInfo: PageInfo)
            if documentType == .json,
                let records = try extractJSONRecords(url: url, numbering: textPiece?.numbering ?? .init())
            {
                result = (records.text, PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1]))
                jsonRecordCount = records.records.count
            } else {
                result = try await extractTextWithPageInfo(from: url, type: documentType)
            }
            extractedText = result.text
            pageInfo = result.pageInfo

            let inferredStructure = detectStructuredElementsInExtractedText(
                result.text,
                pageInfo: result.pageInfo,
                documentType: documentType
            )
            structuredElements = inferredStructure.elements
            usedStructuredParsing = inferredStructure.usedStructuredParsing

            if usedStructuredParsing {
                let tableCount = structuredElements.filter { $0.elementType == "table" }.count
                let listCount = structuredElements.filter { $0.elementType == "list" }.count
                Log.info("[DocumentProcessor] Inferred non-PDF structure: \(tableCount) tables, \(listCount) lists extracted", category: .ingestion)
            }
        }

        try Task.checkCancellation()

        pagesProcessed = pageInfo.totalPages
        ocrPagesCount = pageInfo.ocrPagesUsed > 0 ? pageInfo.ocrPagesUsed : nil

        let extractionTime = Date().timeIntervalSince(startTime)
        let charCount = extractedText.count
        let wordCount = Self.wordCount(of: extractedText)

        Log.debug(
            "[DocumentProcessor] Extracted \(charCount) chars (\(wordCount) words) in \(String(format: "%.2f", extractionTime))s",
            category: .ingestion
        )

        // A very large text that the fallback chunker will take may be more than one document can
        // hold. Its words are counted first, off the main actor, and it is refused now if so:
        // before the cleanup pass, and before anything is stored. Below the size named here no
        // text can hold that many words, so nothing else pays for the count. The chunker checks
        // again on the cleaned text and is the authority.
        let takesFallbackChunker = jsonRecordCount == nil && !(usedStructuredParsing && !structuredElements.isEmpty)
        if takesFallbackChunker, extractedText.utf8.count > Self.largeTextWordCountBytes {
            emitProgress(stage: "parsing", detail: "📏 Measuring a very large text...", page: nil, totalPages: nil)
            let tokenizerWords = await SemanticChunker.wordCountOffMainActor(extractedText)
            try Task.checkCancellation()
            if SemanticChunker.exceedsChunkLimit(
                wordCount: tokenizerWords, maxSize: SemanticChunker.ChunkingConfig.safeMaxSize)
            {
                Log.error(
                    "[DocumentProcessor] \(filename) has \(tokenizerWords) words, more than \(SemanticChunker.maxChunks) chunks can hold; refusing it before cleanup",
                    category: .ingestion)
                throw DocumentProcessingError.tooManyPassages(limit: SemanticChunker.maxChunks)
            }
        }

        // POST-OCR GARBAGE TEXT FILTER
        // Apply a final line-level cleanup for OCR-heavy non-PDF paths.
        // PDF ingestion already filters garbage line-by-line per page during extraction,
        // which keeps page mapping stable and catches isolated bad native-text lines.
        let filteredText: String
        if documentType != .pdf, (ocrPagesCount ?? 0) > 0 {
            let (cleaned, removedCount) = OCRConfiguration.filterGarbageText(extractedText)
            if removedCount > 0 {
                Log.info("[DocumentProcessor] Garbage filter: removed \(removedCount) garbage lines from OCR output", category: .ingestion)
            }
            if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && charCount > 50 {
                Log.warning("[DocumentProcessor] Entire page was garbage OCR — likely a diagram/image page", category: .ingestion)
            }
            filteredText = cleaned
        } else {
            filteredText = extractedText
        }

        // Document-aware text normalization
        // OCR/PDF-heavy sources get the full repair pipeline; authored text files
        // use a conservative profile to avoid mutating real words or formatting.
        //
        // Off the main actor since 5.7. It is one pass over the whole text, and on an 88 MB file
        // it held the main thread for 57 s (iPhone 16 Pro Max, 2026-10-09). Same function, same
        // result; only where it runs changed.
        emitProgress(stage: "parsing", detail: "🧹 Cleaning up the text...", page: nil, totalPages: nil)
        let normalizedText = await Self.normalizeOffMainActor(
            filteredText,
            profile: normalizationProfile(for: documentType)
        )
        try Task.checkCancellation()
        if normalizedText.count != filteredText.count {
            let delta = filteredText.count - normalizedText.count
            Log.info(
                "[DocumentProcessor] Text normalization: cleaned \(delta) chars (\(filteredText.count)→\(normalizedText.count))",
                category: .ingestion
            )
        }

        // CRITICAL: Store NORMALIZED text for full-text search and exact queries
        // Normalized text has CJK bullet artifacts replaced, ll-ligature errors repaired,
        // and encoding garbage cleaned — so FTS5 search actually finds the right words.
        // Raw extractedText with font encoding errors ("colision", "wil") breaks search.

        // Step A: Split normalized text by page break sentinel to get per-page content, each page
        // with its own number (`numberedPages`).
        let startPageNum = pageRange?.lowerBound ?? 0
        let pageTextsFromSentinel = Self.numberedPages(
            splitting: normalizedText, separator: Self.pageBreakSentinel,
            pagesWithText: pageInfo.pageTextRanges.keys.sorted(), firstPageIndex: startPageNum)
        // A batch of a PDF imported in batches is numbered even when it holds one page, so the
        // last batch of, say, 31 pages keeps its row (5.7).
        let isNumbered = pageTextsFromSentinel.count > 1 || (pageRange != nil && !pageTextsFromSentinel.isEmpty)

        // Step B: Build human-readable full-doc text with page markers for FTS5
        let storedText: String
        if isNumbered {
            storedText = pageTextsFromSentinel.map { page in
                "--- Page \(page.pageNumber) ---\n\(page.content)"
            }.joined(separator: "\n\n")
        } else {
            // Single page or no sentinels (non-PDF) — store as-is without markers
            storedText = normalizedText.replacingOccurrences(of: Self.pageBreakSentinel, with: "\n\n")
        }
        let storedCharCount = storedText.count

        if let textPiece {
            // A piece of a file imported in pieces: its text is the caller's to keep.
            try textPiece.keepText(storedText)
        } else if let containerId = containerId {
            try Task.checkCancellation()
            // Primary path: SQLite FTS5 with container isolation (v1.1.0+)
            // Step C, the per-page rows for page-level search and context isolation, goes with it.
            let pageEntries: [(pageNumber: Int, content: String)] = isNumbered ? pageTextsFromSentinel : []
            let storedPages = await Self.storeText(
                storedText, pages: pageEntries, for: documentId, containerId: containerId, append: pageRange != nil)
            Log.debug("[DocumentProcessor] Stored normalized text (\(storedCharCount) chars) to FTS5 for exact query support", category: .ingestion)
            if !pageEntries.isEmpty {
                Log.info(
                    "[DocumentProcessor] Stored \(pageEntries.count) individual pages to FTS5 for page-level context (\(storedPages) in all)",
                    category: .ingestion)
            }
        } else {
            try Task.checkCancellation()
            // Fallback path: File-based storage (legacy, no container context)
            await FullTextStorageService.shared.store(text: storedText, for: documentId)
            Log.debug("[DocumentProcessor] Stored normalized text (\(storedCharCount) chars) to file storage (legacy path)", category: .ingestion)
        }

        // Step D: Strip page break sentinels for chunking — chunker must see continuous text
        let chunkableText = normalizedText.replacingOccurrences(of: Self.pageBreakSentinel, with: "\n\n")
        // Each statement from here to the chunker is one pass over the whole text on the main
        // actor. The yields let the screen and the system in between them.
        await Task.yield()

        // Per-stage conservation ledger. `verifyContentCoverage` below compares this text against the
        // FINISHED chunks and so can only say that text was lost; this records each transition, so a
        // loss names the stage that caused it. See IngestionStageLedger.swift.
        var stageLedger = IngestionStageLedger(documentName: filename)
        let extractionCounts = await Self.ledgerCounts([chunkableText])
        stageLedger.recordExtraction(characters: extractionCounts.characters, words: extractionCounts.words)

        await Task.yield()
        let documentCategory = classifyDocumentCategory(
            text: chunkableText,
            filename: filename,
            documentType: documentType,
            structuredElements: structuredElements
        )
        Log.info("[DocumentProcessor] Document category: \(documentCategory.rawValue)", category: .ingestion)

        // Chunk the text using semantic chunker
        emitProgress(stage: "chunking", detail: "✂️ Semantic chunking text...", page: nil, totalPages: nil)
        await Task.yield() // Yield to UI without blocking (was 0.3s sleep)
        try Task.checkCancellation()
        let chunkingStartTime = Date()

        // Create semantic chunker configuration
        // Use content-adaptive defaults if no override provided
        let baseConfig = SemanticChunker.ChunkingConfig.recommended(
            for: documentType,
            strategyOverride: chunkOverride?.strategy
        )
        let activeWindow = chunkOverride?.targetWordWindow ?? baseConfig.targetSize
        let activeOverlap = chunkOverride?.overlapWords ?? baseConfig.overlap

        // CRITICAL: maxSize is capped to prevent token truncation during embedding.
        // CoreML model has a 510 token limit and RAGService prepends a ~30 word contextual
        // prefix, so the ceiling is 310 words + 30 prefix = 340 total ≈ 500 tokens.
        //
        // The numbers now live on `SemanticChunker.ChunkingConfig` so the Library Settings
        // sliders can bound themselves by the same constants this clamps to. They were
        // duplicated as literals in both places and had drifted: the sliders offered 600 and
        // 200 against these 260 and 50.
        let safeMaxSize = SemanticChunker.ChunkingConfig.safeMaxSize

        let chunkerConfig = SemanticChunker.ChunkingConfig(
            targetSize: min(activeWindow, SemanticChunker.ChunkingConfig.maxTargetSize),
            minSize: max(baseConfig.minSize, 60),
            maxSize: safeMaxSize,  // HARD LIMIT: leaves room for the embedding prefix
            overlap: min(activeOverlap, SemanticChunker.ChunkingConfig.maxOverlap),
            useTopicDetection: baseConfig.useTopicDetection,
            preserveStructure: baseConfig.preserveStructure
        )

        Log.debug(
            "[DocumentProcessor] Using \(documentType.rawValue) chunking: target=\(activeWindow)w, overlap=\(activeOverlap)w",
            category: .ingestion
        )

        var processedChunks: [ProcessedChunk]

        // JSON records: each record is cut from the cleaned text as its own passage. When the
        // headers did not survive the cleanup intact, nothing is cut and the text is chunked as prose.
        let jsonRecordPassages = jsonRecordCount.flatMap {
            JSONRecordExtractor.passages(
                in: chunkableText, expectedCount: $0, numbering: textPiece?.numbering ?? .init())
        }
        if let jsonRecordCount, jsonRecordPassages == nil {
            Log.warning(
                "[DocumentProcessor] JSON records: \(jsonRecordCount) were read from \(filename) but their headers "
                    + "did not all survive text cleanup; chunking the text as prose instead",
                category: .ingestion
            )
        }

        // Structure-aware chunking: Tables and lists become atomic chunks, paragraphs get semantic chunking
        if let jsonRecordPassages {
            processedChunks = await makeJSONRecordChunks(
                jsonRecordPassages, in: chunkableText, documentCategory: documentCategory,
                firstRecordNumber: textPiece?.numbering.first ?? 1, packsRecords: textPiece != nil)
            emitProgress(
                stage: "chunking", detail: "✅ Created \(processedChunks.count) record passages", page: nil,
                totalPages: nil)
            Log.info(
                "[DocumentProcessor] Created \(processedChunks.count) JSON record passages", category: .ingestion)
        } else if usedStructuredParsing && !structuredElements.isEmpty {
            // HUD telemetry: Chunking is CPU-intensive NaturalLanguage processing
            Task { @MainActor in
                HardwareTelemetryState.shared.pulse(.textChunking, intensity: 0.75, duration: 0.4)
            }
            emitProgress(stage: "chunking", detail: "🧩 Structure-aware chunking \(structuredElements.count) elements...", page: nil, totalPages: nil)
            processedChunks = createStructureAwareChunks(
                elements: structuredElements,
                fullText: chunkableText,
                config: chunkerConfig,
                documentId: documentId,
                pageInfo: pageInfo,
                filename: filename,
                documentCategory: documentCategory
            )
            emitProgress(stage: "chunking", detail: "✅ Created \(processedChunks.count) chunks", page: nil, totalPages: nil)
            Log.info("[DocumentProcessor] Created \(processedChunks.count) structure-aware chunks", category: .ingestion)
        } else {
            // Fallback semantic chunking when no reliable structure survived extraction
            // HUD telemetry: Chunking is CPU-intensive NaturalLanguage processing
            Task { @MainActor in
                HardwareTelemetryState.shared.pulse(.textChunking, intensity: 0.75, duration: 0.4)
            }
            let pageMapping = pageInfo.pageTextRanges.isEmpty ? nil : pageInfo.pageTextRanges
            // Off the main actor since 5.7, with progress. On the main actor a large text file
            // froze the screen for as long as chunking took, the status never moved, Cancel could
            // not be tapped, and iOS ended the app when a scene update waited ten seconds.
            let enhancedChunks: [SemanticChunker.EnhancedChunk]
            chunkingRunsInFlight += 1
            do {
                enhancedChunks = try await SemanticChunker.chunkTextOffMainActor(
                    chunkableText,
                    documentId: documentId,
                    config: chunkerConfig,
                    pageNumbers: pageMapping,
                    documentCategory: documentCategory,
                    progress: { [weak self] progress in
                        guard let self else { return }
                        Task { @MainActor in self.reportChunkingProgress(progress) }
                    }
                )
            } catch {
                chunkingRunsInFlight -= 1
                // Chunking did not finish: the text is over the limit, or the import was
                // cancelled, which can be tapped during chunking now that the screen is live. The
                // full text stored above is removed, so it is not left under an id that no
                // document will have. Not when this call was adding pages or a piece to a
                // document that already has some: with no page range and no piece the id is
                // always a new one (the callers were read on 2026-10-09).
                var limitReached: Int?
                if case SemanticChunker.ChunkingError.tooManyChunks(let limit) = error { limitReached = limit }
                if pageRange == nil, textPiece == nil, limitReached != nil || error is CancellationError {
                    if containerId != nil {
                        await SQLiteFullTextService.shared.delete(for: documentId)
                    } else {
                        await FullTextStorageService.shared.delete(for: documentId)
                    }
                    Log.info(
                        "[DocumentProcessor] Removed the stored text of \(filename): chunking did not finish",
                        category: .ingestion)
                }
                if let limitReached {
                    Log.error(
                        "[DocumentProcessor] \(filename) needs more than \(limitReached) chunks; refusing it rather than indexing part of it",
                        category: .ingestion)
                    throw DocumentProcessingError.tooManyPassages(limit: limitReached)
                }
                throw error
            }
            chunkingRunsInFlight -= 1

            // Extract text strings and metadata for downstream use
            processedChunks = enhancedChunks.enumerated().map { index, chunk in
                let metadata = ChunkMetadata(
                    chunkIndex: index,
                    startPosition: chunk.metadata.startOffset,
                    endPosition: chunk.metadata.endOffset,
                    pageNumber: chunk.metadata.pageNumber,
                    sectionTitle: chunk.metadata.sectionTitle,
                    keywords: chunk.metadata.topKeywords,
                    semanticDensity: chunk.metadata.semanticDensity,
                    hasNumericData: chunk.metadata.hasNumericData,
                    hasListStructure: chunk.metadata.hasListStructure,
                    wordCount: chunk.metadata.wordCount,
                    characterCount: chunk.metadata.characterCount,
                    structureType: nil,  // Legacy flat text extraction
                    entities: chunk.metadata.entities,
                    abbreviations: chunk.metadata.abbreviations,
                    sectionPath: chunk.metadata.sectionPath.isEmpty ? nil : chunk.metadata.sectionPath,
                    documentCategory: chunk.metadata.documentCategory,
                    chunkType: chunk.metadata.chunkType,
                    tableTitle: chunk.metadata.tableTitle,
                    hasCrossReferences: chunk.metadata.hasCrossReferences,
                    resolvedReferences: chunk.metadata.resolvedReferences
                )
                return ProcessedChunk(text: chunk.content, parentText: chunk.parentContent, metadata: metadata)
            }
            emitProgress(stage: "chunking", detail: "✅ Created \(processedChunks.count) semantic chunks", page: nil, totalPages: nil)
        }

        let chunkedCounts = await Self.ledgerCounts(processedChunks.map(\.text))
        stageLedger.record(.chunked, chunkCount: processedChunks.count, counts: chunkedCounts)

        // A JSON record's title and path are written by `makeJSONRecordChunks` ("Record 12",
        // "Records 12 to 19"), so there is nothing in them to clean, and cleaning a label is not
        // cheap: a piece of a large file holds thousands of record chunks.
        if jsonRecordPassages == nil {
            processedChunks = await sanitizeProcessedChunkMetadata(processedChunks)
        }
        let sanitizedCounts = await Self.ledgerCounts(processedChunks.map(\.text))
        stageLedger.record(.sanitized, chunkCount: processedChunks.count, counts: sanitizedCounts)

        let chunkingTime = Date().timeIntervalSince(chunkingStartTime)

        // CRITICAL: Post-processing validation - ensure NO chunk exceeds embedding token limit
        // This is a safety net that catches any chunks that slipped through chunking config limits
        emitProgress(stage: "validate", detail: "🔐 Validating token limits...", page: nil, totalPages: nil)
        await Task.yield()
        try Task.checkCancellation()
        processedChunks = await enforceTokenLimitOnChunks(processedChunks)
        let tokenLimitedCounts = await Self.ledgerCounts(processedChunks.map(\.text))
        stageLedger.record(.tokenLimited, chunkCount: processedChunks.count, counts: tokenLimitedCounts)
        stageLedger.emit()

        // CONTENT COVERAGE VERIFICATION: Ensure we captured all the source content
        // This catches bugs where content is silently dropped during chunking
        // Off the main actor (5.7): it splits the whole extracted text and every passage into words,
        // which held the main thread for as long as a large file took.
        await Self.verifyContentCoverage(
            original: extractedText,
            chunkTexts: processedChunks.map(\.text),
            documentId: documentId
        )

    		Log.debug(
                "[DocumentProcessor] Created \(processedChunks.count) semantic chunks in \(String(format: "%.3f", chunkingTime))s",
    			category: .ingestion
    		)

        // Log semantic features detected
        let chunksWithSections = processedChunks.filter { $0.metadata.sectionTitle != nil }.count
        let chunksWithKeywords = processedChunks.filter { !$0.metadata.keywords.isEmpty }.count
        let chunksWithNumericData = processedChunks.filter { $0.metadata.hasNumericData }.count
        let chunksWithLists = processedChunks.filter { $0.metadata.hasListStructure }.count

    		Log.debug("   📑 Semantic features:", category: .ingestion)
    		Log.debug("      - Sections detected: \(chunksWithSections)/\(processedChunks.count)", category: .ingestion)
    		Log.debug("      - Keywords extracted: \(chunksWithKeywords)/\(processedChunks.count)", category: .ingestion)
    		Log.debug("      - Numeric data: \(chunksWithNumericData)/\(processedChunks.count)", category: .ingestion)
    		Log.debug("      - List structures: \(chunksWithLists)/\(processedChunks.count)", category: .ingestion)

        // Calculate average semantic density
        let avgSemanticDensity = processedChunks
            .map { Double($0.metadata.semanticDensity ?? 0) }
            .reduce(0.0, +) / Double(max(1, processedChunks.count))
            Log.debug("      - Avg semantic density: \(String(format: "%.3f", avgSemanticDensity))", category: .ingestion)

        // Apple's detector on the document's text as well (5.7, roadmap row "Entities come from
        // table cells only"): it read table cells and nothing else, and a page read from its text
        // layer never reached it. Its matches join the cells' ones, without repeats, and go where
        // theirs go (the library's vocabulary, through `lastDetectedEntities`).
        mergeDetectedEntities(
            await StructuredDocumentParser.detectedEntities(
                inText: chunkableText, characterLimit: Self.textEntityCharacterLimit))

        // Print chunk statistics
        if !processedChunks.isEmpty {
            let chunkLengths = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkLengths.reduce(0, +) / processedChunks.count
            let minChunkSize = chunkLengths.min() ?? 0
            let maxChunkSize = chunkLengths.max() ?? 0
                Log.debug("   📊 Chunk stats: avg=\(avgChunkSize), min=\(minChunkSize), max=\(maxChunkSize) chars", category: .ingestion)

            let chunkStats = ChunkStatistics(
                averageChars: avgChunkSize,
                minChars: minChunkSize,
                maxChars: maxChunkSize
            )

            let totalTime = Date().timeIntervalSince(startTime)
                Log.debug("   ✅ Total processing: \(String(format: "%.2f", totalTime))s", category: .ingestion)

            // Calculate structured parsing stats
            let tableElements = structuredElements.filter { $0.elementType == "table" }
            let listElements = structuredElements.filter { $0.elementType == "list" }
            let titleElements = structuredElements.filter { $0.elementType == "title" }

            // Count atomic chunks (tables/lists kept as single units)
            let atomicTableChunkCount = processedChunks.filter { $0.metadata.structureType == "table" }.count
            let atomicListChunkCount = processedChunks.filter { $0.metadata.structureType == "list" }.count

            // Calculate max section path depth
            let maxSectionDepth = processedChunks.compactMap { $0.metadata.sectionPath?.count }.max() ?? 0

            // Create processing metadata with structured parsing stats
            var metadata = ProcessingMetadata(
                fileSizeMB: fileSizeMB,
                totalCharacters: charCount,
                totalWords: wordCount,
                extractionTimeSeconds: extractionTime,
                chunkingTimeSeconds: chunkingTime,
                embeddingTimeSeconds: 0, // Will be updated by RAGService after embeddings are generated
                totalProcessingTimeSeconds: totalTime,
                pagesProcessed: pagesProcessed,
                ocrPagesCount: ocrPagesCount,
                chunkStats: chunkStats
            )

            // Add structured parsing stats
            metadata.usedStructuredParsing = usedStructuredParsing
            metadata.tablesExtracted = tableElements.count
            metadata.listsExtracted = listElements.count
            metadata.titlesDetected = titleElements.count
            metadata.visionEntitiesDetected = lastDetectedEntities.count
            metadata.sectionPathDepth = maxSectionDepth
            metadata.atomicTableChunks = atomicTableChunkCount
            metadata.atomicListChunks = atomicListChunkCount
            metadata.targetWordWindow = activeWindow
            metadata.overlapWords = activeOverlap
            metadata.chunkingStrategy = chunkOverride?.strategy ?? "balanced"
            metadata.documentCategory = documentCategory

            let tableDataSet = structuredElements.compactMap(\ .tableData)
            metadata.tableRowsTotal = tableDataSet.reduce(0) { $0 + $1.rows.count }
            metadata.tableColumnsMax = tableDataSet.map { $0.rows.map(\ .count).max() ?? 0 }.max() ?? 0
            metadata.listItemsTotal = structuredElements.compactMap(\ .listItems).reduce(0) { $0 + $1.count }
            metadata.figureReferences = structuredElements.filter { $0.elementType == "figure" }.count

            if usedStructuredParsing {
                Log.info("[DocumentProcessor] Structured parsing stats: \(tableElements.count) tables, \(listElements.count) lists, \(titleElements.count) titles, \(lastDetectedEntities.count) entities detected", category: .ingestion)
            }

            // Create document metadata
            let document = Document(
                id: documentId,
                filename: filename,
                fileURL: url,
                contentType: documentType,
                totalChunks: processedChunks.count,
                processingMetadata: metadata
            )

            return (document, processedChunks)
        }

        let totalTime = Date().timeIntervalSince(startTime)
            Log.debug("   ✅ Total processing: \(String(format: "%.2f", totalTime))s", category: .ingestion)

        // Create document metadata (no chunks case)
        let document = Document(
            id: documentId,
            filename: filename,
            fileURL: url,
            contentType: documentType,
            totalChunks: processedChunks.count
        )

        return (document, processedChunks)
    }

}

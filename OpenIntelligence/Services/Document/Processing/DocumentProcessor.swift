//
//  DocumentProcessor.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
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

/// Service responsible for parsing documents and chunking them for embedding
class DocumentProcessor {
    struct ProcessedChunk: Sendable {
        let text: String
        let parentText: String?
        let metadata: ChunkMetadata

        /// Optional structured table payload preserved only for downstream SQLite storage.
        /// This keeps relational table shape available without bloating every persisted chunk path.
        let structuredTable: StructuredTablePayload?

        nonisolated init(
            text: String,
            parentText: String?,
            metadata: ChunkMetadata,
            structuredTable: StructuredTablePayload? = nil
        ) {
            self.text = text
            self.parentText = parentText
            self.metadata = metadata
            self.structuredTable = structuredTable
        }
    }

    struct StructuredTablePayload: Sendable, Codable {
        let title: String
        let headers: [String]
        let rows: [[String]]
        let extractionQuality: Double
        let extractionSource: String
        let lowQualityRowIndices: [Int]

        nonisolated init(
            title: String,
            headers: [String],
            rows: [[String]],
            extractionQuality: Double = 0,
            extractionSource: String = "vision_document",
            lowQualityRowIndices: [Int] = []
        ) {
            self.title = title
            self.headers = headers
            self.rows = rows
            self.extractionQuality = extractionQuality
            self.extractionSource = extractionSource
            self.lowQualityRowIndices = lowQualityRowIndices
        }

        var rowCount: Int { rows.count }

        var columnCount: Int {
            max(headers.count, rows.map(\ .count).max() ?? 0)
        }

        var searchText: String {
            var lines: [String] = []
            lines.append(title)
            if !headers.isEmpty {
                lines.append(headers.joined(separator: " | "))
            }
            for (rowIndex, row) in rows.prefix(80).enumerated() {
                guard !lowQualityRowIndices.contains(rowIndex) else { continue }
                let normalized = row
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !normalized.isEmpty else { continue }
                lines.append(normalized.joined(separator: " | "))
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Page Break Sentinel

    /// Unique sentinel inserted between PDF pages during text extraction.
    /// Survives text normalization and enables per-page FTS5 storage.
    /// Must never appear naturally in any document.
    static let pageBreakSentinel = "⊕⊕⊕PAGE_BREAK⊕⊕⊕"

    // MARK: - GPU Acceleration

    /// Shared Metal device for GPU-accelerated image processing
    private static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Concurrent queue for GPU context access with bounded parallelism.
    /// CIContext IS thread-safe for rendering (Apple docs). The previous serial queue
    /// was overly conservative — it serialized ALL CIFilter renders, creating a bottleneck.
    /// Metal command buffer contention is handled by the VisionOCRThrottle semaphore,
    /// not by serializing preprocessing. Concurrency is naturally bounded by
    /// pdfRenderingConcurrency (TaskGroup) which limits how many pages render simultaneously.
    private static let gpuQueue = DispatchQueue(
        label: "com.openintelligence.gpu-context",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// GPU-accelerated CIContext for image operations (PDF rendering, OCR prep)
    /// Using Metal backend provides 5-10x speedup over CPU for image processing
    private static let gpuContext: CIContext = {
        if let device = metalDevice {
            Log.info("[DocumentProcessor] 🚀 GPU acceleration enabled via Metal: \(device.name)", category: .ingestion)
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: true,
                .priorityRequestLow: false,  // High priority for extraction
                .highQualityDownsample: true
            ])
        } else {
            Log.warning("[DocumentProcessor] ⚠️ Metal unavailable, using CPU for image processing", category: .ingestion)
            return CIContext(options: [.useSoftwareRenderer: true])
        }
    }()

    /// Check if GPU acceleration is available
    static var isGPUAccelerated: Bool { metalDevice != nil }

    /// Adaptive GPU-accelerated image preprocessing for improved OCR accuracy.
    /// Selects preprocessing strategy based on page characteristics, then applies
    /// the appropriate CIFilter chain using Metal-backed Core Image.
    ///
    /// - Parameters:
    ///   - image: Input CIImage from PDF rendering
    ///   - textQuality: 0.0-1.0 quality score from PageComplexityAnalyzer (default: 0.7)
    ///   - hasNativeTextLayer: Whether PDFKit extracted text for this page
    ///   - isScanned: Whether this appears to be a scanned image
    /// - Returns: Enhanced CIImage optimized for text recognition (eagerly rendered to prevent Metal races)
    private func preprocessImageForOCR(
        _ image: CIImage,
        textQuality: Double = 0.7,
        hasNativeTextLayer: Bool = true,
        isScanned: Bool = false
    ) -> CIImage {
        // Skip if GPU not available
        guard Self.metalDevice != nil else { return image }

        let strategy = AdaptivePreprocessor.selectStrategy(
            textQuality: textQuality,
            hasNativeTextLayer: hasNativeTextLayer,
            isScanned: isScanned,
            imagePresence: 0.0
        )

        Log.debug("[DocumentProcessor] Adaptive preprocessing: using '\(strategy.name)' strategy (quality=\(String(format: "%.1f", textQuality)), scanned=\(isScanned))", category: .ingestion)

        return AdaptivePreprocessor.apply(
            strategy,
            to: image,
            gpuContext: Self.gpuContext,
            gpuQueue: Self.gpuQueue
        )
    }

    // MARK: - Pipeline Trace Helpers (Per-Page Ingestion)

    private func traceIngestionDecision(
        pageNumber: Int,
        strategy: String,
        hasText: Bool,
        textQualityOK: Bool,
        requiresTableOCR: Bool,
        mode: String
    ) {
        guard Log.pipelineTraceEnabled else { return }
        Log.pipelineStep(
            "ING\(pageNumber)",
            title: "Ingestion Decision",
            details: [
                ("mode", mode),
                ("strategy", strategy),
                ("hasText", hasText ? "yes" : "no"),
                ("quality", textQualityOK ? "good" : "poor"),
                ("tableOCR", requiresTableOCR ? "forced" : "no")
            ]
        )
    }

    nonisolated private func traceIngestionOutcome(
        pageNumber: Int,
        path: String,
        chars: Int,
        duration: TimeInterval? = nil,
        extra: [(String, String)] = []
    ) {
        guard Log.pipelineTraceEnabled else { return }
        var details: [(String, String)] = [("path", path), ("chars", "\(chars)")]
        details.append(contentsOf: extra)
        Log.pipelineStep(
            "ING\(pageNumber)",
            title: "Ingestion Outcome",
            details: details,
            duration: duration
        )
    }

    private nonisolated func preferredOCRRenderScale(
        for analysis: PageComplexityAnalysis?,
        documentTextLayerGarbled: Bool
    ) -> CGFloat {
        guard let analysis else {
            return documentTextLayerGarbled ? 6.0 : 5.0
        }

        if documentTextLayerGarbled {
            return 6.0
        }

        let needsHighResolutionOCR = analysis.fineTextRisk >= 0.45
            || analysis.tablePresence > 0.16
            || analysis.columnCount > 1
            || analysis.layoutComplexity >= 0.30
            || analysis.numericDensity > 0.14
            || analysis.headerPatternStrength >= 0.20
            || analysis.textCoverage < 0.58

        if needsHighResolutionOCR {
            return 6.0
        }

        return 5.0
    }

    private func shouldForceVisionForAdaptiveRecovery(
        analysis: PageComplexityAnalysis?,
        strategy: PageProcessingStrategy,
        documentTextLayerGarbled: Bool
    ) -> Bool {
        if documentTextLayerGarbled {
            return true
        }

        guard let analysis else {
            return strategy != .directText
        }

        if analysis.isMixedModeScanned {
            return true
        }

        guard strategy != .directText else { return false }

        return analysis.tablePresence > 0.08
            || analysis.numericDensity > 0.10
            || analysis.columnCount > 1
            || analysis.layoutComplexity >= 0.18
            || analysis.listPatternStrength >= 0.15
            || analysis.headerPatternStrength >= 0.15
            || analysis.textCoverage < 0.55
            || analysis.fineTextRisk >= 0.35
    }

    private func shouldPreferHighResolutionStructure(
        for analysis: PageComplexityAnalysis?,
        strategy: PageProcessingStrategy,
        documentTextLayerGarbled: Bool
    ) -> Bool {
        if documentTextLayerGarbled {
            return true
        }

        let requiresTableOCR = (analysis?.tablePresence ?? 0) > 0.2 || (analysis?.numericDensity ?? 0) > 0.3
        if requiresTableOCR || strategy == .fullOCR {
            return true
        }

        guard let analysis else { return false }

        return analysis.fineTextRisk >= 0.45
            || analysis.columnCount > 1
            || analysis.tablePresence > 0.12
            || analysis.layoutComplexity >= 0.35
            || analysis.textCoverage < 0.65
    }

    struct ChunkingOverride: Sendable {
        let strategy: String?
        let targetWordWindow: Int
        let overlapWords: Int
    }

    // MARK: - Structured Parsing Results (iOS 26+)

    /// Result of structured document extraction, containing both text and structured elements
    private struct StructuredExtractionResult {
        let text: String
        let pageInfo: PageInfo
        let structuredElements: [StructuredElementWrapper]  // Tables, lists with metadata
        let usedStructuredParsing: Bool
    }

    /// Wrapper to hold structured elements with page info (works on all iOS versions)
    /// Sendable struct with nonisolated init to allow construction in TaskGroup
    fileprivate struct StructuredElementWrapper: Sendable {
        let text: String
        let elementType: String  // "table", "list", "paragraph", "title"
        let pageNumber: Int
        let isAtomicChunk: Bool  // Tables should be chunked as single units
        let detectedEntities: [(type: String, value: String)]  // Vision-detected entities (emails, phones, etc.)
        let tableData: TableData?
        let listItems: [String]?
        let extractionSource: String?
        let qualityScore: Double?
        let imageAnalysis: AnalyzedImage?

        nonisolated init(
            text: String,
            elementType: String,
            pageNumber: Int,
            isAtomicChunk: Bool,
            detectedEntities: [(type: String, value: String)] = [],
            tableData: TableData? = nil,
            listItems: [String]? = nil,
            extractionSource: String? = nil,
            qualityScore: Double? = nil,
            imageAnalysis: AnalyzedImage? = nil
        ) {
            self.text = text
            self.elementType = elementType
            self.pageNumber = pageNumber
            self.isAtomicChunk = isAtomicChunk
            self.detectedEntities = detectedEntities
            self.tableData = tableData
            self.listItems = listItems
            self.extractionSource = extractionSource
            self.qualityScore = qualityScore
            self.imageAnalysis = imageAnalysis
        }
    }

    private struct RegionCropRescuePayload: Sendable {
        let elements: [StructuredElementWrapper]
        let pageText: String
        let tableCount: Int
        let listCount: Int
        let figureCount: Int

        nonisolated init(
            elements: [StructuredElementWrapper],
            pageText: String,
            tableCount: Int,
            listCount: Int,
            figureCount: Int
        ) {
            self.elements = elements
            self.pageText = pageText
            self.tableCount = tableCount
            self.listCount = listCount
            self.figureCount = figureCount
        }
    }

    // MARK: - Live Extraction Progress

    /// Rich progress data for real-time UI transparency during extraction
    struct ExtractionProgress: Sendable {
        let stage: String                  // "reading", "parsing", "structured", "chunking"
        let detail: String                 // Human-readable status
        let currentPage: Int?              // Current page being processed
        let totalPages: Int?               // Total pages in document
        // Live metrics (accumulated as we process)
        var tablesFound: Int = 0
        var listsFound: Int = 0
        var headersFound: Int = 0
        var ocrPagesUsed: Int = 0
        var usingVision: Bool = false      // True if RecognizeDocumentsRequest is being used
        var wordsExtracted: Int = 0
        var usingGPU: Bool = false         // True if Metal GPU acceleration is active
        var usingANE: Bool = false         // True if Neural Engine is active (Vision/CoreML)
    }

    // MARK: - Configuration

    /// Optimal chunk size balances context vs. precision (typically 200-500 words)
    let targetChunkSize: Int
    let chunkOverlap: Int

    /// Progress callback for real-time UI updates (simple string, legacy)
    var progressHandler: ((String) -> Void)?

    /// Rich progress callback with live metrics for extraction transparency
    var richProgressHandler: ((ExtractionProgress) -> Void)?

    /// Accumulated extraction metrics (updated during processing)
    private var liveMetrics = ExtractionProgress(stage: "idle", detail: "", currentPage: nil, totalPages: nil)

    /// Vision-detected entities from last document processing (reset on each call)
    /// Contains emails, phone numbers, URLs, dates, etc. extracted via DataDetection
    private(set) var lastDetectedEntities: [(type: String, value: String)] = []

    /// Tokenizer for accurate token counting (matches embedding model tokenization)
    /// CRITICAL: NLTokenizer word count ≠ Tokenizer tokens for technical content
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    private var embeddingTokenizer: Tokenizer?

    /// Dynamic custom words for the current document being processed.
    /// Extracted from PDFKit's text layer BEFORE Vision OCR runs, so Vision
    /// knows the document's domain vocabulary ("document teaches Vision").
    /// Reset on each processDocument() call.
    private var currentDocumentCustomWords: [String] = OCRConfiguration.universalCustomWords

    init(targetChunkSize: Int = 350, chunkOverlap: Int = 60) {
        self.targetChunkSize = targetChunkSize
        self.chunkOverlap = chunkOverlap
        loadTokenizer()
    }

    /// Assert that the tokenizer actually counts, rather than reporting its pad width.
    ///
    /// This is the check that would have caught the most expensive defect in this repository on the
    /// day it shipped. The bundled `tokenizer.json` carried a `padding` block, so
    /// `tokenizer.encode(...).count` returned the pad width for **every** input. `countTokens`
    /// therefore returned 128 forever, the `safeTokenLimit` guard at 430 could never fire, and the
    /// chunker had no working measure of its own output. It logged `maxTokens=128/430` **3,910 times
    /// out of 3,910** across every recorded benchmark run, and that reads exactly like a working
    /// measurement. A constant is only suspicious if something asks whether it should vary.
    ///
    /// So this asks. Two inputs of obviously different length must produce different counts, and a
    /// realistic chunk must not measure the same as a single word. Behavioural rather than
    /// configuration-based on purpose: it holds no matter how a future tokenizer expresses padding,
    /// and it does not need to parse `tokenizer.json`.
    ///
    /// Logs rather than traps. A wrong token count degrades retrieval quality silently; it does not
    /// corrupt data, and refusing to ingest would be a worse outcome than ingesting with a warning.
    private func verifyTokenizerCounts() {
        guard let tokenizer = embeddingTokenizer else { return }
        let short = "test"
        let long = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 20)
        do {
            let shortCount = try tokenizer.encode(text: short, addSpecialTokens: true).count
            let longCount = try tokenizer.encode(text: long, addSpecialTokens: true).count
            guard shortCount != longCount else {
                Log.error(
                    "[DocumentProcessor] TOKENIZER IS NOT COUNTING. A 1-word input and a 180-word "
                        + "input both measured \(shortCount) tokens, which means encode() is padding "
                        + "to a fixed width. Every token-budget decision downstream is now a constant, "
                        + "including the \(Self.safeTokenLimit)-token chunk guard. Remove the `padding` "
                        + "block from embedding_tokenizer.bundle/tokenizer.json; the providers pad "
                        + "themselves.",
                    category: .ingestion
                )
                return
            }
            Log.info(
                "[DocumentProcessor] Tokenizer count check passed: \(shortCount) vs \(longCount) tokens",
                category: .ingestion
            )
        } catch {
            Log.warning("[DocumentProcessor] Tokenizer count check could not run: \(error)", category: .ingestion)
        }
    }

    /// Load Tokenizer from embedding vocab for accurate token counting
    private func loadTokenizer() {
        if let url = OpenIntelligenceResourceBundle.url(forResource: "embedding_tokenizer", withExtension: "bundle") {
            Task {
                do {
                    embeddingTokenizer = try await AutoTokenizer.from(directory: url)
                    Log.info("[DocumentProcessor] Loaded Rust-backed Tokenizer for accurate chunk validation", category: .ingestion)
                    verifyTokenizerCounts()
                } catch {
                    Log.warning("[DocumentProcessor] Failed to load tokenizer: \(error). Falling back to word estimation.", category: .ingestion)
                }
            }
        }
    }

    // MARK: - Progress Emission Helpers

    /// Emit rich progress with accumulated metrics
    private func emitProgress(stage: String, detail: String, page: Int? = nil, totalPages: Int? = nil) {
        // Update simple handler (legacy)
        progressHandler?(detail)

        // Update accumulated metrics with current page info
        var progress = liveMetrics
        progress = ExtractionProgress(
            stage: stage,
            detail: detail,
            currentPage: page,
            totalPages: totalPages,
            tablesFound: liveMetrics.tablesFound,
            listsFound: liveMetrics.listsFound,
            headersFound: liveMetrics.headersFound,
            ocrPagesUsed: liveMetrics.ocrPagesUsed,
            usingVision: liveMetrics.usingVision,
            wordsExtracted: liveMetrics.wordsExtracted,
            usingGPU: liveMetrics.usingGPU,
            usingANE: liveMetrics.usingANE
        )
        richProgressHandler?(progress)
    }

    /// Increment a metric and emit progress
    private func incrementMetric(tables: Int = 0, lists: Int = 0, headers: Int = 0, ocrPages: Int = 0, words: Int = 0) {
        liveMetrics = ExtractionProgress(
            stage: liveMetrics.stage,
            detail: liveMetrics.detail,
            currentPage: liveMetrics.currentPage,
            totalPages: liveMetrics.totalPages,
            tablesFound: liveMetrics.tablesFound + tables,
            listsFound: liveMetrics.listsFound + lists,
            headersFound: liveMetrics.headersFound + headers,
            ocrPagesUsed: liveMetrics.ocrPagesUsed + ocrPages,
            usingVision: liveMetrics.usingVision,
            wordsExtracted: liveMetrics.wordsExtracted + words,
            usingGPU: liveMetrics.usingGPU,
            usingANE: liveMetrics.usingANE
        )
    }

    /// Reset live metrics for new document
    private func resetLiveMetrics(usingVision: Bool = false, totalPages: Int? = nil) {
        // Determine GPU/ANE usage based on current device settings
        let gpuLevel = DeviceCapabilityService.shared.gpuAccelerationLevel
        let usingGPU = gpuLevel >= 0.3 && Self.metalDevice != nil  // GPU for image preprocessing
        let usingANE = true  // Vision always uses ANE when available

        liveMetrics = ExtractionProgress(
            stage: "starting",
            detail: "Initializing...",
            currentPage: 0,
            totalPages: totalPages,
            tablesFound: 0,
            listsFound: 0,
            headersFound: 0,
            ocrPagesUsed: 0,
            usingVision: usingVision,
            wordsExtracted: 0,
            usingGPU: usingGPU,
            usingANE: usingANE
        )
    }

    // MARK: - Public API

    /// Process a document and extract text chunks
    /// Also stores the full original text for exact queries:
    /// - SQLiteFullTextService (FTS5) when containerId is provided (10-100X faster search)
    /// - FullTextStorageService (file-based) as fallback when containerId is nil
    func processDocument(at url: URL, chunkOverride: ChunkingOverride? = nil, containerId: UUID? = nil, pageRange: ClosedRange<Int>? = nil, documentId: UUID? = nil) async throws -> (Document, [ProcessedChunk]) {
        let __spProcessDocument = PipelineSignposts.ingestion.beginInterval("ProcessDocument")
        defer { PipelineSignposts.ingestion.endInterval("ProcessDocument", __spProcessDocument) }
        try Task.checkCancellation()
        // Reset ALL per-document state to prevent vocabulary/entity leaks between documents
        lastDetectedEntities = []
        currentDocumentCustomWords = OCRConfiguration.universalCustomWords
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
                    wordCount: chunk.text.split(separator: " ").count,
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
                totalWords: storedText.split(separator: " ").count,
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
        let maxNonStreamableSizeMB: Double = 500
        if fileSizeMB > maxNonStreamableSizeMB && documentType != .xml {
            Log.error("[DocumentProcessor] File too large: \(String(format: "%.0f", fileSizeMB)) MB (limit: \(String(format: "%.0f", maxNonStreamableSizeMB)) MB)", category: .ingestion)
            throw DocumentProcessingError.fileTooLarge(sizeMB: fileSizeMB, limitMB: maxNonStreamableSizeMB)
        }
        Log.debug("[DocumentProcessor] Document type: \(documentType)", category: .ingestion)

        // Track structured elements for structure-aware chunking (iOS 26+ PDFs)
        var structuredElements: [StructuredElementWrapper] = []
        var usedStructuredParsing = false

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
            let result = try await extractTextWithPageInfo(from: url, type: documentType)
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
        let wordCount = extractedText.split(separator: " ").count

        Log.debug(
            "[DocumentProcessor] Extracted \(charCount) chars (\(wordCount) words) in \(String(format: "%.2f", extractionTime))s",
            category: .ingestion
        )

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
        let normalizedText = OCRConfiguration.normalizeExtractedText(
            filteredText,
            profile: normalizationProfile(for: documentType)
        )
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

        // Step A: Split normalized text by page break sentinel to get per-page content
        let pageTextsFromSentinel = normalizedText.components(separatedBy: Self.pageBreakSentinel)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Step B: Build human-readable full-doc text with page markers for FTS5
        let storedText: String
        let startPageNum = pageRange?.lowerBound ?? 0
        if pageTextsFromSentinel.count > 1 {
            storedText = pageTextsFromSentinel.enumerated().map { (index, pageContent) in
                "--- Page \(startPageNum + index + 1) ---\n\(pageContent)"
            }.joined(separator: "\n\n")
        } else {
            // Single page or no sentinels (non-PDF) — store as-is without markers
            storedText = normalizedText.replacingOccurrences(of: Self.pageBreakSentinel, with: "\n\n")
        }
        let storedCharCount = storedText.count

        if let containerId = containerId {
            try Task.checkCancellation()
            // Primary path: SQLite FTS5 with container isolation (v1.1.0+)
            let shouldAppend = pageRange != nil
            await SQLiteFullTextService.shared.store(text: storedText, for: documentId, containerId: containerId, append: shouldAppend)
            Log.debug("[DocumentProcessor] Stored normalized text (\(storedCharCount) chars) to FTS5 for exact query support", category: .ingestion)

            // Step C: Store per-page content for page-level search and context isolation
            if pageTextsFromSentinel.count > 1 {
                let pageEntries = pageTextsFromSentinel.enumerated().map { (index, content) in
                    (pageNumber: startPageNum + index + 1, content: content)
                }
                try Task.checkCancellation()
                await SQLiteFullTextService.shared.storePages(pages: pageEntries, for: documentId, containerId: containerId, append: shouldAppend)
                Log.info("[DocumentProcessor] Stored \(pageEntries.count) individual pages to FTS5 for page-level context", category: .ingestion)
            }
        } else {
            try Task.checkCancellation()
            // Fallback path: File-based storage (legacy, no container context)
            await FullTextStorageService.shared.store(text: storedText, for: documentId)
            Log.debug("[DocumentProcessor] Stored normalized text (\(storedCharCount) chars) to file storage (legacy path)", category: .ingestion)
        }

        // Step D: Strip page break sentinels for chunking — chunker must see continuous text
        let chunkableText = normalizedText.replacingOccurrences(of: Self.pageBreakSentinel, with: "\n\n")

        // Per-stage conservation ledger. `verifyContentCoverage` below compares this text against the
        // FINISHED chunks and so can only say that text was lost; this records each transition, so a
        // loss names the stage that caused it. See IngestionStageLedger.swift.
        var stageLedger = IngestionStageLedger(documentName: filename)
        stageLedger.recordExtraction(
            characters: chunkableText.count,
            words: chunkableText.split(whereSeparator: \.isWhitespace).count
        )

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

        // Structure-aware chunking: Tables and lists become atomic chunks, paragraphs get semantic chunking
        if usedStructuredParsing && !structuredElements.isEmpty {
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
            let semanticChunker = SemanticChunker()
            let pageMapping = pageInfo.pageTextRanges.isEmpty ? nil : pageInfo.pageTextRanges
            let enhancedChunks = semanticChunker.chunkText(
                chunkableText,
                documentId: documentId,
                config: chunkerConfig,
                pageNumbers: pageMapping,
                documentCategory: documentCategory
            )

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

        stageLedger.record(.chunked, chunkTexts: processedChunks.map(\.text))

        processedChunks = sanitizeProcessedChunkMetadata(processedChunks)
        stageLedger.record(.sanitized, chunkTexts: processedChunks.map(\.text))

        let chunkingTime = Date().timeIntervalSince(chunkingStartTime)

        // CRITICAL: Post-processing validation - ensure NO chunk exceeds embedding token limit
        // This is a safety net that catches any chunks that slipped through chunking config limits
        emitProgress(stage: "validate", detail: "🔐 Validating token limits...", page: nil, totalPages: nil)
        processedChunks = enforceTokenLimitOnChunks(processedChunks)
        stageLedger.record(.tokenLimited, chunkTexts: processedChunks.map(\.text))
        stageLedger.emit()

        // CONTENT COVERAGE VERIFICATION: Ensure we captured all the source content
        // This catches bugs where content is silently dropped during chunking
        verifyContentCoverage(
            original: extractedText,
            chunks: processedChunks,
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

    // MARK: - Text Extraction

    /// Maps page numbers to their corresponding text range in the concatenated document string
    typealias PageTextMapping = [Int: Range<String.Index>]

    /// Holds page information from document extraction
    private struct PageInfo {
        let totalPages: Int
        let ocrPagesUsed: Int
        let pageNumbers: [Int]           // Array of page numbers corresponding to text chunks
        let pageTextRanges: PageTextMapping  // Maps page numbers to text ranges (for citations)

        init(totalPages: Int, ocrPagesUsed: Int, pageNumbers: [Int], pageTextRanges: PageTextMapping = [:]) {
            self.totalPages = totalPages
            self.ocrPagesUsed = ocrPagesUsed
            self.pageNumbers = pageNumbers
            self.pageTextRanges = pageTextRanges
        }
    }

    /// Extract text with page information for semantic chunking
    private func extractTextWithPageInfo(from url: URL, type: DocumentType) async throws -> (text: String, pageInfo: PageInfo) {
        let text: String
        var pageInfo = PageInfo(totalPages: 0, ocrPagesUsed: 0, pageNumbers: [], pageTextRanges: [:])

        switch type {
        case .pdf:
            let (extractedText, pdfPageInfo) = try await extractTextFromPDFWithPages(url: url)
            text = extractedText
            pageInfo = pdfPageInfo

        case .text, .markdown:
            text = try readTextFileWithFallbackEncodings(url: url, purpose: "text document")
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        case .rtf:
            text = try extractTextFromRTF(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Images - Use OCR
        case .png, .jpeg, .heic, .tiff, .gif, .image:
            Log.debug("[DocumentProcessor] Image detected; applying OCR", category: .ingestion)
            text = try await extractTextFromImage(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 1, pageNumbers: [1])

        // Code files - Preserve as-is with syntax
        // NOTE: .xml is handled separately above for large files (streaming path)
        // Small XML files (<50 MB) still go through extractTextFromCode here.
        case .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code:
            Log.debug("[DocumentProcessor] Code file detected; preserving syntax", category: .ingestion)
            text = try extractTextFromCode(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // CSV - Convert to structured text
        case .csv:
            Log.debug("[DocumentProcessor] CSV detected; converting to structured text", category: .ingestion)
            text = try extractTextFromCSV(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Office documents - Attempt extraction
        case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
            Log.debug("[DocumentProcessor] Office document detected; attempting extraction", category: .ingestion)
            text = try await extractTextFromOfficeDocument(url: url, type: type)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Audio/Video - Use Speech transcription
        case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            Log.debug("[DocumentProcessor] Audio/Video detected; transcribing with Speech.framework", category: .ingestion)
        text = try await extractTextFromAudioVideo(url: url)
        pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        case .unknown:
            // Last resort: try treating as plain text
            Log.warning("[DocumentProcessor] Unknown format; attempting plain text extraction", category: .ingestion)
            if let attemptedText = try? readTextFileWithFallbackEncodings(url: url, purpose: "unknown document"), !attemptedText.isEmpty {
                text = attemptedText
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                Log.debug("[DocumentProcessor] Extracted as plain text", category: .ingestion)
            } else {
                Log.error("[DocumentProcessor] Unsupported format: \(url.pathExtension)", category: .ingestion)
                throw DocumentProcessingError.unsupportedFormat
            }
        }

        // Edge case: Empty or whitespace-only document
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Log.error("[DocumentProcessor] Document is empty or contains only whitespace", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        // Edge case: Very short document
        if trimmedText.count < 50 {
            Log.warning("[DocumentProcessor] Very short document (\(trimmedText.count) chars)", category: .ingestion)
        }

        // Edge case: Suspiciously long document (possible issue)
        if text.count > 10_000_000 { // 10MB of text
            Log.warning("[DocumentProcessor] Very large document (\(text.count) chars)", category: .ingestion)
        }

        return (text, pageInfo)
    }

    private func detectStructuredElementsInExtractedText(
        _ text: String,
        pageInfo: PageInfo,
        documentType: DocumentType
    ) -> (elements: [StructuredElementWrapper], usedStructuredParsing: Bool) {
        guard shouldInferStructureFromExtractedText(for: documentType) else {
            return ([], false)
        }

        let pageTexts: [String]
        if text.contains(Self.pageBreakSentinel) {
            pageTexts = text
                .components(separatedBy: Self.pageBreakSentinel)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            pageTexts = [text]
        }

        var allElements: [StructuredElementWrapper] = []
        var foundStructuredContent = false

        for (index, pageText) in pageTexts.enumerated() {
            let pageNumber: Int
            if index < pageInfo.pageNumbers.count {
                pageNumber = pageInfo.pageNumbers[index]
            } else {
                pageNumber = index + 1
            }

            let pageElements = detectStructuredElementsInPageText(pageText, pageNumber: pageNumber)
            if pageElements.contains(where: { $0.elementType != "paragraph" }) {
                foundStructuredContent = true
            }
            allElements.append(contentsOf: pageElements)
        }

        return (allElements, foundStructuredContent)
    }

    private func shouldInferStructureFromExtractedText(for documentType: DocumentType) -> Bool {
        switch documentType {
        case .pdf,
             .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code,
             .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            return false
        default:
            return true
        }
    }

    private nonisolated func detectStructuredElementsInPageText(_ pageText: String, pageNumber: Int) -> [StructuredElementWrapper] {
        let lines = pageText.components(separatedBy: .newlines)
        var elements: [StructuredElementWrapper] = []
        var paragraphBuffer: [String] = []
        var lineIndex = 0

        func flushParagraphBuffer() {
            guard !paragraphBuffer.isEmpty else { return }
            let paragraphText = paragraphBuffer
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraphText.isEmpty {
                elements.append(StructuredElementWrapper(
                    text: paragraphText,
                    elementType: "paragraph",
                    pageNumber: pageNumber,
                    isAtomicChunk: false
                ))
            }
            paragraphBuffer.removeAll()
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                flushParagraphBuffer()
                lineIndex += 1
                continue
            }

            if trimmed == "[Table]" || trimmed == "[/Table]" {
                flushParagraphBuffer()
                lineIndex += 1
                continue
            }

            if let tableEnd = markdownTableBlockEnd(in: lines, startIndex: lineIndex) {
                var captionSource = paragraphBuffer
                let caption = consumeCaptionCandidate(from: &captionSource)
                paragraphBuffer = captionSource
                flushParagraphBuffer()

                let blockLines = Array(lines[lineIndex..<tableEnd])
                if let tableData = parseMarkdownTable(lines: blockLines, pageNumber: pageNumber, caption: caption) {
                    elements.append(StructuredElementWrapper(
                        text: tableData.textRepresentation,
                        elementType: "table",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: tableData.detectedEntities.map { ($0.type.rawValue, $0.value) },
                        tableData: tableData,
                        extractionSource: "text_inferred",
                        qualityScore: tableQualityScore(tableData)
                    ))
                    lineIndex = tableEnd
                    continue
                }
            }

            if let blockEnd = keyValueBlockEnd(in: lines, startIndex: lineIndex) {
                var captionSource = paragraphBuffer
                let caption = consumeCaptionCandidate(from: &captionSource)
                paragraphBuffer = captionSource
                flushParagraphBuffer()

                let blockLines = Array(lines[lineIndex..<blockEnd])
                if let tableData = parseKeyValueTable(lines: blockLines, pageNumber: pageNumber, caption: caption) {
                    elements.append(StructuredElementWrapper(
                        text: tableData.textRepresentation,
                        elementType: "table",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: tableData.detectedEntities.map { ($0.type.rawValue, $0.value) },
                        tableData: tableData,
                        extractionSource: "text_inferred",
                        qualityScore: tableQualityScore(tableData)
                    ))
                    lineIndex = blockEnd
                    continue
                }
            }

            if let blockEnd = parallelListTableBlockEnd(in: lines, startIndex: lineIndex) {
                var captionSource = paragraphBuffer
                let caption = consumeCaptionCandidate(from: &captionSource)
                paragraphBuffer = captionSource
                flushParagraphBuffer()

                let blockLines = Array(lines[lineIndex..<blockEnd])
                if let tableData = parseParallelListTable(lines: blockLines, pageNumber: pageNumber, caption: caption) {
                    elements.append(StructuredElementWrapper(
                        text: tableData.textRepresentation,
                        elementType: "table",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: tableData.detectedEntities.map { ($0.type.rawValue, $0.value) },
                        tableData: tableData,
                        extractionSource: "text_inferred",
                        qualityScore: tableQualityScore(tableData)
                    ))
                    lineIndex = blockEnd
                    continue
                }
            }

            paragraphBuffer.append(line)
            lineIndex += 1
        }

        flushParagraphBuffer()
        return elements
    }

    private nonisolated func inferredStructuredElementsForPDFPageText(_ pageText: String, pageNumber: Int) -> [StructuredElementWrapper] {
        let normalizedText = pageText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return [] }
        guard shouldAttemptStructuredRecoveryFromPDFPageText(normalizedText) else { return [] }

        let inferredElements = detectStructuredElementsInPageText(normalizedText, pageNumber: pageNumber)
        guard inferredElements.contains(where: { $0.elementType == "table" || $0.elementType == "list" }) else {
            return []
        }

        return inferredElements
    }

    private nonisolated func structuredElementMetrics(in elements: [StructuredElementWrapper]) -> (tables: Int, lists: Int, headers: Int) {
        (
            tables: elements.filter { $0.elementType == "table" }.count,
            lists: elements.filter { $0.elementType == "list" }.count,
            headers: elements.filter { $0.elementType == "title" }.count
        )
    }

    private nonisolated func preferredElementsWithLayoutTables(
        existingElements: [StructuredElementWrapper],
        layoutTables: [TableRegion],
        pageNumber: Int
    ) -> (elements: [StructuredElementWrapper], didPromote: Bool) {
        let promotedTables = promotedLayoutTableElements(from: layoutTables, pageNumber: pageNumber)
        guard !promotedTables.isEmpty else {
            return (existingElements, false)
        }

        let existingTableData = existingElements.compactMap(\.tableData)
        let bestExistingScore = existingTableData.map(tableQualityScore).max() ?? 0
        let bestPromotedScore = promotedTables.compactMap(\.tableData).map(tableQualityScore).max() ?? 0
        let existingTablesLookDegraded = existingTableData.contains { tableData in
            let rowCount = max(1, dataRows(for: tableData).count)
            let degradedRowRatio = Double(lowQualityRowIndices(for: tableData).count) / Double(rowCount)
            return tableQualityScore(tableData) < 0.72 || degradedRowRatio >= 0.25
        }

        guard existingTableData.isEmpty
                || bestPromotedScore > bestExistingScore + 0.05
                || (existingTablesLookDegraded && bestPromotedScore >= bestExistingScore - 0.02)
                || bestExistingScore < 0.60
        else {
            return (existingElements, false)
        }

        let preservedElements = existingElements.filter { $0.elementType != "table" }
        return (preservedElements + promotedTables, true)
    }

    private nonisolated func promotedLayoutTableElements(
        from layoutTables: [TableRegion],
        pageNumber: Int
    ) -> [StructuredElementWrapper] {
        layoutTables.compactMap { layoutTable in
            let normalizedRows = layoutTable.rows.map { row in
                row.map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }

            guard normalizedRows.count >= 2 else { return nil }
            guard tableQualityScore(rows: normalizedRows) >= 0.45 else { return nil }

            let headerRow = inferredHeaderRow(from: normalizedRows)
            let tableData = TableData(
                pageNumber: pageNumber,
                rows: normalizedRows,
                headerRow: headerRow,
                caption: nil,
                detectedEntities: []
            )

            return StructuredElementWrapper(
                text: tableData.textRepresentation,
                elementType: "table",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: tableData,
                listItems: nil,
                extractionSource: "layout_table",
                qualityScore: tableQualityScore(tableData)
            )
        }
    }

    private nonisolated func inferredHeaderRow(from rows: [[String]]) -> [String]? {
        guard let firstRow = rows.first, !firstRow.isEmpty else { return nil }

        let visibleCells = firstRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard visibleCells.count >= 2 else { return nil }

        let shortHeaderRatio = Double(visibleCells.filter { $0.count <= 32 }.count) / Double(visibleCells.count)
        let digitRatio = Double(visibleCells.filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }.count) / Double(visibleCells.count)
        let punctuationHeavyRatio = Double(visibleCells.filter {
            let punctuationCount = $0.unicodeScalars.filter { CharacterSet.punctuationCharacters.contains($0) }.count
            return punctuationCount > max(2, $0.count / 3)
        }.count) / Double(visibleCells.count)

        if shortHeaderRatio >= 0.6 && digitRatio <= 0.4 && punctuationHeavyRatio <= 0.4 {
            return firstRow
        }

        return nil
    }

    private nonisolated func tableQualityScore(_ tableData: TableData) -> Double {
        tableQualityScore(rows: tableData.rows)
    }

    private nonisolated func tableQualityScore(rows: [[String]]) -> Double {
        let normalizedRows = rows.map { row in
            row.map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let nonEmptyCells = normalizedRows.flatMap { $0 }.filter { !$0.isEmpty }
        guard !nonEmptyCells.isEmpty else { return 0 }

        let rowCount = normalizedRows.count
        let maxColumns = normalizedRows.map(\.count).max() ?? 0
        let visibleCellCount = Double(nonEmptyCells.count)
        let totalCellSlots = Double(max(1, rowCount * max(1, maxColumns)))
        let fillRatio = visibleCellCount / totalCellSlots
        let readableRatio = nonEmptyCells.map(tableCellReadabilityScore).reduce(0, +) / visibleCellCount

        let headerBonus: Double = inferredHeaderRow(from: normalizedRows) == nil ? 0 : 0.10
        let shapeBonus: Double = maxColumns >= 2 ? 0.15 : 0
        let rowBonus = min(0.15, Double(rowCount) / 8.0 * 0.15)

        let score = (readableRatio * 0.45) + (fillRatio * 0.15) + shapeBonus + rowBonus + headerBonus
        return min(1.0, max(0.0, score))
    }

    nonisolated func tableCellReadabilityScore(_ text: String) -> Double {
        let trimmed = OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let scalarCount = trimmed.unicodeScalars.count
        guard scalarCount > 0 else { return 0 }

        let printableCount = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) ||
            CharacterSet.whitespacesAndNewlines.contains($0) ||
            CharacterSet.punctuationCharacters.contains($0) ||
            CharacterSet.symbols.contains($0)
        }.count
        let printableRatio = Double(printableCount) / Double(scalarCount)

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let alphaNumericRatio = Double(letters + digits) / Double(scalarCount)

        var score = printableRatio * 0.45 + alphaNumericRatio * 0.25

        if letters >= 8 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            let confidence = recognizer.languageHypotheses(withMaximum: 1).values.max() ?? 0
            score += min(0.20, confidence * 0.20)
            if confidence < 0.15 {
                score -= 0.20
            }
        } else if digits > 0 {
            score += 0.10
        }

        return min(1.0, max(0.0, score))
    }

    private nonisolated func tableRowQualityScore(headers: [String], row: [String]) -> Double {
        let normalizedCells = row.map {
            OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let visibleCells = normalizedCells.filter { !$0.isEmpty }
        guard !visibleCells.isEmpty else { return 0 }

        let readability = visibleCells.map(tableCellReadabilityScore).reduce(0, +) / Double(visibleCells.count)
        let fillRatio = Double(visibleCells.count) / Double(max(1, max(headers.count, row.count)))
        let longValueBonus = visibleCells.contains { $0.count >= 18 } ? 0.08 : 0
        let repeatedNoisePenalty = visibleCells.contains {
            $0.range(of: #"^[^A-Za-z0-9]{3,}$"#, options: .regularExpression) != nil
        } ? 0.20 : 0

        return min(1.0, max(0.0, readability * 0.70 + fillRatio * 0.22 + longValueBonus - repeatedNoisePenalty))
    }

    private nonisolated func lowQualityRowIndices(for tableData: TableData) -> [Int] {
        let headers = inferredHeaders(for: tableData)
        return dataRows(for: tableData).enumerated().compactMap { rowIndex, row in
            let score = tableRowQualityScore(headers: headers, row: row)
            return score < 0.38 ? rowIndex : nil
        }
    }

    private nonisolated func shouldAttemptRegionCropRescue(
        analysis: PageComplexityAnalysis?,
        structuredContent: StructuredPageContent,
        hasRecoveredStructure: Bool,
        layoutTables: [TableRegion],
        pageText: String
    ) -> Bool {
        let tableSignal = (analysis?.tablePresence ?? 0) > 0.14 || !layoutTables.isEmpty
        let listSignal = (analysis?.listPatternStrength ?? 0) > 0.18
        let visualSignal = (analysis?.figurePresence ?? 0) > 0.12
            || (analysis?.chartPresence ?? 0) > 0.10
            || (analysis?.imagePresence ?? 0) > 0.22
        let degradedText = (analysis?.textQuality ?? 1.0) < 0.58 || (analysis?.fineTextRisk ?? 0) > 0.48
        let sparseText = pageText.trimmingCharacters(in: .whitespacesAndNewlines).count < 180
        let weakStructuredCapture = structuredContent.qualityScore < 0.68
        let missingExpectedStructure = !hasRecoveredStructure && (tableSignal || listSignal || visualSignal)

        return missingExpectedStructure
            || (weakStructuredCapture && (tableSignal || listSignal || visualSignal))
            || (degradedText && sparseText && (tableSignal || visualSignal))
    }

    private nonisolated func regionRescuePayload(
        from rescue: RegionRescueResult,
        pageNumber: Int
    ) -> RegionCropRescuePayload? {
        var elements: [StructuredElementWrapper] = []
        var tableCount = 0
        var listCount = 0
        var figureCount = 0

        for table in rescue.content.tables {
            let normalizedRows = table.rows.map { row in
                row.map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }

            guard normalizedRows.count >= 2 else { continue }
            guard tableQualityScore(rows: normalizedRows) >= 0.42 else { continue }

            let tableData = TableData(
                pageNumber: pageNumber,
                rows: normalizedRows,
                headerRow: table.hasHeader ? inferredHeaderRow(from: normalizedRows) : nil,
                caption: table.caption,
                detectedEntities: []
            )

            elements.append(StructuredElementWrapper(
                text: tableData.textRepresentation,
                elementType: "table",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: tableData,
                listItems: nil,
                extractionSource: "crop_rescue",
                qualityScore: tableQualityScore(tableData)
            ))
            tableCount += 1
        }

        for list in rescue.content.lists {
            let normalizedItems = list.items
                .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard normalizedItems.count >= 2 else { continue }

            elements.append(StructuredElementWrapper(
                text: normalizedItems.map { "• \($0)" }.joined(separator: "\n"),
                elementType: "list",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: nil,
                listItems: normalizedItems
            ))
            listCount += 1
        }

        for figure in rescue.content.figures {
            var figureParts: [String] = []
            if let caption = figure.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                figureParts.append(caption)
            }
            if let classification = figure.classification?.trimmingCharacters(in: .whitespacesAndNewlines), !classification.isEmpty {
                figureParts.append("Figure: \(classification)")
            }
            if let description = figure.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                figureParts.append(description)
            }

            let figureText = figureParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !figureText.isEmpty else { continue }

            elements.append(StructuredElementWrapper(
                text: figureText,
                elementType: "figure",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: nil,
                listItems: nil
            ))
            figureCount += 1
        }

        let paragraphText = regionRescueParagraphText(from: rescue)
        if !paragraphText.isEmpty {
            elements.append(StructuredElementWrapper(
                text: paragraphText,
                elementType: "paragraph",
                pageNumber: pageNumber,
                isAtomicChunk: false,
                detectedEntities: [],
                tableData: nil,
                listItems: nil
            ))
        }

        let pageText = rescue.readingOrderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !elements.isEmpty || !pageText.isEmpty else { return nil }

        return RegionCropRescuePayload(
            elements: elements,
            pageText: pageText,
            tableCount: tableCount,
            listCount: listCount,
            figureCount: figureCount
        )
    }

    private nonisolated func regionRescueParagraphText(from rescue: RegionRescueResult) -> String {
        rescue.content.textBlocks
            .filter { !$0.isFooter }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.03 {
                    return lhs.boundingBox.maxY > rhs.boundingBox.maxY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .map { OCRConfiguration.normalizeExtractedText($0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private nonisolated func regionTextQualityScore(_ text: String) -> Double {
        let trimmed = OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let baseScore = tableCellReadabilityScore(trimmed)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let lengthBonus = trimmed.count > 140 ? 0.10 : (trimmed.count > 70 ? 0.05 : 0)
        let densityBonus = min(0.15, Double(wordCount) / 80.0 * 0.15)
        let delimiterPenalty = trimmed.filter { $0 == "|" }.count > 8 ? 0.05 : 0

        return min(1.0, max(0.0, baseScore + lengthBonus + densityBonus - delimiterPenalty))
    }

    private nonisolated func preferredElementsWithRegionCropRescue(
        existingElements: [StructuredElementWrapper],
        rescuePayload: RegionCropRescuePayload,
        existingPageText: String,
        pageNumber: Int
    ) -> (elements: [StructuredElementWrapper], pageText: String?, didPromote: Bool) {
        var mergedElements = existingElements
        var didPromote = false

        let rescueTables = rescuePayload.elements.filter { $0.elementType == "table" }
        let rescueLists = rescuePayload.elements.filter { $0.elementType == "list" }
        let rescueFigures = rescuePayload.elements.filter { $0.elementType == "figure" }
        let rescueParagraphText = rescuePayload.elements.first { $0.elementType == "paragraph" }?.text ?? ""

        let existingTables = mergedElements.filter { $0.elementType == "table" }
        let existingLists = mergedElements.filter { $0.elementType == "list" }
        let existingFigures = mergedElements.filter { $0.elementType == "figure" }

        if !rescueTables.isEmpty {
            let rescueBestScore = rescueTables.compactMap(\.tableData).map(tableQualityScore).max() ?? 0
            let existingBestScore = existingTables.compactMap(\.tableData).map(tableQualityScore).max() ?? 0

            if existingTables.isEmpty || rescueBestScore > existingBestScore + 0.08 || existingBestScore < 0.42 {
                mergedElements.removeAll { $0.elementType == "table" }
                mergedElements.append(contentsOf: rescueTables)
                didPromote = true
            }
        }

        if !rescueLists.isEmpty && existingLists.isEmpty {
            mergedElements.append(contentsOf: rescueLists)
            didPromote = true
        }

        if !rescueFigures.isEmpty && existingFigures.isEmpty {
            mergedElements.append(contentsOf: rescueFigures)
            didPromote = true
        }

        var pageTextOverride: String? = nil
        if !rescueParagraphText.isEmpty {
            let existingParagraphText = mergedElements
                .filter { $0.elementType == "paragraph" }
                .map(\.text)
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let baselineText = existingParagraphText.isEmpty ? existingPageText : existingParagraphText
            let rescueScore = regionTextQualityScore(rescueParagraphText)
            let baselineScore = regionTextQualityScore(baselineText)

            if baselineText.isEmpty || rescueScore > baselineScore + 0.12 {
                mergedElements.removeAll { $0.elementType == "paragraph" }
                mergedElements.append(StructuredElementWrapper(
                    text: rescueParagraphText,
                    elementType: "paragraph",
                    pageNumber: pageNumber,
                    isAtomicChunk: false,
                    detectedEntities: [],
                    tableData: nil,
                    listItems: nil
                ))
                pageTextOverride = rescuePayload.pageText
                didPromote = true
            }
        } else if didPromote && existingPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pageTextOverride = rescuePayload.pageText
        }

        return (mergedElements, pageTextOverride, didPromote)
    }

    private nonisolated func markdownTableBlockEnd(in lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count, isPipeTableLine(lines[startIndex]) else { return nil }

        var lineIndex = startIndex
        var visibleLineCount = 0
        var dataLineCount = 0

        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { break }
            guard isPipeTableLine(trimmed) || isPipeTableSeparatorLine(trimmed) else { break }
            visibleLineCount += 1
            if !isPipeTableSeparatorLine(trimmed) {
                dataLineCount += 1
            }
            lineIndex += 1
        }

        guard visibleLineCount >= 2, dataLineCount >= 2 else { return nil }
        return lineIndex
    }

    private nonisolated func isPipeTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pipeCount = trimmed.filter { $0 == "|" }.count
        return pipeCount >= 2
    }

    private nonisolated func isPipeTableSeparatorLine(_ line: String) -> Bool {
        let cells = splitPipeTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private nonisolated func splitPipeTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed
            .components(separatedBy: "|")
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private nonisolated func parseMarkdownTable(lines: [String], pageNumber: Int, caption: String?) -> TableData? {
        let normalizedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard normalizedLines.count >= 2 else { return nil }

        var rows: [[String]] = []
        var sawSeparator = false

        for line in normalizedLines {
            if isPipeTableSeparatorLine(line) {
                sawSeparator = true
                continue
            }

            let cells = splitPipeTableCells(line)
            guard cells.count >= 2 else { continue }
            rows.append(cells)
        }

        guard rows.count >= 2 else { return nil }

        let headerRow = sawSeparator ? rows.first : nil
        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: headerRow,
            caption: caption,
            detectedEntities: []
        )
    }

    private nonisolated func keyValueBlockEnd(in lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count, isKeyValueTableLine(lines[startIndex]) else { return nil }

        var lineIndex = startIndex
        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isKeyValueTableLine(trimmed) else { break }
            lineIndex += 1
        }

        guard lineIndex - startIndex >= 2 else { return nil }
        return lineIndex
    }

    private nonisolated func isKeyValueTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("|") else { return false }

        if trimmed.contains("\t") {
            let cells = trimmed.components(separatedBy: "\t").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return cells.count >= 2
        }

        return trimmed.range(
            of: #"^.{1,90}?(?:\s+-\s+|\s+[–—]\s+|:\s+).{1,}$"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated func parseKeyValueTable(lines: [String], pageNumber: Int, caption: String?) -> TableData? {
        var rows: [[String]] = []

        for line in lines {
            guard let (key, value) = parseKeyValueLine(line) else { continue }
            rows.append([key, value])
        }

        guard rows.count >= 2 else { return nil }
        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: nil,
            caption: caption,
            detectedEntities: []
        )
    }

    private nonisolated func parseKeyValueLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("\t") {
            let cells = trimmed
                .components(separatedBy: "\t")
                .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { return nil }
            return (cells[0], cells.dropFirst().joined(separator: " | "))
        }

        let separators = [" - ", " – ", " — ", ": "]
        for separator in separators {
            let parts = trimmed.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }

            let key = OCRConfiguration.normalizeExtractedText(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = OCRConfiguration.normalizeExtractedText(parts.dropFirst().joined(separator: separator)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            return (key, value)
        }

        return nil
    }

    private nonisolated func parallelListTableBlockEnd(in lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count else { return nil }

        let firstHeader = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isParallelListHeaderLine(firstHeader) else { return nil }

        var lineIndex = startIndex + 1
        var firstColumnLines: [String] = []

        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard !isDocumentSectionHeadingLine(trimmed) else { return nil }

            if isParallelListHeaderLine(trimmed), firstColumnLines.count >= 2 {
                break
            }

            firstColumnLines.append(trimmed)
            lineIndex += 1
        }

        guard lineIndex < lines.count else { return nil }
        let secondHeader = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isParallelListHeaderLine(secondHeader), normalizeParallelListHeader(firstHeader) != normalizeParallelListHeader(secondHeader) else {
            return nil
        }

        lineIndex += 1
        var secondColumnLines: [String] = []

        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || isDocumentSectionHeadingLine(trimmed) {
                break
            }

            if isParallelListHeaderLine(trimmed), secondColumnLines.count >= 2 {
                break
            }

            secondColumnLines.append(trimmed)
            lineIndex += 1
        }

        let leftItems = collapseParallelListItems(firstColumnLines, preferStateLabels: true)
        let rightItems = collapseParallelListItems(secondColumnLines, preferStateLabels: false)

        guard leftItems.count >= 3, rightItems.count >= 3 else { return nil }
        guard abs(leftItems.count - rightItems.count) <= 1 else { return nil }

        return lineIndex
    }

    private nonisolated func parseParallelListTable(lines: [String], pageNumber: Int, caption: String?) -> TableData? {
        let normalizedLines = lines
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard normalizedLines.count >= 8 else { return nil }
        guard let splitIndex = parallelListSplitIndex(in: normalizedLines) else { return nil }

        let firstHeader = normalizedLines[0]
        let secondHeader = normalizedLines[splitIndex]
        let leftItems = collapseParallelListItems(Array(normalizedLines[1..<splitIndex]), preferStateLabels: true)
        let rightItems = collapseParallelListItems(Array(normalizedLines[(splitIndex + 1)...]), preferStateLabels: false)

        let pairCount = min(leftItems.count, rightItems.count)
        guard pairCount >= 3 else { return nil }

        let rows = (0..<pairCount).map { index in
            [leftItems[index], rightItems[index]]
        }

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: [firstHeader, secondHeader],
            caption: caption,
            detectedEntities: []
        )
    }

    private nonisolated func parallelListSplitIndex(in lines: [String]) -> Int? {
        guard lines.count >= 5 else { return nil }

        for index in 2..<(lines.count - 2) {
            let candidate = lines[index]
            guard isParallelListHeaderLine(candidate) else { continue }

            let leftItems = collapseParallelListItems(Array(lines[1..<index]), preferStateLabels: true)
            let rightItems = collapseParallelListItems(Array(lines[(index + 1)...]), preferStateLabels: false)

            guard leftItems.count >= 3, rightItems.count >= 3 else { continue }
            guard abs(leftItems.count - rightItems.count) <= 1 else { continue }

            return index
        }

        return nil
    }

    private nonisolated func collapseParallelListItems(_ lines: [String], preferStateLabels: Bool) -> [String] {
        var items: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let startsNew = current.isEmpty || parallelListLineStartsNewItem(
                trimmed,
                currentItem: current,
                preferStateLabels: preferStateLabels
            )

            if startsNew {
                if !current.isEmpty {
                    items.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                current = trimmed
            } else {
                current += " " + trimmed
            }
        }

        if !current.isEmpty {
            items.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return items
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated func parallelListLineStartsNewItem(
        _ line: String,
        currentItem: String,
        preferStateLabels: Bool
    ) -> Bool {
        if preferStateLabels,
           line.range(of: #"^(?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") {
            return true
        }

        if currentItem.contains("(") && !currentItem.contains(")") {
            return false
        }

        if let first = line.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first) {
            return false
        }

        if line.count <= 10 && currentItem.count <= 40 {
            return false
        }

        if preferStateLabels {
            return line.count <= 40
        }

        return line.count >= 6
    }

    private nonisolated func isParallelListHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count >= 4, trimmed.count <= 40 else { return false }
        guard !trimmed.contains("|") else { return false }
        guard !trimmed.hasSuffix(".") else { return false }
        guard trimmed.range(of: #"^\d+(?:\.\d+)*"#, options: .regularExpression) == nil else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count >= 1, words.count <= 5 else { return false }

        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        guard hasLetters else { return false }

        let uppercaseRatio = Double(trimmed.filter(\.isUppercase).count) / Double(max(1, trimmed.filter(\.isLetter).count))
        return uppercaseRatio >= 0.2 || trimmed == trimmed.uppercased()
    }

    private nonisolated func normalizeParallelListHeader(_ line: String) -> String {
        OCRConfiguration.normalizeExtractedText(line)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func preferredElementsWithRecoveredParallelKeyValueTable(
        existingElements: [StructuredElementWrapper],
        pageText: String,
        pageNumber: Int
    ) -> (elements: [StructuredElementWrapper], didPromote: Bool) {
        guard shouldAttemptStructuredRecoveryFromPDFPageText(pageText) else {
            return (existingElements, false)
        }

        guard let recoveredElement = recoveredParallelKeyValueTableElement(from: pageText, pageNumber: pageNumber) else {
            return (existingElements, false)
        }

        let candidateTables = existingElements.filter(looksLikeParallelKeyValueTableCandidate)
        let bestExistingScore = candidateTables.compactMap { element in
            element.qualityScore ?? element.tableData.map(tableQualityScore)
        }.max() ?? 0
        let recoveredScore = recoveredElement.qualityScore ?? 0
        let existingTablesLookDegraded = candidateTables.compactMap(\.tableData).contains { tableData in
            let rowCount = max(1, dataRows(for: tableData).count)
            let degradedRowRatio = Double(lowQualityRowIndices(for: tableData).count) / Double(rowCount)
            return tableQualityScore(tableData) < 0.74
                || degradedRowRatio >= 0.20
                || looksLikeMispairedIndicatorStateTable(tableData)
        }

        guard candidateTables.isEmpty
                || recoveredScore > bestExistingScore + 0.05
                || (existingTablesLookDegraded && recoveredScore >= bestExistingScore - 0.02)
                || bestExistingScore < 0.76
        else {
            return (existingElements, false)
        }

        let preserved = existingElements.filter { !looksLikeParallelKeyValueTableCandidate($0) }
        return (preserved + [recoveredElement], true)
    }

    private nonisolated func recoveredParallelKeyValueTableElement(from pageText: String, pageNumber: Int) -> StructuredElementWrapper? {
        if let indicatorTable = recoveredIndicatorStateTable(from: pageText, pageNumber: pageNumber) {
            let quality = max(0.94, tableQualityScore(indicatorTable))
            return StructuredElementWrapper(
                text: indicatorTable.textRepresentation,
                elementType: "table",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: indicatorTable,
                listItems: nil,
                extractionSource: "indicator_state_recovery",
                qualityScore: quality
            )
        }

        guard let tableData = recoveredParallelKeyValueTable(from: pageText, pageNumber: pageNumber) else {
            return nil
        }

        let quality = max(0.88, tableQualityScore(tableData))
        return StructuredElementWrapper(
            text: tableData.textRepresentation,
            elementType: "table",
            pageNumber: pageNumber,
            isAtomicChunk: true,
            detectedEntities: [],
            tableData: tableData,
            listItems: nil,
            extractionSource: "parallel_key_value_recovery",
            qualityScore: quality
        )
    }

    private nonisolated func recoveredIndicatorStateTable(from pageText: String, pageNumber: Int) -> TableData? {
        let normalizedLines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let labelHeaderIndex = normalizedLines.firstIndex(where: isIndicatorStateLabelHeaderLine(_:)) else {
            return nil
        }
        guard let statusHeaderIndex = normalizedLines[(labelHeaderIndex + 1)...].firstIndex(where: isIndicatorStateValueHeaderLine(_:)) else {
            return nil
        }

        let sectionEndIndex = normalizedLines[(statusHeaderIndex + 1)...].firstIndex(where: isDocumentSectionHeadingLine(_:))
            ?? normalizedLines.endIndex

        let stateItems = extractIndicatorStateLabels(from: Array(normalizedLines[(labelHeaderIndex + 1)..<statusHeaderIndex]))
        var statusRecovery = extractIndicatorStatusItems(from: Array(normalizedLines[(statusHeaderIndex + 1)..<sectionEndIndex]))

        if let trailingStateLabel = statusRecovery.trailingStateLabel,
           let trailingStatus = statusRecovery.trailingStatus
        {
            statusRecovery.statusItems.append(trailingStatus)
            if !stateItems.contains(where: { $0.caseInsensitiveCompare(trailingStateLabel) == .orderedSame }) {
                var recoveredStates = stateItems
                recoveredStates.append(trailingStateLabel)
                return buildRecoveredIndicatorStateTable(
                    stateItems: recoveredStates,
                    statusItems: statusRecovery.statusItems,
                    pageNumber: pageNumber
                )
            }
        }

        return buildRecoveredIndicatorStateTable(
            stateItems: stateItems,
            statusItems: statusRecovery.statusItems,
            pageNumber: pageNumber
        )
    }

    private nonisolated func buildRecoveredIndicatorStateTable(
        stateItems: [String],
        statusItems: [String],
        pageNumber: Int
    ) -> TableData? {
        guard stateItems.count >= 5, statusItems.count >= 5 else { return nil }
        guard abs(stateItems.count - statusItems.count) <= 1 else { return nil }

        let pairCount = min(stateItems.count, statusItems.count)
        let rows = (0..<pairCount).map { index in
            [stateItems[index], statusItems[index]]
        }

        guard tableQualityScore(rows: rows) >= 0.72 else { return nil }

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: ["Color of Light", "PLAUD Status"],
            caption: "Indicator Light",
            detectedEntities: []
        )
    }

    private nonisolated func recoveredParallelKeyValueTable(from pageText: String, pageNumber: Int) -> TableData? {
        let normalizedLines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let splitIndex = parallelListSplitIndex(in: normalizedLines) else {
            return nil
        }

        let leftItems = collapseParallelListItems(Array(normalizedLines[..<splitIndex]), preferStateLabels: true)
        let rightItems = collapseParallelListItems(Array(normalizedLines[(splitIndex + 1)...]), preferStateLabels: false)
        let pairCount = min(leftItems.count, rightItems.count)

        guard pairCount >= 3 else { return nil }

        let rows = (0..<pairCount).map { index in
            [leftItems[index], rightItems[index]]
        }

        guard tableQualityScore(rows: rows) >= 0.72 else { return nil }

        let headerCells = splitParallelListHeader(normalizedLines[splitIndex])
        let normalizedHeaderRow = headerCells.count == 2 ? headerCells : nil

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: normalizedHeaderRow,
            caption: normalizedHeaderRow?.joined(separator: " / "),
            detectedEntities: []
        )
    }

    private nonisolated func extractIndicatorStateLabels(from lines: [String]) -> [String] {
        var labels: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !isIndicatorStateLabelHeaderLine(trimmed), !isIndicatorStateValueHeaderLine(trimmed) else { continue }
            guard !isDocumentSectionHeadingLine(trimmed) else { continue }

            if startsNewIndicatorStateLabel(trimmed) {
                if let normalized = normalizeIndicatorStateLabel(current) {
                    labels.append(normalized)
                }
                current = trimmed
            } else if shouldAppendIndicatorStateContinuation(trimmed, currentItem: current) {
                current += " " + trimmed
            }
        }

        if let normalized = normalizeIndicatorStateLabel(current) {
            labels.append(normalized)
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for label in labels {
            let key = label.lowercased()
            if seen.insert(key).inserted {
                deduped.append(label)
            }
        }
        return deduped
    }

    private nonisolated func extractIndicatorStatusItems(from lines: [String]) -> (statusItems: [String], trailingStateLabel: String?, trailingStatus: String?) {
        var statusItems: [String] = []
        var current = ""
        var trailingStateLabel: String?
        var trailingStatus: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !isDocumentSectionHeadingLine(trimmed) else { break }

            if let splitPair = splitIndicatorStateAndStatusIfNeeded(trimmed) {
                if !current.isEmpty {
                    statusItems.append(normalizeIndicatorStatusText(current))
                    current = ""
                }
                trailingStateLabel = splitPair.label
                trailingStatus = splitPair.status
                continue
            }

            if current.isEmpty {
                current = trimmed
            } else if shouldAppendIndicatorStatusContinuation(trimmed, currentItem: current) {
                current += " " + trimmed
            } else {
                statusItems.append(normalizeIndicatorStatusText(current))
                current = trimmed
            }
        }

        if !current.isEmpty {
            statusItems.append(normalizeIndicatorStatusText(current))
        }

        return (
            statusItems.filter { !$0.isEmpty },
            trailingStateLabel,
            trailingStatus.map(normalizeIndicatorStatusText(_:))
        )
    }

    private nonisolated func splitIndicatorStateAndStatusIfNeeded(_ line: String) -> (label: String, status: String)? {
        let normalized = OCRConfiguration.normalizeExtractedText(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard startsNewIndicatorStateLabel(normalized) else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"^((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Za-z-]+(?:\s+[A-Za-z-]+)?(?:\s*\(\s*\d+(?:\s*(?:secs?|seconds?)\)?)?)?)\s+([A-Z].+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              let labelRange = Range(match.range(at: 1), in: normalized),
              let statusRange = Range(match.range(at: 2), in: normalized)
        else {
            return nil
        }

        guard let label = normalizeIndicatorStateLabel(String(normalized[labelRange])) else {
            return nil
        }

        let status = normalizeIndicatorStatusText(String(normalized[statusRange]))
        guard !status.isEmpty else { return nil }
        return (label, status)
    }

    private nonisolated func startsNewIndicatorStateLabel(_ line: String) -> Bool {
        line.range(
            of: #"^(?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated func shouldAppendIndicatorStateContinuation(_ line: String, currentItem: String) -> Bool {
        guard !currentItem.isEmpty else { return false }

        if currentItem.contains("(") && !currentItem.contains(")") {
            return true
        }

        if line.range(of: #"^\d+\s*(?:secs?|seconds?)\)?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
           currentItem.contains("(")
        {
            return true
        }

        return false
    }

    private nonisolated func shouldAppendIndicatorStatusContinuation(_ line: String, currentItem: String) -> Bool {
        guard !currentItem.isEmpty else { return false }

        if currentItem.contains("(") && !currentItem.contains(")") {
            return true
        }

        if let first = line.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first)
        {
            return true
        }

        let lowered = line.lowercased()
        let continuationPrefixes = ["and ", "or ", "to ", "for ", "with ", "without ", "of ", "the ", "over-", "under-"]
        return continuationPrefixes.contains(where: { lowered.hasPrefix($0) })
    }

    private nonisolated func normalizeIndicatorStateLabel(_ raw: String) -> String? {
        let normalized = OCRConfiguration.normalizeExtractedText(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"^((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow))\s+(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              let stateRange = Range(match.range(at: 1), in: normalized),
              let descriptorRange = Range(match.range(at: 2), in: normalized)
        else {
            return nil
        }

        let state = canonicalIndicatorStateToken(String(normalized[stateRange]))
        let descriptor = normalizeIndicatorDescriptor(String(normalized[descriptorRange]))
        guard !descriptor.isEmpty else { return nil }
        return "\(state) \(descriptor)"
    }

    private nonisolated func normalizeIndicatorDescriptor(_ descriptor: String) -> String {
        var normalized = OCRConfiguration.normalizeExtractedText(descriptor)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "cyanblue", with: "Cyan-blue", options: [.caseInsensitive])
            .replacingOccurrences(of: "cyan blue", with: "Cyan-blue", options: [.caseInsensitive])
            .replacingOccurrences(of: "secs", with: "secs", options: [.caseInsensitive])

        if normalized.range(of: #"\(\s*\d+\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let digits = normalized.filter(\.isNumber)
            if !digits.isEmpty {
                normalized = normalized.replacingOccurrences(
                    of: #"\(\s*\d+\s*$"#,
                    with: "(\(digits) secs)",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }

        let parts = normalized
            .split(whereSeparator: \.isWhitespace)
            .map { part -> String in
                let token = String(part)
                if token.hasPrefix("(") || token.range(of: #"^\d+$"#, options: [.regularExpression]) != nil {
                    return token
                }
                if token.lowercased() == "secs)" || token.lowercased() == "seconds)" {
                    return "secs)"
                }
                return token
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: "-")
            }

        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func normalizeIndicatorStatusText(_ text: String) -> String {
        OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func isIndicatorStateLabelHeaderLine(_ line: String) -> Bool {
        let normalized = normalizeParallelListHeader(line)
        return normalized == "color of light" || normalized == "indicator light"
    }

    private nonisolated func isIndicatorStateValueHeaderLine(_ line: String) -> Bool {
        let normalized = normalizeParallelListHeader(line)
        return normalized == "plaud status" || normalized == "status" || normalized.contains("status")
    }

    private nonisolated func looksLikeIndicatorStateLabel(_ text: String) -> Bool {
        let normalized = OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return startsNewIndicatorStateLabel(normalized)
    }

    private nonisolated func looksLikeMispairedIndicatorStateTable(_ tableData: TableData) -> Bool {
        let rows = dataRows(for: tableData)
        guard !rows.isEmpty else { return false }

        let tableSignals = [
            tableData.caption?.lowercased() ?? "",
            tableData.headerRow?.joined(separator: " ").lowercased() ?? "",
            rows.prefix(2).flatMap { $0 }.joined(separator: " ").lowercased()
        ].joined(separator: " ")

        let indicatorSignal = tableSignals.contains("color of light")
            || tableSignals.contains("plaud status")
            || tableSignals.contains("indicator light")
            || rows.contains { looksLikeIndicatorStateLabel($0.first ?? "") }

        guard indicatorSignal else { return false }

        let mismatchedRows = rows.filter { row in
            let left = row.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let right = row.count > 1 ? row[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

            guard !left.isEmpty, !right.isEmpty else { return true }
            if !looksLikeIndicatorStateLabel(left) { return true }
            if looksLikeIndicatorStateLabel(right) { return true }
            if isDocumentSectionHeadingLine(right) { return true }
            if right.count > 140 { return true }
            return false
        }.count

        return mismatchedRows > 0
    }

    private nonisolated func splitParallelListHeader(_ line: String) -> [String] {
        let normalized = OCRConfiguration.normalizeExtractedText(line)
        let separators = ["|", ":", " / ", " - ", " – ", " — "]

        for separator in separators {
            let components = normalized.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if components.count == 2 {
                return components
            }
        }

        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 4 else { return [] }
        let midpoint = words.count / 2
        let left = words[..<midpoint].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = words[midpoint...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return [] }
        return [left, right]
    }

    private nonisolated func looksLikeParallelKeyValueTableCandidate(_ element: StructuredElementWrapper) -> Bool {
        guard element.elementType == "table" else { return false }

        if let tableData = element.tableData {
            let visibleRows = tableData.rows.filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            guard visibleRows.count >= 3 else { return false }
            let maxColumns = visibleRows.map(\.count).max() ?? 0
            return maxColumns <= 3
        }

        let tableText = element.text.lowercased()
        let rowCount = tableText.components(separatedBy: "Row ").count - 1
        let keyValueMarkers = tableText.components(separatedBy: "=").count - 1
        return rowCount >= 3 && keyValueMarkers >= rowCount
    }

    private nonisolated func isRecoveredHeuristicTable(_ element: StructuredElementWrapper) -> Bool {
        guard element.elementType == "table" else { return false }

        switch element.extractionSource {
        case "parallel_key_value_recovery", "indicator_state_recovery", "text_inferred":
            return true
        default:
            return false
        }
    }

    private nonisolated func scientificNarrativeSignalCount(in text: String) -> Int {
        let lower = text.lowercased()
        let signals = [
            "abstract", "introduction", "methods", "materials", "results",
            "discussion", "conclusion", "references", "bibliography", "doi",
            "confidence interval", "randomized", "participants", "study"
        ]

        return signals.reduce(into: 0) { count, signal in
            if lower.contains(signal) {
                count += 1
            }
        }
    }

    private nonisolated func isLikelyScientificNarrativeSample(_ text: String) -> Bool {
        let lower = text.lowercased()
        let signalCount = scientificNarrativeSignalCount(in: lower)

        if signalCount >= 3 {
            return true
        }

        return signalCount >= 2 && (
            lower.contains("abstract")
            || lower.contains("references")
            || lower.contains("doi")
        )
    }

    private nonisolated func isLikelyScientificReferenceLine(_ line: String) -> Bool {
        let normalized = OCRConfiguration.normalizeExtractedText(line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()

        guard normalized.count >= 24 else { return false }

        let words = normalized.split(whereSeparator: \.isWhitespace)
        guard words.count >= 6 else { return false }

        let punctuationCount = normalized.unicodeScalars.filter {
            CharacterSet.punctuationCharacters.contains($0)
        }.count
        let punctuationRatio = Double(punctuationCount) / Double(max(1, normalized.count))
        let hasYear = lower.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) != nil
        let citationPatternMatches = [
            #"^\[?\d+\]?\s+[A-Z]"#,
            #"\bet al\b"#,
            #"\bdoi(?::|\s)"#,
            #"\bpmid\b"#,
            #"\b\d{4}\s*;\s*\d"#
        ].contains { pattern in
            normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        return citationPatternMatches || (hasYear && punctuationRatio >= 0.08 && (lower.contains("doi") || lower.contains("et al") || lower.contains(";")))
    }

    private nonisolated func isLikelyScientificReferencePage(_ pageText: String) -> Bool {
        let lines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 4 else { return false }

        let leadingHeading = lines.prefix(3).contains { line in
            let lower = line.lowercased()
            return lower == "references" || lower == "bibliography" || lower.hasPrefix("references ")
        }
        let referenceLineCount = lines.filter(isLikelyScientificReferenceLine(_:)).count
        let referenceLineRatio = Double(referenceLineCount) / Double(max(1, lines.count))

        if leadingHeading {
            return referenceLineCount >= 2 || lines.count >= 8
        }

        return referenceLineCount >= 4 && referenceLineRatio >= 0.28
    }

    private nonisolated func isNarrativeDominantPageText(_ pageText: String) -> Bool {
        let lines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 4 else { return false }

        let sentenceLikeLines = lines.filter { line in
            let wordCount = line.split(whereSeparator: \.isWhitespace).count
            return wordCount >= 8 && (line.count >= 60 || line.contains(".") || line.contains(";"))
        }.count
        let shortLabelLikeLines = lines.filter { line in
            let wordCount = line.split(whereSeparator: \.isWhitespace).count
            return wordCount <= 5 && line.count <= 42 && !line.hasSuffix(".")
        }.count

        let sentenceRatio = Double(sentenceLikeLines) / Double(max(1, lines.count))
        let shortLabelRatio = Double(shortLabelLikeLines) / Double(max(1, lines.count))
        return sentenceRatio >= 0.45 && shortLabelRatio <= 0.35
    }

    private nonisolated func shouldAttemptStructuredRecoveryFromPDFPageText(_ pageText: String) -> Bool {
        let normalized = pageText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }
        guard !isLikelyScientificReferencePage(normalized) else { return false }

        if isLikelyScientificNarrativeSample(normalized) && isNarrativeDominantPageText(normalized) {
            return false
        }

        return true
    }

    private nonisolated func normalizedHeadingMatchText(_ text: String) -> String {
        OCRConfiguration.normalizeExtractedText(text)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func titleMatchesTrustedPageText(_ title: String, pageText: String) -> Bool {
        let normalizedTitle = normalizedHeadingMatchText(title)
        let normalizedPageText = normalizedHeadingMatchText(pageText)

        guard !normalizedTitle.isEmpty else { return false }
        guard !normalizedPageText.isEmpty else { return true }

        if normalizedPageText.contains(normalizedTitle) {
            return true
        }

        let preservedShortTerms: Set<String> = ["ifu", "faq", "ocr", "doi", "fda", "iec"]
        let significantTerms = normalizedTitle
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 4 || preservedShortTerms.contains($0) }

        guard !significantTerms.isEmpty else { return true }

        let matchedTermCount = significantTerms.filter { normalizedPageText.contains($0) }.count
        if significantTerms.count == 1 {
            return matchedTermCount == 1
        }

        return matchedTermCount >= max(2, significantTerms.count - 1)
    }

    private nonisolated func canonicalIndicatorStateToken(_ token: String) -> String {
        let lower = token.lowercased()
        if lower.hasPrefix("flash") { return "Flashing" }
        if lower.hasPrefix("blink") { return "Blinking" }
        if lower.hasPrefix("puls") { return "Pulsing" }
        if lower == "solid" { return "Solid" }
        if lower == "steady" { return "Steady" }
        if lower == "rapid" { return "Rapid" }
        if lower == "slow" { return "Slow" }
        return token.capitalized
    }

    private nonisolated func isDocumentSectionHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: #"^\d+(?:\.\d+)*\.?[A-Z]"#, options: .regularExpression) != nil
            || trimmed.range(of: #"^\d+(?:\.\d+)*\.?\s"#, options: .regularExpression) != nil
    }

    private nonisolated func consumeCaptionCandidate(from paragraphBuffer: inout [String]) -> String? {
        guard let last = paragraphBuffer.last else { return nil }
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 90 else { return nil }
        guard !trimmed.hasSuffix(".") else { return nil }
        guard !trimmed.contains("|") else { return nil }
        guard !trimmed.contains(":") else { return nil }
        guard trimmed.range(of: #"[.!?]{2,}"#, options: .regularExpression) == nil else { return nil }

        paragraphBuffer.removeLast()
        return trimmed
    }

    // MARK: - Text Quality Validation

    /// Check if extracted text is likely garbage (bad OCR layer, encoding issues, etc.)
    /// Returns true if text quality is acceptable, false if OCR should be used instead
    ///
    /// This function is CRITICAL for bulletproof PDF ingestion. PDFs often have
    /// invisible/garbage text layers that PDFKit returns, but the visual content
    /// Checks if extracted text appears to be legitimate human-readable content
    /// vs. garbled/corrupt PDF text layer garbage.
    ///
    /// LANGUAGE-AGNOSTIC: Works for English, CJK, Arabic, Cyrillic, and mixed scripts.
    /// Uses NaturalLanguage framework for script detection instead of English-specific heuristics.
    /// is completely different. We must detect this and fall back to OCR.
    private func isTextQualityAcceptable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            Log.debug("[DocumentProcessor] Text too short to assess quality (\(trimmed.count) chars)", category: .ingestion)
            return false
        }

        // === CHECK 1: Printable character ratio ===
        // Garbage text often has control characters, private use area, etc.
        // This works for ALL scripts — letters, digits, punctuation, CJK, Arabic, etc.
        let printableCount = trimmed.unicodeScalars.filter { scalar in
            // Accept: letters (any script), numbers, punctuation, symbols, spaces
            let category = scalar.properties.generalCategory
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .spaceSeparator, .lineSeparator, .paragraphSeparator,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                 .nonspacingMark, .spacingMark, .enclosingMark:
                return true
            default:
                return false
            }
        }.count
        let printableRatio = Double(printableCount) / Double(trimmed.unicodeScalars.count)
        if printableRatio < 0.60 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Low printable ratio: \(String(format: "%.1f", printableRatio * 100))% (need 60%+)", category: .ingestion)
            return false
        }

        // === CHECK 2: Word length distribution (language-agnostic) ===
        // Garbage text often has very long "words" (no spaces in random bytes)
        // CJK is fine — even single chars are separated by whitespace in PDFKit output
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3 else {
            Log.debug("[DocumentProcessor] ❌ FAIL: Too few words to assess (\(words.count))", category: .ingestion)
            return false
        }

        let avgWordLength = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        if avgWordLength < 1.0 || avgWordLength > 25.0 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Abnormal avg word length: \(String(format: "%.1f", avgWordLength))", category: .ingestion)
            return false
        }

        // === CHECK 3: Gibberish detector (consecutive non-printable sequences) ===
        // Look for runs of 4+ characters that aren't letters, digits, or common punctuation
        let controlChars = trimmed.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory == .control ||
            scalar.properties.generalCategory == .privateUse ||
            scalar.properties.generalCategory == .surrogate ||
            scalar.properties.generalCategory == .unassigned
        }.count
        let controlRatio = Double(controlChars) / Double(max(1, trimmed.unicodeScalars.count))
        if controlRatio > 0.05 {
            Log.debug("[DocumentProcessor] ❌ FAIL: High control character ratio: \(String(format: "%.1f", controlRatio * 100))%", category: .ingestion)
            return false
        }

        // === CHECK 4: NaturalLanguage script/language detection ===
        // Use Apple's NLLanguageRecognizer to check if the text is recognizable as ANY language
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let languageHypotheses = recognizer.languageHypotheses(withMaximum: 3)

        // If NL can't identify ANY language with >10% confidence, it's likely garbage
        let bestConfidence = languageHypotheses.values.max() ?? 0
        if bestConfidence < 0.10 && trimmed.count > 50 {
            Log.debug("[DocumentProcessor] ❌ FAIL: NLLanguageRecognizer can't identify language (best conf: \(String(format: "%.1f%%", bestConfidence * 100)))", category: .ingestion)
            return false
        }

        // === CHECK 5: Character entropy (randomness detection) ===
        // Works for all scripts — random bytes have high entropy regardless of language
        let entropy = calculateCharacterEntropy(trimmed)
        if entropy > 6.0 {  // Raised from 5.5 to accommodate CJK (larger alphabet = higher natural entropy)
            Log.debug("[DocumentProcessor] ❌ FAIL: High entropy (random-looking): \(String(format: "%.2f", entropy)) bits/char", category: .ingestion)
            return false
        }

        // === CHECK 6: Repeated character detection ===
        // Garbage often has the same character repeated many times
        let charCounts = Dictionary(trimmed.map { ($0, 1) }, uniquingKeysWith: +)
        let maxCharFreq = Double(charCounts.values.max() ?? 0) / Double(trimmed.count)
        if maxCharFreq > 0.4 && trimmed.count > 30 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Dominant character frequency: \(String(format: "%.1f%%", maxCharFreq * 100))", category: .ingestion)
            return false
        }

        // === Diagnostic logging ===
        let sampleLength = min(100, trimmed.count)
        let sample = String(trimmed.prefix(sampleLength)).replacingOccurrences(of: "\n", with: "↵")
        let detectedLang = languageHypotheses.max(by: { $0.value < $1.value })?.key.rawValue ?? "?"
        Log.debug("[DocumentProcessor] ✓ PASS: Text quality OK (printable=\(String(format: "%.0f", printableRatio * 100))%, entropy=\(String(format: "%.1f", entropy)), lang=\(detectedLang)) Sample: \"\(sample)...\"", category: .ingestion)

        return true
    }

    /// Remove isolated garbage lines from extracted PDF page text before page assembly.
    /// This is intentionally page-scoped so we preserve page mapping and only strip the
    /// obviously bad lines that survive page-level extraction in otherwise readable PDFs.
    private func removeGarbageLinesFromExtractedPages(
        _ pageTexts: [String],
        source: String
    ) -> [String] {
        var totalRemoved = 0
        var affectedPages = 0
        var cleanedPages: [String] = []
        cleanedPages.reserveCapacity(pageTexts.count)

        for (index, pageText) in pageTexts.enumerated() {
            guard !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                cleanedPages.append(pageText)
                continue
            }

            let (cleaned, removedCount) = OCRConfiguration.filterGarbageText(
                pageText,
                revertIfTooAggressive: false
            )
            if removedCount > 0 {
                totalRemoved += removedCount
                affectedPages += 1
                Log.debug(
                    "[DocumentProcessor] Removed \(removedCount) garbage line(s) from page \(index + 1) (\(source))",
                    category: .ingestion
                )
            }
            cleanedPages.append(cleaned)
        }

        if totalRemoved > 0 {
            Log.info(
                "[DocumentProcessor] Garbage filter removed \(totalRemoved) line(s) across \(affectedPages) page(s) (\(source))",
                category: .ingestion
            )
        }

        return cleanedPages
    }

    /// Calculate Shannon entropy of text (bits per character)
    /// Higher values indicate more randomness (potential garbage)
    private func calculateCharacterEntropy(_ text: String) -> Double {
        let lowered = text.lowercased()
        var frequencies: [Character: Int] = [:]

        for char in lowered where char.isLetter || char.isNumber || char == " " {
            frequencies[char, default: 0] += 1
        }

        let total = Double(frequencies.values.reduce(0, +))
        guard total > 0 else { return 0 }

        var entropy: Double = 0
        for count in frequencies.values {
            let probability = Double(count) / total
            if probability > 0 {
                entropy -= probability * log2(probability)
            }
        }

        return entropy
    }

    // MARK: - Header/Footer Removal

    /// Remove repeated headers and footers from multi-page document text
    /// Detects patterns that appear at the start/end of multiple pages
    private func removeRepeatedHeadersFooters(from pageTexts: [String]) -> [String] {
        guard pageTexts.count >= 3 else { return pageTexts }  // Need multiple pages to detect patterns

        // Collect first and last lines from each page
        var firstLines: [String: Int] = [:]  // line → occurrence count
        var lastLines: [String: Int] = [:]

        for pageText in pageTexts {
            let lines = pageText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Get first 2 non-empty lines (headers)
            for line in lines.prefix(2) {
                let normalized = normalizeForComparison(line)
                if !normalized.isEmpty && normalized.count < 100 {  // Headers are typically short
                    firstLines[normalized, default: 0] += 1
                }
            }

            // Get last 2 non-empty lines (footers)
            for line in lines.suffix(2) {
                let normalized = normalizeForComparison(line)
                if !normalized.isEmpty && normalized.count < 100 {
                    lastLines[normalized, default: 0] += 1
                }
            }
        }

        // Find patterns that appear in >50% of pages
        let threshold = pageTexts.count / 2
        let repeatedHeaders = Set(firstLines.filter { $0.value > threshold }.keys)
        let repeatedFooters = Set(lastLines.filter { $0.value > threshold }.keys)

        if repeatedHeaders.isEmpty && repeatedFooters.isEmpty {
            return pageTexts  // No repeated patterns found
        }

        Log.debug(
            "[DocumentProcessor] Removing \(repeatedHeaders.count) repeated headers, \(repeatedFooters.count) footers",
            category: .ingestion
        )

        // Remove the repeated lines from each page
        return pageTexts.map { pageText in
            var lines = pageText.components(separatedBy: .newlines)

            // Remove headers (from start)
            while let firstLine = lines.first {
                let normalized = normalizeForComparison(firstLine)
                if repeatedHeaders.contains(normalized) || isPageNumber(firstLine) {
                    lines.removeFirst()
                } else if firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.removeFirst()  // Skip empty lines at start
                } else {
                    break
                }
            }

            // Remove footers (from end)
            while let lastLine = lines.last {
                let normalized = normalizeForComparison(lastLine)
                if repeatedFooters.contains(normalized) || isPageNumber(lastLine) {
                    lines.removeLast()
                } else if lastLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.removeLast()  // Skip empty lines at end
                } else {
                    break
                }
            }

            return lines.joined(separator: "\n")
        }
    }

    /// Normalize text for header/footer comparison (ignore case, extra spaces, page numbers)
    private func normalizeForComparison(_ text: String) -> String {
        var normalized = text.lowercased()
            .trimmingCharacters(in: .whitespaces)

        // Remove page numbers for comparison (they change per page but pattern is same)
        // Matches: "Page 1", "1 of 42", "- 5 -", etc.
        let pageNumberPatterns = [
            "page\\s*\\d+",
            "\\d+\\s*of\\s*\\d+",
            "-\\s*\\d+\\s*-",
            "^\\d+$"
        ]

        for pattern in pageNumberPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                normalized = regex.stringByReplacingMatches(
                    in: normalized,
                    options: [],
                    range: NSRange(normalized.startIndex..., in: normalized),
                    withTemplate: ""
                )
            }
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    /// Check if a line is just a page number
    private func isPageNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Common page number patterns
        let patterns = [
            "^\\d+$",                           // Just a number: "5"
            "^page\\s*\\d+$",                   // "Page 5"
            "^\\d+\\s*of\\s*\\d+$",             // "5 of 42"
            "^-\\s*\\d+\\s*-$",                 // "- 5 -"
            "^\\[\\d+\\]$",                     // "[5]"
            "^\\(\\d+\\)$",                     // "(5)"
            "^\\d{1,3}\\s+\\d{1,3}$",           // "2 2" (doubled page number from dual columns)
            "^\\d{1,3}\\s*[-—–]\\s*\\d{0,3}$",  // "3 - 5", "2-", "2 — 7" (section-page)
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - PDF Loading with Encryption Detection

    /// Load a PDF document with encryption/password detection.
    /// Attempts empty-password unlock for owner-encrypted PDFs.
    /// - Parameters:
    ///   - url: Path to the PDF file
    ///   - context: Calling function name for logging
    /// - Returns: Loaded and unlocked PDFDocument
    /// - Throws: `pdfEncrypted` if password-locked, `pdfLoadFailed` if corrupt/unreadable
    private func loadPDF(url: URL, context: String = "PDF") throws -> PDFDocument {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] \(context) load failed: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

        if pdfDocument.isEncrypted {
            if pdfDocument.isLocked {
                // Try empty password — many "encrypted" PDFs have no user password
                if !pdfDocument.unlock(withPassword: "") {
                    Log.error("[DocumentProcessor] \(context) is password-protected: \(url.lastPathComponent)", category: .ingestion)
                    throw DocumentProcessingError.pdfEncrypted
                }
                Log.info("[DocumentProcessor] \(context) unlocked with empty password", category: .ingestion)
            } else {
                Log.debug("[DocumentProcessor] \(context) has owner encryption (restrictions only)", category: .ingestion)
            }
        }

        return pdfDocument
    }

    /// Extract text from PDF with page tracking for semantic chunking
    /// Uses spatial-aware extraction to handle multi-column layouts correctly
    /// ADAPTIVE OCR: Pre-scans pages to classify complexity, skips OCR for simple pages
    private func extractTextFromPDFWithPages(url: URL) async throws -> (text: String, pageInfo: PageInfo) {
        let pdfDocument = try loadPDF(url: url, context: "PDF")

        let pageCount = pdfDocument.pageCount
        Log.debug("[DocumentProcessor] PDF pages: \(pageCount)", category: .ingestion)

        // Edge case: Empty PDF
        guard pageCount > 0 else {
            Log.warning("[DocumentProcessor] PDF has zero pages", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE -1: DOCUMENT-LEVEL TEXT LAYER VALIDATION
        // ═══════════════════════════════════════════════════════════════════════
        // Many PDFs (Kia, Hyundai, Asian-publisher manuals) use font substitution
        // ciphers: the text layer is a character-shifted encoding that LOOKS like
        // normal text to naive analysis (printable ASCII, normal word lengths,
        // NLLanguageRecognizer detects "Dutch" at 56% confidence) but is completely
        // garbled. The ONLY reliable detection is to OCR a sample page and compare
        // the result to PDFKit's text layer. If they don't match, the entire
        // document's text layer is unusable and ALL pages must go through Vision OCR.
        //
        // This runs ONCE per document (~200-500ms) and prevents the catastrophic
        // failure where 93% of content is silently lost to garbled text acceptance.
        // ═══════════════════════════════════════════════════════════════════════
        let startPageIdx = 0
        let endPageIdx = pageCount - 1
        let documentTextLayerGarbled: Bool
        textLayerValidation: do {
            // Sample 3 spread-out pages to get representative PDFKit text
            let sliceCount = (endPageIdx - startPageIdx) + 1
            let sampleIndices = sliceCount <= 3
                ? Array(startPageIdx...endPageIdx)
                : [startPageIdx, startPageIdx + sliceCount / 3, startPageIdx + 2 * sliceCount / 3]

            var bestSampleText = ""
            var bestSamplePage: PDFPage?

            for idx in sampleIndices {
                guard let page = pdfDocument.page(at: idx) else { continue }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count > bestSampleText.count {
                    bestSampleText = text
                    bestSamplePage = page
                }
            }

            // If no text layer at all, not garbled — just needs OCR (handled by existing flow)
            guard bestSampleText.count >= 50, let samplePage = bestSamplePage else {
                documentTextLayerGarbled = false
                Log.debug("[DocumentProcessor] Text layer validation: no/minimal text layer, skipping validation", category: .ingestion)
                break textLayerValidation
            }

            // Render the best sample page and run quick OCR
            emitProgress(stage: "validating", detail: "🔍 Validating text layer...", page: nil, totalPages: pageCount)
            guard let sampleImage = renderPDFPageAsImage(page: samplePage) else {
                documentTextLayerGarbled = false
                Log.warning("[DocumentProcessor] Text layer validation: failed to render sample page", category: .ingestion)
                break textLayerValidation
            }

            let ocrObservations: [VNRecognizedTextObservation]
            do {
                ocrObservations = try await performOCRWithObservationsAsync(on: sampleImage)
            } catch {
                documentTextLayerGarbled = false
                Log.warning("[DocumentProcessor] Text layer validation: OCR failed on sample page (\(error.localizedDescription)), assuming text layer OK", category: .ingestion)
                break textLayerValidation
            }
            let ocrWords: Set<String> = Set(
                ocrObservations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }
                    .map { String($0) }
                    .filter { $0.count >= 3 }
            )

            let pdfKitWords: Set<String> = Set(
                bestSampleText.lowercased()
                    .split(whereSeparator: { !$0.isLetter })
                    .map { String($0) }
                    .filter { $0.count >= 3 }
            )

            // Jaccard similarity: |intersection| / |union|
            guard !ocrWords.isEmpty && !pdfKitWords.isEmpty else {
                documentTextLayerGarbled = false
                Log.debug("[DocumentProcessor] Text layer validation: insufficient words for comparison (OCR: \(ocrWords.count), PDFKit: \(pdfKitWords.count))", category: .ingestion)
                break textLayerValidation
            }

            let intersection = ocrWords.intersection(pdfKitWords).count
            let union = ocrWords.union(pdfKitWords).count
            let jaccard = Double(intersection) / Double(union)

            Log.info("[DocumentProcessor] Text layer validation: Jaccard similarity = \(String(format: "%.3f", jaccard)) (OCR words: \(ocrWords.count), PDFKit words: \(pdfKitWords.count), shared: \(intersection))", category: .ingestion)

            if jaccard < 0.15 {
                // Text layer does NOT match what's visually on the page
                // This is a font substitution cipher — text layer is USELESS
                documentTextLayerGarbled = true
                Log.warning("[DocumentProcessor] ⚠️ GARBLED TEXT LAYER DETECTED (Jaccard=\(String(format: "%.3f", jaccard))). Font substitution cipher suspected. ALL pages will use Vision OCR.", category: .ingestion)

                // Log sample comparison for debugging
                let ocrSample = Array(ocrWords.prefix(5)).joined(separator: ", ")
                let pdfSample = Array(pdfKitWords.prefix(5)).joined(separator: ", ")
                Log.info("[DocumentProcessor] OCR sample: [\(ocrSample)] vs PDFKit sample: [\(pdfSample)]", category: .ingestion)
            } else {
                // Main Jaccard passed. For marginal scores (0.15–0.45), run a secondary
                // check for AutoCAD SHX / CAD font encoding (Gap 3 fix).
                // SHX fonts score Jaccard 0.20–0.40 because ASCII digits survive, but
                // dimension symbols (±, °, Ø) and special chars are remapped.
                // Numeric tokens (dimensions, part numbers) are format-stable and DON'T
                // survive SHX encoding — "M10" becomes garbage, "25.4" becomes "253".
                var shxGarbled = false
                if jaccard < 0.45 {
                    let numericPattern = #"\b\d+\.?\d*\s*[A-Za-z]{0,4}\b"#
                    if let numericRegex = try? NSRegularExpression(pattern: numericPattern) {
                        let extractNumerics = { (text: String) -> Set<String> in
                            let range = NSRange(text.startIndex..., in: text)
                            return Set(
                                numericRegex.matches(in: text, range: range)
                                    .compactMap { Range($0.range, in: text).map { String(text[$0]).lowercased().trimmingCharacters(in: .whitespaces) } }
                                    .filter { $0.count >= 2 }
                            )
                        }
                        let ocrText = ocrObservations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                        let ocrNumerics = extractNumerics(ocrText)
                        let pdfNumerics = extractNumerics(bestSampleText)
                        // Only fire if there's enough numeric content to be meaningful
                        // (5+ tokens ensures we're looking at a real engineering/CAD document)
                        if pdfNumerics.count >= 5 {
                            let numIntersection = ocrNumerics.intersection(pdfNumerics).count
                            let numUnion = ocrNumerics.union(pdfNumerics).count
                            let numericJaccard = numUnion > 0 ? Double(numIntersection) / Double(numUnion) : 1.0
                            Log.info("[DocumentProcessor] SHX secondary check: \(pdfNumerics.count) PDF numerics, \(ocrNumerics.count) OCR numerics, numeric Jaccard=\(String(format: "%.3f", numericJaccard))", category: .ingestion)
                            if numericJaccard < 0.25 {
                                shxGarbled = true
                                Log.warning("[DocumentProcessor] ⚠️ SHX FONT ENCODING DETECTED (numeric Jaccard=\(String(format: "%.3f", numericJaccard)), text Jaccard=\(String(format: "%.3f", jaccard))). Likely AutoCAD/CAD/SHX PDF. ALL pages → Vision OCR.", category: .ingestion)
                            }
                        }
                    }
                }
                documentTextLayerGarbled = shxGarbled
                if !shxGarbled {
                    Log.debug("[DocumentProcessor] ✓ Text layer validated: matches OCR output (Jaccard=\(String(format: "%.3f", jaccard)))", category: .ingestion)
                }
            }
        }

        // PHASE 0: ADAPTIVE COMPLEXITY PRE-SCAN (~5-10ms per page)
        // Quickly analyze all pages to determine OCR strategy BEFORE rendering images
        // This saves massive time by skipping OCR entirely for simple text pages
        let complexityStartTime = Date()
        var complexityAnalyses: [PageComplexityAnalysis] = []

        // Batch analyze pages (runs concurrently, very fast)
        let pagesToAnalyze: [(PDFPage, Int)] = (startPageIdx...endPageIdx).compactMap { index in
            guard let page = pdfDocument.page(at: index) else { return nil }
            return (page, index + 1)
        }

        complexityAnalyses = await PageComplexityAnalyzer.shared.analyzeBatch(pages: pagesToAnalyze)

        // Log summary and estimate time savings
        let complexityTime = Date().timeIntervalSince(complexityStartTime) * 1000
        PageComplexityAnalyzer.shared.logBatchSummary(complexityAnalyses)
        Log.debug("[DocumentProcessor] Complexity pre-scan: \(String(format: "%.0f", complexityTime))ms for \(pageCount) pages", category: .ingestion)

        // Build lookup map for quick access during processing
        var pageComplexity: [Int: PageComplexityAnalysis] = [:]
        for analysis in complexityAnalyses {
            pageComplexity[analysis.pageNumber] = analysis
        }

        // PHASE 1: Extract text from all pages with ADAPTIVE parallel processing
        // Use device-specific concurrency to maximize hardware utilization
        // OCR runs on Neural Engine (ANE), so concurrency is tuned per device tier
        let maxConcurrentPages = DeviceCapabilityService.shared.ocrExtractionConcurrency
        Log.debug("[DocumentProcessor] Using \(maxConcurrentPages) concurrent pages for OCR (tier: \(DeviceCapabilityService.shared.tier.rawValue))", category: .ingestion)

        // PHASE 1.5: DYNAMIC VOCABULARY EXTRACTION
        // Extract domain-specific terms from PDFKit's rough text layer BEFORE Vision OCR.
        // This implements the "document teaches Vision what to look for" approach:
        //   1. PDFKit gives us fast, rough text (free — no Neural Engine needed)
        //   2. We mine it for acronyms, codes, technical terms, compound units
        //   3. Feed those as customWords to Vision, so its neural network knows
        //      "these ARE real words, don't autocorrect them"
        // This scales to ANY domain without hardcoding domain-specific vocabulary.
        let roughDocumentText: String
        if documentTextLayerGarbled {
            roughDocumentText = "" // PDFKit text is garbled — don't mine it for vocab
            Log.debug("[DocumentProcessor] Skipping dynamic vocabulary extraction (garbled text layer)", category: .ingestion)
        } else {
            roughDocumentText = (0..<min(pageCount, 50)).compactMap { i in
                pdfDocument.page(at: i)?.string
            }.joined(separator: "\n")
        }

        let documentCustomWords = OCRConfiguration.customWords(forDocumentText: roughDocumentText)
        self.currentDocumentCustomWords = documentCustomWords
        Log.debug("[DocumentProcessor] Dynamic vocabulary: \(documentCustomWords.count - OCRConfiguration.universalCustomWords.count) document-specific terms extracted", category: .ingestion)

        // Result container for parallel extraction
        struct PageExtractionResult: Sendable {
            let pageIndex: Int
            let text: String
            let usedOCR: Bool
            let usedSpatial: Bool
            let ocrCharCount: Int
            let noTextLayer: Bool
        }

        // MEMORY OPTIMIZATION: Page data struct for batch rendering
        // We now render only maxConcurrentPages at a time instead of all pages upfront
        // Each 1260×1785 RGBA image ≈ 9MB; 542 pages would be 4.8GB if pre-rendered!
        struct PageData: Sendable {
            let pageIndex: Int
            let pageString: String?
            let pageImage: CIImage?
            let hasText: Bool
            let textQualityOK: Bool
            /// True when complexity analysis detected table or dense numeric content.
            /// Forces Vision OCR even when PDFKit text quality looks acceptable,
            /// because PDFKit scrambles table cell values and column alignment.
            let requiresOCRForAccuracy: Bool
        }

        // Parallel extraction using TaskGroup with controlled concurrency
        var results: [PageExtractionResult] = []

        // MEMORY-SAFE RENDERING: Limit how many full-resolution page images are alive at once.
        // At 360 DPI, each page = 6210×11040px ≈ 206 MB (opaque RGB).
        // Previous code rendered maxConcurrentPages (10) images at once = 2+ GB → OOM crash.
        // Now we sub-batch: render pdfRenderingConcurrency (3) images → OCR them → release → next.
        // Quality is UNCHANGED: same 360 DPI, same preprocessing, same Vision accuracy.
        let maxRenderConcurrency = DeviceCapabilityService.shared.pdfRenderingConcurrency
        Log.info("[DocumentProcessor] Memory-safe rendering: max \(maxRenderConcurrency) page images alive at once (\(maxRenderConcurrency) × ~206 MB = ~\(maxRenderConcurrency * 206) MB)", category: .ingestion)

        // Process pages in render-safe sub-batches
        // Outer stride: groups pages for progress reporting (keeps maxConcurrentPages for ANE pipeline)
        // Inner stride: limits concurrent full-res images to pdfRenderingConcurrency
        for batchStart in stride(from: startPageIdx, to: endPageIdx + 1, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, endPageIdx + 1)

            // Sub-batch rendering: render only maxRenderConcurrency pages at a time
            for renderStart in stride(from: batchStart, to: batchEnd, by: maxRenderConcurrency) {
                let renderEnd = min(renderStart + maxRenderConcurrency, batchEnd)
                let subBatchIndices = renderStart..<renderEnd

            // MEMORY-SAFE: Render only this sub-batch's pages (maxRenderConcurrency at a time)
            // GPU ACCELERATION: Apply preprocessing filters for better OCR accuracy
            // ADAPTIVE OCR: Only render images for pages that need OCR based on complexity analysis
            var batchPageData: [PageData] = []
            for pageIndex in subBatchIndices {
                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        batchPageData.append(PageData(pageIndex: pageIndex, pageString: nil, pageImage: nil, hasText: false, textQualityOK: false, requiresOCRForAccuracy: false))
                        return
                    }

                    let pageNumber = pageIndex + 1
                    let complexity = pageComplexity[pageNumber]
                    let strategy = complexity?.processingStrategy ?? .enhancedOCR  // Default to safe
                    let renderScale = preferredOCRRenderScale(for: complexity, documentTextLayerGarbled: documentTextLayerGarbled)
                    let fidelityForcesVision = shouldForceVisionForAdaptiveRecovery(
                        analysis: complexity,
                        strategy: strategy,
                        documentTextLayerGarbled: documentTextLayerGarbled
                    )

                    let pageString = page.string

                    // Detect if this page has table/numeric content that REQUIRES Vision OCR
                    // even when PDFKit text quality looks acceptable.
                    // PDFKit text extraction scrambles table cell values and column alignment.
                    let requiresOCRForAccuracy: Bool = {
                        guard let c = complexity else { return false }
                        return c.tablePresence > 0.2 || c.numericDensity > 0.3
                    }()

                    // ADAPTIVE: Only render image if this page actually needs OCR
                    // Simple pages (.directText, .spatialText) skip expensive image rendering entirely!
                    // EXCEPTION: If text layer is garbled (font substitution cipher), ALL pages need OCR
                    var pageImage: CIImage? = nil
                    if documentTextLayerGarbled || fidelityForcesVision || strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR {
                        // Complex page - render and preprocess image with adaptive strategy
                        if renderScale > 5.0 {
                            Log.info("[DocumentProcessor] Page \(pageNumber): fine text risk \(Int((complexity?.fineTextRisk ?? 0) * 100))% → rendering at \(Int(72 * renderScale)) DPI", category: .ingestion)
                        }
                        pageImage = renderPDFPageAsImage(page: page, scale: renderScale)
                        if let image = pageImage {
                            let textQuality = complexity?.textQuality ?? 0.7
                            let isScanned = complexity?.processingStrategy == .fullOCR
                            let hasText = (pageString?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 10
                            pageImage = preprocessImageForOCR(
                                image,
                                textQuality: textQuality,
                                hasNativeTextLayer: hasText,
                                isScanned: isScanned
                            )
                        }
                    }
                    // else: Skip image rendering - saves ~50-100ms per simple page!

                    // Pre-compute text presence and quality checks
                    let hasText = pageString != nil && !pageString!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    // When text layer is garbled (font substitution cipher), NEVER trust PDFKit text
                    // If the page is mixed-mode scanned, also do not trust the incomplete native text layer
                    let isMixedMode = complexity?.isMixedModeScanned ?? false
                    let textQualityOK = !documentTextLayerGarbled && !isMixedMode && hasText && isTextQualityAcceptable(pageString!)

                    traceIngestionDecision(
                        pageNumber: pageNumber,
                        strategy: fidelityForcesVision && strategy == .spatialText ? "\(strategy.description)+fidelity" : strategy.description,
                        hasText: hasText,
                        textQualityOK: textQualityOK,
                        requiresTableOCR: requiresOCRForAccuracy,
                        mode: fidelityForcesVision ? "ocr-extraction-fidelity" : "ocr-extraction"
                    )

                    // For pages with good text quality that DON'T have tables, try spatial extraction
                    // Table pages skip spatial — their text will come from Vision OCR instead
                    var effectiveString = pageString
                    if hasText && textQualityOK && !requiresOCRForAccuracy {
                        if let spatialText = extractTextWithSpatialOrdering(from: page), !spatialText.isEmpty {
                            effectiveString = spatialText
                        } else {
                            // Second of the two silent fallbacks to raw `page.string`. Same reason
                            // as the one in the batch path: the fallback does not preserve column
                            // order, so a page taking it is a quality event worth seeing.
                            Log.warning(
                                "[DocumentProcessor] Page \(pageIndex + 1): spatial extraction "
                                    + "produced nothing; using raw page text (column order not preserved)",
                                category: .ingestion
                            )
                        }
                    }

                    batchPageData.append(PageData(pageIndex: pageIndex, pageString: effectiveString, pageImage: pageImage, hasText: hasText, textQualityOK: textQualityOK, requiresOCRForAccuracy: requiresOCRForAccuracy))
                }
            }

            let batchResults = await withTaskGroup(of: PageExtractionResult.self) { group in
                for (batchOffset, pageIndex) in subBatchIndices.enumerated() {
                    let pageData = batchPageData[batchOffset]

                    group.addTask {
                        if Task.isCancelled {
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: "",
                                usedOCR: false,
                                usedSpatial: false,
                                ocrCharCount: 0,
                                noTextLayer: false
                            )
                        }

                        let pageStartTime = Date()
                        let pageNumber = pageIndex + 1

                        let pageText = pageData.pageString
                        // Use pre-computed values to avoid MainActor calls
                        let hasText = pageData.hasText
                        let textQualityOK = pageData.textQualityOK
                        let requiresOCRForAccuracy = pageData.requiresOCRForAccuracy

                        if requiresOCRForAccuracy && pageData.pageImage != nil {
                            // ═══════════════════════════════════════════════════════════
                            // TABLE/NUMERIC PAGE: Force Vision OCR for accurate data
                            // PDFKit text extraction DESTROYS table structure —
                            // column values get scrambled, decimals get misread,
                            // and cell boundaries are lost. Vision OCR with
                            // RecognizeDocumentsRequest preserves exact numeric values.
                            // ═══════════════════════════════════════════════════════════
                            Log.debug("   🔬 Page \(pageNumber): Table/numeric content detected, forcing Vision OCR for accuracy", category: .ingestion)
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount), OCR (table accuracy)")
                            }

                            if let pageImage = pageData.pageImage,
                               let (ocrText, _) = try? await self.performEnhancedSpatialOCR(on: pageImage, pageNumber: pageNumber),
                               !ocrText.isEmpty {
                                let pageTime = Date().timeIntervalSince(pageStartTime)
                                // Log comparison for debugging
                                let pdfKitChars = pageText?.count ?? 0
                                Log.debug("   ✓ Page \(pageNumber): Vision OCR \(ocrText.count) chars vs PDFKit \(pdfKitChars) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "table-forced-ocr",
                                    chars: ocrText.count,
                                    duration: pageTime,
                                    extra: [("pdfkitChars", "\(pdfKitChars)")]
                                )

                                return PageExtractionResult(
                                    pageIndex: pageIndex,
                                    text: ocrText,
                                    usedOCR: true,
                                    usedSpatial: false,
                                    ocrCharCount: ocrText.count,
                                    noTextLayer: false
                                )
                            }

                            // Vision OCR failed — fall through to PDFKit text if available
                            if hasText, let fallback = pageText {
                                Log.warning("   ⚠️ Page \(pageNumber): Vision OCR failed on table page, using PDFKit fallback", category: .ingestion)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "table-fallback-pdfkit",
                                    chars: fallback.count,
                                    duration: Date().timeIntervalSince(pageStartTime)
                                )
                                return PageExtractionResult(
                                    pageIndex: pageIndex,
                                    text: fallback,
                                    usedOCR: false,
                                    usedSpatial: false,
                                    ocrCharCount: 0,
                                    noTextLayer: false
                                )
                            }
                        }

                        if hasText && textQualityOK {
                            // Good text layer - use it (spatial extraction already applied above)
                            let isSpatial = pageText != pageData.pageString  // Changed means spatial was used
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount)")
                            }
                            let pageTime = Date().timeIntervalSince(pageStartTime)
                            let method = isSpatial ? "spatial" : "text"
                            Log.debug("   ✓ Page \(pageNumber): \(pageText?.count ?? 0) chars (\(method), \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: isSpatial ? "spatial-ordering" : "native-text",
                                chars: pageText?.count ?? 0,
                                duration: pageTime
                            )

                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: pageText ?? "",
                                usedOCR: false,
                                usedSpatial: isSpatial,
                                ocrCharCount: 0,
                                noTextLayer: false
                            )
                        } else if hasText && !textQualityOK {
                            // Poor quality text - try enhanced OCR
                            Log.debug("   ⚠️ Page \(pageNumber): Text layer quality poor, trying enhanced OCR...", category: .ingestion)
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount), OCR (quality)")
                            }

                            if let pageImage = pageData.pageImage {
                                if let (ocrText, _) = try? await self.performEnhancedSpatialOCR(on: pageImage, pageNumber: pageNumber),
                                   !ocrText.isEmpty {
                                    // Check OCR quality on MainActor
                                    let ocrQualityOK = await MainActor.run { self.isTextQualityAcceptable(ocrText) }
                                    if ocrQualityOK {
                                        let pageTime = Date().timeIntervalSince(pageStartTime)
                                        Log.debug("   ✓ Page \(pageNumber): Enhanced OCR replaced garbage text (\(ocrText.count) chars, \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                                        self.traceIngestionOutcome(
                                            pageNumber: pageNumber,
                                            path: "quality-repair-ocr",
                                            chars: ocrText.count,
                                            duration: pageTime
                                        )

                                        return PageExtractionResult(
                                            pageIndex: pageIndex,
                                            text: ocrText,
                                            usedOCR: true,
                                            usedSpatial: false,
                                            ocrCharCount: ocrText.count,
                                            noTextLayer: false
                                        )
                                    }
                                }
                            }

                            // Fallback to original text
                            Log.warning("   ⚠️ Page \(pageNumber): Using original text despite quality concerns", category: .ingestion)
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "quality-fallback-native",
                                chars: pageText?.count ?? 0,
                                duration: Date().timeIntervalSince(pageStartTime)
                            )
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: pageText ?? "",
                                usedOCR: false,
                                usedSpatial: false,
                                ocrCharCount: 0,
                                noTextLayer: false
                            )
                        } else {
                            // No text layer - OCR required
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount), OCR")
                            }

                            if let pageImage = pageData.pageImage {
                                if let (ocrText, _) = try? await self.performEnhancedSpatialOCR(on: pageImage, pageNumber: pageNumber),
                                   !ocrText.isEmpty {
                                    let pageTime = Date().timeIntervalSince(pageStartTime)
                                    Log.debug("   ✓ Page \(pageNumber): Enhanced OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                                    self.traceIngestionOutcome(
                                        pageNumber: pageNumber,
                                        path: "no-text-ocr",
                                        chars: ocrText.count,
                                        duration: pageTime
                                    )

                                    return PageExtractionResult(
                                        pageIndex: pageIndex,
                                        text: ocrText,
                                        usedOCR: true,
                                        usedSpatial: false,
                                        ocrCharCount: ocrText.count,
                                        noTextLayer: true
                                    )
                                }
                            }

                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "no-text-ocr-empty",
                                chars: 0,
                                duration: Date().timeIntervalSince(pageStartTime)
                            )
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: "",
                                usedOCR: false,
                                usedSpatial: false,
                                ocrCharCount: 0,
                                noTextLayer: true
                            )
                        }
                    }
                }

                var collected: [PageExtractionResult] = []
                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    collected.append(result)
                }
                return collected
            }

            try Task.checkCancellation()

            results.append(contentsOf: batchResults)
            // MEMORY-SAFE: batchPageData goes out of scope here, releasing CIImages
            // Only maxRenderConcurrency (3) page images were alive at once
            // At 360 DPI: 3 × 206 MB = ~618 MB peak vs previous 10 × 206 MB = 2+ GB
            } // end inner sub-batch (render-safe)
        } // end outer batch (progress reporting)

        // Sort results by page index and compute statistics
        results.sort { $0.pageIndex < $1.pageIndex }

        let rawPageTexts = results.map { $0.text }
        let pageTexts = removeGarbageLinesFromExtractedPages(rawPageTexts, source: "pdf-legacy")
        _ = results.filter { $0.noTextLayer }.count  // pagesWithoutText - tracked but not logged
        let ocrUsedCount = results.filter { $0.usedOCR }.count
        let totalOCRChars = results.reduce(0) { $0 + $1.ocrCharCount }
        let spatialExtractionCount = results.filter { $0.usedSpatial }.count

        // PASS 2: Remove repeated headers and footers
        progressHandler?("cleaning headers/footers")
        let cleanedPageTexts = removeRepeatedHeadersFooters(from: pageTexts)

        // PASS 3: Assemble final text with page mappings AND page break sentinels
        // The sentinel survives normalization and lets us split per-page later for FTS5 storage.
        var fullText = ""
        var pageTextRanges: PageTextMapping = [:]

        for (index, cleanedText) in cleanedPageTexts.enumerated() {
            let pageNumber = index + 1
            let pageStartIndex = fullText.endIndex

            if !cleanedText.isEmpty {
                // Insert page break sentinel between pages (not before first page)
                if !fullText.isEmpty {
                    fullText += "\n\n\(Self.pageBreakSentinel)\n\n"
                }
                fullText += cleanedText
                let pageEndIndex = fullText.endIndex
                pageTextRanges[pageNumber] = pageStartIndex..<pageEndIndex
            }
        }

        // Report extraction methods used
        if ocrUsedCount > 0 {
            Log.debug(
                "[DocumentProcessor] OCR applied to \(ocrUsedCount)/\(pageCount) pages (\(totalOCRChars) chars total)",
                category: .ingestion
            )
        }
        if spatialExtractionCount > 0 {
            Log.info(
                "[DocumentProcessor] Spatial extraction (multi-column aware) used on \(spatialExtractionCount)/\(pageCount) pages",
                category: .ingestion
            )
        }

        // Log page mapping stats for debugging
        Log.debug("[DocumentProcessor] Built page→text mapping for \(pageTextRanges.count) pages", category: .ingestion)

        let pageInfo = PageInfo(
            totalPages: pageCount,
            ocrPagesUsed: ocrUsedCount,
            pageNumbers: Array(1...pageCount),
            pageTextRanges: pageTextRanges
        )

        return (fullText, pageInfo)
    }

    // MARK: - Structured Document Parsing (iOS 26+)

    /// Extract PDF content with structure awareness (tables, lists, paragraphs as separate elements)
    /// On iOS 26+, uses Vision's RecognizeDocumentsRequest for structure-aware parsing.
    /// This preserves tabular data integrity - specs in one table won't mix with unrelated data.
    private func extractStructuredPDFContent(url: URL, pageRange: ClosedRange<Int>? = nil) async throws -> StructuredExtractionResult {
        let pdfDocument = try loadPDF(url: url, context: "Structured PDF")

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw DocumentProcessingError.emptyDocument
        }

        // Check if structured parsing is available (iOS 26+)
        if #available(iOS 26.0, *) {
            return try await extractWithStructuredParsing(pdfDocument: pdfDocument, pageCount: pageCount, url: url, pageRange: pageRange)
        } else {
            // Fallback to regular extraction on older iOS versions
            Log.debug("[DocumentProcessor] iOS < 26: Using flat text extraction (no structure awareness)", category: .ingestion)
            let (text, pageInfo) = try await extractTextFromPDFWithPages(url: url)
            return StructuredExtractionResult(
                text: text,
                pageInfo: pageInfo,
                structuredElements: [],
                usedStructuredParsing: false
            )
        }
    }

    /// Check if PDF has high-quality native text layer (digital PDF vs scanned)
    /// Digital PDFs with good text layers should use PDFKit extraction for paragraphs
    /// (better column ordering) while still using Vision for table/list detection
    private func pdfHasGoodNativeText(_ pdfDocument: PDFDocument, samplePages: Int = 5) -> Bool {
        let pageCount = pdfDocument.pageCount
        let samplesToCheck = min(samplePages, pageCount)
        var pagesWithGoodText = 0

        for i in 0..<samplesToCheck {
            // Sample pages spread across the document
            let pageIndex = i * pageCount / samplesToCheck
            guard let page = pdfDocument.page(at: pageIndex),
                  let text = page.string else { continue }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Good text: at least 100 chars, mostly printable ASCII, not garbled
            if trimmed.count > 100 && isTextQualityAcceptable(trimmed) {
                pagesWithGoodText += 1
            }
        }

        // If >60% of sampled pages have good text, it's a digital PDF
        return Double(pagesWithGoodText) / Double(samplesToCheck) > 0.6
    }

    /// iOS 26+ structured parsing using Vision's RecognizeDocumentsRequest
    /// HYBRID MODE: For digital PDFs with good native text:
    /// - Uses PDFKit for paragraph text (correct column ordering)
    /// - Uses Vision for table/list structure detection only
    @available(iOS 26.0, *)
    private func extractWithStructuredParsing(pdfDocument: PDFDocument, pageCount: Int, url: URL, pageRange: ClosedRange<Int>? = nil) async throws -> StructuredExtractionResult {
        let startPageIdx = pageRange?.lowerBound ?? 0
        let endPageIdx = min(pageRange?.upperBound ?? (pageCount - 1), pageCount - 1)
        let parser = StructuredDocumentParser.shared
        let layoutExtractor = LayoutAwareExtractor.shared
        let fingerprint = computeDocumentFingerprint(at: url)
        let checkpointDir = checkpointDirectoryURL(for: fingerprint)
        Log.info("[Checkpoint] Processing document with fingerprint: \(fingerprint)", category: .ingestion)

        // Pass dynamic vocabulary to the structured document parser
        // so RecognizeDocumentsRequest knows the document's domain terms
        await parser.setDocumentCustomWords(currentDocumentCustomWords)

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE -1: DOCUMENT-LEVEL TEXT LAYER VALIDATION
        // ═══════════════════════════════════════════════════════════════════════
        // Font substitution cipher PDFs (Kia, Hyundai, Asian-publisher manuals)
        // have text layers that pass ALL quality checks (printable ASCII, normal
        // word lengths, NLLanguageRecognizer detects "Dutch") but are completely
        // garbled. OCR a sample page and compare via Jaccard similarity.
        // If < 0.15, text layer is unusable → force ALL pages through Vision OCR.
        // Runs ONCE per document (~200-500ms).
        // ═══════════════════════════════════════════════════════════════════════
        let documentTextLayerGarbled: Bool
        textLayerValidation: do {
            let sliceCount = (endPageIdx - startPageIdx) + 1
            let sampleIndices = sliceCount <= 3
                ? Array(startPageIdx...endPageIdx)
                : [startPageIdx, startPageIdx + sliceCount / 3, startPageIdx + 2 * sliceCount / 3]

            var bestSampleText = ""
            var bestSamplePage: PDFPage?

            for idx in sampleIndices {
                guard let page = pdfDocument.page(at: idx) else { continue }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count > bestSampleText.count {
                    bestSampleText = text
                    bestSamplePage = page
                }
            }

            // No text layer at all → not garbled, just needs OCR
            guard bestSampleText.count >= 50, let samplePage = bestSamplePage else {
                documentTextLayerGarbled = false
                Log.debug("[DocumentProcessor] [iOS26] Text layer validation: no/minimal text layer, skipping", category: .ingestion)
                break textLayerValidation
            }

            emitProgress(stage: "validating", detail: "🔍 Validating text layer...", page: nil, totalPages: pageCount)
            guard let sampleImage = renderPDFPageAsImage(page: samplePage) else {
                documentTextLayerGarbled = false
                Log.warning("[DocumentProcessor] [iOS26] Text layer validation: failed to render sample page", category: .ingestion)
                break textLayerValidation
            }

            let ocrObservations: [VNRecognizedTextObservation]
            do {
                ocrObservations = try await performOCRWithObservationsAsync(on: sampleImage)
            } catch {
                documentTextLayerGarbled = false
                Log.warning("[DocumentProcessor] [iOS26] Text layer validation: OCR failed (\(error.localizedDescription)), assuming OK", category: .ingestion)
                break textLayerValidation
            }

            let ocrWords: Set<String> = Set(
                ocrObservations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }
                    .map { String($0) }
                    .filter { $0.count >= 3 }
            )

            let pdfKitWords: Set<String> = Set(
                bestSampleText.lowercased()
                    .split(whereSeparator: { !$0.isLetter })
                    .map { String($0) }
                    .filter { $0.count >= 3 }
            )

            guard !ocrWords.isEmpty && !pdfKitWords.isEmpty else {
                documentTextLayerGarbled = false
                Log.debug("[DocumentProcessor] [iOS26] Text layer validation: insufficient words (OCR: \(ocrWords.count), PDFKit: \(pdfKitWords.count))", category: .ingestion)
                break textLayerValidation
            }

            let intersection = ocrWords.intersection(pdfKitWords).count
            let union = ocrWords.union(pdfKitWords).count
            let jaccard = Double(intersection) / Double(union)

            Log.info("[DocumentProcessor] [iOS26] Text layer Jaccard = \(String(format: "%.3f", jaccard)) (OCR: \(ocrWords.count) words, PDFKit: \(pdfKitWords.count) words, shared: \(intersection))", category: .ingestion)

            if jaccard < 0.15 {
                documentTextLayerGarbled = true
                Log.warning("[DocumentProcessor] ⚠️ [iOS26] GARBLED TEXT LAYER (Jaccard=\(String(format: "%.3f", jaccard))). Font substitution cipher. ALL pages → Vision OCR.", category: .ingestion)
                let ocrSample = Array(ocrWords.prefix(5)).joined(separator: ", ")
                let pdfSample = Array(pdfKitWords.prefix(5)).joined(separator: ", ")
                Log.info("[DocumentProcessor] [iOS26] OCR sample: [\(ocrSample)] vs PDFKit sample: [\(pdfSample)]", category: .ingestion)
            } else {
                // Main Jaccard passed. For marginal scores (0.15–0.45), run a secondary
                // check for AutoCAD SHX / CAD font encoding (Gap 3 fix).
                // SHX fonts score Jaccard 0.20–0.40 because ASCII digits survive, but
                // dimension symbols and special chars are remapped to garbage.
                // Numeric tokens (part numbers, dimensions) don't survive SHX — they're
                // the most reliable signal for this encoding class.
                var shxGarbled = false
                if jaccard < 0.45 {
                    let numericPattern = #"\b\d+\.?\d*\s*[A-Za-z]{0,4}\b"#
                    if let numericRegex = try? NSRegularExpression(pattern: numericPattern) {
                        let extractNumerics = { (text: String) -> Set<String> in
                            let range = NSRange(text.startIndex..., in: text)
                            return Set(
                                numericRegex.matches(in: text, range: range)
                                    .compactMap { Range($0.range, in: text).map { String(text[$0]).lowercased().trimmingCharacters(in: .whitespaces) } }
                                    .filter { $0.count >= 2 }
                            )
                        }
                        let ocrText = ocrObservations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                        let ocrNumerics = extractNumerics(ocrText)
                        let pdfNumerics = extractNumerics(bestSampleText)
                        if pdfNumerics.count >= 5 {
                            let numIntersection = ocrNumerics.intersection(pdfNumerics).count
                            let numUnion = ocrNumerics.union(pdfNumerics).count
                            let numericJaccard = numUnion > 0 ? Double(numIntersection) / Double(numUnion) : 1.0
                            Log.info("[DocumentProcessor] [iOS26] SHX secondary check: \(pdfNumerics.count) PDF numerics, \(ocrNumerics.count) OCR numerics, numeric Jaccard=\(String(format: "%.3f", numericJaccard))", category: .ingestion)
                            if numericJaccard < 0.25 {
                                shxGarbled = true
                                Log.warning("[DocumentProcessor] ⚠️ [iOS26] SHX FONT ENCODING DETECTED (numeric Jaccard=\(String(format: "%.3f", numericJaccard)), text Jaccard=\(String(format: "%.3f", jaccard))). Likely AutoCAD/CAD/SHX PDF. ALL pages → Vision OCR.", category: .ingestion)
                            }
                        }
                    }
                }
                documentTextLayerGarbled = shxGarbled
                if !shxGarbled {
                    Log.debug("[DocumentProcessor] [iOS26] ✓ Text layer validated (Jaccard=\(String(format: "%.3f", jaccard)))", category: .ingestion)
                }
            }
        }

        // Check if this is a digital PDF with good native text
        // PHASE -1 override: if text layer is garbled, NEVER use hybrid mode
        let useHybridMode = !documentTextLayerGarbled && pdfHasGoodNativeText(pdfDocument)
        if useHybridMode {
            Log.info("[DocumentProcessor] � LAYOUT-AWARE HYBRID MODE enabled (digital PDF with good text)", category: .ingestion)
            Log.info("[DocumentProcessor] 📐 Multi-column layouts will be detected and read in proper order", category: .ingestion)
        } else {
            Log.info("[DocumentProcessor] 📷 OCR MODE (scanned PDF or low-quality text layer)", category: .ingestion)
        }

        Log.info("[DocumentProcessor] Starting structured parsing for \(pageCount) pages (iOS 26+)", category: .ingestion)

        // Reset live metrics for this document with Vision enabled
        resetLiveMetrics(usingVision: true, totalPages: pageCount)

        // MEMORY OPTIMIZATION: Render pages in batches, not all at once
        // Each 1260×1785 RGBA image ≈ 9MB; 542 pages = 4.8GB if pre-rendered!
        // Now we render only maxConcurrentPages at a time (~27MB peak)

        struct PageRenderData: Sendable {
            let pageIndex: Int
            let pageImage: CIImage?
            let plainText: String?
            let layoutText: String?  // Layout-aware extracted text
            let layoutTables: [TableRegion]
            let preferHighResolutionStructure: Bool
        }

        // Result container for parallel processing
        struct PageParseResult: Sendable {
            let pageIndex: Int
            let elements: [StructuredElementWrapper]
            let pageText: String
            let hasStructure: Bool
            let usedOCR: Bool
            // Metrics from this page
            let tablesFound: Int
            let listsFound: Int
            let headersFound: Int
        }

        // Parallel structured parsing with device-specific concurrency
        // Vision's RecognizeDocumentsRequest runs on Neural Engine (ANE)
        // Higher-tier devices (A18+) can sustain more concurrent ANE operations
        // MAXIMUM QUALITY MODE: Both layout extraction AND structured parsing run
        // Use visionParsingConcurrency since RecognizeDocumentsRequest is the bottleneck
        let maxConcurrentPages = DeviceCapabilityService.shared.visionParsingConcurrency
        let modeLabel = useHybridMode ? "hybrid (layout + structure)" : "structured"
        Log.info("[DocumentProcessor] 🚀 \(modeLabel.capitalized) extraction with \(maxConcurrentPages) concurrent pages (tier: \(DeviceCapabilityService.shared.tier.rawValue))", category: .ingestion)

        var results: [PageParseResult] = []

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 0: ADAPTIVE COMPLEXITY PRE-SCAN
        // Only render images and run Vision for pages that NEED it
        // Simple single-column pages skip Vision entirely → massive speedup
        // ═══════════════════════════════════════════════════════════════════════
        let complexityStartTime = Date()
        let pagesToAnalyze: [(PDFPage, Int)] = (startPageIdx...endPageIdx).compactMap { index in
            guard let page = pdfDocument.page(at: index) else { return nil }
            return (page, index + 1)
        }
        let complexityAnalyses = await PageComplexityAnalyzer.shared.analyzeBatch(pages: pagesToAnalyze)
        PageComplexityAnalyzer.shared.logBatchSummary(complexityAnalyses)
        let complexityTime = Date().timeIntervalSince(complexityStartTime) * 1000
        Log.info("[DocumentProcessor] Complexity pre-scan: \(String(format: "%.0f", complexityTime))ms for \(pageCount) pages", category: .ingestion)

        // Build lookup for quick access
        var pageComplexity: [Int: PageComplexityAnalysis] = [:]
        for analysis in complexityAnalyses {
            pageComplexity[analysis.pageNumber] = analysis
        }

        // Count pages that can skip Vision after fidelity overrides are applied.
        let skipVisionCount = complexityAnalyses.filter { analysis in
            let strategy = analysis.processingStrategy
            let baseSkip = strategy == .directText || strategy == .spatialText
            return baseSkip && !shouldForceVisionForAdaptiveRecovery(
                analysis: analysis,
                strategy: strategy,
                documentTextLayerGarbled: documentTextLayerGarbled
            )
        }.count
        let visionRequired = pageCount - skipVisionCount
        Log.info("[DocumentProcessor] 🚀 ADAPTIVE: \(skipVisionCount) pages skip Vision OCR, \(visionRequired) need layout detection", category: .ingestion)

        // MEMORY-SAFE RENDERING: Limit concurrent full-res page images.
        // At 360 DPI, each page = 6210×11040px ≈ 206 MB (opaque RGB).
        // Previous code rendered maxConcurrentPages (10) images = 2+ GB → OOM crash.
        // Now sub-batch: render pdfRenderingConcurrency (3) → analyze → OCR → release → next.
        // Quality is UNCHANGED: same 360 DPI, same preprocessing, same Vision accuracy.
        let maxRenderConcurrency = DeviceCapabilityService.shared.pdfRenderingConcurrency
        Log.info("[DocumentProcessor] Memory-safe Vision rendering: max \(maxRenderConcurrency) page images alive at once (~\(maxRenderConcurrency * 206) MB)", category: .ingestion)

        for batchStart in stride(from: startPageIdx, to: endPageIdx + 1, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, endPageIdx + 1)

            // Emit rich progress with current metrics
            await MainActor.run {
                self.emitProgress(
                    stage: "vision",
                    detail: useHybridMode
                        ? "🔬 Max quality parsing pages \(batchStart + 1)-\(batchEnd)/\(pageCount)"
                        : "👁 Vision parsing pages \(batchStart + 1)-\(batchEnd)/\(pageCount)",
                    page: batchEnd,
                    totalPages: pageCount
                )
            }

            // Sub-batch rendering: render only maxRenderConcurrency pages at a time
            // Each sub-batch goes through render → layout → structured parsing → release
            for renderStart in stride(from: batchStart, to: batchEnd, by: maxRenderConcurrency) {
                let renderEnd = min(renderStart + maxRenderConcurrency, batchEnd)
                let subBatchIndices = renderStart..<renderEnd

            // MEMORY-SAFE: Render only this sub-batch's pages
            // GPU ACCELERATION: Apply preprocessing filters for better OCR accuracy
            // ADAPTIVE: Only render images for pages that need Vision layout detection

            // Emit GPU rendering progress
            let gpuActive = DeviceCapabilityService.shared.useGPUForPDFRendering
            let gpuLabel = gpuActive ? "[Metal GPU]" : "[CPU]"
            await MainActor.run {
                self.emitProgress(
                    stage: "render",
                    detail: "🎨 \(gpuLabel) Rendering pages \(renderStart + 1)-\(renderEnd)/\(pageCount)",
                    page: renderStart,
                    totalPages: pageCount
                )
            }

            var batchRenderData: [PageRenderData] = []
            for pageIndex in subBatchIndices {
                // 1. Check if checkpoint exists on disk
                let checkpointURL = checkpointDir.appendingPathComponent("page_\(pageIndex).json")
                if FileManager.default.fileExists(atPath: checkpointURL.path),
                   let data = try? Data(contentsOf: checkpointURL),
                   let checkpoint = try? JSONDecoder().decode(IngestionCheckpointPage.self, from: data) {
                    
                    Log.info("[Checkpoint] Loaded page \(pageIndex + 1) from checkpoint", category: .ingestion)
                    let parsedElements = checkpoint.elements.map { $0.toWrapper() }
                    let pageResult = PageParseResult(
                        pageIndex: checkpoint.pageIndex,
                        elements: parsedElements,
                        pageText: checkpoint.pageText,
                        hasStructure: checkpoint.hasStructure,
                        usedOCR: checkpoint.usedOCR,
                        tablesFound: checkpoint.tablesFound,
                        listsFound: checkpoint.listsFound,
                        headersFound: checkpoint.headersFound
                    )
                    results.append(pageResult)
                    
                    // Increment live metrics from checkpoint
                    let wordCount = checkpoint.pageText.split(separator: " ").count
                    incrementMetric(
                        tables: checkpoint.tablesFound,
                        lists: checkpoint.listsFound,
                        headers: checkpoint.headersFound,
                        ocrPages: checkpoint.usedOCR ? 1 : 0,
                        words: wordCount
                    )
                    
                    // Add dummy render data to preserve index alignment
                    batchRenderData.append(PageRenderData(
                        pageIndex: pageIndex,
                        pageImage: nil,
                        plainText: nil,
                        layoutText: "[CHECKPOINT_SKIPPED]",
                        layoutTables: [],
                        preferHighResolutionStructure: false
                    ))
                    continue
                }

                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        batchRenderData.append(PageRenderData(pageIndex: pageIndex, pageImage: nil, plainText: nil, layoutText: nil, layoutTables: [], preferHighResolutionStructure: false))
                        return
                    }

                    let pageNumber = pageIndex + 1
                    let complexity = pageComplexity[pageNumber]
                    let strategy = complexity?.processingStrategy ?? .enhancedOCR  // Safe default
                    let renderScale = preferredOCRRenderScale(for: complexity, documentTextLayerGarbled: documentTextLayerGarbled)
                    let fidelityForcesVision = shouldForceVisionForAdaptiveRecovery(
                        analysis: complexity,
                        strategy: strategy,
                        documentTextLayerGarbled: documentTextLayerGarbled
                    )
                    // PHASE -1 override: garbled text layer → ALL pages need Vision OCR
                    let needsVision = documentTextLayerGarbled || fidelityForcesVision || strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR
                    let plainText = page.string
                    let hasText = (plainText?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 0
                    let requiresTableOCR = (complexity?.tablePresence ?? 0) > 0.2 || (complexity?.numericDensity ?? 0) > 0.3
                    let preferHighResolutionStructure = shouldPreferHighResolutionStructure(
                        for: complexity,
                        strategy: strategy,
                        documentTextLayerGarbled: documentTextLayerGarbled
                    )

                    traceIngestionDecision(
                        pageNumber: pageNumber,
                        strategy: documentTextLayerGarbled
                            ? "garbled-force-ocr"
                            : (fidelityForcesVision && strategy == .spatialText ? "\(strategy.description)+fidelity" : strategy.description),
                        hasText: hasText,
                        textQualityOK: !documentTextLayerGarbled && (complexity?.textQuality ?? 0) > 0.65,
                        requiresTableOCR: requiresTableOCR,
                        mode: documentTextLayerGarbled
                            ? "structured-garbled-ocr"
                            : (fidelityForcesVision ? "structured-hybrid-fidelity" : "structured-hybrid")
                    )

                    // ADAPTIVE: Only render image if this page needs Vision layout detection
                    // Simple pages with good text skip image rendering entirely!
                    // PHASE -1 override: garbled text → ALWAYS render image for OCR
                    var pageImage: CIImage? = nil
                    if needsVision {
                        if renderScale > 5.0 {
                            Log.info("[DocumentProcessor] Page \(pageNumber): fine text risk \(Int((complexity?.fineTextRisk ?? 0) * 100))% → rendering at \(Int(72 * renderScale)) DPI", category: .ingestion)
                        }
                        pageImage = renderPDFPageAsImage(page: page, scale: renderScale)
                        if let image = pageImage {
                            let textQuality = documentTextLayerGarbled ? 0.0 : (complexity?.textQuality ?? 0.7)
                            let isScanned = documentTextLayerGarbled || strategy == .fullOCR
                            let plainText = page.string
                            // Garbled text layer → tell preprocessor there's NO usable native text
                            let hasText = !documentTextLayerGarbled && (plainText?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 10
                            pageImage = preprocessImageForOCR(
                                image,
                                textQuality: textQuality,
                                hasNativeTextLayer: hasText,
                                isScanned: isScanned
                            )
                        }
                    }

                    // For simple pages, try spatial extraction right away
                    // PHASE -1 override: NEVER use PDFKit text when text layer is garbled
                    var layoutText: String? = nil
                    if !documentTextLayerGarbled && !needsVision, let text = plainText, !text.isEmpty {
                        // Use PDFKit spatial extraction (no Vision needed)
                        // Which of the two outcomes happened is recorded, because `?? text` hides
                        // it and that is why a two-column extraction defect had to be diagnosed by
                        // inference rather than read off a trace. `text` here is raw `page.string`,
                        // which interleaves columns by construction, so the fallback is a materially
                        // worse result and not an equivalent one.
                        let spatial = extractTextWithSpatialOrdering(from: page)
                        layoutText = spatial ?? text
                        Log.debug(
                            "[DocumentProcessor] Page \(pageNumber): strategy=\(strategy.description), "
                                + "Vision skipped, spatial extraction "
                                + (spatial == nil ? "FAILED -> raw page text (column order not preserved)" : "ok"),
                            category: .ingestion
                        )
                    }

                    batchRenderData.append(PageRenderData(
                        pageIndex: pageIndex,
                        pageImage: pageImage,
                        plainText: plainText,
                        layoutText: layoutText,
                        layoutTables: [],
                        preferHighResolutionStructure: preferHighResolutionStructure
                    ))
                }
            }

            // LAYOUT-AWARE EXTRACTION: Only for pages that need Vision
            // Simple pages already have layoutText from PDFKit above
            // This properly handles multi-column layouts by detecting columns spatially
            let pagesNeedingVision = batchRenderData.filter { $0.pageImage != nil && $0.layoutText == nil }
            if useHybridMode && !pagesNeedingVision.isEmpty {
                // Emit layout extraction progress - Vision uses Neural Engine (ANE)
                await MainActor.run {
                    self.emitProgress(
                        stage: "layout",
                        detail: "📐 [ANE] Detecting columns for \(pagesNeedingVision.count) complex pages",
                        page: batchStart,
                        totalPages: pageCount
                    )
                }

                var layoutResults: [Int: LayoutAnalysisResult] = [:]
                await withTaskGroup(of: (Int, LayoutAnalysisResult?).self) { group in
                    for (batchOffset, pageIndex) in subBatchIndices.enumerated() {
                        let renderData = batchRenderData[batchOffset]
                        // ADAPTIVE: Skip pages that already have layoutText (PDFKit extraction)
                        // Only run Vision on pages with images that need layout detection
                        guard let pageImage = renderData.pageImage, renderData.layoutText == nil else { continue }

                        group.addTask {
                            let pageNumber = pageIndex + 1
                            do {
                                let layoutResult = try await layoutExtractor.extractWithLayout(
                                    from: pageImage,
                                    pageNumber: pageNumber
                                )
                                return (batchOffset, layoutResult)
                            } catch {
                                Log.warning("[DocumentProcessor] Layout extraction failed for page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
                                return (batchOffset, nil)
                            }
                        }
                    }

                    for await (offset, result) in group {
                        if let result {
                            layoutResults[offset] = result
                        }
                    }
                }

                // Emit layout complete progress
                await MainActor.run {
                    self.emitProgress(
                        stage: "layout",
                        detail: "✅ Layout detected, parsing structure \(batchStart + 1)-\(batchEnd)",
                        page: batchEnd,
                        totalPages: pageCount
                    )
                }

                // Update batch render data with layout results
                for i in batchRenderData.indices {
                    if let layoutResult = layoutResults[i] {
                        let old = batchRenderData[i]
                        let preferredLayoutText: String = {
                            if !layoutResult.tables.isEmpty || layoutResult.isMultiColumn {
                                return layoutResult.readingOrderText
                            }
                            if let plainText = old.plainText, !plainText.isEmpty {
                                return plainText
                            }
                            return layoutResult.readingOrderText
                        }()
                        batchRenderData[i] = PageRenderData(
                            pageIndex: old.pageIndex,
                            pageImage: old.pageImage,
                            plainText: old.plainText,
                            layoutText: preferredLayoutText,
                            layoutTables: layoutResult.tables,
                            preferHighResolutionStructure: old.preferHighResolutionStructure
                        )
                    }
                }
            }

            // Emit structured extraction progress - Vision uses Neural Engine
            await MainActor.run {
                self.emitProgress(
                    stage: "structure",
                    detail: "🔍 [ANE] Tables/lists \(batchStart + 1)-\(batchEnd)/\(pageCount)",
                    page: batchStart,
                    totalPages: pageCount
                )
            }

            let batchResults = await withTaskGroup(of: PageParseResult.self) { group in
                for (batchOffset, pageIndex) in subBatchIndices.enumerated() {
                    let renderData = batchRenderData[batchOffset]
                    if renderData.layoutText == "[CHECKPOINT_SKIPPED]" {
                        continue
                    }
                    let isHybridMode = useHybridMode  // Capture for sendable closure
                    let isGarbled = documentTextLayerGarbled  // Capture for sendable closure
                    // Gap 1 fix: capture customWords by value here (not via actor state on shared
                    // parser). If two documents ingest concurrently, setDocumentCustomWords() on
                    // the shared singleton clobbers vocabulary mid-parse for the first document.
                    // Capturing here binds this task to doc1's vocabulary regardless of doc2.
                    let capturedCustomWords = currentDocumentCustomWords
                    let capturedComplexity = pageComplexity[pageIndex + 1]

                    group.addTask {
                        if Task.isCancelled {
                            return PageParseResult(
                                pageIndex: pageIndex,
                                elements: [],
                                pageText: "",
                                hasStructure: false,
                                usedOCR: false,
                                tablesFound: 0,
                                listsFound: 0,
                                headersFound: 0
                            )
                        }

                        let pageNumber = pageIndex + 1
                        let bestAvailableText = (renderData.layoutText ?? renderData.plainText)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        // No page data available
                        guard let pageImage = renderData.pageImage else {
                            // PHASE -1: when text layer is garbled, don't use PDFKit fallback
                            if !isGarbled, let nativeText = bestAvailableText, !nativeText.isEmpty {
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: renderData.layoutText != nil ? "structured-skip-vision-layout" : "structured-skip-vision-native",
                                    chars: nativeText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: [StructuredElementWrapper(
                                        text: nativeText,
                                        elementType: "paragraph",
                                        pageNumber: pageNumber,
                                        isAtomicChunk: false
                                    )],
                                    pageText: nativeText,
                                    hasStructure: false,
                                    usedOCR: false,
                                    tablesFound: 0,
                                    listsFound: 0,
                                    headersFound: 0
                                )
                            }
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "structured-empty-no-image",
                                chars: 0
                            )
                            return PageParseResult(pageIndex: pageIndex, elements: [], pageText: "", hasStructure: false, usedOCR: false, tablesFound: 0, listsFound: 0, headersFound: 0)
                        }

                        do {
                            // MAXIMUM QUALITY: Run full Vision structured parsing for tables/lists/headers
                            // customWords: passed explicitly per-task (not actor state) to prevent
                            //   concurrent-document vocab clobbering (Gap 1 fix).
                            // nativeWordCount: PDFKit word count as quality score ground truth
                            //   (Gap 2 fix). nil when garbled (PDFKit text untrustworthy).
                            let nativeCount = !isGarbled ? renderData.plainText?.split(separator: " ").count : nil
                            let structuredContent = try await parser.parsePageImage(
                                pageImage,
                                pageNumber: pageNumber,
                                customWords: capturedCustomWords,
                                nativeWordCount: nativeCount,
                                preferFullResolution: renderData.preferHighResolutionStructure
                            )

                            var elements: [StructuredElementWrapper] = []
                            var pageTablesCount = 0
                            var pageListsCount = 0
                            var pageHeadersCount = 0

                            // Log figure references if any were found
                            if !structuredContent.figureReferences.isEmpty {
                                Log.debug("[DocumentProcessor] Page \(pageNumber) has \(structuredContent.figureReferences.count) figure references: \(structuredContent.figureReferences.prefix(3).joined(separator: ", "))", category: .ingestion)
                            }

                            // Use effectiveContent which automatically falls back to raw text if quality is low
                            let elementsToUse = structuredContent.effectiveContent

                            let isMixedMode = capturedComplexity?.isMixedModeScanned ?? false
                            let pageUsesHybridOverride = isHybridMode && !isMixedMode

                            // HYBRID MODE: Use layout-aware text for paragraphs (correct column order)
                            // Keep Vision's tables, lists, titles (structural elements)
                            let layoutText = renderData.layoutText
                            let trustedPageTextForTitles = (isMixedMode ? structuredContent.rawText : (bestAvailableText ?? layoutText ?? structuredContent.rawText))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let pageHasStructuredTables = elementsToUse.contains { structuredElement in
                                structuredElement.elementType == "table"
                            } || !renderData.layoutTables.isEmpty
                            var usedLayoutForParagraph = false

                            // Convert structured elements to wrappers and count types
                            for element in elementsToUse {
                                let isAtomic = element.elementType == "table" || element.elementType == "list"

                                var entities: [(type: String, value: String)] = []
                                var tableData: TableData?
                                var listItems: [String]?
                                if case .table(let parsedTable) = element {
                                    tableData = parsedTable
                                    entities = parsedTable.detectedEntities.map { ($0.type.rawValue, $0.value) }
                                } else if case .list(let items, _) = element {
                                    listItems = items
                                }
                                if case .table(let tableData) = element {
                                    entities = tableData.detectedEntities.map { ($0.type.rawValue, $0.value) }
                                }

                                // In hybrid mode: replace Vision paragraphs with layout-aware text
                                // This fixes multi-column reading order issues
                                if pageUsesHybridOverride && element.elementType == "paragraph" && !pageHasStructuredTables {
                                    if !usedLayoutForParagraph, let layout = layoutText, !layout.isEmpty {
                                        // Use layout-aware text instead of Vision's paragraph
                                        elements.append(StructuredElementWrapper(
                                            text: layout.trimmingCharacters(in: .whitespacesAndNewlines),
                                            elementType: "paragraph",
                                            pageNumber: pageNumber,
                                            isAtomicChunk: false,
                                            detectedEntities: [],
                                            tableData: nil,
                                            listItems: nil
                                        ))
                                        usedLayoutForParagraph = true
                                    }
                                    continue  // Skip Vision's paragraph
                                }

                                let sanitizedText: String?
                                switch element {
                                case .title(let text, _):
                                    sanitizedText = await MainActor.run {
                                        guard let cleaned = self.sanitizeStructuredLabel(text) else {
                                            return nil
                                        }
                                        guard self.titleMatchesTrustedPageText(cleaned, pageText: trustedPageTextForTitles) else {
                                            Log.debug("[DocumentProcessor] Dropping structured title that does not match trusted page text on page \(pageNumber)", category: .ingestion)
                                            return nil
                                        }
                                        return cleaned
                                    }
                                case .paragraph(let text, _):
                                    sanitizedText = await MainActor.run {
                                        self.sanitizeStructuredNarrativeText(
                                            text,
                                            pageHasTables: pageHasStructuredTables
                                        )
                                    }
                                default:
                                    sanitizedText = OCRConfiguration.normalizeExtractedText(element.textForEmbedding)
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                }

                                guard let sanitizedText, !sanitizedText.isEmpty else {
                                    continue
                                }

                                // Count element types for live metrics only after text survives quality filtering.
                                switch element.elementType {
                                case "table": pageTablesCount += 1
                                case "list": pageListsCount += 1
                                case "title": pageHeadersCount += 1
                                default: break
                                }

                                elements.append(StructuredElementWrapper(
                                    text: sanitizedText,
                                    elementType: element.elementType,
                                    pageNumber: element.pageNumber,
                                    isAtomicChunk: isAtomic,
                                    detectedEntities: entities,
                                    tableData: tableData,
                                    listItems: listItems,
                                    extractionSource: tableData == nil ? nil : "vision_document",
                                    qualityScore: tableData.map(self.tableQualityScore)
                                ))
                            }

                            // If hybrid mode but no paragraphs were in structured content, add layout text
                            if pageUsesHybridOverride && !pageHasStructuredTables && !usedLayoutForParagraph,
                               let layout = layoutText, !layout.isEmpty {
                                elements.append(StructuredElementWrapper(
                                    text: layout.trimmingCharacters(in: .whitespacesAndNewlines),
                                    elementType: "paragraph",
                                    pageNumber: pageNumber,
                                    isAtomicChunk: false,
                                    detectedEntities: [],
                                    tableData: nil,
                                    listItems: nil
                                ))
                            }

                            let preferredLayoutElements = self.preferredElementsWithLayoutTables(
                                existingElements: elements,
                                layoutTables: renderData.layoutTables,
                                pageNumber: pageNumber
                            )
                            if preferredLayoutElements.didPromote {
                                elements = preferredLayoutElements.elements
                                let metrics = self.structuredElementMetrics(in: elements)
                                pageTablesCount = metrics.tables
                                pageListsCount = metrics.lists
                                pageHeadersCount = max(pageHeadersCount, metrics.headers)

                                Log.info(
                                    "[DocumentProcessor] Page \(pageNumber): promoted \(pageTablesCount) layout-detected table(s) over weaker parser output",
                                    category: .ingestion
                                )
                            }

                            let recoveredPageText = (isMixedMode ? structuredContent.rawText : (bestAvailableText ?? structuredContent.rawText))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let recoveredParallelKeyValueElements = self.preferredElementsWithRecoveredParallelKeyValueTable(
                                existingElements: elements,
                                pageText: recoveredPageText,
                                pageNumber: pageNumber
                            )
                            if recoveredParallelKeyValueElements.didPromote {
                                elements = recoveredParallelKeyValueElements.elements
                                let metrics = self.structuredElementMetrics(in: elements)
                                pageTablesCount = metrics.tables
                                pageListsCount = metrics.lists
                                pageHeadersCount = max(pageHeadersCount, metrics.headers)

                                Log.info(
                                    "[DocumentProcessor] Page \(pageNumber): rebuilt parallel key/value table from page text to replace malformed row-column pairing",
                                    category: .ingestion
                                )
                            }

                            if pageTablesCount == 0 && pageListsCount == 0 {
                                let inferenceSourceText = (isMixedMode ? structuredContent.rawText : (layoutText ?? structuredContent.rawText))
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                let inferredElements = self.inferredStructuredElementsForPDFPageText(
                                    inferenceSourceText,
                                    pageNumber: pageNumber
                                )

                                if !inferredElements.isEmpty {
                                    let preservedNonParagraphElements = elements.filter { $0.elementType != "paragraph" }
                                    elements = preservedNonParagraphElements + inferredElements
                                    let metrics = self.structuredElementMetrics(in: elements)
                                    pageTablesCount = metrics.tables
                                    pageListsCount = metrics.lists
                                    pageHeadersCount = max(pageHeadersCount, metrics.headers)

                                    Log.info(
                                        "[DocumentProcessor] Page \(pageNumber): recovered \(pageTablesCount) table(s) from layout/OCR fallback text",
                                        category: .ingestion
                                    )
                                }
                            }

                            // Add figure references as searchable content
                            if !structuredContent.figureReferences.isEmpty {
                                let figureText = "[Visual Content on Page \(pageNumber)]\n" + structuredContent.figureReferences.joined(separator: "\n")
                                elements.append(StructuredElementWrapper(
                                    text: figureText,
                                    elementType: "figure",
                                    pageNumber: pageNumber,
                                    isAtomicChunk: true,
                                    detectedEntities: [],
                                    tableData: nil,
                                    listItems: nil
                                ))
                            }

                            let rescueSourceText = (isMixedMode ? structuredContent.rawText : (bestAvailableText ?? structuredContent.rawText))
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            if self.shouldAttemptRegionCropRescue(
                                analysis: capturedComplexity,
                                structuredContent: structuredContent,
                                hasRecoveredStructure: pageTablesCount > 0 || pageListsCount > 0 || !structuredContent.figureReferences.isEmpty,
                                layoutTables: renderData.layoutTables,
                                pageText: rescueSourceText
                            ), let rescueResult = await IntelligentDocumentProcessor.shared.rescuePageRegions(
                                from: pageImage,
                                pageNumber: pageNumber,
                                preferHighAccuracy: renderData.preferHighResolutionStructure
                            ), let rescuePayload = self.regionRescuePayload(from: rescueResult, pageNumber: pageNumber) {
                                let promotedRescue = self.preferredElementsWithRegionCropRescue(
                                    existingElements: elements,
                                    rescuePayload: rescuePayload,
                                    existingPageText: rescueSourceText,
                                    pageNumber: pageNumber
                                )

                                if promotedRescue.didPromote {
                                    elements = promotedRescue.elements
                                    let metrics = self.structuredElementMetrics(in: elements)
                                    pageTablesCount = metrics.tables
                                    pageListsCount = metrics.lists
                                    pageHeadersCount = max(pageHeadersCount, metrics.headers)

                                    Log.info(
                                        "[DocumentProcessor] Page \(pageNumber): crop rescue promoted \(rescuePayload.tableCount) table(s), \(rescuePayload.listCount) list(s), \(rescuePayload.figureCount) figure region(s)",
                                        category: .ingestion
                                    )
                                }
                            }

                            // Build structured pageText from elements with proper formatting
                            // Each element type gets appropriate visual separation
                            let pageTextOutput: String
                            if !elements.isEmpty {
                                var textParts: [String] = []
                                for elem in elements {
                                    let trimmed = elem.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { continue }
                                    switch elem.elementType {
                                    case "title":
                                        // Section headers get emphasis
                                        textParts.append("\n\(trimmed)")
                                    case "table":
                                        // Tables get clear boundaries
                                        textParts.append("\n\(trimmed)\n")
                                    case "list":
                                        // Lists get a blank line before
                                        textParts.append("\n\(trimmed)")
                                    case "figure":
                                        // Figures get brackets
                                        textParts.append("\n\(trimmed)\n")
                                    default:
                                        // Paragraphs: standard double-newline separation
                                        textParts.append(trimmed)
                                    }
                                }
                                pageTextOutput = textParts.joined(separator: "\n\n")
                            } else if pageUsesHybridOverride, let layout = layoutText, !layout.isEmpty {
                                pageTextOutput = layout
                            } else if let rescueResult = await IntelligentDocumentProcessor.shared.rescuePageRegions(
                                from: pageImage,
                                pageNumber: pageNumber,
                                preferHighAccuracy: true
                            ), let rescuePayload = self.regionRescuePayload(from: rescueResult, pageNumber: pageNumber), !rescuePayload.pageText.isEmpty {
                                pageTextOutput = rescuePayload.pageText
                            } else {
                                pageTextOutput = structuredContent.rawText
                            }

                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: isHybridMode ? "structured-hybrid" : "structured-vision",
                                chars: pageTextOutput.count,
                                extra: [
                                    ("tables", "\(pageTablesCount)"),
                                    ("lists", "\(pageListsCount)"),
                                    ("headers", "\(pageHeadersCount)")
                                ]
                            )

                            // A page used OCR when recognition is the only reason it has any text.
                            // The structured path renders and recognises a page image whether or not
                            // the PDF carries a text layer, so "Vision ran" is not the signal; "there
                            // was no usable native text" is. Hardcoding false here meant a scan that
                            // `RecognizeDocumentsRequest` read cleanly reported zero OCR pages, while
                            // one that fell through to the rescue path below reported one — backwards
                            // from what "OCR: N pages scanned" tells the user in Document Details.
                            let pageNeededOCR = isGarbled || (bestAvailableText?.isEmpty ?? true)

                            return PageParseResult(
                                pageIndex: pageIndex,
                                elements: elements,
                                pageText: pageTextOutput,
                                hasStructure: structuredContent.hasStructuredContent || pageTablesCount > 0 || pageListsCount > 0,
                                usedOCR: pageNeededOCR,
                                tablesFound: pageTablesCount,
                                listsFound: pageListsCount,
                                headersFound: pageHeadersCount
                            )

                        } catch StructuredParsingError.noDocumentDetected {
                            if let rescueResult = await IntelligentDocumentProcessor.shared.rescuePageRegions(
                                from: pageImage,
                                pageNumber: pageNumber,
                                preferHighAccuracy: renderData.preferHighResolutionStructure
                            ), let rescuePayload = self.regionRescuePayload(from: rescueResult, pageNumber: pageNumber) {
                                let metrics = self.structuredElementMetrics(in: rescuePayload.elements)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "structured-region-rescue",
                                    chars: rescuePayload.pageText.count,
                                    extra: [
                                        ("tables", "\(rescuePayload.tableCount)"),
                                        ("lists", "\(rescuePayload.listCount)"),
                                        ("figures", "\(rescuePayload.figureCount)")
                                    ]
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: rescuePayload.elements,
                                    pageText: rescuePayload.pageText,
                                    hasStructure: metrics.tables > 0 || metrics.lists > 0,
                                    usedOCR: true,
                                    tablesFound: metrics.tables,
                                    listsFound: metrics.lists,
                                    headersFound: metrics.headers
                                )
                            }

                            // No document content - try OCR fallback
                            if let ocrText = try? await self.performOCR(on: pageImage), !ocrText.isEmpty {
                                let inferredElements = self.inferredStructuredElementsForPDFPageText(ocrText, pageNumber: pageNumber)
                                let fallbackElements = inferredElements.isEmpty
                                    ? [StructuredElementWrapper(
                                        text: ocrText,
                                        elementType: "paragraph",
                                        pageNumber: pageNumber,
                                        isAtomicChunk: false,
                                        tableData: nil,
                                        listItems: nil
                                    )]
                                    : inferredElements
                                let metrics = self.structuredElementMetrics(in: fallbackElements)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "structured-fallback-ocr",
                                    chars: ocrText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: fallbackElements,
                                    pageText: ocrText,
                                    hasStructure: metrics.tables > 0 || metrics.lists > 0,
                                    usedOCR: true,
                                    tablesFound: metrics.tables,
                                    listsFound: metrics.lists,
                                    headersFound: metrics.headers
                                )
                            }
                            if !isGarbled, let nativeText = bestAvailableText, !nativeText.isEmpty {
                                let inferredElements = self.inferredStructuredElementsForPDFPageText(nativeText, pageNumber: pageNumber)
                                let fallbackElements = inferredElements.isEmpty
                                    ? [StructuredElementWrapper(
                                        text: nativeText,
                                        elementType: "paragraph",
                                        pageNumber: pageNumber,
                                        isAtomicChunk: false,
                                        tableData: nil,
                                        listItems: nil
                                    )]
                                    : inferredElements
                                let metrics = self.structuredElementMetrics(in: fallbackElements)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: renderData.layoutText != nil ? "structured-no-document-layout" : "structured-no-document-native",
                                    chars: nativeText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: fallbackElements,
                                    pageText: nativeText,
                                    hasStructure: metrics.tables > 0 || metrics.lists > 0,
                                    usedOCR: false,
                                    tablesFound: metrics.tables,
                                    listsFound: metrics.lists,
                                    headersFound: metrics.headers
                                )
                            }
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "structured-no-document-empty",
                                chars: 0
                            )
                            return PageParseResult(pageIndex: pageIndex, elements: [], pageText: "", hasStructure: false, usedOCR: false, tablesFound: 0, listsFound: 0, headersFound: 0)

                        } catch {
                            Log.warning("[DocumentProcessor] Structured parsing failed for page \(pageNumber): \(error.localizedDescription)", category: .ingestion)

                            if let rescueResult = await IntelligentDocumentProcessor.shared.rescuePageRegions(
                                from: pageImage,
                                pageNumber: pageNumber,
                                preferHighAccuracy: renderData.preferHighResolutionStructure
                            ), let rescuePayload = self.regionRescuePayload(from: rescueResult, pageNumber: pageNumber) {
                                let metrics = self.structuredElementMetrics(in: rescuePayload.elements)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "structured-error-region-rescue",
                                    chars: rescuePayload.pageText.count,
                                    extra: [
                                        ("tables", "\(rescuePayload.tableCount)"),
                                        ("lists", "\(rescuePayload.listCount)"),
                                        ("figures", "\(rescuePayload.figureCount)")
                                    ]
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: rescuePayload.elements,
                                    pageText: rescuePayload.pageText,
                                    hasStructure: metrics.tables > 0 || metrics.lists > 0,
                                    usedOCR: true,
                                    tablesFound: metrics.tables,
                                    listsFound: metrics.lists,
                                    headersFound: metrics.headers
                                )
                            }

                            // Fallback to the best native/layout text — but NOT if text layer is garbled
                            if !isGarbled, let nativeText = bestAvailableText, !nativeText.isEmpty {
                                let inferredElements = self.inferredStructuredElementsForPDFPageText(nativeText, pageNumber: pageNumber)
                                let fallbackElements = inferredElements.isEmpty
                                    ? [StructuredElementWrapper(
                                        text: nativeText,
                                        elementType: "paragraph",
                                        pageNumber: pageNumber,
                                        isAtomicChunk: false,
                                        tableData: nil,
                                        listItems: nil
                                    )]
                                    : inferredElements
                                let metrics = self.structuredElementMetrics(in: fallbackElements)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: renderData.layoutText != nil ? "structured-error-fallback-layout" : "structured-error-fallback-native",
                                    chars: nativeText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: fallbackElements,
                                    pageText: nativeText,
                                    hasStructure: metrics.tables > 0 || metrics.lists > 0,
                                    usedOCR: false,
                                    tablesFound: metrics.tables,
                                    listsFound: metrics.lists,
                                    headersFound: metrics.headers
                                )
                            }
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "structured-error-empty",
                                chars: 0
                            )
                            return PageParseResult(pageIndex: pageIndex, elements: [], pageText: "", hasStructure: false, usedOCR: false, tablesFound: 0, listsFound: 0, headersFound: 0)
                        }
                    }
                }

                var collected: [PageParseResult] = []
                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    collected.append(result)
                }
                return collected
            }

            try Task.checkCancellation()

            // Aggregate metrics from this sub-batch and emit live progress
            var batchTables = 0, batchLists = 0, batchHeaders = 0, batchOCR = 0
            for r in batchResults {
                batchTables += r.tablesFound
                batchLists += r.listsFound
                batchHeaders += r.headersFound
                if r.usedOCR { batchOCR += 1 }

                // Save page checkpoint
                let pageIndex = r.pageIndex
                let checkpointURL = checkpointDir.appendingPathComponent("page_\(pageIndex).json")
                let checkpointPage = IngestionCheckpointPage(
                    pageIndex: r.pageIndex,
                    elements: r.elements.map { CodableStructuredElement($0) },
                    pageText: r.pageText,
                    hasStructure: r.hasStructure,
                    usedOCR: r.usedOCR,
                    tablesFound: r.tablesFound,
                    listsFound: r.listsFound,
                    headersFound: r.headersFound
                )
                if let data = try? JSONEncoder().encode(checkpointPage) {
                    try? data.write(to: checkpointURL)
                    Log.info("[Checkpoint] Saved checkpoint for page \(r.pageIndex + 1)", category: .ingestion)
                }
            }
            incrementMetric(tables: batchTables, lists: batchLists, headers: batchHeaders, ocrPages: batchOCR)

            results.append(contentsOf: batchResults)
            // MEMORY-SAFE: batchRenderData goes out of scope here, releasing CIImages
            // Only maxRenderConcurrency (3) page images were alive at once
            } // end inner sub-batch (render-safe)

            // Emit updated progress with accumulated metrics (once per outer batch)
            await MainActor.run {
                let m = self.liveMetrics
                var detailParts: [String] = ["pg \(batchEnd)/\(pageCount)"]
                if m.tablesFound > 0 { detailParts.append("\(m.tablesFound) tbl") }
                if m.listsFound > 0 { detailParts.append("\(m.listsFound) lst") }
                if m.headersFound > 0 { detailParts.append("\(m.headersFound) hdr") }
                self.emitProgress(
                    stage: "vision",
                    detail: "👁 Vision: " + detailParts.joined(separator: " • "),
                    page: batchEnd,
                    totalPages: pageCount
                )
            }
        } // end outer batch (progress reporting)

        // Sort by page index and aggregate results
        results.sort { $0.pageIndex < $1.pageIndex }

        var allElements: [StructuredElementWrapper] = []
        var rawPageTexts: [String] = []
        var pagesWithStructure = 0
        var ocrUsedCount = 0

        for result in results {
            allElements.append(contentsOf: result.elements)
            rawPageTexts.append(result.pageText)
            if result.hasStructure { pagesWithStructure += 1 }
            if result.usedOCR { ocrUsedCount += 1 }
        }

        let pageTexts = removeGarbageLinesFromExtractedPages(rawPageTexts, source: "pdf-structured")

        // MEMORY OPTIMIZATION: Release the heavy results array before image analysis.
        // For a 542-page PDF, results holds ~100-200MB of PageParseResult objects.
        // Image analysis adds another ~200MB+ of CIImages — without this release,
        // the combined pressure causes watchdog kills on A18 Pro.
        results.removeAll()

        Log.info("[DocumentProcessor] Structured parsing complete: \(pagesWithStructure)/\(pageCount) pages with tables/lists, \(allElements.count) elements extracted", category: .ingestion)

        // ============================================================
        // VISUAL UNDERSTANDING: Analyze embedded images, diagrams, charts
        // This enables semantic search over visual content (schematics, flowcharts, etc.)
        // ============================================================
        let imageElements = await analyzeEmbeddedImages(pdfDocument: pdfDocument, pageCount: pageCount)
        if !imageElements.isEmpty {
            allElements.append(contentsOf: imageElements)
            Log.info("[DocumentProcessor] Added \(imageElements.count) visual content chunks from images/diagrams", category: .ingestion)
        }

        // Clean headers/footers and assemble text
        let cleanedPageTexts = removeRepeatedHeadersFooters(from: pageTexts)
        var fullText = ""
        var pageTextRanges: PageTextMapping = [:]

        for (index, cleanedText) in cleanedPageTexts.enumerated() {
            let pageNumber = index + 1
            let pageStartIndex = fullText.endIndex
            if !cleanedText.isEmpty {
                // Insert page break sentinel between pages (same as legacy path)
                // so processDocument can split into per-page content with --- Page N --- markers
                if !fullText.isEmpty {
                    fullText += "\n\n\(Self.pageBreakSentinel)\n\n"
                }
                fullText += cleanedText
                pageTextRanges[pageNumber] = pageStartIndex..<fullText.endIndex
            }
        }

        let pageInfo = PageInfo(
            totalPages: pageCount,
            ocrPagesUsed: ocrUsedCount,
            pageNumbers: Array(1...pageCount),
            pageTextRanges: pageTextRanges
        )

        return StructuredExtractionResult(
            text: fullText,
            pageInfo: pageInfo,
            structuredElements: allElements,
            // True when structured extraction produced anything usable, not only when it found a
            // table or a list. `pagesWithStructure` counts tables and lists alone, so a document
            // full of diagrams and headings but containing no table reported `false` here, took the
            // flat-text branch at the call site, and threw away every structured element — titles,
            // figure descriptions, and the embedded-image analysis chunks appended just above.
            // The Neural Engine time to OCR the labels inside each figure was spent and the result
            // discarded before indexing, while the ingestion HUD reported success.
            usedStructuredParsing: pagesWithStructure > 0 || !allElements.isEmpty
        )
    }

    /// Create chunks that respect document structure (tables as atomic units, paragraphs chunked normally)
    /// Tables are kept as single chunks to preserve data integrity across any domain.
    private func createStructureAwareChunks(
        elements: [StructuredElementWrapper],
        fullText: String,
        config: SemanticChunker.ChunkingConfig,
        documentId: UUID,
        pageInfo: PageInfo,
        filename: String,
        documentCategory: DocumentSemanticCategory
    ) -> [ProcessedChunk] {
        var chunks: [ProcessedChunk] = []
        var chunkIndex = 0

        _ = pageInfo

        // Collect all detected entities from structured elements
        var allDetectedEntities: [(type: String, value: String)] = []
        for element in elements {
            allDetectedEntities.append(contentsOf: element.detectedEntities)
        }

        // Store entities for vocabulary learning
        self.lastDetectedEntities = allDetectedEntities
        if !allDetectedEntities.isEmpty {
            Log.info("[DocumentProcessor] Collected \(allDetectedEntities.count) Vision-detected entities for vocabulary learning", category: .ingestion)
        }

        // Group paragraphs for semantic chunking, but tables and lists become atomic chunks
        var paragraphBuffer: [(text: String, page: Int)] = []

        func appendChunk(
            text: String,
            parentText: String?,
            pageNumber: Int,
            sectionTitle: String?,
            structureType: String,
            chunkType: ChunkSemanticType,
            semanticDensity: Float,
            hasNumericData: Bool,
            hasListStructure: Bool,
            sectionPath: [String],
            entities: [String] = [],
            abbreviations: [String: String] = [:],
            tableTitle: String? = nil,
            siblingGroupId: String? = nil,
            structuredTable: StructuredTablePayload? = nil
        ) {
            let resolvedSectionTitle = sectionTitle.flatMap { sanitizeStructuredLabel($0) }
            let resolvedSectionPath = sanitizedSectionPath(sectionPath)
            let metadata = makeChunkMetadata(
                chunkIndex: chunkIndex,
                text: text,
                pageNumber: pageNumber,
                sectionTitle: resolvedSectionTitle,
                structureType: structureType,
                chunkType: chunkType,
                documentCategory: documentCategory,
                sectionPath: resolvedSectionPath,
                semanticDensity: semanticDensity,
                hasNumericData: hasNumericData,
                hasListStructure: hasListStructure,
                entities: entities,
                abbreviations: abbreviations,
                tableTitle: tableTitle,
                siblingGroupId: siblingGroupId
            )
            chunks.append(ProcessedChunk(
                text: text,
                parentText: parentText,
                metadata: metadata,
                structuredTable: structuredTable
            ))
            chunkIndex += 1
        }

        func flushParagraphBuffer() {
            guard !paragraphBuffer.isEmpty else { return }

            // Combine paragraphs for semantic chunking
            let combinedText = paragraphBuffer.map { $0.text }.joined(separator: "\n\n")

            // Build per-page text ranges from the buffer so SemanticChunker
            // can assign the correct page number to each sub-chunk.
            // Each paragraph knows its source page; we track where it lands
            // in the combined string and build a [pageNum: Range<String.Index>] map.
            var localPageRanges: [Int: Range<String.Index>] = [:]
            var currentOffset = combinedText.startIndex
            for (i, entry) in paragraphBuffer.enumerated() {
                let textEnd = combinedText.index(currentOffset, offsetBy: entry.text.count, limitedBy: combinedText.endIndex) ?? combinedText.endIndex
                let entryRange = currentOffset..<textEnd

                if let existing = localPageRanges[entry.page] {
                    // Extend the range for this page (non-contiguous paragraphs on same page)
                    localPageRanges[entry.page] = existing.lowerBound..<textEnd
                } else {
                    localPageRanges[entry.page] = entryRange
                }

                // Skip past the "\n\n" separator between paragraphs
                if i < paragraphBuffer.count - 1 {
                    currentOffset = combinedText.index(textEnd, offsetBy: 2, limitedBy: combinedText.endIndex) ?? combinedText.endIndex
                } else {
                    currentOffset = textEnd
                }
            }

            let semanticChunker = SemanticChunker()
            let subChunks = semanticChunker.chunkText(
                combinedText,
                documentId: documentId,
                config: config,
                pageNumbers: localPageRanges,
                documentCategory: documentCategory
            )

            for subChunk in subChunks {
                let cleanedSectionTitle = subChunk.metadata.sectionTitle.flatMap { sanitizeStructuredLabel($0) }
                let cleanedSectionPath = sanitizedSectionPath(subChunk.metadata.sectionPath)
                let metadata = ChunkMetadata(
                    chunkIndex: chunkIndex,
                    startPosition: subChunk.metadata.startOffset,
                    endPosition: subChunk.metadata.endOffset,
                    pageNumber: subChunk.metadata.pageNumber,
                    sectionTitle: cleanedSectionTitle,
                    keywords: subChunk.metadata.topKeywords,
                    semanticDensity: subChunk.metadata.semanticDensity,
                    hasNumericData: subChunk.metadata.hasNumericData,
                    hasListStructure: subChunk.metadata.hasListStructure,
                    wordCount: subChunk.metadata.wordCount,
                    characterCount: subChunk.metadata.characterCount,
                    structureType: "paragraph",
                    entities: subChunk.metadata.entities,
                    abbreviations: subChunk.metadata.abbreviations,
                    sectionPath: cleanedSectionPath.isEmpty ? nil : cleanedSectionPath,
                    documentCategory: subChunk.metadata.documentCategory,
                    chunkType: subChunk.metadata.chunkType,
                    tableTitle: subChunk.metadata.tableTitle,
                    hasCrossReferences: subChunk.metadata.hasCrossReferences,
                    resolvedReferences: subChunk.metadata.resolvedReferences
                )
                chunks.append(ProcessedChunk(
                    text: subChunk.content,
                    parentText: subChunk.parentContent,
                    metadata: metadata
                ))
                chunkIndex += 1
            }

            paragraphBuffer.removeAll()
        }

        // Track section context for table association
        var currentSectionTitle: String? = nil
        var currentSectionPath: [String] = []

        for element in elements {
            // Track section titles for context association
            if element.elementType == "title" {
                let titleText = sanitizeStructuredLabel(element.text)
                if let titleText {
                    currentSectionTitle = titleText
                    // Structured parsing currently gives us flat page titles, not true heading levels.
                    // Reusing the last few page titles as a fake hierarchy pollutes retrieval metadata.
                    currentSectionPath = [titleText]
                } else {
                    Log.debug("[DocumentProcessor] Dropping garbled section title from path context", category: .ingestion)
                }
            }

            if element.isAtomicChunk {
                // Flush any pending paragraphs first
                flushParagraphBuffer()

                if element.elementType == "table", let tableData = element.tableData {
                    let tableTitle = resolveTableTitle(tableData: tableData, sectionTitle: currentSectionTitle)
                    let structuredTable = structuredTablePayload(
                        from: tableData,
                        tableTitle: tableTitle,
                        extractionQuality: element.qualityScore,
                        extractionSource: element.extractionSource
                    )
                    let siblingGroupId = siblingGroupIdentifier(
                        prefix: "table",
                        pageNumber: element.pageNumber,
                        title: tableTitle
                    )

                    let structuralText = buildStructuralTableText(
                        tableData: tableData,
                        tableTitle: tableTitle,
                        filename: filename,
                        sectionPath: currentSectionPath
                    )

                    let structuralWords = countWords(structuralText)
                    let maxAtomicWords = 380
                    if structuralWords > maxAtomicWords {
                        let baseMetadata = makeChunkMetadata(
                            chunkIndex: chunkIndex,
                            text: structuralText,
                            pageNumber: element.pageNumber,
                            sectionTitle: currentSectionTitle,
                            structureType: "table",
                            chunkType: .tableStructural,
                            documentCategory: documentCategory,
                            sectionPath: currentSectionPath,
                            semanticDensity: 0.90,
                            hasNumericData: true,
                            hasListStructure: false,
                            entities: element.detectedEntities.map(\ .value),
                            tableTitle: tableTitle,
                            siblingGroupId: siblingGroupId
                        )
                        let splitChunks = splitOversizedAtomicChunk(
                            text: structuralText,
                            contextPrefix: "",
                            element: element,
                            baseMetadata: baseMetadata,
                            parentText: currentSectionTitle,
                            structuredTable: structuredTable,
                            maxWords: maxAtomicWords
                        )
                        chunks.append(contentsOf: splitChunks)
                        chunkIndex += splitChunks.count
                    } else {
                        appendChunk(
                            text: structuralText,
                            parentText: currentSectionTitle,
                            pageNumber: element.pageNumber,
                            sectionTitle: currentSectionTitle,
                            structureType: "table",
                            chunkType: .tableStructural,
                            semanticDensity: 0.90,
                            hasNumericData: true,
                            hasListStructure: false,
                            sectionPath: currentSectionPath,
                            entities: element.detectedEntities.map(\ .value),
                            tableTitle: tableTitle,
                            siblingGroupId: siblingGroupId,
                            structuredTable: structuredTable
                        )
                    }

                    let semanticText = buildSemanticTableSummary(
                        tableData: tableData,
                        tableTitle: tableTitle,
                        filename: filename,
                        sectionPath: currentSectionPath,
                        documentCategory: documentCategory
                    )
                    appendChunk(
                        text: semanticText,
                        parentText: currentSectionTitle,
                        pageNumber: element.pageNumber,
                        sectionTitle: currentSectionTitle,
                        structureType: "table",
                        chunkType: .tableSemantic,
                        semanticDensity: 0.82,
                        hasNumericData: semanticText.rangeOfCharacter(from: .decimalDigits) != nil,
                        hasListStructure: false,
                        sectionPath: currentSectionPath,
                        entities: element.detectedEntities.map(\ .value),
                        tableTitle: tableTitle,
                        siblingGroupId: siblingGroupId
                    )

                    if shouldEmitCompatibilityRowChunks(
                        tableData: tableData,
                        tableTitle: tableTitle,
                        extractionSource: element.extractionSource
                    ) {
                        let rowTexts = buildCompatibilityRowTexts(
                            tableData: tableData,
                            tableTitle: tableTitle,
                            filename: filename,
                            sectionPath: currentSectionPath
                        )
                        for rowText in rowTexts {
                            appendChunk(
                                text: rowText,
                                parentText: currentSectionTitle,
                                pageNumber: element.pageNumber,
                                sectionTitle: currentSectionTitle,
                                structureType: "table",
                                chunkType: .tableStructural,
                                semanticDensity: 0.88,
                                hasNumericData: rowText.rangeOfCharacter(from: .decimalDigits) != nil,
                                hasListStructure: false,
                                sectionPath: currentSectionPath,
                                entities: element.detectedEntities.map(\ .value),
                                tableTitle: tableTitle,
                                siblingGroupId: siblingGroupId
                            )
                        }
                    }

                    Log.debug("[DocumentProcessor] Created companion table chunks for page \(element.pageNumber), section: \(currentSectionTitle ?? "none")", category: .ingestion)
                    continue
                }

                if element.elementType == "list" {
                    let siblingGroupId = siblingGroupIdentifier(
                        prefix: "list",
                        pageNumber: element.pageNumber,
                        title: currentSectionTitle ?? "list"
                    )
                    let listItems = normalizedListItems(from: element)
                    for item in listItems {
                        let listText = buildListItemText(item: item, sectionPath: currentSectionPath, sectionTitle: currentSectionTitle)
                        let itemChunkType: ChunkSemanticType = isWarningLikeListItem(item, sectionTitle: currentSectionTitle) ? .warning : .listItem
                        appendChunk(
                            text: listText,
                            parentText: currentSectionTitle,
                            pageNumber: element.pageNumber,
                            sectionTitle: currentSectionTitle,
                            structureType: "list",
                            chunkType: itemChunkType,
                            semanticDensity: 0.72,
                            hasNumericData: listText.rangeOfCharacter(from: .decimalDigits) != nil,
                            hasListStructure: true,
                            sectionPath: currentSectionPath,
                            entities: element.detectedEntities.map(\ .value),
                            siblingGroupId: siblingGroupId
                        )
                    }
                    Log.debug("[DocumentProcessor] Created \(listItems.count) list item chunks from page \(element.pageNumber)", category: .ingestion)
                    continue
                }

                if element.elementType == "figure", let imageAnalysis = element.imageAnalysis {
                    let figureTitle = resolveFigureTitle(from: imageAnalysis)
                    let siblingGroupId = siblingGroupIdentifier(
                        prefix: "figure",
                        pageNumber: element.pageNumber,
                        title: figureTitle
                    )
                    let figureText = buildFigureChunkText(
                        analyzed: imageAnalysis,
                        filename: filename,
                        sectionPath: currentSectionPath
                    )
                    let visualMetadata = makeChunkMetadata(
                        chunkIndex: chunkIndex,
                        text: figureText,
                        pageNumber: element.pageNumber,
                        sectionTitle: currentSectionTitle,
                        structureType: "figure",
                        chunkType: .prose,
                        documentCategory: documentCategory,
                        sectionPath: currentSectionPath,
                        semanticDensity: 0.78,
                        hasNumericData: figureText.rangeOfCharacter(from: .decimalDigits) != nil,
                        hasListStructure: false,
                        entities: imageClassificationLabels(from: imageAnalysis),
                        siblingGroupId: siblingGroupId,
                        bbox: imageAnalysis.boundingBox,
                        imageContentType: imageAnalysis.contentType.rawValue,
                        imageCaption: imageAnalysis.associatedCaption,
                        imageDescription: imageAnalysis.description,
                        imageExtractedText: imageAnalysis.extractedText,
                        imageClassifications: imageClassificationLabels(from: imageAnalysis)
                    )

                    let maxAtomicWords = 380
                    if countWords(figureText) > maxAtomicWords {
                        let splitChunks = splitOversizedAtomicChunk(
                            text: figureText,
                            contextPrefix: "",
                            element: element,
                            baseMetadata: visualMetadata,
                            parentText: currentSectionTitle,
                            maxWords: maxAtomicWords
                        )
                        chunks.append(contentsOf: splitChunks)
                        chunkIndex += splitChunks.count
                    } else {
                        chunks.append(ProcessedChunk(
                            text: figureText,
                            parentText: currentSectionTitle,
                            metadata: visualMetadata
                        ))
                        chunkIndex += 1
                    }

                    continue
                }

            } else if element.elementType == "paragraph" || element.elementType == "title" {
                // Buffer paragraphs for semantic chunking
                let normalized = OCRConfiguration.normalizeExtractedText(element.text)
                let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Do not feed garbled title text into paragraph chunking path
                    if element.elementType == "title", sanitizeStructuredLabel(trimmed) == nil {
                        continue
                    }
                    paragraphBuffer.append((text: trimmed, page: element.pageNumber))
                }
            } else {
                // Lists that aren't atomic get buffered too
                let normalized = OCRConfiguration.normalizeExtractedText(element.text)
                let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    paragraphBuffer.append((text: trimmed, page: element.pageNumber))
                }
            }
        }

        // Flush any remaining paragraphs
        flushParagraphBuffer()

        // Log structure breakdown
        let tableChunks = chunks.filter { $0.metadata.structureType == "table" }.count
        let listChunks = chunks.filter { $0.metadata.structureType == "list" }.count
        let paragraphChunks = chunks.filter { $0.metadata.structureType == "paragraph" }.count

        Log.info("[DocumentProcessor] Structure-aware chunking: \(tableChunks) tables, \(listChunks) lists, \(paragraphChunks) paragraphs", category: .ingestion)

        return chunks
    }

    private func classifyDocumentCategory(
        text: String,
        filename: String,
        documentType: DocumentType,
        structuredElements: [StructuredElementWrapper]
    ) -> DocumentSemanticCategory {
        let lowerFilename = filename.lowercased()
        let sampleLength = max(200, min(text.count / 10, 12000))
        let sample = String(text.prefix(sampleLength)).lowercased()

        var scores: [DocumentSemanticCategory: Double] = [
            .technicalManual: 0,
            .scientificPaper: 0,
            .referenceTable: 0,
            .regulatory: 0,
            .general: 0.25,
        ]

        func add(_ category: DocumentSemanticCategory, _ amount: Double) {
            scores[category, default: 0] += amount
        }

        let strongTechnicalTerms = ["manual", "user guide", "owner", "instructions for use", "ifu", "installation", "troubleshooting", "service manual", "operating instructions"]
        let technicalTerms = ["specifications", "maintenance", "calibration", "setup", "configuration", "controls", "reference manual"]
        let scientificTerms = ["abstract", "introduction", "methods", "materials", "results", "discussion", "conclusion", "references", "doi", "p <", "confidence interval", "randomized", "study"]
        let regulatoryTerms = ["compliance", "regulatory", "iec", "fda", "emc", "warning", "contraindications", "adverse", "authorized representative", "labeling"]
        let referenceTerms = ["table", "specification", "capacity", "dimensions", "part number", "model number", "sku", "compatibility", "matrix", "requirements"]
        let scientificNarrativeSample = isLikelyScientificNarrativeSample(sample)

        for term in strongTechnicalTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.technicalManual, lowerFilename.contains(term) ? 1.2 : 0.7)
        }

        for term in technicalTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.technicalManual, lowerFilename.contains(term) ? 0.8 : 0.45)
        }

        for term in scientificTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.scientificPaper, lowerFilename.contains(term) ? 1.4 : 0.8)
        }

        for term in regulatoryTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.regulatory, lowerFilename.contains(term) ? 1.6 : 0.9)
        }

        for term in referenceTerms where sample.contains(term) || lowerFilename.contains(term) {
            if scientificNarrativeSample && term == "table" {
                continue
            }
            add(.referenceTable, lowerFilename.contains(term) ? 1.2 : 0.7)
        }

        let tableCount = structuredElements.filter { $0.elementType == "table" }.count
        let trustedTableCount = structuredElements.filter { $0.elementType == "table" && !isRecoveredHeuristicTable($0) }.count
        let listCount = structuredElements.filter { $0.elementType == "list" }.count
        if trustedTableCount >= 3 {
            add(.referenceTable, 0.9)
        } else if tableCount >= 3 && scientificNarrativeSample {
            add(.scientificPaper, 0.2)
        }
        if listCount >= 3 {
            add(.regulatory, 0.25)
        }

        let numericDensity = Double(sample.filter { $0.isNumber }.count) / Double(max(sample.count, 1))
        if numericDensity > 0.08 {
            if !scientificNarrativeSample {
                add(.referenceTable, 0.35)
            }
            add(.scientificPaper, 0.15)
        }

        if scientificNarrativeSample {
            add(.scientificPaper, 0.45)
        }

        if sample.contains("table ") && sample.contains("figure ") {
            add(.scientificPaper, 0.7)
        }

        if sample.contains("error code") || sample.contains("troubleshooting") {
            add(.technicalManual, 0.55)
        }

        let rankedScores = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value > rhs.value
        }

        guard let best = rankedScores.first else { return .general }
        let runnerUp = rankedScores.dropFirst().first?.value ?? 0
        guard best.value >= 0.9, (best.value - runnerUp) >= 0.2 else {
            return .general
        }

        return best.key
    }

    private func makeChunkMetadata(
        chunkIndex: Int,
        text: String,
        pageNumber: Int?,
        sectionTitle: String?,
        structureType: String,
        chunkType: ChunkSemanticType,
        documentCategory: DocumentSemanticCategory,
        sectionPath: [String],
        semanticDensity: Float,
        hasNumericData: Bool,
        hasListStructure: Bool,
        entities: [String] = [],
        abbreviations: [String: String] = [:],
        tableTitle: String? = nil,
        siblingGroupId: String? = nil,
        bbox: CGRect? = nil,
        imageContentType: String? = nil,
        imageCaption: String? = nil,
        imageDescription: String? = nil,
        imageExtractedText: String? = nil,
        imageClassifications: [String] = []
    ) -> ChunkMetadata {
        let references = GraphIndexService.extractReferenceTargets(from: text)
        return ChunkMetadata(
            chunkIndex: chunkIndex,
            startPosition: 0,
            endPosition: text.count,
            pageNumber: pageNumber,
            sectionTitle: sectionTitle,
            keywords: extractKeywordsFromStructuredElement(text, type: structureType),
            semanticDensity: semanticDensity,
            hasNumericData: hasNumericData,
            hasListStructure: hasListStructure,
            wordCount: countWords(text),
            characterCount: text.count,
            structureType: structureType,
            siblingGroupId: siblingGroupId,
            entities: entities,
            abbreviations: abbreviations,
            sectionPath: sectionPath.isEmpty ? nil : sectionPath,
            bboxArray: bbox.map { [$0.origin.x, $0.origin.y, $0.size.width, $0.size.height] },
            documentCategory: documentCategory,
            chunkType: chunkType,
            tableTitle: tableTitle,
            imageContentType: imageContentType,
            imageCaption: imageCaption,
            imageDescription: imageDescription,
            imageExtractedText: imageExtractedText,
            imageClassifications: imageClassifications,
            hasCrossReferences: !references.isEmpty,
            resolvedReferences: references
        )
    }

    private nonisolated func imageClassificationLabels(from analyzed: AnalyzedImage) -> [String] {
        analyzed.classifications
            .prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    private nonisolated func resolveFigureTitle(from analyzed: AnalyzedImage) -> String {
        if let caption = normalizedImageContextText(analyzed.associatedCaption, maxLength: 90) {
            return caption
        }

        let typeLabel = analyzed.contentType == .unknown ? "Figure" : analyzed.contentType.rawValue.capitalized
        return "\(typeLabel) on page \(analyzed.pageNumber)"
    }

    private nonisolated func normalizedImageContextText(_ raw: String?, maxLength: Int) -> String? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maxLength))
    }

    private func buildFigureChunkText(
        analyzed: AnalyzedImage,
        filename: String,
        sectionPath: [String]
    ) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        var lines: [String] = []

        if !resolvedSectionPath.isEmpty {
            lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
        }

        lines.append("FIGURE: \(resolveFigureTitle(from: analyzed))")
        lines.append("TYPE: \((analyzed.contentType == .unknown ? "Image" : analyzed.contentType.rawValue.capitalized))")

        let topLabels = imageClassificationLabels(from: analyzed)
        if !topLabels.isEmpty {
            lines.append("CLASSIFICATIONS: \(topLabels.joined(separator: ", "))")
        }

        if let caption = normalizedImageContextText(analyzed.associatedCaption, maxLength: 220) {
            lines.append("CAPTION: \(caption)")
        }

        if let description = normalizedImageContextText(analyzed.description, maxLength: 320) {
            lines.append("SUMMARY: \(description)")
        }

        if let extractedText = normalizedImageContextText(analyzed.extractedText, maxLength: 280) {
            lines.append("LABELS: \(extractedText)")
        }

        if let precedingContext = normalizedImageContextText(analyzed.precedingContext, maxLength: 220) {
            lines.append("NEARBY BEFORE: \(precedingContext)")
        }

        if let followingContext = normalizedImageContextText(analyzed.followingContext, maxLength: 220) {
            lines.append("NEARBY AFTER: \(followingContext)")
        }

        lines.append("SOURCE: \(filename), page \(analyzed.pageNumber)")
        return lines.joined(separator: "\n")
    }

    private func resolveTableTitle(tableData: TableData, sectionTitle: String?) -> String {
        if let caption = sanitizeStructuredLabel(tableData.caption ?? "") {
            return caption
        }
        if let sectionTitle, let cleanSection = sanitizeStructuredLabel(sectionTitle) {
            return cleanSection
        }
        return "Table"
    }

    private func structuredTablePayload(
        from tableData: TableData,
        tableTitle: String,
        extractionQuality: Double? = nil,
        extractionSource: String? = nil
    ) -> StructuredTablePayload {
        let lowQualityRows = lowQualityRowIndices(for: tableData)
        return StructuredTablePayload(
            title: tableTitle,
            headers: inferredHeaders(for: tableData),
            rows: dataRows(for: tableData),
            extractionQuality: extractionQuality ?? tableQualityScore(tableData),
            extractionSource: extractionSource ?? "vision_document",
            lowQualityRowIndices: lowQualityRows
        )
    }

    private func siblingGroupIdentifier(prefix: String, pageNumber: Int, title: String) -> String {
        let normalizedTitle = title.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(prefix)-p\(pageNumber)-\(normalizedTitle)"
    }

    private func normalizedListItems(from element: StructuredElementWrapper) -> [String] {
        if let listItems = element.listItems, !listItems.isEmpty {
            return listItems
                .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return element.text
            .components(separatedBy: CharacterSet.newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: #"^(?:[-*•]\s*|\d+[\.)]\s*)"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    private func buildListItemText(item: String, sectionPath: [String], sectionTitle: String?) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let resolvedSectionTitle = sectionTitle.flatMap { sanitizeStructuredLabel($0) }
        var lines: [String] = []
        if !resolvedSectionPath.isEmpty {
            lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
        } else if let resolvedSectionTitle {
            lines.append("Section: \(resolvedSectionTitle)")
        }
        lines.append(item)
        return lines.joined(separator: "\n")
    }

    private func isWarningLikeListItem(_ item: String, sectionTitle: String?) -> Bool {
        let combined = [sectionTitle, item].compactMap { $0?.lowercased() }.joined(separator: " ")
        let warningTerms = ["warning", "caution", "danger", "important", "notice", "precaution"]
        return warningTerms.contains(where: { combined.contains($0) })
    }

    private func buildStructuralTableText(
        tableData: TableData,
        tableTitle: String,
        filename: String,
        sectionPath: [String]
    ) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let headers = inferredHeaders(for: tableData)
        let rows = dataRows(for: tableData)

        var lines: [String] = []
        if !resolvedSectionPath.isEmpty {
            lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
        }
        lines.append("TABLE: \(tableTitle)")
        lines.append("HEADERS: \(headers.joined(separator: " | "))")

        for (index, row) in rows.enumerated() {
            let normalizedRow = normalizedRow(row, columnCount: headers.count)
            lines.append("ROW \(index + 1): \(normalizedRow.joined(separator: " | "))")
        }

        if let keyValuePairs = tableData.keyValuePairs, !keyValuePairs.isEmpty {
            lines.append("[Specifications]")
            for (key, value) in keyValuePairs {
                lines.append("\(key): \(value)")
            }
        }

        lines.append("SOURCE: \(filename), page \(tableData.pageNumber)")
        return lines.joined(separator: "\n")
    }

    private func buildSemanticTableSummary(
        tableData: TableData,
        tableTitle: String,
        filename: String,
        sectionPath: [String],
        documentCategory: DocumentSemanticCategory
    ) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let headers = inferredHeaders(for: tableData)
        let rows = dataRows(for: tableData)
        let categoryDescriptor: String = {
            switch documentCategory {
            case .technicalManual: return "technical reference"
            case .scientificPaper: return "research data"
            case .referenceTable: return "reference table"
            case .regulatory: return "regulatory table"
            case .general: return "document table"
            }
        }()

        var sentences: [String] = []
        sentences.append("This \(categoryDescriptor) from \(filename) page \(tableData.pageNumber) describes \(tableTitle.lowercased()).")

        if !resolvedSectionPath.isEmpty {
            sentences.append("It appears under \(resolvedSectionPath.joined(separator: " > ")).")
        }

        if !headers.isEmpty {
            let displayedHeaders = headers.prefix(5).joined(separator: ", ")
            sentences.append("Columns include \(displayedHeaders).")
        }

        if let keyValuePairs = tableData.keyValuePairs, !keyValuePairs.isEmpty {
            let preview = keyValuePairs.prefix(4).map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            sentences.append("Key values include \(preview).")
        } else if !rows.isEmpty {
            let preview = rows.prefix(2)
                .map { normalizedRow($0, columnCount: headers.count).filter { !$0.isEmpty }.joined(separator: " | ") }
                .filter { !$0.isEmpty }
                .joined(separator: " || ")
            if !preview.isEmpty {
                sentences.append("Representative rows: \(preview).")
            }
        }

        return sentences.joined(separator: " ")
    }

    private func shouldEmitCompatibilityRowChunks(
        tableData: TableData,
        tableTitle: String,
        extractionSource: String?
    ) -> Bool {
        let trustedSources: Set<String> = ["vision_document", "layout_table", "crop_rescue"]
        if let extractionSource, !trustedSources.contains(extractionSource) {
            return false
        }

        let headers = inferredHeaders(for: tableData).map { $0.lowercased() }
        let lowerTitle = tableTitle.lowercased()
        let signals = ["compat", "requirement", "supported", "model", "camera", "head", "coupler"]
        let headerSignal = headers.contains { header in signals.contains(where: { header.contains($0) }) }
        let titleSignal = signals.contains { lowerTitle.contains($0) }
        return (titleSignal || headerSignal) && headers.count >= 3 && dataRows(for: tableData).count >= 2
    }

    private func buildCompatibilityRowTexts(
        tableData: TableData,
        tableTitle: String,
        filename: String,
        sectionPath: [String]
    ) -> [String] {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let headers = inferredHeaders(for: tableData)
        return dataRows(for: tableData).compactMap { row in
            let normalized = normalizedRow(row, columnCount: headers.count)
            let visiblePairs = zip(headers, normalized).filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !visiblePairs.isEmpty else { return nil }

            var lines: [String] = []
            if !resolvedSectionPath.isEmpty {
                lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
            }
            lines.append("COMPATIBILITY ROW: \(tableTitle)")
            lines.append("CATEGORY: \(visiblePairs.first?.1 ?? "Item")")
            lines.append("VALUES: \(visiblePairs.map { "\($0.0)=\($0.1)" }.joined(separator: " | "))")
            lines.append("SOURCE: \(filename), page \(tableData.pageNumber)")
            return lines.joined(separator: "\n")
        }
    }

    private nonisolated func inferredHeaders(for tableData: TableData) -> [String] {
        let columnCount = tableData.rows.map(\ .count).max() ?? 0
        guard columnCount > 0 else { return [] }

        if let headerRow = tableData.headerRow, !headerRow.isEmpty {
            return (0..<columnCount).map { index in
                if index < headerRow.count {
                    let trimmed = headerRow[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
                }
                return "Column \(index + 1)"
            }
        }

        return (0..<columnCount).map { "Column \($0 + 1)" }
    }

    private nonisolated func dataRows(for tableData: TableData) -> [[String]] {
        if tableData.headerRow != nil && tableData.rows.count > 1 {
            return Array(tableData.rows.dropFirst())
        }
        return tableData.rows
    }

    private func normalizedRow(_ row: [String], columnCount: Int) -> [String] {
        var normalized = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if normalized.count < columnCount {
            normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
        } else if normalized.count > columnCount {
            normalized = Array(normalized.prefix(columnCount))
        }
        return normalized
    }

    /// Sanitizes potential section labels/titles used for section context.
    /// Returns nil when the label appears OCR-garbled and unsafe to propagate.
    private func sanitizeStructuredLabel(_ raw: String) -> String? {
        let normalized = OCRConfiguration
            .normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        guard !normalized.hasPrefix("[OCR unclear]"),
              !normalized.hasPrefix("[OCR quality: low]")
        else {
            return nil
        }

        // Filter line-level OCR garbage and re-evaluate
        let (cleaned, _) = OCRConfiguration.filterGarbageText(normalized)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 2 else { return nil }

        // Reject labels that are symbol-heavy / mostly non-alphanumeric
        let scalars = candidate.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let ratio = Double(alnumCount) / Double(max(1, scalars.count))
        if scalars.count >= 8, ratio < 0.45 {
            return nil
        }

        // Reject long labels that fail global text quality checks
        if candidate.count >= 24, !isTextQualityAcceptable(candidate) {
            return nil
        }

        guard isLikelyStructuredHeading(candidate) else { return nil }

        return candidate
    }

    private func sanitizedSectionPath(_ rawPath: [String]) -> [String] {
        rawPath.reduce(into: [String]()) { result, component in
            guard let cleaned = sanitizeStructuredLabel(component) else { return }
            guard result.last?.caseInsensitiveCompare(cleaned) != .orderedSame else { return }
            result.append(cleaned)
        }
    }

    private func sanitizeProcessedChunkMetadata(_ chunks: [ProcessedChunk]) -> [ProcessedChunk] {
        chunks.map { chunk in
            let cleanedSectionTitle = chunk.metadata.sectionTitle.flatMap { sanitizeStructuredLabel($0) }
            let cleanedSectionPath = sanitizedSectionPath(chunk.metadata.sectionPath ?? [])

            guard cleanedSectionTitle != chunk.metadata.sectionTitle
                || cleanedSectionPath != (chunk.metadata.sectionPath ?? [])
            else {
                return chunk
            }

            let base = chunk.metadata
            let metadata = ChunkMetadata(
                chunkIndex: base.chunkIndex,
                startPosition: base.startPosition,
                endPosition: base.endPosition,
                pageNumber: base.pageNumber,
                sectionTitle: cleanedSectionTitle,
                keywords: base.keywords,
                semanticDensity: base.semanticDensity,
                hasNumericData: base.hasNumericData,
                hasListStructure: base.hasListStructure,
                wordCount: base.wordCount,
                characterCount: base.characterCount,
                createdAt: base.createdAt,
                structureType: base.structureType,
                siblingGroupId: base.siblingGroupId,
                siblingCount: base.siblingCount,
                entities: base.entities,
                abbreviations: base.abbreviations,
                abstractionLevel: base.abstractionLevel,
                sectionPath: cleanedSectionPath.isEmpty ? nil : cleanedSectionPath,
                bboxArray: base.bboxArray,
                documentCategory: base.documentCategory,
                chunkType: base.chunkType,
                tableTitle: base.tableTitle,
                imageContentType: base.imageContentType,
                imageCaption: base.imageCaption,
                imageDescription: base.imageDescription,
                imageExtractedText: base.imageExtractedText,
                imageClassifications: base.imageClassifications,
                hasCrossReferences: base.hasCrossReferences,
                resolvedReferences: base.resolvedReferences
            )

            return ProcessedChunk(
                text: chunk.text,
                parentText: chunk.parentText,
                metadata: metadata,
                structuredTable: chunk.structuredTable
            )
        }
    }

    /// Keep retrieval metadata conservative: a bad heading hurts ranking more than a missing one.
    private func isLikelyStructuredHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("_"), !trimmed.contains("|") else { return false }
        guard trimmed.range(of: #"(?i)^row\s+\d+$"#, options: .regularExpression) == nil else { return false }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty, words.count <= 12 else { return false }

        let scalars = trimmed.unicodeScalars
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuationCount = scalars.filter { CharacterSet.punctuationCharacters.contains($0) }.count

        guard letterCount >= 2 else { return false }

        let alnumRatio = Double(letterCount + digitCount) / Double(max(1, scalars.count))
        if scalars.count >= 8, alnumRatio < 0.55 {
            return false
        }

        if punctuationCount > max(4, scalars.count / 4) {
            return false
        }

        if hasMixedLatinAndCyrillicScalars(trimmed) {
            return false
        }

        if isLikelyLatinSectionHint(trimmed) {
            if OCRConfiguration.isGarbageText(trimmed, isLatinDocument: true) {
                return false
            }

            if letterCount >= 8 {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(trimmed)
                let confidence = recognizer.languageHypotheses(withMaximum: 1).values.max() ?? 0
                if confidence < 0.24 {
                    return false
                }
            }
        }

        if words.count == 1, trimmed.count > 24, !trimmed.contains("-"), !trimmed.contains("/") {
            return false
        }

        return true
    }

    private func hasMixedLatinAndCyrillicScalars(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        guard latinCount > 0, cyrillicCount > 0 else { return false }
        let mixedRatio = Double(min(latinCount, cyrillicCount)) / Double(max(latinCount, cyrillicCount))
        return mixedRatio >= 0.15
    }

    private func isLikelyLatinSectionHint(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        if latinCount > 0 || cyrillicCount > 0 {
            return latinCount >= cyrillicCount
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominantLanguage = recognizer.dominantLanguage else { return false }

        let latinLanguages: Set<NLLanguage> = [
            .english, .french, .german, .spanish, .portuguese,
            .italian, .dutch, .swedish, .danish, .norwegian,
            .finnish, .polish, .czech, .romanian, .hungarian,
            .turkish, .indonesian, .malay, .vietnamese,
            .catalan, .croatian, .slovak
        ]
        return latinLanguages.contains(dominantLanguage)
    }

    /// Sanitizes narrative structured text used for chunking/storage.
    /// Reject low-confidence OCR wrappers and text that collapses to garbage after cleanup.
    private func sanitizeStructuredNarrativeText(_ raw: String, pageHasTables: Bool = false) -> String? {
        let normalized = OCRConfiguration
            .normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        guard !normalized.hasPrefix("[OCR unclear]"),
              !normalized.hasPrefix("[OCR quality: low]")
        else {
            return nil
        }

        let (cleaned, _) = OCRConfiguration.filterGarbageText(normalized, revertIfTooAggressive: false)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 3 else { return nil }

        let scalars = candidate.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let ratio = Double(alnumCount) / Double(max(1, scalars.count))
        if scalars.count >= 12, ratio < 0.45 {
            return nil
        }

        if pageHasTables, isLikelyTableLeakageNarrative(candidate) {
            return nil
        }

        return candidate
    }

    private func isLikelyTableLeakageNarrative(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 80 else { return false }

        let lower = trimmed.lowercased()
        if trimmed.contains("|") {
            return true
        }
        if lower.range(of: #"\b(?:row|column)\s+\d+\b"#, options: .regularExpression) != nil {
            return true
        }

        let scalars = trimmed.unicodeScalars
        let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let digitRatio = Double(digitCount) / Double(max(1, scalars.count))
        let sentenceStopCount = trimmed.filter { ".!?".contains($0) }.count
        let trademarkCount = trimmed.filter { $0 == "®" || $0 == "™" || $0 == "©" }.count

        let fragmentCount = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count

        let citationClusterCount: Int = {
            guard let regex = try? NSRegularExpression(
                pattern: #"\b\d{1,3}(?:,\d{1,3}){1,}\b|\b\d{1,3}-\d{1,3}\b"#,
                options: []
            ) else {
                return 0
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.numberOfMatches(in: trimmed, options: [], range: range)
        }()

        if digitRatio >= 0.08 && sentenceStopCount == 0 && (fragmentCount >= 4 || trademarkCount >= 1 || citationClusterCount >= 2) {
            return true
        }

        if trademarkCount >= 2 && fragmentCount >= 3 {
            return true
        }

        return false
    }

    /// Split an oversized atomic chunk (table/list) into multiple smaller chunks
    /// Preserves context prefix and section path on each chunk for retrieval coherence.
    /// For tables: repeats the header row at the top of each continuation chunk
    /// so that every chunk has column labels for its numeric values.
    private func splitOversizedAtomicChunk(
        text: String,
        contextPrefix: String,
        element: StructuredElementWrapper,
        baseMetadata: ChunkMetadata,
        parentText: String?,
        structuredTable: StructuredTablePayload? = nil,
        maxWords: Int
    ) -> [ProcessedChunk] {
        var chunks: [ProcessedChunk] = []

        // Remove context prefix from text to split just the content
        let contentText = text.hasPrefix(contextPrefix) ? String(text.dropFirst(contextPrefix.count)) : text

        // Split by rows for tables (line-based), or by items for lists
        let lines = contentText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // For tables: detect and preserve header row for repetition in continuation chunks
        // A header row is typically the first non-separator row (no pipes-only or dashes-only)
        let tableHeaderLine: String? = {
            guard element.elementType == "table", lines.count > 2 else { return nil }
            // Check if first line looks like a header (not a separator like "|---|---|")
            if let first = lines.first {
                let stripped = first.replacingOccurrences(of: "|", with: "")
                                   .replacingOccurrences(of: "-", with: "")
                                   .replacingOccurrences(of: ":", with: "")
                                   .trimmingCharacters(in: .whitespaces)
                // If there's actual text content (not just formatting), it's likely a header
                if !stripped.isEmpty {
                    return first
                }
            }
            return nil
        }()

        // Also detect markdown table separator (e.g., "|---|---|")
        let tableSeparatorLine: String? = {
            guard element.elementType == "table", lines.count > 2 else { return nil }
            if lines.count > 1 {
                let second = lines[1]
                let stripped = second.replacingOccurrences(of: "|", with: "")
                                    .replacingOccurrences(of: "-", with: "")
                                    .replacingOccurrences(of: ":", with: "")
                                    .replacingOccurrences(of: " ", with: "")
                // If it's just dashes and pipes, it's a separator
                if stripped.isEmpty {
                    return second
                }
            }
            return nil
        }()

        // Calculate header overhead for word budget
        let headerWords = (tableHeaderLine?.split(separator: " ").count ?? 0) +
                          (tableSeparatorLine?.split(separator: " ").count ?? 0)
        let effectiveMaxWords = maxWords - headerWords

        var currentChunkLines: [String] = []
        var currentWordCount = 0
        var chunkNumber = 0

        // Skip header lines in iteration (they'll be prepended to each chunk)
        let startIndex: Int
        if tableHeaderLine != nil && tableSeparatorLine != nil {
            startIndex = 2
        } else if tableHeaderLine != nil {
            startIndex = 1
        } else {
            startIndex = 0
        }

        for lineIndex in startIndex..<lines.count {
            let line = lines[lineIndex]
            let lineWords = line.split(separator: " ").count

            // If adding this line would exceed limit, flush current chunk
            if currentWordCount + lineWords > effectiveMaxWords && !currentChunkLines.isEmpty {
                // Build chunk with header repetition for tables
                var chunkLines: [String] = []
                if chunkNumber > 0, let header = tableHeaderLine {
                    // Continuation chunk — prepend header for context
                    chunkLines.append(header)
                    if let separator = tableSeparatorLine {
                        chunkLines.append(separator)
                    }
                }
                chunkLines.append(contentsOf: currentChunkLines)

                let chunkContent = contextPrefix + "[Part \(chunkNumber + 1)]\n" + chunkLines.joined(separator: "\n")
                let metadata = ChunkMetadata(
                    chunkIndex: baseMetadata.chunkIndex + chunkNumber,
                    startPosition: baseMetadata.startPosition,
                    endPosition: chunkContent.count,
                    pageNumber: baseMetadata.pageNumber,
                    sectionTitle: baseMetadata.sectionTitle,
                    keywords: extractKeywordsFromStructuredElement(chunkContent, type: element.elementType),
                    semanticDensity: baseMetadata.semanticDensity,
                    hasNumericData: baseMetadata.hasNumericData,
                    hasListStructure: baseMetadata.hasListStructure,
                    wordCount: countWords(chunkContent),
                    characterCount: chunkContent.count,
                    createdAt: baseMetadata.createdAt,
                    structureType: baseMetadata.structureType,
                    siblingGroupId: baseMetadata.siblingGroupId,
                    siblingCount: baseMetadata.siblingCount,
                    entities: baseMetadata.entities,
                    abbreviations: baseMetadata.abbreviations,
                    abstractionLevel: baseMetadata.abstractionLevel,
                    sectionPath: baseMetadata.sectionPath,
                    bboxArray: baseMetadata.bboxArray,
                    documentCategory: baseMetadata.documentCategory,
                    chunkType: baseMetadata.chunkType,
                    tableTitle: baseMetadata.tableTitle,
                    imageContentType: baseMetadata.imageContentType,
                    imageCaption: baseMetadata.imageCaption,
                    imageDescription: baseMetadata.imageDescription,
                    imageExtractedText: baseMetadata.imageExtractedText,
                    imageClassifications: baseMetadata.imageClassifications,
                    hasCrossReferences: baseMetadata.hasCrossReferences,
                    resolvedReferences: baseMetadata.resolvedReferences
                )
                chunks.append(ProcessedChunk(
                    text: chunkContent,
                    parentText: parentText,
                    metadata: metadata,
                    structuredTable: chunkNumber == 0 ? structuredTable : nil
                ))
                chunkNumber += 1
                currentChunkLines = []
                currentWordCount = 0
            }

            currentChunkLines.append(line)
            currentWordCount += lineWords
        }

        // Flush remaining lines
        if !currentChunkLines.isEmpty {
            // Build chunk with header repetition for continuation chunks
            var chunkLines: [String] = []
            if chunkNumber > 0, let header = tableHeaderLine {
                chunkLines.append(header)
                if let separator = tableSeparatorLine {
                    chunkLines.append(separator)
                }
            }
            chunkLines.append(contentsOf: currentChunkLines)

            let chunkContent = contextPrefix + (chunkNumber > 0 ? "[Part \(chunkNumber + 1)]\n" : "") + chunkLines.joined(separator: "\n")
            let metadata = ChunkMetadata(
                chunkIndex: baseMetadata.chunkIndex + chunkNumber,
                startPosition: baseMetadata.startPosition,
                endPosition: chunkContent.count,
                pageNumber: baseMetadata.pageNumber,
                sectionTitle: baseMetadata.sectionTitle,
                keywords: extractKeywordsFromStructuredElement(chunkContent, type: element.elementType),
                semanticDensity: baseMetadata.semanticDensity,
                hasNumericData: baseMetadata.hasNumericData,
                hasListStructure: baseMetadata.hasListStructure,
                wordCount: countWords(chunkContent),
                characterCount: chunkContent.count,
                createdAt: baseMetadata.createdAt,
                structureType: baseMetadata.structureType,
                siblingGroupId: baseMetadata.siblingGroupId,
                siblingCount: baseMetadata.siblingCount,
                entities: baseMetadata.entities,
                abbreviations: baseMetadata.abbreviations,
                abstractionLevel: baseMetadata.abstractionLevel,
                sectionPath: baseMetadata.sectionPath,
                bboxArray: baseMetadata.bboxArray,
                documentCategory: baseMetadata.documentCategory,
                chunkType: baseMetadata.chunkType,
                tableTitle: baseMetadata.tableTitle,
                imageContentType: baseMetadata.imageContentType,
                imageCaption: baseMetadata.imageCaption,
                imageDescription: baseMetadata.imageDescription,
                imageExtractedText: baseMetadata.imageExtractedText,
                imageClassifications: baseMetadata.imageClassifications,
                hasCrossReferences: baseMetadata.hasCrossReferences,
                resolvedReferences: baseMetadata.resolvedReferences
            )
            chunks.append(ProcessedChunk(
                text: chunkContent,
                parentText: parentText,
                metadata: metadata,
                structuredTable: chunkNumber == 0 ? structuredTable : nil
            ))
        }

        return chunks
    }

    // MARK: - Token Limit Enforcement (Critical Safety Net)

    /// Maximum embedding tokens per chunk (512 model limit - 2 for CLS/SEP)
    private static let maxEmbeddableTokens = 510

    /// Contextual prefix adds ~50-80 tokens during embedding
    private static let contextualPrefixTokens = 80

    /// Safe token limit for chunks (before contextual prefix is added)
    private static let safeTokenLimit = maxEmbeddableTokens - contextualPrefixTokens  // 430 tokens

    /// Legacy word-based limit (kept for fallback split function)
    /// ~200 words should be safe even for high-tokenization content (200 * 2 = 400 tokens)
    private static let maxEmbeddableWords = 200

    /// Count ACTUAL embedding tokens using Tokenizer
    /// CRITICAL: NLTokenizer "word count" does NOT match BPE/WordPiece tokens!
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    /// Tables with abbreviations/codes can be 2-3x higher than word-based estimates
    private func countTokens(_ text: String) -> Int {
        if let tokenizer = embeddingTokenizer {
            do {
                let ids = try tokenizer.encode(text: text, addSpecialTokens: true)
                return ids.count
            } catch {
                return text.count / 3 + 2
            }
        } else {
            // Fallback: conservative 3 chars/token for technical content
            return text.count / 3 + 2
        }
    }

    /// Count words using NLTokenizer (for logging/stats only, NOT for limit enforcement)
    private func countWords(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    /// Post-processing validation that ensures NO chunk exceeds embedding token limit
    /// Uses ACTUAL BertTokenizer counting, not word estimation
    /// This is critical for technical content with abbreviations, codes, special chars
    private func enforceTokenLimitOnChunks(_ chunks: [ProcessedChunk]) -> [ProcessedChunk] {
        var validatedChunks: [ProcessedChunk] = []
        var splitCount = 0

        for chunk in chunks {
            let tokenCount = countTokens(chunk.text)

            if tokenCount > Self.safeTokenLimit {
                // This chunk WILL cause token truncation - must split it
                let splitChunks = splitOversizedChunkByTokens(chunk)
                validatedChunks.append(contentsOf: splitChunks)
                splitCount += 1

                Log.warning(
                    "[DocumentProcessor] ⚠️ SPLIT OVERSIZED CHUNK: \(tokenCount)t/\(countWords(chunk.text))w → \(splitChunks.count) sub-chunks " +
                    "(section: \(chunk.metadata.sectionTitle ?? "none"), type: \(chunk.metadata.structureType ?? "paragraph"))",
                    category: .ingestion
                )
            } else {
                validatedChunks.append(chunk)
            }
        }

        if splitCount > 0 {
            Log.info(
                "[DocumentProcessor] Token limit enforcement: split \(splitCount) oversized chunks → " +
                "\(chunks.count) → \(validatedChunks.count) total",
                category: .ingestion
            )
        }

        // VERIFICATION: No chunk should exceed limit now
        let stillTooLarge = validatedChunks.filter { countTokens($0.text) > Self.safeTokenLimit }
        if !stillTooLarge.isEmpty {
            Log.error(
                "[DocumentProcessor] ❌ CRITICAL: \(stillTooLarge.count) chunks STILL exceed token limit after split!",
                category: .ingestion
            )
            // Log details of problematic chunks for debugging
            for (idx, chunk) in stillTooLarge.prefix(3).enumerated() {
                Log.error("[DocumentProcessor] Oversized chunk \(idx+1): \(countTokens(chunk.text))t, preview: \(String(chunk.text.prefix(100)))...", category: .ingestion)
            }
        }

        // Always log enforcement stats for visibility
        let maxTokenCount = validatedChunks.map { countTokens($0.text) }.max() ?? 0
        Log.debug(
            "[DocumentProcessor] Token limit enforcement complete: \(chunks.count)→\(validatedChunks.count) chunks, " +
            "split=\(splitCount), maxTokens=\(maxTokenCount)/\(Self.safeTokenLimit)",
            category: .ingestion
        )

        return validatedChunks
    }

    /// Split a single oversized chunk into multiple smaller chunks that fit within token limits
    /// Preserves metadata and adds part markers for context
    private func splitOversizedChunk(_ chunk: ProcessedChunk) -> [ProcessedChunk] {
        var subChunks: [ProcessedChunk] = []
        let text = chunk.text
        let maxWords = Self.maxEmbeddableWords

        // Try to split on sentence boundaries for coherence
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).filter { !$0.isEmpty }

        var currentText = ""
        var currentWordCount = 0
        var partNumber = 0

        for sentence in sentences {
            let sentenceWords = countWords(sentence)

            // If adding this sentence would exceed limit, flush current buffer
            if currentWordCount + sentenceWords > maxWords && !currentText.isEmpty {
                partNumber += 1
                let partText = "[Part \(partNumber)]\n" + currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
                currentText = ""
                currentWordCount = 0
            }

            // Handle case where a single sentence is too large (rare but possible)
            if sentenceWords > maxWords {
                // Force-split at word boundaries
                let words = sentence.split(separator: " ")
                for wordSlice in stride(from: 0, to: words.count, by: maxWords) {
                    let end = min(wordSlice + maxWords, words.count)
                    partNumber += 1
                    let partWords = words[wordSlice..<end].joined(separator: " ")
                    let partText = "[Part \(partNumber)]\n" + partWords
                    subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
                }
            } else {
                currentText += sentence + ". "
                currentWordCount += sentenceWords
            }
        }

        // Flush remaining content
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            partNumber += 1
            let partText = partNumber > 1
                ? "[Part \(partNumber)]\n" + currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                : currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
        }

        // Edge case: if no sub-chunks were created, return original (shouldn't happen)
        if subChunks.isEmpty {
            Log.warning("[DocumentProcessor] Split produced no sub-chunks, returning original", category: .ingestion)
            return [chunk]
        }

        return subChunks
    }

    /// Split a chunk using ACTUAL token counting (not word estimation)
    /// This is critical for technical content with abbreviations, codes, special chars
    private func splitOversizedChunkByTokens(_ chunk: ProcessedChunk) -> [ProcessedChunk] {
        var subChunks: [ProcessedChunk] = []
        let text = chunk.text
        let maxTokens = Self.safeTokenLimit - 10  // Leave margin for part markers

        // Try to split on sentence boundaries for coherence
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).filter { !$0.isEmpty }

        var currentText = ""
        var currentTokens = 0
        var partNumber = 0

        for sentence in sentences {
            let sentenceTokens = countTokens(sentence)

            // If adding this sentence would exceed limit, flush current buffer
            if currentTokens + sentenceTokens > maxTokens && !currentText.isEmpty {
                partNumber += 1
                let partText = "[Part \(partNumber)]\n" + currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
                currentText = ""
                currentTokens = 0
            }

            // Handle case where a single sentence is too large
            if sentenceTokens > maxTokens {
                // Force-split by progressively adding words until token limit reached
                let words = sentence.split(separator: " ").map(String.init)
                var wordBuffer: [String] = []
                var bufferTokens = 0

                for word in words {
                    let wordTokens = countTokens(word)
                    if bufferTokens + wordTokens > maxTokens && !wordBuffer.isEmpty {
                        partNumber += 1
                        let partText = "[Part \(partNumber)]\n" + wordBuffer.joined(separator: " ")
                        subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
                        wordBuffer = []
                        bufferTokens = 0
                    }
                    wordBuffer.append(word)
                    bufferTokens += wordTokens + 1  // +1 for whitespace token
                }

                // Flush remaining words from sentence
                if !wordBuffer.isEmpty {
                    currentText += wordBuffer.joined(separator: " ") + ". "
                    currentTokens += bufferTokens
                }
            } else {
                currentText += sentence + ". "
                currentTokens += sentenceTokens
            }
        }

        // Flush remaining content
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            partNumber += 1
            let partText = partNumber > 1
                ? "[Part \(partNumber)]\n" + currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                : currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
        }

        // Edge case: if no sub-chunks were created, return original
        if subChunks.isEmpty {
            Log.warning("[DocumentProcessor] Token-based split produced no sub-chunks, returning original", category: .ingestion)
            return [chunk]
        }

        // Final validation: ensure all sub-chunks are within limit
        let stillOversized = subChunks.filter { countTokens($0.text) > Self.safeTokenLimit }
        if !stillOversized.isEmpty {
            Log.warning("[DocumentProcessor] \(stillOversized.count) sub-chunks still oversized after token split, will be truncated at embedding", category: .ingestion)
        }

        return subChunks
    }

    /// Create a sub-chunk with inherited metadata from parent
    private func createSubChunk(from parent: ProcessedChunk, text: String, index: Int) -> ProcessedChunk {
        let wordCount = countWords(text)  // Use NLTokenizer for accuracy
        let metadata = ChunkMetadata(
            chunkIndex: parent.metadata.chunkIndex + index,
            startPosition: parent.metadata.startPosition,
            endPosition: parent.metadata.endPosition,
            pageNumber: parent.metadata.pageNumber,
            sectionTitle: parent.metadata.sectionTitle,
            keywords: parent.metadata.keywords,
            semanticDensity: parent.metadata.semanticDensity,
            hasNumericData: parent.metadata.hasNumericData,
            hasListStructure: parent.metadata.hasListStructure,
            wordCount: wordCount,
            characterCount: text.count,
            structureType: parent.metadata.structureType,
            siblingGroupId: parent.metadata.siblingGroupId,
            siblingCount: parent.metadata.siblingCount,
            entities: parent.metadata.entities,
            abbreviations: parent.metadata.abbreviations,
            abstractionLevel: parent.metadata.abstractionLevel,
            sectionPath: parent.metadata.sectionPath,
            bboxArray: parent.metadata.bboxArray,
            documentCategory: parent.metadata.documentCategory,
            chunkType: parent.metadata.chunkType,
            tableTitle: parent.metadata.tableTitle,
            imageContentType: parent.metadata.imageContentType,
            imageCaption: parent.metadata.imageCaption,
            imageDescription: parent.metadata.imageDescription,
            imageExtractedText: parent.metadata.imageExtractedText,
            imageClassifications: parent.metadata.imageClassifications,
            hasCrossReferences: parent.metadata.hasCrossReferences,
            resolvedReferences: parent.metadata.resolvedReferences
        )
        return ProcessedChunk(
            text: text,
            parentText: parent.parentText,
            metadata: metadata,
            structuredTable: index == 0 ? parent.structuredTable : nil
        )
    }

    // MARK: - Content Coverage Verification

    /// Verify that chunking captured all content from the original document
    /// This is a diagnostic check - logs warnings if significant content is missing
    private func verifyContentCoverage(
        original: String,
        chunks: [ProcessedChunk],
        documentId: UUID
    ) {
        // Count words in original (normalize whitespace)
        let originalWords = Set(
            original.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 3 }  // Only count meaningful words
        )

        // Count unique words in all chunks combined
        var chunkWords = Set<String>()
        for chunk in chunks {
            let words = chunk.text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 3 }
            chunkWords.formUnion(words)
        }

        // Calculate coverage
        let covered = originalWords.intersection(chunkWords).count
        let total = originalWords.count
        let coverage = total > 0 ? Double(covered) / Double(total) * 100 : 100

        // Volume, as opposed to vocabulary. Whitespace is excluded from both sides so reflow and
        // re-indentation cannot move the number.
        let originalChars = original.filter { !$0.isWhitespace }.count
        let chunkChars = chunks.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
        // Account for overlap - chunks may duplicate some content
        let charRatio = originalChars > 0 ? Double(chunkChars) / Double(originalChars) * 100 : 100

        // WHY `charRatio` IS CHECKED AND NOT ONLY LOGGED
        //
        // `coverage` above is a set intersection of unique words, and unique vocabulary saturates
        // long before content does. Truncate the back half of a real document and almost every
        // distinct three-letter-or-longer word still appears in the front half, so word coverage
        // stays above 90 and this function stays silent while half the document is gone. Volume is
        // the metric that moves in that case, and until 2026-08-28 it was computed here, formatted
        // into the healthy-path debug line, and compared against nothing at all.
        //
        // Two bounds, because both directions are real failures seen in this project:
        //   - Below 90%: text was dropped between extraction and the finished chunks.
        //   - Above 200%: chunks are duplicating content far beyond what overlap explains. Legitimate
        //     overlap runs roughly 115–125% at the configured word overlap, so 200 leaves wide margin
        //     and still catches the duplicate-import shape that put five files in the library for
        //     three samples.
        let coverageIsLow = coverage < 90
        let volumeIsLow = charRatio < 90
        let volumeIsImplausible = charRatio > 200

        guard coverageIsLow || volumeIsLow || volumeIsImplausible else {
            Log.debug(
                "[DocumentProcessor] ✅ Content coverage: \(String(format: "%.1f", coverage))% words, " +
                "\(String(format: "%.0f", charRatio))% chars (includes overlap)",
                category: .ingestion
            )
            return
        }

        // Both numbers on every warning, whichever bound tripped. A warning that reports only the
        // metric that failed makes the other one unavailable at exactly the moment it is diagnostic:
        // high word coverage beside low volume is the truncation signature specifically, and is a
        // different fault from both being low.
        let readings = "\(String(format: "%.1f", coverage))% of unique words (\(covered)/\(total)), " +
            "\(String(format: "%.0f", charRatio))% of characters"

        if volumeIsLow {
            Log.warning(
                "[DocumentProcessor] ⚠️ CONTENT VOLUME LOST: \(readings). " +
                "Chunks hold \(chunkChars) non-whitespace characters against \(originalChars) extracted. " +
                "High word coverage beside low volume means the document was truncated rather than filtered.",
                category: .ingestion
            )
        }
        if volumeIsImplausible {
            Log.warning(
                "[DocumentProcessor] ⚠️ CONTENT DUPLICATED: \(readings). " +
                "Chunks hold \(chunkChars) non-whitespace characters against \(originalChars) extracted, " +
                "which overlap alone does not explain.",
                category: .ingestion
            )
        }
        if coverageIsLow {
            let missing = originalWords.subtracting(chunkWords)
            let sampleMissing = Array(missing.prefix(10)).joined(separator: ", ")
            Log.warning(
                "[DocumentProcessor] ⚠️ LOW CONTENT COVERAGE: \(readings). " +
                "Missing samples: \(sampleMissing)...",
                category: .ingestion
            )
        }
    }

    /// Extract keywords from structured elements using NLTagger (domain-agnostic)
    /// Leverages Apple's NLP for nouns, technical terms, and alphanumeric patterns
    private func extractKeywordsFromStructuredElement(_ text: String, type: String) -> [String] {
        var keywords: [String] = []

        // Use NLTagger to extract nouns and technical terms (domain-agnostic)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text

        // Extract nouns and proper nouns (key terms in any domain)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag = tag, tag == .noun || tag == .verb {
                let word = String(text[range]).trimmingCharacters(in: .punctuationCharacters)
                if word.count >= 3 {
                    keywords.append(word.lowercased())
                }
            }
            return true
        }

        // Detect alphanumeric codes/identifiers (e.g., "SAE 0W-20", "API-1234", "ISO 9001")
        // These patterns appear in technical specs across ALL domains
        let alphanumericPattern = #"\b[A-Z]{2,}[-\s]?\d+[A-Z\d-]*\b"#
        if let regex = try? NSRegularExpression(pattern: alphanumericPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    keywords.append(String(text[range]).uppercased())
                }
            }
        }

        // Detect measurement patterns (numbers with units - universal across domains)
        let measurementPattern = #"\b\d+(?:\.\d+)?\s*(?:mg|kg|ml|L|mm|cm|m|ft|in|oz|lb|psi|kPa|V|A|W|Hz|°[CF]|%)\b"#
        if let regex = try? NSRegularExpression(pattern: measurementPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    keywords.append(String(text[range]))
                }
            }
        }

        return Array(Set(keywords)).prefix(20).map { $0 }  // Deduplicate, limit to top 20
    }

    /// Extract text from PDF using PDFKit (native iOS framework) - Legacy method
    /// Now with OCR fallback for image-only pages
    private func extractTextFromPDF(url: URL) async throws -> String {
        let pdfDocument = try loadPDF(url: url, context: "PDF")

        let pageCount = pdfDocument.pageCount
        Log.debug("[DocumentProcessor] PDF pages: \(pageCount)", category: .ingestion)

        // Edge case: Empty PDF
        guard pageCount > 0 else {
            Log.warning("[DocumentProcessor] PDF has zero pages", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        var fullText = ""
        var pagesWithoutText = 0
        var ocrUsedCount = 0
        var totalOCRChars = 0

        // Extract text from all pages, with OCR fallback for image-only pages
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageStartTime = Date()

            // Try standard text extraction first
            let pageText = page.string
            let trimmedText = pageText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = trimmedText.map { !$0.isEmpty } ?? false
            let textQualityOK = hasText && isTextQualityAcceptable(pageText ?? "")

            if hasText && textQualityOK {
                progressHandler?("page \(pageIndex + 1)/\(pageCount)")
                await Task.yield()

                fullText += (pageText ?? "") + "\n\n"

                let pageTime = Date().timeIntervalSince(pageStartTime)
                Log.debug("   ✓ Page \(pageIndex + 1): \(pageText?.count ?? 0) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
            } else if hasText && !textQualityOK {
                // Text exists but quality is poor - try OCR instead
                Log.debug("   ⚠️ Page \(pageIndex + 1): Text layer quality poor, trying OCR...", category: .ingestion)
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR (quality)")

                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty,
                   isTextQualityAcceptable(ocrText) {
                    fullText += ocrText + "\n\n"
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count

                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageIndex + 1): OCR replaced garbage text (\(ocrText.count) chars, \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                } else {
                    // OCR didn't help - fall back to original text
                    fullText += (pageText ?? "") + "\n\n"
                    Log.warning("   ⚠️ Page \(pageIndex + 1): Using original text despite quality concerns", category: .ingestion)
                }
            } else {
                // No extractable text - try OCR on the page image
                pagesWithoutText += 1

                // Update progress for OCR
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR")
                await Task.yield()

                // Render page as image and apply OCR
                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty {
                    fullText += ocrText + "\n\n"
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count

                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageIndex + 1): OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                }
            }
        }

        // Report OCR usage
        if ocrUsedCount > 0 {
            Log.debug("[DocumentProcessor] OCR applied to \(ocrUsedCount)/\(pageCount) pages (\(totalOCRChars) chars total)", category: .ingestion)
        }

        if pagesWithoutText > 0 && ocrUsedCount == 0 {
            Log.warning("[DocumentProcessor] \(pagesWithoutText) pages had no extractable text (may be images)", category: .ingestion)
        }

        // Only throw error if NO text was extracted at all
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            if pagesWithoutText == pageCount {
                Log.error("[DocumentProcessor] PDF contains no extractable text (all pages are images)", category: .ingestion)
                Log.info("[DocumentProcessor] Hint: OCR attempted but found no text. Image quality may be too low.", category: .ingestion)
                Log.info("[DocumentProcessor] Suggestion: Try a higher quality scan or text-based PDF", category: .ingestion)
            }
            throw DocumentProcessingError.imageOnlyPDF
        }

        return fullText
    }

    /// Render a PDF page as a high-resolution image for OCR processing
    /// Uses 5x scale (360 DPI) for maximum Vision OCR accuracy
    /// Higher DPI captures fine text, small labels, and low-quality scans better
    /// Apple's Vision framework works best at 150-300+ DPI
    /// GPU-accelerated when DeviceCapabilityService.useGPUForPDFRendering is enabled
    ///
    /// ROTATION HANDLING: PDF pages can have /Rotate flags (90°, 180°, 270°).
    /// We use .cropBox which returns dimensions in the page's display orientation,
    /// and PDFPage.draw() automatically applies the rotation transform.
    private func renderPDFPageAsImage(page: PDFPage, scale: CGFloat = 5.0) -> CIImage? {
        // Use .cropBox instead of .mediaBox — cropBox respects the page's /Rotate flag
        // and returns dimensions in the correct display orientation.
        // For a portrait page rotated 90° to landscape, cropBox gives landscape dimensions.
        let pageBounds = page.bounds(for: .cropBox)

        // Scale up for maximum OCR accuracy - Vision needs high DPI images
        // PDF pages are typically 72 DPI, so 5x = 360 DPI (maximum quality for text recognition)
        // This captures fine print, subscripts, small labels that 216 DPI misses
        let scaledSize = CGSize(
            width: pageBounds.size.width * scale,
            height: pageBounds.size.height * scale
        )

        let pageRotation = page.rotation
        if pageRotation != 0 {
            Log.info("[DocumentProcessor] PDF page has rotation=\(pageRotation)° — using cropBox for correct orientation", category: .ingestion)
        }

        // Per-page render timing. This measurement was missing when a 210-page PDF took five
        // hours on a Mac: the logs gave no way to separate render cost from OCR cost. Pair it
        // with the "Page N: OCR extracted ..." timing the caller already emits to split them.
        let renderStart = CFAbsoluteTimeGetCurrent()

        // The raster is CPU work on BOTH platforms. `useGPUForPDFRendering` selects only the
        // Core Image preprocessing chain attached afterwards, and CIImage is lazy, so no GPU
        // work has actually run by the time this function returns. The old log line claimed
        // "[GPU-accelerated]" at this point, which pointed a real investigation away from the
        // true bottleneck.
        let attachesOCRPostProcess = DeviceCapabilityService.shared.useGPUForPDFRendering

        func logRender(_ backend: String) {
            let ms = (CFAbsoluteTimeGetCurrent() - renderStart) * 1000
            let suffix = attachesOCRPostProcess ? ", post-process attached" : ""
            Log.debug(
                "[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI) in \(String(format: "%.1f", ms))ms via \(backend), CPU raster\(suffix)",
                category: .ingestion
            )
        }

        #if canImport(UIKit)
        // Use opaque format to avoid alpha channel overhead
        // This prevents the "AlphaPremulLast" warning and halves memory usage
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true  // No alpha channel needed - we draw on white background
        format.scale = 1.0    // We've already scaled the size

        let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
        let uiImage = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))

            let ctx = context.cgContext
            ctx.saveGState()

            // Scale up the PDF rendering
            ctx.scaleBy(x: scale, y: scale)

            // Flip Y-axis: UIKit has origin at top-left, PDF at bottom-left
            ctx.translateBy(x: 0, y: pageBounds.size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)

            // PDFPage.draw(with:to:) handles /Rotate internally when using .cropBox
            page.draw(with: .cropBox, to: ctx)

            ctx.restoreGState()
        }

        logRender("UIGraphicsImageRenderer")

        if attachesOCRPostProcess {
            guard let ciImage = CIImage(image: uiImage) else { return nil }

            // Report GPU activity to HUD
            Task { @MainActor in
                HardwareTelemetryState.shared.reportGPUCompute(operation: .imageProcessing)
            }

            // Apply GPU-accelerated preprocessing for better OCR
            return preprocessImageForOCR(ciImage)
        } else {
            return CIImage(image: uiImage)
        }
        #elseif canImport(AppKit)
        // Draw straight into a bitmap we own, at exactly the pixel size we asked for.
        //
        // This replaces NSImage.lockFocus() + tiffRepresentation + NSBitmapImageRep(data:).
        // AppKit/NSImage.h deprecates lockFocus with the reason "This method is incompatible
        // with resolution-independent drawing": it sizes its backing store from the display's
        // scale factor, so on a Retina display it silently allocated 4x the pixels requested.
        // tiffRepresentation then encoded that whole raster to uncompressed TIFF in memory and
        // NSBitmapImageRep(data:) decoded it straight back — a full CPU serialize/deserialize
        // round-trip, per page. At scale 5 a US Letter page is 3060×3960px; under lockFocus at
        // 2x backing scale it was 6120×7920, roughly 194MB, round-tripped 210 times for the
        // document that took five hours.
        //
        // A CGBitmapContext has the same bottom-left origin as the lockFocus context it
        // replaces, so the transform below is unchanged and page orientation is preserved. It
        // also avoids touching NSGraphicsContext.current, which lockFocus mutates and which is
        // process-global state shared with every concurrent Vision operation.
        let pixelWidth = Int(scaledSize.width.rounded())
        let pixelHeight = Int(scaledSize.height.rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let bitmapContext = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,  // let CoreGraphics choose an aligned stride
            space: CGColorSpaceCreateDeviceRGB(),
            // Opaque, matching format.opaque = true on the UIKit side. We draw on white.
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            Log.warning("[DocumentProcessor] Could not create \(pixelWidth)×\(pixelHeight) bitmap context for PDF page render", category: .ingestion)
            return nil
        }

        bitmapContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmapContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        bitmapContext.saveGState()
        bitmapContext.scaleBy(x: scale, y: scale)
        // PDFPage.draw(with:to:) handles /Rotate internally when using .cropBox
        page.draw(with: .cropBox, to: bitmapContext)
        bitmapContext.restoreGState()

        guard let cgImage = bitmapContext.makeImage() else {
            Log.warning("[DocumentProcessor] Bitmap context produced no image for PDF page render", category: .ingestion)
            return nil
        }

        logRender("CGBitmapContext")

        let ciImage = CIImage(cgImage: cgImage)
        if attachesOCRPostProcess {
            return preprocessImageForOCR(ciImage)
        } else {
            return ciImage
        }
        #else
        return nil
        #endif
    }

    // MARK: - Embedded Image Analysis (Visual Understanding)

    /// Analyze embedded images in PDF pages and create searchable chunks
    /// Uses ImageUnderstandingService for classification, OCR, and AI description
    /// Returns StructuredElementWrapper entries for each analyzed image
    @available(iOS 26.0, *)
    private func analyzeEmbeddedImages(pdfDocument: PDFDocument, pageCount: Int) async -> [StructuredElementWrapper] {
        var imageElements: [StructuredElementWrapper] = []

        // MEMORY OPTIMIZATION: Process images in small batches to avoid OOM on large PDFs.
        // Previous batch size of 20 pages accumulated up to ~200MB of CIImages before analysis.
        // With 542 pages of parsed text already in memory, this caused watchdog kills.
        // 5-page batches keep peak image memory under ~50MB.
        let imageBatchSize = 5
        var totalImagesProcessed = 0

        emitProgress(stage: "visual", detail: "🖼 Scanning for embedded images...", page: 0, totalPages: pageCount)

        for batchStart in stride(from: 0, to: pageCount, by: imageBatchSize) {
            let batchEnd = min(batchStart + imageBatchSize, pageCount)

            // Extract images for just this batch of pages
            var batchImages: [(image: CIImage, pageNumber: Int, bounds: CGRect)] = []
            var pageTextObservationsByPage: [Int: [VNRecognizedTextObservation]] = [:]

            for pageIndex in batchStart..<batchEnd {
                guard let page = pdfDocument.page(at: pageIndex) else { continue }
                let pageNumber = pageIndex + 1

                let pageImages = autoreleasepool { extractImagesFromPDFPage(page: page) }
                guard !pageImages.isEmpty else { continue }

                for (image, bounds) in pageImages {
                    batchImages.append((image, pageNumber, bounds))
                }

                pageTextObservationsByPage[pageNumber] = await pageTextObservationsForImageAnalysis(on: page)
            }

            // Skip if no images in this batch
            guard !batchImages.isEmpty else { continue }

            emitProgress(
                stage: "visual",
                detail: "🧠 Analyzing images (pages \(batchStart + 1)-\(batchEnd)/\(pageCount))...",
                page: batchEnd,
                totalPages: pageCount
            )

            let (analyzedImages, _) = await ImageUnderstandingService.shared.analyzeDocumentImages(
                images: batchImages,
                textObservationsByPage: pageTextObservationsByPage
            )

            // Convert analyzed images to StructuredElementWrapper entries immediately
            // This allows the CIImages to be released before the next batch
            for analyzed in analyzedImages {
                if let element = createImageElement(from: analyzed) {
                    imageElements.append(element)
                }
            }

            totalImagesProcessed += batchImages.count

            // CIImages in batchImages released here when scope exits
        }

        // Early exit if no images found
        guard totalImagesProcessed > 0 else {
            Log.debug("[DocumentProcessor] No embedded images found in PDF", category: .ingestion)
            return []
        }

        Log.info("[DocumentProcessor] Analyzed \(totalImagesProcessed) embedded images, created \(imageElements.count) visual content chunks", category: .ingestion)
        return imageElements
    }

    private func pageTextObservationsForImageAnalysis(on page: PDFPage) async -> [VNRecognizedTextObservation] {
        guard let pageImage = renderPDFPageAsImage(page: page, scale: 2.0) else {
            return []
        }

        do {
            return try await performOCRWithObservations(on: pageImage)
        } catch {
            Log.debug("[DocumentProcessor] Could not build page text observations for embedded-image grounding: \(error.localizedDescription)", category: .ingestion)
            return []
        }
    }

    /// Helper to create a StructuredElementWrapper from an analyzed image
    private func createImageElement(from analyzed: AnalyzedImage) -> StructuredElementWrapper? {
        // Build rich description for the image
        var descriptionParts: [String] = []

        // Content type header
        let contentTypeLabel = analyzed.contentType != .unknown ? analyzed.contentType.rawValue.capitalized : "Image"
        descriptionParts.append("[\(contentTypeLabel) on Page \(analyzed.pageNumber)]")

        // Caption is most valuable for search
        if let caption = analyzed.associatedCaption, !caption.isEmpty {
            descriptionParts.append("Caption: \(String(caption.prefix(200)))")
        }

        // Extracted text from within image (critical for diagrams/flowcharts)
        if let extractedText = analyzed.extractedText, !extractedText.isEmpty {
            let cleanedText = extractedText
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            descriptionParts.append("Labels: \(String(cleanedText.prefix(300)))")
        }

        // AI-generated description (if available)
        if let description = analyzed.description, !description.isEmpty {
            // Only add if we don't have extracted text (avoid redundancy)
            if analyzed.extractedText?.isEmpty ?? true {
                descriptionParts.append(String(description.prefix(250)))
            }
        }

        // Skip if we have no useful content
        guard descriptionParts.count > 1 else { return nil }

        let fullDescription = descriptionParts.joined(separator: "\n")

        // Create element wrapper - figures are atomic chunks
        return StructuredElementWrapper(
            text: fullDescription,
            elementType: "figure",
            pageNumber: analyzed.pageNumber,
            isAtomicChunk: true,
            detectedEntities: [],
            imageAnalysis: analyzed
        )
    }

    // MARK: - PDF Image Extraction (Visual Document Understanding)

    /// Extract embedded images from a PDF page for visual understanding
    /// Uses multiple strategies to find images in PDFs:
    /// 1. PDF annotations (explicit image markers)
    /// 2. Full-page scans (pages without extractable text OR garbled text layers)
    /// 3. Pages with minimal text that are mostly visual
    /// 4. Text quality check — garbled font-encoded text layers (Kia, Hyundai PDFs)
    ///    are treated as image-only pages so figures/diagrams get analyzed
    /// Returns array of (image, bounds) tuples where bounds are normalized coordinates
    private func extractImagesFromPDFPage(page: PDFPage) -> [(image: CIImage, bounds: CGRect)] {
        var extractedImages: [(CIImage, CGRect)] = []
        let pageBounds = page.bounds(for: .cropBox)

        // Strategy 1: Look for image annotations (link, stamp, etc. that might contain images)
        for annotation in page.annotations {
            if let bounds = annotation.bounds as CGRect?,
               bounds.width > 100, bounds.height > 100  // Larger threshold for meaningful images
            {
                if let regionImage = renderPDFRegion(page: page, region: bounds) {
                    let normalizedBounds = CGRect(
                        x: bounds.minX / pageBounds.width,
                        y: bounds.minY / pageBounds.height,
                        width: bounds.width / pageBounds.width,
                        height: bounds.height / pageBounds.height
                    )
                    extractedImages.append((regionImage, normalizedBounds))
                }
            }
        }

        // Determine effective text content — garbled font-encoded text layers
        // (common in Asian-publisher PDFs like Kia, Hyundai) are NOT real text.
        // Check actual text quality so we don't skip visual content on pages
        // where the text layer is encrypted/garbled.
        let rawPageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasUsableText: Bool
        if rawPageText.isEmpty {
            hasUsableText = false
        } else if rawPageText.count < 100 {
            hasUsableText = false // Minimal text — likely mostly visual
        } else {
            // Quality check: if text layer is garbled (font encoding issues),
            // treat the page as having no usable text
            hasUsableText = isTextQualityAcceptable(rawPageText)
        }

        // Strategy 2: Page has no usable text — entire page is a visual element
        // This catches: empty pages, scanned images, garbled text layers, diagrams
        if !hasUsableText {
            // Use 2x scale (144 DPI) instead of default 5x (360 DPI) for image understanding.
            // Vision classification and OCR don't need 360 DPI — 144 DPI is sufficient.
            // Each page drops from ~25MB (2100×2975) to ~4MB (840×1190), preventing OOM
            // when multiple pages fail quality checks in the same batch.
            autoreleasepool {
                if let fullPageImage = renderPDFPageAsImage(page: page, scale: 2.0) {
                    let normalizedBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                    extractedImages.append((fullPageImage, normalizedBounds))
                }
            }
        }

        return extractedImages
    }

    /// Render a specific region of a PDF page as an image
    private func renderPDFRegion(page: PDFPage, region: CGRect) -> CIImage? {
        #if canImport(UIKit)
            let scale: CGFloat = 2.0 // 2x for better quality
            let size = CGSize(width: region.width * scale, height: region.height * scale)

            // Use opaque format to avoid alpha channel overhead
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = 1.0

            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let image = renderer.image { context in
                UIColor.white.set()
                context.fill(CGRect(origin: .zero, size: size))

                context.cgContext.scaleBy(x: scale, y: scale)
                context.cgContext.translateBy(x: -region.minX, y: region.maxY - page.bounds(for: .cropBox).height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)

                page.draw(with: .cropBox, to: context.cgContext)
            }
            return CIImage(image: image)
        #else
            return nil
        #endif
    }

    /// Extract images from entire PDF document with page tracking
    func extractAllImagesFromPDF(url: URL) async -> [(image: CIImage, pageNumber: Int, bounds: CGRect)] {
        guard let pdfDocument = try? loadPDF(url: url, context: "Image extraction") else {
            Log.warning("[DocumentProcessor] Cannot extract images: PDF load failed", category: .ingestion)
            return []
        }

        var allImages: [(CIImage, Int, CGRect)] = []

        for pageIndex in 0 ..< pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageImages = extractImagesFromPDFPage(page: page)
            for (image, bounds) in pageImages {
                allImages.append((image, pageIndex + 1, bounds))
            }
        }

        Log.info("[DocumentProcessor] Extracted \(allImages.count) images from PDF", category: .ingestion)
        return allImages
    }

    /// Process a PDF with full visual understanding (text + images)
    /// Returns extracted text with image descriptions interleaved at appropriate positions
    func processDocumentWithVisualUnderstanding(at url: URL) async throws -> (text: String, visualMetadata: VisualContentMetadata) {
        guard url.pathExtension.lowercased() == "pdf" else {
            // Non-PDF documents don't have embedded images in the same way
            return try (await extractTextWithPageInfo(from: url, type: detectDocumentType(url: url)).text, .empty)
        }

        let pdfDocument = try loadPDF(url: url, context: "Visual understanding")

        let startTime = Date()
        var fullText = ""
        var perPageTextObservations: [[VNRecognizedTextObservation]] = []
        var extractedImages: [(image: CIImage, pageNumber: Int, bounds: CGRect)] = []

        // First pass: Extract text with bounding boxes for caption matching
        for pageIndex in 0 ..< pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            let pageNumber = pageIndex + 1

            progressHandler?("analyzing page \(pageNumber)/\(pdfDocument.pageCount)")

            // Get text
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText += pageText + "\n\n"
                perPageTextObservations.append([]) // No OCR observations for native text
            } else if let pageImage = renderPDFPageAsImage(page: page) {
                // OCR with observations for caption matching
                let observations = try await performOCRWithObservations(on: pageImage)
                perPageTextObservations.append(observations)

                let ocrText = extractTextWithColumnAwareness(from: observations)
                fullText += ocrText + "\n\n"
            } else {
                perPageTextObservations.append([])
            }

            // Extract images from this page
            let pageImages = extractImagesFromPDFPage(page: page)
            for (image, bounds) in pageImages {
                extractedImages.append((image, pageNumber, bounds))
            }
        }

        // Second pass: Analyze images with ImageUnderstandingService
        var visualMetadata = VisualContentMetadata.empty

        if !extractedImages.isEmpty {
            progressHandler?("analyzing \(extractedImages.count) images")

            let textObservationsByPage = Dictionary(uniqueKeysWithValues: perPageTextObservations.enumerated().map { ($0.offset + 1, $0.element) })

            let (analyzedImages, metadata) = await ImageUnderstandingService.shared.analyzeDocumentImages(
                images: extractedImages,
                textObservationsByPage: textObservationsByPage
            )

            visualMetadata = metadata

            // Append compact image descriptions to text for embedding
            // Scale the budget based on document size — large manuals have many figures
            // Base: 3000 chars (~2 chunks) for small docs, up to 30000 for large ones
            let maxImageTextPerDoc = min(30000, max(3000, extractedImages.count * 500))
            var totalImageTextAdded = 0

            for analyzed in analyzedImages {
                // Skip if we've hit the budget
                if totalImageTextAdded >= maxImageTextPerDoc { break }

                var imageText = "\n[Figure p.\(analyzed.pageNumber)"
                if analyzed.contentType != .unknown {
                    imageText += " - \(analyzed.contentType.rawValue)"
                }
                imageText += "]"

                // Prioritize: extracted text > caption > description (most useful first)
                var contentParts: [String] = []

                // Extracted text is most valuable (actual labels in diagrams)
                if let extractedText = analyzed.extractedText, !extractedText.isEmpty {
                    let truncated = String(extractedText.prefix(200))
                    contentParts.append(truncated)
                }

                // Caption is next most valuable
                if let caption = analyzed.associatedCaption {
                    let truncated = String(caption.prefix(150))
                    contentParts.append("Caption: \(truncated)")
                }

                // Full description only if we have room and no other content
                if contentParts.isEmpty, let description = analyzed.description {
                    let truncated = String(description.prefix(200))
                    contentParts.append(truncated)
                }

                if !contentParts.isEmpty {
                    imageText += " " + contentParts.joined(separator: ". ")
                }

                // Cap per-image text and track total
                let finalImageText = String(imageText.prefix(400)) + "\n"
                totalImageTextAdded += finalImageText.count
                fullText += finalImageText
            }

            if analyzedImages.count > 0 {
                Log.debug("[DocumentProcessor] Added \(totalImageTextAdded) chars of image descriptions (\(analyzedImages.count) images)", category: .ingestion)
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)
        Log.info("[DocumentProcessor] Visual understanding complete in \(String(format: "%.2f", processingTime))s: \(extractedImages.count) images analyzed", category: .ingestion)

        return (fullText, visualMetadata)
    }

    /// Perform OCR and return raw observations for spatial analysis
    /// Uses same bulletproof configuration as performOCR()
    /// GPU-accelerated via Metal-backed CGImage conversion
    private func performOCRWithObservations(on image: CIImage) async throws -> [VNRecognizedTextObservation] {
        // Report ANE activity to HUD (Vision OCR uses Neural Engine)
        Task { @MainActor in
            HardwareTelemetryState.shared.pulse(.reranking, intensity: 0.8, duration: 0.3)  // Reuse reranking as "Vision OCR" activity
        }

        // Convert CIImage to CGImage using GPU-accelerated context (CIContext is thread-safe)
        let cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        guard let cgImage = cgImageResult else {
            throw NSError(domain: "DocumentProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage for OCR"])
        }

        // Use CGImage directly - Vision will use GPU acceleration for the request
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: observations)
            }

            // === CENTRALIZED OCR CONFIGURATION (via OCRConfiguration factory) ===
            OCRConfiguration.configureRequest(request, customWords: self.currentDocumentCustomWords)

            // Limit concurrent Vision OCR to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Extract text from RTF using native AttributedString
    private func extractTextFromRTF(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]

        var documentAttributes: NSDictionary?
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: &documentAttributes
        ) else {
            throw DocumentProcessingError.rtfParseFailed
        }
        return attributedString.string
    }

    /// Extract text from images using Vision framework OCR + Visual Understanding
    /// Enhanced for standalone image files: includes classification, AI description, and OCR
    private func extractTextFromImage(url: URL) async throws -> String {
        progressHandler?("Analyzing image")
        await Task.yield()

        let startTime = Date()

        guard let image = CIImage(contentsOf: url) else {
            Log.error("[DocumentProcessor] Failed to load image: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.imageLoadFailed
        }

        let imageSize = image.extent.size
        Log.debug("[DocumentProcessor] Original image: \(Int(imageSize.width))×\(Int(imageSize.height))px", category: .ingestion)

        // Use ImageUnderstandingService for comprehensive analysis
        // This provides: classification, OCR, and AI description (iOS 26+)
        progressHandler?("Understanding image content")
        let analysis = await ImageUnderstandingService.shared.analyzeStandaloneImage(image)

        let analysisTime = Date().timeIntervalSince(startTime)
        Log.debug("[DocumentProcessor] 🖼️ Image analysis complete in \(String(format: "%.2f", analysisTime))s", category: .ingestion)
        Log.debug("[DocumentProcessor] - Type: \(analysis.contentType.rawValue)", category: .ingestion)
        Log.debug("[DocumentProcessor] - Classifications: \(analysis.classifications.count)", category: .ingestion)
        Log.debug("[DocumentProcessor] - OCR: \(analysis.extractedText?.count ?? 0) chars", category: .ingestion)
        Log.debug("[DocumentProcessor] - AI description: \(analysis.aiDescription != nil ? "yes" : "no")", category: .ingestion)

        // Prefer Vision's document understanding when the image is a document.
        //
        // `RecognizeDocumentsRequest` returns cell-level table structure; the OCR inside
        // `analyzeStandaloneImage` uses `VNRecognizeTextRequest`, which returns text lines in
        // reading order and cannot express that a value belongs to a row and a column. Until now
        // this path was the only one that never got the structured parser, so the same table gave
        // cell structure inside a PDF and flat lines when photographed or screenshotted — same
        // content, opposite quality, with nothing in the UI to explain the difference.
        //
        // The classification and AI description from `analyzeStandaloneImage` are still worth
        // keeping, so the structured text is prepended to them rather than replacing them. Any
        // failure falls straight back to the previous behaviour: this can add structure, never
        // remove it.
        if let structured = try? await StructuredDocumentParser.shared.parsePageImage(
            image,
            pageNumber: 1,
            customWords: []
        ) {
            let structuredText = structured.effectiveContent
                .map(StructuredPageContent.plainText(of:))
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")

            if !structuredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Log.debug(
                    "[DocumentProcessor] - Structured parse: \(structured.elements.count) element(s), "
                        + "\(structuredText.count) chars (quality \(String(format: "%.2f", structured.qualityScore)))",
                    category: .ingestion
                )
                return structuredText + "\n\n" + analysis.structuredText
            }
        }

        // Return the structured text which includes all visual understanding
        return analysis.structuredText
    }

    /// Upscale an image for better OCR quality using Lanczos interpolation
    private func upscaleImageForOCR(_ image: CIImage, factor: CGFloat) -> CIImage {
        let transform = CGAffineTransform(scaleX: factor, y: factor)
        return image.transformed(by: transform)
    }

    /// Enhance image contrast and sharpness for better OCR
    /// Particularly helpful for scanned documents and low-quality images
    private func enhanceImageForOCR(_ image: CIImage) -> CIImage {
        var enhanced = image

        // Sharpen slightly to improve text edge detection
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(enhanced, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)  // Subtle sharpening
            if let output = sharpenFilter.outputImage {
                enhanced = output
            }
        }

        // Enhance contrast for better text/background separation
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(enhanced, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.05, forKey: kCIInputContrastKey)  // Subtle contrast boost
            if let output = contrastFilter.outputImage {
                enhanced = output
            }
        }

        return enhanced
    }

    /// Perform OCR on an image using Vision framework with layout-aware text ordering
    /// Configured for maximum accuracy with Apple's latest Vision capabilities
    /// GPU-accelerated via Metal-backed CGImage conversion
    private func performOCR(on image: CIImage) async throws -> String {
        // ATTEMPT 1: Standard OCR on the original image
        let result = try await performOCRSingleAttempt(on: image)

        // If we got meaningful text, return it
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result
        }

        // RETRY WITH ESCALATING PREPROCESSING STRATEGIES
        // If original image produced nothing, the page may be low-quality scan/photo
        Log.info("[DocumentProcessor] OCR empty on raw image — retrying with preprocessing", category: .ingestion)

        // Try progressively more aggressive strategies (skip minimal, start from standard)
        let retryStrategies = Array(AdaptivePreprocessor.strategies.dropFirst()) // standard → maximum
        var bestResult = ""

        for strategy in retryStrategies {
            let preprocessed = AdaptivePreprocessor.apply(
                strategy,
                to: image,
                gpuContext: Self.gpuContext,
                gpuQueue: Self.gpuQueue
            )

            let retryText = try await performOCRSingleAttempt(on: preprocessed)
            let wordCount = retryText.split(separator: " ").count

            if wordCount > bestResult.split(separator: " ").count {
                bestResult = retryText
                Log.debug("[DocumentProcessor] OCR retry '\(strategy.name)': \(wordCount) words", category: .ingestion)
            }

            // Good enough — stop escalating
            if wordCount >= 10 {
                Log.info("[DocumentProcessor] OCR retry '\(strategy.name)' succeeded: \(wordCount) words", category: .ingestion)
                return bestResult
            }
        }

        if !bestResult.isEmpty {
            Log.info("[DocumentProcessor] OCR retry recovered \(bestResult.split(separator: " ").count) words after escalation", category: .ingestion)
        }
        return bestResult
    }

    /// Perform a single OCR attempt on an image (no retry logic)
    private func performOCRSingleAttempt(on image: CIImage) async throws -> String {
        // Convert CIImage to CGImage using GPU-accelerated context (CIContext is thread-safe)
        let cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        guard let cgImage = cgImageResult else {
            Log.error("[DocumentProcessor] Failed to create CGImage for OCR", category: .ingestion)
            return ""
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    Log.error("[DocumentProcessor] OCR failed: \(error.localizedDescription)", category: .ingestion)
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    Log.warning("[DocumentProcessor] OCR returned no results", category: .ingestion)
                    continuation.resume(returning: "")
                    return
                }

                Log.debug("[DocumentProcessor] OCR found \(observations.count) text blocks", category: .ingestion)

                // VISUAL DOCUMENT UNDERSTANDING: Sort observations by reading order
                // Vision uses normalized coordinates where (0,0) is bottom-left
                // Sort by Y descending (top to bottom), then X ascending (left to right)
                let sortedObservations = observations.sorted { obs1, obs2 in
                    let box1 = obs1.boundingBox
                    let box2 = obs2.boundingBox

                    // Use a threshold to detect "same line" (within 2% of image height)
                    let lineThreshold: CGFloat = 0.02
                    let y1 = box1.midY
                    let y2 = box2.midY

                    // If on different lines, sort top-to-bottom (higher Y = higher on page in Vision coords)
                    if abs(y1 - y2) > lineThreshold {
                        return y1 > y2 // Higher Y value means higher on the page
                    }

                    // Same line: sort left-to-right
                    return box1.minX < box2.minX
                }

                // Detect potential columns by analyzing X-position clusters
                let columnText = self.extractTextWithColumnAwareness(from: sortedObservations)

                continuation.resume(returning: columnText)
            }

            // === CENTRALIZED OCR CONFIGURATION (via OCRConfiguration factory) ===
            OCRConfiguration.configureRequest(request, customWords: self.currentDocumentCustomWords)

            // Limit concurrent Vision OCR to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([request])
                } catch {
                    Log.error("[DocumentProcessor] OCR request failed: \(error.localizedDescription)", category: .ingestion)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Enhanced Spatial OCR (Full Document Understanding)

    /// Perform OCR with full spatial analysis - extracts hierarchy, layout, figures, and captions
    /// Returns enriched text with markdown-style headers and figure annotations
    private func performEnhancedSpatialOCR(on image: CIImage, pageNumber: Int) async throws -> (text: String, analysis: SpatialPageAnalysis?) {
        let observations = try await performOCRWithObservationsAsync(on: image)

        guard !observations.isEmpty else {
            return ("", nil)
        }

        // Perform full spatial analysis
        let analyzer = SpatialDocumentAnalyzer.shared
        let analysis = await analyzer.analyze(
            observations: observations,
            pageNumber: pageNumber,
            pageSize: CGSize(width: image.extent.width, height: image.extent.height)
        )

        // Generate enriched text with hierarchy and figure info
        let enrichedText = await analyzer.generateEnrichedText(from: analysis)

        Log.info("[DocumentProcessor] Enhanced OCR page \(pageNumber): \(analysis.hierarchy.count) headers, \(analysis.layout.columnCount) columns, \(analysis.figures.count) figures", category: .ingestion)

        return (enrichedText, analysis)
    }

    /// Async wrapper for observation-based OCR
    /// GPU-accelerated via Metal-backed CGImage conversion
    private func performOCRWithObservationsAsync(on image: CIImage) async throws -> [VNRecognizedTextObservation] {
        // Convert CIImage to CGImage using GPU-accelerated context (CIContext is thread-safe)
        let cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        guard let cgImage = cgImageResult else {
            throw NSError(domain: "DocumentProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage for OCR"])
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: observations)
            }

            // === CENTRALIZED OCR CONFIGURATION (via OCRConfiguration factory) ===
            OCRConfiguration.configureRequest(request, customWords: self.currentDocumentCustomWords)

            // Limit concurrent Vision OCR to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Spatial Text Extraction (Column-Aware PDFKit)

    /// Represents a text line with its spatial position for column detection
    private struct SpatialLine {
        let text: String
        let xPosition: CGFloat  // X center of the line
        let yPosition: CGFloat  // Y position (for sorting)
        let bounds: CGRect
    }

    /// Extract text from a PDF page using spatial ordering to handle multi-column layouts
    /// This is the key 10x improvement: PDFKit's default extraction often mixes columns
    /// By using character/line bounding boxes, we can detect columns and read correctly
    /// Why a word begins a new spatial line, or that it does not.
    enum SpatialLineBreak: Equatable {
        case none
        /// The word sits on a different row.
        case verticalGap
        /// The word sits on the same row but across a horizontal discontinuity — in a
        /// multi-column page, the gutter.
        case horizontalGap
    }

    /// Decides whether `wordBounds` continues the line built so far or starts a new one.
    ///
    /// `nonisolated static` and taking only geometry so the decision is testable without a
    /// `PDFPage`. That matters here: this is the whole two-column defect, and until now the only
    /// way to exercise it was to ingest a real journal PDF on a device.
    ///
    /// **A vertical test alone cannot see a column gutter.** `page.string` on a two-column PDF
    /// emits words row by row across the gutter, so a left-column word and a right-column word at
    /// the same height arrive adjacent and at the same Y. Grouped on Y alone they become one
    /// `SpatialLine`, and that line's `xPosition` is the *mean* of both columns, landing near the
    /// page centre.
    ///
    /// Everything downstream then fails for a reason it cannot detect. `detectColumnBoundaries`
    /// looks for a gap wider than 10% of the page across those means; once every line sits at the
    /// centre there is no gap, so it returns empty, the single-column branch sorts by Y, and the
    /// columns come out interleaved. The function returns non-nil, so no caller can tell.
    ///
    /// The column signal is destroyed here, before the code that looks for it ever runs. That is
    /// why neither the earlier tie-break fix nor a smarter `detectColumnBoundaries` could have
    /// addressed this, and why that entry carries `symptom_attribution_still_open`.
    ///
    /// Observed on device 2026-08-24: a stored chunk read "…in locomotors are more diverse,
    /// consisting of Gi-coupled 5-HT, and 5-HTS. tion, reinforcement learning…" — two columns
    /// welded line for line, with "locomotion" severed across the splice.
    nonisolated static func spatialLineBreak(
        wordBounds: CGRect,
        currentLineBounds: CGRect,
        currentLineY: CGFloat
    ) -> SpatialLineBreak {
        // No line started yet.
        guard currentLineY >= 0 else { return .none }

        let yThreshold = wordBounds.height * 0.5
        if abs(wordBounds.midY - currentLineY) > yThreshold { return .verticalGap }

        guard !currentLineBounds.isEmpty else { return .none }

        // Reading order runs left to right within a line, so a move back to or past the line's own
        // left edge starts a new line whose Y moved by less than the threshold.
        if wordBounds.minX < currentLineBounds.minX { return .horizontalGap }

        // A forward jump far wider than an inter-word space is a gutter. Word spacing is a fraction
        // of the glyph height and a gutter is a multiple of it, so scaling by height keeps this
        // correct at any page size. The floor covers very small type.
        let gutterThreshold = max(wordBounds.height * 1.5, 8)
        if wordBounds.minX - currentLineBounds.maxX > gutterThreshold { return .horizontalGap }

        return .none
    }

    private func extractTextWithSpatialOrdering(from page: PDFPage) -> String? {
        // Get all selections for lines on this page
        // We'll enumerate through the page character by character to find line boundaries
        guard let pageString = page.string, !pageString.isEmpty else { return nil }

        // Use word-level selection to build spatial lines
        var spatialLines: [SpatialLine] = []
        var currentLineText = ""
        var currentLineY: CGFloat = -1
        var currentLineBounds: CGRect = .zero
        var lineXPositions: [CGFloat] = []

        // Enumerate words and group into lines based on Y position.
        //
        // The range handed to `page.selection(for:)` is taken from the Substring itself rather than
        // from a hand-maintained counter. The counter version under-counted twice over and the two
        // errors compounded: `split(whereSeparator:)` omits empty subsequences, so every run of
        // whitespace collapsed to one gap while the cursor advanced by exactly `+ 1` per gap; and
        // `String.count` counts grapheme clusters while `NSRange` addresses UTF-16 code units, so
        // every ligature drifted it further. Both under-count in the same direction, which is why
        // the range stayed valid and `selection(for:)` kept returning bounds — for the wrong text.
        // The word appended was correct and the coordinates recorded against it were not.
        //
        // `Substring` indices are indices into the base string, so `word.startIndex..<word.endIndex`
        // is already the true range. `in: pageString` is load-bearing: `in: word` would produce
        // word-relative offsets and reintroduce the same defect in a new shape.
        let words = pageString.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var unresolvedWords = 0
        // Counted so a trace can distinguish a genuinely single-column page from a two-column page
        // whose gutter was never seen. Those two produced identical output and identical logs until
        // now, which is what made this defect diagnosable only by inference.
        var columnBreaks = 0

        for word in words {
            let wordString = String(word)

            // Try to find this word in the page and get its bounds
            if let selection = page.selection(for: NSRange(word.startIndex..<word.endIndex, in: pageString)),
               let firstChar = selection.selectionsByLine().first {

                let bounds = firstChar.bounds(for: page)

                let lineBreak = Self.spatialLineBreak(
                    wordBounds: bounds,
                    currentLineBounds: currentLineBounds,
                    currentLineY: currentLineY
                )
                if lineBreak == .horizontalGap { columnBreaks += 1 }
                let isNewLine = lineBreak != .none

                if isNewLine && !currentLineText.isEmpty {
                    // Save the previous line
                    let avgX = lineXPositions.isEmpty ? 0 : lineXPositions.reduce(0, +) / CGFloat(lineXPositions.count)
                    spatialLines.append(SpatialLine(
                        text: currentLineText.trimmingCharacters(in: .whitespaces),
                        xPosition: avgX,
                        yPosition: currentLineY,
                        bounds: currentLineBounds
                    ))
                    currentLineText = ""
                    lineXPositions = []
                    currentLineBounds = .zero
                }

                // Add word to current line
                currentLineText += (currentLineText.isEmpty ? "" : " ") + wordString
                currentLineY = bounds.midY
                lineXPositions.append(bounds.midX)
                currentLineBounds = currentLineBounds.isEmpty ? bounds : currentLineBounds.union(bounds)
            } else {
                // A word PDFKit cannot place. Counted rather than ignored: a page where many words
                // fail to resolve produces sparse, unreliable `spatialLines`, and until this was
                // logged there was no way to tell that from a page that simply has little text.
                unresolvedWords += 1
            }
        }

        // Don't forget the last line
        if !currentLineText.isEmpty {
            let avgX = lineXPositions.isEmpty ? 0 : lineXPositions.reduce(0, +) / CGFloat(lineXPositions.count)
            spatialLines.append(SpatialLine(
                text: currentLineText.trimmingCharacters(in: .whitespaces),
                xPosition: avgX,
                yPosition: currentLineY,
                bounds: currentLineBounds
            ))
        }

        // If we couldn't get spatial info, fall back to simple extraction.
        //
        // Returning nil sends the caller to raw `page.string`, which interleaves columns by
        // construction. That is a real quality cliff and it used to be silent — there was no way to
        // distinguish a nil return here from a success, because the call site reads
        // `extractTextWithSpatialOrdering(from: page) ?? text`.
        guard spatialLines.count > 3 else {
            Log.warning(
                "[DocumentProcessor] Spatial extraction bailed: only \(spatialLines.count) line(s) "
                    + "resolved from \(words.count) word(s), \(unresolvedWords) unplaceable. "
                    + "Falling back to raw page text, which does NOT preserve column order.",
                category: .ingestion
            )
            return nil
        }

        if unresolvedWords > 0 {
            Log.debug(
                "[DocumentProcessor] Spatial extraction: \(unresolvedWords) of \(words.count) "
                    + "word(s) could not be placed on the page",
                category: .ingestion
            )
        }

        if columnBreaks > 0 {
            Log.info(
                "[DocumentProcessor] Spatial extraction split \(columnBreaks) line(s) on a horizontal "
                    + "gap; this page's words arrive across a gutter rather than in reading order",
                category: .ingestion
            )
        }

        // Detect columns from X positions
        let xPositions = spatialLines.map { $0.xPosition }
        let pageWidth = page.bounds(for: .cropBox).width
        let columnBoundaries = detectColumnBoundaries(from: xPositions, pageWidth: pageWidth)

        if columnBoundaries.isEmpty {
            // Treated as a single column and sorted by Y alone.
            //
            // This branch is reached both by genuinely single-column pages and by multi-column pages
            // whose boundaries could not be detected, and the two are indistinguishable from here.
            // In the second case a Y-only sort interleaves the columns, because a line on the left
            // and a line on the right at the same height sort adjacent — which is exactly the
            // damage reported against two-column journal PDFs. It then returns non-nil, so nothing
            // downstream can tell. Logged rather than silently returned.
            //
            // The tiebreak on X is not cosmetic. `sorted(by:)` is not stable in Swift, so equal-Y
            // lines previously came out in arbitrary order — the same page could extract
            // differently on two runs. Ordering ties left-to-right makes the output deterministic
            // and, on an undetected two-column page, at least reading-order-correct per row.
            let sorted = spatialLines.sorted {
                $0.yPosition == $1.yPosition ? $0.xPosition < $1.xPosition : $0.yPosition > $1.yPosition
            }
            Log.debug(
                "[DocumentProcessor] Spatial extraction found no column boundaries across "
                    + "\(spatialLines.count) line(s); reading as a single column",
                category: .ingestion
            )
            return sorted.map { $0.text }.joined(separator: "\n")
        }

        // Multi-column: group lines by column, then sort each column top-to-bottom
        Log.debug("[DocumentProcessor] Spatial extraction detected \(columnBoundaries.count + 1) columns", category: .ingestion)

        var columnGroups: [[SpatialLine]] = Array(repeating: [], count: columnBoundaries.count + 1)

        for line in spatialLines {
            // Find which column this line belongs to
            var columnIndex = 0
            for (i, boundary) in columnBoundaries.enumerated() {
                if line.xPosition > boundary {
                    columnIndex = i + 1
                }
            }
            columnGroups[columnIndex].append(line)
        }

        // Process each column top-to-bottom (higher Y = higher on page in PDF coords)
        var result: [String] = []
        for (colIdx, group) in columnGroups.enumerated() {
            // Same non-stable-sort hazard as the single-column branch above.
            let sortedColumn = group.sorted {
                $0.yPosition == $1.yPosition ? $0.xPosition < $1.xPosition : $0.yPosition > $1.yPosition
            }
            let columnText = sortedColumn.map { $0.text }
            if !columnText.isEmpty {
                result.append(contentsOf: columnText)
                // Add paragraph break between columns
                if colIdx < columnGroups.count - 1 {
                    result.append("")
                }
            }
        }

        return result.joined(separator: "\n")
    }

    /// Detect column boundaries from a list of X positions
    /// Returns X coordinates that separate columns (empty = single column)
    private func detectColumnBoundaries(from xPositions: [CGFloat], pageWidth: CGFloat) -> [CGFloat] {
        guard xPositions.count > 5 else { return [] }

        let sorted = xPositions.sorted()

        // Find gaps between clusters of X positions
        var gaps: [(position: CGFloat, gapSize: CGFloat)] = []

        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i-1]
            // Normalize gap size relative to page width
            let normalizedGap = gap / pageWidth
            if normalizedGap > 0.1 { // Gap > 10% of page width
                gaps.append((position: (sorted[i] + sorted[i-1]) / 2, gapSize: gap))
            }
        }

        // Return boundary positions (sorted)
        return gaps.sorted { $0.gapSize > $1.gapSize }  // Largest gaps first
            .prefix(2)  // Max 3 columns
            .map { $0.position }
            .sorted()
    }

    // MARK: - Layout-Aware Text Extraction (OCR)

    private struct OCRReadingBlock {
        let text: String
        let topY: CGFloat
        let minX: CGFloat
    }

    /// Extract text with awareness of tables and multi-column layouts.
    /// Rebuilds table-heavy OCR pages row-by-row and otherwise reads columns top-to-bottom.
    private func extractTextWithColumnAwareness(from observations: [VNRecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        if let tableText = extractTableDominantText(from: observations) {
            return tableText
        }

        // Collect X midpoints to detect columns
        let xMidpoints = observations.map { $0.boundingBox.midX }
        let columns = detectColumns(from: xMidpoints)

        // If single column or can't detect columns, use simple reading order
        guard columns.count > 1 else {
            Log.debug("[DocumentProcessor] Single column layout detected", category: .ingestion)
            let result = ConfidenceVerifier.assembleVerifiedText(from: observations)
            if result.uncertainCount > 0 {
                Log.debug("[DocumentProcessor] ⚠️ \(result.uncertainCount) uncertain observations (avg confidence: \(String(format: "%.1f%%", result.avgConfidence * 100)))", category: .ingestion)
            }
            return result.text
        }

        Log.debug("[DocumentProcessor] Multi-column layout detected: \(columns.count) columns", category: .ingestion)

        // Group observations by column
        var columnGroups: [[VNRecognizedTextObservation]] = Array(repeating: [], count: columns.count)

        for observation in observations {
            let xMid = observation.boundingBox.midX
            // Find which column this observation belongs to
            var closestColumn = 0
            var minDistance = CGFloat.greatestFiniteMagnitude

            for (index, columnCenter) in columns.enumerated() {
                let distance = abs(xMid - columnCenter)
                if distance < minDistance {
                    minDistance = distance
                    closestColumn = index
                }
            }

            columnGroups[closestColumn].append(observation)
        }

        // Sort each column top-to-bottom and extract text with confidence verification
        var allText: [String] = []
        for (index, group) in columnGroups.enumerated() {
            let sortedGroup = group.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let result = ConfidenceVerifier.assembleVerifiedText(from: sortedGroup)

            if !result.text.isEmpty {
                let lines = result.text.components(separatedBy: "\n")
                Log.debug("[DocumentProcessor] Column \(index + 1): \(lines.count) text blocks", category: .ingestion)
                allText.append(contentsOf: lines)
                allText.append("") // Paragraph break between columns
            }
        }

        return allText.joined(separator: "\n")
    }

    /// Rebuild table-heavy OCR pages in row order instead of dumping full columns sequentially.
    private func extractTableDominantText(from observations: [VNRecognizedTextObservation]) -> String? {
        let (tables, remaining) = detectTables(from: observations)
        guard shouldPreferDetectedTables(
            tables,
            remaining: remaining,
            totalObservationCount: observations.count
        ) else {
            return nil
        }

        var blocks = tables.compactMap { table -> OCRReadingBlock? in
            let text = table.toText().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRReadingBlock(
                text: text,
                topY: table.boundingBox.maxY,
                minX: table.boundingBox.minX
            )
        }
        blocks.append(contentsOf: buildOCRReadingBlocks(from: remaining))

        let orderedBlocks = blocks.sorted { lhs, rhs in
            if abs(lhs.topY - rhs.topY) > 0.02 {
                return lhs.topY > rhs.topY
            }
            return lhs.minX < rhs.minX
        }

        guard !orderedBlocks.isEmpty else { return nil }

        Log.info(
            "[DocumentProcessor] Table-aware OCR reconstruction: \(tables.count) tables, \(remaining.count) residual observations",
            category: .ingestion
        )
        return orderedBlocks.map(\.text).joined(separator: "\n")
    }

    private func shouldPreferDetectedTables(
        _ tables: [DetectedTable],
        remaining: [VNRecognizedTextObservation],
        totalObservationCount: Int
    ) -> Bool {
        guard !tables.isEmpty else { return false }

        let cellTexts = tables
            .flatMap(\.rows)
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cellTexts.isEmpty else { return false }

        let maxColumns = tables
            .compactMap { table in
                table.rows.map(\.count).max()
            }
            .max() ?? 0
        let headerCells = tables.first?.rows.first?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let headerLikeFirstRow = !headerCells.isEmpty && headerCells.allSatisfy {
            isShortOCRCell($0) && $0.rangeOfCharacter(from: .decimalDigits) == nil
        }

        let numericCellRatio = Double(cellTexts.filter {
            $0.rangeOfCharacter(from: .decimalDigits) != nil
        }.count) / Double(cellTexts.count)
        let shortCellRatio = Double(cellTexts.filter(isShortOCRCell).count) / Double(cellTexts.count)
        let narrativeCellRatio = Double(cellTexts.filter(isNarrativeOCRCell).count) / Double(cellTexts.count)
        let tableCoverage = Double(totalObservationCount - remaining.count) / Double(max(1, totalObservationCount))

        let looksNarrativeColumns = maxColumns == 2
            && numericCellRatio < 0.15
            && narrativeCellRatio >= 0.5
            && !headerLikeFirstRow
        let looksTabular = maxColumns >= 3
            || numericCellRatio >= 0.2
            || headerLikeFirstRow
            || (shortCellRatio >= 0.7 && narrativeCellRatio <= 0.35)

        let shouldUseTablePath = looksTabular
            && !looksNarrativeColumns
            && (tableCoverage >= 0.55 || remaining.count <= 6)

        if !shouldUseTablePath {
            Log.debug(
                "[DocumentProcessor] Table candidates resemble narrative columns; keeping column reading order",
                category: .ingestion
            )
        }

        return shouldUseTablePath
    }

    private func buildOCRReadingBlocks(from observations: [VNRecognizedTextObservation]) -> [OCRReadingBlock] {
        guard !observations.isEmpty else { return [] }

        let lineThreshold: CGFloat = 0.02
        let sorted = observations.sorted { lhs, rhs in
            let leftY = lhs.boundingBox.midY
            let rightY = rhs.boundingBox.midY

            if abs(leftY - rightY) > lineThreshold {
                return leftY > rightY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var blocks: [OCRReadingBlock] = []
        var currentLine: [VNRecognizedTextObservation] = []
        var currentY: CGFloat?

        func flushCurrentLine() {
            guard !currentLine.isEmpty else { return }

            let orderedLine = currentLine.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let result = ConfidenceVerifier.assembleVerifiedText(from: orderedLine)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                blocks.append(OCRReadingBlock(
                    text: text,
                    topY: orderedLine.map { $0.boundingBox.maxY }.max() ?? 0,
                    minX: orderedLine.map { $0.boundingBox.minX }.min() ?? 0
                ))
            }

            currentLine.removeAll(keepingCapacity: true)
        }

        for observation in sorted {
            let y = observation.boundingBox.midY

            if let previousY = currentY, abs(y - previousY) >= lineThreshold {
                flushCurrentLine()
            }

            currentLine.append(observation)
            currentY = y
        }

        flushCurrentLine()
        return blocks
    }

    private func isShortOCRCell(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 4 && text.count <= 36
    }

    private func isNarrativeOCRCell(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let punctuationCount = text.unicodeScalars.filter {
            CharacterSet(charactersIn: ".,;:!?").contains($0)
        }.count
        return wordCount >= 8 || punctuationCount >= 2
    }

    /// Detect column boundaries using X-position clustering
    /// Returns array of column center X positions
    private func detectColumns(from xMidpoints: [CGFloat]) -> [CGFloat] {
        guard xMidpoints.count > 3 else { return [] }

        // Simple clustering: find gaps in X positions
        let sorted = xMidpoints.sorted()
        var gaps: [(position: CGFloat, gap: CGFloat)] = []

        for i in 1 ..< sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            gaps.append((position: (sorted[i] + sorted[i - 1]) / 2, gap: gap))
        }

        // Find significant gaps (> 15% of page width suggests column boundary)
        let significantGapThreshold: CGFloat = 0.15
        let columnBoundaries = gaps.filter { $0.gap > significantGapThreshold }.map { $0.position }

        if columnBoundaries.isEmpty {
            // Single column
            return [sorted.reduce(0, +) / CGFloat(sorted.count)]
        }

        // Calculate column centers
        var centers: [CGFloat] = []
        var prevBoundary: CGFloat = 0

        for boundary in columnBoundaries.sorted() {
            centers.append((prevBoundary + boundary) / 2)
            prevBoundary = boundary
        }
        centers.append((prevBoundary + 1.0) / 2) // Last column extends to right edge

        return centers
    }

    // MARK: - Table Detection

    /// Detected table structure from OCR observations
    struct DetectedTable: Sendable {
        let rows: [[String]]
        let boundingBox: CGRect
        let confidence: Float

        /// Convert table to readable text format
        func toText() -> String {
            guard !rows.isEmpty else { return "" }

            var output = "[Table]\n"

            // Header row
            if let header = rows.first {
                output += "| " + header.joined(separator: " | ") + " |\n"
                output += "|" + header.map { _ in "---" }.joined(separator: "|") + "|\n"
            }

            // Data rows
            for row in rows.dropFirst() {
                output += "| " + row.joined(separator: " | ") + " |\n"
            }

            output += "[/Table]\n"
            return output
        }
    }

    /// Detect tables in OCR observations using grid alignment analysis
    /// Returns detected tables and remaining non-table observations
    func detectTables(from observations: [VNRecognizedTextObservation]) -> (tables: [DetectedTable], remaining: [VNRecognizedTextObservation]) {
        guard observations.count >= 4 else {
            return ([], observations)
        }

        // Group observations by Y position (rows)
        let lineThreshold: CGFloat = 0.02 // 2% of page height = same row
        var rows: [[VNRecognizedTextObservation]] = []
        var currentRow: [VNRecognizedTextObservation] = []
        var lastY: CGFloat = -1

        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        for obs in sorted {
            let y = obs.boundingBox.midY
            if lastY < 0 || abs(y - lastY) < lineThreshold {
                currentRow.append(obs)
            } else {
                if !currentRow.isEmpty {
                    rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
                }
                currentRow = [obs]
            }
            lastY = y
        }
        if !currentRow.isEmpty {
            rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
        }

        // Detect table regions: multiple rows with consistent column count
        var tables: [DetectedTable] = []
        var tableObservations: Set<UUID> = []
        var i = 0

        while i < rows.count {
            let columnCount = rows[i].count

            // Need at least 2 columns and 2 rows for a table
            if columnCount >= 2 {
                var tableRows: [[VNRecognizedTextObservation]] = [rows[i]]
                var j = i + 1

                // Find consecutive rows with similar column count (±1)
                while j < rows.count {
                    let nextColCount = rows[j].count
                    if abs(nextColCount - columnCount) <= 1, nextColCount >= 2 {
                        tableRows.append(rows[j])
                        j += 1
                    } else {
                        break
                    }
                }

                // If we found 2+ rows with consistent columns, it's likely a table
                if tableRows.count >= 2 {
                    // Check X-alignment consistency (column structure)
                    if hasConsistentColumnAlignment(tableRows) {
                        // CRITICAL: Use confidence-verified text for table cells
                        // Tables contain numeric data where OCR errors cause wrong answers
                        let textRows = tableRows.map { row in
                            row.compactMap { cell -> String? in
                                let analysis = ConfidenceVerifier.analyze(cell)
                                if analysis.isUncertain && analysis.containsNumericData {
                                    Log.warning("[DocumentProcessor] ⚠️ Uncertain table value: '\(analysis.text)' (conf: \(String(format: "%.0f%%", analysis.confidence * 100))). Alternatives: \(analysis.alternatives.map { "\($0.text)(\(String(format: "%.0f%%", $0.confidence * 100)))" }.joined(separator: ", "))", category: .ingestion)
                                }
                                return analysis.text.isEmpty ? nil : analysis.text
                            }
                        }

                        // Calculate bounding box
                        let allObs = tableRows.flatMap { $0 }
                        let minX = allObs.map { $0.boundingBox.minX }.min() ?? 0
                        let maxX = allObs.map { $0.boundingBox.maxX }.max() ?? 1
                        let minY = allObs.map { $0.boundingBox.minY }.min() ?? 0
                        let maxY = allObs.map { $0.boundingBox.maxY }.max() ?? 1

                        tables.append(DetectedTable(
                            rows: textRows,
                            boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                            confidence: Float(tableRows.count) / Float(max(1, rows.count))
                        ))

                        // Mark these observations as table content
                        for row in tableRows {
                            for obs in row {
                                tableObservations.insert(obs.uuid)
                            }
                        }

                        Log.debug("[DocumentProcessor] Detected table: \(tableRows.count) rows × \(columnCount) columns", category: .ingestion)
                    }
                }

                i = j
            } else {
                i += 1
            }
        }

        // Return non-table observations
        let remaining = observations.filter { !tableObservations.contains($0.uuid) }

        return (tables, remaining)
    }

    /// Check if rows have consistent column X-alignment (suggesting table structure)
    private func hasConsistentColumnAlignment(_ rows: [[VNRecognizedTextObservation]]) -> Bool {
        guard rows.count >= 2 else { return false }

        // Get X positions of first row as reference
        let referenceXs = rows[0].map { $0.boundingBox.midX }
        let alignmentThreshold: CGFloat = 0.05 // 5% tolerance

        for row in rows.dropFirst() {
            let rowXs = row.map { $0.boundingBox.midX }

            // Check if this row's X positions roughly align with reference
            var alignedCount = 0
            for x in rowXs {
                for refX in referenceXs {
                    if abs(x - refX) < alignmentThreshold {
                        alignedCount += 1
                        break
                    }
                }
            }

            // Require at least 50% of columns to align
            if alignedCount < row.count / 2 {
                return false
            }
        }

        return true
    }

    private func normalizationProfile(for documentType: DocumentType) -> OCRConfiguration.TextNormalizationProfile {
        switch documentType {
        case .text, .markdown, .rtf,
             .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code,
             .csv,
               .word, .excel, .powerpoint, .pages, .numbers, .keynote,
             .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            return .authoredText

        default:
            return .extractedDocument
        }
    }

    private func readTextFileWithFallbackEncodings(url: URL, purpose: String) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }

        Log.warning("[DocumentProcessor] UTF-8 decode failed for \(purpose); trying fallback encodings", category: .ingestion)

        if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1), !latin1.isEmpty {
            Log.debug("[DocumentProcessor] Decoded \(purpose) with Latin-1", category: .ingestion)
            return latin1
        }

        if let win1252 = try? String(contentsOf: url, encoding: .windowsCP1252), !win1252.isEmpty {
            Log.debug("[DocumentProcessor] Decoded \(purpose) with Windows-1252", category: .ingestion)
            return win1252
        }

        if let ascii = try? String(contentsOf: url, encoding: .ascii), !ascii.isEmpty {
            Log.debug("[DocumentProcessor] Decoded \(purpose) with ASCII", category: .ingestion)
            return ascii
        }

        throw DocumentProcessingError.unsupportedEncoding
    }

    /// Extract text from code files - preserve syntax and structure
    private func extractTextFromCode(url: URL) throws -> String {
        try readTextFileWithFallbackEncodings(url: url, purpose: "code file")
    }

    /// Extract text from CSV - RFC 4180 compliant parser
    /// Handles: quoted fields, embedded delimiters, embedded newlines,
    /// escaped quotes (""), multiple delimiter types (comma, tab, semicolon, pipe)
    private func extractTextFromCSV(url: URL) throws -> String {
        // Try multiple encodings for robustness
        let csvContent: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            csvContent = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            Log.info("[DocumentProcessor] CSV: Using Latin-1 encoding (UTF-8 failed)", category: .ingestion)
            csvContent = latin1
        } else if let win1252 = try? String(contentsOf: url, encoding: .windowsCP1252) {
            Log.info("[DocumentProcessor] CSV: Using Windows-1252 encoding", category: .ingestion)
            csvContent = win1252
        } else {
            throw DocumentProcessingError.unsupportedEncoding
        }

        guard !csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        // Detect delimiter from first line (tab > semicolon > pipe > comma)
        let delimiter = detectCSVDelimiter(csvContent)
        Log.debug("[DocumentProcessor] CSV delimiter detected: '\(delimiter == "\t" ? "TAB" : String(delimiter))'", category: .ingestion)

        // Parse using RFC 4180 state machine
        let rows = parseCSVRows(csvContent, delimiter: delimiter)

        guard !rows.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        let totalRows = rows.count - 1
        if totalRows > 1000 {
            Log.info("[DocumentProcessor] Processing large CSV: \(totalRows) rows", category: .ingestion)
        }

        return formattedPipeTableText(from: rows)
    }

    /// Detect CSV delimiter by analyzing the first few lines
    /// Priority: tab > semicolon > pipe > comma (avoids false positives from commas in text)
    private func detectCSVDelimiter(_ content: String) -> Character {
        // Take first 5 lines (not parsed, just split by raw newline for detection)
        let sampleLines = content.components(separatedBy: .newlines).prefix(5)
        let sample = sampleLines.joined(separator: "\n")

        let tabCount = sample.filter { $0 == "\t" }.count
        let semiCount = sample.filter { $0 == ";" }.count
        let pipeCount = sample.filter { $0 == "|" }.count
        let commaCount = sample.filter { $0 == "," }.count

        // Tab is unambiguous — if present, it's almost always the delimiter
        if tabCount >= sampleLines.count - 1 && tabCount > 0 {
            return "\t"
        }

        // Pick the most frequent delimiter that appears consistently across lines
        let candidates: [(Character, Int)] = [
            ("\t", tabCount),
            (";", semiCount),
            ("|", pipeCount),
            (",", commaCount)
        ]

        // Delimiter should appear at least once per line — pick the one with most consistent count
        if let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        return "," // Default
    }

    /// RFC 4180 CSV parser — handles quoted fields, embedded delimiters, embedded newlines, escaped quotes
    /// Returns array of rows, each row is an array of field values
    private func parseCSVRows(_ content: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            if inQuotes {
                if char == "\"" {
                    // Look ahead: is this an escaped quote ("") or end of quoted field?
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        // Escaped quote — add literal quote and skip both
                        currentField.append("\"")
                        i = content.index(after: next)
                        continue
                    } else {
                        // End of quoted field
                        inQuotes = false
                        i = content.index(after: i)
                        continue
                    }
                } else {
                    // Inside quotes — everything is literal (including delimiters and newlines)
                    currentField.append(char)
                    i = content.index(after: i)
                    continue
                }
            }

            // Not in quotes
            if char == "\"" {
                // Start of quoted field (should be at field start, but be permissive)
                inQuotes = true
                i = content.index(after: i)
                continue
            }

            if char == delimiter {
                // End of field
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
                i = content.index(after: i)
                continue
            }

            if char == "\r" {
                // Handle \r\n and bare \r
                let next = content.index(after: i)
                if next < content.endIndex && content[next] == "\n" {
                    i = content.index(after: next)
                } else {
                    i = content.index(after: i)
                }
                // End of row
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
                continue
            }

            if char == "\n" {
                // End of row
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
                i = content.index(after: i)
                continue
            }

            // Regular character
            currentField.append(char)
            i = content.index(after: i)
        }

        // Don't forget the last field/row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    // MARK: - Audio/Video Transcription

    /// Extract text from audio/video files using Speech.framework
    private func extractTextFromAudioVideo(url: URL) async throws -> String {
        let speechService = SpeechAnalyzerService.shared

        // Check if SpeechAnalyzer can handle this file
        guard speechService.canAnalyze(url: url) else {
            throw DocumentProcessingError.audioTranscriptionFailed("Unsupported audio/video format")
        }

        // Detect language from filename or default to English
        let filename = url.lastPathComponent.lowercased()
        var language = "en-US"

        // Simple language hints from filename
        if filename.contains("_es") || filename.contains("spanish") {
            language = "es-ES"
        } else if filename.contains("_fr") || filename.contains("french") {
            language = "fr-FR"
        } else if filename.contains("_de") || filename.contains("german") {
            language = "de-DE"
        } else if filename.contains("_zh") || filename.contains("chinese") {
            language = "zh-CN"
        } else if filename.contains("_ja") || filename.contains("japanese") {
            language = "ja-JP"
        }

        progressHandler?("transcribing audio")

        do {
            let result = try await speechService.analyze(url: url, language: language)

            if result.isSuccessful {
                Log.info("[DocumentProcessor] Transcribed \(result.wordCount) words from \(url.lastPathComponent) via SpeechAnalyzer", category: .ingestion)
                return speechService.analysisToDocument(result, sourceFile: url.lastPathComponent)
            } else {
                throw DocumentProcessingError.audioTranscriptionEmpty
            }
        } catch let error as SpeechAnalysisError {
            Log.error("[DocumentProcessor] Speech analysis failed: \(error.localizedDescription)", category: .ingestion)
            throw DocumentProcessingError.audioTranscriptionFailed(error.localizedDescription)
        } catch let error as TranscriptionError {
            Log.error("[DocumentProcessor] Transcription failed: \(error.localizedDescription)", category: .ingestion)
            throw DocumentProcessingError.audioTranscriptionFailed(error.localizedDescription)
        }
    }

    /// Extract text from Office documents (Word, Excel, PowerPoint, iWork)
    private func extractTextFromOfficeDocument(url: URL, type: DocumentType) async throws -> String {
        // For iWork documents (.pages, .numbers, .keynote), they're actually ZIP packages
        if type == .pages || type == .numbers || type == .keynote {
            return try extractTextFromIWorkDocument(url: url)
        }

        // For Microsoft Office formats, attempt extraction
        // .docx, .xlsx, .pptx are also ZIP packages with XML
        if type == .word || type == .excel || type == .powerpoint {
            return try extractTextFromOfficeXML(url: url, type: type)
        }

        // Legacy .doc, .xls, .ppt - limited support
        Log.warning("[DocumentProcessor] Legacy Office format detected", category: .ingestion)
        Log.info("[DocumentProcessor] Suggestion: Convert to .docx, .xlsx, or .pptx for better support", category: .ingestion)
        throw DocumentProcessingError.legacyOfficeFormat
    }

    /// Extract text from iWork documents (Pages, Numbers, Keynote)
    private func extractTextFromIWorkDocument(url: URL) throws -> String {
        // iWork documents are packages - look for index.xml or similar
        // This is a simplified implementation
        Log.warning(
            "[DocumentProcessor] iWork content is not readable: modern Pages/Numbers/Keynote store "
                + "text as compressed protobuf in Index/*.iwa, which this app does not parse",
            category: .ingestion
        )
        Log.info("[DocumentProcessor] Suggestion: Export as PDF or text for full compatibility", category: .ingestion)

        // Try to read as a package
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Look for text content in the package
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                if file.pathExtension == "xml" || file.pathExtension == "txt" {
                    if let content = try? String(contentsOf: file, encoding: .utf8), !content.isEmpty {
                        // Basic XML stripping for text extraction
                        let text = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return text
                        }
                    }
                }
            }
        }

        throw DocumentProcessingError.iWorkExtractionFailed
    }

    /// Extract text from modern Office XML formats (.docx, .xlsx, .pptx)
    /// These are ZIP archives containing XML with the actual content
    private func extractTextFromOfficeXML(url: URL, type: DocumentType) throws -> String {
        // Modern Office formats are ZIP files with XML content inside
        // .docx: word/document.xml
        // .xlsx: xl/sharedStrings.xml + xl/worksheets/sheet*.xml
        // .pptx: ppt/slides/slide*.xml

        Log.info("[DocumentProcessor] Extracting Office XML: \(url.lastPathComponent)", category: .ingestion)

        // Read the file as data and extract using Archive (iOS 16+)
        guard let archive = ZIPArchive(url: url) else {
            Log.warning("[DocumentProcessor] Failed to open as ZIP archive", category: .ingestion)
            throw DocumentProcessingError.officeFormatNeedsConversion
        }

        var extractedText = ""

        switch type {
        case .word:
            // Word documents: main content is in word/document.xml
            if let documentXML = archive.extractString(path: "word/document.xml") {
                extractedText = extractTextFromWordXML(documentXML)
            }
            // Headers/footers (stop at first miss, don't loop to 10)
            for i in 1...20 {
                if let headerXML = archive.extractString(path: "word/header\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(headerXML)
                } else if i > 3 { break }  // At least check 1–3
                if let footerXML = archive.extractString(path: "word/footer\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(footerXML)
                }
            }
            // Footnotes and endnotes — important for academic/legal documents
            if let footnotesXML = archive.extractString(path: "word/footnotes.xml") {
                let footnoteText = extractTextFromWordXML(footnotesXML)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !footnoteText.isEmpty {
                    extractedText += "\n\nFootnotes:\n" + footnoteText
                }
            }
            if let endnotesXML = archive.extractString(path: "word/endnotes.xml") {
                let endnoteText = extractTextFromWordXML(endnotesXML)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !endnoteText.isEmpty {
                    extractedText += "\n\nEndnotes:\n" + endnoteText
                }
            }

        case .excel:
            // Excel: shared strings + worksheet cells
            var sharedStrings: [String] = []
            if let sharedStringsXML = archive.extractString(path: "xl/sharedStrings.xml") {
                sharedStrings = extractSharedStringsFromExcel(sharedStringsXML)
            }
            // Extract each worksheet
            for i in 1...100 {
                if let sheetXML = archive.extractString(path: "xl/worksheets/sheet\(i).xml") {
                    extractedText += extractTextFromExcelSheet(sheetXML, sharedStrings: sharedStrings)
                    extractedText += "\n\n"
                } else {
                    break
                }
            }

        case .powerpoint:
            // PowerPoint: slides contain text, notes contain speaker notes
            for i in 1...500 {
                if let slideXML = archive.extractString(path: "ppt/slides/slide\(i).xml") {
                    let slideText = extractTextFromPowerPointSlide(slideXML)
                    extractedText += "Slide \(i):\n" + slideText

                    // Speaker notes — often contain the most detailed information
                    if let notesXML = archive.extractString(path: "ppt/notesSlides/notesSlide\(i).xml") {
                        let notesText = extractTextFromPowerPointSlide(notesXML)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !notesText.isEmpty && notesText != "\(i)" {
                            // Skip notes that are just the slide number
                            extractedText += "\nNotes: " + notesText
                        }
                    }

                    extractedText += "\n\n---\n\n"  // Slide separator
                } else {
                    break
                }
            }

        default:
            throw DocumentProcessingError.officeFormatNeedsConversion
        }

        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.warning("[DocumentProcessor] No text extracted from Office document", category: .ingestion)
            throw DocumentProcessingError.officeFormatNeedsConversion
        }

        Log.info("[DocumentProcessor] Extracted \(trimmed.count) chars from Office document", category: .ingestion)
        return trimmed
    }

    /// Extract text from Word XML with table, list, and run-spacing support.
    /// Parses `<w:tbl>` → `<w:tr>` → `<w:tc>` hierarchy for tables.
    /// Joins `<w:t>` runs within a paragraph with proper whitespace.
    private func extractTextFromWordXML(_ xml: String) -> String {
        var result = ""

        // STEP 1: Extract tables separately and replace them with placeholders
        // This prevents table text from being mixed into paragraph flow
        var tableTexts: [String] = []
        var processedXML = xml

        let tablePattern = #"<w:tbl\b[^>]*>.*?</w:tbl>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(xml.startIndex..., in: xml)
            var matches: [NSTextCheckingResult] = []
            tableRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
                if let match = match { matches.append(match) }
            }

            // The placeholder is wrapped in a `<w:p>` rather than left as bare text.
            //
            // Every table in every .docx was previously extracted and then silently discarded. STEP 2
            // below builds `result` exclusively from `<w:p>...</w:p>` matches, and in OOXML a `<w:tbl>`
            // is a *sibling* of `<w:p>` inside `<w:body>`, never nested inside one. So a bare
            // "[[TABLE_0]]" written where the table used to be sat outside every paragraph match, never
            // entered `result`, and STEP 3's substitution then found nothing to replace. The table text
            // was computed, held in `tableTexts`, and dropped on the floor. Wrapping the placeholder in
            // a paragraph puts it back in the one stream STEP 2 actually reads, and keeps it at the
            // table's original position in the document.
            //
            // Matches are replaced back-to-front so earlier ranges stay valid. Indexing by document
            // order rather than by append order is a readability change, not a second fix: numbering
            // by `tableTexts.count` while walking in reverse labelled the last table 0, but it also
            // stored that table's text at index 0, so the pairing was reversed and self-consistent.
            // Document order is worth having anyway, because the placeholder number now matches the
            // table's position on the page when this has to be debugged from a log.
            var orderedTableTexts = [String](repeating: "", count: matches.count)
            for (reverseOffset, match) in matches.reversed().enumerated() {
                let documentIndex = matches.count - 1 - reverseOffset
                if let matchRange = Range(match.range, in: processedXML) {
                    let tableXML = String(processedXML[matchRange])
                    orderedTableTexts[documentIndex] = extractTableFromWordXML(tableXML)
                    let placeholder = "\n<w:p><w:r><w:t>[[TABLE_\(documentIndex)]]</w:t></w:r></w:p>\n"
                    processedXML.replaceSubrange(matchRange, with: placeholder)
                }
            }
            tableTexts = orderedTableTexts
        }

        // STEP 2: Extract paragraphs with run-level text joining
        let paragraphPattern = #"<w:p\b[^>]*>(.*?)</w:p>"#
        let runTextPattern = #"<w:t[^>]*>([^<]*)</w:t>"#
        let listPattern = #"<w:numPr>"#  // Presence indicates numbered/bullet list item
        let breakPattern = #"<w:br\s*/?\s*>"#

        if let paraRegex = try? NSRegularExpression(pattern: paragraphPattern, options: [.dotMatchesLineSeparators]),
           let runRegex = try? NSRegularExpression(pattern: runTextPattern, options: []),
           let listRegex = try? NSRegularExpression(pattern: listPattern, options: []),
           let breakRegex = try? NSRegularExpression(pattern: breakPattern, options: []) {

            let range = NSRange(processedXML.startIndex..., in: processedXML)
            paraRegex.enumerateMatches(in: processedXML, options: [], range: range) { match, _, _ in
                guard let match = match, let contentRange = Range(match.range(at: 1), in: processedXML) else { return }
                let paraContent = String(processedXML[contentRange])

                // Check for list item
                let isListItem = listRegex.firstMatch(in: paraContent, options: [],
                    range: NSRange(paraContent.startIndex..., in: paraContent)) != nil

                // Replace <w:br/> with newline
                let processed = breakRegex.stringByReplacingMatches(in: paraContent, options: [],
                    range: NSRange(paraContent.startIndex..., in: paraContent), withTemplate: "\n")

                // Extract all text runs and join with space (preserves word boundaries)
                let runRange = NSRange(processed.startIndex..., in: processed)
                var runs: [String] = []
                runRegex.enumerateMatches(in: processed, options: [], range: runRange) { runMatch, _, _ in
                    if let runMatch = runMatch, let textRange = Range(runMatch.range(at: 1), in: processed) {
                        runs.append(String(processed[textRange]))
                    }
                }

                let paragraphText = runs.joined() // Runs within a paragraph are contiguous
                if !paragraphText.trimmingCharacters(in: .whitespaces).isEmpty {
                    if isListItem {
                        result += "• " + paragraphText + "\n"
                    } else {
                        result += paragraphText + "\n"
                    }
                }
            }
        }

        // STEP 3: Re-insert table text at placeholders
        for (i, tableText) in tableTexts.enumerated() {
            result = result.replacingOccurrences(of: "[[TABLE_\(i)]]", with: "\n" + tableText + "\n")
        }

        return result
    }

    /// Extract a single Word XML table as pipe-separated text
    /// Parses `<w:tbl>` → `<w:tr>` → `<w:tc>` → `<w:t>` hierarchy
    private func extractTableFromWordXML(_ tableXML: String) -> String {
        let rowPattern = #"<w:tr\b[^>]*>(.*?)</w:tr>"#
        let cellPattern = #"<w:tc\b[^>]*>(.*?)</w:tc>"#
        let textPattern = #"<w:t[^>]*>([^<]*)</w:t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
              let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) else {
            return ""
        }

        var tableRows: [[String]] = []

        let rowRange = NSRange(tableXML.startIndex..., in: tableXML)
        rowRegex.enumerateMatches(in: tableXML, options: [], range: rowRange) { rowMatch, _, _ in
            guard let rowMatch = rowMatch, let rowContent = Range(rowMatch.range(at: 1), in: tableXML) else { return }
            let rowStr = String(tableXML[rowContent])
            var cells: [String] = []

            let cellRange = NSRange(rowStr.startIndex..., in: rowStr)
            cellRegex.enumerateMatches(in: rowStr, options: [], range: cellRange) { cellMatch, _, _ in
                guard let cellMatch = cellMatch, let cellContent = Range(cellMatch.range(at: 1), in: rowStr) else { return }
                let cellStr = String(rowStr[cellContent])

                // Extract all text runs within the cell
                var cellText: [String] = []
                let textRange = NSRange(cellStr.startIndex..., in: cellStr)
                textRegex.enumerateMatches(in: cellStr, options: [], range: textRange) { textMatch, _, _ in
                    if let textMatch = textMatch, let tRange = Range(textMatch.range(at: 1), in: cellStr) {
                        cellText.append(String(cellStr[tRange]))
                    }
                }
                cells.append(cellText.joined().trimmingCharacters(in: .whitespaces))
            }

            if !cells.allSatisfy({ $0.isEmpty }) {
                tableRows.append(cells)
            }
        }

        // Format as pipe-separated table with header separator
        guard !tableRows.isEmpty else { return "" }

        var output = ""
        for (i, row) in tableRows.enumerated() {
            output += "| " + row.joined(separator: " | ") + " |\n"
            if i == 0 {
                // Add header separator after first row
                output += "|" + row.map { _ in " --- " }.joined(separator: "|") + "|\n"
            }
        }
        return output
    }

    /// Extract shared strings from Excel (these are referenced by index in sheets)
    /// Handles rich text strings with multiple `<r><t>` runs within a single `<si>` element
    private func extractSharedStringsFromExcel(_ xml: String) -> [String] {
        var strings: [String] = []

        // Match each <si>...</si> block, then extract ALL <t> tags within it
        let siPattern = #"<si>(.*?)</si>"#
        let tPattern = #"<t[^>]*>([^<]*)</t>"#

        guard let siRegex = try? NSRegularExpression(pattern: siPattern, options: [.dotMatchesLineSeparators]),
              let tRegex = try? NSRegularExpression(pattern: tPattern, options: []) else {
            return strings
        }

        let range = NSRange(xml.startIndex..., in: xml)
        siRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let match = match, let contentRange = Range(match.range(at: 1), in: xml) else { return }
            let siContent = String(xml[contentRange])

            // Concatenate ALL <t> fragments within this shared string
            var fragments: [String] = []
            let tRange = NSRange(siContent.startIndex..., in: siContent)
            tRegex.enumerateMatches(in: siContent, options: [], range: tRange) { tMatch, _, _ in
                if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: siContent) {
                    fragments.append(String(siContent[textRange]))
                }
            }
            strings.append(fragments.joined())
        }

        return strings
    }

    /// Extract text from Excel worksheet, using shared strings for cell values.
    /// Handles cells with formulas (`<f>` before `<v>`), inline strings (`<is><t>`),
    /// and boolean/error types.
    private func extractTextFromExcelSheet(_ xml: String, sharedStrings: [String]) -> String {
        var rows: [[String]] = []

        let rowPattern = #"<row[^>]*>(.*?)</row>"#
        // More permissive cell pattern: captures type and looks for <v> OR <is><t> anywhere in cell
        let cellPattern = #"<c\b([^>]*)>(.*?)</c>"#
        let typePattern = #"t="([^"]*)""#
        let valuePattern = #"<v>([^<]*)</v>"#
        let inlinePattern = #"<t[^>]*>([^<]*)</t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
              let typeRegex = try? NSRegularExpression(pattern: typePattern, options: []),
              let valueRegex = try? NSRegularExpression(pattern: valuePattern, options: []),
              let inlineRegex = try? NSRegularExpression(pattern: inlinePattern, options: []) else {
            return ""
        }

        let range = NSRange(xml.startIndex..., in: xml)
        rowRegex.enumerateMatches(in: xml, options: [], range: range) { rowMatch, _, _ in
            guard let rowMatch = rowMatch, let rowContentRange = Range(rowMatch.range(at: 1), in: xml) else { return }
            let rowContent = String(xml[rowContentRange])
            var currentRow: [String] = []

            let cellRange = NSRange(rowContent.startIndex..., in: rowContent)
            cellRegex.enumerateMatches(in: rowContent, options: [], range: cellRange) { cellMatch, _, _ in
                guard let cellMatch = cellMatch else { return }
                let attrsRange = Range(cellMatch.range(at: 1), in: rowContent)
                let bodyRange = Range(cellMatch.range(at: 2), in: rowContent)

                let attrs = attrsRange.map { String(rowContent[$0]) } ?? ""
                let body = bodyRange.map { String(rowContent[$0]) } ?? ""

                // Determine cell type
                var cellType: String? = nil
                if let typeMatch = typeRegex.firstMatch(in: attrs, options: [],
                    range: NSRange(attrs.startIndex..., in: attrs)),
                   let tRange = Range(typeMatch.range(at: 1), in: attrs) {
                    cellType = String(attrs[tRange])
                }

                // Try to get value from <v> tag
                if let valueMatch = valueRegex.firstMatch(in: body, options: [],
                    range: NSRange(body.startIndex..., in: body)),
                   let vRange = Range(valueMatch.range(at: 1), in: body) {
                    let value = String(body[vRange])

                    if cellType == "s", let index = Int(value), index < sharedStrings.count {
                        currentRow.append(sharedStrings[index])
                    } else if cellType == "b" {
                        currentRow.append(value == "1" ? "TRUE" : "FALSE")
                    } else {
                        currentRow.append(value)
                    }
                } else if cellType == "inlineStr" || cellType == "str" {
                    // Inline string: extract from <is><t> or just <t>
                    var fragments: [String] = []
                    let bRange = NSRange(body.startIndex..., in: body)
                    inlineRegex.enumerateMatches(in: body, options: [], range: bRange) { tMatch, _, _ in
                        if let tMatch = tMatch, let tRange = Range(tMatch.range(at: 1), in: body) {
                            fragments.append(String(body[tRange]))
                        }
                    }
                    currentRow.append(fragments.joined())
                } else {
                    // Empty cell
                    currentRow.append("")
                }
            }

            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return formattedPipeTableText(from: rows)
    }

    private func formattedPipeTableText(from rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        let columnCount = rows.map(\ .count).max() ?? 0

        func normalizedRow(_ row: [String]) -> [String] {
            var cells = row.map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if cells.count < columnCount {
                cells.append(contentsOf: Array(repeating: "", count: columnCount - cells.count))
            }
            return cells
        }

        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            let cells = normalizedRow(row)
            guard cells.contains(where: { !$0.isEmpty }) else { continue }
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if index == 0 && rows.count > 1 {
                lines.append("|" + Array(repeating: " --- ", count: columnCount).joined(separator: "|") + "|")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Extract text from PowerPoint slide XML with paragraph and table awareness
    /// Preserves `<a:p>` paragraph boundaries, extracts `<a:tbl>` tables as pipe-separated
    private func extractTextFromPowerPointSlide(_ xml: String) -> String {
        var result = ""

        // STEP 1: Extract tables and replace with placeholders
        var tableTexts: [String] = []
        var processedXML = xml
        let tablePattern = #"<a:tbl\b[^>]*>.*?</a:tbl>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(xml.startIndex..., in: xml)
            var matches: [NSTextCheckingResult] = []
            tableRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
                if let match = match { matches.append(match) }
            }
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: processedXML) {
                    let tableXML = String(processedXML[matchRange])
                    let tableText = extractTableFromPowerPointXML(tableXML)
                    let placeholder = "\n[[PPTTABLE_\(tableTexts.count)]]\n"
                    tableTexts.append(tableText)
                    processedXML.replaceSubrange(matchRange, with: placeholder)
                }
            }
        }

        // STEP 2: Extract paragraphs — <a:p> contains <a:r><a:t> text runs
        let paraPattern = #"<a:p\b[^>]*>(.*?)</a:p>"#
        let textPattern = #"<a:t>([^<]*)</a:t>"#

        if let paraRegex = try? NSRegularExpression(pattern: paraPattern, options: [.dotMatchesLineSeparators]),
           let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) {

            let range = NSRange(processedXML.startIndex..., in: processedXML)
            paraRegex.enumerateMatches(in: processedXML, options: [], range: range) { match, _, _ in
                guard let match = match, let contentRange = Range(match.range(at: 1), in: processedXML) else { return }
                let paraContent = String(processedXML[contentRange])

                // Extract all text runs in this paragraph
                var runs: [String] = []
                let tRange = NSRange(paraContent.startIndex..., in: paraContent)
                textRegex.enumerateMatches(in: paraContent, options: [], range: tRange) { tMatch, _, _ in
                    if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: paraContent) {
                        let content = String(paraContent[textRange])
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            runs.append(content)
                        }
                    }
                }

                if !runs.isEmpty {
                    result += runs.joined() + "\n"
                }
            }
        }

        // STEP 3: Re-insert tables
        for (i, tableText) in tableTexts.enumerated() {
            result = result.replacingOccurrences(of: "[[PPTTABLE_\(i)]]", with: "\n" + tableText + "\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract a PowerPoint table as pipe-separated text
    private func extractTableFromPowerPointXML(_ tableXML: String) -> String {
        let rowPattern = #"<a:tr\b[^>]*>(.*?)</a:tr>"#
        let cellPattern = #"<a:tc\b[^>]*>(.*?)</a:tc>"#
        let textPattern = #"<a:t>([^<]*)</a:t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
              let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) else {
            return ""
        }

        var tableRows: [[String]] = []
        let rowRange = NSRange(tableXML.startIndex..., in: tableXML)

        rowRegex.enumerateMatches(in: tableXML, options: [], range: rowRange) { rowMatch, _, _ in
            guard let rowMatch = rowMatch, let rowContent = Range(rowMatch.range(at: 1), in: tableXML) else { return }
            let rowStr = String(tableXML[rowContent])
            var cells: [String] = []

            let cellRange = NSRange(rowStr.startIndex..., in: rowStr)
            cellRegex.enumerateMatches(in: rowStr, options: [], range: cellRange) { cellMatch, _, _ in
                guard let cellMatch = cellMatch, let cellContent = Range(cellMatch.range(at: 1), in: rowStr) else { return }
                let cellStr = String(rowStr[cellContent])

                var cellText: [String] = []
                let tRange = NSRange(cellStr.startIndex..., in: cellStr)
                textRegex.enumerateMatches(in: cellStr, options: [], range: tRange) { tMatch, _, _ in
                    if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: cellStr) {
                        cellText.append(String(cellStr[textRange]))
                    }
                }
                cells.append(cellText.joined().trimmingCharacters(in: .whitespaces))
            }

            if !cells.allSatisfy({ $0.isEmpty }) {
                tableRows.append(cells)
            }
        }

        guard !tableRows.isEmpty else { return "" }
        var output = ""
        for (i, row) in tableRows.enumerated() {
            output += "| " + row.joined(separator: " | ") + " |\n"
            if i == 0 {
                output += "|" + row.map { _ in " --- " }.joined(separator: "|") + "|\n"
            }
        }
        return output
    }

    // MARK: - Chunking Strategy

    /// Intelligent text chunking strategy using semantic boundaries
    /// Splits on paragraphs first, then sentences, maintaining context overlap
    private func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []

        // First, split by paragraphs (semantic boundaries)
        let paragraphs = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var currentChunk = ""
        var wordCount = 0

        for paragraph in paragraphs {
            let paragraphWords = paragraph.split(separator: " ")
            let paragraphWordCount = paragraphWords.count

            // If adding this paragraph exceeds target size, finalize current chunk
            if wordCount + paragraphWordCount > targetChunkSize && wordCount > 0 {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))

                // Implement overlap by keeping last N words
                let overlapWords = currentChunk.split(separator: " ").suffix(chunkOverlap)
                currentChunk = overlapWords.joined(separator: " ") + " "
                wordCount = overlapWords.count
            }

            currentChunk += paragraph + "\n\n"
            wordCount += paragraphWordCount
        }

        // Add final chunk
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks
    }

    // MARK: - Utilities

    func detectDocumentType(url: URL) -> DocumentType {
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        // Documents
        case "pdf":
            return .pdf
        case "txt":
            return .text
        case "md", "markdown", "mdown":
            return .markdown
        case "rtf":
            return .rtf

        // Images (OCR support)
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "heic", "heif":
            return .heic
        case "tiff", "tif":
            return .tiff
        case "gif":
            return .gif
        case "bmp", "webp":
            return .image

        // Code files
        case "swift":
            return .swift
        case "py", "pyw", "pyx":
            return .python
        case "js", "mjs", "cjs":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "java", "class":
            return .java
        case "cpp", "cc", "cxx", "c++":
            return .cpp
        case "c", "h":
            return .c
        case "m", "mm":
            return .objc
        case "go":
            return .go
        case "rs":
            return .rust
        case "rb":
            return .ruby
        case "php":
            return .php
        case "html", "htm":
            return .html
        case "css", "scss", "sass", "less":
            return .css
        case "json", "jsonc":
            return .json
        case "xml":
            return .xml
        case "yaml", "yml":
            return .yaml
        case "sql":
            return .sql
        case "sh", "bash", "zsh", "fish":
            return .shell
        case "kt", "kts", "scala", "clj", "ex", "exs", "elm", "hs", "lua", "pl", "r", "dart", "vim":
            return .code

        // Office documents
        case "doc", "docx":
            return .word
        case "xls", "xlsx":
            return .excel
        case "ppt", "pptx":
            return .powerpoint
        case "pages":
            return .pages
        case "numbers":
            return .numbers
        case "key":
            return .keynote

        // Data formats
        case "csv":
            return .csv

        // Audio formats (Speech transcription)
        case "m4a", "aac":
            return .m4a
        case "mp3":
            return .mp3
        case "wav", "wave", "aiff", "aif", "caf":
            return .wav

        // Video formats (Speech transcription)
        case "mp4", "m4v":
            return .mp4
        case "mov":
            return .mov
        case "avi", "mkv", "webm":
            return .video

        default:
            // Try to detect by content type as fallback
            if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let contentType = resourceValues.contentType {

                if contentType.conforms(to: .image) {
                    return .image
                } else if contentType.conforms(to: .audio) {
                    return .audio
                } else if contentType.conforms(to: .audiovisualContent) {
                    return .video
                } else if contentType.conforms(to: .plainText) || contentType.conforms(to: .sourceCode) {
                    return .code
                }
            }

            return .unknown
        }
    }
}

// MARK: - Errors

enum DocumentProcessingError: LocalizedError {
    case unsupportedFormat
    case pdfLoadFailed
    case pdfEncrypted
    case emptyDocument
    case imageOnlyPDF
    case rtfParseFailed
    case fileNotFound
    case unsupportedEncoding
    case corruptedFile
    case imageLoadFailed
    case ocrFailed
    case legacyOfficeFormat
    case officeFormatNeedsConversion
    case iWorkExtractionFailed
    case audioTranscriptionFailed(String)
    case audioTranscriptionEmpty
    case fileTooLarge(sizeMB: Double, limitMB: Double)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported document format"
        case .pdfLoadFailed:
            return "Failed to load PDF document"
        case .pdfEncrypted:
            return "This PDF is password-protected. Please remove the password and try again."
        case .emptyDocument:
            return "Document contains no text"
        case .imageOnlyPDF:
            return "PDF contains only images (no extractable text). OCR attempted but no text found. Try a higher quality scan or text-based PDF."
        case .rtfParseFailed:
            return "Failed to parse RTF document"
        case .fileNotFound:
            return "File not found at specified location"
        case .unsupportedEncoding:
            return "Document encoding not supported"
        case .corruptedFile:
            return "File appears to be corrupted"
        case .imageLoadFailed:
            return "Failed to load image file"
        case .ocrFailed:
            return "OCR text recognition failed"
        case .legacyOfficeFormat:
            return "Legacy Office format detected. Please convert to .docx, .xlsx, or .pptx for better support, or export as PDF."
        case .officeFormatNeedsConversion:
            return "Office document detected. For best results, export as PDF before importing."
        case .iWorkExtractionFailed:
            return "Pages, Numbers and Keynote files can't be read. Export this document as PDF, "
                + "Word, Excel or PowerPoint and import that instead."
        case let .audioTranscriptionFailed(reason):
            return "Audio transcription failed: \(reason)"
        case .audioTranscriptionEmpty:
            return "Audio transcription produced no text. The audio may be silent or incompatible."
        case let .fileTooLarge(sizeMB, limitMB):
            return "File is too large (\(String(format: "%.0f", sizeMB)) MB). Maximum supported size is \(String(format: "%.0f", limitMB)) MB. Try splitting the file into smaller parts."
        }
    }
}

// MARK: - ZIP Archive Helper for Office Documents

/// Lightweight ZIP archive reader for extracting Office XML content
/// Uses Foundation's compression framework for memory-efficient extraction
private final class ZIPArchive {
    private let fileHandle: FileHandle
    private let fileSize: UInt64
    private var centralDirectory: [String: CentralDirectoryEntry] = [:]

    struct CentralDirectoryEntry {
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let compressionMethod: UInt16
    }

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.fileHandle = handle

        // Get file size
        do {
            let endOffset = try handle.seekToEnd()
            self.fileSize = endOffset
            try handle.seek(toOffset: 0)
        } catch {
            try? handle.close()
            return nil
        }

        // Parse central directory
        if !parseCentralDirectory() {
            try? handle.close()
            return nil
        }
    }

    deinit {
        try? fileHandle.close()
    }

    /// Extract a file from the archive as a string
    func extractString(path: String) -> String? {
        guard let data = extractData(path: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Extract a file from the archive as data
    func extractData(path: String) -> Data? {
        guard let entry = centralDirectory[path] else { return nil }

        do {
            try fileHandle.seek(toOffset: UInt64(entry.localHeaderOffset))

            // Read local file header
            guard let localHeader = try fileHandle.read(upToCount: 30) else { return nil }
            guard localHeader.count >= 30 else { return nil }

            // Parse local header to get filename length and extra field length
            let filenameLength = UInt16(localHeader[26]) | (UInt16(localHeader[27]) << 8)
            let extraLength = UInt16(localHeader[28]) | (UInt16(localHeader[29]) << 8)

            // Skip filename and extra field
            let dataOffset = UInt64(entry.localHeaderOffset) + 30 + UInt64(filenameLength) + UInt64(extraLength)
            try fileHandle.seek(toOffset: dataOffset)

            // Read compressed data
            guard let compressedData = try fileHandle.read(upToCount: Int(entry.compressedSize)) else { return nil }

            // Decompress if needed
            if entry.compressionMethod == 0 {
                // Stored (no compression)
                return compressedData
            } else if entry.compressionMethod == 8 {
                // Deflate compression
                return decompressDeflate(compressedData, uncompressedSize: Int(entry.uncompressedSize))
            }

            return nil
        } catch {
            return nil
        }
    }

    private func parseCentralDirectory() -> Bool {
        // Find End of Central Directory record (search from end)
        let searchSize = min(65557, Int(fileSize))  // Max comment size + EOCD size
        let searchStart = fileSize - UInt64(searchSize)

        do {
            try fileHandle.seek(toOffset: searchStart)
            guard let searchData = try fileHandle.read(upToCount: searchSize) else { return false }

            // Look for EOCD signature (0x06054b50) from the end
            var eocdOffset: Int?
            for i in stride(from: searchData.count - 22, through: 0, by: -1) {
                if searchData[i] == 0x50 && searchData[i+1] == 0x4b &&
                   searchData[i+2] == 0x05 && searchData[i+3] == 0x06 {
                    eocdOffset = i
                    break
                }
            }

            guard let offset = eocdOffset else { return false }

            // Parse EOCD
            let cdEntries = UInt16(searchData[offset + 10]) | (UInt16(searchData[offset + 11]) << 8)
            let cdSize = UInt32(searchData[offset + 12]) | (UInt32(searchData[offset + 13]) << 8) |
                         (UInt32(searchData[offset + 14]) << 16) | (UInt32(searchData[offset + 15]) << 24)
            let cdOffset = UInt32(searchData[offset + 16]) | (UInt32(searchData[offset + 17]) << 8) |
                           (UInt32(searchData[offset + 18]) << 16) | (UInt32(searchData[offset + 19]) << 24)

            // Read central directory
            try fileHandle.seek(toOffset: UInt64(cdOffset))
            guard let cdData = try fileHandle.read(upToCount: Int(cdSize)) else { return false }

            // Parse central directory entries
            var pos = 0
            for _ in 0..<cdEntries {
                guard pos + 46 <= cdData.count else { break }

                // Check signature
                guard cdData[pos] == 0x50 && cdData[pos+1] == 0x4b &&
                      cdData[pos+2] == 0x01 && cdData[pos+3] == 0x02 else { break }

                let compressionMethod = UInt16(cdData[pos + 10]) | (UInt16(cdData[pos + 11]) << 8)
                let compressedSize = UInt32(cdData[pos + 20]) | (UInt32(cdData[pos + 21]) << 8) |
                                     (UInt32(cdData[pos + 22]) << 16) | (UInt32(cdData[pos + 23]) << 24)
                let uncompressedSize = UInt32(cdData[pos + 24]) | (UInt32(cdData[pos + 25]) << 8) |
                                       (UInt32(cdData[pos + 26]) << 16) | (UInt32(cdData[pos + 27]) << 24)
                let filenameLength = UInt16(cdData[pos + 28]) | (UInt16(cdData[pos + 29]) << 8)
                let extraLength = UInt16(cdData[pos + 30]) | (UInt16(cdData[pos + 31]) << 8)
                let commentLength = UInt16(cdData[pos + 32]) | (UInt16(cdData[pos + 33]) << 8)
                let localHeaderOffset = UInt32(cdData[pos + 42]) | (UInt32(cdData[pos + 43]) << 8) |
                                        (UInt32(cdData[pos + 44]) << 16) | (UInt32(cdData[pos + 45]) << 24)

                // Extract filename
                let filenameStart = pos + 46
                let filenameEnd = filenameStart + Int(filenameLength)
                guard filenameEnd <= cdData.count else { break }

                if let filename = String(data: cdData[filenameStart..<filenameEnd], encoding: .utf8) {
                    centralDirectory[filename] = CentralDirectoryEntry(
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize,
                        localHeaderOffset: localHeaderOffset,
                        compressionMethod: compressionMethod
                    )
                }

                pos = filenameEnd + Int(extraLength) + Int(commentLength)
            }

            return !centralDirectory.isEmpty
        } catch {
            return false
        }
    }

    /// Decompress deflate-compressed data using Compression framework
    private func decompressDeflate(_ data: Data, uncompressedSize: Int) -> Data? {
        // Use raw deflate (not zlib wrapped)
        var decompressed = Data(count: uncompressedSize)
        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        return result > 0 ? Data(decompressed.prefix(result)) : nil
    }
}

// MARK: - DocumentProcessor Ingestion Checkpointing & Codable Models Extension

extension DocumentProcessor {
    // MARK: - Checkpoint System Helpers

    private var checkpointsDirectoryURL: URL {
        let url = AppSupportPaths.localCacheDir().appendingPathComponent("IngestionCheckpoints", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func checkpointDirectoryURL(for fingerprint: String) -> URL {
        let url = checkpointsDirectoryURL.appendingPathComponent(fingerprint, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func computeDocumentFingerprint(at url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let path = url.path
        let key = "\(path)_\(size)_\(date)"
        let data = Data(key.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Clean up any checkpoint files for the given document URL
    func cleanCheckpoints(for url: URL) {
        let fingerprint = computeDocumentFingerprint(at: url)
        let checkpointDir = checkpointDirectoryURL(for: fingerprint)
        try? FileManager.default.removeItem(at: checkpointDir)
        Log.info("[Checkpoint] Cleaned up temporary page checkpoints for \(url.lastPathComponent) (fingerprint: \(fingerprint))", category: .ingestion)
    }

    // MARK: - Codable Checkpoint Mappings

    struct CodableDetectedEntity: Codable, Sendable {
        let type: String
        let value: String
        let rawText: String

        init(from entity: DetectedEntity) {
            self.type = entity.type.rawValue
            self.value = entity.value
            self.rawText = entity.rawText
        }

        func toDetectedEntity() -> DetectedEntity {
            let typeEnum = DetectedEntity.EntityType(rawValue: type) ?? .unknown
            return DetectedEntity(type: typeEnum, value: value, rawText: rawText)
        }
    }

    struct CodableTableData: Codable, Sendable {
        let pageNumber: Int
        let rows: [[String]]
        let headerRow: [String]?
        let caption: String?
        let detectedEntities: [CodableDetectedEntity]
        let cellAlignments: [[String]]

        init(_ data: TableData) {
            self.pageNumber = data.pageNumber
            self.rows = data.rows
            self.headerRow = data.headerRow
            self.caption = data.caption
            self.detectedEntities = data.detectedEntities.map { CodableDetectedEntity(from: $0) }
            self.cellAlignments = data.cellAlignments.map { $0.map { $0.rawValue } }
        }

        func toTableData() -> TableData {
            let entities = self.detectedEntities.map { $0.toDetectedEntity() }
            let alignments = self.cellAlignments.map { $0.map { TableCellAlignment(rawValue: $0) ?? .left } }
            return TableData(
                pageNumber: self.pageNumber,
                rows: self.rows,
                headerRow: self.headerRow,
                caption: self.caption,
                detectedEntities: entities,
                cellAlignments: alignments
            )
        }
    }

    struct CodableTupleEntity: Codable, Sendable {
        let type: String
        let value: String
    }

    struct CodableStructuredElement: Codable, Sendable {
        let text: String
        let elementType: String
        let pageNumber: Int
        let isAtomicChunk: Bool
        let detectedEntities: [CodableTupleEntity]
        let tableData: CodableTableData?
        let listItems: [String]?
        let extractionSource: String?
        let qualityScore: Double?

        fileprivate init(_ wrapper: DocumentProcessor.StructuredElementWrapper) {
            self.text = wrapper.text
            self.elementType = wrapper.elementType
            self.pageNumber = wrapper.pageNumber
            self.isAtomicChunk = wrapper.isAtomicChunk
            self.detectedEntities = wrapper.detectedEntities.map { CodableTupleEntity(type: $0.type, value: $0.value) }
            self.tableData = wrapper.tableData.map { CodableTableData($0) }
            self.listItems = wrapper.listItems
            self.extractionSource = wrapper.extractionSource
            self.qualityScore = wrapper.qualityScore
        }

        fileprivate func toWrapper() -> DocumentProcessor.StructuredElementWrapper {
            let entities = self.detectedEntities.map { (type: $0.type, value: $0.value) }
            return DocumentProcessor.StructuredElementWrapper(
                text: self.text,
                elementType: self.elementType,
                pageNumber: self.pageNumber,
                isAtomicChunk: self.isAtomicChunk,
                detectedEntities: entities,
                tableData: self.tableData?.toTableData(),
                listItems: self.listItems,
                extractionSource: self.extractionSource,
                qualityScore: self.qualityScore
            )
        }
    }

    struct IngestionCheckpointPage: Codable, Sendable {
        let pageIndex: Int
        let elements: [CodableStructuredElement]
        let pageText: String
        let hasStructure: Bool
        let usedOCR: Bool
        let tablesFound: Int
        let listsFound: Int
        let headersFound: Int
    }
}

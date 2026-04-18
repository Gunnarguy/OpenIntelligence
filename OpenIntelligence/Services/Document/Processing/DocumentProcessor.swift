//
//  DocumentProcessor.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
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

    struct ChunkingOverride: Sendable {
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
    private struct StructuredElementWrapper: Sendable {
        let text: String
        let elementType: String  // "table", "list", "paragraph", "title"
        let pageNumber: Int
        let isAtomicChunk: Bool  // Tables should be chunked as single units
        let detectedEntities: [(type: String, value: String)]  // Vision-detected entities (emails, phones, etc.)

        nonisolated init(text: String, elementType: String, pageNumber: Int, isAtomicChunk: Bool, detectedEntities: [(type: String, value: String)] = []) {
            self.text = text
            self.elementType = elementType
            self.pageNumber = pageNumber
            self.isAtomicChunk = isAtomicChunk
            self.detectedEntities = detectedEntities
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

    /// BertTokenizer for accurate token counting (matches embedding model tokenization)
    /// CRITICAL: NLTokenizer word count ≠ BertTokenizer tokens for technical content
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    private var embeddingTokenizer: BertTokenizer?

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

    /// Load BertTokenizer from embedding vocab for accurate token counting
    private func loadTokenizer() {
        if let url = OpenIntelligenceResourceBundle.url(forResource: "embedding_vocab", withExtension: "json") {
            do {
                let vocabData = try Data(contentsOf: url)
                let vocabDict = try JSONDecoder().decode([String: Int].self, from: vocabData)
                embeddingTokenizer = BertTokenizer(
                    vocab: vocabDict,
                    merges: nil,
                    tokenizeChineseChars: true,
                    doLowerCase: true
                )
                Log.info("[DocumentProcessor] Loaded BertTokenizer for accurate chunk validation", category: .ingestion)
            } catch {
                Log.warning("[DocumentProcessor] Failed to load BertTokenizer: \(error). Falling back to word estimation.", category: .ingestion)
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
    func processDocument(at url: URL, chunkOverride: ChunkingOverride? = nil, containerId: UUID? = nil) async throws -> (Document, [ProcessedChunk]) {
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
    let documentId = UUID()
    var pagesProcessed: Int? = nil
    var ocrPagesCount: Int? = nil

        // Determine document type
        let documentType = detectDocumentType(url: url)

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

        let extractedText: String
        let pageInfo: PageInfo

        // Use structured parsing for PDFs on iOS 26+ (preserves table/list structure)
        if documentType == .pdf {
            let structuredResult = try await extractStructuredPDFContent(url: url)
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
        }

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
        // Parts diagrams, rotated text, and noisy scans produce OCR garbage:
        // Cyrillic substitutions, backwards text, consonant noise, etc.
        // Filter per-line to remove garbage while preserving valid text.
        let filteredText: String
        if ocrPagesCount ?? 0 > 0 {
            // Only filter OCR'd pages — PDFKit text extraction is clean
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

        // UNIVERSAL TEXT NORMALIZATION
        // Runs on ALL extracted text — PDFKit and OCR alike — to fix:
        // ligatures, broken hyphens, smart quotes, zero-width chars, multi-spaces.
        // This is the single quality gate between raw extraction and chunking/embedding.
        let normalizedText = OCRConfiguration.normalizeExtractedText(filteredText)
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
        if pageTextsFromSentinel.count > 1 {
            storedText = pageTextsFromSentinel.enumerated().map { (index, pageContent) in
                "--- Page \(index + 1) ---\n\(pageContent)"
            }.joined(separator: "\n\n")
        } else {
            // Single page or no sentinels (non-PDF) — store as-is without markers
            storedText = normalizedText.replacingOccurrences(of: Self.pageBreakSentinel, with: "\n\n")
        }
        let storedCharCount = storedText.count

        if let containerId = containerId {
            // Primary path: SQLite FTS5 with container isolation (v1.1.0+)
            await SQLiteFullTextService.shared.store(text: storedText, for: documentId, containerId: containerId)
            Log.debug("[DocumentProcessor] Stored normalized text (\(storedCharCount) chars) to FTS5 for exact query support", category: .ingestion)

            // Step C: Store per-page content for page-level search and context isolation
            if pageTextsFromSentinel.count > 1 {
                let pageEntries = pageTextsFromSentinel.enumerated().map { (index, content) in
                    (pageNumber: index + 1, content: content)
                }
                await SQLiteFullTextService.shared.storePages(pages: pageEntries, for: documentId, containerId: containerId)
                Log.info("[DocumentProcessor] Stored \(pageEntries.count) individual pages to FTS5 for page-level context", category: .ingestion)
            }
        } else {
            // Fallback path: File-based storage (legacy, no container context)
            await FullTextStorageService.shared.store(text: storedText, for: documentId)
            Log.debug("[DocumentProcessor] Stored normalized text (\(storedCharCount) chars) to file storage (legacy path)", category: .ingestion)
        }

        // Step D: Strip page break sentinels for chunking — chunker must see continuous text
        let chunkableText = normalizedText.replacingOccurrences(of: Self.pageBreakSentinel, with: "\n\n")

        // Chunk the text using semantic chunker
        emitProgress(stage: "chunking", detail: "✂️ Semantic chunking text...", page: nil, totalPages: nil)
        await Task.yield() // Yield to UI without blocking (was 0.3s sleep)
        let chunkingStartTime = Date()

        // Create semantic chunker configuration
        // Use content-adaptive defaults if no override provided
        let baseConfig = SemanticChunker.ChunkingConfig.recommended(for: documentType)
        let activeWindow = chunkOverride?.targetWordWindow ?? baseConfig.targetSize
        let activeOverlap = chunkOverride?.overlapWords ?? baseConfig.overlap

        // CRITICAL: maxSize is capped at 310 words to prevent token truncation during embedding
        // CoreML model has 510 token limit; 340 words ≈ 500 tokens
        // BUT RAGService adds ~30 word contextual prefix during embedding
        // ACTUAL SAFE LIMIT: 310 words + 30 prefix = 340 total ≈ 500 tokens
        let safeMaxSize = 310

        let chunkerConfig = SemanticChunker.ChunkingConfig(
            targetSize: min(activeWindow, safeMaxSize - 50),  // Target must leave room for variance
            minSize: max(baseConfig.minSize, 60),
            maxSize: safeMaxSize,  // HARD LIMIT: Never exceed 310 words (leaves room for prefix)
            overlap: min(activeOverlap, 50),  // Cap overlap to prevent bloat
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
                pageInfo: pageInfo
            )
            emitProgress(stage: "chunking", detail: "✅ Created \(processedChunks.count) chunks", page: nil, totalPages: nil)
            Log.info("[DocumentProcessor] Created \(processedChunks.count) structure-aware chunks", category: .ingestion)
        } else {
            // Standard semantic chunking for non-PDF or iOS < 26
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
                pageNumbers: pageMapping
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
                    sectionPath: chunk.metadata.sectionPath.isEmpty ? nil : chunk.metadata.sectionPath
                )
                return ProcessedChunk(text: chunk.content, parentText: chunk.parentContent, metadata: metadata)
            }
            emitProgress(stage: "chunking", detail: "✅ Created \(processedChunks.count) semantic chunks", page: nil, totalPages: nil)
        }

        let chunkingTime = Date().timeIntervalSince(chunkingStartTime)

        // CRITICAL: Post-processing validation - ensure NO chunk exceeds embedding token limit
        // This is a safety net that catches any chunks that slipped through chunking config limits
        emitProgress(stage: "validate", detail: "🔐 Validating token limits...", page: nil, totalPages: nil)
        processedChunks = enforceTokenLimitOnChunks(processedChunks)

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
            do {
                // Try UTF-8 first (most common)
                text = try String(contentsOf: url, encoding: .utf8)
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            } catch {
                // Fallback to other encodings if UTF-8 fails
                Log.warning("[DocumentProcessor] UTF-8 decode failed; trying fallback encodings", category: .ingestion)
                if let data = try? Data(contentsOf: url) {
                    if let decodedText = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii) {
                        text = decodedText
                        pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                        Log.debug("[DocumentProcessor] Decoded with fallback encoding", category: .ingestion)
                    } else {
                        throw DocumentProcessingError.unsupportedEncoding
                    }
                } else {
                    throw error
                }
            }

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
            if let attemptedText = try? String(contentsOf: url, encoding: .utf8), !attemptedText.isEmpty {
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
        let documentTextLayerGarbled: Bool
        textLayerValidation: do {
            // Sample 3 spread-out pages to get representative PDFKit text
            let sampleIndices = pageCount <= 3
                ? Array(0..<pageCount)
                : [0, pageCount / 3, 2 * pageCount / 3]

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
        let pagesToAnalyze: [(PDFPage, Int)] = (0..<pageCount).compactMap { index in
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
        for batchStart in stride(from: 0, to: pageCount, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, pageCount)

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
                    if documentTextLayerGarbled || strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR {
                        // Complex page - render and preprocess image with adaptive strategy
                        pageImage = renderPDFPageAsImage(page: page)
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
                    let textQualityOK = !documentTextLayerGarbled && hasText && isTextQualityAcceptable(pageString!)

                    traceIngestionDecision(
                        pageNumber: pageNumber,
                        strategy: strategy.description,
                        hasText: hasText,
                        textQualityOK: textQualityOK,
                        requiresTableOCR: requiresOCRForAccuracy,
                        mode: "ocr-extraction"
                    )

                    // For pages with good text quality that DON'T have tables, try spatial extraction
                    // Table pages skip spatial — their text will come from Vision OCR instead
                    var effectiveString = pageString
                    if hasText && textQualityOK && !requiresOCRForAccuracy {
                        if let spatialText = extractTextWithSpatialOrdering(from: page), !spatialText.isEmpty {
                            effectiveString = spatialText
                        }
                    }

                    batchPageData.append(PageData(pageIndex: pageIndex, pageString: effectiveString, pageImage: pageImage, hasText: hasText, textQualityOK: textQualityOK, requiresOCRForAccuracy: requiresOCRForAccuracy))
                }
            }

            let batchResults = await withTaskGroup(of: PageExtractionResult.self) { group in
                for (batchOffset, pageIndex) in subBatchIndices.enumerated() {
                    let pageData = batchPageData[batchOffset]

                    group.addTask {
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
                    collected.append(result)
                }
                return collected
            }

            results.append(contentsOf: batchResults)
            // MEMORY-SAFE: batchPageData goes out of scope here, releasing CIImages
            // Only maxRenderConcurrency (3) page images were alive at once
            // At 360 DPI: 3 × 206 MB = ~618 MB peak vs previous 10 × 206 MB = 2+ GB
            } // end inner sub-batch (render-safe)
        } // end outer batch (progress reporting)

        // Sort results by page index and compute statistics
        results.sort { $0.pageIndex < $1.pageIndex }

        let pageTexts = results.map { $0.text }
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
    private func extractStructuredPDFContent(url: URL) async throws -> StructuredExtractionResult {
        let pdfDocument = try loadPDF(url: url, context: "Structured PDF")

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw DocumentProcessingError.emptyDocument
        }

        // Check if structured parsing is available (iOS 26+)
        if #available(iOS 26.0, *) {
            return try await extractWithStructuredParsing(pdfDocument: pdfDocument, pageCount: pageCount)
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
    private func extractWithStructuredParsing(pdfDocument: PDFDocument, pageCount: Int) async throws -> StructuredExtractionResult {
        let parser = StructuredDocumentParser.shared
        let layoutExtractor = LayoutAwareExtractor.shared

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
            let sampleIndices = pageCount <= 3
                ? Array(0..<pageCount)
                : [0, pageCount / 3, 2 * pageCount / 3]

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
        let pagesToAnalyze: [(PDFPage, Int)] = (0..<pageCount).compactMap { index in
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

        // Count pages that can skip Vision
        let skipVisionCount = complexityAnalyses.filter { $0.processingStrategy == .directText || $0.processingStrategy == .spatialText }.count
        let visionRequired = pageCount - skipVisionCount
        Log.info("[DocumentProcessor] 🚀 ADAPTIVE: \(skipVisionCount) pages skip Vision OCR, \(visionRequired) need layout detection", category: .ingestion)

        // MEMORY-SAFE RENDERING: Limit concurrent full-res page images.
        // At 360 DPI, each page = 6210×11040px ≈ 206 MB (opaque RGB).
        // Previous code rendered maxConcurrentPages (10) images = 2+ GB → OOM crash.
        // Now sub-batch: render pdfRenderingConcurrency (3) → analyze → OCR → release → next.
        // Quality is UNCHANGED: same 360 DPI, same preprocessing, same Vision accuracy.
        let maxRenderConcurrency = DeviceCapabilityService.shared.pdfRenderingConcurrency
        Log.info("[DocumentProcessor] Memory-safe Vision rendering: max \(maxRenderConcurrency) page images alive at once (~\(maxRenderConcurrency * 206) MB)", category: .ingestion)

        for batchStart in stride(from: 0, to: pageCount, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, pageCount)

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
                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        batchRenderData.append(PageRenderData(pageIndex: pageIndex, pageImage: nil, plainText: nil, layoutText: nil))
                        return
                    }

                    let pageNumber = pageIndex + 1
                    let complexity = pageComplexity[pageNumber]
                    let strategy = complexity?.processingStrategy ?? .enhancedOCR  // Safe default
                    // PHASE -1 override: garbled text layer → ALL pages need Vision OCR
                    let needsVision = documentTextLayerGarbled || strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR
                    let plainText = page.string
                    let hasText = (plainText?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 0
                    let requiresTableOCR = (complexity?.tablePresence ?? 0) > 0.2 || (complexity?.numericDensity ?? 0) > 0.3

                    traceIngestionDecision(
                        pageNumber: pageNumber,
                        strategy: documentTextLayerGarbled ? "garbled-force-ocr" : strategy.description,
                        hasText: hasText,
                        textQualityOK: !documentTextLayerGarbled && (complexity?.textQuality ?? 0) > 0.65,
                        requiresTableOCR: requiresTableOCR,
                        mode: documentTextLayerGarbled ? "structured-garbled-ocr" : "structured-hybrid"
                    )

                    // ADAPTIVE: Only render image if this page needs Vision layout detection
                    // Simple pages with good text skip image rendering entirely!
                    // PHASE -1 override: garbled text → ALWAYS render image for OCR
                    var pageImage: CIImage? = nil
                    if needsVision {
                        pageImage = renderPDFPageAsImage(page: page)
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
                        layoutText = extractTextWithSpatialOrdering(from: page) ?? text
                        Log.debug("[DocumentProcessor] Page \(pageNumber): Using PDFKit spatial extraction (skipped Vision)", category: .ingestion)
                    }

                    batchRenderData.append(PageRenderData(pageIndex: pageIndex, pageImage: pageImage, plainText: plainText, layoutText: layoutText))
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

                var layoutResults: [Int: String] = [:]
                await withTaskGroup(of: (Int, String).self) { group in
                    for (batchOffset, pageIndex) in subBatchIndices.enumerated() {
                        let renderData = batchRenderData[batchOffset]
                        // ADAPTIVE: Skip pages that already have layoutText (PDFKit extraction)
                        // Only run Vision on pages with images that need layout detection
                        guard let pageImage = renderData.pageImage, renderData.layoutText == nil else { continue }

                        group.addTask {
                            let pageNumber = pageIndex + 1
                            do {
                                let layoutText = try await layoutExtractor.extractForRAG(
                                    from: pageImage,
                                    nativeText: renderData.plainText,
                                    pageNumber: pageNumber
                                )
                                return (batchOffset, layoutText)
                            } catch {
                                Log.warning("[DocumentProcessor] Layout extraction failed for page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
                                return (batchOffset, renderData.plainText ?? "")
                            }
                        }
                    }

                    for await (offset, text) in group {
                        layoutResults[offset] = text
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
                    if let layoutText = layoutResults[i] {
                        let old = batchRenderData[i]
                        batchRenderData[i] = PageRenderData(
                            pageIndex: old.pageIndex,
                            pageImage: old.pageImage,
                            plainText: old.plainText,
                            layoutText: layoutText
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
                    let isHybridMode = useHybridMode  // Capture for sendable closure
                    let isGarbled = documentTextLayerGarbled  // Capture for sendable closure
                    // Gap 1 fix: capture customWords by value here (not via actor state on shared
                    // parser). If two documents ingest concurrently, setDocumentCustomWords() on
                    // the shared singleton clobbers vocabulary mid-parse for the first document.
                    // Capturing here binds this task to doc1's vocabulary regardless of doc2.
                    let capturedCustomWords = currentDocumentCustomWords

                    group.addTask {
                        let pageNumber = pageIndex + 1

                        // No page data available
                        guard let pageImage = renderData.pageImage else {
                            // PHASE -1: when text layer is garbled, don't use PDFKit fallback
                            if !isGarbled, let plainText = renderData.plainText, !plainText.isEmpty {
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "structured-skip-vision-native",
                                    chars: plainText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: [StructuredElementWrapper(
                                        text: plainText,
                                        elementType: "paragraph",
                                        pageNumber: pageNumber,
                                        isAtomicChunk: false
                                    )],
                                    pageText: plainText,
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
                            let structuredContent = try await parser.parsePageImage(pageImage, pageNumber: pageNumber, customWords: capturedCustomWords, nativeWordCount: nativeCount)

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

                            // HYBRID MODE: Use layout-aware text for paragraphs (correct column order)
                            // Keep Vision's tables, lists, titles (structural elements)
                            let layoutText = renderData.layoutText
                            var usedLayoutForParagraph = false

                            // Convert structured elements to wrappers and count types
                            for element in elementsToUse {
                                let isAtomic = element.elementType == "table"

                                // Count element types for live metrics
                                switch element.elementType {
                                case "table": pageTablesCount += 1
                                case "list": pageListsCount += 1
                                case "title": pageHeadersCount += 1
                                default: break
                                }

                                var entities: [(type: String, value: String)] = []
                                if case .table(let tableData) = element {
                                    entities = tableData.detectedEntities.map { ($0.type.rawValue, $0.value) }
                                }

                                // In hybrid mode: replace Vision paragraphs with layout-aware text
                                // This fixes multi-column reading order issues
                                if isHybridMode && element.elementType == "paragraph" {
                                    if !usedLayoutForParagraph, let layout = layoutText, !layout.isEmpty {
                                        // Use layout-aware text instead of Vision's paragraph
                                        elements.append(StructuredElementWrapper(
                                            text: layout.trimmingCharacters(in: .whitespacesAndNewlines),
                                            elementType: "paragraph",
                                            pageNumber: pageNumber,
                                            isAtomicChunk: false,
                                            detectedEntities: []
                                        ))
                                        usedLayoutForParagraph = true
                                    }
                                    continue  // Skip Vision's paragraph
                                }

                                elements.append(StructuredElementWrapper(
                                    text: element.textForEmbedding,
                                    elementType: element.elementType,
                                    pageNumber: element.pageNumber,
                                    isAtomicChunk: isAtomic,
                                    detectedEntities: entities
                                ))
                            }

                            // If hybrid mode but no paragraphs were in structured content, add layout text
                            if isHybridMode && !usedLayoutForParagraph, let layout = layoutText, !layout.isEmpty {
                                elements.append(StructuredElementWrapper(
                                    text: layout.trimmingCharacters(in: .whitespacesAndNewlines),
                                    elementType: "paragraph",
                                    pageNumber: pageNumber,
                                    isAtomicChunk: false,
                                    detectedEntities: []
                                ))
                            }

                            // Add figure references as searchable content
                            if !structuredContent.figureReferences.isEmpty {
                                let figureText = "[Visual Content on Page \(pageNumber)]\n" + structuredContent.figureReferences.joined(separator: "\n")
                                elements.append(StructuredElementWrapper(
                                    text: figureText,
                                    elementType: "figure",
                                    pageNumber: pageNumber,
                                    isAtomicChunk: true,
                                    detectedEntities: []
                                ))
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
                            } else if isHybridMode, let layout = layoutText, !layout.isEmpty {
                                pageTextOutput = layout
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

                            return PageParseResult(
                                pageIndex: pageIndex,
                                elements: elements,
                                pageText: pageTextOutput,
                                hasStructure: structuredContent.hasStructuredContent,
                                usedOCR: false,
                                tablesFound: pageTablesCount,
                                listsFound: pageListsCount,
                                headersFound: pageHeadersCount
                            )

                        } catch StructuredParsingError.noDocumentDetected {
                            // No document content - try OCR fallback
                            if let ocrText = try? await self.performOCR(on: pageImage), !ocrText.isEmpty {
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "structured-fallback-ocr",
                                    chars: ocrText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: [StructuredElementWrapper(
                                        text: ocrText,
                                        elementType: "paragraph",
                                        pageNumber: pageNumber,
                                        isAtomicChunk: false
                                    )],
                                    pageText: ocrText,
                                    hasStructure: false,
                                    usedOCR: true,
                                    tablesFound: 0,
                                    listsFound: 0,
                                    headersFound: 0
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
                            // Fallback to plain text — but NOT if text layer is garbled
                            if !isGarbled, let plainText = renderData.plainText, !plainText.isEmpty {
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "structured-error-fallback-native",
                                    chars: plainText.count
                                )
                                return PageParseResult(
                                    pageIndex: pageIndex,
                                    elements: [],
                                    pageText: plainText,
                                    hasStructure: false,
                                    usedOCR: false,
                                    tablesFound: 0,
                                    listsFound: 0,
                                    headersFound: 0
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
                    collected.append(result)
                }
                return collected
            }

            // Aggregate metrics from this sub-batch and emit live progress
            var batchTables = 0, batchLists = 0, batchHeaders = 0, batchOCR = 0
            for r in batchResults {
                batchTables += r.tablesFound
                batchLists += r.listsFound
                batchHeaders += r.headersFound
                if r.usedOCR { batchOCR += 1 }
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
        var pageTexts: [String] = []
        var pagesWithStructure = 0
        var ocrUsedCount = 0

        for result in results {
            allElements.append(contentsOf: result.elements)
            pageTexts.append(result.pageText)
            if result.hasStructure { pagesWithStructure += 1 }
            if result.usedOCR { ocrUsedCount += 1 }
        }

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
            usedStructuredParsing: pagesWithStructure > 0
        )
    }

    /// Create chunks that respect document structure (tables as atomic units, paragraphs chunked normally)
    /// Tables are kept as single chunks to preserve data integrity across any domain.
    private func createStructureAwareChunks(
        elements: [StructuredElementWrapper],
        fullText: String,
        config: SemanticChunker.ChunkingConfig,
        documentId: UUID,
        pageInfo: PageInfo
    ) -> [ProcessedChunk] {
        var chunks: [ProcessedChunk] = []
        var chunkIndex = 0

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
                pageNumbers: localPageRanges
            )

            for subChunk in subChunks {
                let metadata = ChunkMetadata(
                    chunkIndex: chunkIndex,
                    startPosition: subChunk.metadata.startOffset,
                    endPosition: subChunk.metadata.endOffset,
                    pageNumber: subChunk.metadata.pageNumber,
                    sectionTitle: subChunk.metadata.sectionTitle,
                    keywords: subChunk.metadata.topKeywords,
                    semanticDensity: subChunk.metadata.semanticDensity,
                    hasNumericData: subChunk.metadata.hasNumericData,
                    hasListStructure: subChunk.metadata.hasListStructure,
                    wordCount: subChunk.metadata.wordCount,
                    characterCount: subChunk.metadata.characterCount,
                    structureType: "paragraph",
                    sectionPath: subChunk.metadata.sectionPath.isEmpty ? nil : subChunk.metadata.sectionPath
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
                    // Build section path (max 3 levels)
                    if currentSectionPath.count >= 3 {
                        currentSectionPath.removeFirst()
                    }
                    currentSectionPath.append(titleText)
                } else {
                    Log.debug("[DocumentProcessor] Dropping garbled section title from path context", category: .ingestion)
                }
            }

            if element.isAtomicChunk {
                // Flush any pending paragraphs first
                flushParagraphBuffer()

                // Tables and important lists become single atomic chunks
                var text = OCRConfiguration.normalizeExtractedText(element.text)

                // Universal garbage filtering for atomic structured content.
                // This prevents OCR-corrupted rows/headers from becoming retrieval anchors.
                let (filteredAtomicText, removedAtomicLines) = OCRConfiguration.filterGarbageText(text)
                if removedAtomicLines > 0 {
                    Log.debug(
                        "[DocumentProcessor] Atomic \(element.elementType) cleanup removed \(removedAtomicLines) noisy lines",
                        category: .ingestion
                    )
                    text = filteredAtomicText
                }

                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                // UNIVERSAL: Prepend FULL section path to table for hierarchical context
                // Works for ANY domain: "Operating Materials > Engine Oil > Viscosity Grades"
                //                       "Medications > Dosing > Adult Dosage"
                //                       "Financial > Q4 2025 > Revenue Breakdown"
                var contextPrefix = ""
                if !currentSectionPath.isEmpty && element.elementType == "table" {
                    // Build full hierarchical path (e.g., "Section Path: Chapter > Topic > Subtopic")
                    let pathString = currentSectionPath.joined(separator: " > ")
                    contextPrefix = "Section Path: \(pathString)\n"
                    text = contextPrefix + text
                    Log.debug("[DocumentProcessor] Table with full path: \(pathString)", category: .ingestion)
                } else if let sectionTitle = currentSectionTitle,
                          element.elementType == "table",
                          sanitizeStructuredLabel(sectionTitle) != nil
                {
                    // Fallback to single section title if no path available
                    contextPrefix = "Section: \(sectionTitle)\n"
                    text = contextPrefix + text
                    Log.debug("[DocumentProcessor] Table with section: \(sectionTitle)", category: .ingestion)
                }

                let wordCount = text.split(separator: " ").count
                let metadata = ChunkMetadata(
                    chunkIndex: chunkIndex,
                    startPosition: 0,
                    endPosition: text.count,
                    pageNumber: element.pageNumber,
                    sectionTitle: currentSectionTitle,  // NOW carries section context
                    keywords: extractKeywordsFromStructuredElement(text, type: element.elementType),
                    semanticDensity: 0.8,  // Tables are very information-dense
                    hasNumericData: element.elementType == "table",
                    hasListStructure: element.elementType == "list",
                    wordCount: wordCount,
                    characterCount: text.count,
                    structureType: element.elementType,
                    sectionPath: currentSectionPath.isEmpty ? nil : currentSectionPath  // NOW carries section path
                )

                // Check if atomic chunk exceeds embedding token limit (~400 words ≈ 500 tokens)
                // If so, split into multiple chunks while preserving context prefix
                let maxAtomicWords = 380  // Leave room for context prefix in 510 token limit
                if wordCount > maxAtomicWords {
                    // Split oversized table/list into multiple chunks
                    let splitChunks = splitOversizedAtomicChunk(
                        text: text,
                        contextPrefix: contextPrefix,
                        element: element,
                        baseChunkIndex: chunkIndex,
                        sectionTitle: currentSectionTitle,
                        sectionPath: currentSectionPath,
                        maxWords: maxAtomicWords
                    )
                    chunks.append(contentsOf: splitChunks)
                    chunkIndex += splitChunks.count
                    Log.debug("[DocumentProcessor] Split oversized \(element.elementType) (\(wordCount)w) into \(splitChunks.count) chunks", category: .ingestion)
                } else {
                    chunks.append(ProcessedChunk(
                        text: text,
                        parentText: currentSectionTitle,  // Parent text is the section title
                        metadata: metadata
                    ))
                    chunkIndex += 1
                    Log.debug("[DocumentProcessor] Created atomic \(element.elementType) chunk (\(wordCount) words) from page \(element.pageNumber), section: \(currentSectionTitle ?? "none")", category: .ingestion)
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

        return candidate
    }

    /// Split an oversized atomic chunk (table/list) into multiple smaller chunks
    /// Preserves context prefix and section path on each chunk for retrieval coherence.
    /// For tables: repeats the header row at the top of each continuation chunk
    /// so that every chunk has column labels for its numeric values.
    private func splitOversizedAtomicChunk(
        text: String,
        contextPrefix: String,
        element: StructuredElementWrapper,
        baseChunkIndex: Int,
        sectionTitle: String?,
        sectionPath: [String],
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
                let totalWordCount = currentWordCount + headerWords
                let metadata = ChunkMetadata(
                    chunkIndex: baseChunkIndex + chunkNumber,
                    startPosition: 0,
                    endPosition: chunkContent.count,
                    pageNumber: element.pageNumber,
                    sectionTitle: sectionTitle,
                    keywords: extractKeywordsFromStructuredElement(chunkContent, type: element.elementType),
                    semanticDensity: 0.8,
                    hasNumericData: element.elementType == "table",
                    hasListStructure: element.elementType == "list",
                    wordCount: totalWordCount,
                    characterCount: chunkContent.count,
                    structureType: element.elementType,
                    sectionPath: sectionPath.isEmpty ? nil : sectionPath
                )
                chunks.append(ProcessedChunk(text: chunkContent, parentText: sectionTitle, metadata: metadata))
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
            let totalWordCount = currentWordCount + (chunkNumber > 0 ? headerWords : 0)
            let metadata = ChunkMetadata(
                chunkIndex: baseChunkIndex + chunkNumber,
                startPosition: 0,
                endPosition: chunkContent.count,
                pageNumber: element.pageNumber,
                sectionTitle: sectionTitle,
                keywords: extractKeywordsFromStructuredElement(chunkContent, type: element.elementType),
                semanticDensity: 0.8,
                hasNumericData: element.elementType == "table",
                hasListStructure: element.elementType == "list",
                wordCount: totalWordCount,
                characterCount: chunkContent.count,
                structureType: element.elementType,
                sectionPath: sectionPath.isEmpty ? nil : sectionPath
            )
            chunks.append(ProcessedChunk(text: chunkContent, parentText: sectionTitle, metadata: metadata))
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

    /// Count ACTUAL embedding tokens using BertTokenizer
    /// CRITICAL: NLTokenizer "word count" does NOT match BPE/WordPiece tokens!
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    /// Tables with abbreviations/codes can be 2-3x higher than word-based estimates
    private func countTokens(_ text: String) -> Int {
        if let tokenizer = embeddingTokenizer {
            let tokens = tokenizer.tokenize(text: text)
            return tokens.count + 2  // +2 for [CLS] and [SEP]
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
            sectionPath: parent.metadata.sectionPath
        )
        return ProcessedChunk(text: text, parentText: parent.parentText, metadata: metadata)
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

        // Also check character count as secondary metric
        let originalChars = original.filter { !$0.isWhitespace }.count
        let chunkChars = chunks.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
        // Account for overlap - chunks may duplicate some content
        let charRatio = originalChars > 0 ? Double(chunkChars) / Double(originalChars) * 100 : 100

        if coverage < 90 {
            let missing = originalWords.subtracting(chunkWords)
            let sampleMissing = Array(missing.prefix(10)).joined(separator: ", ")
            Log.warning(
                "[DocumentProcessor] ⚠️ LOW CONTENT COVERAGE: \(String(format: "%.1f", coverage))% of unique words captured " +
                "(\(covered)/\(total)). Missing samples: \(sampleMissing)...",
                category: .ingestion
            )
        } else {
            Log.debug(
                "[DocumentProcessor] ✅ Content coverage: \(String(format: "%.1f", coverage))% words, " +
                "\(String(format: "%.0f", charRatio))% chars (includes overlap)",
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

        // GPU-accelerated path: Use Metal-backed CIContext for image processing
        // This offloads sharpening/contrast enhancement to GPU
        if DeviceCapabilityService.shared.useGPUForPDFRendering {
            guard let ciImage = CIImage(image: uiImage) else { return nil }

            // Report GPU activity to HUD
            Task { @MainActor in
                HardwareTelemetryState.shared.reportGPUCompute(operation: .imageProcessing)
            }

            // Apply GPU-accelerated preprocessing for better OCR
            let processedImage = preprocessImageForOCR(ciImage)

            Log.debug("[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI) [GPU-accelerated]", category: .ingestion)
            return processedImage
        } else {
            Log.debug("[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI)", category: .ingestion)
            return CIImage(image: uiImage)
        }
        #elseif canImport(AppKit)
        guard scaledSize.width > 0 && scaledSize.height > 0 else { return nil }

        let image = NSImage(size: scaledSize)
        image.lockFocus()
        NSColor.white.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: scaledSize)).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: pageBounds.size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .cropBox, to: ctx)
            ctx.restoreGState()
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        if DeviceCapabilityService.shared.useGPUForPDFRendering {
            Log.debug("[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI) [GPU-accelerated]", category: .ingestion)
            return preprocessImageForOCR(ciImage)
        } else {
            Log.debug("[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI)", category: .ingestion)
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

            for pageIndex in batchStart..<batchEnd {
                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else { return }
                    let pageNumber = pageIndex + 1

                    let pageImages = extractImagesFromPDFPage(page: page)
                    for (image, bounds) in pageImages {
                        batchImages.append((image, pageNumber, bounds))
                    }
                }
            }

            // Skip if no images in this batch
            guard !batchImages.isEmpty else { continue }

            emitProgress(
                stage: "visual",
                detail: "🧠 Analyzing images (pages \(batchStart + 1)-\(batchEnd)/\(pageCount))...",
                page: batchEnd,
                totalPages: pageCount
            )

            // Analyze just this batch's images
            let emptyTextObs: [[VNRecognizedTextObservation]] = Array(repeating: [], count: batchEnd - batchStart)

            let (analyzedImages, _) = await ImageUnderstandingService.shared.analyzeDocumentImages(
                images: batchImages,
                textObservations: emptyTextObs
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
            detectedEntities: []
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

            let (analyzedImages, metadata) = await ImageUnderstandingService.shared.analyzeDocumentImages(
                images: extractedImages,
                textObservations: perPageTextObservations
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

        // Enumerate words and group into lines based on Y position
        let words = pageString.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var wordIndex = 0

        for word in words {
            let wordString = String(word)

            // Try to find this word in the page and get its bounds
            if let selection = page.selection(for: NSRange(location: wordIndex, length: wordString.count)),
               let firstChar = selection.selectionsByLine().first {

                let bounds = firstChar.bounds(for: page)

                // Check if this is a new line (Y position changed significantly)
                let yThreshold: CGFloat = bounds.height * 0.5
                let isNewLine = currentLineY >= 0 && abs(bounds.midY - currentLineY) > yThreshold

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
            }

            wordIndex += wordString.count + 1 // +1 for separator
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

        // If we couldn't get spatial info, fall back to simple extraction
        guard spatialLines.count > 3 else { return nil }

        // Detect columns from X positions
        let xPositions = spatialLines.map { $0.xPosition }
        let pageWidth = page.bounds(for: .cropBox).width
        let columnBoundaries = detectColumnBoundaries(from: xPositions, pageWidth: pageWidth)

        if columnBoundaries.isEmpty {
            // Single column - just sort by Y (top to bottom)
            let sorted = spatialLines.sorted { $0.yPosition > $1.yPosition }
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
            let sortedColumn = group.sorted { $0.yPosition > $1.yPosition }
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

    /// Extract text with awareness of multi-column layouts
    /// Groups observations by columns and processes each column top-to-bottom
    private func extractTextWithColumnAwareness(from observations: [VNRecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

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

    /// Extract text from code files - preserve syntax and structure
    private func extractTextFromCode(url: URL) throws -> String {
        // Try UTF-8 first (standard for code)
        if let code = try? String(contentsOf: url, encoding: .utf8) {
            return code
        }

        // Fallback to other encodings
        if let data = try? Data(contentsOf: url),
           let code = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii) {
            return code
        }

        throw DocumentProcessingError.unsupportedEncoding
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

        // Build structured text output
        var structuredText = ""

        // Header row
        if let header = rows.first {
            // Use parsed fields (handles quoted column names)
            structuredText += "Table with columns: " + header.joined(separator: ", ") + "\n\n"
        }

        // Process ALL data rows - ZERO DATA LOSS policy
        let totalRows = rows.count - 1
        if totalRows > 1000 {
            Log.info("[DocumentProcessor] Processing large CSV: \(totalRows) rows", category: .ingestion)
        }

        for i in 1..<rows.count {
            let values = rows[i]
            if !values.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                structuredText += "Row \(i): " + values.joined(separator: " | ") + "\n"
            }
        }

        return structuredText
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
        Log.warning("[DocumentProcessor] iWork document support is limited", category: .ingestion)
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
            // Process in reverse to preserve indices
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: processedXML) {
                    let tableXML = String(processedXML[matchRange])
                    let tableText = extractTableFromWordXML(tableXML)
                    let placeholder = "\n[[TABLE_\(tableTexts.count)]]\n"
                    tableTexts.append(tableText)
                    processedXML.replaceSubrange(matchRange, with: placeholder)
                }
            }
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

        // Format as pipe-separated table for better RAG readability
        guard !rows.isEmpty else { return "" }
        var output = ""
        for (i, row) in rows.enumerated() {
            output += "| " + row.joined(separator: " | ") + " |\n"
            if i == 0 {
                output += "|" + row.map { _ in " --- " }.joined(separator: "|") + "|\n"
            }
        }
        return output
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

    private func detectDocumentType(url: URL) -> DocumentType {
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
            return "iWork document support is limited. Please export as PDF or text for full compatibility."
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

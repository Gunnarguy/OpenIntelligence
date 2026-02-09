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

    // MARK: - GPU Acceleration

    /// Shared Metal device for GPU-accelerated image processing
    private static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Serial queue for GPU context access to prevent Metal synchronization issues
    /// CIContext is thread-safe for rendering, but concurrent Metal command buffer
    /// submissions during VNRecognizeTextRequest can cause race conditions
    private static let gpuQueue = DispatchQueue(label: "com.openintelligence.gpu-context", qos: .userInitiated)

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

    /// GPU-accelerated image preprocessing for improved OCR accuracy
    /// Applies sharpening and contrast enhancement using Metal-backed Core Image filters
    /// - Parameter image: Input CIImage from PDF rendering
    /// - Returns: Enhanced CIImage optimized for text recognition (eagerly rendered to prevent Metal races)
    private func preprocessImageForOCR(_ image: CIImage) -> CIImage {
        // Skip if GPU not available
        guard Self.metalDevice != nil else { return image }

        var processedImage = image

        // 1. Unsharp Mask - enhances text edges for better OCR
        if let unsharpMask = CIFilter(name: "CIUnsharpMask") {
            unsharpMask.setValue(processedImage, forKey: kCIInputImageKey)
            unsharpMask.setValue(0.5, forKey: kCIInputRadiusKey)     // Subtle sharpening
            unsharpMask.setValue(0.8, forKey: kCIInputIntensityKey)  // Moderate intensity
            if let output = unsharpMask.outputImage {
                processedImage = output
            }
        }

        // 2. Contrast boost - improves text/background separation
        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(processedImage, forKey: kCIInputImageKey)
            colorControls.setValue(1.05, forKey: kCIInputContrastKey)    // Slight boost
            colorControls.setValue(1.0, forKey: kCIInputSaturationKey)   // Preserve colors
            colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)   // No change
            if let output = colorControls.outputImage {
                processedImage = output
            }
        }

        let croppedImage = processedImage.cropped(to: image.extent)

        // CRITICAL: Eagerly render to CGImage using our controlled context
        // This prevents Metal command buffer race conditions when Vision
        // tries to render the lazy CIImage with its own Metal resources
        // The gpuQueue serializes access to prevent concurrent Metal submissions
        var renderedCGImage: CGImage?
        Self.gpuQueue.sync {
            renderedCGImage = Self.gpuContext.createCGImage(croppedImage, from: croppedImage.extent)
        }

        if let cgImage = renderedCGImage {
            return CIImage(cgImage: cgImage)
        }

        // Fallback to lazy evaluation if rendering fails
        return croppedImage
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

    init(targetChunkSize: Int = 350, chunkOverlap: Int = 60) {
        self.targetChunkSize = targetChunkSize
        self.chunkOverlap = chunkOverlap
        loadTokenizer()
    }

    /// Load BertTokenizer from embedding vocab for accurate token counting
    private func loadTokenizer() {
        if let url = Bundle.main.url(forResource: "embedding_vocab", withExtension: "json") {
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
        // Reset detected entities for this document
        lastDetectedEntities = []
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

        // CRITICAL: Store full original text for exact queries
        // This enables queries like "count word 'X' in all documents"
        // FTS5 (SQLite) is 10-100X faster than file-based storage for search
        if let containerId = containerId {
            // Primary path: SQLite FTS5 with container isolation (v1.1.0+)
            await SQLiteFullTextService.shared.store(text: extractedText, for: documentId, containerId: containerId)
            Log.debug("[DocumentProcessor] Stored full text (\(charCount) chars) to FTS5 for exact query support", category: .ingestion)
        } else {
            // Fallback path: File-based storage (legacy, no container context)
            await FullTextStorageService.shared.store(text: extractedText, for: documentId)
            Log.debug("[DocumentProcessor] Stored full text (\(charCount) chars) to file storage (legacy path)", category: .ingestion)
        }

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
                fullText: extractedText,
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
                extractedText,
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
    /// is completely different. We must detect this and fall back to OCR.
    private func isTextQualityAcceptable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            Log.debug("[DocumentProcessor] Text too short to assess quality (\(trimmed.count) chars)", category: .ingestion)
            return false
        }

        // === CHECK 1: Alphanumeric ratio (should be > 65%) ===
        // Garbage text often has many special characters, ligature placeholders, etc.
        let alphanumericCount = trimmed.filter { $0.isLetter || $0.isNumber }.count
        let alphanumericRatio = Double(alphanumericCount) / Double(trimmed.count)
        if alphanumericRatio < 0.60 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Low alphanumeric ratio: \(String(format: "%.1f", alphanumericRatio * 100))% (need 60%+)", category: .ingestion)
            return false
        }

        // === CHECK 2: Word length distribution ===
        // Garbage text often has very short or very long "words"
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3 else {
            Log.debug("[DocumentProcessor] ❌ FAIL: Too few words to assess (\(words.count))", category: .ingestion)
            return false
        }

        let avgWordLength = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        if avgWordLength < 2.5 || avgWordLength > 18.0 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Abnormal avg word length: \(String(format: "%.1f", avgWordLength))", category: .ingestion)
            return false
        }

        // === CHECK 3: Gibberish detector (consecutive non-letter sequences) ===
        let consecutiveNonLetterPattern = try? NSRegularExpression(pattern: "[^a-zA-Z0-9\\s]{4,}", options: [])
        let gibberishMatches = consecutiveNonLetterPattern?.numberOfMatches(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) ?? 0
        let gibberishRatio = Double(gibberishMatches) / Double(max(1, trimmed.count / 80))
        if gibberishRatio > 2.5 {
            Log.debug("[DocumentProcessor] ❌ FAIL: High gibberish ratio: \(String(format: "%.1f", gibberishRatio))", category: .ingestion)
            return false
        }

        // === CHECK 4: Vowel/consonant balance ===
        // Real English text has ~38% vowels, garbage is often wildly different
        let letters = trimmed.lowercased().filter { $0.isLetter }
        let vowels = letters.filter { "aeiou".contains($0) }
        let vowelRatio = Double(vowels.count) / Double(max(1, letters.count))
        if vowelRatio < 0.15 || vowelRatio > 0.65 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Abnormal vowel ratio: \(String(format: "%.1f", vowelRatio * 100))% (need 15-65%)", category: .ingestion)
            return false
        }

        // === CHECK 5: Character entropy (randomness detection) ===
        // Real text has lower entropy than random garbage
        let entropy = calculateCharacterEntropy(trimmed)
        if entropy > 5.5 {  // English text is typically 4.0-5.0 bits/char
            Log.debug("[DocumentProcessor] ❌ FAIL: High entropy (random-looking): \(String(format: "%.2f", entropy)) bits/char", category: .ingestion)
            return false
        }

        // === CHECK 6: Common English words ===
        // At least some common words should be present
        let commonPatterns = ["the ", "and ", "is ", "to ", "of ", "a ", "in ", "for ", "that ", "with ", "this ", "are ", "be ", "at ", "or "]
        let matchCount = commonPatterns.filter { trimmed.lowercased().contains($0) }.count
        let hasEnoughCommonWords = matchCount >= 2

        // If no common words AND metrics are borderline, prefer OCR
        if !hasEnoughCommonWords && (alphanumericRatio < 0.70 || vowelRatio < 0.25 || vowelRatio > 0.50) {
            Log.debug("[DocumentProcessor] ❌ FAIL: Only \(matchCount) common words found + borderline metrics", category: .ingestion)
            return false
        }

        // === CHECK 7: Sample the text for diagnostic logging ===
        let sampleLength = min(100, trimmed.count)
        let sample = String(trimmed.prefix(sampleLength)).replacingOccurrences(of: "\n", with: "↵")
        Log.debug("[DocumentProcessor] ✓ PASS: Text quality OK (alpha=\(String(format: "%.0f", alphanumericRatio * 100))%, vowel=\(String(format: "%.0f", vowelRatio * 100))%, entropy=\(String(format: "%.1f", entropy)), words=\(matchCount)) Sample: \"\(sample)...\"", category: .ingestion)

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
            "^\\(\\d+\\)$"                      // "(5)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }

        return false
    }

    /// Extract text from PDF with page tracking for semantic chunking
    /// Uses spatial-aware extraction to handle multi-column layouts correctly
    /// ADAPTIVE OCR: Pre-scans pages to classify complexity, skips OCR for simple pages
    private func extractTextFromPDFWithPages(url: URL) async throws -> (text: String, pageInfo: PageInfo) {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] PDF load failed: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

        let pageCount = pdfDocument.pageCount
        Log.debug("[DocumentProcessor] PDF pages: \(pageCount)", category: .ingestion)

        // Edge case: Empty PDF
        guard pageCount > 0 else {
            Log.warning("[DocumentProcessor] PDF has zero pages", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
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
        }

        // Parallel extraction using TaskGroup with controlled concurrency
        var results: [PageExtractionResult] = []

        // Process pages in batches to control memory pressure
        for batchStart in stride(from: 0, to: pageCount, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, pageCount)
            let batchIndices = batchStart..<batchEnd

            // MEMORY OPTIMIZATION: Render only this batch's pages
            // GPU ACCELERATION: Apply preprocessing filters for better OCR accuracy
            // ADAPTIVE OCR: Only render images for pages that need OCR based on complexity analysis
            var batchPageData: [PageData] = []
            for pageIndex in batchIndices {
                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        batchPageData.append(PageData(pageIndex: pageIndex, pageString: nil, pageImage: nil, hasText: false, textQualityOK: false))
                        return
                    }

                    let pageNumber = pageIndex + 1
                    let complexity = pageComplexity[pageNumber]
                    let strategy = complexity?.processingStrategy ?? .enhancedOCR  // Default to safe

                    let pageString = page.string

                    // ADAPTIVE: Only render image if this page actually needs OCR
                    // Simple pages (.directText, .spatialText) skip expensive image rendering entirely!
                    var pageImage: CIImage? = nil
                    if strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR {
                        // Complex page - render and preprocess image
                        pageImage = renderPDFPageAsImage(page: page)
                        if let image = pageImage {
                            pageImage = preprocessImageForOCR(image)
                        }
                    }
                    // else: Skip image rendering - saves ~50-100ms per simple page!

                    // Pre-compute text presence and quality checks
                    let hasText = pageString != nil && !pageString!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let textQualityOK = hasText && isTextQualityAcceptable(pageString!)

                    // For pages with good text quality, also try spatial extraction synchronously
                    var effectiveString = pageString
                    if hasText && textQualityOK {
                        if let spatialText = extractTextWithSpatialOrdering(from: page), !spatialText.isEmpty {
                            effectiveString = spatialText
                        }
                    }

                    batchPageData.append(PageData(pageIndex: pageIndex, pageString: effectiveString, pageImage: pageImage, hasText: hasText, textQualityOK: textQualityOK))
                }
            }

            let batchResults = await withTaskGroup(of: PageExtractionResult.self) { group in
                for (batchOffset, pageIndex) in batchIndices.enumerated() {
                    let pageData = batchPageData[batchOffset]

                    group.addTask {
                        let pageStartTime = Date()
                        let pageNumber = pageIndex + 1

                        let pageText = pageData.pageString
                        // Use pre-computed values to avoid MainActor calls
                        let hasText = pageData.hasText
                        let textQualityOK = pageData.textQualityOK

                        if hasText && textQualityOK {
                            // Good text layer - use it (spatial extraction already applied above)
                            let isSpatial = pageText != pageData.pageString  // Changed means spatial was used
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount)")
                            }
                            let pageTime = Date().timeIntervalSince(pageStartTime)
                            let method = isSpatial ? "spatial" : "text"
                            Log.debug("   ✓ Page \(pageNumber): \(pageText!.count) chars (\(method), \(String(format: "%.2f", pageTime))s)", category: .ingestion)

                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: pageText!,
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
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: pageText!,
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
            // MEMORY OPTIMIZATION: batchPageData goes out of scope here, releasing CIImages
            // This keeps peak memory to ~36MB (4 pages) instead of ~4.8GB (542 pages)
        }

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

        // PASS 3: Assemble final text with page mappings
        var fullText = ""
        var pageTextRanges: PageTextMapping = [:]

        for (index, cleanedText) in cleanedPageTexts.enumerated() {
            let pageNumber = index + 1
            let pageStartIndex = fullText.endIndex

            if !cleanedText.isEmpty {
                fullText += cleanedText + "\n\n"
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
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] PDF load failed for structured parsing: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

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

        // Check if this is a digital PDF with good native text
        let useHybridMode = pdfHasGoodNativeText(pdfDocument)
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

        for batchStart in stride(from: 0, to: pageCount, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, pageCount)
            let batchIndices = batchStart..<batchEnd

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

            // MEMORY OPTIMIZATION: Render only this batch's pages (not all pages upfront)
            // This keeps peak memory to ~27MB (3 pages) instead of ~4.8GB (542 pages)
            // GPU ACCELERATION: Apply preprocessing filters for better OCR accuracy
            // ADAPTIVE: Only render images for pages that need Vision layout detection

            // Emit GPU rendering progress
            let gpuActive = DeviceCapabilityService.shared.useGPUForPDFRendering
            let gpuLabel = gpuActive ? "[Metal GPU]" : "[CPU]"
            await MainActor.run {
                self.emitProgress(
                    stage: "render",
                    detail: "🎨 \(gpuLabel) Rendering pages \(batchStart + 1)-\(batchEnd)/\(pageCount)",
                    page: batchStart,
                    totalPages: pageCount
                )
            }

            var batchRenderData: [PageRenderData] = []
            for pageIndex in batchIndices {
                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        batchRenderData.append(PageRenderData(pageIndex: pageIndex, pageImage: nil, plainText: nil, layoutText: nil))
                        return
                    }

                    let pageNumber = pageIndex + 1
                    let complexity = pageComplexity[pageNumber]
                    let strategy = complexity?.processingStrategy ?? .enhancedOCR  // Safe default
                    let needsVision = strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR

                    // ADAPTIVE: Only render image if this page needs Vision layout detection
                    // Simple pages with good text skip image rendering entirely!
                    var pageImage: CIImage? = nil
                    if needsVision {
                        pageImage = renderPDFPageAsImage(page: page)
                        if let image = pageImage {
                            pageImage = preprocessImageForOCR(image)
                        }
                    }

                    let plainText = page.string

                    // For simple pages, try spatial extraction right away
                    var layoutText: String? = nil
                    if !needsVision, let text = plainText, !text.isEmpty {
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
                    for (batchOffset, pageIndex) in batchIndices.enumerated() {
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
                for (batchOffset, pageIndex) in batchIndices.enumerated() {
                    let renderData = batchRenderData[batchOffset]
                    let isHybridMode = useHybridMode  // Capture for sendable closure

                    group.addTask {
                        let pageNumber = pageIndex + 1

                        // No page data available
                        guard let pageImage = renderData.pageImage else {
                            if let plainText = renderData.plainText, !plainText.isEmpty {
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
                            return PageParseResult(pageIndex: pageIndex, elements: [], pageText: "", hasStructure: false, usedOCR: false, tablesFound: 0, listsFound: 0, headersFound: 0)
                        }

                        do {
                            // MAXIMUM QUALITY: Run full Vision structured parsing for tables/lists/headers
                            let structuredContent = try await parser.parsePageImage(pageImage, pageNumber: pageNumber)

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

                            // Use layout text for pageText in hybrid mode (correct column order)
                            let pageTextOutput = (isHybridMode && layoutText != nil && !layoutText!.isEmpty)
                                ? layoutText!
                                : structuredContent.rawText

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
                            return PageParseResult(pageIndex: pageIndex, elements: [], pageText: "", hasStructure: false, usedOCR: false, tablesFound: 0, listsFound: 0, headersFound: 0)

                        } catch {
                            Log.warning("[DocumentProcessor] Structured parsing failed for page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
                            // Fallback to plain text
                            if let plainText = renderData.plainText, !plainText.isEmpty {
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

            // Aggregate metrics from this batch and emit live progress
            var batchTables = 0, batchLists = 0, batchHeaders = 0, batchOCR = 0
            for r in batchResults {
                batchTables += r.tablesFound
                batchLists += r.listsFound
                batchHeaders += r.headersFound
                if r.usedOCR { batchOCR += 1 }
            }
            incrementMetric(tables: batchTables, lists: batchLists, headers: batchHeaders, ocrPages: batchOCR)

            // Emit updated progress with accumulated metrics
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

            results.append(contentsOf: batchResults)

            // MEMORY OPTIMIZATION: Clear batch render data to release CIImages
            // This allows ARC to reclaim ~27MB per batch before the next batch loads
            // batchRenderData goes out of scope here, releasing the images
        }

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
                fullText += cleanedText + "\n\n"
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
                let titleText = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
                currentSectionTitle = titleText
                // Build section path (max 3 levels)
                if currentSectionPath.count >= 3 {
                    currentSectionPath.removeFirst()
                }
                currentSectionPath.append(titleText)
            }

            if element.isAtomicChunk {
                // Flush any pending paragraphs first
                flushParagraphBuffer()

                // Tables and important lists become single atomic chunks
                var text = element.text
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
                } else if let sectionTitle = currentSectionTitle, element.elementType == "table" {
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
                paragraphBuffer.append((text: element.text, page: element.pageNumber))
            } else {
                // Lists that aren't atomic get buffered too
                paragraphBuffer.append((text: element.text, page: element.pageNumber))
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

    /// Split an oversized atomic chunk (table/list) into multiple smaller chunks
    /// Preserves context prefix and section path on each chunk for retrieval coherence
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

        var currentChunkLines: [String] = []
        var currentWordCount = 0
        var chunkNumber = 0

        for line in lines {
            let lineWords = line.split(separator: " ").count

            // If adding this line would exceed limit, flush current chunk
            if currentWordCount + lineWords > maxWords && !currentChunkLines.isEmpty {
                let chunkContent = contextPrefix + "[Part \(chunkNumber + 1)]\n" + currentChunkLines.joined(separator: "\n")
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
                    wordCount: currentWordCount,
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
            let chunkContent = contextPrefix + (chunkNumber > 0 ? "[Part \(chunkNumber + 1)]\n" : "") + currentChunkLines.joined(separator: "\n")
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
                wordCount: currentWordCount,
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
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] PDF load failed: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

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
            let hasText = pageText != nil && !pageText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let textQualityOK = hasText && isTextQualityAcceptable(pageText!)

            if hasText && textQualityOK {
                progressHandler?("page \(pageIndex + 1)/\(pageCount)")
                await Task.yield()

                fullText += pageText! + "\n\n"

                let pageTime = Date().timeIntervalSince(pageStartTime)
                Log.debug("   ✓ Page \(pageIndex + 1): \(pageText!.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
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
                    fullText += pageText! + "\n\n"
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
    private func renderPDFPageAsImage(page: PDFPage, scale: CGFloat = 5.0) -> CIImage? {
        let pageBounds = page.bounds(for: .mediaBox)

        // Scale up for maximum OCR accuracy - Vision needs high DPI images
        // PDF pages are typically 72 DPI, so 5x = 360 DPI (maximum quality for text recognition)
        // This captures fine print, subscripts, small labels that 216 DPI misses
        let scaledSize = CGSize(
            width: pageBounds.size.width * scale,
            height: pageBounds.size.height * scale
        )

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

            // Scale up the PDF rendering
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: 0, y: pageBounds.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: context.cgContext)
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
            page.draw(with: .mediaBox, to: ctx)
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

        // MEMORY OPTIMIZATION: Process images in batches to avoid OOM on large PDFs
        // Previous implementation loaded ALL images (100+ pages × 48MB = 5GB+) before analysis
        // Now we process in batches of 20 pages, keeping memory under ~960MB for images
        let imageBatchSize = 20
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
    /// 2. Full-page scans (pages without extractable text)
    /// 3. Vision rectangle detection (find image regions via computer vision)
    /// Returns array of (image, bounds) tuples where bounds are normalized coordinates
    private func extractImagesFromPDFPage(page: PDFPage) -> [(image: CIImage, bounds: CGRect)] {
        var extractedImages: [(CIImage, CGRect)] = []
        let pageBounds = page.bounds(for: .mediaBox)

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

        // Strategy 2: If page has no extractable text but renders as image,
        // the whole page might be a scanned image or diagram
        let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if pageText.isEmpty {
            if let fullPageImage = renderPDFPageAsImage(page: page) {
                let normalizedBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                extractedImages.append((fullPageImage, normalizedBounds))
            }
        }

        // Strategy 3: Look for pages with minimal text that might be mostly diagrams
        // If page has less than 100 characters but isn't empty, it's likely mostly visual
        else if pageText.count < 100 {
            if let fullPageImage = renderPDFPageAsImage(page: page) {
                // Render at lower scale since we're just checking for visual content
                let normalizedBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                extractedImages.append((fullPageImage, normalizedBounds))
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
                context.cgContext.translateBy(x: -region.minX, y: region.maxY - page.bounds(for: .mediaBox).height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)

                page.draw(with: .mediaBox, to: context.cgContext)
            }
            return CIImage(image: image)
        #else
            return nil
        #endif
    }

    /// Extract images from entire PDF document with page tracking
    func extractAllImagesFromPDF(url: URL) async -> [(image: CIImage, pageNumber: Int, bounds: CGRect)] {
        guard let pdfDocument = PDFDocument(url: url) else {
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

        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentProcessingError.pdfLoadFailed
        }

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
            // Cap total image text to avoid overwhelming document/context budgets
            let maxImageTextPerDoc = 3000  // ~2 chunks worth of image descriptions max
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

        // Convert CIImage to CGImage using GPU-accelerated context with serial queue
        var cgImageResult: CGImage?
        Self.gpuQueue.sync {
            cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        }
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

            // === BULLETPROOF OCR CONFIGURATION (same as performOCR) ===
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]
            request.minimumTextHeight = 0.0
            // Note: customWords left empty - Vision's language correction handles domain terms
            // Adding domain-specific words here would make the app less universal

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
        // Convert CIImage to CGImage using GPU-accelerated context with serial queue
        var cgImageResult: CGImage?
        Self.gpuQueue.sync {
            cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        }
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

            // === BULLETPROOF OCR CONFIGURATION ===

            // Use latest Vision revision for best accuracy
            request.revision = VNRecognizeTextRequestRevision3

            // Maximum accuracy mode (uses neural network)
            request.recognitionLevel = .accurate

            // Enable language correction (NLP post-processing)
            request.usesLanguageCorrection = true

            // Automatically detect language (iOS 16+)
            // This is better than hardcoded language list for mixed-language docs
            request.automaticallyDetectsLanguage = true

            // Prioritize English but support many languages
            // Order matters - first language is preferred
            request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]

            // Capture small text (important for footnotes, table cells, diagrams)
            // 0.0 = detect all text regardless of size (relative to image height)
            request.minimumTextHeight = 0.0

            // Note: customWords left empty - Vision's language correction handles domain terms
            // Adding domain-specific words here would make the app less universal

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
        // Convert CIImage to CGImage using GPU-accelerated context with serial queue
        var cgImageResult: CGImage?
        Self.gpuQueue.sync {
            cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        }
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

            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]
            request.minimumTextHeight = 0.0

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
        let pageWidth = page.bounds(for: .mediaBox).width
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
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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

        // Sort each column top-to-bottom and extract text
        var allText: [String] = []
        for (index, group) in columnGroups.enumerated() {
            let sortedGroup = group.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let columnText = sortedGroup.compactMap { $0.topCandidates(1).first?.string }

            if !columnText.isEmpty {
                Log.debug("[DocumentProcessor] Column \(index + 1): \(columnText.count) text blocks", category: .ingestion)
                allText.append(contentsOf: columnText)
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
                        let textRows = tableRows.map { row in
                            row.compactMap { $0.topCandidates(1).first?.string }
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

    /// Extract text from CSV - convert to structured readable format
    private func extractTextFromCSV(url: URL) throws -> String {
        let csvContent = try String(contentsOf: url, encoding: .utf8)
        let lines = csvContent.components(separatedBy: .newlines)

        guard !lines.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        // Parse CSV and convert to readable format
        var structuredText = ""

        // Detect delimiter (comma or tab)
        let delimiter = lines.first?.contains("\t") == true ? "\t" : ","

        // Process header
        if let header = lines.first {
            let headers = header.components(separatedBy: delimiter)
            structuredText += "Table with columns: " + headers.joined(separator: ", ") + "\n\n"
        }

        // Process ALL rows - ZERO DATA LOSS policy
        // CSV files must be fully ingested regardless of size
        let totalRows = lines.count - 1
        if totalRows > 1000 {
            Log.info("[DocumentProcessor] Processing large CSV: \(totalRows) rows", category: .ingestion)
        }

        for i in 1..<lines.count {
            let row = lines[i]
            if !row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let values = row.components(separatedBy: delimiter)
                structuredText += "Row \(i): " + values.joined(separator: " | ") + "\n"
            }
        }

        return structuredText
    }

    // MARK: - Audio/Video Transcription

    /// Extract text from audio/video files using Speech.framework
    private func extractTextFromAudioVideo(url: URL) async throws -> String {
        let transcriptionService = AudioTranscriptionService.shared

        // Check authorization first
        let authorized = await transcriptionService.checkAuthorization()
        if !authorized {
            Log.warning("[DocumentProcessor] Speech recognition not authorized; requesting permission", category: .ingestion)
            try await transcriptionService.requestAuthorization()
        }

        // Detect language from filename or default to English
        let filename = url.lastPathComponent.lowercased()
        var language: NLLanguage = .english

        // Simple language hints from filename
        if filename.contains("_es") || filename.contains("spanish") {
            language = .spanish
        } else if filename.contains("_fr") || filename.contains("french") {
            language = .french
        } else if filename.contains("_de") || filename.contains("german") {
            language = .german
        } else if filename.contains("_zh") || filename.contains("chinese") {
            language = .simplifiedChinese
        } else if filename.contains("_ja") || filename.contains("japanese") {
            language = .japanese
        }

        progressHandler?("transcribing audio")

        do {
            let result = try await transcriptionService.transcribe(url: url, language: language)

            if result.isSuccessful {
                Log.info("[DocumentProcessor] Transcribed \(result.wordCount) words from \(url.lastPathComponent)", category: .ingestion)
                return transcriptionService.transcriptionToDocument(result, sourceFile: url.lastPathComponent)
            } else {
                throw DocumentProcessingError.audioTranscriptionEmpty
            }
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
            // Also check for headers/footers
            for i in 1...10 {
                if let headerXML = archive.extractString(path: "word/header\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(headerXML)
                }
                if let footerXML = archive.extractString(path: "word/footer\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(footerXML)
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
            // PowerPoint: slides contain text
            for i in 1...500 {
                if let slideXML = archive.extractString(path: "ppt/slides/slide\(i).xml") {
                    extractedText += extractTextFromPowerPointSlide(slideXML)
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

    /// Extract text from Word XML (removes tags, preserves structure)
    private func extractTextFromWordXML(_ xml: String) -> String {
        // Word uses <w:t> tags for text, <w:p> for paragraphs
        var text = xml

        // Replace paragraph breaks with newlines
        text = text.replacingOccurrences(of: "</w:p>", with: "\n")

        // Replace soft breaks
        text = text.replacingOccurrences(of: "<w:br/>", with: "\n")
        text = text.replacingOccurrences(of: "<w:br />", with: "\n")

        // Extract text from <w:t> tags
        // Pattern: <w:t>content</w:t> or <w:t xml:space="preserve">content</w:t>
        let pattern = #"<w:t[^>]*>([^<]*)</w:t>"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            var extractedParts: [String] = []

            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let match = match, let contentRange = Range(match.range(at: 1), in: text) {
                    extractedParts.append(String(text[contentRange]))
                }
            }

            return extractedParts.joined()
        }

        // Fallback: strip all XML tags
        return text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Extract shared strings from Excel (these are referenced by index in sheets)
    private func extractSharedStringsFromExcel(_ xml: String) -> [String] {
        var strings: [String] = []

        // Pattern: <t>content</t> within <si> elements
        let pattern = #"<si>.*?<t[^>]*>([^<]*)</t>.*?</si>"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(xml.startIndex..., in: xml)
            regex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
                if let match = match, let contentRange = Range(match.range(at: 1), in: xml) {
                    strings.append(String(xml[contentRange]))
                }
            }
        }

        return strings
    }

    /// Extract text from Excel worksheet, using shared strings for cell values
    private func extractTextFromExcelSheet(_ xml: String, sharedStrings: [String]) -> String {
        var rows: [[String]] = []
        var currentRow: [String] = []

        // Pattern for cells: <c r="A1" t="s"><v>0</v></c> (t="s" means shared string index)
        // or <c r="A1"><v>123</v></c> for numbers
        let rowPattern = #"<row[^>]*>(.*?)</row>"#
        let cellPattern = #"<c[^>]*(?:t="([^"]*)")?[^>]*><v>([^<]*)</v></c>"#

        if let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
           let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: []) {

            let range = NSRange(xml.startIndex..., in: xml)
            rowRegex.enumerateMatches(in: xml, options: [], range: range) { rowMatch, _, _ in
                if let rowMatch = rowMatch, let rowContentRange = Range(rowMatch.range(at: 1), in: xml) {
                    let rowContent = String(xml[rowContentRange])
                    currentRow = []

                    let cellRange = NSRange(rowContent.startIndex..., in: rowContent)
                    cellRegex.enumerateMatches(in: rowContent, options: [], range: cellRange) { cellMatch, _, _ in
                        if let cellMatch = cellMatch {
                            let typeRange = Range(cellMatch.range(at: 1), in: rowContent)
                            let valueRange = Range(cellMatch.range(at: 2), in: rowContent)

                            if let valueRange = valueRange {
                                let value = String(rowContent[valueRange])
                                let cellType = typeRange.map { String(rowContent[$0]) }

                                if cellType == "s", let index = Int(value), index < sharedStrings.count {
                                    currentRow.append(sharedStrings[index])
                                } else {
                                    currentRow.append(value)
                                }
                            }
                        }
                    }

                    if !currentRow.isEmpty {
                        rows.append(currentRow)
                    }
                }
            }
        }

        // Format as tab-separated values (like CSV but cleaner for RAG)
        return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// Extract text from PowerPoint slide XML
    private func extractTextFromPowerPointSlide(_ xml: String) -> String {
        let text = xml

        // PowerPoint uses <a:t> tags for text
        let pattern = #"<a:t>([^<]*)</a:t>"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            var extractedParts: [String] = []

            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let match = match, let contentRange = Range(match.range(at: 1), in: text) {
                    let content = String(text[contentRange])
                    if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                        extractedParts.append(content)
                    }
                }
            }

            return extractedParts.joined(separator: " ")
        }

        // Fallback
        return text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported document format"
        case .pdfLoadFailed:
            return "Failed to load PDF document"
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

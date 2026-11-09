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
    /// The number of words in `text`, split at spaces, tabs and line breaks (5.7). Through 5.6 the
    /// Words figure split at spaces only, so two words either side of a line break counted as one and
    /// a document's count read low (row "Word counts look wrong and ingested text may be truncated").
    nonisolated static func wordCount(of text: String) -> Int {
        // The same count without a substring for every word (5.7).
        IngestionStageLedger.wordCount(of: text)
    }

    /// `IngestionStageLedger.counts(of:)` off the main actor (5.7). Counted on it, the four
    /// recordings of an import held the main thread for about 1.7 s on 8 MB of text on an M3 Pro.
    @concurrent
    nonisolated static func ledgerCounts(_ texts: [String]) async
        -> (characters: Int, words: Int, uniformLengths: Bool)
    {
        IngestionStageLedger.counts(of: texts)
    }

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
    static let gpuQueue = DispatchQueue(
        label: "com.openintelligence.gpu-context",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// GPU-accelerated CIContext for image operations (PDF rendering, OCR prep)
    /// Using Metal backend provides 5-10x speedup over CPU for image processing
    static let gpuContext: CIContext = {
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

    /// The 99th minus the 1st percentile of the image's luminance (0 to 1), from a 64-bin CIAreaHistogram of a
    /// downscaled copy; nil when it cannot be measured.
    static func brightnessSpread(of image: CIImage) -> Double? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite else { return nil }
        let scale = min(1, 512 / max(extent.width, extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let gray = small.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        let bins = 64
        let histogram = gray.applyingFilter(
            "CIAreaHistogram",
            parameters: [kCIInputExtentKey: CIVector(cgRect: gray.extent), "inputCount": bins, "inputScale": 1.0])
        var data = [Float](repeating: 0, count: bins * 4)
        Self.gpuContext.render(
            histogram, toBitmap: &data, rowBytes: bins * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: bins, height: 1), format: .RGBAf, colorSpace: nil)
        let counts = (0..<bins).map { Double(data[$0 * 4]) }
        let total = counts.reduce(0, +)
        guard total > 0 else { return nil }
        func percentile(_ p: Double) -> Double {
            var running = 0.0
            for (index, count) in counts.enumerated() {
                running += count
                if running >= p * total { return (Double(index) + 0.5) / Double(bins) }
            }
            return 1
        }
        // The 1st and 99th percentiles: on a clean page with little ink the 5th is still paper, so the spread read near 0
        // and a clean page was stretched (refuting review, 2026-11-08).
        return percentile(0.99) - percentile(0.01)
    }

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
    func preprocessImageForOCR(
        _ image: CIImage,
        textQuality: Double = 0.7,
        hasNativeTextLayer: Bool = true,
        isScanned: Bool = false
    ) -> CIImage {
        // Skip if GPU not available
        guard Self.metalDevice != nil else { return image }

        // A faded page without a text layer: stretch its contrast and drop colour, nothing else (5.8). Measured on this
        // Mac on 2026-11-08 on a degraded synthetic scan: words read 0.01 untouched, 0.41 with CIColorControls contrast 1.8
        // and saturation 0, 0.11 binarized; Liebl and Burghardt 2020 (arXiv 2008.02777) found grayscale beats binarized
        // input for OCR. Gated on the 1st-to-99th percentile brightness spanning under half the range.
        // `OI_SCAN_CONTRAST=off` in the environment turns it off, to compare on one build.
        if !hasNativeTextLayer, ProcessInfo.processInfo.environment["OI_SCAN_CONTRAST"] != "off",
            let spread = Self.brightnessSpread(of: image), spread < 0.5,
            let filter = CIFilter(name: "CIColorControls")
        {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(1.8, forKey: kCIInputContrastKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            if let output = filter.outputImage?.cropped(to: image.extent),
                let cg = Self.gpuContext.createCGImage(output, from: output.extent)
            {
                Log.info("[DocumentProcessor] Faded page (brightness spread \(String(format: "%.2f", spread))): contrast stretched", category: .ingestion)
                return CIImage(cgImage: cg)
            }
        }

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

    func traceIngestionDecision(
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

    nonisolated func traceIngestionOutcome(
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

    nonisolated func preferredOCRRenderScale(
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

    /// Whether a page is read from its own text layer because most of that layer's letters are in a script Vision's
    /// text recognition has no model for, such as Greek or Hebrew. Vision would read other letters there, and the
    /// layout and structure passes take their text from Vision (a Greek page imported as Cyrillic and Latin junk,
    /// measured 2026-10-19). Not for a page the classifier marks as a scan with a text layer over part of it
    /// (`isMixedModeScanned`): its text layer may be a header or a stamp, and the scanned body needs Vision (review,
    /// 2026-10-19). Not when the document's text layer was judged a cipher.
    nonisolated static func readsTextLayerVisionCannotRead(
        _ pageText: String?, complexity: PageComplexityAnalysis?, documentTextLayerGarbled: Bool
    ) -> Bool {
        guard !documentTextLayerGarbled, !(complexity?.isMixedModeScanned ?? false), let pageText else { return false }
        return !OCRConfiguration.visionCanReadMostOf(pageText)
    }

    func shouldForceVisionForAdaptiveRecovery(
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

    func shouldPreferHighResolutionStructure(
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
    struct StructuredExtractionResult {
        let text: String
        let pageInfo: PageInfo
        let structuredElements: [StructuredElementWrapper]  // Tables, lists with metadata
        let usedStructuredParsing: Bool
    }

    /// Wrapper to hold structured elements with page info (works on all iOS versions)
    /// Sendable struct with nonisolated init to allow construction in TaskGroup
    struct StructuredElementWrapper: Sendable {
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
        /// The running header and footer lines the parser's margin rule left out of this element's page (5.8). Not
        /// text of the element: the cross-page running-line rule counts them as printed on the page, so a header the
        /// margin rule removed on some pages is still seen to repeat and is removed on the pages it missed.
        var marginalLines: [String] = []

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

    struct RegionCropRescuePayload: Sendable {
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
    var liveMetrics = ExtractionProgress(stage: "idle", detail: "", currentPage: nil, totalPages: nil)

    /// A text of fewer bytes than this cannot hold more words than `SemanticChunker.maxChunks`
    /// chunks of `safeMaxSize` words can (a word and what separates it from the next take two
    /// bytes at the least), so the early word count is skipped for it. About 31 MB.
    nonisolated static let largeTextWordCountBytes =
        SemanticChunker.maxChunks * SemanticChunker.ChunkingConfig.safeMaxSize * 2

    /// How many off-main chunker runs this processor is waiting on; see `reportChunkingProgress`.
    /// A count and not a flag: the engine uses one processor for every import, and a second
    /// import can start while the first is still chunking.
    var chunkingRunsInFlight = 0
    private var lastChunkingPercentShown = -1

    /// Vision-detected entities from last document processing (reset on each call)
    /// Contains emails, phone numbers, URLs, dates, etc. extracted via DataDetection
    var lastDetectedEntities: [(type: String, value: String)] = []

    /// How much of a document's text Apple's detector reads for entities (5.7): about a second on
    /// the Mac, off the main actor.
    static let textEntityCharacterLimit = 1_000_000

    /// Adds entities found in the text to the ones found in table cells, leaving out repeats.
    func mergeDetectedEntities(_ found: [DetectedEntity]) {
        guard !found.isEmpty else { return }
        var seen = Set(lastDetectedEntities.map { "\($0.type)|\($0.value)" })
        for entity in found {
            let key = "\(entity.type.rawValue)|\(entity.value)"
            guard seen.insert(key).inserted else { continue }
            lastDetectedEntities.append((type: entity.type.rawValue, value: entity.value))
        }
    }

    /// Tokenizer for accurate token counting (matches embedding model tokenization)
    /// CRITICAL: NLTokenizer word count ≠ Tokenizer tokens for technical content
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    var embeddingTokenizer: Tokenizer?

    /// Dynamic custom words for the current document being processed.
    /// Extracted from PDFKit's text layer BEFORE Vision OCR runs, so Vision
    /// knows the document's domain vocabulary ("document teaches Vision").
    /// Reset on each processDocument() call.
    var currentDocumentCustomWords: [String] = OCRConfiguration.universalCustomWords

    /// The languages this document is known to contain, narrowed from the full recognition list by
    /// `OCRConfiguration.narrowedRecognitionLanguages(matching:)`. `nil` means not narrowed: keep all of
    /// `OCRConfiguration.recognitionLanguages` and let Vision detect. Per-document state, so it
    /// resets with the rest of it.
    var currentDocumentRecognitionLanguages: [String]?

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
    ///
    /// `legacy: false` leaves the string handler out when a rich handler is installed. The engine
    /// files the string handler's text under Extracting and the rich handler's "chunking" under
    /// Chunking, so one status sent to both moves the queue item between two stages, and every
    /// stage change is a haptic, a saved queue and a Live Activity update. A status repeated
    /// through a stage goes to the rich handler alone.
    func emitProgress(
        stage: String, detail: String, page: Int? = nil, totalPages: Int? = nil, legacy: Bool = true
    ) {
        // Update simple handler (legacy)
        if legacy || richProgressHandler == nil {
            progressHandler?(detail)
        }

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

    /// Shows where the chunker is. The chunker calls back from the concurrent pool every 25
    /// chunks and each call hops here, so a report can arrive after chunking has returned or
    /// behind a later one; both are dropped.
    func reportChunkingProgress(_ progress: SemanticChunker.ChunkingProgress) {
        guard chunkingRunsInFlight > 0 else { return }
        switch progress.phase {
        case .findingStructure:
            lastChunkingPercentShown = -1
            emitProgress(stage: "chunking", detail: "✂️ Reading the text's structure...", legacy: false)
        case .cuttingChunks:
            // The chunker reports every 25 chunks. The status changes when the percentage does,
            // so a document of any length gives at most 101 of these.
            let percent = Self.chunkingPercent(progress.fractionOfText)
            guard percent > lastChunkingPercentShown else { return }
            lastChunkingPercentShown = percent
            emitProgress(
                stage: "chunking",
                detail: Self.chunkingProgressText(
                    chunksCreated: progress.chunksCreated, fractionOfText: progress.fractionOfText),
                legacy: false)
        case .finishing:
            emitProgress(
                stage: "chunking",
                detail: "✂️ Finishing \(Self.passageCountText(progress.chunksCreated))...",
                legacy: false)
        }
    }

    nonisolated static func chunkingPercent(_ fractionOfText: Double) -> Int {
        Int((min(1, max(0, fractionOfText)) * 100).rounded(.down))
    }

    nonisolated static func passageCountText(_ count: Int) -> String {
        count == 1 ? "1 passage" : "\(count.formatted(.number)) passages"
    }

    /// "✂️ Chunking 42% (1,250 passages)". The share is of the text, which is known; the final
    /// number of passages is not known until the last one is cut.
    nonisolated static func chunkingProgressText(chunksCreated: Int, fractionOfText: Double) -> String {
        "✂️ Chunking \(chunkingPercent(fractionOfText))% (\(passageCountText(chunksCreated)))"
    }

    /// `OCRConfiguration.normalizeExtractedText` on the concurrent pool instead of the main actor.
    @concurrent
    nonisolated static func normalizeOffMainActor(
        _ text: String,
        profile: OCRConfiguration.TextNormalizationProfile
    ) async -> String {
        OCRConfiguration.normalizeExtractedText(text, profile: profile)
    }

    /// Increment a metric and emit progress
    func incrementMetric(tables: Int = 0, lists: Int = 0, headers: Int = 0, ocrPages: Int = 0, words: Int = 0) {
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
    func resetLiveMetrics(usingVision: Bool = false, totalPages: Int? = nil) {
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
        case "json", "jsonc", "jsonl", "ndjson":
            // JSON Lines shares `.json`: the type is stored in each document record, and a new case
            // would not decode on an older build reading the same library.
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
    /// The text needs more passages than one document may have (`SemanticChunker.maxChunks`).
    case tooManyPassages(limit: Int)

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
        case let .tooManyPassages(limit):
            return "This file is too long to import in one piece. It needs more than \(limit.formatted(.number)) passages, which is the most one document can have. Split it into smaller files and import those."
        }
    }
}



// MARK: - The keyword index's text and page rows for one document or one batch (5.7)

extension DocumentProcessor {
    /// Stores a document's text and its page rows, or, when `append` is set, one batch of a PDF
    /// imported in batches. Returns how many page rows the document has after it.
    ///
    /// An appended batch's text store clears all of the document's page rows
    /// (`SQLiteFullTextService.store` calls `delete(for:)`, which removes them), and through 5.6
    /// `storePages(append: true)` then added only the current batch, so a PDF over 10 MB, imported
    /// fifteen pages at a time, kept page rows for its last batch (backlog row
    /// 3f549a74d54f8178ad55d3d273cc832a). The rows the batches before this one stored are read first
    /// and stored again with this batch's; a page this batch stores again (an import resumed from
    /// its checkpoint) is kept once, as this batch has it. The fix is here and not in the store,
    /// which is a protected file. Its cost grows with the square of the page count, as the
    /// appended text's own store already does.
    @discardableResult
    nonisolated static func storeText(
        _ text: String, pages: [(pageNumber: Int, content: String)], for documentId: UUID, containerId: UUID,
        append: Bool
    ) async -> Int {
        let earlier = append ? await SQLiteFullTextService.shared.retrieveAllPages(for: documentId) : []
        await SQLiteFullTextService.shared.store(text: text, for: documentId, containerId: containerId, append: append)
        let rows = pageRows(keeping: earlier, adding: pages)
        guard !rows.isEmpty else { return 0 }
        await SQLiteFullTextService.shared.storePages(pages: rows, for: documentId, containerId: containerId, append: append)
        return rows.count
    }

    /// A PDF's text split at its page breaks, each page with its number. A page with no text gets
    /// no page break (both PDF extractors insert one only before a page that has text), so the
    /// n-th piece is the n-th page that has text. Its number is the n-th of `pagesWithText`, the
    /// pages that had text counted from 1 within the batch, moved by `firstPageIndex`, the batch's
    /// first page counted from 0. Through 5.6 the number was the piece's place, so every page after
    /// a blank one was stored as the page before it (5.7). When the counts differ, which neither
    /// extractor produces, the place is used, as before.
    nonisolated static func numberedPages(
        splitting text: String, separator: String, pagesWithText: [Int], firstPageIndex: Int
    ) -> [(pageNumber: Int, content: String)] {
        let pieces = text.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard pagesWithText.count == pieces.count else {
            return pieces.filter { !$0.isEmpty }.enumerated().map { (firstPageIndex + $0.offset + 1, $0.element) }
        }
        return zip(pagesWithText, pieces).compactMap { number, content in
            content.isEmpty ? nil : (firstPageIndex + number, content)
        }
    }

    /// The earlier rows without the pages the batch brings, then the batch's, in page order.
    nonisolated static func pageRows(
        keeping earlier: [(pageNumber: Int, content: String)], adding batch: [(pageNumber: Int, content: String)]
    ) -> [(pageNumber: Int, content: String)] {
        let renewed = Set(batch.map(\.pageNumber))
        return (earlier.filter { !renewed.contains($0.pageNumber) } + batch).sorted { $0.pageNumber < $1.pageNumber }
    }
}

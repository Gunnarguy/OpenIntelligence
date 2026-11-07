//
//  DocumentProcessor+StructuredParsing.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved from DocumentProcessor.swift on 2026-11-05 (5.8 split); only access keywords changed.
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
    // MARK: - Structured Document Parsing (iOS 26+)

    /// Extract PDF content with structure awareness (tables, lists, paragraphs as separate elements)
    /// On iOS 26+, uses Vision's RecognizeDocumentsRequest for structure-aware parsing.
    /// This preserves tabular data integrity - specs in one table won't mix with unrelated data.
    func extractStructuredPDFContent(url: URL, pageRange: ClosedRange<Int>? = nil) async throws -> StructuredExtractionResult {
        let pdfDocument = try loadPDF(url: url, context: "Structured PDF")

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw DocumentProcessingError.emptyDocument
        }

        // Detect the document language BEFORE the version branch.
        //
        // This was originally added inside `extractTextFromPDFWithPages`, which is only the
        // pre-26 fallback below — so on every shipping OS it never ran. Verified against a live
        // trace on 2026-08-29: `OCR languages narrowed` appeared zero times. Both branches need it,
        // so it belongs here.
        await detectDocumentRecognitionLanguagesIfNeeded(pdfDocument: pdfDocument, pageCount: pageCount)

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
            var unreadableSampleSeen = false

            for idx in sampleIndices {
                guard let page = pdfDocument.page(at: idx) else { continue }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // OCR can check a text layer only in a script it reads. Vision has no model for Greek, Hebrew and
                // many other scripts, so on such a page it returns other letters, the two share no word, and through
                // 5.6 a correct text layer was judged a cipher: every page went to OCR and the garbage filter emptied
                // what OCR gave (measured 2026-10-19, a Greek page imported with no text). Such a page is not a
                // sample; a page of the same document in a script Vision reads still is (review, 2026-10-19).
                guard OCRConfiguration.visionCanReadMostOf(text) else {
                    if text.count >= 50 { unreadableSampleSeen = true }
                    continue
                }
                if text.count > bestSampleText.count {
                    bestSampleText = text
                    bestSamplePage = page
                }
            }

            // No text layer at all → not garbled, just needs OCR
            guard bestSampleText.count >= 50, let samplePage = bestSamplePage else {
                documentTextLayerGarbled = false
                if unreadableSampleSeen {
                    Log.info("[DocumentProcessor] [iOS26] Text layer kept without an OCR check: the sampled pages' letters are mostly in a script Vision's text recognition does not read", category: .ingestion)
                } else {
                    Log.debug("[DocumentProcessor] [iOS26] Text layer validation: no/minimal text layer, skipping", category: .ingestion)
                }
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
        let pageComplexity = await prescanPageComplexity(endPageIdx: endPageIdx, startPageIdx: startPageIdx, checkpointDir: checkpointDir, pdfDocument: pdfDocument, pageCount: pageCount, documentTextLayerGarbled: documentTextLayerGarbled)

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

            // Rendering progress. Through 5.6 the line said "[Metal GPU]" whenever the GPU rendering
            // setting was on and "[ANE]" for the Vision steps below, as fixed text: neither was a
            // measurement of where the work ran (row "PDF page renders are logged as GPU-accelerated on
            // a macOS path whose expensive stages run on CPU"), so the lines name the step only (5.7).
            await MainActor.run {
                self.emitProgress(
                    stage: "render",
                    detail: "🎨 Rendering pages \(renderStart + 1)-\(renderEnd)/\(pageCount)",
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
                    
                    loadCheckpointedPage(pageIndex: pageIndex, checkpoint: checkpoint, results: &results, batchRenderData: &batchRenderData)
                    continue
                }

                renderPageForParsing(pageIndex: pageIndex, pdfDocument: pdfDocument, batchRenderData: &batchRenderData, pageComplexity: pageComplexity, documentTextLayerGarbled: documentTextLayerGarbled)
            }

            // LAYOUT-AWARE EXTRACTION: Only for pages that need Vision
            // Simple pages already have layoutText from PDFKit above
            // This properly handles multi-column layouts by detecting columns spatially
            let pagesNeedingVision = batchRenderData.filter { $0.pageImage != nil && $0.layoutText == nil }
            if useHybridMode && !pagesNeedingVision.isEmpty {
                // Emit layout extraction progress. Vision chooses the hardware it runs on.
                await MainActor.run {
                    self.emitProgress(
                        stage: "layout",
                        detail: "📐 Detecting columns for \(pagesNeedingVision.count) complex pages",
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

            let batchResults = await parseSubBatchStructure(batchEnd: batchEnd, batchStart: batchStart, pageCount: pageCount, subBatchIndices: subBatchIndices, batchRenderData: batchRenderData, useHybridMode: useHybridMode, documentTextLayerGarbled: documentTextLayerGarbled, pageComplexity: pageComplexity, parser: parser)

            try Task.checkCancellation()

            recordParsedBatch(batchResults: batchResults, checkpointDir: checkpointDir)

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

        return await assembleStructuredExtractionResult(results: &results, pageCount: pageCount, pdfDocument: pdfDocument)
    }

    /// Step A9: reports structure progress and parses every page of a sub-batch concurrently (one task per page), returning each page's elements, text and counts.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func parseSubBatchStructure(batchEnd: Int, batchStart: Int, pageCount: Int, subBatchIndices: Range<Int>, batchRenderData: [DocumentProcessor.PageRenderData], useHybridMode: Bool, documentTextLayerGarbled: Bool, pageComplexity: [Int : PageComplexityAnalysis], parser: StructuredDocumentParser) async -> [DocumentProcessor.PageParseResult] {
        // Emit structured extraction progress. Vision chooses the hardware it runs on.
        await MainActor.run {
            self.emitProgress(
                stage: "structure",
                detail: "🔍 Tables/lists \(batchStart + 1)-\(batchEnd)/\(pageCount)",
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
                // Captured alongside the vocabulary for the same reason: these run concurrently
                // and must not read actor state that a later document could have replaced.
                let capturedLanguages = currentDocumentRecognitionLanguages
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
                            recognitionLanguages: capturedLanguages,
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
        return batchResults
    }

    /// Step A7 (checkpoint): turns a page saved by an interrupted import back into its parse result and metrics, and appends the placeholder render record that keeps the sub-batch's indexes aligned.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func loadCheckpointedPage(pageIndex: Int, checkpoint: DocumentProcessor.IngestionCheckpointPage, results: inout [DocumentProcessor.PageParseResult], batchRenderData: inout [DocumentProcessor.PageRenderData]) {
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
    }

    /// Step A7 (render): renders one page at its complexity's scale (or keeps its text layer when Vision is not needed) inside an autorelease pool and appends its render record.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func renderPageForParsing(pageIndex: Int, pdfDocument: PDFDocument, batchRenderData: inout [DocumentProcessor.PageRenderData], pageComplexity: [Int : PageComplexityAnalysis], documentTextLayerGarbled: Bool) {
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
            let plainText = page.string
            let textLayerUnreadableByVision = Self.readsTextLayerVisionCannotRead(
                plainText, complexity: complexity, documentTextLayerGarbled: documentTextLayerGarbled)
            if textLayerUnreadableByVision {
                Log.info("[DocumentProcessor] Page \(pageNumber): read from its text layer, whose script Vision's text recognition does not read", category: .ingestion)
            }
            // PHASE -1 override: garbled text layer → ALL pages need Vision OCR
            let needsVision = !textLayerUnreadableByVision
                && (documentTextLayerGarbled || fidelityForcesVision || strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR)
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
                    : textLayerUnreadableByVision
                        ? "text-layer, script Vision does not read"
                        : (fidelityForcesVision && strategy == .spatialText ? "\(strategy.description)+fidelity" : strategy.description),
                hasText: hasText,
                textQualityOK: textLayerUnreadableByVision
                    || (!documentTextLayerGarbled && (complexity?.textQuality ?? 0) > 0.65),
                requiresTableOCR: requiresTableOCR && !textLayerUnreadableByVision,
                mode: documentTextLayerGarbled
                    ? "structured-garbled-ocr"
                    : textLayerUnreadableByVision
                        ? "structured-text-layer"
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
                // A right-to-left page read from its text layer keeps PDFKit's order: the spatial reading
                // orders a line's words left to right (`spatialLineBreak`).
                let keepsPDFKitOrder = textLayerUnreadableByVision && OCRConfiguration.isMostlyRightToLeft(text)
                let spatial = keepsPDFKitOrder ? nil : extractTextWithSpatialOrdering(from: page)
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

    /// Step A4: measures each page that has no checkpoint for layout complexity, so simple pages skip Vision, and logs how many need it.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func prescanPageComplexity(endPageIdx: Int, startPageIdx: Int, checkpointDir: URL, pdfDocument: PDFDocument, pageCount: Int, documentTextLayerGarbled: Bool) async -> [Int : PageComplexityAnalysis] {
        let complexityStartTime = Date()
        // A page with a checkpoint is loaded from it below and never rendered, so it is not analysed either (5.7):
        // a resumed 913-page import on the owner's iPhone re-scanned every page first (24 s) before loading 568 saved
        // ones.
        let pagesToAnalyze: [(PDFPage, Int)] = (startPageIdx...endPageIdx).compactMap { index in
            let saved = checkpointDir.appendingPathComponent("page_\(index).json")
            guard !FileManager.default.fileExists(atPath: saved.path),
                let page = pdfDocument.page(at: index)
            else { return nil }
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
            return (baseSkip && !shouldForceVisionForAdaptiveRecovery(
                analysis: analysis,
                strategy: strategy,
                documentTextLayerGarbled: documentTextLayerGarbled
            )) || Self.readsTextLayerVisionCannotRead(
                pdfDocument.page(at: analysis.pageNumber - 1)?.string, complexity: analysis,
                documentTextLayerGarbled: documentTextLayerGarbled)
        }.count
        let visionRequired = pageCount - skipVisionCount
        Log.info("[DocumentProcessor] 🚀 ADAPTIVE: \(skipVisionCount) pages skip Vision OCR, \(visionRequired) need layout detection", category: .ingestion)
        return pageComplexity
    }

    /// Step A10: counts a sub-batch's tables, lists, headers and OCR pages, saves each page's checkpoint, and adds the counts to the live metrics.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func recordParsedBatch(batchResults: [DocumentProcessor.PageParseResult], checkpointDir: URL) {
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
    }

    /// Steps A11 to A13: sorts the parsed pages, flattens them into elements and page texts, adds the embedded-image analysis, and assembles the result.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func assembleStructuredExtractionResult(results: inout [DocumentProcessor.PageParseResult], pageCount: Int, pdfDocument: PDFDocument) async -> StructuredExtractionResult {
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
    func createStructureAwareChunks(
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

    func classifyDocumentCategory(
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
                .map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
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

    nonisolated func inferredHeaders(for tableData: TableData) -> [String] {
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

    nonisolated func dataRows(for tableData: TableData) -> [[String]] {
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

    /// Cleans each chunk's section title and path. A label is cleaned once and remembered for
    /// the rest of the call: the chunks of one section carry the same title and path, and
    /// cleaning one runs text cleanup, language detection and the heading test. The loop lets
    /// the main actor go every 50 chunks. As one uninterrupted `map`, with a new language
    /// recognizer for every label, this held the main actor for 14 s on a 2 MB piece of a JSON
    /// Lines file (3,019 chunks; a sample of the run on 2026-10-09 showed all of it here).
    func sanitizeProcessedChunkMetadata(_ chunks: [ProcessedChunk]) async -> [ProcessedChunk] {
        var cleanedLabels: [String: String?] = [:]
        func cleanedLabel(_ raw: String) -> String? {
            if let known = cleanedLabels[raw] { return known }
            let cleaned = sanitizeStructuredLabel(raw)
            cleanedLabels[raw] = cleaned
            return cleaned
        }

        var result: [ProcessedChunk] = []
        result.reserveCapacity(chunks.count)
        for (offset, chunk) in chunks.enumerated() {
            if offset > 0, offset % 50 == 0 { await Task.yield() }
            result.append(sanitizedChunk(chunk, cleanedLabel: cleanedLabel))
        }
        return result
    }

    private func sanitizedChunk(_ chunk: ProcessedChunk, cleanedLabel: (String) -> String?) -> ProcessedChunk {
        let cleanedSectionTitle = chunk.metadata.sectionTitle.flatMap { cleanedLabel($0) }
        // As `sanitizedSectionPath`, with the remembered labels.
        let cleanedSectionPath = (chunk.metadata.sectionPath ?? []).reduce(into: [String]()) { path, component in
            guard let cleaned = cleanedLabel(component) else { return }
            guard path.last?.caseInsensitiveCompare(cleaned) != .orderedSame else { return }
            path.append(cleaned)
        }

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

}

// MARK: - Page records for extractWithStructuredParsing

// Declared inside `extractWithStructuredParsing` until 2026-11-06; moved here unchanged so the steps it was
// broken into can name them.
extension DocumentProcessor {
    private struct PageRenderData: Sendable {
        let pageIndex: Int
        let pageImage: CIImage?
        let plainText: String?
        let layoutText: String?  // Layout-aware extracted text
        let layoutTables: [TableRegion]
        let preferHighResolutionStructure: Bool
    }

    // Result container for parallel processing
    private struct PageParseResult: Sendable {
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
}

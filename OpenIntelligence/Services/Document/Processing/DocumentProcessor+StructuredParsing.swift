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
        let documentTextLayerGarbled = await validateDocumentTextLayer(endPageIdx: endPageIdx, startPageIdx: startPageIdx, pdfDocument: pdfDocument, pageCount: pageCount)

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

            // Emit rich progress with current metrics. `page` is the pages finished so far (5.8): this said
            // `batchEnd`, so a PDF that fits one batch reported its extraction done before any page was read.
            await MainActor.run {
                self.emitProgress(
                    stage: "vision",
                    detail: useHybridMode
                        ? "🔬 Max quality parsing pages \(batchStart + 1)-\(batchEnd)/\(pageCount)"
                        : "👁 Vision parsing pages \(batchStart + 1)-\(batchEnd)/\(pageCount)",
                    page: batchStart,
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
            try await parseSubBatch(pageCount: pageCount, renderEnd: renderEnd, renderStart: renderStart, subBatchIndices: subBatchIndices, checkpointDir: checkpointDir, results: &results, documentTextLayerGarbled: documentTextLayerGarbled, pageComplexity: pageComplexity, pdfDocument: pdfDocument, batchEnd: batchEnd, batchStart: batchStart, layoutExtractor: layoutExtractor, useHybridMode: useHybridMode, parser: parser)
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

    /// Step A6: takes one sub-batch of pages through render (or checkpoint load), layout detection, structured parsing and its checkpoints, and adds its results.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func parseSubBatch(pageCount: Int, renderEnd: Int, renderStart: Int, subBatchIndices: Range<Int>, checkpointDir: URL, results: inout [DocumentProcessor.PageParseResult], documentTextLayerGarbled: Bool, pageComplexity: [Int : PageComplexityAnalysis], pdfDocument: PDFDocument, batchEnd: Int, batchStart: Int, layoutExtractor: LayoutAwareExtractor, useHybridMode: Bool, parser: StructuredDocumentParser) async throws {
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

        await detectSubBatchLayouts(batchRenderData: &batchRenderData, useHybridMode: useHybridMode, batchStart: batchStart, pageCount: pageCount, subBatchIndices: subBatchIndices, layoutExtractor: layoutExtractor, batchEnd: batchEnd)

        let batchResults = await parseSubBatchStructure(batchEnd: batchEnd, batchStart: batchStart, pageCount: pageCount, subBatchIndices: subBatchIndices, batchRenderData: batchRenderData, useHybridMode: useHybridMode, documentTextLayerGarbled: documentTextLayerGarbled, pageComplexity: pageComplexity, parser: parser)

        try Task.checkCancellation()

        recordParsedBatch(batchResults: batchResults, checkpointDir: checkpointDir)

        results.append(contentsOf: batchResults)
    }

    /// Step A1: decides once per document whether its text layer is garbled (a font-substitution cipher) by reading a sample page with OCR and comparing the two.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func validateDocumentTextLayer(endPageIdx: Int, startPageIdx: Int, pdfDocument: PDFDocument, pageCount: Int) async -> Bool {
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
        return documentTextLayerGarbled
    }

    /// Step A8: in hybrid mode, detects columns and tables on the sub-batch's pages that need Vision, concurrently, and merges the reading-order text into their render records.
    /// Moved unchanged from `extractWithStructuredParsing` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    @available(iOS 26.0, *)
    private func detectSubBatchLayouts(batchRenderData: inout [DocumentProcessor.PageRenderData], useHybridMode: Bool, batchStart: Int, pageCount: Int, subBatchIndices: Range<Int>, layoutExtractor: LayoutAwareExtractor, batchEnd: Int) async {
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
                    page: subBatchIndices.lowerBound,
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
                    page: subBatchIndices.lowerBound,
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
                page: subBatchIndices.lowerBound,
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
                // Each page as it finishes (5.8). Every report during a batch named the batch's first page, so
                // the progress the system's background task showed stayed put through the whole extraction: 4%
                // for 71 s while nine of ten pages were read on the owner's iPhone (2026-11-07), and iOS ended the
                // task. A task that shows little progress is the one iOS ends first ("Performing long-running
                // tasks on iOS and iPadOS"). Rich handler only, so the queue item keeps its stage.
                let finishedPages = subBatchIndices.lowerBound + collected.count
                await MainActor.run {
                    self.emitProgress(
                        stage: "structure",
                        detail: "🔍 Page \(finishedPages)/\(pageCount) read",
                        page: finishedPages,
                        totalPages: pageCount,
                        legacy: false
                    )
                }
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

//
//  DocumentProcessor+ImagesAndOCR.swift
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
    // MARK: - Embedded Image Analysis (Visual Understanding)

    /// Analyze embedded images in PDF pages and create searchable chunks
    /// Uses ImageUnderstandingService for classification, OCR, and AI description
    /// Returns StructuredElementWrapper entries for each analyzed image
    @available(iOS 26.0, *)
    func analyzeEmbeddedImages(pdfDocument: PDFDocument, pageCount: Int) async -> [StructuredElementWrapper] {
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
            // Stays on `VNRecognizeTextRequest` (5.7). Scanned pages are read by `RecognizeDocumentsRequest`
            // (`StructuredDocumentParser`); this is one of the older request's remaining uses, which move to Vision's Swift
            // `RecognizeTextRequest` together, checked against the OCR fixtures in IngestionFormatCoverageTests, not one
            // at a time (roadmap row "Vision: DataDetection results are computed and thrown away, and VisionKit is never
            // imported").
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
            OCRConfiguration.configureRequest(request, customWords: self.currentDocumentCustomWords, languages: self.currentDocumentRecognitionLanguages)

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
    func extractTextFromRTF(url: URL) throws -> String {
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
    func extractTextFromImage(url: URL) async throws -> String {
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
    func performOCR(on image: CIImage) async throws -> String {
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
            // Stays on `VNRecognizeTextRequest` (5.7). Scanned pages are read by `RecognizeDocumentsRequest`
            // (`StructuredDocumentParser`); this is one of the older request's remaining uses, which move to Vision's Swift
            // `RecognizeTextRequest` together, checked against the OCR fixtures in IngestionFormatCoverageTests, not one
            // at a time (roadmap row "Vision: DataDetection results are computed and thrown away, and VisionKit is never
            // imported").
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
            OCRConfiguration.configureRequest(request, customWords: self.currentDocumentCustomWords, languages: self.currentDocumentRecognitionLanguages)

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
    func performEnhancedSpatialOCR(on image: CIImage, pageNumber: Int) async throws -> (text: String, analysis: SpatialPageAnalysis?) {
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
    func performOCRWithObservationsAsync(on image: CIImage) async throws -> [VNRecognizedTextObservation] {
        // Convert CIImage to CGImage using GPU-accelerated context (CIContext is thread-safe)
        let cgImageResult = Self.gpuContext.createCGImage(image, from: image.extent)
        guard let cgImage = cgImageResult else {
            throw NSError(domain: "DocumentProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage for OCR"])
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            // Stays on `VNRecognizeTextRequest` (5.7). Scanned pages are read by `RecognizeDocumentsRequest`
            // (`StructuredDocumentParser`); this is one of the older request's remaining uses, which move to Vision's Swift
            // `RecognizeTextRequest` together, checked against the OCR fixtures in IngestionFormatCoverageTests, not one
            // at a time (roadmap row "Vision: DataDetection results are computed and thrown away, and VisionKit is never
            // imported").
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
            OCRConfiguration.configureRequest(request, customWords: self.currentDocumentCustomWords, languages: self.currentDocumentRecognitionLanguages)

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

}

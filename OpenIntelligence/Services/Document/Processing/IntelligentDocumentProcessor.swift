//
//  IntelligentDocumentProcessor.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/24/26.
//
//  Orchestrates Apple CoreML vision models for intelligent document processing
//  Pipeline: Classify → Detect Regions → Extract per-region → Structure-aware chunking
//
//  Uses:
//  - FastViT T8: Content type classification (8.2MB)
//  - DETR ResNet50: Semantic region detection (43MB)
//  - Vision OCR: Text extraction per-region
//

import CoreImage
import Foundation
import NaturalLanguage
import PDFKit
import Vision

// MARK: - Intelligent Processing Result

/// Complete result of intelligent document analysis
struct IntelligentProcessingResult: Sendable {
    let classification: DocumentClassificationResult
    let regions: [RegionDetectionResult]     // Per-page regions
    let structuredContent: StructuredDocumentContent
    let processingMetrics: IntelligentProcessingMetrics
}

/// Extracted content organized by structure
struct StructuredDocumentContent: Sendable {
    let textBlocks: [ExtractedTextBlock]
    let tables: [ExtractedTable]
    let figures: [ExtractedFigure]
    let lists: [ExtractedList]
    let metadata: DocumentStructureMetadata
}

struct ExtractedTextBlock: Sendable, Identifiable {
    let id = UUID()
    let pageNumber: Int
    let text: String
    let boundingBox: CGRect
    let isHeader: Bool
    let isFooter: Bool
    let confidence: Float
}

struct ExtractedTable: Sendable, Identifiable {
    let id = UUID()
    let pageNumber: Int
    let rows: [[String]]
    let boundingBox: CGRect
    let hasHeader: Bool
    let caption: String?
}

struct ExtractedFigure: Sendable, Identifiable {
    let id = UUID()
    let pageNumber: Int
    let boundingBox: CGRect
    let caption: String?
    let classification: String?     // From FastViT/Vision
    let description: String?        // AI-generated description
}

struct ExtractedList: Sendable, Identifiable {
    let id = UUID()
    let pageNumber: Int
    let items: [String]
    let isNumbered: Bool
    let boundingBox: CGRect
}

struct DocumentStructureMetadata: Sendable {
    let totalPages: Int
    let textBlockCount: Int
    let tableCount: Int
    let figureCount: Int
    let listCount: Int
    let estimatedWordCount: Int
    let primaryLanguage: String?
    let contentTypes: [DocumentContentType]
}

struct IntelligentProcessingMetrics: Sendable {
    let classificationTimeMs: Double
    let regionDetectionTimeMs: Double
    let ocrTimeMs: Double
    let totalTimeMs: Double
    let modelsUsed: [String]
    let pagesProcessed: Int
}

struct RegionRescueResult: Sendable {
    let pageNumber: Int
    let detectedRegions: [DocumentDetectedRegion]
    let content: StructuredDocumentContent
    let readingOrderText: String
    let averageConfidence: Float
    let modelUsed: String
    let processingTimeMs: Double
}

// MARK: - Intelligent Document Processor

/// Orchestrates intelligent document processing using CoreML vision models
/// Provides enhanced extraction compared to basic OCR-only processing
actor IntelligentDocumentProcessor {

    static let shared = IntelligentDocumentProcessor()
    private nonisolated static let visionRenderContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: - Dependencies

    private let classifier = CoreMLDocumentClassifier.shared
    private let regionDetector = CoreMLRegionDetector.shared

    private init() {}

    // MARK: - Main Processing Pipeline

    /// Process a PDF document with intelligent region detection and extraction
    /// - Parameters:
    ///   - pdf: PDFDocument to process
    ///   - options: Processing options
    /// - Returns: Structured extraction result
    func processDocument(
        _ pdf: PDFDocument,
        options: ProcessingOptions = .default
    ) async throws -> IntelligentProcessingResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var modelsUsed: Set<String> = []

        let pageCount = min(pdf.pageCount, options.maxPages)
        Log.info("[IntelligentProcessor] Starting intelligent processing of \(pageCount) pages", category: .ingestion)

        // STEP 1: Classify first page to determine document type
        let classificationStart = CFAbsoluteTimeGetCurrent()
        let classification = await classifyDocument(pdf, options: options)
        let classificationTime = (CFAbsoluteTimeGetCurrent() - classificationStart) * 1000
        modelsUsed.insert(classification.confidence > 0 ? "FastViT/Vision" : "Heuristic")

        Log.info("[IntelligentProcessor] Document classified as: \(classification.contentType.rawValue) (confidence: \(String(format: "%.2f", classification.confidence)))", category: .ingestion)

        // STEP 2: Detect regions on each page
        let regionStart = CFAbsoluteTimeGetCurrent()
        var allRegions: [RegionDetectionResult] = []

        for pageIndex in 0..<pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            if let pageImage = renderPageToImage(page, dpi: options.renderDPI) {
                let pageRegions = await regionDetector.detectRegions(in: pageImage, pageNumber: pageIndex + 1)
                allRegions.append(pageRegions)
                modelsUsed.insert(pageRegions.modelUsed)

                if pageIndex == 0 || (pageIndex + 1) % 10 == 0 {
                    Log.debug("[IntelligentProcessor] Page \(pageIndex + 1): \(pageRegions.regions.count) regions detected", category: .ingestion)
                }
            }
        }
        let regionTime = (CFAbsoluteTimeGetCurrent() - regionStart) * 1000

        // STEP 3: Extract content per region with appropriate OCR settings
        let ocrStart = CFAbsoluteTimeGetCurrent()
        let structuredContent = await extractStructuredContent(
            from: pdf,
            regions: allRegions,
            hints: classification.processingHints,
            options: options
        )
        let ocrTime = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        let metrics = IntelligentProcessingMetrics(
            classificationTimeMs: classificationTime,
            regionDetectionTimeMs: regionTime,
            ocrTimeMs: ocrTime,
            totalTimeMs: totalTime,
            modelsUsed: Array(modelsUsed),
            pagesProcessed: pageCount
        )

        Log.info("[IntelligentProcessor] ✓ Processing complete in \(String(format: "%.0f", totalTime))ms - \(structuredContent.textBlocks.count) text blocks, \(structuredContent.tables.count) tables, \(structuredContent.figures.count) figures", category: .ingestion)

        return IntelligentProcessingResult(
            classification: classification,
            regions: allRegions,
            structuredContent: structuredContent,
            processingMetrics: metrics
        )
    }

    func rescuePageRegions(
        from image: CIImage,
        pageNumber: Int,
        preferHighAccuracy: Bool = true
    ) async -> RegionRescueResult? {
        let detection = await regionDetector.detectRegions(in: image, pageNumber: pageNumber)
        let candidateRegions = prioritizedRescueRegions(from: detection.sortedByReadingOrder)

        guard !candidateRegions.isEmpty else { return nil }

        let filteredDetection = RegionDetectionResult(
            pageNumber: pageNumber,
            regions: candidateRegions,
            processingTimeMs: detection.processingTimeMs,
            modelUsed: detection.modelUsed
        )

        let content = await extractStructuredContent(
            from: image,
            regions: filteredDetection,
            preferHighAccuracy: preferHighAccuracy
        )

        guard content.metadata.textBlockCount > 0
            || content.metadata.tableCount > 0
            || content.metadata.figureCount > 0
            || content.metadata.listCount > 0 else {
            return nil
        }

        let readingOrderText = buildReadingOrderText(from: content)
        let averageConfidence = candidateRegions.reduce(Float.zero) { $0 + $1.confidence } / Float(candidateRegions.count)

        Log.info(
            "[IntelligentProcessor] Page \(pageNumber): crop rescue kept \(candidateRegions.count) region(s) -> \(content.metadata.tableCount) table(s), \(content.metadata.listCount) list(s), \(content.metadata.textBlockCount) text block(s)",
            category: .ingestion
        )

        return RegionRescueResult(
            pageNumber: pageNumber,
            detectedRegions: candidateRegions,
            content: content,
            readingOrderText: readingOrderText,
            averageConfidence: averageConfidence,
            modelUsed: detection.modelUsed,
            processingTimeMs: detection.processingTimeMs
        )
    }

    // MARK: - Classification

    private func prioritizedRescueRegions(from regions: [DocumentDetectedRegion]) -> [DocumentDetectedRegion] {
        let filtered = regions.filter { region in
            switch region.type {
            case .table, .list, .caption, .figure, .chart, .formField, .handwriting, .equation, .codeBlock:
                return region.confidence >= 0.30 && region.areaFraction >= 0.008
            case .textBlock:
                return region.confidence >= 0.55 && region.areaFraction >= 0.008 && region.areaFraction <= 0.45
            case .header, .footer:
                return region.confidence >= 0.60 && region.areaFraction <= 0.18
            default:
                return false
            }
        }

        let prioritized = filtered.sorted { lhs, rhs in
            let leftPriority = rescuePriority(for: lhs.type)
            let rightPriority = rescuePriority(for: rhs.type)

            if leftPriority != rightPriority {
                return leftPriority > rightPriority
            }

            let yDelta = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(yDelta) > 0.03 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }

            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        return Array(prioritized.prefix(12))
    }

    private func rescuePriority(for type: DocumentRegionType) -> Int {
        switch type {
        case .table: return 6
        case .list, .equation, .codeBlock: return 5
        case .figure, .chart, .caption: return 4
        case .formField, .handwriting: return 3
        case .textBlock: return 2
        case .header, .footer: return 1
        default: return 0
        }
    }

    /// Classify document type based on first page(s)
    private func classifyDocument(_ pdf: PDFDocument, options: ProcessingOptions) async -> DocumentClassificationResult {
        // Sample first page for classification
        guard let firstPage = pdf.page(at: 0),
              let pageImage = renderPageToImage(firstPage, dpi: 150) else { // Lower DPI for classification
            return DocumentClassificationResult(
                contentType: .unknown,
                confidence: 0,
                allClassifications: [],
                processingHints: ProcessingHints(
                    ocrAccuracy: .high,
                    preserveLayout: true,
                    extractTables: true,
                    chunkingPreset: .default
                )
            )
        }

        return await classifier.classify(pageImage)
    }

    // MARK: - Content Extraction

    /// Extract structured content from PDF using detected regions
    private func extractStructuredContent(
        from pdf: PDFDocument,
        regions: [RegionDetectionResult],
        hints: ProcessingHints,
        options: ProcessingOptions
    ) async -> StructuredDocumentContent {
        var textBlocks: [ExtractedTextBlock] = []
        var tables: [ExtractedTable] = []
        var figures: [ExtractedFigure] = []
        var lists: [ExtractedList] = []
        var estimatedWords = 0
        var contentTypes: Set<DocumentContentType> = []

        // Extract OCR accuracy to avoid actor isolation on enum comparison
        let useHighDPI: Bool
        switch hints.ocrAccuracy {
        case .high: useHighDPI = true
        case .standard: useHighDPI = false
        }
        let dpi: CGFloat = useHighDPI ? 360 : 216

        for (pageIndex, pageRegions) in regions.enumerated() {
            guard let page = pdf.page(at: pageIndex),
                  let pageImage = renderPageToImage(page, dpi: dpi) else { continue }

            // Access regions and sort locally to avoid actor isolation
            let sortedRegions = pageRegions.regions.sorted { a, b in
                let yDiff = b.boundingBox.midY - a.boundingBox.midY
                if abs(yDiff) > 0.05 { return yDiff > 0 }
                return a.boundingBox.midX < b.boundingBox.midX
            }

            for region in sortedRegions {
                switch region.type {
                case .textBlock, .header, .footer:
                    // Extract text from this region
                    let text = await extractText(from: pageImage, region: region.boundingBox)
                    if !text.isEmpty {
                        textBlocks.append(ExtractedTextBlock(
                            pageNumber: region.pageNumber,
                            text: text,
                            boundingBox: region.boundingBox,
                            isHeader: region.type == .header,
                            isFooter: region.type == .footer,
                            confidence: region.confidence
                        ))
                        estimatedWords += text.split(separator: " ").count
                        contentTypes.insert(.textDocument)
                    }

                case .table:
                    // Extract table structure
                    let tableData = await extractTable(from: pageImage, region: region.boundingBox)
                    if !tableData.isEmpty {
                        tables.append(ExtractedTable(
                            pageNumber: region.pageNumber,
                            rows: tableData,
                            boundingBox: region.boundingBox,
                            hasHeader: true, // Assume first row is header
                            caption: findNearbyCaption(for: region, in: pageRegions.regions)
                        ))
                        contentTypes.insert(.spreadsheet)
                    }

                case .figure, .chart, .logo:
                    // Record figure location with classification
                    let classification = region.metadata["classification"] ?? region.type.rawValue
                    figures.append(ExtractedFigure(
                        pageNumber: region.pageNumber,
                        boundingBox: region.boundingBox,
                        caption: findNearbyCaption(for: region, in: pageRegions.regions),
                        classification: classification,
                        description: nil // Could use Apple FM for description
                    ))
                    if region.type == .chart {
                        contentTypes.insert(.chart)
                    } else {
                        contentTypes.insert(.diagram)
                    }

                case .list:
                    // Extract list items
                    let text = await extractText(from: pageImage, region: region.boundingBox)
                    let items = parseListItems(text)
                    if !items.isEmpty {
                        lists.append(ExtractedList(
                            pageNumber: region.pageNumber,
                            items: items,
                            isNumbered: text.contains(where: { $0.isNumber }),
                            boundingBox: region.boundingBox
                        ))
                        estimatedWords += items.joined().split(separator: " ").count
                    }

                case .formField:
                    contentTypes.insert(.form)
                    // Extract form field (treat as text for now)
                    let text = await extractText(from: pageImage, region: region.boundingBox)
                    if !text.isEmpty {
                        textBlocks.append(ExtractedTextBlock(
                            pageNumber: region.pageNumber,
                            text: text,
                            boundingBox: region.boundingBox,
                            isHeader: false,
                            isFooter: false,
                            confidence: region.confidence
                        ))
                    }

                case .handwriting:
                    contentTypes.insert(.handwritten)
                    // Use high-accuracy OCR for handwriting
                    let text = await extractText(from: pageImage, region: region.boundingBox, highAccuracy: true)
                    if !text.isEmpty {
                        textBlocks.append(ExtractedTextBlock(
                            pageNumber: region.pageNumber,
                            text: text,
                            boundingBox: region.boundingBox,
                            isHeader: false,
                            isFooter: false,
                            confidence: region.confidence * 0.7 // Lower confidence for handwriting
                        ))
                    }

                default:
                    // Extract as generic text
                    let text = await extractText(from: pageImage, region: region.boundingBox)
                    if !text.isEmpty {
                        textBlocks.append(ExtractedTextBlock(
                            pageNumber: region.pageNumber,
                            text: text,
                            boundingBox: region.boundingBox,
                            isHeader: false,
                            isFooter: false,
                            confidence: region.confidence
                        ))
                        estimatedWords += text.split(separator: " ").count
                    }
                }
            }
        }

        let metadata = DocumentStructureMetadata(
            totalPages: regions.count,
            textBlockCount: textBlocks.count,
            tableCount: tables.count,
            figureCount: figures.count,
            listCount: lists.count,
            estimatedWordCount: estimatedWords,
            primaryLanguage: detectPrimaryLanguage(textBlocks),
            contentTypes: Array(contentTypes)
        )

        return StructuredDocumentContent(
            textBlocks: textBlocks,
            tables: tables,
            figures: figures,
            lists: lists,
            metadata: metadata
        )
    }

    private func extractStructuredContent(
        from image: CIImage,
        regions: RegionDetectionResult,
        preferHighAccuracy: Bool
    ) async -> StructuredDocumentContent {
        var textBlocks: [ExtractedTextBlock] = []
        var tables: [ExtractedTable] = []
        var figures: [ExtractedFigure] = []
        var lists: [ExtractedList] = []
        var estimatedWords = 0
        var contentTypes: Set<DocumentContentType> = []

        for region in regions.sortedByReadingOrder {
            switch region.type {
            case .textBlock, .header, .footer, .caption, .codeBlock, .equation:
                let highAccuracy = preferHighAccuracy || region.boundingBox.height < 0.08 || region.type == .equation
                let text = await extractText(
                    from: image,
                    region: region.boundingBox,
                    highAccuracy: highAccuracy,
                    paddingFraction: region.type == .caption ? 0.025 : 0.018
                )
                if !text.isEmpty {
                    textBlocks.append(ExtractedTextBlock(
                        pageNumber: region.pageNumber,
                        text: text,
                        boundingBox: region.boundingBox,
                        isHeader: region.type == .header,
                        isFooter: region.type == .footer,
                        confidence: region.confidence
                    ))
                    estimatedWords += text.split(separator: " ").count
                    contentTypes.insert(.textDocument)
                }

            case .table:
                let tableData = await extractTable(
                    from: image,
                    region: region.boundingBox,
                    highAccuracy: preferHighAccuracy
                )
                if !tableData.isEmpty {
                    tables.append(ExtractedTable(
                        pageNumber: region.pageNumber,
                        rows: tableData,
                        boundingBox: region.boundingBox,
                        hasHeader: true,
                        caption: findNearbyCaption(for: region, in: regions.regions)
                    ))
                    contentTypes.insert(.spreadsheet)
                }

            case .figure, .chart, .logo:
                let classification = region.metadata["classification"] ?? region.type.rawValue
                let embeddedText = await extractText(
                    from: image,
                    region: region.boundingBox,
                    highAccuracy: preferHighAccuracy,
                    paddingFraction: 0.03
                )
                figures.append(ExtractedFigure(
                    pageNumber: region.pageNumber,
                    boundingBox: region.boundingBox,
                    caption: findNearbyCaption(for: region, in: regions.regions),
                    classification: classification,
                    description: embeddedText.isEmpty ? nil : embeddedText
                ))
                contentTypes.insert(region.type == .chart ? .chart : .diagram)

            case .list:
                let text = await extractText(
                    from: image,
                    region: region.boundingBox,
                    highAccuracy: preferHighAccuracy,
                    paddingFraction: 0.025
                )
                let items = parseListItems(text)
                if !items.isEmpty {
                    lists.append(ExtractedList(
                        pageNumber: region.pageNumber,
                        items: items,
                        isNumbered: text.contains(where: { $0.isNumber }),
                        boundingBox: region.boundingBox
                    ))
                    estimatedWords += items.joined(separator: " ").split(separator: " ").count
                }

            case .formField:
                contentTypes.insert(.form)
                let text = await extractText(
                    from: image,
                    region: region.boundingBox,
                    highAccuracy: true,
                    paddingFraction: 0.02
                )
                if !text.isEmpty {
                    textBlocks.append(ExtractedTextBlock(
                        pageNumber: region.pageNumber,
                        text: text,
                        boundingBox: region.boundingBox,
                        isHeader: false,
                        isFooter: false,
                        confidence: region.confidence
                    ))
                }

            case .handwriting:
                contentTypes.insert(.handwritten)
                let text = await extractText(
                    from: image,
                    region: region.boundingBox,
                    highAccuracy: true,
                    paddingFraction: 0.02
                )
                if !text.isEmpty {
                    textBlocks.append(ExtractedTextBlock(
                        pageNumber: region.pageNumber,
                        text: text,
                        boundingBox: region.boundingBox,
                        isHeader: false,
                        isFooter: false,
                        confidence: region.confidence * 0.7
                    ))
                }

            default:
                break
            }
        }

        let metadata = DocumentStructureMetadata(
            totalPages: 1,
            textBlockCount: textBlocks.count,
            tableCount: tables.count,
            figureCount: figures.count,
            listCount: lists.count,
            estimatedWordCount: estimatedWords,
            primaryLanguage: detectPrimaryLanguage(textBlocks),
            contentTypes: Array(contentTypes)
        )

        return StructuredDocumentContent(
            textBlocks: textBlocks,
            tables: tables,
            figures: figures,
            lists: lists,
            metadata: metadata
        )
    }

    private func buildReadingOrderText(from content: StructuredDocumentContent) -> String {
        var readingElements: [(topY: CGFloat, minX: CGFloat, text: String)] = []

        for block in content.textBlocks {
            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            readingElements.append((block.boundingBox.maxY, block.boundingBox.minX, trimmed))
        }

        for table in content.tables {
            let rows = table.rows
                .map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " | ") }
                .filter { !$0.isEmpty }
            guard !rows.isEmpty else { continue }
            let text = ([table.caption].compactMap { $0 } + rows).joined(separator: "\n")
            readingElements.append((table.boundingBox.maxY, table.boundingBox.minX, text))
        }

        for list in content.lists {
            let items = list.items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { continue }
            readingElements.append((
                list.boundingBox.maxY,
                list.boundingBox.minX,
                items.map { "• \($0)" }.joined(separator: "\n")
            ))
        }

        for figure in content.figures {
            var parts: [String] = []
            if let caption = figure.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                parts.append(caption)
            }
            if let classification = figure.classification?.trimmingCharacters(in: .whitespacesAndNewlines), !classification.isEmpty {
                parts.append("Figure: \(classification)")
            }
            if let description = figure.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                parts.append(description)
            }
            guard !parts.isEmpty else { continue }
            readingElements.append((figure.boundingBox.maxY, figure.boundingBox.minX, parts.joined(separator: "\n")))
        }

        return readingElements
            .sorted { lhs, rhs in
                if abs(lhs.topY - rhs.topY) > 0.03 {
                    return lhs.topY > rhs.topY
                }
                return lhs.minX < rhs.minX
            }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    // MARK: - OCR Helpers

    /// Extract text from a region of an image
    private func extractText(
        from image: CIImage,
        region: CGRect,
        highAccuracy: Bool = false,
        paddingFraction: CGFloat = 0.018
    ) async -> String {
        let croppedImage = preparedRegionImage(
            from: image,
            region: region,
            paddingFraction: paddingFraction,
            minimumScale: highAccuracy ? 1.5 : 1.0,
            forceUpscale: highAccuracy
        )

        return await recognizeText(in: croppedImage, highAccuracy: highAccuracy)
    }

    private func recognizeText(in image: CIImage, highAccuracy: Bool = false) async -> String {
        let imageExtent = image.extent
        guard imageExtent.width > 0, imageExtent.height > 0 else { return "" }
        guard let cgImage = materializedCGImage(from: image) else {
            Log.warning("[IntelligentProcessor] Failed to materialize region image for OCR", category: .ingestion)
            return ""
        }

        var extractedText = ""

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            // Sort by position (top to bottom, left to right)
            let sorted = observations.sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) < 0.02 {
                    return a.boundingBox.midX < b.boundingBox.midX
                }
                return a.boundingBox.midY > b.boundingBox.midY
            }

            extractedText = sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }

        OCRConfiguration.configureRequest(request)

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Limit concurrent Vision OCR to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            try? handler.perform([request])
        }

        return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func materializedCGImage(from image: CIImage) -> CGImage? {
        Self.visionRenderContext.createCGImage(image, from: image.extent)
    }

    @available(iOS 26.0, *)
    private nonisolated func materializedImageData(from image: CIImage) -> Data? {
        Self.visionRenderContext.pngRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [:]
        )
    }

    private func preparedRegionImage(
        from image: CIImage,
        region: CGRect,
        paddingFraction: CGFloat,
        minimumScale: CGFloat,
        forceUpscale: Bool
    ) -> CIImage {
        let imageExtent = image.extent
        let cropRect = CGRect(
            x: region.minX * imageExtent.width,
            y: region.minY * imageExtent.height,
            width: region.width * imageExtent.width,
            height: region.height * imageExtent.height
        )

        guard cropRect.width > 0, cropRect.height > 0 else { return image }

        let padX = max(imageExtent.width * 0.012, cropRect.width * paddingFraction)
        let padY = max(imageExtent.height * 0.012, cropRect.height * paddingFraction)
        let paddedRect = cropRect.insetBy(dx: -padX, dy: -padY).intersection(imageExtent)

        let cropped = image.cropped(to: paddedRect)
        let scale = regionUpscaleFactor(
            for: paddedRect,
            within: imageExtent,
            minimumScale: minimumScale,
            forceUpscale: forceUpscale
        )

        guard scale > 1.01 else { return cropped }
        return cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func regionUpscaleFactor(
        for cropRect: CGRect,
        within imageExtent: CGRect,
        minimumScale: CGFloat,
        forceUpscale: Bool
    ) -> CGFloat {
        let relativeWidth = cropRect.width / max(1, imageExtent.width)
        let relativeHeight = cropRect.height / max(1, imageExtent.height)
        let minRelativeDimension = min(relativeWidth, relativeHeight)

        var scale = minimumScale
        if minRelativeDimension < 0.10 {
            scale = max(scale, 2.2)
        } else if minRelativeDimension < 0.18 {
            scale = max(scale, 1.8)
        } else if minRelativeDimension < 0.28 {
            scale = max(scale, 1.35)
        }

        if forceUpscale {
            scale = max(scale, 1.5)
        }

        return scale
    }

    /// Extract table data from a region
    private func extractTable(
        from image: CIImage,
        region: CGRect,
        highAccuracy: Bool = true
    ) async -> [[String]] {
        let croppedImage = preparedRegionImage(
            from: image,
            region: region,
            paddingFraction: 0.035,
            minimumScale: highAccuracy ? 1.8 : 1.3,
            forceUpscale: true
        )

        // Use iOS 26 RecognizeDocumentsRequest for tables if available
        if #available(iOS 26.0, *) {
            return await extractTableWithVision26(from: croppedImage)
        }

        // Fallback: Extract text and try to parse as table
        let text = await recognizeText(in: croppedImage, highAccuracy: highAccuracy)
        return parseTextAsTable(text)
    }

    @available(iOS 26.0, *)
    private func extractTableWithVision26(from croppedImage: CIImage) async -> [[String]] {
        guard let imageData = materializedImageData(from: croppedImage) else {
            Log.warning("[IntelligentProcessor] Failed to materialize cropped table image for Vision", category: .ingestion)
            return []
        }

        do {
            var request = RecognizeDocumentsRequest()
            // Configure text recognition for maximum accuracy and CJK artifact prevention
            request.textRecognitionOptions.useLanguageCorrection = true
            request.textRecognitionOptions.automaticallyDetectLanguage = true
            request.textRecognitionOptions.minimumTextHeightFraction = 0.0
            request.textRecognitionOptions.recognitionLanguages = OCRConfiguration.recognitionLanguages.compactMap {
                Locale.Language(identifier: $0)
            }
            // Throttle Vision operations to prevent Metal GPU race conditions
            let configuredRequest = request
            let extractedRows = try await VisionOCRThrottle.performAsync {
                let observations = try await configuredRequest.perform(on: imageData)

                // Get the document from the first observation
                guard let document = observations.first?.document else {
                    return [[String]]()
                }

                // Find first table
                for table in document.tables {
                    var rows: [[String]] = []
                    for row in table.rows {
                        let cells = row.map { cell in
                            cell.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        rows.append(cells)
                    }
                    if !rows.isEmpty {
                        return rows
                    }
                }

                return [[String]]()
            }

            if !extractedRows.isEmpty {
                return extractedRows
            }
        } catch {
            Log.debug("[IntelligentProcessor] Table extraction failed: \(error)", category: .ingestion)
        }

        return []
    }

    /// Parse text that looks like table data
    private func parseTextAsTable(_ text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // Try to detect delimiter (tab, |, or multiple spaces)
        var rows: [[String]] = []

        for line in lines {
            let cells: [String]
            if line.contains("\t") {
                cells = line.components(separatedBy: "\t")
            } else if line.contains("|") {
                cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                // Try splitting on multiple spaces
                cells = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }

            if cells.count > 1 {
                rows.append(cells)
            }
        }

        return rows
    }

    /// Parse text as list items
    private func parseListItems(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var items: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Remove common list markers
            var item = trimmed
            let markers = ["•", "-", "*", "·", "○", "●", "◦", "▪", "▸"]
            for marker in markers {
                if item.hasPrefix(marker) {
                    item = String(item.dropFirst()).trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            // Remove numbered list prefix (1. 2. etc)
            if let range = item.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                item = String(item[range.upperBound...])
            }

            if !item.isEmpty {
                items.append(item)
            }
        }

        return items
    }

    /// Find caption text near a figure/table region
    private func findNearbyCaption(for region: DocumentDetectedRegion, in allRegions: [DocumentDetectedRegion]) -> String? {
        // Look for text blocks immediately below or above the region
        let captionCandidates = allRegions.filter { candidate in
            guard candidate.type == .textBlock || candidate.type == .caption else { return false }

            // Check if horizontally aligned
            let horizontalOverlap = min(region.boundingBox.maxX, candidate.boundingBox.maxX) -
                                   max(region.boundingBox.minX, candidate.boundingBox.minX)
            guard horizontalOverlap > region.boundingBox.width * 0.5 else { return false }

            // Check if vertically adjacent (below figure)
            let verticalGap = region.boundingBox.minY - candidate.boundingBox.maxY
            return verticalGap > 0 && verticalGap < 0.05
        }

        // Look for "Figure X" or "Table X" pattern
        for candidate in captionCandidates {
            if let content = candidate.extractedContent,
               content.lowercased().contains("figure") || content.lowercased().contains("table") {
                return content
            }
        }

        return captionCandidates.first?.extractedContent
    }

    /// Detect primary language from text blocks
    private func detectPrimaryLanguage(_ textBlocks: [ExtractedTextBlock]) -> String? {
        let sampleText = textBlocks.prefix(10).map { $0.text }.joined(separator: " ")
        guard !sampleText.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sampleText)
        return recognizer.dominantLanguage?.rawValue
    }

    // MARK: - Image Rendering

    /// Render PDF page to CIImage at specified DPI
    private func renderPageToImage(_ page: PDFPage, dpi: CGFloat) -> CIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        #if canImport(UIKit)
        // Use opaque format to avoid alpha channel overhead
        // This prevents "AlphaPremulLast" warning and halves memory during decode
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
        let uiImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))

            context.cgContext.translateBy(x: 0, y: scaledSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }

        guard let cgImage = uiImage.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
        #else
        return nil
        #endif
    }

    // MARK: - Processing Options

    struct ProcessingOptions: Sendable {
        let maxPages: Int
        let renderDPI: CGFloat
        let enableTableExtraction: Bool
        let enableFigureAnalysis: Bool
        let parallelPages: Int

        static let `default` = ProcessingOptions(
            maxPages: 500,
            renderDPI: 300,
            enableTableExtraction: true,
            enableFigureAnalysis: true,
            parallelPages: 4
        )

        static let fast = ProcessingOptions(
            maxPages: 100,
            renderDPI: 200,
            enableTableExtraction: false,
            enableFigureAnalysis: false,
            parallelPages: 8
        )

        static let highQuality = ProcessingOptions(
            maxPages: 1000,
            renderDPI: 400,
            enableTableExtraction: true,
            enableFigureAnalysis: true,
            parallelPages: 2
        )
    }
}

// MARK: - Convenience Extensions

extension IntelligentProcessingResult {
    /// Get all text content suitable for chunking
    var allText: String {
        var parts: [String] = []

        // Add text blocks (excluding headers/footers)
        for block in structuredContent.textBlocks where !block.isHeader && !block.isFooter {
            parts.append(block.text)
        }

        // Add table content as text
        for table in structuredContent.tables {
            if let caption = table.caption {
                parts.append(caption)
            }
            for row in table.rows {
                parts.append(row.joined(separator: " | "))
            }
        }

        // Add list content
        for list in structuredContent.lists {
            parts.append(list.items.joined(separator: "\n"))
        }

        // Add figure captions
        for figure in structuredContent.figures {
            if let caption = figure.caption {
                parts.append(caption)
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

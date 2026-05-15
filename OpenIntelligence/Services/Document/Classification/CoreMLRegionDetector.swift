//
//  CoreMLRegionDetector.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/24/26.
//
//  DETR-based document region detection for intelligent extraction
//  Uses Apple's pre-trained DETR ResNet50 model (43-85MB, ~35ms inference)
//  Detects: tables, figures, charts, text blocks, images in documents
//  Download: https://developer.apple.com/machine-learning/models/
//

import CoreML
import CoreImage
import Foundation
import Vision

// MARK: - Document Region Types

/// Types of regions that can be detected in a document
enum DocumentRegionType: String, Sendable, CaseIterable {
    case textBlock      // Paragraph of text
    case table          // Tabular data
    case figure         // Generic figure/image
    case chart          // Charts and graphs
    case header         // Page header
    case footer         // Page footer
    case logo           // Company logos
    case signature      // Signatures
    case handwriting    // Handwritten content
    case formField      // Form input fields
    case pageNumber     // Page numbers
    case caption        // Figure/table captions
    case list           // Bulleted/numbered lists
    case codeBlock      // Source code
    case equation       // Mathematical equations
    case unknown        // Unclassified region

    /// Whether this region should be processed with special handling
    var requiresSpecialProcessing: Bool {
        switch self {
        case .table, .chart, .formField, .handwriting, .equation:
            return true
        default:
            return false
        }
    }

    /// Whether this region should be kept atomic (never split)
    var isAtomic: Bool {
        switch self {
        case .table, .chart, .figure, .logo, .signature, .equation:
            return true
        default:
            return false
        }
    }
}

/// A detected region in a document page
struct DocumentDetectedRegion: Sendable, Identifiable {
    let id = UUID()
    let type: DocumentRegionType
    let boundingBox: CGRect          // Normalized coordinates (0-1)
    let confidence: Float
    let pageNumber: Int
    let extractedContent: String?    // OCR'd text from this region
    let metadata: [String: String]   // Additional metadata (e.g., table dimensions)

    /// Convert to pixel coordinates given page size
    func pixelRect(pageSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.minX * pageSize.width,
            y: (1 - boundingBox.maxY) * pageSize.height, // Flip Y for Vision coordinates
            width: boundingBox.width * pageSize.width,
            height: boundingBox.height * pageSize.height
        )
    }

    /// Calculate area as fraction of page
    nonisolated var areaFraction: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

/// Result of region detection on a document page
struct RegionDetectionResult: Sendable {
    let pageNumber: Int
    let regions: [DocumentDetectedRegion]
    let processingTimeMs: Double
    let modelUsed: String // "DETR" or "Vision" fallback

    /// Regions sorted by reading order (top-to-bottom, left-to-right)
    nonisolated var sortedByReadingOrder: [DocumentDetectedRegion] {
        regions.sorted { a, b in
            // Primary: top-to-bottom (higher Y first in normalized coords)
            let yDiff = b.boundingBox.midY - a.boundingBox.midY
            if abs(yDiff) > 0.05 { // Allow some tolerance for same-line items
                return yDiff > 0
            }
            // Secondary: left-to-right
            return a.boundingBox.midX < b.boundingBox.midX
        }
    }

    /// Get regions of specific type
    func regions(ofType type: DocumentRegionType) -> [DocumentDetectedRegion] {
        regions.filter { $0.type == type }
    }

    /// Check if page has tables
    var hasTables: Bool {
        regions.contains { $0.type == .table }
    }

    /// Check if page has figures
    var hasFigures: Bool {
        regions.contains { $0.type == .figure || $0.type == .chart }
    }
}

// MARK: - Region Detector Service

/// Service for detecting semantic regions in document pages using CoreML/Vision
/// Primary: DETR ResNet50 (semantic segmentation)
/// Fallback: Vision framework document detection APIs
actor CoreMLRegionDetector {

    static let shared = CoreMLRegionDetector()
    private nonisolated static let visionRenderContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: - Model State

    private var detrModel: VNCoreMLModel?
    private var detrBackingModel: MLModel?
    private var isModelLoaded = false

    /// COCO class labels mapped to document region types
    /// DETR is trained on COCO, so we map relevant object classes
    private let cocoToRegionType: [String: DocumentRegionType] = [
        // Direct mappings from COCO classes that might appear in documents
        "book": .textBlock,
        "cell_phone": .figure,
        "laptop": .figure,
        "tv": .figure,
        "keyboard": .figure,
        "mouse": .figure,
        "clock": .figure,
        "person": .figure,  // Photos of people

        // Semantic segmentation classes (from DETR-panoptic)
        "banner": .header,
        "wall": .textBlock,
        "table": .table,
        "desk": .table,
    ]

    private init() {}

    // MARK: - Model Loading

    /// Load DETR model on demand
    func loadModel() async throws {
        guard !isModelLoaded else { return }

        // Check for DETR semantic segmentation model
        guard let modelURL = OpenIntelligenceResourceBundle.url(forResource: "DETRResnet50SemanticSegmentationF16", withExtension: "mlmodelc") else {
            Log.info("[CoreMLRegionDetector] DETR model not bundled, using Vision framework fallback", category: .initialization)
            throw DetectorError.modelNotFound
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Use all available compute

            let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
            detrBackingModel = mlModel
            detrModel = try VNCoreMLModel(for: mlModel)
            isModelLoaded = true

            Log.info("[CoreMLRegionDetector] ✓ DETR ResNet50 model loaded successfully", category: .initialization)
        } catch {
            Log.warning("[CoreMLRegionDetector] Failed to load DETR: \(error.localizedDescription)", category: .initialization)
            throw error
        }
    }

    // MARK: - Region Detection

    /// Detect regions in a document page image
    /// - Parameters:
    ///   - image: CIImage of the document page
    ///   - pageNumber: Page number for tracking
    /// - Returns: Detection result with all identified regions
    func detectRegions(in image: CIImage, pageNumber: Int) async -> RegionDetectionResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Try DETR model first
        do {
            try await loadModel()
            if let model = detrModel, let backingModel = detrBackingModel {
                let regions = try await detectWithDETR(image, model: model, backingModel: backingModel, pageNumber: pageNumber)
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return RegionDetectionResult(
                    pageNumber: pageNumber,
                    regions: regions,
                    processingTimeMs: elapsed,
                    modelUsed: "DETR"
                )
            }
        } catch {
            // Fall through to Vision fallback
        }

        // Fallback: Use Vision framework APIs
        let regions = await detectWithVision(image, pageNumber: pageNumber)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return RegionDetectionResult(
            pageNumber: pageNumber,
            regions: regions,
            processingTimeMs: elapsed,
            modelUsed: "Vision"
        )
    }

    /// Detect using DETR CoreML model (semantic segmentation)
    private func detectWithDETR(_ image: CIImage, model: VNCoreMLModel, backingModel: MLModel, pageNumber: Int) async throws -> [DocumentDetectedRegion] {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        // Limit concurrent Vision requests to prevent Metal race conditions
        try withExtendedLifetime(backingModel) {
            try VisionOCRThrottle.performSync {
                try handler.perform([request])
            }
        }

        // DETR returns segmentation masks - convert to regions
        guard let results = request.results else {
            return []
        }

        var regions: [DocumentDetectedRegion] = []

        // Handle different result types
        if let pixelResults = results as? [VNPixelBufferObservation] {
            // Semantic segmentation mask - extract regions from mask
            regions = extractRegionsFromMask(pixelResults.first, pageNumber: pageNumber)
        } else if let rectResults = results as? [VNRecognizedObjectObservation] {
            // Object detection results
            for observation in rectResults {
                let regionType = mapToRegionType(observation.labels.first?.identifier ?? "")
                regions.append(DocumentDetectedRegion(
                    type: regionType,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    pageNumber: pageNumber,
                    extractedContent: nil,
                    metadata: [:]
                ))
            }
        }

        return regions
    }

    /// Extract regions from segmentation mask
    private func extractRegionsFromMask(_ mask: VNPixelBufferObservation?, pageNumber: Int) -> [DocumentDetectedRegion] {
        guard let mask = mask else { return [] }

        // For now, return empty - full mask analysis requires more complex processing
        // This would involve connected component analysis on the segmentation mask
        let width = CVPixelBufferGetWidth(mask.pixelBuffer)
        let height = CVPixelBufferGetHeight(mask.pixelBuffer)
        Log.debug("[CoreMLRegionDetector] Segmentation mask received, size: \(width)x\(height)", category: .ingestion)

        return []
    }

    /// Map COCO/model labels to document region types
    private func mapToRegionType(_ label: String) -> DocumentRegionType {
        let lowercased = label.lowercased()

        // Check direct mapping
        if let type = cocoToRegionType[lowercased] {
            return type
        }

        // Heuristic keyword matching
        if lowercased.contains("table") { return .table }
        if lowercased.contains("chart") || lowercased.contains("graph") { return .chart }
        if lowercased.contains("figure") || lowercased.contains("image") { return .figure }
        if lowercased.contains("text") || lowercased.contains("paragraph") { return .textBlock }
        if lowercased.contains("header") { return .header }
        if lowercased.contains("footer") { return .footer }
        if lowercased.contains("list") { return .list }
        if lowercased.contains("code") { return .codeBlock }
        if lowercased.contains("equation") || lowercased.contains("formula") { return .equation }

        return .unknown
    }

    /// Fallback detection using Vision framework
    private func detectWithVision(_ image: CIImage, pageNumber: Int) async -> [DocumentDetectedRegion] {
        var regions: [DocumentDetectedRegion] = []

        // 1. Detect text regions
        let textRegions = await detectTextRegions(image, pageNumber: pageNumber)
        regions.append(contentsOf: textRegions)

        // 2. Detect rectangles (potential tables, figures)
        let rectRegions = await detectRectangles(image, pageNumber: pageNumber)
        regions.append(contentsOf: rectRegions)

        // 3. On iOS 26+, use document segmentation
        if #available(iOS 26.0, *) {
            let docRegions = await detectDocumentStructure(image, pageNumber: pageNumber)
            // Merge with existing, preferring document structure results
            regions = mergeRegions(existing: regions, new: docRegions)
        }

        return regions
    }

    /// Detect text block regions using Vision
    private func detectTextRegions(_ image: CIImage, pageNumber: Int) async -> [DocumentDetectedRegion] {
        var regions: [DocumentDetectedRegion] = []
        guard let cgImage = materializedCGImage(from: image) else {
            Log.warning("[CoreMLRegionDetector] Failed to materialize page image for text region detection", category: .ingestion)
            return regions
        }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            // Group nearby text observations into blocks
            // For now, treat each observation as a potential text block
            for observation in observations where observation.confidence > 0.5 {
                regions.append(DocumentDetectedRegion(
                    type: .textBlock,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    pageNumber: pageNumber,
                    extractedContent: observation.topCandidates(1).first?.string,
                    metadata: [:]
                ))
            }
        }

        request.recognitionLevel = .fast // Fast for region detection
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Limit concurrent Vision OCR to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            try? handler.perform([request])
        }

        // Cluster nearby text regions into larger blocks
        return clusterTextRegions(regions)
    }

    /// Detect rectangular regions (tables, figures, boxes)
    private func detectRectangles(_ image: CIImage, pageNumber: Int) async -> [DocumentDetectedRegion] {
        var regions: [DocumentDetectedRegion] = []

        let request = VNDetectRectanglesRequest { request, error in
            guard let observations = request.results as? [VNRectangleObservation] else { return }

            for observation in observations where observation.confidence > 0.7 {
                // Classify rectangle based on aspect ratio
                let aspectRatio = observation.boundingBox.width / observation.boundingBox.height
                let regionType: DocumentRegionType

                if aspectRatio > 1.5 {
                    // Wide rectangles might be tables
                    regionType = .table
                } else if aspectRatio < 0.7 {
                    // Tall rectangles might be sidebars
                    regionType = .textBlock
                } else {
                    // Square-ish might be figures
                    regionType = .figure
                }

                regions.append(DocumentDetectedRegion(
                    type: regionType,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    pageNumber: pageNumber,
                    extractedContent: nil,
                    metadata: ["aspectRatio": String(format: "%.2f", aspectRatio)]
                ))
            }
        }

        request.minimumAspectRatio = 0.1
        request.maximumAspectRatio = 10.0
        request.minimumSize = 0.05 // At least 5% of image
        request.maximumObservations = 20

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        // Limit concurrent Vision requests to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            try? handler.perform([request])
        }

        return regions
    }

    /// Detect document structure using iOS 26+ APIs
    @available(iOS 26.0, *)
    private func detectDocumentStructure(_ image: CIImage, pageNumber: Int) async -> [DocumentDetectedRegion] {
        var regions: [DocumentDetectedRegion] = []
        guard let imageData = materializedImageData(from: image) else {
            Log.warning("[CoreMLRegionDetector] Failed to materialize page image for document structure detection", category: .ingestion)
            return regions
        }

        do {
            var request = RecognizeDocumentsRequest()
            // Configure text recognition for maximum accuracy
            request.textRecognitionOptions.useLanguageCorrection = true
            request.textRecognitionOptions.automaticallyDetectLanguage = true
            request.textRecognitionOptions.minimumTextHeightFraction = 0.0
            request.textRecognitionOptions.recognitionLanguages = OCRConfiguration.recognitionLanguages.compactMap {
                Locale.Language(identifier: $0)
            }
            // Throttle Vision operations to prevent Metal GPU race conditions
            let configuredRequest = request
            regions = try await VisionOCRThrottle.performAsync {
                let observations = try await configuredRequest.perform(on: imageData)

                // Get the document from the first observation
                guard let document = observations.first?.document else {
                    return [DocumentDetectedRegion]()
                }

                var extractedRegions: [DocumentDetectedRegion] = []

                // Extract tables
                for table in document.tables {
                    // Tables don't have a direct bounds property, but we can estimate from cells
                    // For now, we'll create a region without precise bounds
                    extractedRegions.append(DocumentDetectedRegion(
                        type: .table,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), // Full page placeholder
                        confidence: 0.9,
                        pageNumber: pageNumber,
                        extractedContent: nil,
                        metadata: [
                            "rows": "\(table.rows.count)",
                            "columns": "\(table.rows.first?.count ?? 0)"
                        ]
                    ))
                }

                // Extract lists
                for _ in document.lists {
                    extractedRegions.append(DocumentDetectedRegion(
                        type: .list,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), // Full page placeholder
                        confidence: 0.85,
                        pageNumber: pageNumber,
                        extractedContent: nil,
                        metadata: [:]
                    ))
                }

                // Extract paragraphs as text blocks
                for paragraph in document.paragraphs {
                    let text = paragraph.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    extractedRegions.append(DocumentDetectedRegion(
                        type: .textBlock,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), // Full page placeholder
                        confidence: 0.85,
                        pageNumber: pageNumber,
                        extractedContent: text,
                        metadata: [:]
                    ))
                }

                return extractedRegions
            }
        } catch {
            Log.debug("[CoreMLRegionDetector] Document structure detection failed: \(error)", category: .ingestion)
        }

        return regions
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

    /// Cluster nearby text regions into larger blocks
    private func clusterTextRegions(_ regions: [DocumentDetectedRegion]) -> [DocumentDetectedRegion] {
        guard regions.count > 1 else { return regions }

        // Simple clustering: merge regions that are close together
        var clustered: [DocumentDetectedRegion] = []
        var used = Set<UUID>()

        for region in regions {
            guard !used.contains(region.id) else { continue }

            var cluster = [region]
            used.insert(region.id)

            // Find nearby regions
            for other in regions where other.id != region.id && !used.contains(other.id) {
                let horizontalOverlap = regionsOverlapHorizontally(region.boundingBox, other.boundingBox)
                let verticalDistance = abs(region.boundingBox.midY - other.boundingBox.midY)

                if horizontalOverlap && verticalDistance < 0.05 {
                    cluster.append(other)
                    used.insert(other.id)
                }
            }

            // Merge cluster into single region
            if cluster.count > 1 {
                let mergedBox = cluster.reduce(cluster[0].boundingBox) { result, region in
                    result.union(region.boundingBox)
                }
                let mergedContent = cluster.compactMap { $0.extractedContent }.joined(separator: " ")
                let avgConfidence = cluster.map { $0.confidence }.reduce(0, +) / Float(cluster.count)

                clustered.append(DocumentDetectedRegion(
                    type: .textBlock,
                    boundingBox: mergedBox,
                    confidence: avgConfidence,
                    pageNumber: region.pageNumber,
                    extractedContent: mergedContent.isEmpty ? nil : mergedContent,
                    metadata: ["clusteredFrom": "\(cluster.count)"]
                ))
            } else {
                clustered.append(region)
            }
        }

        return clustered
    }

    /// Check if two regions overlap horizontally
    private func regionsOverlapHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let minWidth = min(a.width, b.width)
        return overlap > minWidth * 0.5
    }

    /// Merge region lists, preferring new results for overlapping areas
    private func mergeRegions(existing: [DocumentDetectedRegion], new: [DocumentDetectedRegion]) -> [DocumentDetectedRegion] {
        guard !new.isEmpty else { return existing }
        guard !existing.isEmpty else { return new }

        var merged = new

        // Add existing regions that don't significantly overlap with new ones
        for existingRegion in existing {
            let hasSignificantOverlap = new.contains { newRegion in
                let intersection = existingRegion.boundingBox.intersection(newRegion.boundingBox)
                let overlapArea = intersection.width * intersection.height
                let existingArea = existingRegion.boundingBox.width * existingRegion.boundingBox.height
                return overlapArea > existingArea * 0.5
            }

            if !hasSignificantOverlap {
                merged.append(existingRegion)
            }
        }

        return merged
    }

    // MARK: - Errors

    enum DetectorError: Error {
        case modelNotFound
        case detectionFailed(String)
    }
}

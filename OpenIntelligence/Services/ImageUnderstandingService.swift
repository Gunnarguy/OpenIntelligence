//
//  ImageUnderstandingService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/13/26.
//
//  Visual Document Understanding: Image classification, description, and caption association
//

import CoreImage
import Foundation
import Vision
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

// MARK: - Image Understanding Types

/// Represents an image extracted from a document with its analysis
struct AnalyzedImage: Sendable {
    let imageId: UUID
    let pageNumber: Int
    let boundingBox: CGRect // Normalized coordinates (0-1)
    let classifications: [ImageClassification]
    let description: String? // AI-generated description
    let associatedCaption: String? // Nearby text identified as caption
    let contentType: ImageContentType
}

/// Classification result from Vision framework
struct ImageClassification: Sendable {
    let identifier: String
    let confidence: Float
}

/// High-level content type detected from classifications
enum ImageContentType: String, Sendable, Codable {
    case diagram
    case chart
    case photograph
    case technicalDrawing
    case screenshot
    case logo
    case unknown

    /// Determine content type from Vision classifications
    static func from(classifications: [ImageClassification]) -> ImageContentType {
        let identifiers = Set(classifications.map { $0.identifier.lowercased() })

        // Check for specific content types based on Vision's taxonomy
        if identifiers.contains(where: { $0.contains("diagram") || $0.contains("schematic") }) {
            return .diagram
        }
        if identifiers.contains(where: { $0.contains("chart") || $0.contains("graph") || $0.contains("plot") }) {
            return .chart
        }
        if identifiers.contains(where: { $0.contains("drawing") || $0.contains("blueprint") }) {
            return .technicalDrawing
        }
        if identifiers.contains(where: { $0.contains("screenshot") || $0.contains("screen") }) {
            return .screenshot
        }
        if identifiers.contains(where: { $0.contains("logo") || $0.contains("emblem") }) {
            return .logo
        }
        if identifiers.contains(where: { $0.contains("photo") || $0.contains("portrait") || $0.contains("landscape") }) {
            return .photograph
        }

        return .unknown
    }
}

/// Metadata about visual content in a document
struct VisualContentMetadata: Codable, Sendable {
    let imageCount: Int
    let imageClassifications: [String: Float] // aggregated label → max confidence
    let hasTableContent: Bool
    let columnLayout: ColumnLayout
    let captionedImages: Int
    let imagesWithDescriptions: Int

    static var empty: VisualContentMetadata {
        VisualContentMetadata(
            imageCount: 0,
            imageClassifications: [:],
            hasTableContent: false,
            columnLayout: .single,
            captionedImages: 0,
            imagesWithDescriptions: 0
        )
    }
}

enum ColumnLayout: String, Codable, Sendable {
    case single
    case double
    case multi
    case complex
}

// MARK: - Image Understanding Service

/// Service for analyzing images within documents using Apple Vision framework
@MainActor
class ImageUnderstandingService {
    static let shared = ImageUnderstandingService()

    private init() {}

    // MARK: - Image Classification (iOS 18+)

    /// Classify an image using Vision framework
    /// Returns array of classifications with identifiers and confidence scores
    func classifyImage(_ image: CIImage) async throws -> [ImageClassification] {
        // Check for iOS 18+ API availability
        if #available(iOS 18.0, *) {
            return try await classifyImageModern(image)
        } else {
            // Fallback for older iOS - use legacy VNClassifyImageRequest
            return try await classifyImageLegacy(image)
        }
    }

    @available(iOS 18.0, *)
    private func classifyImageModern(_ image: CIImage) async throws -> [ImageClassification] {
        let request = ClassifyImageRequest()

        do {
            let results = try await request.perform(on: image)

            // Filter to high-confidence classifications
            let filtered = results.filter { $0.confidence > 0.1 }

            Log.debug("[ImageUnderstanding] Classified image: \(filtered.prefix(5).map { "\($0.identifier): \(String(format: "%.2f", $0.confidence))" })", category: .ingestion)

            return filtered.map { ImageClassification(identifier: $0.identifier, confidence: $0.confidence) }
        } catch {
            Log.warning("[ImageUnderstanding] Classification failed: \(error.localizedDescription)", category: .ingestion)
            return []
        }
    }

    private func classifyImageLegacy(_ image: CIImage) async throws -> [ImageClassification] {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    Log.warning("[ImageUnderstanding] Legacy classification failed: \(error.localizedDescription)", category: .ingestion)
                    continuation.resume(returning: [])
                    return
                }

                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let classifications = observations
                    .filter { $0.confidence > 0.1 }
                    .prefix(10)
                    .map { ImageClassification(identifier: $0.identifier, confidence: $0.confidence) }

                continuation.resume(returning: Array(classifications))
            }

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Caption Detection

    /// Find potential captions for an image based on spatial proximity
    /// Looks for text blocks directly below or above the image
    func findAssociatedCaption(
        for imageBounds: CGRect,
        in textObservations: [VNRecognizedTextObservation],
        maxDistance: CGFloat = 0.05 // 5% of page height
    ) -> String? {
        // Look for text immediately below the image (most common caption position)
        let captionCandidates = textObservations.filter { observation in
            let textBox = observation.boundingBox

            // Text should be below the image
            let belowImage = textBox.maxY < imageBounds.minY &&
                textBox.maxY > (imageBounds.minY - maxDistance)

            // Text should overlap horizontally with the image
            let horizontalOverlap = textBox.midX > imageBounds.minX &&
                textBox.midX < imageBounds.maxX

            return belowImage && horizontalOverlap
        }

        // Sort by distance to image (closest first)
        let sorted = captionCandidates.sorted { obs1, obs2 in
            let dist1 = imageBounds.minY - obs1.boundingBox.maxY
            let dist2 = imageBounds.minY - obs2.boundingBox.maxY
            return dist1 < dist2
        }

        // Take the closest text block as caption
        if let captionObs = sorted.first,
           let captionText = captionObs.topCandidates(1).first?.string
        {
            // Check if it looks like a caption (starts with "Figure", "Image", etc.)
            let captionPatterns = ["figure", "fig.", "image", "diagram", "chart", "table", "photo"]
            let lowerCaption = captionText.lowercased()

            if captionPatterns.contains(where: { lowerCaption.hasPrefix($0) }) ||
                captionText.count < 200
            { // Short text near image is likely caption
                Log.debug("[ImageUnderstanding] Found caption: \(captionText.prefix(50))...", category: .ingestion)
                return captionText
            }
        }

        return nil
    }

    // MARK: - Image Description Generation

    /// Generate a text description of an image using Apple Intelligence
    /// This creates searchable text from visual content
    func generateImageDescription(
        _ image: CIImage,
        context _: String? = nil, // Optional document context for better descriptions
        caption: String? = nil
    ) async -> String? {
        // For now, generate description from classifications + caption
        // Full Foundation Models image input requires iOS 26+

        do {
            let classifications = try await classifyImage(image)

            if classifications.isEmpty, caption == nil {
                return nil
            }

            var description = ""

            // Add content type
            let contentType = ImageContentType.from(classifications: classifications)
            if contentType != .unknown {
                description += "[\(contentType.rawValue.capitalized)] "
            }

            // Add top classifications
            let topLabels = classifications.prefix(5).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            if !topLabels.isEmpty {
                description += "Contains: \(topLabels.joined(separator: ", ")). "
            }

            // Add caption if available
            if let caption = caption {
                description += "Caption: \(caption)"
            }

            return description.isEmpty ? nil : description.trimmingCharacters(in: .whitespaces)

        } catch {
            Log.warning("[ImageUnderstanding] Failed to generate description: \(error.localizedDescription)", category: .ingestion)
            return caption // Fall back to just the caption if available
        }
    }

    // MARK: - Aggregate Analysis

    /// Analyze all images in a document and return aggregated metadata
    func analyzeDocumentImages(
        images: [(image: CIImage, pageNumber: Int, bounds: CGRect)],
        textObservations: [[VNRecognizedTextObservation]] // Per-page text
    ) async -> (images: [AnalyzedImage], metadata: VisualContentMetadata) {
        var analyzedImages: [AnalyzedImage] = []
        var allClassifications: [String: Float] = [:]
        var captionedCount = 0
        var describedCount = 0

        for (image, pageNumber, bounds) in images {
            do {
                // Classify the image
                let classifications = try await classifyImage(image)

                // Aggregate classifications
                for classification in classifications {
                    let existing = allClassifications[classification.identifier] ?? 0
                    allClassifications[classification.identifier] = max(existing, classification.confidence)
                }

                // Find associated caption
                let pageTextObs = pageNumber <= textObservations.count ? textObservations[pageNumber - 1] : []
                let caption = findAssociatedCaption(for: bounds, in: pageTextObs)
                if caption != nil { captionedCount += 1 }

                // Generate description
                let description = await generateImageDescription(image, caption: caption)
                if description != nil { describedCount += 1 }

                let contentType = ImageContentType.from(classifications: classifications)

                let analyzed = AnalyzedImage(
                    imageId: UUID(),
                    pageNumber: pageNumber,
                    boundingBox: bounds,
                    classifications: classifications,
                    description: description,
                    associatedCaption: caption,
                    contentType: contentType
                )

                analyzedImages.append(analyzed)

            } catch {
                Log.warning("[ImageUnderstanding] Failed to analyze image on page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
            }
        }

        let metadata = VisualContentMetadata(
            imageCount: images.count,
            imageClassifications: allClassifications,
            hasTableContent: allClassifications.keys.contains(where: { $0.lowercased().contains("table") }),
            columnLayout: .single, // Will be set by DocumentProcessor based on text analysis
            captionedImages: captionedCount,
            imagesWithDescriptions: describedCount
        )

        Log.info("[ImageUnderstanding] Analyzed \(images.count) images: \(captionedCount) captioned, \(describedCount) described", category: .ingestion)

        return (analyzedImages, metadata)
    }
}

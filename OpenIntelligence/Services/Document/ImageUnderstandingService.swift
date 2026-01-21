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
    let extractedText: String? // OCR'd text from within the image (labels, annotations)
    let precedingContext: String? // Text that appears before this image
    let followingContext: String? // Text that appears after this image
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

    // MARK: - Image OCR (Extract Text from Diagrams/Flowcharts)

    /// Extract text from within an image using Vision OCR
    /// Critical for diagrams, flowcharts, and annotated technical drawings
    func extractTextFromImage(_ image: CIImage) async -> String? {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    Log.debug("[ImageUnderstanding] Image OCR failed: \(error.localizedDescription)", category: .ingestion)
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                // Sort observations by reading order (top-to-bottom, left-to-right)
                let sortedObservations = observations.sorted { obs1, obs2 in
                    let box1 = obs1.boundingBox
                    let box2 = obs2.boundingBox
                    let lineThreshold: CGFloat = 0.05

                    if abs(box1.midY - box2.midY) > lineThreshold {
                        return box1.midY > box2.midY  // Top to bottom
                    }
                    return box1.minX < box2.minX  // Left to right
                }

                // Extract all text
                let textLines = sortedObservations.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }

                let combinedText = textLines.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if combinedText.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    Log.debug("[ImageUnderstanding] Extracted \(textLines.count) text elements from image", category: .ingestion)
                    continuation.resume(returning: combinedText)
                }
            }

            // Configure for maximum accuracy on potentially low-contrast diagram text
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.01  // Catch small labels

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Context Extraction

    /// Find text that appears before and after an image on the same page
    /// This provides semantic context for what the image relates to
    func findSurroundingContext(
        for imageBounds: CGRect,
        in textObservations: [VNRecognizedTextObservation],
        maxChars: Int = 200
    ) -> (preceding: String?, following: String?) {
        // Separate text into "above" and "below" the image
        var aboveTexts: [(text: String, y: CGFloat)] = []
        var belowTexts: [(text: String, y: CGFloat)] = []

        for observation in textObservations {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            let box = observation.boundingBox

            // Vision uses normalized coords where Y=0 is bottom
            if box.maxY > imageBounds.maxY {
                // Text is above the image (higher Y = higher on page)
                aboveTexts.append((text, box.minY))
            } else if box.minY < imageBounds.minY {
                // Text is below the image
                belowTexts.append((text, box.maxY))
            }
        }

        // Sort and extract
        aboveTexts.sort { $0.y > $1.y }  // Closest to image first (lower Y)
        belowTexts.sort { $0.y < $1.y }  // Closest to image first (higher Y)

        // Take closest text blocks up to maxChars
        var precedingContext = ""
        for (text, _) in aboveTexts {
            if precedingContext.count + text.count > maxChars { break }
            precedingContext = text + " " + precedingContext
        }

        var followingContext = ""
        for (text, _) in belowTexts {
            if followingContext.count + text.count > maxChars { break }
            followingContext += text + " "
        }

        return (
            precedingContext.isEmpty ? nil : precedingContext.trimmingCharacters(in: .whitespaces),
            followingContext.isEmpty ? nil : followingContext.trimmingCharacters(in: .whitespaces)
        )
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

    /// Generate a comprehensive text description of an image
    /// Combines classification, OCR'd text, caption, and surrounding context
    func generateImageDescription(
        _ image: CIImage,
        extractedText: String? = nil,  // OCR'd text from within the image
        caption: String? = nil,
        precedingContext: String? = nil,
        followingContext: String? = nil
    ) async -> String? {
        do {
            let classifications = try await classifyImage(image)
            let contentType = ImageContentType.from(classifications: classifications)

            var descriptionParts: [String] = []

            // 1. Content type
            if contentType != .unknown {
                descriptionParts.append("[\(contentType.rawValue.capitalized)]")
            }

            // 2. Caption (most important for semantic search)
            if let caption = caption, !caption.isEmpty {
                let truncated = String(caption.prefix(150))
                descriptionParts.append("Caption: \(truncated)")
            }

            // 3. Extracted text from within the image (critical for diagrams!)
            if let extractedText = extractedText, !extractedText.isEmpty {
                // Clean up OCR artifacts and cap length
                let cleanedText = extractedText
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "  ", with: " ")
                let truncated = String(cleanedText.prefix(200))
                descriptionParts.append("Labels: \(truncated)")
            }

            // 4. Top classifications (brief, for context)
            let topLabels = classifications.prefix(3).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            if !topLabels.isEmpty && descriptionParts.count < 2 {
                // Only add if we don't have enough other info
                descriptionParts.append("Shows: \(topLabels.joined(separator: ", "))")
            }

            // Skip surrounding context in description - it's redundant with the chunk it appears in

            if descriptionParts.isEmpty {
                return nil
            }

            // Cap total description length
            let joined = descriptionParts.joined(separator: ". ")
            return String(joined.prefix(400))

        } catch {
            Log.warning("[ImageUnderstanding] Failed to generate description: \(error.localizedDescription)", category: .ingestion)
            // Fall back to extracted text or caption
            if let extractedText = extractedText { return "Labels: \(String(extractedText.prefix(200)))" }
            if let caption = caption { return "Caption: \(String(caption.prefix(150)))" }
            return nil
        }
    }

    // MARK: - Aggregate Analysis

    /// Analyze all images in a document and return aggregated metadata
    /// Performs full semantic extraction: classification, OCR, captions, and context
    func analyzeDocumentImages(
        images: [(image: CIImage, pageNumber: Int, bounds: CGRect)],
        textObservations: [[VNRecognizedTextObservation]] // Per-page text
    ) async -> (images: [AnalyzedImage], metadata: VisualContentMetadata) {
        var analyzedImages: [AnalyzedImage] = []
        var allClassifications: [String: Float] = [:]
        var captionedCount = 0
        var describedCount = 0
        var ocrExtractedCount = 0

        for (image, pageNumber, bounds) in images {
            do {
                // 1. Classify the image
                let classifications = try await classifyImage(image)
                let contentType = ImageContentType.from(classifications: classifications)

                // Aggregate classifications
                for classification in classifications {
                    let existing = allClassifications[classification.identifier] ?? 0
                    allClassifications[classification.identifier] = max(existing, classification.confidence)
                }

                // 2. Get page text observations
                let pageTextObs = pageNumber <= textObservations.count ? textObservations[pageNumber - 1] : []

                // 3. Find associated caption
                let caption = findAssociatedCaption(for: bounds, in: pageTextObs)
                if caption != nil { captionedCount += 1 }

                // 4. Extract text FROM the image (critical for diagrams/flowcharts)
                var extractedText: String? = nil
                if contentType == .diagram || contentType == .chart || contentType == .technicalDrawing || contentType == .screenshot {
                    // These content types likely have text we should extract
                    extractedText = await extractTextFromImage(image)
                    if extractedText != nil { ocrExtractedCount += 1 }
                } else {
                    // For other types, still try OCR but don't count as critical
                    extractedText = await extractTextFromImage(image)
                }

                // 5. Find surrounding context
                let (precedingContext, followingContext) = findSurroundingContext(for: bounds, in: pageTextObs)

                // 6. Generate comprehensive description
                let description = await generateImageDescription(
                    image,
                    extractedText: extractedText,
                    caption: caption,
                    precedingContext: precedingContext,
                    followingContext: followingContext
                )
                if description != nil { describedCount += 1 }

                let analyzed = AnalyzedImage(
                    imageId: UUID(),
                    pageNumber: pageNumber,
                    boundingBox: bounds,
                    classifications: classifications,
                    description: description,
                    associatedCaption: caption,
                    contentType: contentType,
                    extractedText: extractedText,
                    precedingContext: precedingContext,
                    followingContext: followingContext
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

        Log.info("[ImageUnderstanding] Analyzed \(images.count) images: \(captionedCount) captioned, \(ocrExtractedCount) with extracted text, \(describedCount) described", category: .ingestion)

        return (analyzedImages, metadata)
    }
}

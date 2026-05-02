//
//  ImageUnderstandingService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/13/26.
//
//  Visual Document Understanding: Image classification, description, and caption association
//  Enhanced with Apple Intelligence (FoundationModels) for rich natural language descriptions
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
#if canImport(FoundationModels)
    import FoundationModels
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
    private nonisolated static let visionRenderContext = CIContext(options: [.cacheIntermediates: false])

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
        guard let cgImage = materializedCGImage(from: image) else {
            Log.warning("[ImageUnderstanding] Failed to materialize image for Vision classification", category: .ingestion)
            return []
        }

        let request = ClassifyImageRequest()

        do {
            // Throttle Vision operations to prevent Metal GPU race conditions
            let results = try await VisionOCRThrottle.performAsync {
                try await request.perform(on: cgImage)
            }

            // Filter to high-confidence classifications
            let filtered = results.filter { $0.confidence > 0.1 }

            Log.debug("[ImageUnderstanding] Classified image: \(filtered.prefix(5).map { "\($0.identifier): \(String(format: "%.2f", $0.confidence))" })", category: .ingestion)

            return filtered.map { ImageClassification(identifier: $0.identifier, confidence: $0.confidence) }
        } catch {
            Log.warning("[ImageUnderstanding] Classification failed: \(error.localizedDescription)", category: .ingestion)
            return []
        }
    }

    private nonisolated func materializedCGImage(from image: CIImage) -> CGImage? {
        Self.visionRenderContext.createCGImage(image, from: image.extent)
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

            // Limit concurrent Vision requests to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Image OCR (Extract Text from Diagrams/Flowcharts)

    /// Extract text from within an image using Vision OCR
    /// Critical for diagrams, flowcharts, and annotated technical drawings
    func extractTextFromImage(_ image: CIImage) async -> String? {
        // MAXIMUM QUALITY OCR: Upscale low-res images and enhance for better recognition
        var processedImage = image
        let imageSize = image.extent.size
        let maxDimension = max(imageSize.width, imageSize.height)

        // Upscale small images for better OCR (target 2000px minimum)
        if maxDimension < 2000 {
            let upscaleFactor = min(3.0, 2000.0 / maxDimension)
            let transform = CGAffineTransform(scaleX: upscaleFactor, y: upscaleFactor)
            processedImage = image.transformed(by: transform)
        }

        // Enhance contrast for diagram/flowchart text
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(processedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.08, forKey: kCIInputContrastKey)  // Slightly higher for diagrams
            if let output = contrastFilter.outputImage {
                processedImage = output
            }
        }

        let requestHandler = VNImageRequestHandler(ciImage: processedImage, options: [:])

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
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE"]
            request.minimumTextHeight = 0.005  // Catch tiny labels (default is 0.03125)

            // Limit concurrent Vision OCR to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
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
    /// THROTTLED: Max 2 concurrent analyses to prevent memory pressure on large docs.
    /// At 542 pages + 8 images, unbounded parallelism caused watchdog kills.
    func analyzeDocumentImages(
        images: [(image: CIImage, pageNumber: Int, bounds: CGRect)],
        textObservationsByPage: [Int: [VNRecognizedTextObservation]]
    ) async -> (images: [AnalyzedImage], metadata: VisualContentMetadata) {
        guard !images.isEmpty else {
            return ([], VisualContentMetadata(
                imageCount: 0,
                imageClassifications: [:],
                hasTableContent: false,
                columnLayout: .single,
                captionedImages: 0,
                imagesWithDescriptions: 0
            ))
        }

        // Throttle concurrency to prevent memory spikes on large documents.
        // Each image analysis involves Vision classification + OCR + description.
        // With 542 pages of parsed text already in memory, launching all images
        // concurrently caused watchdog kills on A18 Pro.
        let maxConcurrent = 2
        Log.info("[ImageUnderstanding] 🚀 Analyzing \(images.count) images (max \(maxConcurrent) concurrent)", category: .ingestion)

        let results = await withTaskGroup(of: AnalyzedImage?.self) { group in
            var index = 0
            var collected: [AnalyzedImage] = []

            // Seed the group with initial batch
            while index < min(maxConcurrent, images.count) {
                let (image, pageNumber, bounds) = images[index]
                let pageTextObs = textObservationsByPage[pageNumber] ?? []
                let capturedIndex = index
                group.addTask { [self] in
                    do {
                        return try await self.analyzeOneImage(
                            image: image, pageNumber: pageNumber,
                            bounds: bounds, pageTextObs: pageTextObs
                        )
                    } catch {
                        Log.warning("[ImageUnderstanding] Failed image \(capturedIndex) on page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
                        return nil
                    }
                }
                index += 1
            }

            // As each completes, add the next one — sliding window
            for await result in group {
                if let analyzed = result {
                    collected.append(analyzed)
                }

                // Launch next image if any remain
                if index < images.count {
                    let (image, pageNumber, bounds) = images[index]
                    let pageTextObs = textObservationsByPage[pageNumber] ?? []
                    let capturedIndex = index
                    group.addTask { [self] in
                        do {
                            return try await self.analyzeOneImage(
                                image: image, pageNumber: pageNumber,
                                bounds: bounds, pageTextObs: pageTextObs
                            )
                        } catch {
                            Log.warning("[ImageUnderstanding] Failed image \(capturedIndex) on page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
                            return nil
                        }
                    }
                    index += 1
                }
            }
            return collected
        }

        // Sort by page number for consistent output
        let sortedResults = results.sorted { $0.pageNumber < $1.pageNumber }

        // Aggregate metadata from results
        var allClassifications: [String: Float] = [:]
        var captionedCount = 0
        var describedCount = 0
        var ocrExtractedCount = 0

        for analyzed in sortedResults {
            for classification in analyzed.classifications {
                let existing = allClassifications[classification.identifier] ?? 0
                allClassifications[classification.identifier] = max(existing, classification.confidence)
            }
            if analyzed.associatedCaption != nil { captionedCount += 1 }
            if analyzed.description != nil { describedCount += 1 }
            if analyzed.extractedText != nil { ocrExtractedCount += 1 }
        }

        let metadata = VisualContentMetadata(
            imageCount: images.count,
            imageClassifications: allClassifications,
            hasTableContent: allClassifications.keys.contains(where: { $0.lowercased().contains("table") }),
            columnLayout: .single, // Will be set by DocumentProcessor based on text analysis
            captionedImages: captionedCount,
            imagesWithDescriptions: describedCount
        )

        Log.info("[ImageUnderstanding] ✅ Parallel analysis complete: \(sortedResults.count)/\(images.count) images processed (\(captionedCount) captioned, \(ocrExtractedCount) OCR, \(describedCount) described)", category: .ingestion)

        return (sortedResults, metadata)
    }

    /// Analyze a single image (internal helper for parallel processing)
    private func analyzeOneImage(
        image: CIImage,
        pageNumber: Int,
        bounds: CGRect,
        pageTextObs: [VNRecognizedTextObservation]
    ) async throws -> AnalyzedImage {
        // 1. Classify the image
        let classifications = try await classifyImage(image)
        let contentType = ImageContentType.from(classifications: classifications)

        // 2. Find associated caption
        let caption = findAssociatedCaption(for: bounds, in: pageTextObs)

        // 3. Extract text FROM the image (critical for diagrams, screenshots, and annotated figures)
        let extractedText = await extractTextFromImage(image)

        // 4. Find surrounding context
        let (precedingContext, followingContext) = findSurroundingContext(for: bounds, in: pageTextObs)

        // 5. Generate comprehensive description
        var description: String? = nil

        if #available(iOS 26.0, *) {
            description = await generateAIDescription(
                for: image,
                contentType: contentType,
                classifications: classifications,
                extractedText: extractedText,
                caption: caption,
                precedingContext: precedingContext,
                followingContext: followingContext
            )
        }

        // Fall back to classification-based description if no AI description
        if description == nil {
            description = await generateImageDescription(
                image,
                extractedText: extractedText,
                caption: caption,
                precedingContext: precedingContext,
                followingContext: followingContext
            )
        }

        return AnalyzedImage(
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
    }

    // MARK: - Apple Intelligence Image Description (iOS 26+)

    /// Generate a rich natural language description using Apple Intelligence (FoundationModels)
    /// This provides semantic understanding beyond classification, e.g.:
    /// "This flowchart shows a 5-step process: Start → Input validation → Processing → Output → End"
    /// "This bar chart compares quarterly revenue: Q1=$2.1M, Q2=$2.8M, Q3=$3.2M, Q4=$4.1M"
    @available(iOS 26.0, *)
    func generateAIDescription(
        for image: CIImage,
        contentType: ImageContentType,
        classifications: [ImageClassification],
        extractedText: String? = nil,
        caption: String? = nil,
        precedingContext: String? = nil,
        followingContext: String? = nil
    ) async -> String? {
        #if canImport(FoundationModels)
        do {
            // Check if FoundationModels is available
            guard SystemLanguageModel.default.isAvailable else {
                Log.debug("[ImageUnderstanding] FoundationModels not available, using classification fallback", category: .ingestion)
                return nil
            }

            // Create a language model session
            let session = LanguageModelSession()

            // Build context-aware prompt based on content type
            let prompt = buildImageDescriptionPrompt(
                contentType: contentType,
                classifications: classifications,
                extractedText: extractedText,
                caption: caption,
                precedingContext: precedingContext,
                followingContext: followingContext
            )

            // Generate description
            // Note: iOS 26 FoundationModels supports image attachments
            // For now, we use text context since image attachment API may vary
            let response = try await session.respond(to: prompt)

            let description = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            if !description.isEmpty {
                Log.info("[ImageUnderstanding] AI generated description: \(description.prefix(100))...", category: .ingestion)
                return description
            }

        } catch {
            Log.warning("[ImageUnderstanding] AI description failed: \(error.localizedDescription)", category: .ingestion)
        }
        #endif

        return nil
    }

    /// Build a context-aware prompt for image description based on content type
    private func buildImageDescriptionPrompt(
        contentType: ImageContentType,
        classifications: [ImageClassification],
        extractedText: String?,
        caption: String?,
        precedingContext: String?,
        followingContext: String?
    ) -> String {
        var contextParts: [String] = []

        // Add content type context
        let typeHint: String
        switch contentType {
        case .diagram:
            typeHint = "This is a diagram or flowchart."
        case .chart:
            typeHint = "This is a chart or graph."
        case .technicalDrawing:
            typeHint = "This is a technical drawing or schematic."
        case .screenshot:
            typeHint = "This is a screenshot."
        case .photograph:
            typeHint = "This is a photograph."
        case .logo:
            typeHint = "This is a logo or emblem."
        case .unknown:
            typeHint = "This is an image."
        }
        contextParts.append(typeHint)

        let topClassifications = classifications
            .prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        if !topClassifications.isEmpty {
            contextParts.append("Vision classifications: \(topClassifications.joined(separator: ", "))")
        }

        // Add caption if available
        if let caption = caption, !caption.isEmpty {
            contextParts.append("Caption: \(caption)")
        }

        // Add extracted text if available
        if let text = extractedText, !text.isEmpty {
            let truncatedText = String(text.prefix(500))
            contextParts.append("Text visible in image: \(truncatedText)")
        }

        if let precedingContext = precedingContext, !precedingContext.isEmpty {
            contextParts.append("Nearby text before image: \(String(precedingContext.prefix(220)))")
        }

        if let followingContext = followingContext, !followingContext.isEmpty {
            contextParts.append("Nearby text after image: \(String(followingContext.prefix(220)))")
        }

        let context = contextParts.joined(separator: "\n")

        // Build the prompt
        let prompt: String
        switch contentType {
        case .diagram:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, describe what this diagram shows. Focus on the flow, steps, labels, relationships, and exact terms visible.

            \(context)

            Provide a concise grounded description (2-3 sentences). Preserve exact codes, labels, units, statuses, and arrows when they appear.
            """

        case .chart:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, describe what this chart shows. Extract visible values, labels, legends, and trends when supported.

            \(context)

            Provide a concise grounded description (2-3 sentences) including exact values or units only if they appear in the supplied context.
            """

        case .technicalDrawing:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, describe what this technical drawing shows. Identify components, measurements, specifications, and labels.

            \(context)

            Provide a concise grounded technical description (2-3 sentences). Preserve exact component names, codes, and units where visible.
            """

        case .screenshot:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, describe what this screenshot shows. Identify interface elements, visible text, controls, and workflow context.

            \(context)

            Provide a concise grounded description (2-3 sentences) of what the screenshot depicts. Preserve exact visible UI text when possible.
            """

        case .photograph:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, describe what this photograph shows. Focus on the main subject, any readable labels, and the document-relevant context.

            \(context)

            Provide a concise grounded description (1-2 sentences).
            """

        case .logo:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, describe what this logo or emblem identifies.

            \(context)

            Provide a concise grounded description (1 sentence).
            """

        default:
            prompt = """
            You are writing retrieval text for a document intelligence engine.
            Based only on this context, provide a brief grounded description of what this image shows.

            \(context)

            Describe the content in 1-2 sentences. Preserve exact labels, numbers, and units when visible.
            """
        }

        return prompt
    }

    /// Enhanced image analysis using both Vision classification and Apple Intelligence description
    /// Returns a comprehensive analysis combining both approaches
    @available(iOS 26.0, *)
    func analyzeImageWithAI(_ image: CIImage) async -> EnhancedImageAnalysis {
        // Get Vision classifications first
        let classifications = (try? await classifyImage(image)) ?? []
        let contentType = ImageContentType.from(classifications: classifications)

        // Extract text from image
        let extractedText = await extractTextFromImage(image)

        // Generate AI description
        let aiDescription = await generateAIDescription(
            for: image,
            contentType: contentType,
            classifications: classifications,
            extractedText: extractedText,
            caption: nil,
            precedingContext: nil,
            followingContext: nil
        )

        // Generate combined description
        let combinedDescription = generateCombinedDescription(
            classifications: classifications,
            contentType: contentType,
            extractedText: extractedText,
            aiDescription: aiDescription
        )

        return EnhancedImageAnalysis(
            classifications: classifications,
            contentType: contentType,
            extractedText: extractedText,
            aiDescription: aiDescription,
            combinedDescription: combinedDescription
        )
    }

    /// Generate a combined description from all analysis sources
    private func generateCombinedDescription(
        classifications: [ImageClassification],
        contentType: ImageContentType,
        extractedText: String?,
        aiDescription: String?
    ) -> String {
        var parts: [String] = []

        // Add AI description first (most valuable)
        if let ai = aiDescription, !ai.isEmpty {
            parts.append(ai)
        }

        // Add content type if no AI description
        if parts.isEmpty && contentType != .unknown {
            parts.append("[\(contentType.rawValue.capitalized)]")
        }

        // Add extracted text labels
        if let text = extractedText, !text.isEmpty {
            let truncated = String(text.prefix(200))
            parts.append("Labels: \(truncated)")
        }

        // Add top classifications if minimal info
        if parts.isEmpty {
            let topLabels = classifications.prefix(3).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            if !topLabels.isEmpty {
                parts.append("Shows: \(topLabels.joined(separator: ", "))")
            }
        }

        return parts.joined(separator: ". ")
    }

    // MARK: - Standalone Image Analysis (All iOS Versions)

    /// Analyze a standalone image file and generate rich context for RAG.
    /// Works on all iOS versions: uses Vision classification + OCR, with AI description on iOS 26+.
    /// Returns structured text suitable for chunking and embedding.
    ///
    /// Example output:
    /// ```
    /// [Image: Photograph]
    /// Content: consumer electronics, audio equipment, speaker
    /// Text: "SONOS ROOST"
    /// Description: A white cylindrical wireless speaker with the Sonos logo.
    /// ```
    func analyzeStandaloneImage(_ image: CIImage) async -> StandaloneImageAnalysis {
        // 1. Classify the image
        let classifications = (try? await classifyImage(image)) ?? []
        let contentType = ImageContentType.from(classifications: classifications)

        // 2. Extract text from image (OCR)
        let extractedText = await extractTextFromImage(image)

        // 3. Generate AI description if available (iOS 26+)
        var aiDescription: String? = nil
        if #available(iOS 26.0, *) {
            aiDescription = await generateAIDescription(
                for: image,
                contentType: contentType,
                classifications: classifications,
                extractedText: extractedText,
                caption: nil,
                precedingContext: nil,
                followingContext: nil
            )
        }

        // 4. Generate classification-based description as fallback
        let classificationDescription = await generateImageDescription(
            image,
            extractedText: extractedText,
            caption: nil,
            precedingContext: nil,
            followingContext: nil
        )

        // 5. Build structured text for RAG
        var textParts: [String] = []

        // Header with content type
        let typeLabel = contentType != .unknown ? contentType.rawValue.capitalized : "Image"
        textParts.append("[Image: \(typeLabel)]")

        // Top classifications (semantic content)
        let topLabels = classifications.prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: ", ")
        if !topLabels.isEmpty {
            textParts.append("Content: \(topLabels)")
        }

        // OCR text (critical for labels, product names, etc.)
        if let text = extractedText, !text.isEmpty {
            let cleanedText = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            textParts.append("Text: \"\(cleanedText)\"")
        }

        // AI description (most valuable for semantic understanding)
        if let description = aiDescription, !description.isEmpty {
            textParts.append("Description: \(description)")
        } else if let fallback = classificationDescription, !fallback.isEmpty {
            textParts.append("Description: \(fallback)")
        }

        let structuredText = textParts.joined(separator: "\n")

        Log.info("[ImageUnderstanding] 🖼️ Standalone image analyzed: \(contentType.rawValue), \(classifications.count) classifications, \(extractedText?.count ?? 0) OCR chars", category: .ingestion)

        return StandaloneImageAnalysis(
            classifications: classifications,
            contentType: contentType,
            extractedText: extractedText,
            aiDescription: aiDescription,
            classificationDescription: classificationDescription,
            structuredText: structuredText
        )
    }
}

// MARK: - Standalone Image Analysis Result

/// Result from analyzing a standalone image file for RAG ingestion
struct StandaloneImageAnalysis: Sendable {
    let classifications: [ImageClassification]
    let contentType: ImageContentType
    let extractedText: String?           // OCR text from within image
    let aiDescription: String?           // iOS 26+ AI description
    let classificationDescription: String? // Vision classification description
    let structuredText: String           // Combined text ready for RAG chunking

    /// Raw OCR text only (for backward compatibility)
    var ocrText: String {
        extractedText ?? ""
    }

    /// Best description available
    var bestDescription: String {
        aiDescription ?? classificationDescription ?? ""
    }
}

// MARK: - Enhanced Image Analysis Result

/// Result from enhanced AI-powered image analysis
struct EnhancedImageAnalysis {
    let classifications: [ImageClassification]
    let contentType: ImageContentType
    let extractedText: String?
    let aiDescription: String?      // Apple Intelligence generated description
    let combinedDescription: String // Best description combining all sources

    /// Returns the most informative description available
    var bestDescription: String {
        if let ai = aiDescription, !ai.isEmpty {
            return ai
        }
        return combinedDescription
    }
}

// MARK: - Image Description Service (Standalone)

/// Standalone service for generating image descriptions using Apple Intelligence
/// Can be used independently from document processing for live camera analysis
@MainActor
class ImageDescriptionService {

    static let shared = ImageDescriptionService()

    private init() {}

    /// Check if AI image description is available
    var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return SystemLanguageModel.default.isAvailable
            #else
            return false
            #endif
        }
        return false
    }

    /// Describe an image using Apple Intelligence
    /// Returns a natural language description of the image content
    func describeImage(_ cgImage: CGImage) async -> String? {
        guard isAvailable else { return nil }

        if #available(iOS 26.0, *) {
            let ciImage = CIImage(cgImage: cgImage)
            return await ImageUnderstandingService.shared.generateAIDescription(
                for: ciImage,
                contentType: .unknown,
                classifications: [],
                extractedText: nil,
                caption: nil,
                precedingContext: nil,
                followingContext: nil
            )
        }

        return nil
    }

    /// Describe an image with additional context
    func describeImage(
        _ cgImage: CGImage,
        extractedText: String?,
        caption: String?
    ) async -> String? {
        guard isAvailable else { return nil }

        if #available(iOS 26.0, *) {
            let ciImage = CIImage(cgImage: cgImage)

            // First classify to determine content type
            let classifications = (try? await ImageUnderstandingService.shared.classifyImage(ciImage)) ?? []
            let contentType = ImageContentType.from(classifications: classifications)

            return await ImageUnderstandingService.shared.generateAIDescription(
                for: ciImage,
                contentType: contentType,
                classifications: classifications,
                extractedText: extractedText,
                caption: caption,
                precedingContext: nil,
                followingContext: nil
            )
        }

        return nil
    }

    /// Full enhanced analysis of an image
    func analyzeImage(_ cgImage: CGImage) async -> EnhancedImageAnalysis? {
        if #available(iOS 26.0, *) {
            let ciImage = CIImage(cgImage: cgImage)
            return await ImageUnderstandingService.shared.analyzeImageWithAI(ciImage)
        }
        return nil
    }
}

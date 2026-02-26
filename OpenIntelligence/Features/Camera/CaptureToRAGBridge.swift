//
//  CaptureToRAGBridge.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  Bridge between camera capture and RAG pipeline.
//  Converts captured text/images into documents for ingestion.
//

import Foundation
import UIKit

// MARK: - Capture to RAG Bridge

/// Service that bridges camera captures to the RAG ingestion pipeline
actor CaptureToRAGBridge {

    // MARK: - Singleton

    static let shared = CaptureToRAGBridge()

    private init() {}

    // MARK: - Ingestion

    /// Ingest a capture result into the RAG system
    /// - Parameters:
    ///   - result: The capture result from camera
    ///   - containerId: Target container ID (nil for default)
    ///   - ragService: The RAG service to use for ingestion
    func ingestCapture(
        _ result: CaptureResult,
        to containerId: UUID?,
        ragService: RAGService
    ) async throws {

        guard !result.recognizedText.isEmpty else {
            throw CaptureIngestionError.noTextContent
        }

        // Generate title from content
        let title = generateTitle(from: result)

        // Create a temporary markdown file
        let content = formatAsMarkdown(result)

        let tempDir = FileManager.default.temporaryDirectory
        let filename = sanitizeFilename(title) + ".md"
        let fileURL = tempDir.appendingPathComponent(filename)

        // Write content
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        Log.info("[CaptureToRAG] Created temp file: \(filename) (\(content.count) chars)", category: .ingestion)

        // Ingest via RAGService
        await MainActor.run {
            _ = ragService.enqueueDocuments([fileURL])
            Log.info("[CaptureToRAG] Successfully queued capture: \(title)", category: .ingestion)
        }
    }

    /// Ingest captured image with AI-generated description
    /// - Parameters:
    ///   - image: The captured image
    ///   - text: Recognized text from the image
    ///   - description: AI-generated description of the image content
    ///   - containerId: Target container
    ///   - ragService: RAG service
    func ingestImageWithDescription(
        image: CGImage,
        text: String,
        description: String?,
        to containerId: UUID?,
        ragService: RAGService
    ) async throws {

        // Combine text and description
        var content = """
        # Captured Image

        **Captured:** \(ISO8601DateFormatter().string(from: Date()))

        """

        if let description = description, !description.isEmpty {
            content += """
            ## Image Description

            \(description)

            """
        }

        if !text.isEmpty {
            content += """
            ## Recognized Text

            \(text)

            """
        }

        // Generate title
        let title = generateTitleFromText(text) ?? "Camera Capture \(dateFormatter.string(from: Date()))"

        let tempDir = FileManager.default.temporaryDirectory
        let filename = sanitizeFilename(title) + ".md"
        let fileURL = tempDir.appendingPathComponent(filename)

        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        await MainActor.run {
            _ = ragService.enqueueDocuments([fileURL])
        }
    }

    // MARK: - Formatting

    /// Format capture result as Markdown for ingestion
    private func formatAsMarkdown(_ result: CaptureResult) -> String {
        var markdown = """
        # Camera Capture

        **Captured:** \(ISO8601DateFormatter().string(from: result.timestamp))
        **Type:** \(captureTypeLabel(result.captureType))

        ---

        """

        // Add structured elements if available
        if !result.structuredElements.isEmpty {
            markdown += "## Document Structure\n\n"

            for element in result.structuredElements {
                switch element.type {
                case .heading:
                    markdown += "### \(element.content)\n\n"

                case .paragraph:
                    markdown += element.content + "\n\n"

                case .list(let items):
                    markdown += "**List (\(items) items):**\n"
                    // Parse content as list items
                    for line in element.content.split(separator: "\n") {
                        markdown += "- \(line)\n"
                    }
                    markdown += "\n"

                case .table(let rows, let columns):
                    markdown += "**Table (\(rows)×\(columns)):**\n\n"
                    markdown += "```\n\(element.content)\n```\n\n"
                }
            }

            markdown += "---\n\n"
        }

        // Add full text content
        markdown += "## Full Text\n\n"
        markdown += result.recognizedText

        return markdown
    }

    /// Generate a title from capture content
    private func generateTitle(from result: CaptureResult) -> String {
        // Try to extract a meaningful title from the first line
        let text = result.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let title = generateTitleFromText(text) {
            return title
        }

        // Fallback to date-based title
        return "Capture \(dateFormatter.string(from: result.timestamp))"
    }

    /// Extract title from text content
    private func generateTitleFromText(_ text: String) -> String? {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        let cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // If first line is reasonable length, use it as title
        if cleaned.count >= 3 && cleaned.count <= 100 {
            return cleaned
        }

        // If too long, truncate
        if cleaned.count > 100 {
            let truncated = String(cleaned.prefix(80))
            if let lastSpace = truncated.lastIndex(of: " ") {
                return String(truncated[..<lastSpace]) + "..."
            }
            return truncated + "..."
        }

        return nil
    }

    /// Sanitize filename for file system
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.components(separatedBy: invalid).joined(separator: "_")
        return String(sanitized.prefix(100))
    }

    /// Get label for capture type
    private func captureTypeLabel(_ type: CaptureResult.CaptureType) -> String {
        switch type {
        case .textOnly: return "Text Only"
        case .fullImage: return "Full Image"
        case .structuredDocument: return "Structured Document"
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}

// MARK: - Errors

enum CaptureIngestionError: LocalizedError {
    case noTextContent
    case ingestionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noTextContent:
            return "No text content was captured"
        case .ingestionFailed(let error):
            return "Failed to ingest capture: \(error.localizedDescription)"
        }
    }
}

// MARK: - Live Analysis Service

/// Service for continuous live camera analysis
actor LiveAnalysisService {

    // MARK: - Properties

    private var isAnalyzing = false
    private let analysisInterval: TimeInterval = 0.1 // 10 FPS

    // MARK: - Analysis

    /// Analyze a camera frame for live preview
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) async -> FrameAnalysis {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return await analyzeImage(ciImage)
    }

    /// Analyze a CIImage for regions and text
    func analyzeImage(_ image: CIImage) async -> FrameAnalysis {
        return await withCheckedContinuation { continuation in
            let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])

            var regions: [DetectedRegion] = []
            var recognizedText = ""
            let aestheticsScore: Float? = nil
            var sceneLabels: [String] = []
            var detectedObjects: [String] = []

            // Text recognition
            let textRequest = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

                for observation in observations {
                    if let text = observation.topCandidates(1).first?.string {
                        recognizedText += text + " "
                        regions.append(DetectedRegion(
                            type: .text,
                            boundingBox: observation.boundingBox,
                            confidence: observation.confidence,
                            preview: String(text.prefix(30))
                        ))
                    }
                }
            }
            // Use centralized OCR configuration — same as main document pipeline
            OCRConfiguration.configureRequest(textRequest)

            // Document detection
            let documentRequest = VNDetectDocumentSegmentationRequest { request, error in
                guard let observation = request.results?.first as? VNRectangleObservation else { return }
                regions.append(DetectedRegion(
                    type: .document,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: nil
                ))
            }

            // Barcode detection
            let barcodeRequest = VNDetectBarcodesRequest { request, error in
                guard let observations = request.results as? [VNBarcodeObservation] else { return }
                for observation in observations {
                    regions.append(DetectedRegion(
                        type: .barcode,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        preview: observation.payloadStringValue
                    ))
                }
            }

            // Scene classification
            let classifyRequest = VNClassifyImageRequest { request, error in
                guard let observations = request.results as? [VNClassificationObservation] else { return }

                let topClassifications = observations
                    .filter { $0.confidence > 0.3 }
                    .prefix(3)

                for classification in topClassifications {
                    let label = classification.identifier.replacingOccurrences(of: "_", with: " ").capitalized
                    sceneLabels.append(label)
                    regions.append(DetectedRegion(
                        type: .scene,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                        confidence: classification.confidence,
                        preview: label
                    ))
                }
            }

            // Animal/Object detection
            let animalRequest = VNRecognizeAnimalsRequest { request, error in
                guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }

                for observation in observations {
                    let label = observation.labels.first?.identifier ?? "Animal"
                    detectedObjects.append(label.capitalized)
                    regions.append(DetectedRegion(
                        type: .object,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        preview: label.capitalized
                    ))
                }
            }

            // Face detection
            let faceRequest = VNDetectFaceRectanglesRequest { request, error in
                guard let observations = request.results as? [VNFaceObservation] else { return }

                for observation in observations {
                    regions.append(DetectedRegion(
                        type: .face,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        preview: "Face"
                    ))
                }
            }

            // Human body detection
            let humanRequest = VNDetectHumanRectanglesRequest { request, error in
                guard let observations = request.results as? [VNHumanObservation] else { return }

                for observation in observations {
                    regions.append(DetectedRegion(
                        type: .human,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        preview: "Person"
                    ))
                }
            }

            // Limit concurrent Vision requests to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([textRequest, documentRequest, barcodeRequest, classifyRequest, animalRequest, faceRequest, humanRequest])
                } catch {
                    // Silent failure for live analysis
                }
            }

            continuation.resume(returning: FrameAnalysis(
                regions: regions,
                recognizedText: recognizedText.trimmingCharacters(in: .whitespacesAndNewlines),
                aestheticsScore: aestheticsScore,
                sceneLabels: sceneLabels,
                detectedObjects: detectedObjects,
                humanPoses: [],  // Not needed for bridge
                animalPoses: [],  // Not needed for bridge
                lensSmudgeDetected: false
            ))
        }
    }
}

// MARK: - Vision Helpers

@preconcurrency import Vision

//
//  VisualIntelligenceIntents.swift
//  OpenIntelligence
//
//  Visual Intelligence integration for camera-based document analysis.
//  Extends AppIntents to support Visual Intelligence actions:
//  - Analyze photos/screenshots for document ingestion
//  - Extract text from camera captures via Visual Intelligence
//  - Search documents using visual context from camera
//

import AppIntents
import Foundation
import SwiftUI
import Vision

// MARK: - Analyze Image Intent

/// Analyze an image using Visual Intelligence and RAG
/// Triggered from camera Control Center or share sheet
@available(iOS 26.0, *)
struct AnalyzeImageIntent: AppIntent {
    static var title: LocalizedStringResource = "Analyze Image with RAG"
    static var description: IntentDescription = .init(
        "Extract and analyze text from an image using your document library",
        categoryName: "Visual Intelligence",
        searchKeywords: ["image", "photo", "camera", "visual", "analyze", "ocr"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Image", description: "The image to analyze")
    var imageFile: IntentFile

    @Parameter(
        title: "Question",
        description: "Optional question about the image content",
        default: ""
    )
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$imageFile)") {
            \.$question
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        Log.info("[VisualIntelligence] Analyze Image intent invoked", category: .pipeline)

        let imageData = imageFile.data

        // Extract text using Vision OCR
        let extractedText = try await extractText(from: imageData)

        guard !extractedText.isEmpty else {
            return .result(
                dialog: "No text was found in the image.",
                view: ErrorSnippetView(message: "No text detected")
            )
        }

        // If a question was asked, query RAG with the extracted context
        if !question.isEmpty {
            let ragService = await MainActor.run { RAGService() }
            let config = InferenceConfig(maxTokens: 300, temperature: 0.7)

            do {
                let response = try await ragService.query(question, topK: 3, config: config)
                let answer = response.generatedResponse

                return .result(
                    dialog: IntentDialog(stringLiteral: String(answer.prefix(500))),
                    view: VisualAnalysisSnippetView(
                        extractedText: String(extractedText.prefix(200)),
                        answer: answer,
                        question: question
                    )
                )
            } catch {
                return .result(
                    dialog: "Found text but couldn't query: \(error.localizedDescription)",
                    view: VisualAnalysisSnippetView(
                        extractedText: extractedText,
                        answer: nil,
                        question: question
                    )
                )
            }
        }

        // No question — just return the extracted text
        return .result(
            dialog: IntentDialog(stringLiteral: "Found \(extractedText.split(separator: " ").count) words of text."),
            view: VisualAnalysisSnippetView(
                extractedText: extractedText,
                answer: nil,
                question: nil
            )
        )
    }

    /// Extract text from image data using Vision framework
    private func extractText(from imageData: Data) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return ""
        }

        let texts = observations
            .compactMap { $0.topCandidates(1).first?.string }
        return texts.joined(separator: "\n")
    }
}

// MARK: - Ingest from Camera Intent

/// Capture and ingest a document from the camera
@available(iOS 26.0, *)
struct IngestFromCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "Ingest Document from Camera"
    static var description: IntentDescription = .init(
        "Capture a document with your camera and add it to your knowledge base",
        categoryName: "Visual Intelligence",
        searchKeywords: ["camera", "capture", "scan", "ingest", "document"]
    )

    static var openAppWhenRun: Bool = true  // Need camera UI

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(
            dialog: "Opening camera for document capture..."
        )
    }
}

// MARK: - Visual Search Intent

/// Search documents using a photo as context
@available(iOS 26.0, *)
struct VisualSearchIntent: AppIntent {
    static var title: LocalizedStringResource = "Visual Document Search"
    static var description: IntentDescription = .init(
        "Search your documents using text from a photo",
        categoryName: "Visual Intelligence",
        searchKeywords: ["visual", "search", "photo", "find"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Photo", description: "Photo to extract search context from")
    var photo: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Search documents using \(\.$photo)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        Log.info("[VisualIntelligence] Visual Search intent invoked", category: .pipeline)

        let imageData = photo.data

        // Extract text from the photo
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])

        let extractedText = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ") ?? ""

        guard !extractedText.isEmpty else {
            return .result(
                dialog: "No text found in the photo to search with.",
                view: ErrorSnippetView(message: "No searchable text")
            )
        }

        // Use extracted text as a query
        let ragService = await MainActor.run { RAGService() }
        let config = InferenceConfig(maxTokens: 300, temperature: 0.7)

        do {
            let searchQuery = "Based on this text: \(String(extractedText.prefix(200)))"
            let response = try await ragService.query(searchQuery, topK: 5, config: config)

            return .result(
                dialog: IntentDialog(stringLiteral: String(response.generatedResponse.prefix(400))),
                view: VisualAnalysisSnippetView(
                    extractedText: String(extractedText.prefix(200)),
                    answer: response.generatedResponse,
                    question: "Visual search from photo"
                )
            )
        } catch {
            return .result(
                dialog: "Search failed: \(error.localizedDescription)",
                view: ErrorSnippetView(message: error.localizedDescription)
            )
        }
    }
}



// MARK: - Snippet Views

@available(iOS 16.0, *)
struct VisualAnalysisSnippetView: View {
    let extractedText: String
    let answer: String?
    let question: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let question = question {
                Text(question)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let answer = answer {
                Text(answer)
                    .font(.body)
                    .lineLimit(8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Extracted Text")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(extractedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding()
    }
}

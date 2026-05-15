//
//  CoreMLDocumentClassifier.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/24/26.
//
//  FastViT-based document content classification for intelligent routing
//  Uses Apple's pre-trained FastViT T8 model (8.2MB, <1ms inference)
//  Download: https://developer.apple.com/machine-learning/models/
//

import CoreML
import CoreImage
import Foundation
import Vision

// MARK: - Document Content Types

/// High-level document content classification for routing
enum DocumentContentType: String, Sendable, CaseIterable {
    case textDocument       // Plain text, articles, reports
    case form               // Forms with fields to fill
    case receipt            // Receipts, invoices, bills
    case diagram            // Flowcharts, architecture diagrams
    case chart              // Bar charts, pie charts, graphs
    case photograph         // Photos embedded in documents
    case technicalDrawing   // Blueprints, schematics, CAD
    case presentation       // Slides, decks
    case spreadsheet        // Tables, grids of data
    case handwritten        // Handwritten notes
    case mixed              // Multiple content types detected
    case unknown            // Could not classify

    /// Processing hints for each content type
    var processingHints: ProcessingHints {
        switch self {
        case .textDocument:
            return ProcessingHints(
                ocrAccuracy: .standard,
                preserveLayout: false,
                extractTables: false,
                chunkingPreset: .narrative
            )
        case .form:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: true,
                chunkingPreset: .default
            )
        case .receipt:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: true,
                chunkingPreset: .default
            )
        case .diagram:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: false,
                chunkingPreset: .default
            )
        case .technicalDrawing:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: false,
                chunkingPreset: .technical
            )
        case .chart:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: true,
                chunkingPreset: .default
            )
        case .spreadsheet:
            return ProcessingHints(
                ocrAccuracy: .standard,
                preserveLayout: true,
                extractTables: true,
                chunkingPreset: .default
            )
        case .photograph:
            return ProcessingHints(
                ocrAccuracy: .standard,
                preserveLayout: false,
                extractTables: false,
                chunkingPreset: .narrative
            )
        case .presentation:
            return ProcessingHints(
                ocrAccuracy: .standard,
                preserveLayout: true,
                extractTables: true,
                chunkingPreset: .narrative
            )
        case .handwritten:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: false,
                chunkingPreset: .narrative
            )
        case .mixed, .unknown:
            return ProcessingHints(
                ocrAccuracy: .high,
                preserveLayout: true,
                extractTables: true,
                chunkingPreset: .default
            )
        }
    }
}

/// Processing configuration hints based on content type
struct ProcessingHints: Sendable, Equatable {
    enum OCRAccuracy: Sendable, Equatable {
        case standard   // Faster, 216 DPI
        case high       // Slower, 360 DPI
    }

    enum ChunkingPreset: Sendable, Equatable {
        case narrative   // 400 words, more overlap
        case technical   // 280 words, structured
        case `default`   // 350 words, balanced
    }

    let ocrAccuracy: OCRAccuracy
    let preserveLayout: Bool
    let extractTables: Bool
    let chunkingPreset: ChunkingPreset
}

/// Classification result with confidence
struct DocumentClassificationResult: Sendable {
    let contentType: DocumentContentType
    let confidence: Float
    let allClassifications: [(type: DocumentContentType, confidence: Float)]
    let processingHints: ProcessingHints

    /// Whether classification is confident enough to use
    var isHighConfidence: Bool { confidence >= 0.7 }
}

// MARK: - Document Classifier Service

/// Service for classifying document content using CoreML models
/// Uses FastViT T8 (8.2MB) for efficient on-device classification
actor CoreMLDocumentClassifier {

    static let shared = CoreMLDocumentClassifier()
    private nonisolated static let visionRenderContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: - Model State

    // Keep the backing Core ML model alive alongside the Vision wrapper.
    // We've seen cooperative-queue teardown crashes when only the VNCoreMLModel is retained.
    private var visionModel: VNCoreMLModel?
    private var backingModel: MLModel?
    private var isModelLoaded = false
    private var modelLoadError: Error?

    /// ImageNet labels mapped to document content types
    /// FastViT is trained on ImageNet-1K, so we map relevant classes
    private let imagenetToDocumentType: [String: DocumentContentType] = [
        // Document-like classes
        "envelope": .textDocument,
        "book_jacket": .textDocument,
        "binder": .textDocument,
        "notebook": .handwritten,
        "letter_opener": .textDocument,

        // Form/receipt-like
        "menu": .form,
        "grocery_store": .receipt,
        "cash_machine": .receipt,
        "wallet": .receipt,

        // Chart/diagram classes
        "web_site": .diagram,
        "crossword_puzzle": .diagram,
        "jigsaw_puzzle": .diagram,
        "maze": .diagram,

        // Technical
        "monitor": .presentation,
        "screen": .presentation,
        "desktop_computer": .presentation,
        "laptop": .presentation,
        "notebook_computer": .presentation,

        // Spreadsheet indicators
        "abacus": .spreadsheet,
        "calculator": .spreadsheet,
        "rule": .spreadsheet,

        // Photo classes (subset)
        "studio_couch": .photograph,
        "window_shade": .photograph,
        "window_screen": .photograph,
    ]

    private init() {}

    // MARK: - Model Loading

    /// Load FastViT model on demand
    func loadModel() async throws {
        guard !isModelLoaded else { return }

        // Check if model file exists
        guard let modelURL = OpenIntelligenceResourceBundle.url(forResource: "FastViTT8F16", withExtension: "mlmodelc") else {
            // Model not bundled - use Vision fallback
            Log.info("[CoreMLDocumentClassifier] FastViT model not bundled, using Vision framework fallback", category: .initialization)
            throw ClassifierError.modelNotFound
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine // Prefer ANE for efficiency

            let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
            backingModel = mlModel
            visionModel = try VNCoreMLModel(for: mlModel)
            isModelLoaded = true

            Log.info("[CoreMLDocumentClassifier] ✓ FastViT T8 model loaded successfully", category: .initialization)
        } catch {
            modelLoadError = error
            Log.warning("[CoreMLDocumentClassifier] Failed to load FastViT: \(error.localizedDescription)", category: .initialization)
            throw error
        }
    }

    // MARK: - Classification

    /// Classify a document page image
    /// - Parameter image: CIImage of the document page
    /// - Returns: Classification result with content type and confidence
    func classify(_ image: CIImage) async -> DocumentClassificationResult {
        // Try CoreML model first
        do {
            try await loadModel()
            if let model = visionModel, let backingModel = backingModel {
                return try await classifyWithCoreML(image, model: model, backingModel: backingModel)
            }
        } catch {
            // Fall through to Vision fallback
        }

        // Fallback: Use Vision framework classification
        return await classifyWithVision(image)
    }

    /// Classify using FastViT CoreML model
    private func classifyWithCoreML(_ image: CIImage, model: VNCoreMLModel, backingModel: MLModel) async throws -> DocumentClassificationResult {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        // Limit concurrent Vision requests to prevent Metal race conditions
        try withExtendedLifetime(backingModel) {
            try VisionOCRThrottle.performSync {
                try handler.perform([request])
            }
        }

        guard let results = request.results as? [VNClassificationObservation] else {
            return DocumentClassificationResult(
                contentType: .unknown,
                confidence: 0,
                allClassifications: [],
                processingHints: Self.getProcessingHints(for: .unknown)
            )
        }

        // Map ImageNet classes to document types
        var typeScores: [DocumentContentType: Float] = [:]

        for observation in results.prefix(20) {
            let identifier = observation.identifier.lowercased()

            // Check direct mapping
            if let docType = imagenetToDocumentType[identifier] {
                typeScores[docType, default: 0] += observation.confidence
            }

            // Heuristic keyword matching
            if identifier.contains("diagram") || identifier.contains("chart") {
                typeScores[.diagram, default: 0] += observation.confidence
            }
            if identifier.contains("document") || identifier.contains("paper") || identifier.contains("page") {
                typeScores[.textDocument, default: 0] += observation.confidence
            }
            if identifier.contains("photo") || identifier.contains("portrait") {
                typeScores[.photograph, default: 0] += observation.confidence
            }
            if identifier.contains("table") || identifier.contains("grid") {
                typeScores[.spreadsheet, default: 0] += observation.confidence
            }
        }

        // Find best match
        let sorted = typeScores.sorted { $0.value > $1.value }
        let bestType = sorted.first?.key ?? .unknown
        let bestConfidence = sorted.first?.value ?? 0

        // Detect mixed content if multiple types have significant scores
        let significantTypes = sorted.filter { $0.value > 0.2 }
        let finalType = significantTypes.count > 2 ? .mixed : bestType

        return DocumentClassificationResult(
            contentType: finalType,
            confidence: bestConfidence,
            allClassifications: sorted.map { ($0.key, $0.value) },
            processingHints: Self.getProcessingHints(for: finalType)
        )
    }

    /// Fallback classification using Vision framework
    private func classifyWithVision(_ image: CIImage) async -> DocumentClassificationResult {
        guard let cgImage = materializedCGImage(from: image) else {
            Log.warning("[CoreMLDocumentClassifier] Failed to materialize image for Vision fallback", category: .ingestion)
            return DocumentClassificationResult(
                contentType: .textDocument,
                confidence: 0.5,
                allClassifications: [(.textDocument, 0.5)],
                processingHints: Self.getProcessingHints(for: .textDocument)
            )
        }

        // Use built-in Vision classification
        if #available(iOS 18.0, *) {
            do {
                let request = ClassifyImageRequest()
                // Throttle Vision operations to prevent Metal GPU race conditions
                let results = try await VisionOCRThrottle.performAsync {
                    let observations = try await request.perform(on: cgImage)
                    return observations.prefix(20).map {
                        ImageClassification(identifier: $0.identifier, confidence: $0.confidence)
                    }
                }

                var typeScores: [DocumentContentType: Float] = [:]

                for observation in results {
                    let identifier = observation.identifier.lowercased()

                    // Map Vision classifications to document types
                    if identifier.contains("text") || identifier.contains("document") || identifier.contains("writing") {
                        typeScores[.textDocument, default: 0] += observation.confidence
                    }
                    if identifier.contains("diagram") || identifier.contains("flowchart") || identifier.contains("schematic") {
                        typeScores[.diagram, default: 0] += observation.confidence
                    }
                    if identifier.contains("chart") || identifier.contains("graph") || identifier.contains("plot") {
                        typeScores[.chart, default: 0] += observation.confidence
                    }
                    if identifier.contains("photo") || identifier.contains("picture") || identifier.contains("image") {
                        typeScores[.photograph, default: 0] += observation.confidence
                    }
                    if identifier.contains("table") || identifier.contains("grid") || identifier.contains("spreadsheet") {
                        typeScores[.spreadsheet, default: 0] += observation.confidence
                    }
                    if identifier.contains("form") || identifier.contains("application") {
                        typeScores[.form, default: 0] += observation.confidence
                    }
                    if identifier.contains("receipt") || identifier.contains("invoice") || identifier.contains("bill") {
                        typeScores[.receipt, default: 0] += observation.confidence
                    }
                    if identifier.contains("handwriting") || identifier.contains("handwritten") {
                        typeScores[.handwritten, default: 0] += observation.confidence
                    }
                    if identifier.contains("slide") || identifier.contains("presentation") {
                        typeScores[.presentation, default: 0] += observation.confidence
                    }
                    if identifier.contains("drawing") || identifier.contains("blueprint") || identifier.contains("technical") {
                        typeScores[.technicalDrawing, default: 0] += observation.confidence
                    }
                }

                let sorted = typeScores.sorted { $0.value > $1.value }
                let bestType = sorted.first?.key ?? .textDocument // Default to text
                let bestConfidence = sorted.first?.value ?? 0.5

                return DocumentClassificationResult(
                    contentType: bestType,
                    confidence: bestConfidence,
                    allClassifications: sorted.map { ($0.key, $0.value) },
                    processingHints: Self.getProcessingHints(for: bestType)
                )
            } catch {
                Log.warning("[CoreMLDocumentClassifier] Vision classification failed: \(error)", category: .ingestion)
            }
        }

        // Ultimate fallback - assume text document
        return DocumentClassificationResult(
            contentType: .textDocument,
            confidence: 0.5,
            allClassifications: [(.textDocument, 0.5)],
            processingHints: Self.getProcessingHints(for: .textDocument)
        )
    }

    private nonisolated func materializedCGImage(from image: CIImage) -> CGImage? {
        Self.visionRenderContext.createCGImage(image, from: image.extent)
    }

    // MARK: - Helper

    /// Get processing hints for a content type (nonisolated to avoid actor isolation issues)
    private nonisolated static func getProcessingHints(for contentType: DocumentContentType) -> ProcessingHints {
        switch contentType {
        case .textDocument:
            return ProcessingHints(ocrAccuracy: .standard, preserveLayout: false, extractTables: false, chunkingPreset: .narrative)
        case .form, .receipt:
            return ProcessingHints(ocrAccuracy: .high, preserveLayout: true, extractTables: true, chunkingPreset: .default)
        case .diagram:
            return ProcessingHints(ocrAccuracy: .high, preserveLayout: true, extractTables: false, chunkingPreset: .default)
        case .technicalDrawing:
            return ProcessingHints(ocrAccuracy: .high, preserveLayout: true, extractTables: false, chunkingPreset: .technical)
        case .chart, .spreadsheet:
            return ProcessingHints(ocrAccuracy: .high, preserveLayout: true, extractTables: true, chunkingPreset: .default)
        case .photograph:
            return ProcessingHints(ocrAccuracy: .standard, preserveLayout: false, extractTables: false, chunkingPreset: .narrative)
        case .presentation:
            return ProcessingHints(ocrAccuracy: .standard, preserveLayout: true, extractTables: true, chunkingPreset: .narrative)
        case .handwritten:
            return ProcessingHints(ocrAccuracy: .high, preserveLayout: true, extractTables: false, chunkingPreset: .narrative)
        case .mixed, .unknown:
            return ProcessingHints(ocrAccuracy: .high, preserveLayout: true, extractTables: true, chunkingPreset: .default)
        }
    }

    // MARK: - Errors

    enum ClassifierError: Error {
        case modelNotFound
        case classificationFailed(String)
    }
}

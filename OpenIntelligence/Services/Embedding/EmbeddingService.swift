//
//  EmbeddingService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Accelerate
import Foundation
import NaturalLanguage

/// Helper to silence deprecation warning for legacy NLEmbeddingProvider
@available(iOS, deprecated: 999.0, message: "Use CoreMLSentenceEmbeddingProvider instead")
private func makeLegacyNLEmbeddingProvider() -> NLEmbeddingProvider {
    NLEmbeddingProvider()
}

/// Service for generating semantic embeddings from text using Apple's on-device models
class EmbeddingService {
    // MARK: - Properties

    private let provider: EmbeddingProvider
    private let targetDimension: Int
    private let providerIdentifier: String
    private var dimensionAdjustmentCount = 0

    /// The actual provider ID being used (may differ from requested if fallback occurred)
    var actualProviderId: String { providerIdentifier }

    // MARK: - Token Counting (Critical for Chunk Validation)

    /// Count ACTUAL tokens that will be used during embedding
    /// This uses the real tokenizer, not linguistic word count
    /// Example: "VHA21\VHAPALGarciG1" = 1 word but 10+ tokens
    func countTokens(_ text: String) -> Int {
        provider.countTokens(text)
    }

    /// Maximum safe token count for this provider
    var maxSafeTokens: Int { provider.maxSafeTokens }

    // MARK: - Ingestion Mode (GPU + ANE Parallelism)

    /// Enable ingestion mode - forces embeddings to GPU so ANE can focus on Vision OCR
    /// This creates true parallelism: GPU handles embeddings while ANE handles Vision OCR
    /// Call this before starting document ingestion for up to 2x throughput
    func enableIngestionMode() {
        provider.enableIngestionMode()
    }

    /// Disable ingestion mode - returns to default compute units
    func disableIngestionMode() {
        provider.disableIngestionMode()
    }

    // MARK: - Initialization

    init(
        provider: EmbeddingProvider = CoreMLSentenceEmbeddingProvider(),
        providerId: String = "coreml_sentence_embedding",
        targetDimension: Int? = nil
    ) {
        self.provider = provider
        self.targetDimension = targetDimension ?? provider.dimension
        providerIdentifier = providerId
        if !provider.isAvailable {
            Log.warning("[EmbeddingService] Provider '\(providerId)' not available on this device", category: .embedding)
        }
    }

    /// Factory method to create an EmbeddingService based on provider ID
    /// Used for per-container embedding provider selection
    static func forProvider(
        id: String,
        targetDimension: Int? = nil,
        allowFallback: Bool = true
    ) -> EmbeddingService {
        // Map provider IDs to their native (supported) dimensions
        // This prevents mismatched dimension configurations
        // NOTE: CoreML model (MiniLM-L6-v2) ONLY outputs 384D - this is fixed by the model architecture
        let nativeDimensions: [String: [Int]] = [
            "nl_embedding": [512],
            "nl_contextual_embedding": [512],
            "coreml_sentence_embedding": [384],  // MiniLM-L6-v2 is fixed at 384D
            "apple_fm_embed": [1024],
        ]

        // Validate target dimension against provider's supported dimensions
        func validatedDimension(for providerId: String, requested: Int?) -> Int? {
            guard let requested = requested,
                  let supported = nativeDimensions[providerId]
            else {
                return nil // Use provider's default
            }
            if supported.contains(requested) {
                return requested
            }
            Log.warning(
                "[EmbeddingService] Dimension \(requested) not supported by \(providerId), using provider default",
                category: .embedding
            )
            return nil // Provider will use its native dimension
        }

        let resolved: EmbeddingService
        switch id {
        case "coreml_sentence_embedding":
            resolved = EmbeddingService(
                provider: CoreMLSentenceEmbeddingProvider(),
                providerId: "coreml_sentence_embedding",
                targetDimension: validatedDimension(for: "coreml_sentence_embedding", requested: targetDimension)
            )
        case "apple_fm_embed":
            resolved = EmbeddingService(
                provider: AppleFMEmbeddingProvider(),
                providerId: "apple_fm_embed",
                targetDimension: validatedDimension(for: "apple_fm_embed", requested: targetDimension)
            )
        case "nl_embedding":
            // NLEmbeddingProvider is deprecated but kept for legacy compatibility
            resolved = EmbeddingService(
                provider: Self.makeLegacyNLEmbeddingProvider(),
                providerId: "nl_embedding",
                targetDimension: validatedDimension(for: "nl_embedding", requested: targetDimension)
            )
        default:
            Log.warning(
                "Unknown embedding provider '\(id)', defaulting to CoreMLSentenceEmbedding",
                category: .embedding
            )
            resolved = EmbeddingService(
                provider: CoreMLSentenceEmbeddingProvider(),
                providerId: "coreml_sentence_embedding",
                targetDimension: validatedDimension(for: "coreml_sentence_embedding", requested: targetDimension)
            )
        }

        // Check availability and handle fallback
        if resolved.isAvailable {
            Log.info("[EmbeddingService] Using provider '\(resolved.actualProviderId)' (available: true)", category: .embedding)
            return resolved
        }

        guard allowFallback else {
            Log.warning("[EmbeddingService] Provider '\(id)' unavailable and fallback disabled.", category: .embedding)
            return resolved
        }

        Log.warning("[EmbeddingService] Provider '\(id)' unavailable. Attempting fallback.", category: .embedding)

        // 1. Try CoreML Sentence Embedding (Preferred)
        // Only try if we haven't already tried it (i.e., if id wasn't "coreml_sentence_embedding")
        if id != "coreml_sentence_embedding" {
            let coreMLService = EmbeddingService(
                provider: CoreMLSentenceEmbeddingProvider(),
                providerId: "coreml_sentence_embedding",
                targetDimension: nil
            )
            if coreMLService.isAvailable {
                Log.info("[EmbeddingService] Falling back to CoreMLSentenceEmbedding", category: .embedding)
                return coreMLService
            }
        }

        // 2. Try NLEmbedding (Last Resort - Always Available)
        // NLEmbeddingProvider is deprecated but kept as ultimate fallback
        Log.warning("[EmbeddingService] CoreML unavailable. Falling back to NLEmbeddingProvider.", category: .embedding)
        return EmbeddingService(
            provider: Self.makeLegacyNLEmbeddingProvider(),
            providerId: "nl_embedding",
            targetDimension: 512
        )
    }

    // MARK: - Legacy Provider Helper

    /// Helper to instantiate the deprecated NLEmbeddingProvider.
    /// This is intentional: we keep NLEmbedding as an ultimate fallback for devices where CoreML fails.
    /// Returns `any EmbeddingProvider` to avoid exposing deprecated type in signature.
    @inline(__always)
    private static func makeLegacyNLEmbeddingProvider() -> any EmbeddingProvider {
        // Delegate to top-level function which has @available(iOS, deprecated: 999.0)
        // to suppress the NLEmbeddingProvider deprecation warning
        OpenIntelligence.makeLegacyNLEmbeddingProvider()
    }

    // MARK: - Public API

    /// Check if embedding generation is available on this device
    var isAvailable: Bool {
        return provider.isAvailable
    }

    /// The dimensionality this service will output after adjustments
    var outputDimension: Int {
        targetDimension
    }

    /// Generate a semantic embedding for a text chunk
    /// Returns a vector representing the semantic meaning
    func generateEmbedding(for text: String) async throws -> [Float] {
        // Report ANE activity - single embedding
        HardwareTelemetryReporter.pulse(.embeddingGeneration, intensity: 0.8, duration: 0.15)
        HardwareTelemetryReporter.reportEmbedding(count: 1)

        do {
            let vec = try await provider.embed(text: text)
            let adjusted = adjustDimension(vec)
            try validateEmbedding(adjusted)
            return adjusted
        } catch {
            throw EmbeddingError.wrap(error, provider: providerIdentifier)
        }
    }

    /// Generate embeddings for multiple text chunks in batch with optional progress callback
    func generateEmbeddings(
        for texts: [String],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        // Report ANE activity - batch embedding (sustained while processing)
        let intensity = min(1.0, 0.5 + Double(texts.count) * 0.05)
        HardwareTelemetryReporter.sustain(.embeddingGeneration, active: true, intensity: intensity)
        HardwareTelemetryReporter.reportEmbedding(count: texts.count)
        defer { HardwareTelemetryReporter.sustain(.embeddingGeneration, active: false) }

        do {
            Log.debug("Generating embeddings for \(texts.count) chunks", category: .embedding)
            let startTime = Date()

            // If no progress handler, use the fast batch method
            guard let progressHandler = progressHandler else {
                let rawEmbeddings = try await provider.embedBatch(texts: texts)
                let embeddings = rawEmbeddings.map { adjustDimension($0) }
                let totalTime = Date().timeIntervalSince(startTime)
                let avgTime = texts.isEmpty ? 0 : totalTime / Double(texts.count)
                Log.info("Embedded \(texts.count) chunks in \(String(format: "%.2f", totalTime))s (avg: \(String(format: "%.0f", avgTime * 1000))ms)", category: .embedding)
                return embeddings
            }

            // With progress handler, process in smaller batches to report progress
            let batchSize = 16 // Report progress every 16 chunks
            var allEmbeddings: [[Float]] = []
            allEmbeddings.reserveCapacity(texts.count)

            for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, texts.count)
                let batch = Array(texts[batchStart..<batchEnd])

                let rawBatch = try await provider.embedBatch(texts: batch)
                let adjusted = rawBatch.map { adjustDimension($0) }
                allEmbeddings.append(contentsOf: adjusted)

                // Report progress
                progressHandler(batchEnd, texts.count)
            }

            let totalTime = Date().timeIntervalSince(startTime)
            let avgTime = texts.isEmpty ? 0 : totalTime / Double(texts.count)
            Log.info("Embedded \(texts.count) chunks in \(String(format: "%.2f", totalTime))s (avg: \(String(format: "%.0f", avgTime * 1000))ms)", category: .embedding)
            return allEmbeddings
        } catch {
            throw EmbeddingError.wrap(error, provider: providerIdentifier)
        }
    }

    /// Generate embeddings for multiple text chunks in batch (no progress callback)
    func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        try await generateEmbeddings(for: texts, progressHandler: nil)
    }

    // MARK: - Validation

    /// Validate that an embedding is well-formed
    private func validateEmbedding(_ embedding: [Float]) throws {
        // Check dimensionality
        guard embedding.count == targetDimension else {
            Log.error("Invalid dimension: \(embedding.count) (expected \(targetDimension))", category: .embedding)
            throw EmbeddingError.invalidDimension(expected: targetDimension, actual: embedding.count)
        }

        // Check for NaN or Inf values
        for (index, value) in embedding.enumerated() {
            if value.isNaN {
                Log.error("NaN detected at index \(index)", category: .embedding)
                throw EmbeddingError.containsNaN
            }
            if value.isInfinite {
                Log.error("Infinite value at index \(index)", category: .embedding)
                throw EmbeddingError.containsInfinite
            }
        }

        // Check that embedding is not all zeros (likely indicates an error)
        let magnitude = embedding.reduce(0.0) { $0 + $1 * $1 }
        if magnitude < 0.0001 {
            Log.warning("Near-zero embedding vector", category: .embedding)
        }
    }

    // MARK: - Private Helpers

    /// Average multiple token embeddings into a single chunk-level embedding
    /// This produces a fixed-size representation regardless of input length
    private func averageEmbeddings(_ vectors: [[Double]]) -> [Float] {
        guard !vectors.isEmpty else {
            return Array(repeating: 0.0, count: targetDimension)
        }

        let count = vectors.count
        var averaged = Array(repeating: 0.0, count: targetDimension)

        // Sum all vectors
        for vector in vectors {
            for (i, value) in vector.enumerated() {
                if i < targetDimension {
                    averaged[i] += value
                }
            }
        }

        // Divide by count to get average
        for i in 0 ..< targetDimension {
            averaged[i] /= Double(count)
        }

        // Convert to Float for efficient storage
        return averaged.map { Float($0) }
    }

    /// Create a fallback embedding when the model fails to embed the text.
    /// Returns a ZERO VECTOR instead of the previous Unicode-hash approach which
    /// produced vectors in a completely different space than the model's output,
    /// causing meaningless cosine similarities and polluting search results.
    ///
    /// A zero vector has cosine similarity 0.0 with everything, which means:
    /// - It won't be retrieved by vector search (correctly)
    /// - It won't incorrectly match any query
    /// - BM25/FTS5 keyword search can still find the chunk via text matching
    private func createFallbackEmbedding(for text: String) -> [Float] {
        Log.warning("[EmbeddingService] Creating zero-vector fallback for text (\(text.prefix(50))...). This chunk will only be findable via keyword/BM25 search.", category: .embedding)
        return Array(repeating: Float(0.0), count: targetDimension)
    }

    /// Calculate cosine similarity between two embedding vectors using Accelerate.
    /// Returns a value between -1 (opposite) and 1 (identical).
    /// Uses vDSP_dotpr + vDSP_svesq for hardware-accelerated computation.
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else {
            Log.warning("Embedding dimension mismatch in cosine similarity", category: .embedding)
            return 0.0
        }

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        let magnitudeA = sqrt(vDSP.sumOfSquares(a))
        let magnitudeB = sqrt(vDSP.sumOfSquares(b))
        let magnitude = magnitudeA * magnitudeB

        guard magnitude > 1e-9 else { return 0.0 }
        return dotProduct / magnitude
    }

    private func adjustDimension(_ vector: [Float]) -> [Float] {
        if vector.count == targetDimension {
            return vector
        }

        if vector.count > targetDimension {
            recordAdjustment(for: vector.count)
            Log.warning(
                "Truncating embedding from \(vector.count) → \(targetDimension) dimensions",
                category: .embedding
            )
            return Array(vector.prefix(targetDimension))
        }

        recordAdjustment(for: vector.count)
        Log.warning(
            "Padding embedding from \(vector.count) → \(targetDimension) dimensions",
            category: .embedding
        )
        return vector + Array(repeating: 0.0, count: targetDimension - vector.count)
    }

    private func recordAdjustment(for actualDimension: Int) {
        dimensionAdjustmentCount += 1

        if dimensionAdjustmentCount == 1 || dimensionAdjustmentCount.isMultiple(of: 25) {
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Embedding dimension auto-adjusted",
                metadata: [
                    "provider": providerIdentifier,
                    "target": "\(targetDimension)",
                    "actual": "\(actualDimension)",
                    "occurrences": "\(dimensionAdjustmentCount)",
                ]
            )
        }

        if dimensionAdjustmentCount > 100 {
            // Log error instead of crashing - this can happen with legacy containers
            // that have mismatched embeddingDim settings. User should rebuild the library.
            if dimensionAdjustmentCount == 101 {
                // Only log once at the threshold to avoid spam
                Log.error(
                    """
                    Embedding dimension mismatch detected 100+ times for provider \(providerIdentifier). \
                    Target: \(targetDimension), Actual: \(actualDimension). \
                    Consider rebuilding the library with matching dimensions.
                    """,
                    category: .embedding
                )
                TelemetryCenter.emit(
                    .system,
                    severity: .error,
                    title: "Embedding dimension mismatch - rebuild recommended",
                    metadata: [
                        "provider": providerIdentifier,
                        "target": "\(targetDimension)",
                        "actual": "\(actualDimension)",
                    ]
                )
            }
        }
    }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case modelUnavailable
    case emptyInput
    case generationFailed(String)
    case noVectorsReturned
    case invalidDimension(expected: Int, actual: Int)
    case containsNaN
    case containsInfinite
    case notImplemented
    case outputParsingFailed
    case embeddingFailed(String) // General embedding failure with description
    case custom(String)
    case providerFailed(provider: String, underlying: String) // Provider-specific error for better debugging

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Embedding model is not available on this device"
        case .emptyInput:
            return "Cannot generate embedding for empty text"
        case let .generationFailed(message):
            return "Embedding generation failed: \(message)"
        case .noVectorsReturned:
            return "No embedding vectors were returned"
        case let .invalidDimension(expected, actual):
            return "Invalid embedding dimension: expected \(expected), got \(actual)"
        case .containsNaN:
            return "Embedding contains NaN values"
        case .containsInfinite:
            return "Embedding contains infinite values"
        case .notImplemented:
            return "This embedding functionality is not yet implemented"
        case .outputParsingFailed:
            return "Failed to parse model output tensor"
        case let .embeddingFailed(message):
            return "Embedding failed: \(message)"
        case let .custom(message):
            return message
        case let .providerFailed(provider, underlying):
            return "[\(provider)] \(underlying)"
        }
    }

    /// Wraps an error with provider context for better debugging
    static func wrap(_ error: Error, provider: String) -> EmbeddingError {
        if let embeddingError = error as? EmbeddingError {
            // Already an embedding error, add provider context if not present
            switch embeddingError {
            case .providerFailed:
                return embeddingError // Already has context
            default:
                return .providerFailed(provider: provider, underlying: embeddingError.errorDescription ?? "Unknown error")
            }
        }
        return .providerFailed(provider: provider, underlying: error.localizedDescription)
    }
}

//
//  NLContextualEmbeddingProvider.swift
//  OpenIntelligence
//
//  HIGH-ACCURACY contextual embeddings using Apple's NLContextualEmbedding (iOS 17+)
//  Unlike NLEmbedding's static word vectors, this provides BERT-like contextual understanding.
//
//  Key differences from NLEmbedding:
//  - Context-aware: "bank" near "river" ≠ "bank" near "money"
//  - Per-token embeddings that can be pooled for sentence-level semantics
//  - Higher dimensional (typically 512-1024) with richer semantic capture
//  - Supports 27+ languages across Latin, Cyrillic, CJK, Arabic, Thai, Indic scripts
//
//  Expected accuracy improvement: 15-25% over NLEmbedding for semantic search
//

import Foundation
import NaturalLanguage

/// Contextual embedding provider using Apple's NLContextualEmbedding (iOS 17+)
/// Provides BERT-like embeddings that understand words in context
@available(iOS 17.0, macOS 14.0, *)
final class NLContextualEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    private var contextualEmbedding: NLContextualEmbedding?
    private let language: NLLanguage
    private let poolingStrategy: PoolingStrategy
    private var isLoaded: Bool = false
    private let loadLock = NSLock()

    /// Fallback provider for when contextual embedding isn't available
    private lazy var nlEmbeddingFallback: NLEmbeddingProvider = .init()

    /// Dimension of the contextual embedding model (typically 512 or 768)
    private(set) var dimension: Int = 512

    /// Pooling strategy for converting token-level embeddings to sentence-level
    enum PoolingStrategy: Sendable {
        case mean // Average all token embeddings (most common)
        case cls // Use first token embedding (BERT-style [CLS])
        case maxPool // Element-wise max across tokens (captures salient features)
        case meanMaxConcat // Concat mean + max for richer representation (doubles dimension)
    }

    // MARK: - Initialization

    /// Initialize with a specific language
    /// - Parameters:
    ///   - language: Target language for embeddings (default: English)
    ///   - pooling: Strategy for converting token embeddings to sentence embeddings
    init(language: NLLanguage = .english, pooling: PoolingStrategy = .mean) {
        self.language = language
        poolingStrategy = pooling

        // Try to create the contextual embedding model
        if let embedding = NLContextualEmbedding(language: language) {
            contextualEmbedding = embedding
            dimension = embedding.dimension

            Log.info(
                "[NLContextualEmbedding] Created for \(language.rawValue), dim=\(embedding.dimension)",
                category: .embedding
            )

            // Check if assets need to be downloaded
            if !embedding.hasAvailableAssets {
                Log.warning(
                    "[NLContextualEmbedding] Assets not available for \(language.rawValue), requesting download...",
                    category: .embedding
                )
                requestAssets()
            }
        } else {
            Log.warning(
                "[NLContextualEmbedding] Not available for \(language.rawValue)",
                category: .embedding
            )
        }

        // Adjust dimension for concat pooling
        if pooling == .meanMaxConcat, let emb = contextualEmbedding {
            dimension = emb.dimension * 2
        }
    }

    // MARK: - EmbeddingProvider Conformance

    var isAvailable: Bool {
        guard let embedding = contextualEmbedding else { return false }
        return embedding.hasAvailableAssets
    }

    func embed(text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EmbeddingError.emptyInput
        }

        // Ensure model is loaded
        try ensureLoaded()

        guard let embedding = contextualEmbedding else {
            // Fall back to NLEmbedding for better semantic quality than hash
            Log.warning("[NLContextualEmbedding] Assets not ready, falling back to NLEmbedding", category: .embedding)
            return try await nlEmbeddingFallback.embed(text: trimmed)
        }

        do {
            // Get contextual embedding result (per-token embeddings)
            let result = try embedding.embeddingResult(for: trimmed, language: language)

            // Pool token embeddings to sentence embedding
            let sentenceEmbedding = poolTokenEmbeddings(result: result, text: trimmed)

            return sentenceEmbedding

        } catch {
            Log.error(
                "[NLContextualEmbedding] Failed to embed text: \(error.localizedDescription)",
                category: .embedding
            )
            throw EmbeddingError.modelError(error.localizedDescription)
        }
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        // Process batch with parallel embedding
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let embedding = try await self.embed(text: text)
                    return (index, embedding)
                }
            }

            var results: [(Int, [Float])] = []
            for try await result in group {
                results.append(result)
            }

            // Sort by original index and extract embeddings
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - Private Methods

    /// Ensure the embedding model is loaded into memory
    private func ensureLoaded() throws {
        loadLock.lock()
        defer { loadLock.unlock() }

        guard !isLoaded, let embedding = contextualEmbedding else { return }

        do {
            try embedding.load()
            isLoaded = true
            Log.info("[NLContextualEmbedding] Model loaded successfully", category: .embedding)
        } catch {
            Log.error("[NLContextualEmbedding] Failed to load model: \(error)", category: .embedding)
            throw EmbeddingError.modelError("Failed to load contextual embedding model")
        }
    }

    /// Request asset download for the embedding model
    private func requestAssets() {
        guard let embedding = contextualEmbedding else { return }

        embedding.requestAssets { result, error in
            if let error = error {
                Log.error(
                    "[NLContextualEmbedding] Asset request failed: \(error.localizedDescription)",
                    category: .embedding
                )
                return
            }

            switch result {
            case .available:
                Log.info("[NLContextualEmbedding] Assets are now available", category: .embedding)
            case .notAvailable:
                Log.warning("[NLContextualEmbedding] Assets not available for download", category: .embedding)
            case .error:
                Log.error("[NLContextualEmbedding] Error downloading assets", category: .embedding)
            @unknown default:
                Log.warning("[NLContextualEmbedding] Unknown asset status", category: .embedding)
            }
        }
    }

    /// Pool token-level embeddings to a single sentence embedding
    private func poolTokenEmbeddings(result: NLContextualEmbeddingResult, text: String) -> [Float] {
        let range = text.startIndex ..< text.endIndex
        var allEmbeddings: [[Float]] = []

        // Enumerate all token embeddings in the result
        result.enumerateTokenVectors(in: range) { vector, _ in
            // Convert [Double] to [Float]
            let floatVector = vector.map { Float($0) }
            allEmbeddings.append(floatVector)
            return true // continue enumeration
        }

        guard !allEmbeddings.isEmpty else {
            // This is a synchronous context, so use hash fallback as last resort
            // Primary fallback to NLEmbedding happens at the async embed() level
            Log.warning("[NLContextualEmbedding] No token embeddings found, using hash fallback", category: .embedding)
            return createFallbackEmbedding(for: text)
        }

        let dim = allEmbeddings[0].count

        switch poolingStrategy {
        case .mean:
            return meanPool(embeddings: allEmbeddings, dimension: dim)

        case .cls:
            // Use first token (CLS-like behavior)
            return allEmbeddings[0]

        case .maxPool:
            return maxPool(embeddings: allEmbeddings, dimension: dim)

        case .meanMaxConcat:
            let meanVec = meanPool(embeddings: allEmbeddings, dimension: dim)
            let maxVec = maxPool(embeddings: allEmbeddings, dimension: dim)
            return meanVec + maxVec
        }
    }

    /// Mean pooling: average all embeddings element-wise
    private func meanPool(embeddings: [[Float]], dimension: Int) -> [Float] {
        var result = [Float](repeating: 0, count: dimension)
        let count = Float(embeddings.count)

        for embedding in embeddings {
            for i in 0 ..< dimension {
                result[i] += embedding[i]
            }
        }

        for i in 0 ..< dimension {
            result[i] /= count
        }

        return result
    }

    /// Max pooling: element-wise maximum across all embeddings
    private func maxPool(embeddings: [[Float]], dimension: Int) -> [Float] {
        var result = [Float](repeating: -.infinity, count: dimension)

        for embedding in embeddings {
            for i in 0 ..< dimension {
                result[i] = max(result[i], embedding[i])
            }
        }

        return result
    }

    /// Fallback hash-based embedding when model is unavailable
    private func createFallbackEmbedding(for text: String) -> [Float] {
        var embedding = [Float](repeating: 0, count: dimension)
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)

        for (wordIndex, word) in words.enumerated() {
            let hash = word.hashValue
            for i in 0 ..< dimension {
                let position = abs((hash &+ i &* 31) % dimension)
                let contribution = Float(hash % 1000) / 1000.0 * (wordIndex % 2 == 0 ? 1 : -1)
                embedding[position] += contribution
            }
        }

        // L2 normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            for i in 0 ..< dimension {
                embedding[i] /= magnitude
            }
        }

        return embedding
    }

    /// Unload the model to free memory
    func unload() {
        loadLock.lock()
        defer { loadLock.unlock() }

        contextualEmbedding?.unload()
        isLoaded = false
        Log.debug("[NLContextualEmbedding] Model unloaded", category: .embedding)
    }
}

// MARK: - Embedding Error Extension

extension EmbeddingError {
    static func modelError(_ message: String) -> EmbeddingError {
        return .embeddingFailed(message)
    }
}

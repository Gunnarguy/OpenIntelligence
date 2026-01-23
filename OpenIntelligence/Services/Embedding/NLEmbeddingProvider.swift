//
//  NLEmbeddingProvider.swift
//  OpenIntelligence
//
//  Default on-device embedding provider backed by Apple's NaturalLanguage NLEmbedding.
//  Mirrors previous EmbeddingService behavior: 512-dim word vectors averaged to a chunk embedding.
//

import Foundation
import NaturalLanguage

@available(*, deprecated, message: "Use CoreMLSentenceEmbeddingProvider for better accuracy (Silicon-Native Architecture)")
final class NLEmbeddingProvider: EmbeddingProvider {
    // MARK: - Properties
    private let embedding: NLEmbedding?
    let dimension: Int = 512

    // MARK: - Init
    init(language: NLLanguage = .english) {
        let resolved = NLEmbedding.wordEmbedding(for: language)
        self.embedding = resolved
        if resolved == nil {
            Log.warning(
                "NLEmbedding not available for \(language.rawValue); using fallback hash embeddings",
                category: .embedding
            )
        }
    }

    // MARK: - EmbeddingProvider
    var isAvailable: Bool { true }

    func embed(text: String) async throws -> [Float] {
        // Edge case: Empty or whitespace-only text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw EmbeddingError.emptyInput
        }

        // Tokenize simple by whitespace; keep parity with previous implementation
        let words = trimmedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else {
            throw EmbeddingError.emptyInput
        }

        var wordVectors: [[Double]] = []
        var wordsProcessed = 0
        var wordsSkipped = 0

        if let embedding = embedding {
            for word in words {
                if let vector = embedding.vector(for: word) {
                    wordVectors.append(vector)
                    wordsProcessed += 1
                } else if let vector = embedding.vector(for: word.lowercased()) {
                    wordVectors.append(vector)
                    wordsProcessed += 1
                } else {
                    wordsSkipped += 1
                }
            }

            if wordsSkipped > 0 && wordsSkipped > words.count / 2 {
                Log.warning(
                    "Low NLEmbedding coverage: \(wordsProcessed)/\(words.count) words",
                    category: .embedding
                )
            }
        }

        // If no word vectors found or embedding unavailable, use fallback strategy
        let chunkEmbedding: [Float]
        if wordVectors.isEmpty {
            Log.info(
                "Falling back to hash embedding (NLEmbedding missing or low coverage)",
                category: .embedding
            )
            Log.debug("Fallback embedding input length: \(trimmedText.count) chars", category: .embedding)
            chunkEmbedding = createFallbackEmbedding(for: trimmedText)
        } else {
            // Average all word embeddings to get a single chunk-level embedding
            chunkEmbedding = averageEmbeddings(wordVectors)
        }

        try validateEmbedding(chunkEmbedding)
        return chunkEmbedding
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        // For small batches, process sequentially to avoid overhead
        if texts.count < 5 {
            var out: [[Float]] = []
            out.reserveCapacity(texts.count)
            for t in texts {
                let e = try await embed(text: t)
                out.append(e)
            }
            return out
        }

        // Parallelize batch embedding for larger batches
        // NLEmbedding is CPU-bound, so we use all available cores
        let maxConcurrent = min(8, ProcessInfo.processInfo.activeProcessorCount)

        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            var pendingIndex = 0
            var results: [(Int, [Float])] = []
            results.reserveCapacity(texts.count)

            // Seed initial batch
            for _ in 0..<min(maxConcurrent, texts.count) {
                let idx = pendingIndex
                let text = texts[idx]
                pendingIndex += 1
                group.addTask {
                    let embedding = try await self.embed(text: text)
                    return (idx, embedding)
                }
            }

            // Process remaining with sliding window
            for try await result in group {
                results.append(result)

                // Log progress periodically
                if results.count % 50 == 0 {
                    Log.verbose("[NLEmbeddingProvider] Progress: \(results.count)/\(texts.count)", category: .embedding)
                }

                // Add next task if any remain
                if pendingIndex < texts.count {
                    let idx = pendingIndex
                    let text = texts[idx]
                    pendingIndex += 1
                    group.addTask {
                        let embedding = try await self.embed(text: text)
                        return (idx, embedding)
                    }
                }
            }

            // Sort by original index
            results.sort { $0.0 < $1.0 }
            return results.map { $0.1 }
        }
    }

    // MARK: - Helpers (ported from previous EmbeddingService for parity)
    private func averageEmbeddings(_ vectors: [[Double]]) -> [Float] {
        guard !vectors.isEmpty else {
            return Array(repeating: 0.0, count: dimension)
        }
        let count = vectors.count
        var averaged = Array(repeating: 0.0, count: dimension)
        for vector in vectors {
            for (i, value) in vector.enumerated() {
                if i < dimension {
                    averaged[i] += value
                }
            }
        }
        for i in 0..<dimension {
            averaged[i] /= Double(count)
        }
        return averaged.map { Float($0) }
    }

    private func createFallbackEmbedding(for text: String) -> [Float] {
        var vec = Array(repeating: Float(0.0), count: dimension)
        let normalized = text.lowercased()

        // Character frequency features (first 256 dims)
        for (index, char) in normalized.unicodeScalars.prefix(256).enumerated() {
            if index < dimension {
                vec[index] = Float(char.value % 256) / 128.0 - 1.0
            }
        }
        if dimension > 256 {
            vec[256] = Float(min(text.count, 1000)) / 1000.0
        }
        if dimension > 261 {
            let wordCount = normalized.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            vec[261] = Float(min(wordCount, 100)) / 100.0
        }
        if dimension > 266 {
            let hasNumbers = normalized.rangeOfCharacter(from: .decimalDigits) != nil
            vec[266] = hasNumbers ? 1.0 : -1.0
        }
        let magnitude = sqrt(vec.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            vec = vec.map { $0 / magnitude }
        }
        return vec
    }

    private func validateEmbedding(_ embedding: [Float]) throws {
        guard embedding.count == dimension else {
            throw EmbeddingError.invalidDimension(expected: dimension, actual: embedding.count)
        }
        for v in embedding {
            if v.isNaN { throw EmbeddingError.containsNaN }
            if v.isInfinite { throw EmbeddingError.containsInfinite }
        }
        let magnitude = embedding.reduce(0.0) { $0 + $1 * $1 }
        if magnitude < 0.0001 {
            Log.warning("[NLEmbeddingProvider] Near-zero embedding vector", category: .embedding)
        }
    }
}

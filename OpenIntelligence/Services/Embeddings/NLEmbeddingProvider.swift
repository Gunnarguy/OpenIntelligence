//
//  NLEmbeddingProvider.swift
//  OpenIntelligence
//
//  Default on-device embedding provider backed by Apple's NaturalLanguage NLEmbedding.
//  Mirrors previous EmbeddingService behavior: 512-dim word vectors averaged to a chunk embedding.
//

import Foundation
import NaturalLanguage

final class NLEmbeddingProvider: EmbeddingProvider {
    // MARK: - Properties
    private let embedding: NLEmbedding?
    let dimension: Int = 512
    
    // MARK: - Init
    init(language: NLLanguage = .english) {
        self.embedding = NLEmbedding.wordEmbedding(for: language)
        if embedding == nil {
            print("⚠️ [NLEmbeddingProvider] NLEmbedding not available for \(language.rawValue)")
        }
    }
    
    // MARK: - EmbeddingProvider
    var isAvailable: Bool { embedding != nil }
    
    func embed(text: String) async throws -> [Float] {
        guard let embedding = embedding else {
            throw EmbeddingError.modelUnavailable
        }
        
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
            print("⚠️  [NLEmbeddingProvider] Low coverage: \(wordsProcessed)/\(words.count) words have embeddings")
        }
        
        // If no word vectors found, use fallback strategy
        let chunkEmbedding: [Float]
        if wordVectors.isEmpty {
            print("⚠️  [NLEmbeddingProvider] No vectors returned - using fallback embedding")
            print("   💡 Text: \"\(trimmedText.prefix(50))...\"")
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
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        
        for (idx, t) in texts.enumerated() {
            let e = try await embed(text: t)
            out.append(e)
            if (idx + 1) % 50 == 0 {
                print("   [NLEmbeddingProvider] Progress: \(idx + 1)/\(texts.count)")
            }
        }
        return out
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
            print("⚠️  [NLEmbeddingProvider] Near-zero embedding vector")
        }
    }
}

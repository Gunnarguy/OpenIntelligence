//
//  EmbeddingService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
import NaturalLanguage

/// Service for generating semantic embeddings from text using Apple's on-device models
class EmbeddingService {
    
    // MARK: - Properties
    
    private let provider: EmbeddingProvider
    private let embeddingDimension: Int
    
    // MARK: - Initialization
    
    init(provider: EmbeddingProvider = NLEmbeddingProvider()) {
        self.provider = provider
        self.embeddingDimension = provider.dimension
        if !provider.isAvailable {
            print("⚠️ Warning: Embedding provider not available on this device")
        }
    }
    
    /// Factory method to create an EmbeddingService based on provider ID
    /// Used for per-container embedding provider selection
    static func forProvider(id: String) -> EmbeddingService {
        switch id {
        case "nl_embedding":
            return EmbeddingService(provider: NLEmbeddingProvider())
        case "coreml_sentence_embedding":
            return EmbeddingService(provider: CoreMLSentenceEmbeddingProvider())
        case "apple_fm_embed":
            return EmbeddingService(provider: AppleFMEmbeddingProvider())
        default:
            Log.warning("Unknown embedding provider '\(id)', falling back to NLEmbedding", category: .embedding)
            return EmbeddingService(provider: NLEmbeddingProvider())
        }
    }
    
    // MARK: - Public API
    
    /// Check if embedding generation is available on this device
    var isAvailable: Bool {
        return provider.isAvailable
    }
    
    /// Generate a semantic embedding for a text chunk
    /// Returns a vector representing the semantic meaning
    func generateEmbedding(for text: String) async throws -> [Float] {
        let vec = try await provider.embed(text: text)
        try validateEmbedding(vec)
        return vec
    }
    
    /// Generate embeddings for multiple text chunks in batch
    func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        print("🔢 [EmbeddingService] Generating embeddings for \(texts.count) chunks via provider...")
        let startTime = Date()
        let embeddings = try await provider.embedBatch(texts: texts)
        let totalTime = Date().timeIntervalSince(startTime)
        let avgTime = texts.isEmpty ? 0 : totalTime / Double(texts.count)
        print("✅ [EmbeddingService] Complete: \(texts.count) embeddings in \(String(format: "%.2f", totalTime))s")
        if texts.count > 0 {
            print("   Average: \(String(format: "%.0f", avgTime * 1000))ms per embedding")
        }
        return embeddings
    }
    
    // MARK: - Validation
    
    /// Validate that an embedding is well-formed
    private func validateEmbedding(_ embedding: [Float]) throws {
        // Check dimensionality
        guard embedding.count == embeddingDimension else {
            print("❌ [EmbeddingService] Invalid dimension: \(embedding.count) (expected \(embeddingDimension))")
            throw EmbeddingError.invalidDimension(expected: embeddingDimension, actual: embedding.count)
        }
        
        // Check for NaN or Inf values
        for (index, value) in embedding.enumerated() {
            if value.isNaN {
                print("❌ [EmbeddingService] NaN detected at index \(index)")
                throw EmbeddingError.containsNaN
            }
            if value.isInfinite {
                print("❌ [EmbeddingService] Infinite value detected at index \(index)")
                throw EmbeddingError.containsInfinite
            }
        }
        
        // Check that embedding is not all zeros (likely indicates an error)
        let magnitude = embedding.reduce(0.0) { $0 + $1 * $1 }
        if magnitude < 0.0001 { // Very small threshold
            print("⚠️  [EmbeddingService] Warning: Near-zero embedding vector")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Average multiple token embeddings into a single chunk-level embedding
    /// This produces a fixed-size representation regardless of input length
    private func averageEmbeddings(_ vectors: [[Double]]) -> [Float] {
        guard !vectors.isEmpty else {
            return Array(repeating: 0.0, count: embeddingDimension)
        }
        
        let count = vectors.count
        var averaged = Array(repeating: 0.0, count: embeddingDimension)
        
        // Sum all vectors
        for vector in vectors {
            for (i, value) in vector.enumerated() {
                if i < embeddingDimension {
                    averaged[i] += value
                }
            }
        }
        
        // Divide by count to get average
        for i in 0..<embeddingDimension {
            averaged[i] /= Double(count)
        }
        
        // Convert to Float for efficient storage
        return averaged.map { Float($0) }
    }
    
    /// Create a fallback embedding for text with no word vectors
    /// Uses character-level and structural features to create a synthetic embedding
    private func createFallbackEmbedding(for text: String) -> [Float] {
        var embedding = Array(repeating: Float(0.0), count: embeddingDimension)
        
        // Use a simple hash-based approach to create a deterministic embedding
        // This ensures the same text always gets the same embedding
        let normalized = text.lowercased()
        
        // Populate embedding with character frequency features (first 256 dimensions)
        for (index, char) in normalized.unicodeScalars.prefix(256).enumerated() {
            if index < embeddingDimension {
                // Use Unicode value normalized to [-1, 1] range
                embedding[index] = Float(char.value % 256) / 128.0 - 1.0
            }
        }
        
        // Add text length feature (dimension 256-260)
        if embeddingDimension > 256 {
            embedding[256] = Float(min(text.count, 1000)) / 1000.0
        }
        
        // Add word count feature (dimension 261-265)
        if embeddingDimension > 261 {
            let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            embedding[261] = Float(min(wordCount, 100)) / 100.0
        }
        
        // Add numeric content indicator (dimension 266-270)
        if embeddingDimension > 266 {
            let hasNumbers = text.rangeOfCharacter(from: .decimalDigits) != nil
            embedding[266] = hasNumbers ? 1.0 : -1.0
        }
        
        // Normalize to unit length (standard for embeddings)
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }
        
        return embedding
    }
    
    /// Calculate cosine similarity between two embedding vectors
    /// Returns a value between -1 (opposite) and 1 (identical)
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else {
            print("⚠️ Warning: Embedding dimension mismatch")
            return 0.0
        }
        
        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        
        guard magnitude > 0 else {
            return 0.0
        }
        
        return dotProduct / magnitude
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
    
    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Embedding model is not available on this device"
        case .emptyInput:
            return "Cannot generate embedding for empty text"
        case .generationFailed(let message):
            return "Embedding generation failed: \(message)"
        case .noVectorsReturned:
            return "No embedding vectors were returned"
        case .invalidDimension(let expected, let actual):
            return "Invalid embedding dimension: expected \(expected), got \(actual)"
        case .containsNaN:
            return "Embedding contains NaN values"
        case .containsInfinite:
            return "Embedding contains infinite values"
        case .notImplemented:
            return "This embedding functionality is not yet implemented"
        }
    }
}

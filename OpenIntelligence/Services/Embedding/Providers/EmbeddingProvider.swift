//
//  EmbeddingProvider.swift
//  OpenIntelligence
//
//  Abstraction for pluggable embedding backends.
//  Implementations can use NaturalLanguage (NLEmbedding), CoreML sentence encoders,
//  or remote/local services. Keep dimensions consistent per index namespace.
//

import Foundation

protocol EmbeddingProvider {
    /// Whether this provider can generate embeddings on the current device/runtime
    var isAvailable: Bool { get }

    /// Output vector dimension (e.g., 512 for NLEmbedding, 384/768 for sentence encoders)
    var dimension: Int { get }

    /// Generate an embedding for a single text input
    func embed(text: String) async throws -> [Float]

    /// Generate embeddings for a batch of texts
    func embedBatch(texts: [String]) async throws -> [[Float]]

    /// Count actual tokens for a text (critical for chunk validation)
    /// Returns the number of tokens the embedding model will use, NOT linguistic word count
    /// Default implementation estimates based on character count if tokenizer unavailable
    func countTokens(_ text: String) -> Int

    /// Maximum safe token count (typically 510 for 512-token models after CLS/SEP)
    var maxSafeTokens: Int { get }

    /// Enable ingestion mode - forces embeddings to GPU so ANE can focus on Vision OCR
    /// This creates true ANE+GPU parallelism for faster document ingestion
    func enableIngestionMode()

    /// Disable ingestion mode - returns to default compute units
    func disableIngestionMode()
}

// MARK: - Default Implementations

extension EmbeddingProvider {
    /// Default token count estimation (fallback when tokenizer unavailable)
    /// Uses conservative 3 chars/token ratio for safety
    func countTokens(_ text: String) -> Int {
        return text.count / 3 + 2  // +2 for CLS/SEP
    }

    /// Default max tokens (512 - 2 for CLS/SEP)
    var maxSafeTokens: Int { 510 }

    /// Default no-op for providers that don't support ingestion mode
    func enableIngestionMode() {}
    func disableIngestionMode() {}
}

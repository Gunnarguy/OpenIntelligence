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
}

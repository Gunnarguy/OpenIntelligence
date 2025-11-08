//
//  CoreMLSentenceEmbeddingProvider.swift
//  OpenIntelligence
//
//  Scaffold for a local sentence-embedding backend powered by Core ML.
//  This enables higher-quality, multilingual sentence embeddings (e.g., 384/768 dims)
//  as an alternative to NLEmbedding's word-avg 512-dim vectors.
//
//  Notes:
//  - This is a scaffold. Tokenization and model IO mapping are model-specific and not implemented yet.
//  - Plan: support popular sentence encoders (e.g., E5, MiniLM, GTE) converted to CoreML.
//  - Dimension should be read from the model's metadata or output tensor shape.
//

import Foundation
#if canImport(CoreML)
import CoreML
#endif

final class CoreMLSentenceEmbeddingProvider: EmbeddingProvider {
    #if canImport(CoreML)
    private let model: MLModel?
    #endif
    
    let dimension: Int
    
    init(dimension: Int = 384) {
        // Placeholder init when a model isn't loaded yet (keeps UI selectable but unavailable)
        self.dimension = dimension
        #if canImport(CoreML)
        self.model = nil
        #endif
    }
    
    #if canImport(CoreML)
    /// Initialize with a Core ML model package URL (.mlmodelc/.mlpackage)
    convenience init(modelURL: URL, expectedDimension: Int) {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let loaded = try MLModel(contentsOf: modelURL, configuration: cfg)
            self.init(model: loaded, dimension: expectedDimension)
        } catch {
            print("✗ [CoreMLSentenceEmbeddingProvider] Failed to load model: \(error.localizedDescription)")
            self.init(dimension: expectedDimension)
        }
    }
    
    /// Initialize with an already-loaded MLModel
    init(model: MLModel, dimension: Int) {
        self.dimension = dimension
        self.model = model
    }
    #endif
    
    var isAvailable: Bool {
        #if canImport(CoreML)
        return model != nil
        #else
        return false
        #endif
    }
    
    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }
        #if canImport(CoreML)
        guard let _ = model else {
            throw EmbeddingError.modelUnavailable
        }
        // TODO: Implement tokenization and model input mapping for the specific model signature.
        // Example (pseudo):
        // 1) tokens = tokenizer.encode(text)
        // 2) features = MLDictionaryFeatureProvider(...)
        // 3) out = try await model.prediction(from: features)
        // 4) vector = extractFloatArray(out, key: "sentence_embedding")
        // 5) validate dimension
        throw EmbeddingError.notImplemented
        #else
        throw EmbeddingError.modelUnavailable
        #endif
    }
    
    func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // For now, sequential map; future: batch inputs where model supports it
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        for t in texts {
            let v = try await embed(text: t)
            out.append(v)
        }
        return out
    }
}

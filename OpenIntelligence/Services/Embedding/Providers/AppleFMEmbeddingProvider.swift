//  AppleFMEmbeddingProvider.swift
//  OpenIntelligence
//
//  Scaffold for an Apple Foundation Models–backed embedding provider.
//  Note: As of the local 2025 docs snapshot included in this repo (Docs/),
//  there is no public embedding API surfaced alongside LanguageModelSession,
//  so this provider reports isAvailable = false and throws .notImplemented.
//
//  When Apple exposes an embedding endpoint, wire it here and update
//  container-level provider selection to allow "apple_fm_embed" per-library.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleFMEmbeddingProvider: EmbeddingProvider {
    // Dimensions are unknown until Apple publishes an embedding spec.
    // Keep a placeholder to make downstream validation explicit.
    let dimension: Int = 1024

    // Until Apple publishes an embeddings API, keep this unavailable.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        // FoundationModels is present, but embeddings API isn't documented in our snapshot.
        return false
        #else
        return false
        #endif
    }

    func embed(text: String) async throws -> [Float] {
        throw EmbeddingError.notImplemented
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        // For parity with other providers; will become a proper batch call when API exists.
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        for t in texts {
            out.append(try await embed(text: t))
        }
        return out
    }
}

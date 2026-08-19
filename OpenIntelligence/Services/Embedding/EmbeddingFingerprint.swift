//
//  EmbeddingFingerprint.swift
//  OpenIntelligence
//
//  Identifies the exact pipeline that produced a library's vectors.
//

import CryptoKit
import Foundation

/// A short digest of everything that determines what a vector means.
///
/// The staleness check in `RAGService.resolveEmbeddingContext` compares a container's stored
/// `embeddingProviderId` and `embeddingDim` against the live service. Both of those are *declared*
/// values: `actualProviderId` returns the string literal handed to the initialiser, and
/// `outputDimension` returns a number from a hardcoded table. Neither reads an artifact, so neither
/// moves when the artifacts move.
///
/// Commit `2753d15` proved the cost of that. It changed two bundled `tokenizer.json` files —
/// deleting a `padding` block and raising `truncation.max_length` from 128 to 512 — which altered
/// the content of every vector the app would produce from then on, while leaving
/// `coreml_sentence_embedding` and `384` on both sides of the comparison. Its own commit message
/// says it: "Existing libraries need re-embedding to benefit. Old vectors are valid, not corrupt,
/// and nothing detects the change." The mean-pooling re-export will do the same thing again.
///
/// This hashes the inputs that actually decide the numbers, so the detector fires.
enum EmbeddingFingerprint {
    /// Bump when the *set of terms* changes, so old fingerprints are known-incomparable rather
    /// than accidentally equal to a new one computed differently.
    private static let schemaVersion = 1

    private static let cacheLock = NSLock()
    private static var cache: [String: String] = [:]

    /// Compute the fingerprint for a given embedding configuration.
    ///
    /// Memoised per input tuple. `resolveEmbeddingContext` runs on every query, and hashing a
    /// 711 KB tokenizer takes about a millisecond — cheap once, wasteful thousands of times.
    static func compute(
        providerId: String,
        dimension: Int,
        maxSequenceLength: Int,
        poolingRecipe: String,
        modelRevision: String,
        chunkerRecipe: String
    ) -> String {
        let key = "\(schemaVersion)|\(providerId)|\(dimension)|\(maxSequenceLength)|\(poolingRecipe)|\(modelRevision)|\(chunkerRecipe)"

        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        var hasher = SHA256()
        hasher.update(data: Data(key.utf8))

        // The term that does the work.
        //
        // `2753d15` changed only this file. A byte hash of it would have caught that commit with
        // no developer discipline required — no constant to remember to bump, no review step to
        // skip. Everything else here is a declared string that someone has to maintain.
        if let tokenizerData = tokenizerBytes() {
            hasher.update(data: Data("tokenizer:".utf8))
            hasher.update(data: tokenizerData)
        } else {
            // Absent is itself a state worth distinguishing from present-and-empty.
            hasher.update(data: Data("tokenizer:absent".utf8))
        }

        let digest = hasher.finalize()
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        let result = String(hex)

        cacheLock.lock()
        cache[key] = result
        cacheLock.unlock()
        return result
    }

    /// The bundled tokenizer's raw bytes, resolved the same way the providers resolve it.
    ///
    /// Deliberately NOT the compiled `.mlmodelc`. `model.mil` and `coremldata.bin` are `coremlc`
    /// output and can change on an Xcode or SDK bump with byte-identical numerics, which would
    /// rebuild every user's library on an app update that changed nothing about their vectors.
    /// The model is covered by the declared `modelRevision` instead.
    private static func tokenizerBytes() -> Data? {
        guard let bundleURL = OpenIntelligenceResourceBundle.url(
            forResource: "embedding_tokenizer",
            withExtension: "bundle"
        ) else { return nil }
        let jsonURL = bundleURL.appendingPathComponent("tokenizer.json")
        return try? Data(contentsOf: jsonURL)
    }

    /// Clear the memo. Tests only; the inputs cannot change within a process in production.
    static func resetCacheForTesting() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}

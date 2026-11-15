//
//  StoredVectorModelCheck.swift
//  OpenIntelligence
//
//  Whether a library's stored vectors were already written by the live embedding model (5.8).
//

import Foundation

/// Whether a library's stored vectors were already written by the live embedding model, decided from the vectors
/// themselves (5.8).
///
/// `EmbeddingModelRecord` is kept per device, so a device with no record for a library rebuilt it even when another
/// device had already rebuilt it and iCloud had brought those vectors here: on 2026-11-14 the owner's iPhone
/// re-embedded five libraries his Mac had finished minutes earlier. A record that travelled with the library would
/// say which model one device used, not which vectors this device holds after a merge. So the check embeds a few
/// stored passages again with the live model and compares: vectors from the same model are almost identical
/// whatever chip computed them, and vectors from another model are unrelated. Every document must pass; one that
/// fails, or that has no passage to test, sends the whole library to the rebuild it would have had anyway.
nonisolated enum StoredVectorModelCheck {
    /// Passages tested in each document.
    static let passagesPerDocument = 2
    /// The same model on another chip gives a cosine near 1; another model's vector for the same text is unrelated.
    static let minimumSimilarity: Float = 0.95
    /// Long enough to mean something, short enough that it was never cut to fit the model.
    static let contentLength = 80...1_500

    /// Up to `passagesPerDocument` passages of each document, spread through it, or nil when some document in
    /// `documentIds` has no passage that can be tested.
    static func sample(of chunks: [DocumentChunk], documentIds: Set<UUID>) -> [DocumentChunk]? {
        guard !documentIds.isEmpty else { return nil }
        var byDocument: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks where documentIds.contains(chunk.documentId) && contentLength.contains(chunk.content.count) {
            byDocument[chunk.documentId, default: []].append(chunk)
        }
        var picked: [DocumentChunk] = []
        for id in documentIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let testable = byDocument[id], !testable.isEmpty else { return nil }
            let ordered = testable.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
            let positions = Set((0..<passagesPerDocument).map { ordered.count * $0 / passagesPerDocument })
            picked += positions.sorted().map { ordered[$0] }
        }
        return picked
    }

    /// The text a passage was embedded from: its stored prefix, then its content (`RAGService` re-embedding).
    static func embeddedText(of chunk: DocumentChunk) -> String {
        (chunk.contextualPrefix ?? "") + chunk.content
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var aa: Float = 0
        var bb: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            aa += a[index] * a[index]
            bb += b[index] * b[index]
        }
        guard aa > 0, bb > 0 else { return 0 }
        return dot / (aa.squareRoot() * bb.squareRoot())
    }

    /// The lowest similarity between each stored vector and the live model's vector for the same text, or nil when
    /// the two lists don't line up or a stored vector is unusable.
    static func lowestSimilarity(stored: [[Float]], fresh: [[Float]]) -> Float? {
        guard !stored.isEmpty, stored.count == fresh.count else { return nil }
        var lowest: Float = 1
        for (old, new) in zip(stored, fresh) {
            guard old.count == new.count, !old.isEmpty, old.contains(where: { $0 != 0 }) else { return nil }
            lowest = min(lowest, cosine(old, new))
        }
        return lowest
    }

    static func storedVectorsAreLive(stored: [[Float]], fresh: [[Float]]) -> Bool {
        guard let lowest = lowestSimilarity(stored: stored, fresh: fresh) else { return false }
        return lowest >= minimumSimilarity
    }
}

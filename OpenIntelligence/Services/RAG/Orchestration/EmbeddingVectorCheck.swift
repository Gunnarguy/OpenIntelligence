//
//  EmbeddingVectorCheck.swift
//  OpenIntelligence
//

import Foundation

/// Refuses an import whose embedding model handed back empty vectors (5.7).
///
/// A vector of all zeros, or one that holds a value that isn't a finite number, matches nothing, so
/// a passage stored with one can be found only by its words. Through 5.6 nothing checked: an import
/// embeds through the batch path, which validates nothing, and a model that returned zeros for every
/// passage built a library that looked healthy and could not be searched by meaning. That is what a
/// library made in the iOS 27 Simulator held on 2026-10-08 (127 passages, every vector zero), and
/// 5.7 makes the Core ML copy of the embedding model, the one that wrote those zeros there, the
/// default for new iPhone and iPad libraries.
///
/// Mean-pooled text always gives a vector with some length, so a zero vector means the model failed,
/// not that the text was odd. When more than half of a batch comes back unusable, the model failed
/// for that batch and the import stops with a plain message, so nothing unsearchable is stored. A
/// few unusable vectors in a larger batch are logged by name and count and stored as before, where
/// keyword search still finds their passages, so one bad passage can't end a long import.
nonisolated enum EmbeddingVectorCheck {
    struct EmptyVectors: LocalizedError {
        let unusable: Int
        let total: Int
        let filename: String

        var errorDescription: String? {
            "The embedding model returned empty results for \(unusable) of \(total) passages of \(filename), "
                + "so they weren't added to search. Try importing it again."
        }
    }

    /// False for an empty vector, one with a value that isn't finite, and one whose values are all zero.
    static func isUsable(_ vector: [Float]) -> Bool {
        guard !vector.isEmpty else { return false }
        var sumOfSquares: Float = 0
        for value in vector {
            guard value.isFinite else { return false }
            sumOfSquares += value * value
        }
        return sumOfSquares > 1e-12
    }

    static func unusableCount(_ vectors: [[Float]]) -> Int {
        vectors.reduce(0) { $0 + (isUsable($1) ? 0 : 1) }
    }

    /// Throws when more than half of `vectors` are unusable; logs when some are.
    static func requireUsable(_ vectors: [[Float]], of filename: String) throws {
        let unusable = unusableCount(vectors)
        guard unusable > 0 else { return }
        if unusable * 2 > vectors.count {
            Log.error(
                "[EmbeddingVectorCheck] \(filename): \(unusable) of \(vectors.count) vectors came back empty; "
                    + "the embedding model failed for this batch and nothing from it is stored",
                category: .ingestion)
            throw EmptyVectors(unusable: unusable, total: vectors.count, filename: filename)
        }
        Log.warning(
            "[EmbeddingVectorCheck] \(filename): \(unusable) of \(vectors.count) vectors came back empty; "
                + "those passages are stored without a usable vector, and keyword search still finds them",
            category: .ingestion)
    }
}

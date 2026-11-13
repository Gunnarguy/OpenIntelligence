//
//  EmbeddingModelRecord.swift
//  OpenIntelligence
//
//  Which embedding model wrote each library's vectors on this device (5.8).
//

import Foundation

/// Which embedding model wrote each library's vectors on this device, so a model change is told apart from a smaller
/// pipeline change (5.8).
///
/// A library's stored `EmbeddingFingerprint` is an opaque hash, so a different fingerprint says the pipeline changed but
/// not whether the model did. A pipeline tweak leaves vectors in the same space (worse, still searchable: the app
/// offers a rebuild); a new model puts them in another space, where the new model's queries score them as noise, so
/// they are cleared and rebuilt at once (`RAGService.resolveEmbeddingContext`). A library with no record here was
/// embedded before 5.8, by MiniLM-L6-v2 or earlier, which counts as a model change. Kept per device in
/// `UserDefaults`, beside `containerEmbeddingFingerprints.v1`, because the vectors are rebuilt per device.
nonisolated enum EmbeddingModelRecord {
    static let defaultsKey = "embeddingModelRevisionByLibrary.v1"

    static func recorded(for library: UUID, defaults: UserDefaults = .standard) -> String? {
        (defaults.dictionary(forKey: defaultsKey) as? [String: String])?[library.uuidString]
    }

    /// True when this device has no record of the model behind the library's vectors, or a record of another one.
    static func modelChanged(for library: UUID, live: String, defaults: UserDefaults = .standard) -> Bool {
        recorded(for: library, defaults: defaults) != live
    }

    static func record(_ revision: String, for library: UUID, defaults: UserDefaults = .standard) {
        var all = (defaults.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        all[library.uuidString] = revision
        defaults.set(all, forKey: defaultsKey)
    }

    /// Records the model only when nothing is recorded: a library whose fingerprint matches the live pipeline was
    /// written by the live model.
    static func recordIfAbsent(_ revision: String, for library: UUID, defaults: UserDefaults = .standard) {
        guard recorded(for: library, defaults: defaults) == nil else { return }
        record(revision, for: library, defaults: defaults)
    }
}

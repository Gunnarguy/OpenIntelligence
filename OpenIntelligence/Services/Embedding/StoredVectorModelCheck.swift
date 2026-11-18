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
    /// `documentIds` has no passage that can be tested. With `skippingUntestable`, a document with no testable passage
    /// is left out instead (the health check's per-document sample, 5.8).
    static func sample(
        of chunks: [DocumentChunk], documentIds: Set<UUID>, perDocument: Int = passagesPerDocument,
        skippingUntestable: Bool = false
    ) -> [DocumentChunk]? {
        guard !documentIds.isEmpty, perDocument > 0 else { return nil }
        var byDocument: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks where documentIds.contains(chunk.documentId) && contentLength.contains(chunk.content.count) {
            byDocument[chunk.documentId, default: []].append(chunk)
        }
        var picked: [DocumentChunk] = []
        for id in documentIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let testable = byDocument[id], !testable.isEmpty else {
                if skippingUntestable { continue }
                return nil
            }
            let ordered = testable.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
            let positions = Set((0..<perDocument).map { ordered.count * $0 / perDocument })
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

    /// Below this for a sampled passage, the stored vector is not the live model's (5.8, 2026-11-18). Measured with
    /// the bundled Granite model in the iOS 27.0 Simulator (`GraniteGroundingFloorMeasurementTests`): the same model's
    /// vectors for texts on unrelated subjects came out at 0.636 or more (51 pairs), and for a passage with and
    /// without its prefix at 0.991 or more. On the owner's iPhone the old model's vectors scored 0.002 to 0.133
    /// against Granite's questions and 0.016 to 0.101 against their answers (Gate E, 2026-11-14 to 11-18).
    static let anotherModelCeiling: Float = 0.5

    /// One stored vector against the live model's vector for the same text: true when both are usable and they score
    /// under `anotherModelCeiling`; a pair that does not compare (an unusable vector on either side, or two sizes) says
    /// nothing, so a failing embedder that returns zeros never reads as another model.
    static func isAnotherModels(stored: [Float], fresh: [Float]) -> Bool? {
        guard stored.count == fresh.count, EmbeddingVectorCheck.isUsable(stored), EmbeddingVectorCheck.isUsable(fresh)
        else { return nil }
        return cosine(stored, fresh) < anotherModelCeiling
    }

    /// True when every pair compares and none reaches `anotherModelCeiling`. No pair, or one that does not compare,
    /// says no.
    static func storedVectorsAreAnotherModels(stored: [[Float]], fresh: [[Float]]) -> Bool {
        guard !stored.isEmpty, stored.count == fresh.count else { return false }
        for (old, new) in zip(stored, fresh) {
            guard isAnotherModels(stored: old, fresh: new) == true else { return false }
        }
        return true
    }

    /// The documents whose sampled passage holds another model's vector, from one passage of each (`sample(of:
    /// documentIds:perDocument: 1, skippingUntestable: true)`), or nil when no pair compares. A document whose pair
    /// does not compare is in neither set.
    static func documentsWithAnotherModelsVectors(
        sample: [DocumentChunk], stored: [[Float]], fresh: [[Float]]
    ) -> (failing: Set<UUID>, compared: Int)? {
        guard sample.count == stored.count, stored.count == fresh.count else { return nil }
        var failing: Set<UUID> = []
        var compared = 0
        for (index, chunk) in sample.enumerated() {
            guard let another = isAnotherModels(stored: stored[index], fresh: fresh[index]) else { continue }
            compared += 1
            if another { failing.insert(chunk.documentId) }
        }
        return compared == 0 ? nil : (failing, compared)
    }

    /// What the health check does about a library after comparing its sample (5.8, 2026-11-18).
    enum RepairAction: Equatable {
        /// Nothing to repair, or nothing could be compared.
        case none
        /// Re-embed these documents in place, once for this model.
        case rebuild(Set<UUID>)
        /// A repair for this model already ran and did not take, or the person stopped automatic repairs: show the
        /// library's rebuild banner and leave the choice to them.
        case showBanner
    }

    /// The next step for a library, and the per-device record it leaves (`UserDefaults`, by library and model revision).
    /// A repair is queued once per model revision; after it, a library whose vectors still don't match shows the
    /// rebuild banner instead of queueing again at every launch. A check that finds the live model's vectors records
    /// that, and later launches skip the check (`checkIsDue`).
    static func repairAction(
        failing: Set<UUID>?, library: UUID, revision: String, repairsSuppressed: Bool,
        defaults: UserDefaults = .standard
    ) -> RepairAction {
        guard let failing else { return .none }
        let key = recordKey(library)
        guard !failing.isEmpty else {
            defaults.set("verified|\(revision)", forKey: key)
            return .none
        }
        if repairsSuppressed || defaults.string(forKey: key) == "attempted|\(revision)" { return .showBanner }
        defaults.set("attempted|\(revision)", forKey: key)
        return .rebuild(failing)
    }

    /// Whether the health check should compare this library's vectors: not once a check under this model revision found
    /// them the live model's.
    static func checkIsDue(library: UUID, revision: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: recordKey(library)) != "verified|\(revision)"
    }

    private static func recordKey(_ library: UUID) -> String { "storedVectorModelCheck.\(library.uuidString)" }

    static func storedVectorsAreLive(stored: [[Float]], fresh: [[Float]]) -> Bool {
        guard let lowest = lowestSimilarity(stored: stored, fresh: fresh) else { return false }
        return lowest >= minimumSimilarity
    }
}

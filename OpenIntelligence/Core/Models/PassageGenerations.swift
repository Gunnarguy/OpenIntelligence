//
//  PassageGenerations.swift
//  OpenIntelligence
//
//  One document, one set of passages (5.8, 2026-11-13).
//
//  A rebuild gives a document new passages with new ids, and through 5.7 two copies of a library's passages were merged
//  by id and text, so a library rebuilt on one device and still holding its old passages on another came out of the
//  merge with both sets. On the owner's devices on 2026-11-13 Library 6 held 16,554 passages for 37 documents: the
//  8,230 made that morning by the rebuild for the new search model, and 8,324 from 2026-11-03 to 11-07, embedded by the
//  old model. Search then met every document twice, the old half with vectors from another model, and answers cited
//  the same page twice ("[S1]" and "[S2]", both CD004426.pdf p.24).
//
//  A document's passages are all made in one import or rebuild, minutes apart at most. So where a document has passages
//  the same place twice (two passages with one index), each place keeps its newest passage and the old set's leftovers go.
//

import Foundation

nonisolated enum PassageGenerations {
    /// Passages made further apart than this belong to different imports or rebuilds of the document.
    static let gap: TimeInterval = 30 * 60

    /// The passages of each document's newest import or rebuild, in the order given. `removed` is how many older ones
    /// were left out.
    ///
    /// Only a document that holds one place twice (two passages with one index) has two sets: a rebuild starts again
    /// at passage 0, and an import paused for hours holds every place once and is left whole. For such a document each
    /// place keeps its newest passage, and a passage made more than `gap` before the newest set began (the earliest of
    /// the places held twice) is a leftover of the old set at a place the new set no longer has.
    ///
    /// The first version (same day) cut a document at any 30-minute gap going back from its newest passage. A document's
    /// summary passage is made after its others, 33 to 36 minutes after on the owner's iPhone, so that one passage was
    /// taken for the newest set and the document's 1,100 real passages were removed: his Library 6 went from 16,554 to
    /// 4,292 at 17:32 on 2026-11-13, where 8,226 was right. Restored from the Mac's copy.
    static func newest(of chunks: [DocumentChunk]) -> (kept: [DocumentChunk], removed: Int) {
        var dropped = Set<UUID>()
        for (_, passages) in Dictionary(grouping: chunks, by: \.documentId) {
            let byPlace = Dictionary(grouping: passages, by: \.metadata.chunkIndex)
            let heldTwice = byPlace.values.filter { $0.count > 1 }
            guard !heldTwice.isEmpty else { continue }
            func newest(_ group: [DocumentChunk]) -> DocumentChunk {
                group.max { $0.metadata.createdAt < $1.metadata.createdAt } ?? group[0]
            }
            let newSetBegan = heldTwice.map { newest($0).metadata.createdAt }.min() ?? .distantPast
            let cutoff = newSetBegan.addingTimeInterval(-gap)
            for group in byPlace.values {
                let keeper = newest(group)
                for passage in group where passage.id != keeper.id || passage.metadata.createdAt < cutoff {
                    dropped.insert(passage.id)
                }
            }
        }
        guard !dropped.isEmpty else { return (chunks, 0) }
        let kept = chunks.filter { !dropped.contains($0.id) }
        return (kept, chunks.count - kept.count)
    }
}

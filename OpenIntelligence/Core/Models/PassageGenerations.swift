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
//  the same place twice (two passages with one index) and passages made more than `gap` apart, the newest run is the
//  document and the older runs are leftovers.
//

import Foundation

nonisolated enum PassageGenerations {
    /// Passages made further apart than this belong to different imports or rebuilds of the document.
    static let gap: TimeInterval = 30 * 60

    /// The passages of each document's newest import or rebuild, in the order given. `removed` is how many older ones
    /// were left out.
    static func newest(of chunks: [DocumentChunk]) -> (kept: [DocumentChunk], removed: Int) {
        var cutoff: [UUID: Date] = [:]
        for (documentId, passages) in Dictionary(grouping: chunks, by: \.documentId) {
            // Only a document that holds one place twice has two sets: a rebuild starts again at passage 0. A long
            // import that was paused for hours has passages made far apart and every place once; it is left whole.
            var places = Set<Int>()
            guard passages.contains(where: { !places.insert($0.metadata.chunkIndex).inserted }) else { continue }
            let sorted = passages.map(\.metadata.createdAt).sorted(by: >)
            var oldestOfNewestRun = sorted[0]
            for date in sorted.dropFirst() {
                guard oldestOfNewestRun.timeIntervalSince(date) <= gap else { break }
                oldestOfNewestRun = date
            }
            if oldestOfNewestRun != sorted[sorted.count - 1] { cutoff[documentId] = oldestOfNewestRun }
        }
        guard !cutoff.isEmpty else { return (chunks, 0) }
        let kept = chunks.filter { chunk in
            guard let from = cutoff[chunk.documentId] else { return true }
            return chunk.metadata.createdAt >= from
        }
        return (kept, chunks.count - kept.count)
    }
}

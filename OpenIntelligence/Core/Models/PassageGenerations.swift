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
    /// Each document's passages with one passage a place: where two hold the same place (the same index), the newer
    /// one stays. In the order given. `removed` is how many were left out.
    static func newest(of chunks: [DocumentChunk]) -> (kept: [DocumentChunk], removed: Int) {
        // By place and nothing else. Two rules that also read the times passages were made each removed real passages
        // on the owner's iPhone on 2026-11-13: a 30-minute gap took a document's later summary for a new set (16,554 to
        // 4,292), and a cutoff from "when the new set began" took a summary re-made that evening on the Mac for the
        // start of a set and dropped the document made that morning (8,237 to 6,843). A passage is left out only when
        // a newer passage of the same document holds the same place. An old set's passages at places the new set does
        // not reach stay (310 of 16,554 in his Library 6); a Rebuild of the library removes them.
        var keeper: [String: DocumentChunk] = [:]
        for chunk in chunks {
            let place = "\(chunk.documentId.uuidString)|\(chunk.metadata.chunkIndex)"
            if let held = keeper[place], held.metadata.createdAt >= chunk.metadata.createdAt { continue }
            keeper[place] = chunk
        }
        guard keeper.count < chunks.count else { return (chunks, 0) }
        let keptIds = Set(keeper.values.map(\.id))
        let kept = chunks.filter { keptIds.contains($0.id) }
        return (kept, chunks.count - kept.count)
    }
}

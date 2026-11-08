//
//  RAGService+TablePassages.swift
//  OpenIntelligence
//
//  A table is stored as passages of three kinds that share a `siblingGroupId`: the table itself (`tableStructural`,
//  split into parts when it is long), a summary (`tableSemantic`) and, for some tables, one passage per row. The summary
//  lists only a table's first two rows, so when retrieval ranks it first, the model reads two rows and nothing else: on
//  2026-11-07 "How much DHA is recommended?" retrieved the summary of a paper's Table 1, whose first two rows are other
//  supplements, and the answer gave the first row's dose as DHA's. Wherever a summary is a candidate, its table now goes
//  into the context in the summary's place, for every library, imported before or after this change.
//

import Foundation

extension RAGService {
    /// Replaces each table summary among `candidates` with the table it summarises, at the summary's place and score.
    /// The table is the summary's `tableStructural` siblings that come before it in the document and after any earlier
    /// summary of the same group (two uncaptioned tables on one page can share a group), leaving out the per-row
    /// passages ("COMPATIBILITY ROW:"). A table part already among the candidates moves up to the summary's place when it
    /// ranked lower, and the summary is dropped when the whole table ranked higher; a summary whose table is not found
    /// stays.
    nonisolated static func withTablesForSummaries(
        _ candidates: [RetrievedChunk], allChunks: [DocumentChunk]
    ) -> [RetrievedChunk] {
        let summaries = candidates.filter { $0.chunk.metadata.chunkType == .tableSemantic && $0.chunk.metadata.siblingGroupId != nil }
        guard !summaries.isEmpty else { return candidates }

        struct TableKey: Hashable {
            let documentId: UUID
            let group: String
        }
        let wanted = Set(summaries.compactMap { candidate in
            candidate.chunk.metadata.siblingGroupId.map { TableKey(documentId: candidate.chunk.documentId, group: $0) }
        })
        var partsByKey: [TableKey: [DocumentChunk]] = [:]
        var summaryIndicesByKey: [TableKey: [Int]] = [:]
        for chunk in allChunks {
            guard let group = chunk.metadata.siblingGroupId else { continue }
            let key = TableKey(documentId: chunk.documentId, group: group)
            guard wanted.contains(key) else { continue }
            switch chunk.metadata.chunkType {
            case .tableStructural where !chunk.content.contains("COMPATIBILITY ROW:"):
                partsByKey[key, default: []].append(chunk)
            case .tableSemantic:
                summaryIndicesByKey[key, default: []].append(chunk.metadata.chunkIndex)
            default:
                break
            }
        }

        func table(for summary: DocumentChunk) -> [DocumentChunk] {
            guard let group = summary.metadata.siblingGroupId else { return [] }
            let key = TableKey(documentId: summary.documentId, group: group)
            let index = summary.metadata.chunkIndex
            let earlierSummary = (summaryIndicesByKey[key] ?? []).filter { $0 < index }.max() ?? Int.min
            return (partsByKey[key] ?? [])
                .filter { $0.metadata.chunkIndex < index && $0.metadata.chunkIndex > earlierSummary }
                .sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
        }

        var result = candidates
        var position = 0
        while position < result.count {
            let candidate = result[position]
            guard candidate.chunk.metadata.chunkType == .tableSemantic else {
                position += 1
                continue
            }
            let parts = table(for: candidate.chunk)
            guard !parts.isEmpty else {
                position += 1
                continue
            }
            let partIds = Set(parts.map(\.id))
            let earlierIds = Set(result[..<position].map(\.chunk.id))
            if partIds.isSubset(of: earlierIds) {
                // The whole table already ranked higher; the summary adds nothing.
                result.remove(at: position)
                continue
            }
            // Parts that ranked lower move up; parts not retrieved are added.
            result.removeAll { partIds.contains($0.chunk.id) && !earlierIds.contains($0.chunk.id) }
            let inserted = parts.filter { !earlierIds.contains($0.id) }.map { part in
                RetrievedChunk(
                    chunk: part,
                    similarityScore: candidate.similarityScore,
                    rank: candidate.rank,
                    sourceDocument: candidate.sourceDocument,
                    pageNumber: part.metadata.pageNumber ?? candidate.pageNumber
                )
            }
            guard let summaryPosition = result.firstIndex(where: { $0.chunk.id == candidate.chunk.id }) else {
                position += 1
                continue
            }
            result.replaceSubrange(summaryPosition...summaryPosition, with: inserted)
            position = summaryPosition + inserted.count
        }
        return result
    }
}

//
//  VectorMergeKeepsReembeddedVectorsTests.swift
//  OpenIntelligenceTests
//
//  A library re-embedded in place keeps its passages' ids and text and changes only their vectors (5.8, the move to
//  the Granite embedder). Through f5759e4d the sync merge kept the first copy of a passage it met and read the iCloud
//  copy first, so the next pass wrote the iCloud copy's old vectors back over the ones the rebuild had just made, on
//  every device, and the iCloud copy itself never changed. On the owner's iPhone on 2026-11-14 a library's 126
//  passages were re-embedded at 16:43:06 and four seconds later the pass logged "persistVectorChunks writing 126
//  chunk(s)" to the local store and "Shared vector store already current", which means the merge result was the
//  iCloud copy byte for byte. Its answers' grounding gate then measured a question and its answer at cosines of 0.03
//  to 0.13 against their own sources until 2026-11-18.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class VectorMergeKeepsReembeddedVectorsTests: XCTestCase {
    private let document = UUID()
    private let oldModel: [Float] = [1, 0, 0, 0]
    private let newModel: [Float] = [0, 1, 0, 0]
    private let importedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func passages(
        embedding: [Float], madeAt: Date, ids: [UUID]? = nil, text: String = "Passage", count: Int = 3
    ) -> [DocumentChunk] {
        (0..<count).map { index in
            DocumentChunk(
                id: ids?[index] ?? UUID.deterministic(from: "\(document.uuidString)_\(text)_\(index)"),
                documentId: document,
                content: "\(text) \(index) of the review on the gut-brain axis.",
                embedding: embedding,
                metadata: ChunkMetadata(chunkIndex: index, createdAt: madeAt))
        }
    }

    private func merge(shared: [DocumentChunk], local: [DocumentChunk]) -> [DocumentChunk] {
        WorkspaceSyncService.mergeVectorChunks(shared: shared, local: local, allowedDocumentIds: [document])
    }

    /// The iPhone: it re-embedded its passages; iCloud still holds the old model's. Failed on f5759e4d ("the merge
    /// wrote the old model's vectors back").
    func testThisDevicesReembeddedVectorsWinOverTheICloudCopy() {
        let before = passages(embedding: oldModel, madeAt: importedAt)
        let rebuilt = before.map { $0.reembedded(newModel, contextualPrefix: $0.contextualPrefix) }
        let merged = merge(shared: before, local: rebuilt)
        XCTAssertEqual(merged.count, 3)
        XCTAssertTrue(merged.allSatisfy { $0.embedding == newModel }, "the merge wrote the old model's vectors back")
        XCTAssertEqual(merged.map(\.id), before.map(\.id), "a re-embed keeps the passages; only their vectors change")
    }

    /// The Mac, later: its own copy is still the old model's and iCloud now holds the iPhone's rebuild.
    func testTheICloudCopysReembeddedVectorsWinOverThisDevicesOldOnes() {
        let before = passages(embedding: oldModel, madeAt: importedAt)
        let rebuilt = before.map { $0.reembedded(newModel, contextualPrefix: $0.contextualPrefix) }
        XCTAssertTrue(merge(shared: rebuilt, local: before).allSatisfy { $0.embedding == newModel })
    }

    /// Review row 1: another device split the document again (new passages, later time) and iCloud holds that split;
    /// this device then re-embeds its old split in place. The new split must win: a re-embed is dated from the passage,
    /// not from the clock, so it cannot outrank a split made after the passage was.
    func testAReembedOfAnOldSplitNeverUndoesALaterSplit() {
        let oldSplit = passages(embedding: oldModel, madeAt: importedAt, text: "Old split")
        let newSplit = passages(
            embedding: newModel, madeAt: importedAt.addingTimeInterval(3_600), text: "New split", count: 3)
        // Re-embedded on this device after the new split was made elsewhere.
        let reembeddedOldSplit = oldSplit.map { $0.reembedded([0, 0, 1, 0], contextualPrefix: nil) }
        let merged = merge(shared: newSplit, local: reembeddedOldSplit)
        XCTAssertEqual(Set(merged.map(\.id)), Set(newSplit.map(\.id)), "the re-embed of the old split undid the new split")
        XCTAssertTrue(merged.allSatisfy { $0.content.hasPrefix("New split") })
        // And from the other side.
        XCTAssertEqual(Set(merge(shared: reembeddedOldSplit, local: newSplit).map(\.id)), Set(newSplit.map(\.id)))
    }

    /// Two copies of the same passage under different ids (the duplicate-text rule) follow the same rule.
    func testTheNewerCopyWinsWhenTheSamePassageCarriesAnotherId() {
        let before = passages(embedding: oldModel, madeAt: importedAt)
        let otherIds = (0..<3).map { _ in UUID() }
        let rebuilt = passages(embedding: newModel, madeAt: importedAt.addingTimeInterval(60), ids: otherIds)
        let merged = merge(shared: before, local: rebuilt)
        XCTAssertEqual(merged.count, 3)
        XCTAssertTrue(merged.allSatisfy { $0.embedding == newModel })
        XCTAssertEqual(merged.map(\.id), otherIds)
    }

    /// Copies made at the same moment keep the iCloud copy, as every merge did before this rule.
    func testCopiesOfOneAgeKeepTheICloudCopy() {
        let shared = passages(embedding: oldModel, madeAt: importedAt)
        let local = passages(embedding: newModel, madeAt: importedAt)
        XCTAssertTrue(merge(shared: shared, local: local).allSatisfy { $0.embedding == oldModel })
    }

    /// Review row 12: a passage stored without its time decodes as the oldest copy, not as "now", so it never wins.
    func testAPassageStoredWithoutItsTimeIsTheOldestCopy() throws {
        let dated = passages(embedding: newModel, madeAt: importedAt)
        let json = try JSONEncoder().encode(passages(embedding: oldModel, madeAt: importedAt))
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        for index in objects.indices {
            var metadata = try XCTUnwrap(objects[index]["metadata"] as? [String: Any])
            XCTAssertNotNil(metadata.removeValue(forKey: "createdAt"), "precondition: the field is written")
            objects[index]["metadata"] = metadata
        }
        let undated = try JSONDecoder().decode(
            [DocumentChunk].self, from: JSONSerialization.data(withJSONObject: objects))
        XCTAssertTrue(undated.allSatisfy { $0.metadata.createdAt == .distantPast })
        XCTAssertTrue(merge(shared: undated, local: dated).allSatisfy { $0.embedding == newModel })
        XCTAssertTrue(merge(shared: dated, local: undated).allSatisfy { $0.embedding == newModel })
    }

    /// The re-embedded passage is the same passage: everything but its vector, its prefix and its time is kept, and
    /// its time is one millisecond later than the passage's.
    func testAReembeddedPassageKeepsEverythingButItsVectorAndTime() {
        let original = DocumentChunk(
            documentId: document, content: "Text.", parentContent: "Parent.", contextualPrefix: "[From a.pdf] ",
            embedding: oldModel,
            metadata: ChunkMetadata(
                chunkIndex: 4, startPosition: 10, endPosition: 15, pageNumber: 2, sectionTitle: "Methods",
                wordCount: 1, characterCount: 5, createdAt: importedAt, sectionPath: ["Methods"], tableTitle: "T1"))
        let rebuilt = original.reembedded(newModel, contextualPrefix: "[From a.pdf] [Methods] ")
        XCTAssertEqual(rebuilt.id, original.id)
        XCTAssertEqual(rebuilt.documentId, original.documentId)
        XCTAssertEqual(rebuilt.content, original.content)
        XCTAssertEqual(rebuilt.parentContent, original.parentContent)
        XCTAssertEqual(rebuilt.contextualPrefix, "[From a.pdf] [Methods] ")
        XCTAssertEqual(rebuilt.embedding, newModel)
        XCTAssertEqual(rebuilt.metadata.createdAt, importedAt.addingTimeInterval(0.001))
        XCTAssertEqual(rebuilt.metadata.chunkIndex, 4)
        XCTAssertEqual(rebuilt.metadata.startPosition, 10)
        XCTAssertEqual(rebuilt.metadata.endPosition, 15)
        XCTAssertEqual(rebuilt.metadata.pageNumber, 2)
        XCTAssertEqual(rebuilt.metadata.sectionTitle, "Methods")
        XCTAssertEqual(rebuilt.metadata.sectionPath, ["Methods"])
        XCTAssertEqual(rebuilt.metadata.tableTitle, "T1")
        // The millisecond survives the store's JSON.
        let roundTrip = try? JSONDecoder().decode(DocumentChunk.self, from: JSONEncoder().encode(rebuilt))
        XCTAssertGreaterThan(roundTrip?.metadata.createdAt ?? .distantPast, importedAt)
    }

    // MARK: - Cost (review row 16)

    /// The merge as it was through f5759e4d, kept here to time against: the first copy met stays.
    private static func mergeAsBefore(shared: [DocumentChunk], local: [DocumentChunk], allowed: Set<UUID>) -> [DocumentChunk] {
        var orderedIds: [UUID] = []
        var byId: [UUID: DocumentChunk] = [:]
        var duplicateKeyToId: [String: UUID] = [:]
        func ingest(_ chunks: [DocumentChunk]) {
            for chunk in chunks where allowed.contains(chunk.documentId) {
                if byId[chunk.id] != nil { continue }
                let key = "\(chunk.documentId.uuidString)|\(chunk.metadata.chunkIndex)|\(chunk.content)"
                if let existing = duplicateKeyToId[key], byId[existing] != nil { continue }
                orderedIds.append(chunk.id)
                byId[chunk.id] = chunk
                duplicateKeyToId[key] = chunk.id
            }
        }
        ingest(shared)
        ingest(local)
        return PassageGenerations.newest(of: orderedIds.compactMap { byId[$0] }).kept.sorted { lhs, rhs in
            lhs.documentId != rhs.documentId
                ? lhs.documentId.uuidString < rhs.documentId.uuidString : lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
    }

    func testTheMergeCostsAboutWhatItDidOn100kPassages() {
        let documents = (0..<1_000).map { _ in UUID() }
        let filler = String(repeating: "The intestinal microbiota signals to the brain. ", count: 6)
        var shared: [DocumentChunk] = []
        shared.reserveCapacity(100_000)
        for document in documents {
            for index in 0..<100 {
                shared.append(
                    DocumentChunk(
                        documentId: document, content: "\(index) \(filler)", embedding: oldModel,
                        metadata: ChunkMetadata(chunkIndex: index, createdAt: importedAt)))
            }
        }
        let identical = shared
        let reembedded = shared.map { $0.reembedded(newModel, contextualPrefix: nil) }
        let allowed = Set(documents)

        func time(_ label: String, _ body: () -> [DocumentChunk]) -> (seconds: Double, result: [DocumentChunk]) {
            let start = Date()
            let result = body()
            let seconds = Date().timeIntervalSince(start)
            print("[VectorMergeCost] \(label): \(String(format: "%.3f", seconds)) s for \(result.count) passages")
            return (seconds, result)
        }
        let beforeIdentical = time("before, copies identical") {
            Self.mergeAsBefore(shared: shared, local: identical, allowed: allowed)
        }
        let afterIdentical = time("after, copies identical") {
            WorkspaceSyncService.mergeVectorChunks(shared: shared, local: identical, allowedDocumentIds: allowed)
        }
        let beforeReembedded = time("before, every passage re-embedded") {
            Self.mergeAsBefore(shared: shared, local: reembedded, allowed: allowed)
        }
        let afterReembedded = time("after, every passage re-embedded") {
            WorkspaceSyncService.mergeVectorChunks(shared: shared, local: reembedded, allowedDocumentIds: allowed)
        }
        XCTAssertEqual(afterIdentical.result.map(\.id), beforeIdentical.result.map(\.id), "identical copies merge as before")
        XCTAssertEqual(afterReembedded.result.count, 100_000)
        XCTAssertTrue(afterReembedded.result.allSatisfy { $0.embedding == newModel })
        XCTAssertTrue(beforeReembedded.result.allSatisfy { $0.embedding == oldModel }, "the old merge kept the old vectors")
        // Generous: a cost regression of several times, not run-to-run noise.
        XCTAssertLessThan(afterReembedded.seconds, max(beforeReembedded.seconds * 3, 2))
        XCTAssertLessThan(afterIdentical.seconds, max(beforeIdentical.seconds * 3, 2))
    }
}

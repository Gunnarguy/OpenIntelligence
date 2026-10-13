//
//  ParentDocumentServiceTests.swift
//  OpenIntelligenceTests
//
//  Parent expansion adds the passages next to a retrieved one, from the same document and the
//  same group, section or page. From 5.7 it looks only at the documents the retrieved passages
//  come from and sorts each once. Until then it built a dictionary of every passage in the
//  library for each question, grouped every passage by document, and sorted a document again for
//  each retrieved passage. What it returns must not depend on any of that: on the order passages
//  are stored in, or on what else is in the library.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class ParentDocumentServiceTests: XCTestCase {
    private let words = [
        "pump", "valve", "torque", "sterile", "cycle", "lumen", "channel", "detergent", "rinse", "filter",
        "manual", "service", "replace", "inspect", "pressure", "adapter", "seal", "record", "ledger", "margin",
    ]

    /// Text no two passages share much of, so the redundancy check never removes a sibling.
    private func text(_ document: Int, _ number: Int) -> String {
        (0..<12).map { "\(words[(number * 7 + $0 * 3 + document) % words.count])\(document)x\(number)y\($0)" }
            .joined(separator: " ")
    }

    private func passage(
        _ document: UUID, _ documentNumber: Int, _ number: Int, group: String? = nil, section: String? = nil,
        page: Int? = nil
    ) -> DocumentChunk {
        DocumentChunk(
            documentId: document, content: text(documentNumber, number), embedding: [],
            metadata: ChunkMetadata(
                chunkIndex: number, pageNumber: page, sectionTitle: section, siblingGroupId: group))
    }

    private func retrieved(_ chunk: DocumentChunk, score: Float = 0.9) -> RetrievedChunk {
        RetrievedChunk(chunk: chunk, similarityScore: score, rank: 1, sourceDocument: "manual.pdf", pageNumber: nil)
    }

    private let roomy = ParentDocumentService.Config(
        maxSiblingsPerSide: 2, maxExpandedTokens: 100_000, allowCrossPageExpansion: false, minRelevanceForExpansion: 0.1)

    func testAPassageBringsItsNeighboursFromTheSameGroupAndStopsAtTheGroupsEdge() async {
        let manual = UUID()
        let passages = (0..<10).map { passage(manual, 0, $0, group: $0 < 5 ? "first" : "second") }
        let service = ParentDocumentService(config: roomy)

        let middle = await service.expandWithSiblings(retrievedChunks: [retrieved(passages[2])], allChunks: passages, query: "")
        XCTAssertEqual(middle.expandedChunks.map(\.chunk.metadata.chunkIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(middle.addedSiblings, 4)

        let edge = await service.expandWithSiblings(retrievedChunks: [retrieved(passages[4])], allChunks: passages, query: "")
        XCTAssertEqual(edge.expandedChunks.map(\.chunk.metadata.chunkIndex), [2, 3, 4], "passage 5 is in the next group")

        let first = await service.expandWithSiblings(retrievedChunks: [retrieved(passages[0])], allChunks: passages, query: "")
        XCTAssertEqual(first.expandedChunks.map(\.chunk.metadata.chunkIndex), [0, 1, 2])
    }

    func testSectionsAndPagesDecideWhenThereIsNoGroup() async {
        let manual = UUID()
        let bySection = (0..<8).map { passage(manual, 0, $0, section: $0 < 4 ? "Engine Oil" : "Transmission", page: 1) }
        let service = ParentDocumentService(config: roomy)
        let inSection = await service.expandWithSiblings(retrievedChunks: [retrieved(bySection[3])], allChunks: bySection, query: "")
        XCTAssertEqual(inSection.expandedChunks.map(\.chunk.metadata.chunkIndex), [1, 2, 3], "same page, another section: not a sibling")

        let byPage = (0..<8).map { passage(manual, 0, $0, page: $0 < 4 ? 1 : 2) }
        let onPage = await service.expandWithSiblings(retrievedChunks: [retrieved(byPage[2])], allChunks: byPage, query: "")
        XCTAssertEqual(onPage.expandedChunks.map(\.chunk.metadata.chunkIndex), [0, 1, 2, 3])

        let bare = (0..<8).map { passage(manual, 0, $0) }
        let adjacent = await service.expandWithSiblings(retrievedChunks: [retrieved(bare[4])], allChunks: bare, query: "")
        XCTAssertEqual(adjacent.expandedChunks.map(\.chunk.metadata.chunkIndex), [3, 4, 5], "with nothing else to go on, only the passages either side")
    }

    func testTheResultDoesNotDependOnStoredOrderOrOnTheRestOfTheLibrary() async {
        let manual = UUID()
        let lease = UUID()
        let other = UUID()
        let ofManual = (0..<400).map { passage(manual, 0, $0, group: "g\($0 / 6)") }
        // Another document with the same passage numbers and the same group names.
        let ofLease = (0..<400).map { passage(lease, 1, $0, group: "g\($0 / 6)") }
        let ofOther = (0..<3_000).map { passage(other, 2, $0, section: "S\($0 / 9)") }
        let picked = [retrieved(ofManual[7]), retrieved(ofManual[250], score: 0.7), retrieved(ofLease[13], score: 0.6)]
        let service = ParentDocumentService(config: roomy)

        let alone = await service.expandWithSiblings(retrievedChunks: picked, allChunks: ofManual + ofLease, query: "")
        let whole = await service.expandWithSiblings(
            retrievedChunks: picked, allChunks: (ofOther + ofLease + ofManual).shuffled(), query: "")
        XCTAssertEqual(whole.expandedChunks.map(\.chunk.id), alone.expandedChunks.map(\.chunk.id))
        XCTAssertEqual(whole.expandedChunks.map(\.similarityScore), alone.expandedChunks.map(\.similarityScore))
        XCTAssertEqual(whole.addedSiblings, alone.addedSiblings)

        // Passage 7 is in group 1 (6 to 11): 5 is outside it. Passage 250 is in group 41 (246 to
        // 251). The lease's passage 13 is in its group 2 (12 to 17).
        XCTAssertEqual(
            alone.expandedChunks.filter { $0.chunk.documentId == manual }.map(\.chunk.metadata.chunkIndex),
            [6, 7, 8, 9, 248, 249, 250, 251])
        XCTAssertEqual(
            alone.expandedChunks.filter { $0.chunk.documentId == lease }.map(\.chunk.metadata.chunkIndex), [12, 13, 14, 15])
        XCTAssertFalse(whole.expandedChunks.contains { $0.chunk.documentId == other })
    }

    func testRetrievedPassagesAreAlwaysKeptAndNothingIsAddedTwice() async {
        let manual = UUID()
        let passages = (0..<12).map { passage(manual, 0, $0, group: "one") }
        let picked = [retrieved(passages[3]), retrieved(passages[4], score: 0.8), retrieved(passages[9], score: 0.05)]
        let result = await ParentDocumentService(config: roomy).expandWithSiblings(
            retrievedChunks: picked, allChunks: passages, query: "")
        let numbers = result.expandedChunks.map(\.chunk.metadata.chunkIndex)
        XCTAssertEqual(Set(numbers).count, numbers.count, "no passage twice")
        XCTAssertTrue(Set(numbers).isSuperset(of: [3, 4, 9]))
        XCTAssertEqual(Set(numbers), [1, 2, 3, 4, 5, 6, 9], "passage 9 scored too low to bring neighbours")
    }

    /// Two passages with one id. The dictionary of every passage that used to be built for each
    /// question was made with `uniqueKeysWithValues`, which stops the app on a repeated key.
    func testTwoPassagesWithOneIdDoNotStopTheApp() async {
        let manual = UUID()
        var passages = (0..<6).map { passage(manual, 0, $0, group: "one") }
        let twin = passages[2]
        passages.append(
            DocumentChunk(
                id: twin.id, documentId: manual, content: text(0, 99), embedding: [],
                metadata: ChunkMetadata(chunkIndex: 6, siblingGroupId: "one")))
        let result = await ParentDocumentService(config: roomy).expandWithSiblings(
            retrievedChunks: [retrieved(passages[4])], allChunks: passages, query: "")
        XCTAssertTrue(result.expandedChunks.contains { $0.chunk.metadata.chunkIndex == 4 })
        XCTAssertGreaterThan(result.addedSiblings, 0)
    }
}

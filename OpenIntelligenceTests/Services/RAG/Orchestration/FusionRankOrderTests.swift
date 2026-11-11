//
//  FusionRankOrderTests.swift
//  OpenIntelligenceTests
//
//  Deep Think and Maximum fuse several searches by reciprocal rank (5.8). Each search comes back in lost-in-the-middle
//  order, best first and second best last, so the fusion has to rank each search by score itself, or the second best
//  passage of every search gets the worst rank.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class FusionRankOrderTests: XCTestCase {
    private func chunk(_ name: String, _ score: Float) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0, pageNumber: 1, sectionTitle: nil, keywords: [], hasNumericData: false,
            hasListStructure: false, wordCount: 1, characterCount: name.count)
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: name, embedding: [0], metadata: metadata),
            similarityScore: score, rank: 0, sourceDocument: "doc", pageNumber: 1)
    }

    func testLostInTheMiddleOrderIsRankedByScoreBeforeFusion() {
        // Five passages placed best first and second best last: 1, 3, 5, 4, 2.
        let placed = [chunk("p1", 0.9), chunk("p3", 0.7), chunk("p5", 0.5), chunk("p4", 0.6), chunk("p2", 0.8)]
        let ranked = AgenticOrchestrator.rankedForFusion(placed).map(\.chunk.content)
        XCTAssertEqual(ranked, ["p1", "p2", "p3", "p4", "p5"])
    }

    func testTiesKeepTheSearchsOwnOrder() {
        let ranked = AgenticOrchestrator.rankedForFusion([chunk("a", 0.5), chunk("b", 0.5), chunk("c", 0.9)])
            .map(\.chunk.content)
        XCTAssertEqual(ranked, ["c", "a", "b"])
    }

    func testTheAblationSwitchNamesTheRule() {
        XCTAssertEqual(RetrievalAblation.parse("fusionScoreOrder"), [.fusionScoreOrder])
    }
}

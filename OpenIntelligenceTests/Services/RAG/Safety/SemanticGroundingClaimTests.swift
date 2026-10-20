//
//  SemanticGroundingClaimTests.swift
//  OpenIntelligenceTests
//
//  Gate E compares how close the whole answer sits to one chunk with how close the question sat.
//  On 2026-10-02 it failed nine of nine right, cited answers to two sample questions, and in seven
//  of them the claim check had supported every sentence. From 5.6, when the ratio is the only thing
//  that failed and every claim is supported, the claims decide. These pin that rule and its two
//  limits: an unsupported claim, and an answer far from every chunk, still fail the gate.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class SemanticGroundingClaimTests: XCTestCase {
    private let leaseText =
        "Rent is late after 11:59 p.m. on the 5th day of the month. A late charge of $75.00 applies on the 6th day."

    private func leaseChunk() -> RetrievedChunk {
        let metadata = ChunkMetadata(chunkIndex: 0, pageNumber: 3, wordCount: 22, characterCount: leaseText.count)
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: leaseText, embedding: [], metadata: metadata),
            similarityScore: 0.9,
            rank: 1,
            sourceDocument: "Lease.pdf",
            pageNumber: 3
        )
    }

    private func grounding(
        claim: String,
        responseEmbedding: [Float]
    ) async -> (gate: RAGVerificationResult.GateResult?, claims: [RAGVerificationResult.ClaimResult]) {
        let result = await VerificationGateService().verify(
            response: claim,
            query: "When is my rent late?",
            retrievedChunks: [leaseChunk()],
            topScores: [0.9],
            responseEmbedding: responseEmbedding,
            queryEmbedding: [1, 0, 0],
            chunkEmbeddings: [[1, 0, 0]],
            structuredClaims: [StructuredRAGClaim(claim: claim, citations: ["S1"], isExtracted: true)]
        )
        return (result.gateResults.first { $0.gate == .semanticGrounding }, result.claimResults)
    }

    /// Cosine 0.5 with the chunk against the question's 1.0: ratio 0.5, under the 0.80 threshold and
    /// over the 0.25 floor.
    private let ratioOnlyFailure: [Float] = [0.5, 0.866, 0]

    func testSupportedClaimsDecideWhenOnlyTheRatioFails() async throws {
        let outcome = await grounding(
            claim: "Rent is late after 11:59 p.m. on the 5th day of the month.",
            responseEmbedding: ratioOnlyFailure
        )
        XCTAssertFalse(outcome.claims.isEmpty)
        XCTAssertTrue(
            outcome.claims.allSatisfy { $0.verdict == .supported },
            "precondition: the claim check must support a sentence copied from the source")
        let gate = try XCTUnwrap(outcome.gate)
        XCTAssertTrue(gate.passed, gate.details)
        XCTAssertTrue(gate.details.hasPrefix("Grounded by claims"), gate.details)
    }

    func testAnUnsupportedClaimStillFailsTheGate() async throws {
        let outcome = await grounding(
            claim: "Pets are allowed with a refundable deposit of four hundred dollars.",
            responseEmbedding: ratioOnlyFailure
        )
        XCTAssertFalse(outcome.claims.allSatisfy { $0.verdict == .supported })
        let gate = try XCTUnwrap(outcome.gate)
        XCTAssertFalse(gate.passed, gate.details)
    }

    func testAnAnswerFarFromEveryChunkStillFailsWhateverTheClaimsSay() async throws {
        // Cosine 0.1 with the chunk: under the absolute floor.
        let outcome = await grounding(
            claim: "Rent is late after 11:59 p.m. on the 5th day of the month.",
            responseEmbedding: [0.1, 0.995, 0]
        )
        let gate = try XCTUnwrap(outcome.gate)
        XCTAssertFalse(gate.passed, gate.details)
    }

    /// When the question sat as far from the chunks as the answer, the ratio passes and only the floor fails, and the
    /// detail names the floor (5.7). It read "UNGROUNDED (ratio=2.115 < 0.80" for a ratio that passed and a best
    /// similarity of 0.245 (demo copy of 3a9fcb8, 2026-10-20).
    func testTheDetailNamesTheFloorWhenOnlyTheFloorFails() async throws {
        let claim = "Rent is late after 11:59 p.m. on the 5th day of the month."
        let result = await VerificationGateService().verify(
            response: claim,
            query: "When is my rent late?",
            retrievedChunks: [leaseChunk()],
            topScores: [0.9],
            responseEmbedding: [0.24, 0.9708, 0],
            queryEmbedding: [0.25, 0.9682, 0],
            chunkEmbeddings: [[1, 0, 0]],
            structuredClaims: [StructuredRAGClaim(claim: claim, citations: ["S1"], isExtracted: true)]
        )
        let gate = try XCTUnwrap(result.gateResults.first { $0.gate == .semanticGrounding })
        XCTAssertFalse(gate.passed, gate.details)
        XCTAssertTrue(gate.details.hasPrefix("UNGROUNDED (respMax=0.240 < floor 0.25"), gate.details)
    }
}

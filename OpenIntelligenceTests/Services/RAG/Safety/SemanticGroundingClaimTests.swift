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

    private func farFromItsPassages(flagged: Bool) async -> RAGVerificationResult {
        let claim = "Rent is late after 11:59 p.m. on the 5th day of the month."
        return await VerificationGateService().verify(
            response: claim,
            query: "When is my rent late?",
            retrievedChunks: [leaseChunk()],
            topScores: [0.9],
            responseEmbedding: [0.031, 0.9995, 0],
            queryEmbedding: [0.045, 0.999, 0],
            chunkEmbeddings: [[1, 0, 0]],
            structuredClaims: [StructuredRAGClaim(claim: claim, citations: ["S1"], isExtracted: true)],
            passageVectorsMayBeAnotherModels: flagged
        )
    }

    /// In a library the model check flagged, a question under the floor too means the stored vectors are another
    /// model's, and no distance says anything about the answer (5.8, 2026-11-18). On the owner's iPhone a grounded Deep
    /// Think answer measured respMax 0.031 against qryMax 0.045 and the gate failed it as ungrounded.
    func testTheGateDoesNotJudgeWhenTheQuestionIsAsFarFromItsPassagesAsTheAnswer() async throws {
        let result = await farFromItsPassages(flagged: true)
        let gate = try XCTUnwrap(result.gateResults.first { $0.gate == .semanticGrounding })
        XCTAssertTrue(gate.passed, gate.details)
        XCTAssertTrue(gate.notChecked)
        XCTAssertTrue(gate.details.hasPrefix("NOT_CHECKED (qryMax=0.045 < floor 0.25"), gate.details)
        XCTAssertFalse(result.abstainReason?.contains("Semantic Grounding") ?? false)
        // Review row 6: it measured nothing, so it is out of the average and the answer does not read Verified.
        let judged = result.gateResults.filter { !$0.notChecked }
        XCTAssertEqual(result.overallConfidence, judged.reduce(0) { $0 + $1.confidence } / Float(judged.count), accuracy: 1e-6)
        if result.passed {
            let summary = RAGService.verificationSummary(for: result)
            XCTAssertTrue(summary.hasPrefix("checked:"), summary)
            XCTAssertTrue(summary.contains("not_checked:Gate E: Semantic Grounding"), summary)
            XCTAssertFalse(summary.contains("verified:"), summary)
            XCTAssertNotEqual(VerificationOutcome.from(gatingDecision: summary), .supported)
        }
    }

    /// The same numbers in a library the check did not flag (an NLEmbedding library, or a Granite one whose vectors
    /// are the live model's): the floor decides, and the answer fails (review row 5).
    func testOutsideAFlaggedLibraryTheFloorStillFailsTheAnswer() async throws {
        let result = await farFromItsPassages(flagged: false)
        let gate = try XCTUnwrap(result.gateResults.first { $0.gate == .semanticGrounding })
        XCTAssertFalse(gate.passed, gate.details)
        XCTAssertFalse(gate.notChecked)
        XCTAssertTrue(gate.details.hasPrefix("UNGROUNDED (respMax=0.031 < floor 0.25"), gate.details)
    }

    /// With the app's NLEmbedding provider (`nl_embedding`, averaged NLEmbedding word vectors), an off-topic question
    /// and answer against a lease passage, the library not flagged (an NLEmbedding library never is,
    /// `RAGService.passageVectorsMayBeAnotherModels`): the gate is never NOT_CHECKED, and it fails the answer whenever
    /// the answer is under the floor (review row 5).
    func testNLEmbeddingVectorsAndAnOffTopicQuestionAreJudgedAsBefore() async throws {
        let provider = NLEmbeddingProvider()
        let question = "Which planet has a storm called the Great Red Spot?"
        let answer = "Jupiter's Great Red Spot is a storm larger than Earth that has lasted for centuries."
        let passage = try await provider.embed(text: leaseText)
        let answerVector = try await provider.embed(text: answer)
        let questionVector = try await provider.embed(text: question)
        func cosine(_ a: [Float], _ b: [Float]) -> Float { StoredVectorModelCheck.cosine(a, b) }
        let respMax = cosine(answerVector, passage), qryMax = cosine(questionVector, passage)
        let result = await VerificationGateService().verify(
            response: answer, query: question, retrievedChunks: [leaseChunk()], topScores: [0.9],
            responseEmbedding: answerVector, queryEmbedding: questionVector, chunkEmbeddings: [passage],
            passageVectorsMayBeAnotherModels: false)
        let gate = try XCTUnwrap(result.gateResults.first { $0.gate == .semanticGrounding })
        print("[SemanticGrounding] NLEmbedding off-topic: qryMax \(qryMax), respMax \(respMax): \(gate.details)")
        XCTAssertFalse(gate.notChecked, gate.details)
        XCTAssertFalse(gate.details.hasPrefix("NOT_CHECKED"), gate.details)
        if respMax < VerificationGateService.semanticGroundingFloor {
            XCTAssertFalse(gate.passed, gate.details)
        }
        // The same vectors flagged would be declined only if the question were under the floor; an NLEmbedding
        // library is never flagged, so this never reaches the gate.
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

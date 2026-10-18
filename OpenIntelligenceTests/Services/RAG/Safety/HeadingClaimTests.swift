//
//  HeadingClaimTests.swift
//  OpenIntelligenceTests
//
//  An answer's own heading is not a claim for Fact Check (5.7, `VerificationGateService.headingLines`). The model
//  sometimes lists its title among its claims, and "Hotel Address in Lisbon" was scored Partial, so a right answer
//  read "1 of 2 Verified" (demo copy of e9de06d in the Simulator, 2026-10-15).
//

import XCTest

@testable import OpenIntelligence

final class HeadingClaimTests: XCTestCase {
    func testHeadingsAreFoundInEveryForm() {
        let answer = """
            ## Hotel Address in Lisbon
            The hotel is Casa Azulejo, Rua das Flores 41, Chiado [S3].
            **Check-out**
            Getting there:
            Take the metro to Baixa-Chiado.
            """
        let headings = VerificationGateService.headingLines(in: answer)
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Hotel Address in Lisbon")))
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Check-out")))
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Getting there")))
        XCTAssertFalse(
            headings.contains(VerificationGateService.headingKey("The hotel is Casa Azulejo, Rua das Flores 41, Chiado.")))
        XCTAssertFalse(headings.contains(VerificationGateService.headingKey("Take the metro to Baixa-Chiado.")))
    }

    func testAnAnswerWithNoHeadingsHasNone() {
        XCTAssertTrue(VerificationGateService.headingLines(in: "Check-out is at 11:00 a.m. [S2].").isEmpty)
    }

    private func leaseChunk(_ text: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: 2,
            sectionTitle: nil,
            keywords: [],
            hasNumericData: false,
            hasListStructure: false,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.9,
            rank: 1,
            sourceDocument: "Juniper Flats Lease - Unit 4B.pdf",
            pageNumber: 2
        )
    }

    /// The heading stays out of the answer's claim list too, so Fact Check neither lists it as "Not checked" nor
    /// counts it: the half `eaccacc` left, seen 2026-10-18 in 2 of 4 takes of one question in the Simulator. And the
    /// space a removed citation leaves before the full stop goes with it.
    func testAHeadingNeverReachesTheClaimListAndNoSpaceIsLeftWhereACitationWas() {
        let lease = "13. Entry by Landlord. Landlord will give at least 24 hours' notice before entering, except in an emergency."
        let generation = StructuredRAGGeneration(
            reasoning: nil,
            answer: "**Notice to Enter**\n- The landlord must give at least 24 hours' notice before entering, except in an emergency [S1].",
            confidence: 90,
            citations: ["S1"],
            matchedTerms: [],
            claims: [
                StructuredRAGClaim(claim: "Notice to Enter", citations: [], isExtracted: false),
                StructuredRAGClaim(
                    claim: "The landlord must give at least 24 hours' notice before entering, except in an emergency [S1].",
                    citations: ["S1"], isExtracted: true),
            ])
        let answer = StructuredAnswer.from(
            response: generation.answer,
            retrievedChunks: [leaseChunk(lease)],
            answerIntent: .lookup,
            verificationResult: nil,
            structuredGeneration: generation)
        XCTAssertEqual(
            answer.claims.map(\.claim),
            ["The landlord must give at least 24 hours' notice before entering, except in an emergency."])
    }

    private func structured(_ answer: String, _ claims: [(String, [String])]) -> StructuredRAGGeneration {
        StructuredRAGGeneration(
            reasoning: nil, answer: answer, confidence: 90, citations: ["S1"], matchedTerms: [],
            claims: claims.map { StructuredRAGClaim(claim: $0.0, citations: $0.1, isExtracted: true) })
    }

    private func claims(of generation: StructuredRAGGeneration, chunk text: String) -> [String] {
        StructuredAnswer.from(
            response: generation.answer, retrievedChunks: [leaseChunk(text)], answerIntent: .lookup,
            verificationResult: nil, structuredGeneration: generation
        ).claims.map(\.claim)
    }

    /// A sentence the answer makes in bold is a claim, not a heading (review, 2026-10-18): treating every bold line as
    /// a heading took "$400 deposit" out of Fact Check and, with the checks on, out of the answer itself.
    func testABoldSentenceIsAClaimNotAHeading() {
        let answer = "**Yes, cats are allowed with a $400 deposit.**\n- The deposit is refundable [S2]."
        XCTAssertTrue(VerificationGateService.headingLines(in: answer).isEmpty)
        XCTAssertTrue(VerificationGateService.isBoldTitle("**Notice to Enter**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Yes, cats are allowed with a $400 deposit.**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**24 hours' notice**"))
        let generation = structured(answer, [
            ("Yes, cats are allowed with a $400 deposit.", []), ("The deposit is refundable [S2].", ["S2"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Cats are allowed with a $400 deposit. The deposit is refundable."),
            ["Yes, cats are allowed with a $400 deposit.", "The deposit is refundable."])
    }

    /// A heading that carries a citation is still a heading, on both sides: Gate B and the claim list match the same
    /// way, so a heading claim with a citation is neither checked nor listed (review, 2026-10-18).
    func testAHeadingWithACitationIsStillAHeading() {
        let answer = "## Notice to Enter [S1]\n- The landlord must give at least 24 hours' notice [S1]."
        let headings = VerificationGateService.headingLines(in: answer)
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Notice to Enter [S1]")))
        XCTAssertEqual(VerificationGateService.headingKey("Notice to Enter [S1]"), VerificationGateService.headingKey("Notice to Enter"))
        let generation = structured(answer, [
            ("Notice to Enter [S1]", ["S1"]), ("The landlord must give at least 24 hours' notice [S1].", ["S1"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Landlord will give at least 24 hours' notice before entering."),
            ["The landlord must give at least 24 hours' notice."])
    }

    /// When every claim is a heading, the claims stay: an answer is never left with none, which with the checks on
    /// would turn it into a refusal (review, 2026-10-18).
    func testWhenEveryClaimIsAHeadingTheClaimsStay() {
        let generation = structured("**Notice to Enter**", [("Notice to Enter", [])])
        XCTAssertEqual(claims(of: generation, chunk: "13. Entry by Landlord."), ["Notice to Enter"])
    }

    /// What a removed citation leaves behind is tidied, and nothing else is touched (review, 2026-10-18).
    func testWhatARemovedCitationLeavesBehindIsTidied() {
        let generation = structured("Check-out is at 11:00 a.m. [S2].", [
            ("Check-out is at 11:00 a.m. [S2].", ["S2"]),
            ("Rent is due on the 5th [S1], [S2].", ["S1", "S2"]),
            ("See the lease (section 13 [S1]).", ["S1"]),
            ("It costs $75.50 [S1].", ["S1"]),
            ("Wait for the next step... [S3]", ["S3"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Check-out is at 11:00 a.m. Rent is due on the 5th. It costs $75.50."),
            ["Check-out is at 11:00 a.m.", "Rent is due on the 5th.", "See the lease (section 13).", "It costs $75.50.",
             "Wait for the next step..."])
    }

    /// The answer rebuilt from its checked claims keeps an abbreviation's full stop before the citation:
    /// "11:00 a.m. [S1].", not "11:00 a.m [S1]." (review, 2026-10-18).
    func testTheRebuiltAnswerKeepsAnAbbreviationsFullStop() {
        XCTAssertTrue(StructuredAnswer.endsWithAbbreviation("Check-out is at 11:00 a.m."))
        XCTAssertTrue(StructuredAnswer.endsWithAbbreviation("Bring a photo ID, a lease, etc."))
        XCTAssertFalse(StructuredAnswer.endsWithAbbreviation("It costs $75.50."))
        XCTAssertFalse(StructuredAnswer.endsWithAbbreviation("Rent is due on the 5th."))
        let claim = "Check-out is at 11:00 a.m."
        let verification = RAGVerificationResult(
            passed: true,
            gateResults: [.init(gate: .evidenceCoverage, passed: true, confidence: 1, details: "")],
            claimResults: [.init(claim: claim, verdict: .supported, confidence: 0.9, details: "", citations: ["S1"], resolvedEvidenceIds: [])],
            overallConfidence: 0.9, shouldAbstain: false, abstainReason: nil)
        let generation = structured("Check-out is at 11:00 a.m. [S1].", [("Check-out is at 11:00 a.m. [S1].", ["S1"])])
        let answer = StructuredAnswer.from(
            response: generation.answer, retrievedChunks: [leaseChunk("Check-out is at 11:00 a.m. on the last day.")],
            answerIntent: .lookup, verificationResult: verification, structuredGeneration: generation)
        XCTAssertFalse(answer.refuse)
        XCTAssertFalse(answer.answer.contains("a.m ["), answer.answer)
        XCTAssertFalse(answer.answer.contains("a.m.."), answer.answer)
    }

    /// Without structured claims, a bold sentence with a time in it is a claim the checks can support (review,
    /// 2026-10-18): it is not taken for a heading, so the answer is not refused for having no claims.
    func testABoldSentenceInAPlainAnswerIsKept() {
        let verification = RAGVerificationResult(
            passed: true,
            gateResults: [.init(gate: .evidenceCoverage, passed: true, confidence: 1, details: "")],
            claimResults: [.init(claim: "Check-out is at 11:00 a.m.", verdict: .supported, confidence: 0.9, details: "", citations: [], resolvedEvidenceIds: [])],
            overallConfidence: 0.9, shouldAbstain: false, abstainReason: nil)
        let answer = StructuredAnswer.from(
            response: "**Check-out is at 11:00 a.m.**", retrievedChunks: [leaseChunk("Check-out is at 11:00 a.m.")],
            answerIntent: .lookup, verificationResult: verification, structuredGeneration: nil, allowUngroundedFallback: false)
        XCTAssertFalse(answer.refuse)
        XCTAssertEqual(answer.claims.count, 1)
    }

    /// A number that starts with its decimal point keeps the space in front of it.
    func testADecimalAfterASpaceKeepsItsSpace() {
        let generation = StructuredRAGGeneration(
            reasoning: nil,
            answer: "The late fee is .5 percent of the rent [S1].",
            confidence: 90,
            citations: ["S1"],
            matchedTerms: [],
            claims: [StructuredRAGClaim(claim: "The late fee is .5 percent of the rent [S1].", citations: ["S1"], isExtracted: true)])
        let answer = StructuredAnswer.from(
            response: generation.answer,
            retrievedChunks: [leaseChunk("The late fee is .5 percent of the rent.")],
            answerIntent: .lookup,
            verificationResult: nil,
            structuredGeneration: generation)
        XCTAssertEqual(answer.claims.map(\.claim), ["The late fee is .5 percent of the rent."])
    }
}

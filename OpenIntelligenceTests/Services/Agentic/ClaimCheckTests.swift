//
//  ClaimCheckTests.swift
//  OpenIntelligenceTests
//
//  "Check a Claim" returns a verdict a shortcut can test and says where it rests (5.7). The checks
//  below run the real claim check (`VerificationGateService`) on passages made here.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ClaimCheckTests: XCTestCase {
    private func passage(_ text: String, score: Float) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(), content: text, embedding: [],
                metadata: ChunkMetadata(
                    chunkIndex: 0, pageNumber: 3, wordCount: text.split(separator: " ").count,
                    characterCount: text.count)),
            similarityScore: score, rank: 0, sourceDocument: "Lease.pdf", pageNumber: 3)
    }

    func testAnUnrelatedPassageDoesNotHoldItUp() async {
        // Through the first version of this action the claim was also the check's question, which
        // counted every word of it as found, so this came back partly supported.
        let outcome = await ClaimCheck.check(
            "The security deposit is two months of rent.",
            against: [passage("The garden hose is kept in the shed behind the garage.", score: 0.2)])
        XCTAssertEqual(outcome.verdict, .unsupported)
    }

    func testAMatchingPassageHoldsItUp() async {
        let outcome = await ClaimCheck.check(
            "The security deposit is two months of rent.",
            against: [passage("The tenant pays a security deposit of two months of rent before moving in.", score: 0.8)]
        )
        XCTAssertEqual(outcome.verdict, .supported)
        XCTAssertEqual(outcome.source, "Lease.pdf, page 3")
        XCTAssertFalse(outcome.negationDiffers)
    }

    func testAPassageThatSaysTheOppositeIsNotSupported() async {
        let outcome = await ClaimCheck.check(
            "Pets are allowed in the apartment.",
            against: [passage("Pets are not allowed in the apartment at any time.", score: 0.85)])
        XCTAssertTrue(outcome.negationDiffers)
        XCTAssertNotEqual(outcome.verdict, .supported)
    }

    func testOnlyTheMatchingSentenceIsComparedForANegation() async {
        // The first version compared the sentences after the matching one too, so a "not" anywhere
        // after it lowered a passage that says just what the claim says.
        let text = "Pets are allowed in the apartment. Smoking is not allowed anywhere on the property."
        XCTAssertEqual(
            ClaimCheck.matchingSentence(for: "Pets are allowed in the apartment.", in: text),
            "Pets are allowed in the apartment.")
        let outcome = await ClaimCheck.check(
            "Pets are allowed in the apartment.", against: [passage(text, score: 0.85)])
        XCTAssertFalse(outcome.negationDiffers)
        XCTAssertEqual(outcome.verdict, .supported)
    }

    func testAProhibitionIsTheOppositeOfAnAllowance() async {
        let outcome = await ClaimCheck.check(
            "Smoking is allowed in the building.",
            against: [passage("Smoking is prohibited in the building and on the balconies.", score: 0.85)])
        XCTAssertTrue(outcome.negationDiffers)
        XCTAssertNotEqual(outcome.verdict, .supported)
    }

    func testNoPassageIsNotFound() async {
        let outcome = await ClaimCheck.check("Anything at all.", against: [])
        XCTAssertEqual(outcome.verdict, .notFound)
        XCTAssertEqual(ClaimCheck.sentence(outcome), "Nothing in the active library matches it.")
    }

    func testContentWordCoverageCountsWholeWords() {
        let lease = [passage("The tenant pays a security deposit of two months of rent.", score: 0.5)]
        XCTAssertEqual(ClaimCheck.contentWordCoverage("The security deposit is two months of rent.", in: lease), 1)
        XCTAssertEqual(ClaimCheck.contentWordCoverage("The garden hose is in the shed.", in: lease), 0)
        XCTAssertEqual(ClaimCheck.contentWordCoverage("It is.", in: lease), 1, "no content word to check")
    }

    func testNegationsAreFoundInEitherSpelling() {
        XCTAssertTrue(ClaimCheck.hasNegation("Smoking isn't permitted."))
        XCTAssertTrue(ClaimCheck.hasNegation("Smoking isn\u{2019}t permitted."))
        XCTAssertTrue(ClaimCheck.hasNegation("No pets."))
        XCTAssertTrue(ClaimCheck.hasNegation("The landlord will never enter without notice."))
        XCTAssertFalse(
            ClaimCheck.hasNegation("Notice is given in writing."), "a word that starts with \"no\" is not a negation")
    }

    func testBoundsAndSetPhrasesAreNotNegations() {
        XCTAssertFalse(ClaimCheck.hasNegation("Rent is due no later than the 5th."))
        XCTAssertFalse(ClaimCheck.hasNegation("Give notice not less than 30 days before leaving."))
        XCTAssertFalse(ClaimCheck.hasNegation("Repairs not to exceed $500 are the tenant's."))
        XCTAssertFalse(ClaimCheck.hasNegation("Unit No. 4 is on the second floor."))
        XCTAssertFalse(ClaimCheck.hasNegation("No. of guests: 4."))
        XCTAssertFalse(ClaimCheck.hasNegation("Appliances, including without limitation the stove, stay."))
        XCTAssertFalse(ClaimCheck.hasNegation("The fee applies whether or not the tenant is home."))
        XCTAssertFalse(ClaimCheck.hasNegation("The rent is fixed; nonetheless, utilities vary."))
        XCTAssertTrue(
            ClaimCheck.hasNegation("Rent is due no later than the 5th, and no pets are allowed."),
            "a bound beside a real negation")
        XCTAssertTrue(ClaimCheck.hasNegation("The answer is no."))
    }

    func testRefusalsWithoutANotAreNegations() {
        XCTAssertTrue(ClaimCheck.hasNegation("The deposit is non-refundable."))
        XCTAssertTrue(ClaimCheck.hasNegation("The deposit is nonrefundable."))
        XCTAssertTrue(ClaimCheck.hasNegation("Smoking is prohibited in the building."))
        XCTAssertTrue(ClaimCheck.hasNegation("Subletting is forbidden."))
        XCTAssertFalse(ClaimCheck.hasNegation("The deposit is refundable."))
    }

    func testTheGatesVerdictsMapToFourLabels() {
        XCTAssertEqual(ClaimCheck.verdict(.supported).label, "Supported")
        XCTAssertEqual(ClaimCheck.verdict(.partial).label, "Partly supported")
        XCTAssertEqual(ClaimCheck.verdict(.unsupported).label, "Not supported")
        XCTAssertEqual(ClaimCheck.verdict(nil).label, "Not supported", "no verdict is not a support")
        XCTAssertEqual(ClaimCheck.Verdict.notFound.label, "Not found")
    }

    func testTheSentenceNamesThePassageAndWhatDiffers() {
        XCTAssertEqual(
            ClaimCheck.sentence(
                .init(verdict: .supported, source: "Lease.pdf, page 3", numberMismatch: false, negationDiffers: false)),
            "Your documents hold it up, in Lease.pdf, page 3.")
        XCTAssertEqual(
            ClaimCheck.sentence(
                .init(verdict: .partial, source: "Lease.pdf, page 3", numberMismatch: true, negationDiffers: true)),
            "Your documents partly hold it up, in Lease.pdf, page 3. One of them says no where the other says yes, so read the passage. A number in it doesn't match what the documents say."
        )
        XCTAssertEqual(
            ClaimCheck.sentence(
                .init(verdict: .unsupported, source: "Lease.pdf, page 3", numberMismatch: false, negationDiffers: false)
            ),
            "Your documents don't hold it up. The closest passage is in Lease.pdf, page 3.")
    }
}

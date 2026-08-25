import XCTest
@testable import OpenIntelligenceEngine

/// Pins `AgenticPolicyService.assertsAbsenceOfEvidence` and the verification action
/// built on it.
///
/// The failure this implements a check for, observed 2026-08-17: Self-RAG returned
/// `accept (relevance=70%, citations=1/1, confidence=88%)` for an answer that asserted
/// the corpus held no evidence on the question while citing twenty sources from it.
/// `citations=1/1` is a perfect score and means only that the markers resolve.
///
/// Most of these cases are answers that must **not** be flagged, because a false
/// positive spends a retry for nothing.
final class AbsenceAssertionTests: XCTestCase {

    // MARK: - Must be flagged

    /// Close to the sentence from the capture.
    func testFlagsAbsenceClaimAboutTheDocuments() {
        let answer = "Dopamine signalling can include social interaction, but the provided documents contain no detailed evidence of such effects."
        XCTAssertTrue(AgenticPolicyService.assertsAbsenceOfEvidence(in: answer))
    }

    func testFlagsCommonPhrasings() {
        for answer in [
            "The documents do not mention social stress.",
            "The retrieved sources do not address this question.",
            "There is no information in the provided context about dosage.",
            "This cannot be determined from the excerpts supplied."
        ] {
            XCTAssertTrue(AgenticPolicyService.assertsAbsenceOfEvidence(in: answer), "Should flag: \(answer)")
        }
    }

    // MARK: - Must NOT be flagged

    /// A finding reported *by* a document is not a claim *about* the documents. This is
    /// the distinction the detector exists to make, and the main false-positive risk.
    func testDoesNotFlagAFindingOfNoEffect() {
        let answer = "The study found no evidence of an effect on locomotion [S1]. A later trial reported no data supporting the hypothesis [S2]."
        XCTAssertFalse(AgenticPolicyService.assertsAbsenceOfEvidence(in: answer))
    }

    /// Corpus reference without an absence claim.
    func testDoesNotFlagOrdinaryCitationLanguage() {
        let answer = "The provided documents describe two mechanisms [S1]. The sources agree on the timescale [S2]."
        XCTAssertFalse(AgenticPolicyService.assertsAbsenceOfEvidence(in: answer))
    }

    /// The two halves must fall in the same sentence, not merely the same answer.
    func testRequiresBothSignalsInOneSentence() {
        let answer = "The documents describe dopamine dynamics in detail. Separately, the trial found no evidence of harm."
        XCTAssertFalse(AgenticPolicyService.assertsAbsenceOfEvidence(in: answer))
    }

    // MARK: - The gate

    /// A self-contradicting answer must not be accepted, whatever its other scores.
    func testSelfContradictingAnswerIsRetried() {
        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: true,
            groundingScore: 1.0,
            totalCitations: 20,
            calibratedConfidence: 0.88,
            assertsAbsenceOfEvidence: true
        )
        XCTAssertEqual(action, "retry")
    }

    /// An honest abstention — asserting absence with nothing cited — is not a
    /// contradiction and must still be allowed through.
    func testHonestAbstentionIsNotRetried() {
        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: true,
            groundingScore: 1.0,
            totalCitations: 0,
            calibratedConfidence: 0.9,
            assertsAbsenceOfEvidence: true
        )
        XCTAssertNotEqual(action, "retry")
    }

    /// The existing behaviour is unchanged when the new signal is absent.
    func testUnrelatedBehaviourUnchanged() {
        XCTAssertEqual(
            AgenticPolicyService.verificationAction(
                addressesQuestion: true, groundingScore: 1.0,
                totalCitations: 4, calibratedConfidence: 0.9
            ),
            "accept"
        )
        XCTAssertEqual(
            AgenticPolicyService.verificationAction(
                addressesQuestion: true, groundingScore: 0.5,
                totalCitations: 4, calibratedConfidence: 0.9
            ),
            "retry"
        )
    }
}

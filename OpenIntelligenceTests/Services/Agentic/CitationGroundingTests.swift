import XCTest

@testable import OpenIntelligenceEngine

/// Covers the four defects behind a device capture on 2026-08-19 in which the reasoning trace cited
/// `[S13]` and `[S17]` against a twelve-source list, and the pipeline accepted the answer at 67%
/// confidence with half its citations ungrounded.
final class CitationGroundingTests: XCTestCase {

    // MARK: - Dangling citation detection

    func testCitationsWithinRangeAreNotReportedAsDangling() {
        let text = "Dopamine acts on the dorsal striatum [S1] and not the NAc [S12]."
        XCTAssertEqual(AgenticOrchestrator.danglingCitations(in: text, sourceCount: 12), [])
    }

    /// The exact shape from the capture.
    func testCitationsPastTheEndOfTheSourceListAreReported() {
        let text = "Striatal D2 receptors modulate lateral inhibition [S13], and autoreceptors [S17]."
        XCTAssertEqual(AgenticOrchestrator.danglingCitations(in: text, sourceCount: 12), [13, 17])
    }

    func testZeroAndNegativeIndicesAreReported() {
        XCTAssertEqual(AgenticOrchestrator.danglingCitations(in: "see [S0]", sourceCount: 12), [0])
    }

    func testEachDanglingIndexIsReportedOnce() {
        let text = "[S13] and again [S13] and once more [S13]"
        XCTAssertEqual(AgenticOrchestrator.danglingCitations(in: text, sourceCount: 12), [13])
    }

    func testTextWithNoCitationsIsClean() {
        XCTAssertEqual(AgenticOrchestrator.danglingCitations(in: "no citations here", sourceCount: 0), [])
    }

    // MARK: - Grounding threshold

    /// The capture logged `accept (relevance=54%, citations=2/4, confidence=67%)`. Half the
    /// citations failed to check out and the answer shipped.
    func testHalfTheCitationsUngroundedNoLongerAccepts() {
        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: true,
            groundingScore: 0.5,
            totalCitations: 4,
            calibratedConfidence: 0.67
        )
        XCTAssertEqual(action, "retry", "An answer with half its citations ungrounded must not be accepted.")
    }

    func testWellGroundedAnswersStillAccept() {
        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: true,
            groundingScore: 0.9,
            totalCitations: 4,
            calibratedConfidence: 0.8
        )
        XCTAssertEqual(action, "accept")
    }

    /// An answer citing nothing is not judged by the grounding bar, which has nothing to measure.
    func testAnswersWithNoCitationsAreNotFailedByTheGroundingBar() {
        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: true,
            groundingScore: 0.0,
            totalCitations: 0,
            calibratedConfidence: 0.8
        )
        XCTAssertNotEqual(action, "retry")
    }

    // MARK: - Confidence must be able to express failure

    /// Previously this returned exactly 0.30, because `completeness` saturated and the floor was
    /// 0.30. A fully ungrounded, fully irrelevant answer reported thirty percent confidence.
    func testAFullyUngroundedAnswerReportsLowConfidence() {
        let confidence = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: 0.0,
            citationScore: 0.0,
            answerLength: 3821,
            sourceCount: 12
        )
        XCTAssertLessThan(confidence, 0.30, "Confidence must be able to fall below the old floor.")
    }

    /// Length is not evidence of correctness. Two answers grounded identically must score the same
    /// whether one is terse and the other is five paragraphs.
    func testAnswerLengthDoesNotChangeConfidence() {
        let terse = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: 0.9, citationScore: 1.0, answerLength: 120, sourceCount: 12
        )
        let verbose = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: 0.9, citationScore: 1.0, answerLength: 3821, sourceCount: 12
        )
        XCTAssertEqual(terse, verbose, accuracy: 0.0001)
    }

    func testGroundingStillMovesConfidence() {
        let grounded = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: 0.9, citationScore: 1.0, answerLength: 800, sourceCount: 12
        )
        let ungrounded = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: 0.9, citationScore: 0.0, answerLength: 800, sourceCount: 12
        )
        XCTAssertGreaterThan(grounded, ungrounded)
    }
}

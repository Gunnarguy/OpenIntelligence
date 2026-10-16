import XCTest

@testable import OpenIntelligence

/// Pins when the app asks Apple for a rating. Each property here, if it drifted, would either
/// waste one of Apple's three prompts a year or skip the people most worth asking.
final class ReviewPromptServiceTests: XCTestCase {

    func testAsksOnTheFirstVerifiedAnswer() {
        // Three answers on two days was the old bar; 37% of device-weeks have one session.
        XCTAssertEqual(ReviewPromptService.minimumVerifiedAnswers, 1)
    }

    func testVerifiedSinglePassAnswer_counts() {
        XCTAssertTrue(ReviewPromptService.isVerified("verified:92%", retrievedSourceCount: 3))
        XCTAssertTrue(ReviewPromptService.isVerified("lenient,verified:70%", retrievedSourceCount: 1))
    }

    func testFlaggedAnswer_neverCounts_whateverItCited() {
        for decision in [
            "no_sources", "unverified:missing_citations", "low_confidence", "verification_gates_failed",
            "relevance_gate_failed", "high_accuracy_blocked", "context_empty",
            // An answer of excerpts alone, which no check stood behind (5.7).
            "excerpts_only",
        ] {
            XCTAssertFalse(ReviewPromptService.isVerified(decision, retrievedSourceCount: 5), decision)
        }
    }

    func testAgenticAnswer_withSources_counts() {
        // Deep Think and Maximum leave the gating string nil unless source-only refinement ran.
        // Until 5.4 that meant the most engaged users were never asked.
        XCTAssertTrue(ReviewPromptService.isVerified(nil, retrievedSourceCount: 4))
        XCTAssertTrue(ReviewPromptService.isVerified("", retrievedSourceCount: 1))
    }

    func testAgenticAnswer_withoutSources_doesNotCount() {
        XCTAssertFalse(ReviewPromptService.isVerified(nil, retrievedSourceCount: 0))
        XCTAssertFalse(ReviewPromptService.isVerified("", retrievedSourceCount: 0))
    }

    func testSourceOnlyAbstention_doesNotCount_butRefinementDoes() {
        // A Deep Think or Maximum answer that abstained is the app saying it could not answer.
        XCTAssertFalse(ReviewPromptService.isVerified("source_only_abstained", retrievedSourceCount: 2))
        XCTAssertTrue(ReviewPromptService.isVerified("source_only_refined", retrievedSourceCount: 2))
    }

    /// A failed check writes `unverified:<gates>`, which the old list of failure words missed, so an answer under a
    /// red Unverified badge counted (found 2026-10-15). The rating now follows the badge.
    func testAnAnswerUnderAnUnverifiedBadge_neverCounts() {
        XCTAssertFalse(ReviewPromptService.isVerified("unverified:numeric_sanity", retrievedSourceCount: 4))
        XCTAssertFalse(ReviewPromptService.isVerified("lenient,unverified:evidence_coverage+numeric_sanity", retrievedSourceCount: 4))
        XCTAssertFalse(ReviewPromptService.isVerified("verification_skipped", retrievedSourceCount: 4))
    }

    func testPassingGatesWithNoSupportedClaim_doNotCount() {
        let partial = StructuredAnswer.Claim(
            claim: "A claim.", evidenceIds: [], confidence: 0.5, isExtracted: false, verificationVerdict: .partial,
            verificationDetails: nil)
        XCTAssertFalse(ReviewPromptService.isVerified("verified:87%", retrievedSourceCount: 3, claims: [partial, partial]))
        XCTAssertTrue(ReviewPromptService.isVerified("verified:87%", retrievedSourceCount: 3, claims: []))
    }
}

//
//  VerificationOutcomeTests.swift
//  OpenIntelligenceTests
//
//  The Verified badge is a claim on every answer. Through 5.5 the bubble and the response details
//  called an answer Verified unless its gating string held one of a short list of failure words, so
//  `unverified:<gates>`, `verification_skipped` and a missing string all read Verified. These pin
//  each string the engine writes to what it means.
//

import XCTest

@testable import OpenIntelligenceEngine

final class VerificationOutcomeTests: XCTestCase {
    func testOnlyAPassedCheckIsSupported() {
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:92%"), .supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "lenient,verified:70%"), .supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "acceptance_override,verified:81%"), .supported)
        // Deep Think and Maximum: the source-only check ran and kept the answer.
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "source_only_refined"), .supported)
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "agentic_precision_extractive_override,source_only_refined"),
            .supported
        )
    }

    func testAFailedCheckIsNotSupportedEvenThoughItsNameContainsVerified() {
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding"), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "lenient,unverified:evidence_coverage+numeric_sanity"), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verification_gates_failed"), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "missing_citations"), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "source_only_abstained"), .notSupported)
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "extractive_override_pre_generation,source_only_abstained"),
            .notSupported
        )
    }

    func testACheckThatNeverRanIsNotChecked() {
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: nil), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: ""), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verification_skipped"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "lenient,verification_skipped"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "finished_early_by_person"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "agentic_precision_extractive_override"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "extractive_intent"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "allowed"), .notChecked)
    }

    func testRetrievalOutcomesKeepTheirOwnStates() {
        for decision in ["no_sources", "no_documents", "context_empty"] {
            XCTAssertEqual(VerificationOutcome.from(gatingDecision: decision), .noSources, decision)
        }
        for decision in ["low_confidence", "rerank_empty", "mmr_empty", "relevance_gate_failed"] {
            XCTAssertEqual(VerificationOutcome.from(gatingDecision: decision), .lowConfidence, decision)
        }
        for decision in ["reliability_fallback", "high_accuracy_blocked"] {
            XCTAssertEqual(VerificationOutcome.from(gatingDecision: decision), .partial, decision)
        }
    }

    /// An answer of excerpts alone had no model and no check behind it, and read Partially Verified
    /// through 5.6 (row "The Verified badge shows for answers whose checks failed or never ran").
    func testAnAnswerOfExcerptsAloneReadsNotChecked() {
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "excerpts_only"), .notChecked)
    }

    /// On 2026-10-15 an answer saying a date was not in the owner's notes passed the gates (0.87) and showed a green
    /// Verified over Fact Check's "0 of 2 Verified", both claims partial (5.7).
    func testPassingGatesWithNoSupportedClaimAreNotVerified() {
        let partial = Self.claim(.partial), unsupported = Self.claim(.unsupported), supported = Self.claim(.supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:87%", claims: [partial, partial]), .partial)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:87%", claims: [partial, unsupported]), .partial)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:87%", claims: [unsupported]), .notSupported)
        // One supported claim keeps the gates' Verified, and so does an answer whose claims were not checked.
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:87%", claims: [partial, supported]), .supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:87%", claims: [Self.claim(nil)]), .supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:87%", claims: []), .supported)
        // The claims never raise an outcome the gates did not reach.
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding", claims: [supported]), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: nil, claims: [supported]), .notChecked)
    }

    private static func claim(_ verdict: StructuredAnswer.Claim.VerificationVerdict?) -> StructuredAnswer.Claim {
        StructuredAnswer.Claim(
            claim: "A claim.", evidenceIds: [], confidence: 0.5, isExtracted: false, verificationVerdict: verdict,
            verificationDetails: nil)
    }
}

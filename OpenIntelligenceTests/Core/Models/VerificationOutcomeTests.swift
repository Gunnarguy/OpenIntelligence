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
}

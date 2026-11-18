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

    /// An answer is verified only when it is in the sources and answers the question (5.8). On 2026-11-07 the answer
    /// "1-28. [S3]" to "How much DHA is recommended?" was a page range the source-only check called supported.
    func testAnAnswerThatDoesNotAnswerIsNotSupportedHoweverGrounded() {
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:92%,answers:none"), .notSupported)
        XCTAssertEqual(
            VerificationOutcome.from(
                gatingDecision: "acceptance_override,unverified:Gate E: Semantic Grounding,source_only_refined,answers:none"),
            .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "source_only_refined,answers:none"), .notSupported)
        // A partial reading adds a warning and leaves the badge.
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:92%,answers:partial"), .supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:92%,answers:full"), .supported)
        // No judgment (model unavailable) leaves the grounding outcome as it was.
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verified:92%"), .supported)
        // The judge cannot raise a failed or unchecked answer on its own.
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding,answers:full"), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "answers:full"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "verification_skipped,answers:full"), .notChecked)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "no_sources,answers:none"), .noSources)
    }

    /// Standard runs the source-only check after its gates fail, so a rewrite it kept follows the gates' `unverified:`
    /// for the answer it replaced. The rewrite decides only when the judge read it as a full answer.
    func testAKeptSourceOnlyRewriteThatAnswersIsSupportedAfterFailedGates() {
        XCTAssertEqual(
            VerificationOutcome.from(
                gatingDecision: "acceptance_override,unverified:Gate E: Semantic Grounding,source_only_refined,answers:full"),
            .supported)
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding,source_only_refined"), .notSupported)
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding,source_only_refined,answers:partial"),
            .notSupported)
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding,source_only_abstained,answers:full"),
            .notSupported)
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "missing_citations,source_only_refined,answers:full"), .notSupported)
        // The rewrite's own checked claims still lower it when none is supported.
        XCTAssertEqual(
            VerificationOutcome.from(
                gatingDecision: "unverified:semantic_grounding,source_only_refined,answers:full",
                claims: [Self.claim(.unsupported)]),
            .notSupported)
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
        // The claims never raise an outcome to Verified, nor one no check reached.
        XCTAssertNotEqual(
            VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding", claims: [supported]), .supported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: nil, claims: [supported]), .notChecked)
    }

    /// On the owner's iPhone on 2026-11-18 a Deep Think answer showed a red Unverified under Fact Check's "5 of 6
    /// Verified": Gate E alone failed. Gate E failing alone over a supported claim is partial (5.8).
    func testGateEFailingAloneOverASupportedClaimIsPartial() {
        let supported = Self.claim(.supported), partial = Self.claim(.partial), unsupported = Self.claim(.unsupported)
        let fiveOfSix = Array(repeating: supported, count: 5) + [partial]
        let deepThink = "unverified:Gate E: Semantic Grounding,answers:full"
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: deepThink, claims: fiveOfSix), .partial)
        // An unsupported claim beside a supported one: still partial, and the details name it (below).
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: deepThink, claims: [supported, unsupported]), .partial)
        // No supported claim: the failure stands.
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: deepThink, claims: [partial, unsupported]), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: deepThink, claims: []), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: deepThink, claims: [Self.claim(nil)]), .notSupported)
    }

    /// Review row 7: any other failed gate keeps Unverified, alone or beside Gate E, whatever the claims say. A and I
    /// never read the answer; B, C, D, F, G and H find a defect in it.
    func testAnyOtherFailedGateStaysUnverified() {
        let fiveOfSix = Array(repeating: Self.claim(.supported), count: 5) + [Self.claim(.partial)]
        for gate in VerificationGate.allCases where gate != .semanticGrounding {
            for decision in ["unverified:\(gate.rawValue)", "unverified:Gate E: Semantic Grounding+\(gate.rawValue)"] {
                XCTAssertEqual(VerificationOutcome.from(gatingDecision: decision, claims: fiveOfSix), .notSupported, decision)
            }
        }
        // A name the rule cannot read is not lifted.
        XCTAssertEqual(
            VerificationOutcome.from(gatingDecision: "unverified:semantic_grounding", claims: fiveOfSix), .notSupported)
    }

    /// Review row 11: failures a supported claim cannot answer for stay not supported beside a failed Gate E.
    func testFailuresTheClaimsCannotAnswerForStayUnverified() {
        let fiveOfSix = Array(repeating: Self.claim(.supported), count: 5) + [Self.claim(.partial)]
        for other in [
            "unverified:Gate E: Semantic Grounding,answers:none",
            "unverified:Gate E: Semantic Grounding,missing_citations",
            "unverified:Gate E: Semantic Grounding,source_only_abstained",
            "verification_gates_failed:Gate E: Semantic Grounding",
            "verification_gates_failed",
            "source_only_abstained",
            "missing_citations",
        ] {
            XCTAssertEqual(VerificationOutcome.from(gatingDecision: other, claims: fiveOfSix), .notSupported, other)
        }
    }

    /// Review row 6: gates that passed with one that could not judge do not read Verified.
    func testAGateThatCouldNotJudgeKeepsTheAnswerFromVerified() {
        let supported = Self.claim(.supported), partial = Self.claim(.partial), unsupported = Self.claim(.unsupported)
        let unchecked = "checked:86%,not_checked:Gate E: Semantic Grounding,answers:full"
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: unchecked), .partial)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: unchecked, claims: [supported, partial]), .partial)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: unchecked, claims: [partial]), .partial)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: unchecked, claims: [unsupported]), .notSupported)
        XCTAssertEqual(VerificationOutcome.from(gatingDecision: "checked:86%,not_checked:Gate E: Semantic Grounding,answers:none"), .notSupported)
        XCTAssertEqual(
            VerificationOutcome.uncheckedChecks(in: unchecked),
            ["how close the whole answer sits to its passages, because this library's search index was made by an older model and is being rebuilt"])
    }

    func testTheFailedChecksAreNamedInPlainWords() {
        XCTAssertEqual(
            VerificationOutcome.failedChecks(in: "unverified:Gate E: Semantic Grounding,answers:full"),
            ["the answer as a whole reads far from its passages"])
        XCTAssertEqual(
            VerificationOutcome.failedChecks(in: "lenient,unverified:Gate C: Numeric Sanity+Gate H: Answer Completeness"),
            ["a number in the answer is not in the passages", "part of the question may be left unanswered"])
        XCTAssertEqual(VerificationOutcome.failedChecks(in: "verified:88%"), [])
        XCTAssertEqual(VerificationOutcome.failedChecks(in: nil), [])
        // A name this list does not know is shown as written rather than dropped.
        XCTAssertEqual(VerificationOutcome.failedChecks(in: "unverified:semantic_grounding"), ["semantic_grounding"])
        for gate in VerificationGate.allCases {
            let named = VerificationOutcome.failedChecks(in: "unverified:\(gate.rawValue)")
            XCTAssertEqual(named.count, 1)
            XCTAssertNotEqual(named.first, gate.rawValue, "\(gate.rawValue) has no plain words")
        }
    }

    /// The details count claims as Fact Check does (supported of all claims) and name the unsupported ones.
    func testThePartialSummarySaysWhatPassedAndWhatDidNot() {
        let supported = Self.claim(.supported), partial = Self.claim(.partial)
        let claims = Array(repeating: supported, count: 5) + [partial]
        let deepThink = "unverified:Gate E: Semantic Grounding,answers:full"
        XCTAssertEqual(
            VerificationOutcome.partialSummary(gatingDecision: deepThink, claims: claims),
            "5 of 6 claims are supported by your documents. One check of the whole answer did not pass: "
                + "the answer as a whole reads far from its passages.")
        let unsupported = StructuredAnswer.Claim(
            claim: "Probiotics cure canine anxiety.", evidenceIds: [], confidence: 0.1, isExtracted: false,
            verificationVerdict: .unsupported, verificationDetails: nil)
        let unchecked = StructuredAnswer.Claim(
            claim: "Not checked.", evidenceIds: [], confidence: 0.1, isExtracted: false, verificationVerdict: nil,
            verificationDetails: nil)
        let withUnsupported = VerificationOutcome.partialSummary(
            gatingDecision: deepThink, claims: [supported, unsupported, unchecked])
        XCTAssertEqual(
            withUnsupported,
            "1 of 3 claims are supported by your documents. One check of the whole answer did not pass: "
                + "the answer as a whole reads far from its passages. "
                + "Not found in your documents: \u{201C}Probiotics cure canine anxiety.\u{201D}.")
        // Partial from the claims alone keeps the copy it had.
        XCTAssertEqual(
            VerificationOutcome.partialSummary(gatingDecision: "verified:87%", claims: [partial]),
            "Some parts of this answer are well-supported by your documents, but not all claims could be verified.")
    }

    private static func claim(_ verdict: StructuredAnswer.Claim.VerificationVerdict?) -> StructuredAnswer.Claim {
        StructuredAnswer.Claim(
            claim: "A claim.", evidenceIds: [], confidence: 0.5, isExtracted: false, verificationVerdict: verdict,
            verificationDetails: nil)
    }
}

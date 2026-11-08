//
//  VerificationOutcome.swift
//  OpenIntelligence
//

import Foundation

/// What an answer's gating string says about verification, read one way for every surface that
/// labels an answer.
///
/// The message bubble and the response details each mapped a short list of failure words and called
/// everything else Verified. Standard writes `verified:NN%` when its gates pass, `unverified:<gates>`
/// when they fail and `verification_skipped` when they did not run (`RAGService`, where
/// `gatingSummary` is built). Deep Think and Maximum leave the string empty unless their source-only
/// check ran, because `VerificationGateService.verify` is called on Standard's path only. So a failed check and a check
/// that never ran both read Verified. Here an answer is `supported` only when the string says a
/// check ran and passed: the gates, or the source-only check Deep Think and Maximum run afterwards.
nonisolated enum VerificationOutcome: Equatable, Sendable {
    /// The verification gates ran and passed.
    case supported
    /// The gates ran and failed, or the answer is missing its citations.
    case notSupported
    /// Retrieval found little that matched the question.
    case lowConfidence
    /// The answer fell back to excerpts, or part of it was blocked, or Fact Check supported none of its claims and
    /// found some partly supported (`from(gatingDecision:claims:)`).
    case partial
    /// Nothing in the library matched.
    case noSources
    /// No verification ran, or the string does not say that one did.
    case notChecked

    static func from(gatingDecision: String?) -> VerificationOutcome {
        let decision = (gatingDecision ?? "").lowercased()
        guard !decision.isEmpty else { return .notChecked }

        if ["no_sources", "no_documents", "context_empty"].contains(where: { decision.contains($0) }) {
            return .noSources
        }
        // An answer is verified only when it is in the sources and it answers the question (5.8,
        // `AnswerResponsivenessJudge`). The grounding checks below cannot see the second: on 2026-11-07 "1-28. [S3]",
        // a page range copied from the paper, was the source-only check's supported answer to "How much DHA is
        // recommended?". The judge's `answers:` token is appended last and describes the text shown.
        if decision.contains("answers:none") {
            return .notSupported
        }
        var outcome = groundingOutcome(decision)
        // Standard runs the source-only check after its gates fail, so its string holds the gates' `unverified:` for
        // the answer the check replaced. A rewrite the check kept and the judge read as a full answer is the checked
        // answer shown. Without the judge's word it stays as the gates left it, which is how "1-28" read Verified
        // when this rule stood alone (reverted the same night).
        if outcome == .notSupported, decision.contains("source_only_refined"), decision.contains("answers:full"),
            !decision.contains("missing_citations")
        {
            outcome = .supported
        }
        // `answers:partial` does not lower the badge; it adds a warning where the answer is built. Measured on the
        // Mac on 2026-11-07, the judge called a third of correct terse answers partial ("220 human-human dialogs" for
        // how big a dataset is), so only its `none` is firm enough to label an answer.
        return outcome
    }

    /// What the grounding checks in the string say, before the judge's `answers:` token is read.
    private static func groundingOutcome(_ decision: String) -> VerificationOutcome {
        // "unverified" before "verified": the first contains the second. A source-only check that
        // made the answer abstain is a check that did not support it.
        let failed = ["unverified", "verification_gates_failed", "missing_citations", "source_only_abstained"]
        if failed.contains(where: { decision.contains($0) }) {
            return .notSupported
        }
        if ["low_confidence", "rerank_empty", "mmr_empty", "relevance_gate_failed"].contains(where: { decision.contains($0) }) {
            return .lowConfidence
        }
        // Excerpts with no model and no check behind them (5.7).
        if decision.contains("excerpts_only") {
            return .notChecked
        }
        if ["reliability_fallback", "high_accuracy_blocked"].contains(where: { decision.contains($0) }) {
            return .partial
        }
        // The gates passed, or the source-only check ran and kept the answer.
        if decision.contains("verified:") || decision.contains("source_only_refined") {
            return .supported
        }
        return .notChecked
    }

    /// The gates' outcome read against the claims Fact Check checked (5.7). Fact Check under an answer counts the
    /// claims it supported, and the gates can pass an answer whose every checked claim it left partial or
    /// unsupported: on 2026-10-15 an answer saying a date was not in the owner's notes showed a green Verified over
    /// "0 of 2 Verified". A passing outcome with no supported claim is partial when any claim is, and not supported
    /// otherwise. An answer without checked claims reads as `from(gatingDecision:)`.
    static func from(gatingDecision: String?, claims: [StructuredAnswer.Claim]) -> VerificationOutcome {
        let outcome = from(gatingDecision: gatingDecision)
        guard outcome == .supported else { return outcome }
        let verdicts = claims.compactMap(\.verificationVerdict)
        guard !verdicts.isEmpty, !verdicts.contains(.supported) else { return outcome }
        return verdicts.contains(.partial) ? .partial : .notSupported
    }
}

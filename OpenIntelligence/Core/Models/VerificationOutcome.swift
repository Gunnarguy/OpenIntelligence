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
    /// The answer fell back to excerpts, or part of it was blocked.
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
        // "unverified" before "verified": the first contains the second. A source-only check that
        // made the answer abstain is a check that did not support it.
        let failed = ["unverified", "verification_gates_failed", "missing_citations", "source_only_abstained"]
        if failed.contains(where: { decision.contains($0) }) {
            return .notSupported
        }
        if ["low_confidence", "rerank_empty", "mmr_empty", "relevance_gate_failed"].contains(where: { decision.contains($0) }) {
            return .lowConfidence
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
}

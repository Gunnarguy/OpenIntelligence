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
    /// Part of the answer holds up and part does not, or could not be checked: the answer fell back to excerpts, or
    /// part of it was blocked; the gates passed and Fact Check supported none of its claims but found some partly
    /// supported; the gates passed with one that could not judge (`not_checked:`, 5.8); or only Gate E, the grounding
    /// of the whole answer, failed while Fact Check supported at least one claim (5.8). See
    /// `from(gatingDecision:claims:)`, and `partialSummary` for what the details say.
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
        // The gates passed but one could not judge the answer (5.8, `RAGService.verificationSummary`): not Verified.
        if decision.contains("not_checked:") {
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
    /// otherwise; so is a passing outcome with a gate that could not judge (`not_checked:`). An answer without checked
    /// claims reads as `from(gatingDecision:)`.
    ///
    /// One failure is lifted (5.8, 2026-11-18): when the only gate that failed is Gate E and Fact Check supported at
    /// least one claim, the answer reads partial, not Unverified. On the owner's iPhone on 2026-11-18 a Deep Think answer
    /// showed a red Unverified under "5 of 6 Verified" because Gate E alone failed. Gate E is the one gate that judges
    /// the whole answer's grounding against the passages, which Fact Check judges claim by claim; Gates A and I never
    /// read the answer (A scores retrieval, I the passages' subjects), and B, C, D, F, G and H find a defect in the answer
    /// itself, so a failure of any of them stays not supported. So do an answer the judge found does not answer the
    /// question, missing citations, a source-only check that abstained and Standard's refusal. The claims never raise an
    /// answer to Verified; `partialSummary` names what did not pass, and the claims Fact Check did not support.
    static func from(gatingDecision: String?, claims: [StructuredAnswer.Claim]) -> VerificationOutcome {
        let outcome = from(gatingDecision: gatingDecision)
        let verdicts = claims.compactMap(\.verificationVerdict)
        if outcome == .notSupported, verdicts.contains(.supported), onlyGroundingFailed(gatingDecision) {
            return .partial
        }
        let passedButUnchecked = outcome == .partial && (gatingDecision ?? "").lowercased().contains("not_checked:")
        guard outcome == .supported || passedButUnchecked else { return outcome }
        guard !verdicts.isEmpty, !verdicts.contains(.supported) else { return outcome }
        return verdicts.contains(.partial) ? .partial : .notSupported
    }

    /// Gate E is the only gate the string says failed, over the answer shown, and the string records none of the
    /// failures a supported claim cannot answer for. `verification_gates_failed` is Standard's refusal in place of the
    /// answer (`ConversationMemoryService.refusalDecisionPrefix`).
    private static func onlyGroundingFailed(_ gatingDecision: String?) -> Bool {
        guard let gatingDecision else { return false }
        let decision = gatingDecision.lowercased()
        guard decision.contains("unverified:"), !decision.contains("verification_gates_failed"),
            !["answers:none", "missing_citations", "source_only_abstained"].contains(where: { decision.contains($0) })
        else { return false }
        let failed = gateNames(after: "unverified:", in: gatingDecision)
        return !failed.isEmpty && failed.allSatisfy { $0.hasPrefix("Gate E") }
    }

    /// The gate names a token lists, joined by `+` up to the next `,` (`RAGService.verificationSummary`).
    private static func gateNames(after token: String, in gatingDecision: String?) -> [String] {
        guard let decision = gatingDecision, let start = decision.range(of: token) else { return [] }
        let listed = decision[start.upperBound...].prefix { $0 != "," }
        return listed.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The whole-answer checks the string says failed, in plain words, in the order the gates ran.
    static func failedChecks(in gatingDecision: String?) -> [String] {
        gateNames(after: "unverified:", in: gatingDecision).map { name in
            plainCheckNames.first { name.hasPrefix($0.gate) }?.plain ?? name
        }
    }

    /// The checks the string says could not judge the answer (`not_checked:`, 5.8), in plain words.
    static func uncheckedChecks(in gatingDecision: String?) -> [String] {
        gateNames(after: "not_checked:", in: gatingDecision).map { name in
            plainUncheckedNames.first { name.hasPrefix($0.gate) }?.plain ?? name
        }
    }

    /// What a partial answer got right and what did not check out, for the response details (5.8, 2026-11-18): Fact
    /// Check's count as Fact Check shows it (supported of all claims, `GroundedAnswerView.factCheckSummary`), the
    /// whole-answer checks that failed or could not run, in plain words, and the claims Fact Check did not support.
    /// Before, a failed Gate E over mostly supported claims read "Could Not Verify" beside "5 of 6 Verified".
    static func partialSummary(gatingDecision: String?, claims: [StructuredAnswer.Claim]) -> String {
        let checked = claims.filter { $0.verificationVerdict != nil }
        let supported = checked.filter { $0.verificationVerdict == .supported }.count
        let failed = failedChecks(in: gatingDecision)
        let unchecked = uncheckedChecks(in: gatingDecision)
        guard !failed.isEmpty || !unchecked.isEmpty else {
            return "Some parts of this answer are well-supported by your documents, but not all claims could be verified."
        }
        var parts: [String] = []
        if !checked.isEmpty { parts.append("\(supported) of \(claims.count) claims are supported by your documents.") }
        if !failed.isEmpty {
            let checks = failed.count == 1 ? "One check of the whole answer" : "\(failed.count) checks of the whole answer"
            parts.append("\(checks) did not pass: " + failed.joined(separator: "; ") + ".")
        }
        if !unchecked.isEmpty {
            let checks = unchecked.count == 1 ? "One check could not run" : "\(unchecked.count) checks could not run"
            parts.append("\(checks): " + unchecked.joined(separator: "; ") + ".")
        }
        let unsupported = claims.filter { $0.verificationVerdict == .unsupported }.map { "\u{201C}\(quoted($0.claim))\u{201D}" }
        if !unsupported.isEmpty {
            parts.append("Not found in your documents: " + unsupported.joined(separator: "; ") + ".")
        }
        return parts.joined(separator: " ")
    }

    /// A claim short enough to name in a sentence.
    private static func quoted(_ claim: String) -> String {
        let trimmed = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        return String(trimmed.prefix(117)).trimmingCharacters(in: .whitespaces) + "..."
    }

    /// What a gate that could not judge leaves unmeasured, in plain words (5.8).
    private static let plainUncheckedNames: [(gate: String, plain: String)] = [
        ("Gate E", "how close the whole answer sits to its passages, because this library's search index was made by an older model and is being rebuilt")
    ]

    /// Each gate's name as `VerificationGate` writes it, and what its failure means in plain words.
    private static let plainCheckNames: [(gate: String, plain: String)] = [
        ("Gate A", "the passages found match the question only weakly"),
        ("Gate B", "some sentences could not be found in the passages"),
        ("Gate C", "a number in the answer is not in the passages"),
        ("Gate D", "the passages contradict each other"),
        ("Gate E", "the answer as a whole reads far from its passages"),
        ("Gate F", "an abbreviation is spelled out differently from the passages"),
        ("Gate G", "the text came out malformed or repetitive"),
        ("Gate H", "part of the question may be left unanswered"),
        ("Gate I", "the passages come from more than one subject"),
    ]
}

//
//  RouteEvalMetrics.swift
//  OpenIntelligence
//
//  Phase 9 route-evidence gates for the PCC dynamic routing audit.
//
//  `RAGEvalMetrics` scores *answer* quality (recall, citations, abstention).
//  This file scores *route* honesty: whether the `ModelExecutionReceipt` chain
//  a run produced is internally consistent and fail-closed.
//
//  These gates are deliberately computable from receipts alone, so the same
//  scoring runs against simulator data, physical-device data, and TestFlight
//  data without modification. Producing the receipts still requires a signed
//  device — the harness makes that evidence checkable, it does not substitute
//  for it.
//

import Foundation

// MARK: - Route Invariants

/// Invariants every `ModelExecutionReceipt` must satisfy.
///
/// Each case encodes a property the routing layer already claims to guarantee
/// in `Docs/RELEASE_NOTES.md` and `CHANGELOG.md`. A violation means either the
/// routing layer regressed or the claim was never true on that platform.
enum RouteInvariant: String, Codable, Sendable, CaseIterable {

    /// A receipt may only claim an execution target that actually succeeded.
    ///
    /// If `completedTarget` is `.onDevice` or `.privateCloudCompute`, the
    /// attempt chain must contain a `.succeeded` attempt with that same target.
    /// Without this, a receipt can report a route that never ran.
    case completedTargetAttested

    /// Divergence between intent and outcome must be explained.
    ///
    /// If `intendedTarget != completedTarget`, `fallbackReason` must be set.
    case fallbackAttributed

    /// A fallback reason may not be attached to a route that did not diverge.
    ///
    /// If `intendedTarget == completedTarget`, `fallbackReason` must be `nil`.
    case fallbackReasonRequiresDivergence

    /// Quota states that do not authorize cloud execution must block it.
    ///
    /// `.limitReached`, `.unsupported`, and `.unknown` are all fail-closed
    /// states. None of them may be accompanied by a PCC attempt.
    case quotaFailClosed

    /// A non-abstaining receipt must record how the answer was produced.
    case attemptChainPresent

    /// The attempted route must appear in the attempt chain.
    ///
    /// `actualTarget` records the route that was *attempted* (which may differ
    /// from `completedTarget` when a fallback completed the answer), so it must
    /// be present among the attempts.
    case actualTargetAttempted

    /// Human-readable statement of what the invariant guarantees.
    var summary: String {
        switch self {
        case .completedTargetAttested:
            "Completed route is backed by a succeeded attempt on that route"
        case .fallbackAttributed:
            "Intent/outcome divergence carries a fallback reason"
        case .fallbackReasonRequiresDivergence:
            "No fallback reason without divergence"
        case .quotaFailClosed:
            "Non-authorizing quota states block PCC attempts"
        case .attemptChainPresent:
            "Non-abstaining receipts record an attempt chain"
        case .actualTargetAttempted:
            "Attempted route appears in the attempt chain"
        }
    }

    /// Whether a violation blocks promotion.
    ///
    /// All current invariants are blocking: each one, if violated, makes the
    /// route telemetry actively misleading rather than merely incomplete.
    var isBlocking: Bool { true }
}

// MARK: - Violation

/// A single invariant violation found in one receipt.
struct RouteEvalViolation: Codable, Sendable, Equatable, Identifiable {

    /// Stable identity for reporting (`receiptID` + invariant).
    var id: String { "\(receiptID.uuidString):\(invariant.rawValue)" }

    /// The receipt that failed the check.
    let receiptID: UUID

    /// The invariant that failed.
    let invariant: RouteInvariant

    /// Concrete detail naming the observed values, for triage.
    let detail: String
}

// MARK: - Receipt Scoring

extension ModelExecutionReceipt {

    /// Check this receipt against every route invariant.
    ///
    /// - Returns: All violations found. Empty means the receipt is coherent.
    func routeViolations() -> [RouteEvalViolation] {
        var violations: [RouteEvalViolation] = []

        func record(_ invariant: RouteInvariant, _ detail: String) {
            violations.append(
                RouteEvalViolation(receiptID: id, invariant: invariant, detail: detail)
            )
        }

        let attemptedTargets = attempts.map(\.target)
        let succeededTargets = attempts.filter { $0.result == .succeeded }.map(\.target)

        // RI-1: the completed route must have actually succeeded.
        if completedTarget == .onDevice || completedTarget == .privateCloudCompute {
            if !succeededTargets.contains(completedTarget) {
                record(
                    .completedTargetAttested,
                    "completedTarget=\(completedTarget.rawValue) has no succeeded attempt "
                        + "(attempts: \(attemptDescription))"
                )
            }
        }

        // RI-2 / RI-3: divergence and fallback reason must agree.
        if intendedTarget != completedTarget, fallbackReason == nil {
            record(
                .fallbackAttributed,
                "intended=\(intendedTarget.rawValue) completed=\(completedTarget.rawValue) "
                    + "but fallbackReason is nil"
            )
        }
        if intendedTarget == completedTarget, let fallbackReason {
            record(
                .fallbackReasonRequiresDivergence,
                "intended==completed==\(completedTarget.rawValue) "
                    + "but fallbackReason=\(fallbackReason.rawValue)"
            )
        }

        // RI-4: fail-closed quota states must not be paired with a PCC attempt.
        if Self.nonAuthorizingQuotaStates.contains(pccQuotaAtPlanning),
           attemptedTargets.contains(.privateCloudCompute) {
            record(
                .quotaFailClosed,
                "quotaAtPlanning=\(pccQuotaAtPlanning.rawValue) does not authorize cloud "
                    + "execution, but a PCC attempt was recorded"
            )
        }

        // RI-5: a real answer must record how it was produced.
        if attempts.isEmpty, completedTarget != .abstain {
            record(
                .attemptChainPresent,
                "completedTarget=\(completedTarget.rawValue) with an empty attempt chain"
            )
        }

        // RI-6: the attempted route must appear in the chain.
        if !attempts.isEmpty, !attemptedTargets.contains(actualTarget) {
            record(
                .actualTargetAttempted,
                "actualTarget=\(actualTarget.rawValue) absent from attempts "
                    + "(\(attemptDescription))"
            )
        }

        return violations
    }

    /// Quota states that must never authorize cloud execution.
    ///
    /// `.unknown` is included deliberately: unrecognized SDK quota values map to
    /// `.unknown` and must fail closed rather than optimistically allow PCC.
    static var nonAuthorizingQuotaStates: Set<PCCQuotaState> {
        [.limitReached, .unsupported, .unknown]
    }

    /// Compact rendering of the attempt chain for violation messages.
    private var attemptDescription: String {
        guard !attempts.isEmpty else { return "none" }
        return attempts
            .map { "\($0.target.rawValue):\($0.result.rawValue)" }
            .joined(separator: " → ")
    }

    /// Wall-clock duration of the attempt that completed this receipt, if recorded.
    var completedAttemptDuration: TimeInterval? {
        attempts
            .last { $0.target == completedTarget && $0.result == .succeeded }
            .map { $0.finishedAt.timeIntervalSince($0.startedAt) }
    }
}

// MARK: - Aggregate Route Metrics

/// Aggregate route-evidence metrics across an evaluation run.
///
/// Promotion gates (Phase 9):
///
/// | Gate                       | Target |
/// |:---------------------------|:-------|
/// | Receipt integrity rate     | = 1.00 |
/// | Unauthorized cloud attempts| = 0    |
/// | Unattested completions     | = 0    |
/// | Unexplained fallbacks      | = 0    |
struct RouteEvalMetrics: Codable, Sendable {

    // -- Volume --

    /// Total receipts scored.
    let totalReceipts: Int

    /// Receipts with zero violations.
    let coherentReceipts: Int

    // -- Violations --

    /// Every violation found, retained for reporting and triage.
    let violations: [RouteEvalViolation]

    /// Violation counts keyed by invariant raw value.
    let violationsByInvariant: [String: Int]

    // -- Route distribution --

    /// How many receipts completed on each target.
    let completionsByTarget: [String: Int]

    /// Receipts that intended PCC but completed on-device.
    let pccToLocalFallbacks: Int

    /// Fallback reason counts keyed by raw value.
    let fallbackReasons: [String: Int]

    // -- Latency --

    /// Mean duration of the completing attempt, in seconds, by target.
    let meanCompletionSecondsByTarget: [String: Double]

    // MARK: Derived

    /// Fraction of receipts with no violations.
    var receiptIntegrityRate: Double {
        guard totalReceipts > 0 else { return 0 }
        return Double(coherentReceipts) / Double(totalReceipts)
    }

    /// Count of fail-closed quota violations — cloud attempted without authorization.
    var unauthorizedCloudAttempts: Int {
        violationsByInvariant[RouteInvariant.quotaFailClosed.rawValue] ?? 0
    }

    /// Count of receipts claiming a route that never succeeded.
    var unattestedCompletions: Int {
        violationsByInvariant[RouteInvariant.completedTargetAttested.rawValue] ?? 0
    }

    /// Count of route divergences with no stated reason.
    var unexplainedFallbacks: Int {
        violationsByInvariant[RouteInvariant.fallbackAttributed.rawValue] ?? 0
    }

    /// Whether this run satisfies every Phase 9 route gate.
    ///
    /// An empty run does not pass: absence of receipts is absence of evidence.
    var meetsRouteGates: Bool {
        totalReceipts > 0
            && receiptIntegrityRate >= 1.0
            && unauthorizedCloudAttempts == 0
            && unattestedCompletions == 0
            && unexplainedFallbacks == 0
    }

    /// Individual gate results for reporting, mirroring `RAGEvalMetrics.gateResults`.
    var gateResults: [(name: String, target: String, actual: String, passed: Bool)] {
        [
            (
                "Receipt integrity rate", "= 1.000",
                String(format: "%.3f", receiptIntegrityRate),
                totalReceipts > 0 && receiptIntegrityRate >= 1.0
            ),
            (
                "Unauthorized cloud attempts", "= 0",
                String(unauthorizedCloudAttempts), unauthorizedCloudAttempts == 0
            ),
            (
                "Unattested completions", "= 0",
                String(unattestedCompletions), unattestedCompletions == 0
            ),
            (
                "Unexplained fallbacks", "= 0",
                String(unexplainedFallbacks), unexplainedFallbacks == 0
            ),
            (
                "Receipts scored", "≥ 1",
                String(totalReceipts), totalReceipts > 0
            ),
        ]
    }
}

// MARK: - Computation

extension RouteEvalMetrics {

    /// Score a batch of receipts against every route invariant.
    static func compute(from receipts: [ModelExecutionReceipt]) -> RouteEvalMetrics {
        guard !receipts.isEmpty else { return .empty }

        var allViolations: [RouteEvalViolation] = []
        var byInvariant: [String: Int] = [:]
        var completions: [String: Int] = [:]
        var reasons: [String: Int] = [:]
        var durations: [String: [TimeInterval]] = [:]
        var coherent = 0
        var pccToLocal = 0

        for receipt in receipts {
            let violations = receipt.routeViolations()
            if violations.isEmpty { coherent += 1 }
            allViolations.append(contentsOf: violations)
            for violation in violations {
                byInvariant[violation.invariant.rawValue, default: 0] += 1
            }

            completions[receipt.completedTarget.rawValue, default: 0] += 1

            if let reason = receipt.fallbackReason {
                reasons[reason.rawValue, default: 0] += 1
            }

            if receipt.intendedTarget == .privateCloudCompute,
               receipt.completedTarget == .onDevice {
                pccToLocal += 1
            }

            if let duration = receipt.completedAttemptDuration {
                durations[receipt.completedTarget.rawValue, default: []].append(duration)
            }
        }

        let meanByTarget = durations.mapValues { samples in
            samples.reduce(0, +) / Double(samples.count)
        }

        return RouteEvalMetrics(
            totalReceipts: receipts.count,
            coherentReceipts: coherent,
            violations: allViolations,
            violationsByInvariant: byInvariant,
            completionsByTarget: completions,
            pccToLocalFallbacks: pccToLocal,
            fallbackReasons: reasons,
            meanCompletionSecondsByTarget: meanByTarget
        )
    }

    /// Empty metrics (no receipts scored).
    static let empty = RouteEvalMetrics(
        totalReceipts: 0,
        coherentReceipts: 0,
        violations: [],
        violationsByInvariant: [:],
        completionsByTarget: [:],
        pccToLocalFallbacks: 0,
        fallbackReasons: [:],
        meanCompletionSecondsByTarget: [:]
    )
}

// MARK: - Reporting

extension RouteEvalMetrics {

    /// Markdown summary suitable for pasting into an evidence bundle.
    var markdownSummary: String {
        var lines: [String] = []
        lines.append("## Route Evidence Gates (Phase 9)")
        lines.append("")
        lines.append("| Gate | Target | Actual | Result |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for gate in gateResults {
            lines.append(
                "| \(gate.name) | \(gate.target) | \(gate.actual) | \(gate.passed ? "PASS" : "FAIL") |"
            )
        }
        lines.append("")
        lines.append("Receipts scored: \(totalReceipts) · coherent: \(coherentReceipts)")

        if !completionsByTarget.isEmpty {
            let distribution = completionsByTarget
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            lines.append("Completed by route: \(distribution)")
        }

        if pccToLocalFallbacks > 0 {
            lines.append("PCC → on-device fallbacks: \(pccToLocalFallbacks)")
        }

        if !fallbackReasons.isEmpty {
            let reasons = fallbackReasons
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            lines.append("Fallback reasons: \(reasons)")
        }

        if !violations.isEmpty {
            lines.append("")
            lines.append("### Violations")
            lines.append("")
            for violation in violations {
                lines.append("- **\(violation.invariant.rawValue)** — \(violation.detail)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

//
//  RouteEvalMetricsTests.swift
//  OpenIntelligenceTests
//
//  Pins the Phase 9 route-evidence gates. Each test builds a receipt that
//  either satisfies or deliberately breaks one invariant, so a regression in
//  `RouteEvalMetrics` surfaces as a named failure rather than a rate drift.
//

import XCTest
@testable import OpenIntelligence

final class RouteEvalMetricsTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed reference instant so durations are deterministic.
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func attempt(
        _ target: ModelExecutionTarget,
        _ result: ModelExecutionAttemptResult,
        seconds: TimeInterval = 1,
        failureCode: String? = nil
    ) -> ModelExecutionAttempt {
        ModelExecutionAttempt(
            target: target,
            startedAt: start,
            finishedAt: start.addingTimeInterval(seconds),
            result: result,
            failureCode: failureCode
        )
    }

    private func receipt(
        intended: ModelExecutionTarget,
        attempts: [ModelExecutionAttempt],
        actual: ModelExecutionTarget,
        completed: ModelExecutionTarget,
        fallbackReason: ModelRouteReason? = nil,
        quota: PCCQuotaState = .belowLimit
    ) -> ModelExecutionReceipt {
        ModelExecutionReceipt(
            planID: UUID(),
            policyVersion: "test-policy",
            intendedTarget: intended,
            attempts: attempts,
            actualTarget: actual,
            completedTarget: completed,
            fallbackReason: fallbackReason,
            pccQuotaAtPlanning: quota
        )
    }

    /// A clean on-device answer: intent, attempt, and completion all agree.
    private var cleanLocalReceipt: ModelExecutionReceipt {
        receipt(
            intended: .onDevice,
            attempts: [attempt(.onDevice, .succeeded)],
            actual: .onDevice,
            completed: .onDevice
        )
    }

    // MARK: - Coherent Receipts

    func testCleanLocalReceiptHasNoViolations() {
        XCTAssertTrue(cleanLocalReceipt.routeViolations().isEmpty)
    }

    func testCleanPCCReceiptHasNoViolations() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .succeeded)],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute
        )
        XCTAssertTrue(receipt.routeViolations().isEmpty)
    }

    /// The documented PCC-failure path: PCC attempted, failed, on-device completed.
    func testPCCToLocalFallbackChainIsCoherent() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [
                attempt(.privateCloudCompute, .failed, failureCode: "pcc_quota"),
                attempt(.onDevice, .succeeded),
            ],
            actual: .privateCloudCompute,
            completed: .onDevice,
            fallbackReason: .pccQuotaReached
        )
        XCTAssertTrue(receipt.routeViolations().isEmpty, "documented fallback chain must score clean")
    }

    func testAbstentionWithoutAttemptsIsCoherent() {
        let receipt = receipt(
            intended: .abstain,
            attempts: [],
            actual: .abstain,
            completed: .abstain
        )
        XCTAssertTrue(receipt.routeViolations().isEmpty)
    }

    // MARK: - RI-1 Completed Target Attested

    func testCompletedTargetWithOnlyFailedAttemptViolates() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .failed, failureCode: "pcc_generation")],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.completedTargetAttested), ".failed must never attest a completion")
    }

    /// The F-06 partial-stream shape: meaningful output streamed, then the
    /// attempt died. The delivered text came from that target, so `.partial`
    /// attests the completion — coherent, and counted separately.
    func testPartialStreamCompletionAttests() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .partial, failureCode: "partial_stream")],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute
        )
        XCTAssertTrue(receipt.routeViolations().isEmpty, "a partial stream is a coherent completion")
        XCTAssertTrue(receipt.completedViaPartialStream)

        let metrics = RouteEvalMetrics.compute(from: [receipt, cleanLocalReceipt])
        XCTAssertEqual(metrics.partialCompletions, 1)
        XCTAssertTrue(metrics.meetsRouteGates, "partial completions are tracked, not punished")
        XCTAssertTrue(metrics.markdownSummary.contains("Partial-stream completions: 1"))
    }

    /// `.partial` on a different target must not attest the completed one.
    func testPartialOnOtherTargetDoesNotAttest() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .partial, failureCode: "partial_stream")],
            actual: .privateCloudCompute,
            completed: .onDevice,
            fallbackReason: .fallback
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.completedTargetAttested))
    }

    func testCompletionAttributedToUnattemptedRouteViolates() {
        let receipt = receipt(
            intended: .onDevice,
            attempts: [attempt(.onDevice, .succeeded)],
            actual: .onDevice,
            completed: .privateCloudCompute,
            fallbackReason: .fallback
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(
            invariants.contains(.completedTargetAttested),
            "claiming PCC completion with only a local attempt must be caught"
        )
    }

    // MARK: - RI-2 / RI-3 Fallback Attribution

    func testDivergenceWithoutFallbackReasonViolates() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [
                attempt(.privateCloudCompute, .failed),
                attempt(.onDevice, .succeeded),
            ],
            actual: .privateCloudCompute,
            completed: .onDevice,
            fallbackReason: nil
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.fallbackAttributed))
    }

    func testFallbackReasonWithoutDivergenceViolates() {
        let receipt = receipt(
            intended: .onDevice,
            attempts: [attempt(.onDevice, .succeeded)],
            actual: .onDevice,
            completed: .onDevice,
            fallbackReason: .pccUnavailable
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.fallbackReasonRequiresDivergence))
    }

    // MARK: - RI-4 Quota Fail-Closed

    func testPCCAttemptUnderLimitReachedViolates() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .succeeded)],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute,
            quota: .limitReached
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.quotaFailClosed))
    }

    /// Unknown quota must fail closed — an unrecognized SDK state is not permission.
    func testPCCAttemptUnderUnknownQuotaViolates() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .succeeded)],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute,
            quota: .unknown
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.quotaFailClosed))
    }

    func testApproachingLimitStillAuthorizesPCC() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .succeeded)],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute,
            quota: .approachingLimit
        )
        XCTAssertTrue(receipt.routeViolations().isEmpty)
    }

    func testLimitReachedWithoutPCCAttemptIsCoherent() {
        let receipt = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.onDevice, .succeeded)],
            actual: .onDevice,
            completed: .onDevice,
            fallbackReason: .pccQuotaReached,
            quota: .limitReached
        )
        XCTAssertTrue(receipt.routeViolations().isEmpty, "planner-time quota block is the correct behavior")
    }

    // MARK: - RI-5 / RI-6 Chain Integrity

    func testNonAbstainingReceiptWithEmptyChainViolates() {
        let receipt = receipt(
            intended: .onDevice,
            attempts: [],
            actual: .onDevice,
            completed: .onDevice
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.attemptChainPresent))
    }

    func testActualTargetAbsentFromChainViolates() {
        let receipt = receipt(
            intended: .onDevice,
            attempts: [attempt(.onDevice, .succeeded)],
            actual: .privateCloudCompute,
            completed: .onDevice
        )
        let invariants = receipt.routeViolations().map(\.invariant)
        XCTAssertTrue(invariants.contains(.actualTargetAttempted))
    }

    // MARK: - Aggregate Metrics

    func testEmptyRunDoesNotPassGates() {
        let metrics = RouteEvalMetrics.compute(from: [])
        XCTAssertEqual(metrics.totalReceipts, 0)
        XCTAssertFalse(metrics.meetsRouteGates, "absence of receipts is not evidence of correctness")
    }

    func testAllCleanReceiptsPassGates() {
        let metrics = RouteEvalMetrics.compute(from: [cleanLocalReceipt, cleanLocalReceipt])
        XCTAssertEqual(metrics.totalReceipts, 2)
        XCTAssertEqual(metrics.coherentReceipts, 2)
        XCTAssertEqual(metrics.receiptIntegrityRate, 1.0, accuracy: 0.0001)
        XCTAssertTrue(metrics.meetsRouteGates)
    }

    func testSingleViolationFailsGates() {
        let bad = receipt(
            intended: .privateCloudCompute,
            attempts: [attempt(.privateCloudCompute, .succeeded)],
            actual: .privateCloudCompute,
            completed: .privateCloudCompute,
            quota: .limitReached
        )
        let metrics = RouteEvalMetrics.compute(from: [cleanLocalReceipt, bad])

        XCTAssertEqual(metrics.totalReceipts, 2)
        XCTAssertEqual(metrics.coherentReceipts, 1)
        XCTAssertEqual(metrics.unauthorizedCloudAttempts, 1)
        XCTAssertFalse(metrics.meetsRouteGates)
    }

    func testFallbackAccountingIsReported() {
        let fallback = receipt(
            intended: .privateCloudCompute,
            attempts: [
                attempt(.privateCloudCompute, .failed, failureCode: "pcc_generation"),
                attempt(.onDevice, .succeeded),
            ],
            actual: .privateCloudCompute,
            completed: .onDevice,
            fallbackReason: .fallback
        )
        let metrics = RouteEvalMetrics.compute(from: [fallback, cleanLocalReceipt])

        XCTAssertEqual(metrics.pccToLocalFallbacks, 1)
        XCTAssertEqual(metrics.fallbackReasons[ModelRouteReason.fallback.rawValue], 1)
        XCTAssertEqual(metrics.completionsByTarget[ModelExecutionTarget.onDevice.rawValue], 2)
        XCTAssertTrue(metrics.meetsRouteGates, "a clean fallback is correct behavior, not a gate failure")
    }

    func testCompletionLatencyUsesCompletingAttempt() {
        let slow = receipt(
            intended: .onDevice,
            attempts: [attempt(.onDevice, .succeeded, seconds: 3)],
            actual: .onDevice,
            completed: .onDevice
        )
        let metrics = RouteEvalMetrics.compute(from: [slow])
        let mean = metrics.meanCompletionSecondsByTarget[ModelExecutionTarget.onDevice.rawValue]
        XCTAssertEqual(try XCTUnwrap(mean), 3.0, accuracy: 0.0001)
    }

    func testMarkdownSummaryListsViolations() {
        let bad = receipt(
            intended: .onDevice,
            attempts: [],
            actual: .onDevice,
            completed: .onDevice
        )
        let summary = RouteEvalMetrics.compute(from: [bad]).markdownSummary

        XCTAssertTrue(summary.contains("Route Evidence Gates"))
        XCTAssertTrue(summary.contains(RouteInvariant.attemptChainPresent.rawValue))
        XCTAssertTrue(summary.contains("FAIL"))
    }
}

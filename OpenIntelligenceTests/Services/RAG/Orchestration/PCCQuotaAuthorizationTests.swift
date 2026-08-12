//
//  PCCQuotaAuthorizationTests.swift
//  OpenIntelligenceTests
//
//  Pins the one rule that decides whether a cloud attempt is allowed, and pins that the planner and
//  the route-gate scorer read the same copy of it.
//
//  Why this exists. `RouteEvalMetrics.RouteInvariant.quotaFailClosed` declares the contract in its
//  own doc comment: "`.limitReached`, `.unsupported`, and `.unknown` are all fail-closed states.
//  None of them may be accompanied by a PCC attempt." The planner did not implement it.
//  `FoundationModelCapabilitySnapshot.canUsePCC` tested only `pccQuota != .limitReached`, so
//  `.unknown` permitted a cloud attempt that this project's own scorer would then count as an
//  `unauthorizedCloudAttempts` violation.
//
//  That is reachable in production rather than only in tests. `FoundationModelCapabilityProvider`
//  maps `pcc.quotaUsage.status` through an `@unknown default`, so any status a future SDK adds
//  becomes `.unknown` while `hasPCCEntitlement` and `pccAvailable` are both true. The planner was
//  fail-open on precisely the state the gate was written to catch, and the first real route-gate run
//  would have reported it, correctly.
//
//  Found on 2026-08-11 by reconciling the v5.0 roadmap against the code, not by a failing test.
//  There was no test on this path at all.
//

@testable import OpenIntelligence
import XCTest

final class PCCQuotaAuthorizationTests: XCTestCase {
    // MARK: - The rule itself

    /// Only the two states that actually mean "quota remains" authorize a cloud attempt.
    func testOnlyBelowAndApproachingLimitAuthorizeCloud() {
        XCTAssertTrue(PCCQuotaState.belowLimit.authorizesCloudExecution)
        XCTAssertTrue(PCCQuotaState.approachingLimit.authorizesCloudExecution)

        XCTAssertFalse(PCCQuotaState.limitReached.authorizesCloudExecution)
        XCTAssertFalse(
            PCCQuotaState.unsupported.authorizesCloudExecution,
            "PCC is not supported here, so nothing may attempt it."
        )
        XCTAssertFalse(
            PCCQuotaState.unknown.authorizesCloudExecution,
            "An unrecognised SDK quota status must route on-device rather than gamble a cloud call. This is the assertion the planner was failing."
        )
    }

    /// Every state is classified, so adding one cannot silently default to permitted.
    func testEveryQuotaStateIsClassified() {
        XCTAssertEqual(
            PCCQuotaState.allCases.count, 5,
            "A quota state was added or removed. Decide explicitly which side of authorizesCloudExecution it falls on, and check ModelExecutionReceipt.nonAuthorizingQuotaStates still reads the derived set."
        )
    }

    // MARK: - The planner and the scorer must agree

    /// The scorer's non-authorizing set is exactly the complement of what the planner permits.
    ///
    /// These were two hardcoded copies of one rule and they had already diverged. The set is derived
    /// now, so this asserts the derivation rather than a coincidence.
    func testScorerAndPlannerShareOneRule() {
        let nonAuthorizing = ModelExecutionReceipt.nonAuthorizingQuotaStates

        for state in PCCQuotaState.allCases {
            XCTAssertEqual(
                nonAuthorizing.contains(state), !state.authorizesCloudExecution,
                "\(state.rawValue) is classified differently by the planner and the route gate, which is the defect this file exists for."
            )
        }

        XCTAssertEqual(
            nonAuthorizing, Set<PCCQuotaState>([.limitReached, .unsupported, .unknown]),
            "The fail-closed set changed. RouteEvalMetrics.RouteInvariant.quotaFailClosed documents these three by name; update that contract deliberately if this is intended."
        )
    }

    // MARK: - The composite gate

    /// `canUsePCC` refuses a cloud attempt on an unrecognised quota even when everything else is fine.
    ///
    /// This is the exact snapshot shape `FoundationModelCapabilityProvider` produces from its
    /// `@unknown default`: entitled, available, and carrying a quota nobody mapped.
    func testCanUsePCCFailsClosedOnUnknownQuota() {
        let entitledAndAvailableButUnknownQuota = FoundationModelCapabilitySnapshot(
            supportsOnDevice: true,
            onDeviceAvailable: true,
            onDeviceContextSize: 4096,
            supportsPCC: true,
            hasPCCEntitlement: true,
            pccAvailable: true,
            pccQuota: .unknown,
            pccContextSize: 4096,
            source: .sdkExact,
            unavailabilityReason: nil
        )

        XCTAssertFalse(
            entitledAndAvailableButUnknownQuota.canUsePCC,
            "Entitled and available with an unmapped quota status must not authorize PCC. Before this fix canUsePCC returned true here, and RouteEvalMetrics would have scored the resulting attempt as unauthorized."
        )
    }

    /// The healthy case still works, so the fix is not simply disabling PCC.
    func testCanUsePCCStillAllowsAHealthyCloudRoute() {
        for quota in [PCCQuotaState.belowLimit, .approachingLimit] {
            let healthy = FoundationModelCapabilitySnapshot(
                supportsOnDevice: true,
                onDeviceAvailable: true,
                onDeviceContextSize: 4096,
                supportsPCC: true,
                hasPCCEntitlement: true,
                pccAvailable: true,
                pccQuota: quota,
                pccContextSize: 4096,
                source: .sdkExact,
                unavailabilityReason: nil
            )
            XCTAssertTrue(healthy.canUsePCC, "\(quota.rawValue) should still authorize PCC.")
        }
    }

    /// The other three inputs still gate independently of quota.
    func testTheOtherGatesStillApply() {
        func snapshot(
            supportsPCC: Bool = true,
            entitled: Bool = true,
            available: Bool = true
        ) -> FoundationModelCapabilitySnapshot {
            FoundationModelCapabilitySnapshot(
                supportsOnDevice: true,
                onDeviceAvailable: true,
                onDeviceContextSize: 4096,
                supportsPCC: supportsPCC,
                hasPCCEntitlement: entitled,
                pccAvailable: available,
                pccQuota: .belowLimit,
                pccContextSize: 4096,
                source: .sdkExact,
                unavailabilityReason: nil
            )
        }

        XCTAssertFalse(snapshot(supportsPCC: false).canUsePCC)
        XCTAssertFalse(snapshot(entitled: false).canUsePCC, "No signed entitlement means no cloud.")
        XCTAssertFalse(snapshot(available: false).canUsePCC)
        XCTAssertTrue(snapshot().canUsePCC)
    }
}

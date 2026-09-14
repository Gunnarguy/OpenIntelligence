import XCTest

@testable import OpenIntelligenceEngine

/// Pins the one line per generation that a TestFlight build writes to the unified log.
///
/// The line exists because a Release build wrote nothing about routing to Console.app until
/// 2026-09-14, so there was no way to observe from outside the app whether an answer came from the
/// device or from Private Cloud Compute. Its shape is tested here because the shape is the
/// contract: a reader filters Console for `subsystem == "Gunndamental.OpenIntelligence" AND
/// category == "routing"` and greps for these tokens, and a rename would silently break that
/// without failing any build.
///
/// What is deliberately NOT tested is that the line reaches the unified log on a device. Foundation
/// Models does not run in the simulator, so the generation paths that emit it never execute here;
/// that is the roadmap row's closing condition and it needs a phone.
final class RouteLogLineTests: XCTestCase {

    // MARK: - The started line

    func testStartedLine_onDevice_withNoPlan_saysDirect() {
        let line = RouteLogLine.started(actualTarget: .onDevice, reasoningLevel: nil, plan: nil)
        XCTAssertEqual(
            line.rendered,
            "route started actual=onDevice intended=direct reasoning=none plan=direct policy=none"
        )
    }

    func testStartedLine_privateCloudCompute_carriesReasoningLevel() {
        let line = RouteLogLine.started(actualTarget: .privateCloudCompute, reasoningLevel: "deep", plan: nil)
        XCTAssertEqual(
            line.rendered,
            "route started actual=privateCloudCompute intended=direct reasoning=deep plan=direct policy=none"
        )
    }

    // MARK: - The completed line

    func testCompletedLine_withNoReceipt_isOnDeviceDirect() {
        let line = RouteLogLine.completed(actualTarget: .onDevice, receipt: nil)
        XCTAssertEqual(
            line.rendered,
            "route completed actual=onDevice intended=direct fallback=none attempts=1 plan=direct policy=none"
        )
    }

    func testCompletedLine_withReceipt_namesPlanFallbackAndAttempts() {
        let planID = UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000000")!
        let receipt = ModelExecutionReceipt(
            planID: planID,
            policyVersion: "pcc-dynamic-router-v2",
            intendedTarget: .privateCloudCompute,
            attempts: [
                ModelExecutionAttempt(target: .privateCloudCompute, startedAt: Date(), result: .failed),
                ModelExecutionAttempt(target: .onDevice, startedAt: Date(), result: .succeeded),
            ],
            actualTarget: .onDevice,
            completedTarget: .onDevice,
            fallbackReason: .pccUnavailable,
            pccQuotaAtPlanning: .belowLimit
        )
        let line = RouteLogLine.completed(actualTarget: .onDevice, receipt: receipt)
        XCTAssertEqual(
            line.rendered,
            "route completed actual=onDevice intended=privateCloudCompute fallback=pccUnavailable"
                + " attempts=2 plan=1A2B3C4D policy=pcc-dynamic-router-v2"
        )
    }

    // MARK: - What the line can never carry

    /// Every token is an enum raw value, a UUID prefix, a version constant or a count. There is no
    /// parameter through which a query, a passage or an answer could arrive, so the strongest
    /// statement available is that the rendered line contains only the vocabulary below.
    func testRenderedLine_containsOnlyKnownVocabulary() {
        let planID = UUID()
        let receipt = ModelExecutionReceipt(
            planID: planID,
            policyVersion: "pcc-dynamic-router-v2",
            intendedTarget: .onDevice,
            attempts: [ModelExecutionAttempt(target: .onDevice, startedAt: Date(), result: .succeeded)],
            actualTarget: .onDevice,
            completedTarget: .onDevice,
            fallbackReason: nil,
            pccQuotaAtPlanning: .belowLimit
        )
        let allowedValues: Set<String> =
            Set(["route", "started", "completed", "direct", "none", "pcc-dynamic-router-v2"])
            .union(["onDevice", "privateCloudCompute", "deterministic", "abstain"])
            .union([String(planID.uuidString.prefix(8))])
        let lines = [
            RouteLogLine.started(actualTarget: .onDevice, reasoningLevel: nil, plan: nil),
            RouteLogLine.completed(actualTarget: .onDevice, receipt: receipt),
        ]
        for line in lines {
            for token in line.rendered.split(separator: " ") {
                let value = token.split(separator: "=", maxSplits: 1).last.map(String.init) ?? String(token)
                XCTAssertTrue(
                    allowedValues.contains(value) || Int(value) != nil,
                    "unexpected token \(token) in: \(line.rendered)"
                )
            }
        }
    }

    // MARK: - The predicate is a contract

    func testSubsystemAndCategory_areTheDocumentedPredicate() {
        XCTAssertEqual(RouteLog.subsystem, "Gunndamental.OpenIntelligence")
        XCTAssertEqual(RouteLog.category, "routing")
    }
}

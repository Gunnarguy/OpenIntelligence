import XCTest
@testable import OpenIntelligence

@MainActor
final class ModelExecutionPlannerTests: XCTestCase {
    private let localBudget = ContextBudgetSnapshot(
        contextSize: 4096,
        instructions: 400,
        tools: 0,
        schema: 0,
        history: 200,
        evidence: 1200,
        output: 512,
        reasoning: 0,
        safety: 256,
        source: .sdkExact
    )

    private let pccBudget = ContextBudgetSnapshot(
        contextSize: 32768,
        instructions: 400,
        tools: 0,
        schema: 0,
        history: 200,
        evidence: 6000,
        output: 1024,
        reasoning: 2048,
        safety: 512,
        source: .sdkExact
    )

    private func constraints(
        allowsPCC: Bool = true,
        requiresOnDevice: Bool = false,
        requiresPCC: Bool = false,
        networkAvailable: Bool = true,
        consentGranted: Bool = false,
        isForegroundInteractive: Bool = true,
        qualityMode: String = "Standard"
    ) -> PreRetrievalConstraints {
        PreRetrievalConstraints(
            allowsPCC: allowsPCC,
            requiresOnDevice: requiresOnDevice,
            requiresPCC: requiresPCC,
            networkAvailable: networkAvailable,
            consentGranted: consentGranted,
            isForegroundInteractive: isForegroundInteractive,
            qualityMode: qualityMode
        )
    }

    private func evidence(
        topScore: Float = 0.8,
        estimatedTokens: Int = 1200,
        multiDocument: Bool = false
    ) -> PostRetrievalEvidence {
        PostRetrievalEvidence(
            chunkCount: 4,
            topScore: topScore,
            meanScore: topScore - 0.1,
            estimatedEvidenceTokens: estimatedTokens,
            hasContradictions: false,
            requiresExactExtraction: false,
            requiresMultiDocumentSynthesis: multiDocument
        )
    }

    private func capability(
        available: Bool = true,
        quota: PCCQuotaState = .belowLimit
    ) -> FoundationModelCapabilitySnapshot {
        FoundationModelCapabilitySnapshot(
            supportsOnDevice: true,
            onDeviceAvailable: true,
            onDeviceContextSize: 4096,
            supportsPCC: true,
            hasPCCEntitlement: true,
            pccAvailable: available,
            pccQuota: quota,
            pccContextSize: 32768,
            source: .sdkExact,
            unavailabilityReason: nil
        )
    }

    func testLocalOnlyNeverSelectsPCC() {
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(allowsPCC: false, requiresOnDevice: true),
            evidence: evidence(),
            localBudget: localBudget,
            pccBudget: pccBudget,
            capability: capability()
        )

        XCTAssertEqual(plan.synthesisTarget, .onDevice)
        XCTAssertEqual(plan.privacyBoundary, .localOnly)
        XCTAssertFalse(plan.requiresCloudConsent)
    }

    func testDeepMultiDocumentSynthesisSelectsPCCWhenEligible() {
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(qualityMode: "Deep Think"),
            evidence: evidence(multiDocument: true),
            localBudget: localBudget,
            pccBudget: pccBudget,
            capability: capability()
        )

        XCTAssertEqual(plan.synthesisTarget, .privateCloudCompute)
        XCTAssertTrue(plan.requiresCloudConsent)
        XCTAssertEqual(plan.fallback.target, .onDevice)
    }

    func testQuotaReachedFallsBackToLocalWithoutRetry() {
        let oversizedLocalBudget = ContextBudgetSnapshot(
            contextSize: 4096,
            instructions: 600,
            tools: 1000,
            schema: 200,
            history: 800,
            evidence: 3000,
            output: 700,
            reasoning: 0,
            safety: 256,
            source: .sdkExact
        )
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(),
            evidence: evidence(estimatedTokens: 3000),
            localBudget: oversizedLocalBudget,
            pccBudget: pccBudget,
            capability: capability(quota: .limitReached)
        )

        XCTAssertEqual(plan.synthesisTarget, .onDevice)
        XCTAssertEqual(plan.stages.first(where: { $0.role == .synthesize })?.reason, .pccQuotaReached)
        XCTAssertFalse(plan.fallback.mayRetryPCC)
    }

    func testInsufficientEvidenceAbstainsInsteadOfEscalating() {
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(requiresPCC: true),
            evidence: evidence(topScore: 0.1),
            localBudget: localBudget,
            pccBudget: pccBudget,
            capability: capability()
        )

        XCTAssertEqual(plan.synthesisTarget, .abstain)
        XCTAssertEqual(plan.privacyBoundary, .pccProhibited)
    }

    func testBackgroundRequestDoesNotSelectPCCWhenConsentWouldBeRequired() {
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(
                consentGranted: false,
                isForegroundInteractive: false,
                qualityMode: "Deep Think"
            ),
            evidence: evidence(multiDocument: true),
            localBudget: localBudget,
            pccBudget: pccBudget,
            capability: capability()
        )

        XCTAssertEqual(plan.synthesisTarget, .onDevice)
        XCTAssertFalse(plan.requiresCloudConsent)
    }

    func testBackgroundRequestMayUsePCCAfterRememberedConsent() {
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(
                consentGranted: true,
                isForegroundInteractive: false,
                qualityMode: "Deep Think"
            ),
            evidence: evidence(multiDocument: true),
            localBudget: localBudget,
            pccBudget: pccBudget,
            capability: capability()
        )

        XCTAssertEqual(plan.synthesisTarget, .privateCloudCompute)
    }

    func testCloudOnlyWithDeniedPermissionAbstains() {
        let plan = ModelExecutionPlanner().makePlan(
            constraints: constraints(allowsPCC: false, requiresPCC: true),
            evidence: evidence(),
            localBudget: localBudget,
            pccBudget: pccBudget,
            capability: capability()
        )

        XCTAssertEqual(plan.synthesisTarget, .abstain)
        XCTAssertEqual(plan.privacyBoundary, .pccProhibited)
    }

    func testReceiptRoundTripKeepsIntendedAndActualTargetsSeparate() throws {
        let receipt = ModelExecutionReceipt(
            planID: UUID(),
            policyVersion: ModelExecutionPlan.policyVersion,
            intendedTarget: .privateCloudCompute,
            attempts: [
                ModelExecutionAttempt(
                    target: .privateCloudCompute,
                    startedAt: Date(),
                    result: .failed,
                    failureCode: "networkFailure"
                ),
                ModelExecutionAttempt(
                    target: .onDevice,
                    startedAt: Date(),
                    result: .succeeded
                ),
            ],
            actualTarget: .privateCloudCompute,
            completedTarget: .onDevice,
            fallbackReason: .networkUnavailable,
            pccQuotaAtPlanning: .belowLimit,
            verificationPassed: true
        )

        let decoded = try JSONDecoder().decode(
            ModelExecutionReceipt.self,
            from: JSONEncoder().encode(receipt)
        )
        XCTAssertEqual(decoded, receipt)
        XCTAssertEqual(decoded.intendedTarget, .privateCloudCompute)
        XCTAssertEqual(decoded.completedTarget, .onDevice)
    }
}

import XCTest

@testable import OpenIntelligenceEngine

/// Deep Think runs its Self-RAG check after the chain on every device (5.7). Through 5.6 the check keyed on a step budget
/// of 8 or more, which the A17 Pro's 5 never reached, so an iPhone 15 Pro skipped it.
@MainActor
final class DeepThinkSelfRAGTests: XCTestCase {
    private func config(steps: Int) -> AgenticConfig {
        AgenticConfig(
            maxSteps: steps, maxTotalTokens: 20000, streamIntermediateResults: true,
            confidenceThreshold: 0.85, escalationThreshold: 0.35)
    }

    /// The step budgets `optimizedAgenticConfig` gives each tier: 5 (A17 Pro), 8, 10, and 12 to 32.
    func testDeepThinkRunsTheCheckWhateverTheDevicesStepBudget() {
        for steps in [5, 8, 10, 12, 32] {
            XCTAssertTrue(
                AgenticOrchestrator.runsDeepThinkSelfRAG(qualityMode: .deepThink, config: config(steps: steps)),
                "\(steps) steps")
        }
    }

    func testStandardAndMaximumDoNotRunDeepThinksCheck() {
        XCTAssertFalse(AgenticOrchestrator.runsDeepThinkSelfRAG(qualityMode: .standard, config: .fast))
        XCTAssertFalse(AgenticOrchestrator.runsDeepThinkSelfRAG(qualityMode: .standard, config: config(steps: 8)))
        XCTAssertFalse(AgenticOrchestrator.runsDeepThinkSelfRAG(qualityMode: .maximum, config: .unlimited))
    }
}

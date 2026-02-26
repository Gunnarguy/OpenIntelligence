import XCTest
@testable import OpenIntelligence

final class VerificationGateServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeChunk(content: String, index: Int = 0, score: Float = 0.8) -> RetrievedChunk {
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: content,
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: index)
        )
        return RetrievedChunk(chunk: chunk, similarityScore: score, rank: index + 1)
    }

    // MARK: - Gate A: Retrieval Confidence

    func testGateA_HighScoresPass() async {
        let service = VerificationGateService(config: .default)
        let chunks = [makeChunk(content: "Answer is 42.", score: 0.85)]

        let result = await service.verify(
            response: "The answer is 42.",
            query: "what is the answer?",
            retrievedChunks: chunks,
            topScores: [0.85, 0.70, 0.55]
        )

        let gateA = result.gateResults.first { $0.gate == .retrievalConfidence }
        XCTAssertNotNil(gateA, "Gate A result should be present")
        XCTAssertTrue(gateA?.passed ?? false,
                      "Gate A should pass with score 0.85 > default tau 0.40")
    }

    func testGateA_LowScoresFail() async {
        let service = VerificationGateService(config: .strict)
        let chunks = [makeChunk(content: "Some content.", score: 0.3)]

        let result = await service.verify(
            response: "The answer is unknown.",
            query: "what is the answer?",
            retrievedChunks: chunks,
            topScores: [0.30, 0.25, 0.20]
        )

        let gateA = result.gateResults.first { $0.gate == .retrievalConfidence }
        XCTAssertNotNil(gateA)
        XCTAssertFalse(gateA?.passed ?? true,
                       "Gate A should fail with score 0.30 < strict tau 0.65")
    }

    // MARK: - Gate C: Numeric Sanity

    func testGateC_MatchingNumbersPass() async {
        let service = VerificationGateService(config: .default)
        let chunks = [makeChunk(content: "The capacity is 3.5 liters.")]

        let result = await service.verify(
            response: "The capacity is 3.5 liters.",
            query: "what is the capacity?",
            retrievedChunks: chunks,
            topScores: [0.90]
        )

        let gateC = result.gateResults.first { $0.gate == .numericSanity }
        XCTAssertNotNil(gateC)
        XCTAssertTrue(gateC?.passed ?? false,
                      "Gate C should pass when response numbers match source")
    }

    func testGateC_YearExemption() async {
        let service = VerificationGateService(config: .default)
        let chunks = [makeChunk(content: "The system was updated.")]

        let result = await service.verify(
            response: "As of 2024, the system was updated.",
            query: "when was it updated?",
            retrievedChunks: chunks,
            topScores: [0.85]
        )

        let gateC = result.gateResults.first { $0.gate == .numericSanity }
        XCTAssertNotNil(gateC)
        // Years 1900-2100 should be exempt from numeric hallucination checks
        XCTAssertTrue(gateC?.passed ?? false,
                      "Gate C should exempt years (1900-2100) from hallucination checks")
    }

    func testGateC_SmallIntegerExemption() async {
        let service = VerificationGateService(config: .default)
        let chunks = [makeChunk(content: "Follow these steps to complete the process.")]

        let result = await service.verify(
            response: "There are 3 steps to complete the process.",
            query: "how many steps?",
            retrievedChunks: chunks,
            topScores: [0.80]
        )

        let gateC = result.gateResults.first { $0.gate == .numericSanity }
        XCTAssertNotNil(gateC)
        // Small integers 1-10 should be exempt
        XCTAssertTrue(gateC?.passed ?? false,
                      "Gate C should exempt small integers (1-10)")
    }

    // MARK: - Overall Verification

    func testAllGatesPassForHighQualityResponse() async {
        let service = VerificationGateService(config: .default)
        let chunks = [
            makeChunk(content: "The recommended oil viscosity is SAE 0W-20 for optimal engine performance.", score: 0.92),
            makeChunk(content: "Always use SAE 0W-20 synthetic oil as specified by the manufacturer.", index: 1, score: 0.85)
        ]

        let result = await service.verify(
            response: "The recommended oil viscosity is SAE 0W-20.",
            query: "what oil should I use?",
            retrievedChunks: chunks,
            topScores: [0.92, 0.85]
        )

        XCTAssertTrue(result.passed, "High quality response matching sources should pass all gates")
        XCTAssertFalse(result.shouldAbstain, "Should not abstain for high quality response")
    }

    func testEmptyChunksTriggersAbstain() async {
        let service = VerificationGateService(config: .default)

        let result = await service.verify(
            response: "I found the answer.",
            query: "what is the answer?",
            retrievedChunks: [],
            topScores: []
        )

        // With no retrieved chunks, Gate A should fail (no scores)
        let gateA = result.gateResults.first { $0.gate == .retrievalConfidence }
        XCTAssertFalse(gateA?.passed ?? true, "Gate A should fail with no scores")
    }

    // MARK: - Configuration

    func testDefaultConfigHasReasonableThresholds() {
        let config = VerificationConfig.default
        XCTAssertGreaterThan(config.tauNormal, 0, "Normal tau should be positive")
        XCTAssertGreaterThan(config.tauTouchy, config.tauNormal, "Touchy tau should be stricter")
        XCTAssertGreaterThan(config.muMargin, 0, "Margin should be positive")
    }

    func testStrictConfigIsStricterThanDefault() {
        let defaultConfig = VerificationConfig.default
        let strictConfig = VerificationConfig.strict

        XCTAssertGreaterThan(strictConfig.tauNormal, defaultConfig.tauNormal,
                             "Strict tau should be higher than default")
        XCTAssertGreaterThan(strictConfig.muMargin, defaultConfig.muMargin,
                             "Strict margin should be higher than default")
    }

    // MARK: - Verification Gate Enum

    func testAllGatesAreRepresented() {
        let allGates = VerificationGate.allCases
        XCTAssertEqual(allGates.count, 5, "Should have 5 verification gates (A-E)")
        XCTAssertTrue(allGates.contains(.retrievalConfidence))
        XCTAssertTrue(allGates.contains(.evidenceCoverage))
        XCTAssertTrue(allGates.contains(.numericSanity))
        XCTAssertTrue(allGates.contains(.contradictionSweep))
        XCTAssertTrue(allGates.contains(.semanticGrounding))
    }

    // MARK: - Result Helpers

    func testFailedGatesFilterWorks() {
        // Create a mock result with some failures
        let passedGate = RAGVerificationResult.GateResult(
            gate: .retrievalConfidence, passed: true, confidence: 0.9, details: "OK"
        )
        let failedGate = RAGVerificationResult.GateResult(
            gate: .numericSanity, passed: false, confidence: 0.3, details: "Number mismatch"
        )
        let result = RAGVerificationResult(
            passed: false,
            gateResults: [passedGate, failedGate],
            overallConfidence: 0.5,
            shouldAbstain: false,
            abstainReason: nil
        )

        XCTAssertEqual(result.failedGates.count, 1)
        XCTAssertEqual(result.failedGates.first, .numericSanity)
    }
}

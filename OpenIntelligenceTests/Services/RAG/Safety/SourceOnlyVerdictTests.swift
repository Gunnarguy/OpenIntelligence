//
//  SourceOnlyVerdictTests.swift
//  OpenIntelligenceTests
//
//  5.8: `RAGService.sourceOnlyOutcomeIfNeeded` skips the source-only check, before any model call, when the check
//  would see less than the coverage floor of the answer and there is no abstention to preserve. That is only safe if
//  every outcome the model could return would keep the generated answer. These walk every combination of outcome
//  against the rules as they stood inline before 5.8 (copied below unchanged), and against the skip.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SourceOnlyVerdictTests: XCTestCase {
    /// The inline rules before 5.8, verbatim in meaning: true means the outcome replaced the answer.
    private func replacedBefore58(
        shouldAbstain: Bool, supported: Int, fidelity: Float, coverage: Double, preserve: Bool
    ) -> Bool {
        if shouldAbstain { return preserve }
        guard supported > 0 else { return preserve }
        guard fidelity >= 0.72 else { return false }
        guard coverage >= 0.85 else { return false }
        return true
    }

    private let abstains = [false, true]
    private let supportedCounts = [0, 1, 7]
    private let fidelities: [Float] = [0, 0.5, 0.7199, 0.72, 0.9, 1]
    private let coverages = [0, 0.01, 0.5, 0.8499, 0.85, 0.9, 1]
    private let preserves = [false, true]

    func testTheVerdictMatchesTheRulesBefore58ForEveryOutcome() {
        var checked = 0
        for a in abstains { for s in supportedCounts { for f in fidelities { for c in coverages { for p in preserves {
            let verdict = RAGService.sourceOnlyVerdict(
                shouldAbstain: a, supportedClaimCount: s, fidelity: f, coverage: c, preserveAbstention: p)
            XCTAssertEqual(
                verdict == .replace, replacedBefore58(shouldAbstain: a, supported: s, fidelity: f, coverage: c, preserve: p),
                "abstain \(a), supported \(s), fidelity \(f), coverage \(c), preserve \(p)")
            checked += 1
        } } } } }
        XCTAssertEqual(checked, 504)
    }

    func testBelowTheFloorWithNothingToPreserveEveryOutcomeKeepsTheAnswer() {
        // The skip's condition: coverage under the floor and no abstention to preserve.
        for a in abstains { for s in supportedCounts { for f in fidelities { for c in coverages where c < 0.85 {
            XCTAssertNotEqual(
                RAGService.sourceOnlyVerdict(
                    shouldAbstain: a, supportedClaimCount: s, fidelity: f, coverage: c, preserveAbstention: false),
                .replace, "abstain \(a), supported \(s), fidelity \(f), coverage \(c)")
        } } } }
    }

    func testWithAnAbstentionToPreserveTheCheckCanStillReplaceBelowTheFloor() {
        // Why the skip requires `!preserveAbstention`: here a model outcome below the floor does replace the answer.
        XCTAssertEqual(
            RAGService.sourceOnlyVerdict(
                shouldAbstain: true, supportedClaimCount: 0, fidelity: 0, coverage: 0.1, preserveAbstention: true),
            .replace)
    }

    func testCoverageBeforeTheModelIsBelowTheFloorForALongAnswerAndWholeForAShortOne() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let chunks = (0..<8).map { i in
            let text = String(repeating: "The boiler in flat \(i) is serviced every March by the building engineer. ", count: 12)
            return RetrievedChunk(
                chunk: DocumentChunk(
                    documentId: UUID(), content: text, embedding: [],
                    metadata: ChunkMetadata(
                        chunkIndex: i, endPosition: text.count, sectionTitle: nil, semanticDensity: 1, hasNumericData: false,
                        wordCount: text.split(separator: " ").count, characterCount: text.count)),
                similarityScore: 0.8, rank: i + 1, sourceDocument: "flat-\(i).md", pageNumber: nil)
        }
        let service = SourceOnlyAnswerService.shared
        // The coverage needs the model's window; without Apple Intelligence (a fresh Simulator) it is nil by design.
        guard service.isAvailable else { throw XCTSkip("Apple Intelligence is not available on this device") }
        let long = String(repeating: "The boiler is serviced every March by the building's own engineer, who signs the log. ", count: 80)
        let short = "The boiler is serviced every March."
        let longCoverage = try XCTUnwrap(
            service.candidateCoverageBeforeModel(
                query: "When is the boiler serviced?", candidateAnswer: long, retrievedChunks: chunks, answerIntent: .lookup))
        let shortCoverage = try XCTUnwrap(
            service.candidateCoverageBeforeModel(
                query: "When is the boiler serviced?", candidateAnswer: short, retrievedChunks: chunks, answerIntent: .lookup))
        XCTAssertLessThan(longCoverage, 0.85, "a 7,000-character answer does not fit the check's share")
        XCTAssertEqual(shortCoverage, 1, "a one-sentence answer fits whole")
    }
}

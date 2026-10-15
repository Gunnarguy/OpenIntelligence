//
//  AnswerUsageTallyTests.swift
//  OpenIntelligenceTests
//
//  An answer keeps Apple's own token count (5.7): every model call it makes adds its usage to the answer's tally
//  (`AnswerUsageTally`, set by `RAGService.query`), and the total is saved with the answer
//  (`ResponseMetadata.appleUsage`). Answers saved before 5.7 have none and still load.
//

import XCTest

@testable import OpenIntelligence

// Main actor: `ResponseMetadata`'s coding is main-actor isolated, as the app's other model types are.
@MainActor
final class AnswerUsageTallyTests: XCTestCase {
    private let first = GenerationUsage(outputTokens: 120, reasoningTokens: 0, inputTokens: 900, cachedInputTokens: 300)
    private let second = GenerationUsage(outputTokens: 80, reasoningTokens: 40, inputTokens: 1_100, cachedInputTokens: 0)

    func testUsageAddsUp() {
        XCTAssertEqual(
            first + second,
            GenerationUsage(outputTokens: 200, reasoningTokens: 40, inputTokens: 2_000, cachedInputTokens: 300))
    }

    func testTheTallyCountsOnlyInsideItsAnswer() async {
        let tally = AnswerUsageTally()
        let first = first
        let second = second
        await AnswerUsageTally.$current.withValue(tally) {
            AnswerUsageTally.current?.add(first)
            AnswerUsageTally.current?.add(nil)
            await Task { AnswerUsageTally.current?.add(second) }.value
        }
        XCTAssertEqual(tally.total, first + second, "a child task's call counts too")
        XCTAssertNil(AnswerUsageTally.current, "no tally outside an answer")
    }

    func testAnAnswerSavedBeforeTheCountStillLoads() throws {
        var metadata = ResponseMetadata(
            totalGenerationTime: 1.5, tokensGenerated: 42, modelUsed: "Apple Intelligence", retrievalTime: 0.2)
        metadata.appleUsage = first
        let saved = try JSONEncoder().encode(metadata)
        XCTAssertEqual(try JSONDecoder().decode(ResponseMetadata.self, from: saved).appleUsage, first)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object.removeValue(forKey: "appleUsage")
        let older = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(ResponseMetadata.self, from: older).appleUsage)
    }

    func testTheCopiesKeepTheCount() {
        var metadata = ResponseMetadata(
            totalGenerationTime: 1, tokensGenerated: 1, modelUsed: "Apple Intelligence", retrievalTime: 0.1)
        metadata.appleUsage = second
        XCTAssertEqual(metadata.withReasoningTrace(["a step"]).appleUsage, second)
        XCTAssertEqual(metadata.appendingGatingDecision("finished_early_by_person").appleUsage, second)
    }

    func testTheDetailsLine() {
        XCTAssertEqual(ChatResponseDetailsView.appleUsageText(first), "900 in (300 cached), 120 out")
        XCTAssertEqual(ChatResponseDetailsView.appleUsageText(second), "1,100 in (0 cached), 80 out, 40 reasoning")
    }
}

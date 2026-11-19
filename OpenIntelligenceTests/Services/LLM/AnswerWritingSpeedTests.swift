//
//  AnswerWritingSpeedTests.swift
//  OpenIntelligenceTests
//
//  Tokens per second means how fast the answer's text was written (5.8, `AnswerWritingSpeed`): the answer's tokens
//  over the time from its first text to its last. Reading the prompt, retrieval and Deep Think's steps are outside
//  that window, and for Deep Think and Maximum only the call whose text became the answer counts. Until 5.8 the bar
//  read 1 to 5 because the figure divided by the whole call or the whole run.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class AnswerWritingSpeedTests: XCTestCase {

    // MARK: - Decode-only rate

    func testTheRateLeavesOutTheTimeBeforeTheFirstText() throws {
        // 300 tokens written between 4 s (after reading the prompt) and 14 s: 30 a second, not 300 / 14.
        let rate = try XCTUnwrap(
            AnswerWritingSpeed.tokensPerSecond(writtenTokens: 300, firstTextAt: 4, lastTextAt: 14))
        XCTAssertEqual(rate, 30, accuracy: 0.001)
    }

    func testNoWindowGivesNoRate() {
        XCTAssertNil(AnswerWritingSpeed.tokensPerSecond(writtenTokens: 300, firstTextAt: nil, lastTextAt: 14))
        XCTAssertNil(AnswerWritingSpeed.tokensPerSecond(writtenTokens: 300, firstTextAt: 4, lastTextAt: nil))
        // An answer that arrived in one piece has no writing time: no rate rather than thousands a second.
        XCTAssertNil(AnswerWritingSpeed.tokensPerSecond(writtenTokens: 300, firstTextAt: 4, lastTextAt: 4.01))
        XCTAssertNil(AnswerWritingSpeed.tokensPerSecond(writtenTokens: 0, firstTextAt: 4, lastTextAt: 14))
    }

    // MARK: - Written tokens

    func testApplesCountLessReasoningIsTheWrittenCount() {
        let usage = GenerationUsage(outputTokens: 500, reasoningTokens: 200, inputTokens: 6_000, cachedInputTokens: 0)
        XCTAssertEqual(
            AnswerWritingSpeed.writtenTokens(usage: usage, usageCoversText: true, text: "ignored", onDevice: false), 300
        )
    }

    func testTheEstimatorCountsWhenApplesCountCoversMoreThanTheText() {
        let usage = GenerationUsage(outputTokens: 500, reasoningTokens: 0, inputTokens: 6_000, cachedInputTokens: 0)
        let text = String(repeating: "a", count: 140)
        // 140 characters at 1.4 a token on device, 2.5 in the cloud (`FoundationModelTokenBudget`).
        XCTAssertEqual(
            AnswerWritingSpeed.writtenTokens(usage: usage, usageCoversText: false, text: text, onDevice: true), 100)
        XCTAssertEqual(
            AnswerWritingSpeed.writtenTokens(usage: nil, usageCoversText: true, text: text, onDevice: false), 56)
        XCTAssertEqual(
            AnswerWritingSpeed.writtenTokens(usage: nil, usageCoversText: false, text: "  \n", onDevice: true), 0)
    }

    // MARK: - Saved figure on a response

    func testAResponseWithoutAMeasurementDividesByItsWritingTimeOnly() throws {
        let response = LLMResponse(
            text: "x", tokensGenerated: 200, timeToFirstToken: 3, totalTime: 13, modelName: nil, toolCallsMade: 0)
        XCTAssertEqual(try XCTUnwrap(response.tokensPerSecond), 20, accuracy: 0.001, "200 over 10 s, not over 13 s")
    }

    func testAMeasuredResponseReportsItsMeasurementEvenWhenEmpty() {
        let measured = LLMResponse(
            text: "x", tokensGenerated: 200, timeToFirstToken: 3, totalTime: 13, modelName: nil, toolCallsMade: 0,
            writingSpeed: .measured(42))
        XCTAssertEqual(measured.tokensPerSecond, 42)
        let unmeasurable = LLMResponse(
            text: "x", tokensGenerated: 200, timeToFirstToken: 3, totalTime: 13, modelName: nil, toolCallsMade: 0,
            writingSpeed: .measured(nil))
        XCTAssertNil(unmeasurable.tokensPerSecond, "a stream with no writing window does not fall back to a guess")
    }

    // MARK: - Live figure

    func testTheLiveFigureWaitsForAnswerText() {
        XCTAssertEqual(
            AnswerWritingSpeed.liveTokensPerSecond(
                charactersAfterFirstPiece: 0, elapsedSinceFirstPiece: 5, onDevice: true), 0)
        XCTAssertEqual(
            AnswerWritingSpeed.liveTokensPerSecond(
                charactersAfterFirstPiece: 140, elapsedSinceFirstPiece: 0.1, onDevice: true), 0)
        // 280 characters at 1.4 a token in 4 s: 50 a second.
        XCTAssertEqual(
            AnswerWritingSpeed.liveTokensPerSecond(
                charactersAfterFirstPiece: 280, elapsedSinceFirstPiece: 4, onDevice: true), 50, accuracy: 0.001)
    }

    // MARK: - Deep Think and Maximum: the final answer's call

    private let finalText = """
        The lease runs for twelve months from March 1. Either party may end it with sixty days' written notice, \
        and the deposit is returned within thirty days of the keys being handed back.
        """

    func testTheFinalAnswerIsTheLatestCallWhoseTextItHolds() {
        let calls = [
            AnswerWritingSpeed.Call(text: "PLAN: search for notice period", tokensPerSecond: 3, streamedToChat: false),
            AnswerWritingSpeed.Call(text: finalText, tokensPerSecond: 31, streamedToChat: true),
            AnswerWritingSpeed.Call(text: "VERDICT: supported", tokensPerSecond: 2, streamedToChat: false),
        ]
        // The answer's cleanup changes its opening; the call is still found.
        let shown = "**Answer:** " + finalText.replacingOccurrences(of: "\n", with: " ")
        XCTAssertEqual(AnswerWritingSpeed.finalAnswerSpeed(finalAnswer: shown, calls: calls), 31)
    }

    /// A short later call whose text sits inside the answer ("60 days") never takes over its speed (review, 2026-11-18).
    func testAShortLaterCallInsideTheAnswerIsNotTaken() {
        let calls = [
            AnswerWritingSpeed.Call(text: finalText, tokensPerSecond: 30, streamedToChat: true),
            AnswerWritingSpeed.Call(text: "supported", tokensPerSecond: 1, streamedToChat: false),
        ]
        XCTAssertEqual(
            AnswerWritingSpeed.finalAnswerSpeed(finalAnswer: finalText + " This is supported.", calls: calls), 30)
    }

    func testAnAnswerWrittenWithoutStreamingIsStillFound() {
        let calls = [
            AnswerWritingSpeed.Call(
                text: "first draft that was replaced entirely", tokensPerSecond: 25, streamedToChat: true),
            AnswerWritingSpeed.Call(text: finalText, tokensPerSecond: 28, streamedToChat: false),
        ]
        XCTAssertEqual(AnswerWritingSpeed.finalAnswerSpeed(finalAnswer: finalText, calls: calls), 28)
    }

    func testWithNoMatchTheLatestStreamedCallCountsAndOtherwiseNothing() {
        let calls = [
            AnswerWritingSpeed.Call(text: "an analysis step", tokensPerSecond: 4, streamedToChat: false),
            AnswerWritingSpeed.Call(text: "the answer as streamed", tokensPerSecond: 33, streamedToChat: true),
            AnswerWritingSpeed.Call(text: "a check", tokensPerSecond: 5, streamedToChat: false),
        ]
        XCTAssertEqual(AnswerWritingSpeed.finalAnswerSpeed(finalAnswer: "rewritten answer", calls: calls), 33)
        XCTAssertNil(
            AnswerWritingSpeed.finalAnswerSpeed(
                finalAnswer: "rewritten answer",
                calls: [AnswerWritingSpeed.Call(text: "an analysis step", tokensPerSecond: 4, streamedToChat: false)]),
            "the run's other calls never stand in for the answer")
    }

    func testTheMeterRecordsOnlyInsideItsRun() async {
        let meter = AgenticAnswerWritingMeter()
        await AgenticAnswerWritingMeter.$current.withValue(meter) {
            AgenticAnswerWritingMeter.current?.record(text: "answer", tokensPerSecond: 17, streamedToChat: true)
            await Task {
                AgenticAnswerWritingMeter.current?.record(text: "check", tokensPerSecond: nil, streamedToChat: false)
            }.value
        }
        XCTAssertEqual(
            meter.calls,
            [
                AnswerWritingSpeed.Call(text: "answer", tokensPerSecond: 17, streamedToChat: true),
                AnswerWritingSpeed.Call(text: "check", tokensPerSecond: nil, streamedToChat: false),
            ], "a child task's call counts too")
        XCTAssertNil(AgenticAnswerWritingMeter.current, "no meter outside a run")
    }
}

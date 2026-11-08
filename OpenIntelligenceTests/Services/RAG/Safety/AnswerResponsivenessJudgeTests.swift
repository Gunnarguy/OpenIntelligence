//
//  AnswerResponsivenessJudgeTests.swift
//  OpenIntelligenceTests
//
//  The parts of the responsiveness judge that do not need the model: what it reads, the answers it settles without
//  the model, the token it writes and the note a rewrite gets. Its verdicts on real answers are measured in
//  `BenchmarkRuns/2026-11-07-responsiveness`.
//

import XCTest

@testable import OpenIntelligenceEngine

final class AnswerResponsivenessJudgeTests: XCTestCase {
    func testTheJudgeReadsTheAnswerWithoutCitationMarkersOrEmphasis() {
        XCTAssertEqual(AnswerResponsivenessJudge.readableAnswer("1-28. [S3]"), "1-28.")
        XCTAssertEqual(
            AnswerResponsivenessJudge.readableAnswer("The tank holds **14.3 gallons** [S1, S2]."),
            "The tank holds 14.3 gallons .")
        XCTAssertEqual(AnswerResponsivenessJudge.readableAnswer("Use 200 mg [E2]"), "Use 200 mg")
    }

    func testAVeryLongAnswerIsCutAtTheLimit() {
        let long = String(repeating: "word ", count: 2_000)
        let readable = AnswerResponsivenessJudge.readableAnswer(long)
        XCTAssertTrue(readable.hasSuffix("[answer continues]"))
        XCTAssertLessThanOrEqual(readable.count, AnswerResponsivenessJudge.answerCharacterLimit + 20)
    }

    func testAnEmptyAnswerOrOneOfCitationsAloneIsSettledWithoutTheModel() {
        XCTAssertEqual(AnswerResponsivenessJudge.judgmentWithoutModel(answer: "")?.verdict, AnswerResponsiveness.none)
        XCTAssertEqual(
            AnswerResponsivenessJudge.judgmentWithoutModel(answer: "[S3]")?.verdict, AnswerResponsiveness.none)
        XCTAssertEqual(
            AnswerResponsivenessJudge.judgmentWithoutModel(answer: " ** . ")?.verdict, AnswerResponsiveness.none)
        // Anything with a letter or a digit goes to the model: "28" can be a full answer to "how many pages".
        XCTAssertNil(AnswerResponsivenessJudge.judgmentWithoutModel(answer: "1-28. [S3]"))
        XCTAssertNil(AnswerResponsivenessJudge.judgmentWithoutModel(answer: "Yes"))
    }

    func testThePromptCarriesTheQuestionAndTheReadableAnswer() {
        let prompt = AnswerResponsivenessJudge.prompt(question: " How much DHA is recommended? ", answer: "1-28. [S3]")
        XCTAssertTrue(prompt.contains("Question: How much DHA is recommended?"))
        XCTAssertTrue(prompt.contains("Answer: 1-28."))
        XCTAssertFalse(prompt.contains("[S3]"))
        XCTAssertTrue(AnswerResponsivenessJudge.prompt(question: "Q?", answer: "[S1]").contains("Answer: (empty)"))
    }

    /// An answer saying the library does not have it answers the question, whatever the model says it gives.
    func testTheVerdictComesFromTheReviewsTwoAnswers() {
        typealias Judge = AnswerResponsivenessJudge
        XCTAssertEqual(Judge.verdict(saysItIsNotInTheSources: true, verdict: "none"), .full)
        XCTAssertEqual(Judge.verdict(saysItIsNotInTheSources: false, verdict: "none"), AnswerResponsiveness.none)
        XCTAssertEqual(Judge.verdict(saysItIsNotInTheSources: false, verdict: "partial"), .partial)
        XCTAssertEqual(Judge.verdict(saysItIsNotInTheSources: false, verdict: " Full "), .full)
        // An unreadable reading is not held against the answer.
        XCTAssertEqual(Judge.verdict(saysItIsNotInTheSources: false, verdict: "unclear"), .full)
    }

    func testTheGatingTokenNamesTheVerdict() {
        for verdict in AnswerResponsiveness.allCases {
            let judgment = ResponsivenessJudgment(verdict: verdict, askedFor: "", missing: "", seconds: 0)
            XCTAssertEqual(judgment.gatingToken, "answers:\(verdict.rawValue)")
        }
    }

    func testARewriteIsToldWhatWasAskedAndWhatWasMissing() {
        let judgment = ResponsivenessJudgment(
            verdict: .none, askedFor: "an amount of DHA with its unit", missing: "no amount is given", seconds: 1)
        let note = judgment.regenerationNote
        XCTAssertTrue(note.contains("The question asks for an amount of DHA with its unit."))
        XCTAssertTrue(note.contains("Missing: no amount is given."))
        XCTAssertTrue(note.contains("If the sources give several values"))
        XCTAssertTrue(note.contains("If the sources do not contain it, say so."))
        let bare = ResponsivenessJudgment(verdict: .none, askedFor: " ", missing: "", seconds: 0).regenerationNote
        XCTAssertFalse(bare.contains("asks for"))
        XCTAssertFalse(bare.contains("Missing:"))
        let partial = ResponsivenessJudgment(verdict: .partial, askedFor: "", missing: "", seconds: 0).regenerationNote
        XCTAssertTrue(partial.hasPrefix("Your previous answer answered only part of the question."))
    }

    /// Standard keeps a rewrite only when it answers more completely than the first answer.
    @MainActor
    func testARewriteIsKeptOnlyWhenItAnswersMoreCompletely() {
        let rank = RAGService.responsivenessRank
        XCTAssertLessThan(rank(AnswerResponsiveness.none), rank(.partial))
        XCTAssertLessThan(rank(.partial), rank(.full))
    }
}

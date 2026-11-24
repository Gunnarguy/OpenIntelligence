//
//  EarlierTurnsAndNamedValuesTests.swift
//  OpenIntelligenceTests
//
//  Items 1 to 3 of the 5.9 proposal (`Docs/ai/plans/consistent-answers.md`, 2026-11-23). In the answer test every
//  wrong answer to the middle and end documents' token questions named another document's token (34 of 34): a scoped
//  ask read the library's conversation memory, and the answer check, given the earlier turns, called a right token
//  wrong and had it rewritten. Standard also gave "45 C" as a battery's warranty coverage, a value its table gave for
//  something else, and the coverage gate passed it because the question held the words "warranty coverage".
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class EarlierTurnsAndNamedValuesTests: XCTestCase {
    // MARK: Item 1: a scoped ask neither reads nor records the conversation

    func testOnlyAnAskWithoutScopeUsesTheConversation() {
        XCTAssertTrue(ConversationContextRules.usesConversation(scope: nil))
        XCTAssertTrue(ConversationContextRules.usesConversation(scope: []))
        XCTAssertFalse(ConversationContextRules.usesConversation(scope: [UUID()]))
    }

    func testAScopedAskGoesWithoutTheLibrarysEarlierTurns() async {
        DirectModelCallsForTesting.disabled = true
        defer { DirectModelCallsForTesting.disabled = false }
        let engine = RAGService()
        let library = UUID()
        let memory = ConversationMemoryService.shared
        memory.clearMemory(for: library)
        addTeardownBlock { @MainActor in ConversationMemoryService.shared.clearMemory(for: library) }
        await memory.addTurn(
            userQuery: "What is the required validation token?",
            assistantResponse: "The required validation token is LITM-BEGINNING-42 [S1].", for: library)
        func prompt(_ question: String) -> String {
            engine.buildGenerationPrompt(
                selectedId: library, question: question, retrievalConfig: .default, qualityModeRequiresCitations: false
            ).promptForGeneration
        }

        let question = "What is the required validation token?"
        let unscoped = prompt(question)
        XCTAssertTrue(unscoped.contains("LITM-BEGINNING-42"), "an ask in the chat still gets its memory: \(unscoped)")
        let scoped = RAGQueryScope.$documentIds.withValue([UUID()]) { prompt(question) }
        XCTAssertEqual(scoped, question, "a scoped ask is the bare question")
    }

    // MARK: Item 2: earlier turns reach the answer check only for a question that points back

    func testTheTwentyTestQuestionsStandAlone() throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json")
        guard let data = try? Data(contentsOf: manifest) else {
            throw XCTSkip("the fixture pack is not beside the test bundle (\(manifest.path))")
        }
        let cases = try XCTUnwrap(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 20)
        for question in cases.compactMap({ $0["query"] as? String }) {
            XCTAssertFalse(ConversationContextRules.pointsBack(question), question)
        }
    }

    func testFollowUpsPointBackAndQuestionsThatNameTheirSubjectDoNot() {
        for question in [
            "When is it due?", "And the deposit?", "Why?", "What does that mean?", "What about Project M2?",
            "Which one did you mention earlier?", "How does that compare with the other one?", "Also the payload",
            "Is the second one cheaper?", "What are their side effects?",
        ] {
            XCTAssertTrue(ConversationContextRules.pointsBack(question), question)
        }
        for question in [
            "What regulates mitochondrial quality?", "Who owns Project M1 and what is its reporting deadline?",
            "What is the required validation token?", "How many gallons of gasoline can the vehicle hold?",
            "Does the lease allow pets in the unit?", "What is the notice period for ending the lease?",
        ] {
            XCTAssertFalse(ConversationContextRules.pointsBack(question), question)
        }
    }

    /// The case seen on 2026-11-22: the middle document's question answered with its own token, and the check, shown
    /// an earlier answer about another document, called it wrong.
    func testTheJudgeGetsNoEarlierTurnsForAQuestionThatStandsAlone() {
        let question = "What is the required validation token?"
        let prompt =
            RAGService.earlierTurnsFraming
            + "User: What is the required validation token?\nAssistant: LITM-BEGINNING-42 [S1]\nCURRENT QUESTION: "
            + question
        XCTAssertEqual(RAGService.judgedQuestion(prompt: prompt, question: question), question)

        let followUp = "And when is it due?"
        let earlier = "User: Who owns Project M1?\nAssistant: Owner-1A [S1]\n\nCURRENT QUESTION: " + followUp
        let judged = RAGService.judgedQuestion(prompt: earlier, question: followUp)
        XCTAssertTrue(judged.hasPrefix(followUp))
        XCTAssertTrue(judged.contains("Project M1"), "a follow-up is still read against the turn before it")
        XCTAssertTrue(judged.contains("for reference only"))
    }

    // MARK: Item 3: a value is covered only by passages that say what it is

    func testWhatStatesAValue() {
        XCTAssertTrue(VerificationGateService.statesValue("The warranty coverage is 45 C."))
        XCTAssertTrue(VerificationGateService.statesValue("Capital expenditure was $1,577 million."))
        XCTAssertFalse(VerificationGateService.statesValue("The documents do not state the warranty coverage."))
        XCTAssertFalse(VerificationGateService.statesValue("The lease was signed in 2024."), "a plain year")
    }

    func testAValueGivenForSomethingElseDoesNotCoverTheClaimThatNamesWhatWasAsked() async {
        let gate = VerificationGateService()
        let warranty = "What is the warranty coverage for the unreleased 2032 prototype battery pack?"
        let unlabelled = "| field | value | | primary answer | 45 c | | control value | 88 units |"
        let labelled = "| field | value | | maximum charging temperature | 45 c | | control value | 88 units |"
        let invented = "The warranty coverage for the unreleased 2032 prototype battery pack is 45 C."
        let covered1 = await gate.isClaimCovered(claim: invented, inCorpus: unlabelled, query: warranty)
        XCTAssertFalse(covered1, "the passage says nothing of a warranty; only the question did")
        let covered2 = await gate.isClaimCovered(claim: invented, inCorpus: labelled, query: warranty)
        XCTAssertFalse(covered2, "45 C is the charging temperature, not a warranty")

        let temperature = "What is the maximum charging temperature limit?"
        let answer = "The maximum charging temperature limit is 45 C."
        let covered3 = await gate.isClaimCovered(claim: answer, inCorpus: labelled, query: temperature)
        XCTAssertTrue(covered3, "the passage names what the value is")
    }

    func testARefusalStillReadsTheQuestionsWords() async {
        let gate = VerificationGateService()
        let warranty = "What is the warranty coverage for the unreleased 2032 prototype battery pack?"
        let refusal = "The documents do not state the warranty coverage for the prototype battery pack."
        let covered = await gate.isClaimCovered(
            claim: refusal, inCorpus: "| maximum charging temperature | 45 c |", query: warranty)
        XCTAssertTrue(covered, "a claim with no value keeps the question's words, as before")
    }

    // MARK: Item 4: the cited file is named even when the answer mentions other files

    func testAnAnswerThatMentionsOtherFilesStillGetsTheCitedFilesName() {
        let names = ["retrieval_alpha.md", "retrieval_beta.md", "retrieval_gamma.md"]
        let answer =
            "The BETA trial cohort is described in Retrieval Fixture [S2]. The retrieval_alpha.md and retrieval_gamma.md "
            + "files cover other controls."
        XCTAssertEqual(
            RAGService.namingTheCitedDocument(
                answer, question: "Which fixture describes the BETA trial cohort?", sourceNames: names),
            "The BETA trial cohort is described in Retrieval Fixture [S2] (retrieval_beta.md). The retrieval_alpha.md and "
                + "retrieval_gamma.md files cover other controls.")
        let named = "It is retrieval_beta.md [S2]; retrieval_alpha.md is about ALPHA."
        XCTAssertEqual(
            RAGService.namingTheCitedDocument(named, question: "Which file describes BETA?", sourceNames: names), named)
    }

    // MARK: Items 5 to 7

    func testTheAnswerFirstInstructionHasNoPhraseToCopyAsALabel() {
        let instruction = AgenticOrchestrator.answerFirstInstruction
        XCTAssertFalse(instruction.contains("the exact value, name or finding"), instruction)
        XCTAssertFalse(
            instruction.contains(": the "), "no colon before a noun phrase the model can copy: \(instruction)")
        XCTAssertTrue(instruction.hasSuffix("\n"))
    }

    func testASummaryFingerprintIsStableAndTellsTextsApart() {
        XCTAssertEqual(DocumentSummaryService.fingerprint("abc"), DocumentSummaryService.fingerprint("abc"))
        XCTAssertEqual(DocumentSummaryService.fingerprint(""), "cbf29ce484222325", "FNV-1a's offset basis")
        XCTAssertNotEqual(DocumentSummaryService.fingerprint("abc"), DocumentSummaryService.fingerprint("abd"))
        XCTAssertEqual(DocumentSummaryService.fingerprint("abc").count, 16)
    }

    func testTheStepTemperatureDefaultAndItsMeasurementOverride() {
        let key = "benchmarkAgenticDefaultTemperature"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        XCTAssertEqual(RAGService.agenticDefaultTemperature(.maximum), 0.5)
        UserDefaults.standard.set(0.2, forKey: key)
        XCTAssertEqual(RAGService.agenticDefaultTemperature(.deepThink), 0.2, accuracy: 0.0001)
    }

    func testBothStandardPromptsSayAValueMustBeNamed() {
        XCTAssertTrue(RAGService.valueMustBeNamedRule.contains("names it as the thing asked"))
    }
}

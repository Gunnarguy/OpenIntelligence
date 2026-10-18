import XCTest
@testable import OpenIntelligenceEngine

/// Pins `AgenticOrchestrator.shouldAcceptReplacement` and the citation counter it
/// depends on.
///
/// The rule is never trade a grounded answer for an ungrounded one. It fired six times
/// across three device captures between 2026-08-24 and 2026-08-25, every time on the
/// recursive-research loop proposing to swap a ~3,000-character cited answer for a
/// ~200-character uncited fragment.
final class AnswerReplacementGuardTests: XCTestCase {

    // MARK: - The counter the guard depends on

    /// The undercount that silently disarmed the guard. `verifyCitations` was fixed for
    /// the parenthesis form after a device run scored `citations=0/0` on an answer
    /// carrying five `(S1)` markers; `citationCount` was not fixed with it.
    func testCitationCount_CountsParenthesisForm() {
        XCTAssertEqual(AgenticOrchestrator.citationCount(in: "Dopamine acts fast (S1) and slow (S2)."), 2)
        XCTAssertEqual(AgenticOrchestrator.citationCount(in: "Dopamine acts fast [S1] and slow [S2]."), 2)
        XCTAssertEqual(AgenticOrchestrator.citationCount(in: "Mixed forms [S1] and (S2) and [S3]."), 3)
    }

    func testCitationCount_IgnoresNonCitations() {
        XCTAssertEqual(AgenticOrchestrator.citationCount(in: "No markers here at all."), 0)
        XCTAssertEqual(AgenticOrchestrator.citationCount(in: "Section (S) and [Sx] are not citations."), 0)
    }

    // MARK: - The guard

    /// The exact shape observed on device: 9 citations traded for none.
    func testRejectsTradingCitationsForNone() {
        let grounded = "Dopamine receptors regulate movement [S1]. Striatal signalling accelerates locomotion [S2]."
        let stub = "Dopamine is involved in movement."
        XCTAssertFalse(AgenticOrchestrator.shouldAcceptReplacement(previous: grounded, replacement: stub))
    }

    /// The parenthesis case that used to slip through: previous counted as zero, so the
    /// guard returned true and allowed the very replacement it exists to block.
    func testRejectsTradingParenthesisCitationsForNone() {
        let grounded = "Dopamine receptors regulate movement (S1). Striatal signalling accelerates locomotion (S2)."
        let stub = "Dopamine is involved in movement."
        XCTAssertFalse(AgenticOrchestrator.shouldAcceptReplacement(previous: grounded, replacement: stub))
    }

    /// Shorter is allowed. This is deliberately not a rule about length — 12 of the 18
    /// answers discarded in the 2026-08-15 run had themselves failed citation grounding.
    func testAcceptsShorterReplacementThatKeepsCitations() {
        let long = "A long grounded answer [S1] with much elaboration and repetition [S2] throughout."
        let short = "A tighter grounded answer [S1][S2]."
        XCTAssertTrue(AgenticOrchestrator.shouldAcceptReplacement(previous: long, replacement: short))
    }

    /// Nothing to protect: an ungrounded answer may be replaced by anything.
    func testAcceptsReplacementWhenPreviousWasUngrounded() {
        XCTAssertTrue(AgenticOrchestrator.shouldAcceptReplacement(previous: "No citations here.", replacement: "Also none."))
        XCTAssertTrue(AgenticOrchestrator.shouldAcceptReplacement(previous: "No citations here.", replacement: "Now grounded [S1]."))
    }

    /// Gaining citations is always fine.
    func testAcceptsReplacementThatAddsCitations() {
        XCTAssertTrue(AgenticOrchestrator.shouldAcceptReplacement(previous: "One source [S1].", replacement: "Two sources [S1][S2]."))
    }
    // MARK: - Research may replace a synthesis only when it agrees with it (5.7)

    private let fileTypesSynthesis = """
        OpenIntelligence imports PDF files, Word documents, Markdown and plain text files, CSV and \
        spreadsheet files, JSON and JSON Lines records, images with text in them, and audio recordings, \
        which it transcribes on the device. Each file is cut into passages and indexed so a question can \
        find the passage that answers it. The documentation does not explicitly list every file type it \
        accepts, so formats that are not named here may also work through the same import path.
        """

    private let checksSynthesis = """
        OpenIntelligence runs nine verification checks on a Standard answer before it shows it. They \
        compare the answer with the passages it rests on: whether its words and numbers appear there, \
        whether its citations point at real passages, and whether a sentence says the opposite of its \
        source. The documents do not say how long each check takes, but every answer is checked the same way.
        """

    /// The wrong line measured on 2026-09-23 says things the synthesis never said: kept out.
    func testAOneLineAnswerThatSaysSomethingNewDoesNotReplaceTheSynthesis() {
        XCTAssertFalse(
            AgenticOrchestrator.researchMayReplaceSynthesis(
                question: "What file types does OpenIntelligence handle?",
                synthesis: fileTypesSynthesis,
                research: "OpenIntelligence handles file types such as notes, warnings, exceptions, and documents."))
    }

    /// The Self-RAG loop's call (the one Deep Think reaches) applies the first call site's checks (5.7): the wrong line
    /// keeps the answer and stops the loop, the right one replaces it, and an evidence dump or a retrieval miss keeps it.
    func testTheLoopsResearchCallAppliesTheFirstSitesChecks() {
        XCTAssertEqual(
            AgenticOrchestrator.loopResearchVerdict(
                question: "What file types does OpenIntelligence handle?", answer: fileTypesSynthesis,
                research: "OpenIntelligence handles file types such as notes, warnings, exceptions, and documents.",
                isEvidenceDump: false, isRetrievalMiss: false),
            .keepAndStop)
        XCTAssertEqual(
            AgenticOrchestrator.loopResearchVerdict(
                question: "How many verification checks does OpenIntelligence run?", answer: checksSynthesis,
                research: "Nine verification checks run.", isEvidenceDump: false, isRetrievalMiss: false),
            .replace)
        XCTAssertEqual(
            AgenticOrchestrator.loopResearchVerdict(
                question: "How many verification checks does OpenIntelligence run?", answer: checksSynthesis,
                research: "Nine verification checks run.", isEvidenceDump: true, isRetrievalMiss: false),
            .keep)
        XCTAssertEqual(
            AgenticOrchestrator.loopResearchVerdict(
                question: "How many verification checks does OpenIntelligence run?", answer: checksSynthesis,
                research: "Nine verification checks run.", isEvidenceDump: false, isRetrievalMiss: true),
            .keep)
    }

    /// The right line from the same day agrees with the synthesis: it may replace it.
    func testAOneLineAnswerThatAgreesWithTheSynthesisReplacesIt() {
        XCTAssertTrue(
            AgenticOrchestrator.researchMayReplaceSynthesis(
                question: "How many verification checks does OpenIntelligence run?",
                synthesis: checksSynthesis, research: "Nine verification checks run."))
    }

    func testAShortSynthesisOrALongResearchAnswerIsLeftToTheOtherRules() {
        XCTAssertTrue(
            AgenticOrchestrator.researchMayReplaceSynthesis(
                question: "Q?", synthesis: "A short synthesis.", research: "Something else entirely."))
        XCTAssertTrue(
            AgenticOrchestrator.researchMayReplaceSynthesis(
                question: "What file types does OpenIntelligence handle?", synthesis: fileTypesSynthesis,
                research: String(fileTypesSynthesis.prefix(fileTypesSynthesis.count / 2))))
    }

    func testAnAnswerThatOnlyRepeatsTheQuestionDoesNotReplaceTheSynthesis() {
        XCTAssertFalse(
            AgenticOrchestrator.researchMayReplaceSynthesis(
                question: "What file types does OpenIntelligence handle?", synthesis: fileTypesSynthesis,
                research: "OpenIntelligence handles file types."))
    }

    func testNumbersCountTheSameWrittenEitherWay() {
        XCTAssertEqual(AgenticOrchestrator.answerWords(in: "Nine checks"), ["9", "checks"])
        XCTAssertTrue(AgenticOrchestrator.answerWords(in: "It runs 9 checks").contains("9"))
    }
}

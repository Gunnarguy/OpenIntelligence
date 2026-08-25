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
}

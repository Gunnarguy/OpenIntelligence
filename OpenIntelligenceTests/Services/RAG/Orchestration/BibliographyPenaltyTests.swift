import XCTest
@testable import OpenIntelligenceEngine

/// Pins `RAGEngine.computeBibliographyPenalty`.
///
/// A reference list is the worst possible evidence and one of the best keyword
/// matches: a page of citations about dopamine contains "dopamine" many times and
/// states no fact about it. On 2026-08-24 two of twenty cited sources in a shipped
/// Deep Think answer were bibliography entries.
///
/// The risk in a penalty like this is the false positive, so most of these cases are
/// prose that *must not* be demoted.
final class BibliographyPenaltyTests: XCTestCase {

    /// Verbatim from the document that produced the defect.
    private let referenceList = """
    58. Menegas W, Akiti K, Amo R, Uchida N, Watabe-Uchida M. Dopamine neurons \
    projecting to the posterior striatum reinforce avoidance of threatening stimuli. \
    Nat. Neurosci. 2018; 21: 1421-1430.
    59. Chang CH, Grace AA. Amygdala-ventral pallidum pathway decreases dopamine \
    activity after chronic mild stress. Biol. Psychiatry 2014; 76: 223-230.
    60. Howe MW, Tierney PL, Sandberg SG, Phillips PE, Graybiel AM. Prolonged dopamine \
    signalling in striatum signals proximity and value of distant rewards. \
    Nature 2013; 500: 575-579.
    """

    func testReferenceList_IsPenalised() {
        let penalty = RAGEngine.computeBibliographyPenalty(content: referenceList)
        XCTAssertGreaterThan(penalty, 0, "A three-entry reference list must be demoted")
    }

    /// Body prose about the same subject must not be touched. This is the passage the
    /// reference list was outranking.
    func testResponsiveProse_IsNotPenalised() {
        let prose = """
        Stimulation of dopamine axon terminals in the dorsal striatum induced the \
        acceleration of locomotion within 160 ms, whereas sustained signalling operated \
        over minutes. These findings suggest that transient and sustained dopamine \
        signals regulate distinct aspects of motivated behavior, and that the two \
        timescales are dissociable in principle.
        """
        XCTAssertEqual(RAGEngine.computeBibliographyPenalty(content: prose), 0)
    }

    /// A methods paragraph legitimately cites authors and carries years. It must survive.
    func testMethodsProseCitingAuthors_IsNotPenalised() {
        let methods = """
        We followed the protocol described by Menegas and colleagues, adapting the \
        injection volume for the smaller cohort. Recordings were made over fourteen days \
        in a temperature-controlled room, and the analysis pipeline was the one reported \
        in that earlier work, with the single change that baseline drift was corrected \
        per session rather than per animal.
        """
        XCTAssertEqual(RAGEngine.computeBibliographyPenalty(content: methods), 0)
    }

    /// A numbered procedure opens on digits and must not be mistaken for citations.
    func testNumberedProcedure_IsNotPenalised() {
        let procedure = """
        1. Remove the access panel and set it aside. 2. Disconnect the ribbon cable from \
        the mainboard, taking care not to bend the pins. 3. Lift the assembly clear of \
        the housing. 4. Inspect the gasket for cracking before reassembly, replacing it \
        if any deformation is visible along the seating edge.
        """
        XCTAssertEqual(RAGEngine.computeBibliographyPenalty(content: procedure), 0)
    }

    /// Short chunks are skipped entirely rather than guessed at.
    func testShortContent_IsNotPenalised() {
        XCTAssertEqual(RAGEngine.computeBibliographyPenalty(content: "Nature 2013; 500: 575-579."), 0)
    }

    /// Denser citation blocks are demoted harder, so a page of pure references loses to
    /// a page that merely ends with a few.
    func testDenserReferenceBlock_IsPenalisedAtLeastAsHard() {
        let sparse = referenceList + " " + String(repeating: "This paragraph discusses the mechanism at length and states a finding. ", count: 12)
        let dense = RAGEngine.computeBibliographyPenalty(content: referenceList)
        let diluted = RAGEngine.computeBibliographyPenalty(content: sparse)
        XCTAssertGreaterThanOrEqual(dense, diluted)
    }
}

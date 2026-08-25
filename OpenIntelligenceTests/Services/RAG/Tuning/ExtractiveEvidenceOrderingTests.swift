import XCTest
@testable import OpenIntelligenceEngine

/// Pins `EvidenceScoringPolicyService.extractiveEvidencePrecedes`.
///
/// The predicate this replaced used `abs(aPriority - bPriority) >= 2` inside a
/// comparator, which is not a strict weak ordering. `sorted(by:)` is documented as
/// producing an unspecified result for such a predicate, so the evidence a query was
/// answered from came out in an undefined order.
///
/// Third instance of that shape found in this codebase on 2026-08-24, and the most
/// consequential: `LEDGER.md` records `final` r@1 at 0.442 against `rerank` r@1 at
/// 0.610, meaning the ordering gets worse at exactly this stage.
final class ExtractiveEvidenceOrderingTests: XCTestCase {

    private func precedes(_ lhs: (p: Float, r: Float), _ rhs: (p: Float, r: Float)) -> Bool {
        EvidenceScoringPolicyService.extractiveEvidencePrecedes(
            lhsPriority: lhs.p, lhsRelevance: lhs.r,
            rhsPriority: rhs.p, rhsRelevance: rhs.r
        )
    }

    /// The case that broke the old predicate: a chain stepping by less than the
    /// threshold, where both inner pairs compare "equal" but the outer pair does not.
    func testIsTransitive() {
        let a: (p: Float, r: Float) = (5, 0.10)
        let b: (p: Float, r: Float) = (4, 0.50)
        let c: (p: Float, r: Float) = (3, 0.90)

        if precedes(a, b) && precedes(b, c) {
            XCTAssertTrue(precedes(a, c), "Comparator is not transitive")
        }
        if precedes(c, b) && precedes(b, a) {
            XCTAssertTrue(precedes(c, a), "Comparator is not transitive in reverse")
        }
        XCTAssertNotEqual(precedes(a, c), precedes(c, a), "Comparator is not asymmetric")
    }

    /// Sorting must be stable across runs and independent of input order, which an
    /// unspecified-result predicate cannot guarantee.
    func testSortIsOrderIndependent() {
        let items: [(p: Float, r: Float)] = [
            (10, 0.20), (11, 0.90), (12, 0.10), (0, 0.99), (5, 0.30), (4, 0.80)
        ]
        let forward = items.sorted { precedes($0, $1) }.map(\.p)
        let reversed = items.reversed().sorted { precedes($0, $1) }.map(\.p)
        XCTAssertEqual(forward, reversed, "Sort result depends on input order")
    }

    /// A clear priority advantage still outranks relevance.
    func testClearPriorityAdvantageWins() {
        XCTAssertTrue(precedes((20, 0.01), (5, 0.99)))
    }

    /// Within a band, relevance decides — the cross-encoder's ordering survives.
    func testWithinBandRelevanceDecides() {
        XCTAssertTrue(precedes((10, 0.90), (10, 0.20)))
        XCTAssertFalse(precedes((10, 0.20), (10, 0.90)))
    }

    /// Whole-word keyword credit: a keyword matched inside a longer word is worth 5
    /// points here, which is enough to reorder the evidence a query is answered from.
    func testKeywordCreditIsWholeWord() {
        let tokens = Set(EvidenceScoringPolicyService.evidenceTokens(in: "Dopamine signalling in the striatum"))
        XCTAssertTrue(tokens.contains("dopamine"))
        XCTAssertFalse(tokens.contains("min"), "'min' must not be credited from inside 'dopamine'")
        XCTAssertTrue(tokens.contains("striatum"))
    }
}

import XCTest

@testable import OpenIntelligenceEngine

final class StructuredAnswerTests: XCTestCase {

    // MARK: - citationIndex

    func testCitationIndexAcceptsValidFormats() {
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "S1"), 0)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "s2"), 1)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "[S3]"), 2)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: " [s4] "), 3)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "S10"), 9)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "S999"), 998)
    }

    func testCitationIndexRejectsInvalidFormats() {
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: ""))
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "S"))
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "1"))
        // Citations are one-based, so S0 is out of range.
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "S0"))
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "S-1"))
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "abc"))
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "Sabc"))
    }

    func testCitationIndexUsesFirstMatchWithinSurroundingText() {
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "Source S5"), 4)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "S6 is the source"), 5)
        XCTAssertEqual(StructuredAnswerParsing.citationIndex(from: "see S2 and S7"), 1)
        // Only the first S<digits> match is considered; a later valid token does not rescue it.
        XCTAssertNil(StructuredAnswerParsing.citationIndex(from: "S0 then S3"))
    }

    // MARK: - minimumClaimLength

    func testMinimumClaimLengthForExtractiveFirstIntents() {
        let extractiveFirst: [AnswerIntent] = [.lookup, .tableLookup]

        for intent in extractiveFirst {
            XCTAssertTrue(intent.isExtractiveFirst, "Expected \(intent) to be extractive-first")
            XCTAssertEqual(
                StructuredAnswerParsing.minimumClaimLength(for: intent), 8,
                "Expected 8 for extractive-first intent \(intent)")
        }
    }

    func testMinimumClaimLengthForSynthesisIntents() {
        let synthesis: [AnswerIntent] = [
            .procedure, .compare, .summarize, .investigate, .compute, .findings,
        ]

        for intent in synthesis {
            XCTAssertFalse(intent.isExtractiveFirst, "Expected \(intent) to not be extractive-first")
            XCTAssertEqual(
                StructuredAnswerParsing.minimumClaimLength(for: intent), 20,
                "Expected 20 for synthesis intent \(intent)")
        }
    }

    func testMinimumClaimLengthIntentCoverageIsExhaustive() {
        let covered: Set<AnswerIntent> = [
            .lookup, .tableLookup, .procedure, .compare, .summarize, .investigate, .compute,
            .findings,
        ]
        XCTAssertEqual(covered, Set(AnswerIntent.allCases))
    }

    func testMinimumClaimLengthBoundarySemantics() {
        // Claim admission at the call site is `sentence.count >= minimum`: a claim of
        // exactly the minimum length qualifies, one character shorter does not.
        let extractiveMinimum = StructuredAnswerParsing.minimumClaimLength(for: .lookup)
        XCTAssertGreaterThanOrEqual("SAE 0W-20".count, extractiveMinimum)  // 9 characters
        XCTAssertGreaterThanOrEqual("SAE 0W20".count, extractiveMinimum)  // 8 characters
        XCTAssertLessThan("SAE0W20".count, extractiveMinimum)  // 7 characters

        let synthesisMinimum = StructuredAnswerParsing.minimumClaimLength(for: .summarize)
        XCTAssertGreaterThanOrEqual("The pump runs hourly.".count, synthesisMinimum)  // 21 characters
        XCTAssertGreaterThanOrEqual("The pump ran hourly.".count, synthesisMinimum)  // 20 characters
        XCTAssertLessThan("The pump ran hourly".count, synthesisMinimum)  // 19 characters
    }
}

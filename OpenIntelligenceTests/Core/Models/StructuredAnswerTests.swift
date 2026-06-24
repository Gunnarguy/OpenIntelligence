import XCTest
@testable import OpenIntelligenceEngine

final class StructuredAnswerTests: XCTestCase {

    func testMinimumClaimLength_ExtractiveIntents() {
        let extractiveIntents: [AnswerIntent] = [
            .lookup, .tableLookup, .procedure, .compare, .compute
        ]

        for intent in extractiveIntents {
            XCTAssertEqual(StructuredAnswer.minimumClaimLength(for: intent), 8,
                           "Expected 8 for extractive intent \(intent)")
        }
    }

    func testMinimumClaimLength_NonExtractiveIntents() {
        let nonExtractiveIntents: [AnswerIntent] = [
            .summarize, .investigate, .findings
        ]

        for intent in nonExtractiveIntents {
            XCTAssertEqual(StructuredAnswer.minimumClaimLength(for: intent), 20,
                           "Expected 20 for non-extractive intent \(intent)")
        }
    }
}

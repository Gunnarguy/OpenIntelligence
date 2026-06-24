import XCTest
@testable import OpenIntelligence

final class StructuredAnswerTests: XCTestCase {

    // MARK: - citationIndex Tests

    func testCitationIndex_validFormats() {
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "S1"), 0)
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "s2"), 1)
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "[S3]"), 2)
        XCTAssertEqual(StructuredAnswer.citationIndex(from: " [s4] "), 3)
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "S10"), 9)
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "S999"), 998)
    }

    func testCitationIndex_invalidFormats() {
        XCTAssertNil(StructuredAnswer.citationIndex(from: ""))
        XCTAssertNil(StructuredAnswer.citationIndex(from: "S"))
        XCTAssertNil(StructuredAnswer.citationIndex(from: "1"))
        XCTAssertNil(StructuredAnswer.citationIndex(from: "S0")) // Must be > 0
        XCTAssertNil(StructuredAnswer.citationIndex(from: "S-1"))
        XCTAssertNil(StructuredAnswer.citationIndex(from: "abc"))
        XCTAssertNil(StructuredAnswer.citationIndex(from: "Sabc"))
    }

    func testCitationIndex_withExtraText() {
        // According to current implementation, firstMatch is used, so it might extract from middle of string
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "Source S5"), 4)
        XCTAssertEqual(StructuredAnswer.citationIndex(from: "S6 is the source"), 5)
    }
}

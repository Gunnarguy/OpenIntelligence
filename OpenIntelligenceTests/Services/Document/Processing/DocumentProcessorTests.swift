import XCTest
@testable import OpenIntelligenceEngine

final class DocumentProcessorTests: XCTestCase {

    func testTableCellReadabilityScore_EmptyString_ReturnsZero() {
        let processor = DocumentProcessor()
        XCTAssertEqual(processor.tableCellReadabilityScore(""), 0)
        XCTAssertEqual(processor.tableCellReadabilityScore("   "), 0)
        XCTAssertEqual(processor.tableCellReadabilityScore("\n\t"), 0)
    }

    func testTableCellReadabilityScore_NonPrintableCharacters_ReturnsZero() {
        let processor = DocumentProcessor()
        let nonPrintable = String(UnicodeScalar(7)!) // Bell character
        XCTAssertEqual(processor.tableCellReadabilityScore(nonPrintable), 0)
    }

    func testTableCellReadabilityScore_HighlyReadableText() {
        let processor = DocumentProcessor()
        let score = processor.tableCellReadabilityScore("Annual Revenue 2024")
        XCTAssertGreaterThan(score, 0.5)
    }

    func testTableCellReadabilityScore_NumbersOnly() {
        let processor = DocumentProcessor()
        let score = processor.tableCellReadabilityScore("1,234.56")
        XCTAssertGreaterThan(score, 0.1) // Should get some score for digits
    }

    func testTableCellReadabilityScore_MixedGibberish() {
        let processor = DocumentProcessor()
        let gibberishScore = processor.tableCellReadabilityScore("x$#@%&*()")
        let readableScore = processor.tableCellReadabilityScore("Company Info")
        XCTAssertLessThan(gibberishScore, readableScore)
    }
}

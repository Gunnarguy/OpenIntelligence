import XCTest
@testable import OpenIntelligenceEngine

final class DocumentProcessorTests: XCTestCase {

    // MARK: - Spatial line breaking (two-column extraction)
    //
    // Geometry modelled on a two-column journal page: 612pt wide, ~10pt type,
    // left column x 50...290, right column x 320...560. These are the cases that
    // decide whether `detectColumnBoundaries` downstream sees a real gutter or a
    // page of averaged centre-points, which is the whole two-column defect.

    private func rect(x: CGFloat, y: CGFloat, w: CGFloat = 30, h: CGFloat = 10) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    func testSpatialLineBreak_NoLineStarted_IsNotABreak() {
        let result = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 50, y: 700),
            currentLineBounds: .zero,
            currentLineY: -1
        )
        XCTAssertEqual(result, .none)
    }

    func testSpatialLineBreak_NormalWordSpacing_IsNotABreak() {
        // Next word 4pt after the current line ends. Ordinary inter-word space.
        let result = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 154, y: 700),
            currentLineBounds: CGRect(x: 50, y: 700, width: 100, height: 10),
            currentLineY: 705
        )
        XCTAssertEqual(result, .none)
    }

    func testSpatialLineBreak_NextRow_IsVerticalGap() {
        let result = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 50, y: 688),
            currentLineBounds: CGRect(x: 50, y: 700, width: 240, height: 10),
            currentLineY: 705
        )
        XCTAssertEqual(result, .verticalGap)
    }

    /// The defect. A left-column line ends at x=290 and the next word starts at
    /// x=320 on the same row: that is the gutter, not a wide space. Before this
    /// was detected the two columns merged into one line whose mean X sat at the
    /// page centre, which erased the signal `detectColumnBoundaries` looks for.
    func testSpatialLineBreak_CrossingTheGutter_IsHorizontalGap() {
        let result = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 320, y: 700),
            currentLineBounds: CGRect(x: 50, y: 700, width: 240, height: 10),
            currentLineY: 705
        )
        XCTAssertEqual(result, .horizontalGap)
    }

    /// Wrapping back to the left margin while Y moved less than the threshold.
    func testSpatialLineBreak_BackToLeftMargin_IsHorizontalGap() {
        let result = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 50, y: 698),
            currentLineBounds: CGRect(x: 320, y: 700, width: 240, height: 10),
            currentLineY: 703
        )
        XCTAssertEqual(result, .horizontalGap)
    }

    func testSpatialLineBreak_EmptyCurrentBounds_CannotJudgeHorizontally() {
        let result = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 400, y: 700),
            currentLineBounds: .zero,
            currentLineY: 705
        )
        XCTAssertEqual(result, .none)
    }

    /// The threshold scales with glyph height, so the same layout at a different
    /// point size classifies identically rather than depending on absolute units.
    func testSpatialLineBreak_ThresholdScalesWithGlyphHeight() {
        // 20pt type: a 20pt gap is now ordinary spacing, not a gutter.
        let ordinary = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 270, y: 700, w: 60, h: 20),
            currentLineBounds: CGRect(x: 50, y: 700, width: 200, height: 20),
            currentLineY: 710
        )
        XCTAssertEqual(ordinary, .none)

        // The same 20pt gap at 10pt type exceeds 1.5x height and is a gutter.
        let gutter = DocumentProcessor.spatialLineBreak(
            wordBounds: rect(x: 270, y: 700, w: 60, h: 10),
            currentLineBounds: CGRect(x: 50, y: 700, width: 200, height: 10),
            currentLineY: 705
        )
        XCTAssertEqual(gutter, .horizontalGap)
    }

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

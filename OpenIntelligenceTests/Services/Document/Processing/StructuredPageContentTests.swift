import XCTest
@testable import OpenIntelligenceEngine

/// Regression tests for `StructuredPageContent.effectiveContent`.
///
/// `effectiveContent` decides what survives a low-quality structured parse. Until 2026-08-08 it
/// *chose* between the structured elements and the recovered raw text, so a page where the parse
/// captured one table kept the table and silently discarded the prose the parser had already
/// re-OCR'd for exactly that purpose. A scanned datasheet could ship with most of the page absent
/// from chunks, from FTS5 and from the vector index, with only a log warning to show for it.
///
/// These tests need no fixture and no Vision call, so they are the tightest available guard on that
/// behaviour. The format fixtures in `IngestionFormatCoverageTests` cover the same merge through the
/// real pipeline, where it depends on OCR actually driving `qualityScore` below the threshold.
final class StructuredPageContentTests: XCTestCase {

    // MARK: - Builders

    private func table(
        rows: [[String]],
        page: Int = 1,
        caption: String? = nil
    ) -> StructuredElement {
        .table(
            TableData(
                pageNumber: page,
                rows: rows,
                headerRow: rows.first,
                caption: caption,
                detectedEntities: []
            )
        )
    }

    private func page(
        elements: [StructuredElement],
        rawText: String,
        quality: Double,
        number: Int = 1
    ) -> StructuredPageContent {
        StructuredPageContent(
            pageNumber: number,
            elements: elements,
            rawText: rawText,
            qualityScore: quality,
            figureReferences: []
        )
    }

    private func paragraphTexts(_ elements: [StructuredElement]) -> [String] {
        elements.compactMap { element in
            if case let .paragraph(text, _) = element { return text }
            return nil
        }
    }

    // MARK: - The guards

    func testHighQualityParse_ReturnsElementsUntouched() {
        // A parse that captured the page does not get raw text stapled onto it, even when raw text
        // is present. Otherwise every good page would carry a duplicate of itself.
        let content = page(
            elements: [table(rows: [["Part", "Torque"], ["Caliper bolt", "85 Nm"]])],
            rawText: "Part Torque Caliper bolt 85 Nm and a great deal of surrounding prose",
            quality: 0.9
        )

        XCTAssertEqual(content.effectiveContent.count, 1)
        XCTAssertEqual(content.effectiveContent.first?.elementType, "table")
    }

    func testEmptyRawText_ReturnsElementsUntouched() {
        let content = page(
            elements: [table(rows: [["Part", "Torque"]])],
            rawText: "",
            quality: 0.1
        )

        XCTAssertEqual(content.effectiveContent.count, 1)
        XCTAssertEqual(content.effectiveContent.first?.elementType, "table")
    }

    func testLowQualityWithNoStructure_FallsBackToRawText() {
        // Paragraphs and titles are not "structure" for this purpose: if the parse found no table
        // and no list, the raw OCR text is the better representation of the page.
        let content = page(
            elements: [.title(text: "Brake Service", pageNumber: 1)],
            rawText: "Brake Service\nInspect the caliper before every rotation.",
            quality: 0.2
        )

        let result = content.effectiveContent
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.elementType, "paragraph")
        XCTAssertEqual(
            paragraphTexts(result).first,
            "Brake Service\nInspect the caliper before every rotation."
        )
    }

    // MARK: - The defect this file exists for

    func testLowQualityWithTable_KeepsTableAndAppendsUncoveredProse() {
        // The 2026-08-08 defect: this returned ONLY the table, dropping every line of recovered
        // prose. The table is the cheap part to notice missing; the prose left silently.
        let content = page(
            elements: [table(rows: [["Part", "Torque"], ["Caliper bolt", "85 Nm"]])],
            rawText: """
            Part Torque
            Caliper bolt 85 Nm
            Torque values assume clean dry threads.
            Replace the retaining clip whenever the caliper is removed.
            """,
            quality: 0.3
        )

        let result = content.effectiveContent

        XCTAssertEqual(result.count, 2, "The table must survive and the recovered prose must be appended")
        XCTAssertEqual(result.first?.elementType, "table")

        let recovered = paragraphTexts(result).joined(separator: "\n")
        XCTAssertTrue(
            recovered.contains("Torque values assume clean dry threads."),
            "Prose the table does not cover was discarded"
        )
        XCTAssertTrue(
            recovered.contains("Replace the retaining clip whenever the caliper is removed."),
            "Prose the table does not cover was discarded"
        )
    }

    func testLowQualityWithTable_DoesNotDuplicateCoveredLines() {
        // The merge is not "append everything": lines the structured elements already carry must
        // not come back a second time, or the chunk inventory doubles and MMR starts treating the
        // page as its own near-duplicate.
        let content = page(
            elements: [table(rows: [["Part", "Torque"], ["Caliper bolt", "85 Nm"]])],
            rawText: "Part Torque\nCaliper bolt 85 Nm",
            quality: 0.3
        )

        let result = content.effectiveContent
        XCTAssertEqual(result.count, 1, "Every raw line was already covered by the table")
        XCTAssertEqual(result.first?.elementType, "table")
    }

    func testLowQualityWithList_CountsAsStructureAndMerges() {
        let content = page(
            elements: [.list(items: ["Check pad thickness", "Check rotor runout"], pageNumber: 1)],
            rawText: """
            Check pad thickness
            Check rotor runout
            Discard any pad below three millimetres.
            """,
            quality: 0.3
        )

        let result = content.effectiveContent
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.elementType, "list")
        XCTAssertTrue(
            paragraphTexts(result).joined().contains("Discard any pad below three millimetres.")
        )
    }

    func testRecoveredText_DropsVeryShortLines() {
        // Lines of two characters or fewer are OCR noise far more often than content, and each one
        // that survives becomes a chunk boundary candidate.
        let content = page(
            elements: [table(rows: [["Part", "Torque"]])],
            rawText: """
            Part Torque
            x
            ..
            Torque values assume clean dry threads.
            """,
            quality: 0.3
        )

        let recovered = paragraphTexts(content.effectiveContent).joined(separator: "\n")
        XCTAssertTrue(recovered.contains("Torque values assume clean dry threads."))
        XCTAssertFalse(recovered.contains("\nx"), "Single-character OCR noise was kept")
        XCTAssertFalse(recovered.contains(".."), "Punctuation-only OCR noise was kept")
    }

    // MARK: - hasStructuredContent, which gates the branch above

    func testHasStructuredContent_OnlyTablesAndLists() {
        XCTAssertTrue(
            page(elements: [table(rows: [["a", "b"]])], rawText: "x", quality: 0.1)
                .hasStructuredContent
        )
        XCTAssertTrue(
            page(elements: [.list(items: ["a"], pageNumber: 1)], rawText: "x", quality: 0.1)
                .hasStructuredContent
        )
        XCTAssertFalse(
            page(elements: [.title(text: "a", pageNumber: 1)], rawText: "x", quality: 0.1)
                .hasStructuredContent
        )
        XCTAssertFalse(
            page(elements: [.figure(description: "a", pageNumber: 1)], rawText: "x", quality: 0.1)
                .hasStructuredContent
        )
        XCTAssertFalse(
            page(elements: [], rawText: "x", quality: 0.1).hasStructuredContent
        )
    }

    // MARK: - Coverage normalisation

    func testNormalizedForCoverage_IgnoresWhitespaceAndPunctuation() {
        // The structured serialisation and the raw OCR text differ in spacing and punctuation for
        // the same content, so the coverage check has to compare on letters and digits only.
        XCTAssertEqual(
            StructuredPageContent.normalizedForCoverage("Caliper bolt — 85 Nm"),
            StructuredPageContent.normalizedForCoverage("caliper bolt 85 nm")
        )
        XCTAssertEqual(StructuredPageContent.normalizedForCoverage(" \n\t "), "")
    }
}

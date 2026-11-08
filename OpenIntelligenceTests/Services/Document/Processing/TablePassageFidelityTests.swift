//
//  TablePassageFidelityTests.swift
//  OpenIntelligenceTests
//
//  A table reaches the model with every row. On 2026-11-07 "How much DHA is recommended?" retrieved the summary of a
//  paper's Table 1, which listed only the first two rows ("Representative rows"), under the title "International
//  Journal of", the page-1 masthead; DHA was row 3, and the answer gave row 1's dose. These pin the three fixes: a
//  summary lists every row or none, page furniture is never a title, and a retrieved summary brings its table.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class TablePassageFidelityTests: XCTestCase {
    private let supplements = TableData(
        pageNumber: 10,
        rows: [
            ["Nutraceuticals", "Suggested Daily Intake"],
            ["PhyCB/Spirulina", "100-200 mg/15-30 g"],
            ["Ferulic Acid", "500-1000 mg"],
            ["DHA", "1-2 g"],
            ["Vitamin D", "2000-10,000 IU"],
        ],
        headerRow: ["Nutraceuticals", "Suggested Daily Intake"],
        caption: nil,
        detectedEntities: [])

    func testASummaryListsEveryRowWithItsLabel() {
        let summary = DocumentProcessor().buildSemanticTableSummary(
            tableData: supplements, tableTitle: "Table 1", filename: "paper.pdf", sectionPath: [],
            documentCategory: .scientificPaper)
        // A two-column table is read as name-value pairs ("DHA: 1-2 g"), a wider one as named rows.
        XCTAssertTrue(summary.contains("DHA: 1-2 g") || summary.contains("DHA | Suggested Daily Intake: 1-2 g"), summary)
        XCTAssertTrue(summary.contains("Vitamin D: 2000-10,000 IU") || summary.contains("Vitamin D | Suggested Daily Intake"), summary)
        XCTAssertTrue(summary.contains("PhyCB/Spirulina"), summary)
        XCTAssertFalse(summary.contains("Representative rows"), summary)
    }

    func testALongTableSummaryListsNoRowsRatherThanSome() {
        let rows = [["Item", "Value"]] + (1...120).map { ["Item number \($0) with a longer name", "\($0) mg per day"] }
        let table = TableData(pageNumber: 1, rows: rows, headerRow: ["Item", "Value"], caption: nil, detectedEntities: [])
        let summary = DocumentProcessor().buildSemanticTableSummary(
            tableData: table, tableTitle: "Table 2", filename: "x.pdf", sectionPath: [], documentCategory: .general)
        XCTAssertTrue(summary.contains("It has 120"), summary)
        XCTAssertFalse(summary.contains("Item number 1 with"), summary)
    }

    func testPageFurnitureIsNeverATitle() {
        for line in [
            "International Journal of", "10 of 27", "Page 3", "Int. J. Mol. Sci. 2020, 21, 3624",
            "Int. J. lest. ocl. 2020, 21. 3024",
            "doi:10.3390/ijms21103624", "© 2020 by the authors", "Results and",
        ] {
            XCTAssertTrue(DocumentProcessor.isPageFurnitureLabel(line), line)
        }
        for heading in [
            "Introduction", "2.1 Data Collection", "Table 1. Nutraceuticals", "Results and Discussion", "Vitamin D",
            "Vitamin A", "Appendix A", "Part 1 of 2", "Step 3 of 7", "Sign In", "Power On", "What to Look For",
        ] {
            XCTAssertFalse(DocumentProcessor.isPageFurnitureLabel(heading), heading)
        }
        XCTAssertNil(DocumentProcessor().sanitizeStructuredLabel("International Journal of"))
        XCTAssertEqual(
            DocumentProcessor().resolveTableTitle(tableData: supplements, sectionTitle: "International Journal of"), "Table")
    }

    private func passage(
        _ document: UUID, index: Int, type: ChunkSemanticType, group: String?, text: String
    ) -> DocumentChunk {
        DocumentChunk(
            documentId: document, content: text, embedding: [],
            metadata: ChunkMetadata(chunkIndex: index, siblingGroupId: group, chunkType: type))
    }

    private func retrieved(_ chunk: DocumentChunk, score: Float = 0.9) -> RetrievedChunk {
        RetrievedChunk(chunk: chunk, similarityScore: score, rank: 1, sourceDocument: "paper.pdf", pageNumber: 10)
    }

    func testARetrievedSummaryBringsItsTableInItsPlace() {
        let doc = UUID()
        let table = passage(doc, index: 40, type: .tableStructural, group: "table-p10-t1", text: "ROW 3: DHA | 1-2 g")
        let summary = passage(doc, index: 41, type: .tableSemantic, group: "table-p10-t1", text: "Representative rows")
        let row = passage(doc, index: 42, type: .tableStructural, group: "table-p10-t1", text: "DHA: 1-2 g")
        let other = passage(doc, index: 3, type: .prose, group: nil, text: "Intro")
        let result = RAGService.withTablesForSummaries(
            [retrieved(summary), retrieved(other, score: 0.5)], allChunks: [other, table, summary, row])
        XCTAssertEqual(result.map(\.chunk.id), [table.id, other.id])
        XCTAssertEqual(result.first?.similarityScore, 0.9)
    }

    func testASummaryWhoseTableIsAlreadyACandidateIsDropped() {
        let doc = UUID()
        let table = passage(doc, index: 1, type: .tableStructural, group: "g", text: "ROW 1: a | b")
        let summary = passage(doc, index: 2, type: .tableSemantic, group: "g", text: "summary")
        let result = RAGService.withTablesForSummaries([retrieved(table), retrieved(summary)], allChunks: [table, summary])
        XCTAssertEqual(result.map(\.chunk.id), [table.id])
    }

    func testASummaryWhoseTableIsMissingStays() {
        let summary = passage(UUID(), index: 2, type: .tableSemantic, group: "g", text: "summary")
        let result = RAGService.withTablesForSummaries([retrieved(summary)], allChunks: [summary])
        XCTAssertEqual(result.map(\.chunk.id), [summary.id])
    }

    func testANumberedCaptionIsTheTablesTitle() {
        XCTAssertEqual(
            DocumentProcessor.numberedTableCaption(
                "Table 1. Nutraceuticals with potential for prevention/control of Parkinson's disease. Suggested daily intake ranges."),
            "Table 1: Nutraceuticals with potential for prevention/control of Parkinson's disease")
        XCTAssertEqual(DocumentProcessor.numberedTableCaption("TABLE IV: Results"), "TABLE IV: Results")
        XCTAssertNil(DocumentProcessor.numberedTableCaption("International Journal of"))
        let captioned = TableData(
            pageNumber: 10, rows: [["a", "b"], ["c", "d"]], headerRow: nil,
            caption: "Table 2. Doses by age.", detectedEntities: [])
        XCTAssertEqual(
            DocumentProcessor().resolveTableTitle(tableData: captioned, sectionTitle: "International Journal of"),
            "Table 2: Doses by age")
    }

    func testTheCaptionLineNearestAboveATableIsFound() {
        // Normalized boxes, origin at the bottom left: the table spans y 0.3 to 0.6.
        let table = CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.3)
        let paragraphs: [(text: String, box: CGRect)] = [
            ("Table 1. Nutraceuticals and doses.", CGRect(x: 0.1, y: 0.62, width: 0.8, height: 0.03)),
            ("Table 9. Far away on the page.", CGRect(x: 0.1, y: 0.95, width: 0.8, height: 0.03)),
            ("Some body text that mentions Table 1.", CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05)),
        ]
        XCTAssertEqual(
            StructuredDocumentParser.tableCaption(tableBox: table, paragraphs: paragraphs), "Table 1. Nutraceuticals and doses.")
        XCTAssertNil(StructuredDocumentParser.tableCaption(tableBox: table, paragraphs: [paragraphs[1]]))
        let below: [(text: String, box: CGRect)] = [("Table 3: Results.", CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.05))]
        XCTAssertEqual(StructuredDocumentParser.tableCaption(tableBox: table, paragraphs: below), "Table 3: Results.")
    }

    func testTwoTablesSharingAGroupEachBringTheirOwnRowsAndNotThePerRowPassages() {
        let doc = UUID()
        let table1 = passage(doc, index: 10, type: .tableStructural, group: "table-p3-table", text: "ROW 1: a | 1")
        let summary1 = passage(doc, index: 11, type: .tableSemantic, group: "table-p3-table", text: "s1")
        let row1 = passage(doc, index: 12, type: .tableStructural, group: "table-p3-table", text: "COMPATIBILITY ROW: Table\nVALUES: a=1")
        let table2 = passage(doc, index: 13, type: .tableStructural, group: "table-p3-table", text: "ROW 1: b | 2")
        let summary2 = passage(doc, index: 14, type: .tableSemantic, group: "table-p3-table", text: "s2")
        let all = [table1, summary1, row1, table2, summary2]
        XCTAssertEqual(RAGService.withTablesForSummaries([retrieved(summary2)], allChunks: all).map(\.chunk.id), [table2.id])
        XCTAssertEqual(RAGService.withTablesForSummaries([retrieved(summary1)], allChunks: all).map(\.chunk.id), [table1.id])
    }

    func testATablePartThatRankedLowerMovesUpToTheSummarysPlace() {
        let doc = UUID()
        let table = passage(doc, index: 1, type: .tableStructural, group: "g", text: "ROW 1: a | b")
        let summary = passage(doc, index: 2, type: .tableSemantic, group: "g", text: "summary")
        let other = passage(doc, index: 9, type: .prose, group: nil, text: "x")
        let result = RAGService.withTablesForSummaries(
            [retrieved(summary), retrieved(other, score: 0.6), retrieved(table, score: 0.2)], allChunks: [table, summary, other])
        XCTAssertEqual(result.map(\.chunk.id), [table.id, other.id])
        XCTAssertEqual(result.first?.similarityScore, 0.9)
    }

    func testARowNamesTheColumnOfEachValue() {
        XCTAssertEqual(
            DocumentProcessor.namedRowCells(["DHA", "1-2 g", "3 g"], headers: ["Nutrient", "Daily Dose", "Upper Limit"]),
            "DHA | Daily Dose: 1-2 g | Upper Limit: 3 g")
        XCTAssertEqual(DocumentProcessor.namedRowCells(["a", "b"], headers: ["Column 1", "Column 2"]), "a | b")
        XCTAssertEqual(DocumentProcessor.namedRowCells(["a", "", "c"], headers: ["X", "Y", "Z"]), "a | Z: c")
    }

    /// A stored row names its columns, and the file does not: the highlighter strips the names so the row is still
    /// found in the page word for word.
    func testARowWithColumnNamesIsStillFoundOnItsPage() {
        let passage = "TABLE: Table 1\nHEADERS: Nutrient | Daily Dose | Upper Limit\nROW 1: DHA | Daily Dose: 1-2 g | Upper Limit: 3 g"
        XCTAssertEqual(PassageLocator.withoutImportLabels(passage), "DHA 1-2 g 3 g")
    }

    func testARunningHeaderIsFoundOnEveryPageAndLeftOut() {
        let pages: [(page: Int, text: String)] = [
            (1, "Int. J. Mol. Sci. 2020, 21, 3624 1 of 27"), (1, "WARNING"), (1, "Body text of page one."),
            (2, "Int. J. Mol. Sci. 2020, 21, 3624 2 of 27"), (2, "WARNING"), (2, "Body text of page two."),
            (3, "Int. J. Mol. Sci. 2020, 21, 3624 3 of 27"), (3, "More body text."),
        ]
        let keys = DocumentProcessor.runningLineKeys(in: pages)
        XCTAssertTrue(DocumentProcessor.isRunningElement("Int. J. Mol. Sci. 2020, 21, 3624 2 of 27", runningKeys: keys))
        XCTAssertFalse(DocumentProcessor.isRunningElement("WARNING", runningKeys: keys), "a repeated heading without a number")
        XCTAssertFalse(DocumentProcessor.isRunningElement("Body text of page two.", runningKeys: keys))
        XCTAssertTrue(DocumentProcessor.isRunningElement("12 of 40", runningKeys: []), "a page counter on its own")
        XCTAssertFalse(DocumentProcessor.isRunningElement("Results and", runningKeys: []), "a wrapped line is the heading test's call")
    }

    /// Gate C counts a value as grounded only when a row about the question holds it, when the passages have one.
    func testAValueFromAnotherRowIsNotGroundedForTheQuestion() {
        let table = """
            TABLE: Table 1: Nutraceuticals
            HEADERS: Nutraceuticals | Suggested Daily Intake
            ROW 1: PhyCB/Spirulina | Suggested Daily Intake: 100-200 mg/15-30 g
            ROW 2: Ferulic Acid | Suggested Daily Intake: 500-1000 mg
            ROW 3: DHA | Suggested Daily Intake: 1-2 g
            """
        let question = "How much DHA is recommended?"
        func misplaced(_ answer: String, passages: [String] = [table]) -> [String] {
            VerificationGateService.valuesFromOtherRows(
                question: question, answerValues: NumericValueExtractor.mentions(inAnswer: answer), passages: passages)
        }
        XCTAssertFalse(misplaced("Two values are mentioned for DHA: 100-200 mg/15-30 g [S1]").isEmpty)
        XCTAssertTrue(misplaced("DHA is recommended at 1-2 g a day [S1].").isEmpty)
        // The same value also stated in prose about the question is left to the other checks.
        XCTAssertTrue(
            misplaced("DHA: 100-200 mg.", passages: [table, "Some trials gave DHA at 100-200 mg a day."]).isEmpty)
        // A question no row is about is not judged this way.
        XCTAssertTrue(
            VerificationGateService.valuesFromOtherRows(
                question: "How much taurine is recommended?",
                answerValues: NumericValueExtractor.mentions(inAnswer: "Taurine: 500-1000 mg"), passages: [table]
            ).isEmpty)
    }

    func testAWideTablesPairsSayWhichRowTheyBelongTo() {
        let table = TableData(
            pageNumber: 2,
            rows: [["Nutrient", "Daily Dose", "Upper Limit"], ["DHA", "1-2 g", "3 g"], ["Zinc", "30-80 mg", "100 mg"]],
            headerRow: ["Nutrient", "Daily Dose", "Upper Limit"], caption: nil, detectedEntities: [])
        let pairs = (table.keyValuePairs ?? []).map { "\($0.key): \($0.value)" }
        XCTAssertEqual(pairs, ["DHA Daily Dose: 1-2 g", "DHA Upper Limit: 3 g", "Zinc Daily Dose: 30-80 mg", "Zinc Upper Limit: 100 mg"])
    }

    /// A table cell is read from the page's own characters when they agree with what Vision read (5.8).
    func testACellIsReadFromTheTextLayerWhenItAgrees() {
        let words = [
            TextLayerWord(text: "1\u{2013}2", box: CGRect(x: 0.40, y: 0.50, width: 0.05, height: 0.02)),
            TextLayerWord(text: "g", box: CGRect(x: 0.46, y: 0.50, width: 0.01, height: 0.02)),
            TextLayerWord(text: "DHA", box: CGRect(x: 0.10, y: 0.50, width: 0.05, height: 0.02)),
        ]
        let cell = CGRect(x: 0.35, y: 0.48, width: 0.2, height: 0.06)
        XCTAssertEqual(StructuredDocumentParser.textLayerText(in: cell, words: words), "1\u{2013}2 g")
        XCTAssertNil(StructuredDocumentParser.textLayerText(in: CGRect(x: 0.8, y: 0.1, width: 0.1, height: 0.1), words: words))
        // Vision's misread of the same cell agrees closely enough; another cell's text does not.
        XCTAssertTrue(StructuredDocumentParser.textLayerAgrees("1\u{2013}2 g", withVision: "1-28"))
        XCTAssertTrue(StructuredDocumentParser.textLayerAgrees("3624", withVision: "3024"))
        XCTAssertTrue(StructuredDocumentParser.textLayerAgrees("Zinc", withVision: ""))
        XCTAssertFalse(StructuredDocumentParser.textLayerAgrees("Magnesium", withVision: "Vitamin D"))
        XCTAssertFalse(StructuredDocumentParser.textLayerAgrees("", withVision: "DHA"))
    }

    /// Rows run together on one line (a long table's part, split again by words) are each read on their own.
    func testRowsRunTogetherOnOneLineAreReadSeparately() {
        let runTogether = "ROW 1: PhyCB/Spirulina | 100-200 mg/15-30 g ROW 2: Ferulic Acid | 500-1000 mg ROW 3: DHA | 1-2 g ROW 4: Vitamin D | 2000-10,000 IU"
        let misplaced = VerificationGateService.valuesFromOtherRows(
            question: "How much DHA is recommended?",
            answerValues: NumericValueExtractor.mentions(inAnswer: "DHA: 100-200 mg/15-30 g"), passages: [runTogether])
        XCTAssertFalse(misplaced.isEmpty)
    }

    func testRunningLinesAreTakenOutOfALongerParagraph() {
        let page = "Int. J. Test. Sci. 2020, 21, 3624 2 of 2\nSeveral nutrients have been proposed.\nTheir doses differ."
        XCTAssertEqual(
            DocumentProcessor.withoutRunningLines(page, runningKeys: []),
            "Several nutrients have been proposed.\nTheir doses differ.")
        XCTAssertEqual(DocumentProcessor.withoutRunningLines("Plain text.", runningKeys: []), "Plain text.")
    }

    /// OCR clean-up no longer rewrites a capital L or a unit's l as a 1.
    func testOCRCleanupKeepsLettersBeforeDigits() {
        let parser = StructuredDocumentParser.shared
        XCTAssertEqual(parser.cleanOCRText("L4-L5 disc"), "L4-L5 disc")
        XCTAssertEqual(parser.cleanOCRText("Lot L1234"), "Lot L1234")
        XCTAssertEqual(parser.cleanOCRText("add ml5 drops"), "add ml5 drops")
        XCTAssertEqual(parser.cleanOCRText("page l2 of 3"), "page 12 of 3")
        XCTAssertEqual(parser.cleanOCRText("4O5 units"), "405 units")
    }

    /// Superscripts and subscripts survive normalization as "^" and "_" rather than fusing into the number.
    func testScriptsSurviveNormalization() {
        XCTAssertEqual(OCRConfiguration.normalizeExtractedText("10\u{00B3} cells"), "10^3 cells")
        XCTAssertEqual(OCRConfiguration.normalizeExtractedText("x10\u{2079}/L"), "x10^9/L")
        XCTAssertEqual(OCRConfiguration.normalizeExtractedText("H\u{2082}O"), "H_2O")
        XCTAssertEqual(OCRConfiguration.normalizeExtractedText("\u{00BD} cup"), "1/2 cup")
        XCTAssertEqual(OCRConfiguration.normalizeExtractedText("speci\u{00AD}\nfication"), "specification")
        XCTAssertEqual(OCRConfiguration.markingScriptsAndFractions("plain 103"), "plain 103")
    }

    /// A line that is only a number is a page number at a page's edge and a table cell anywhere else.
    func testBareNumberLinesAreKeptAwayFromThePageEdges() {
        let page = "Intro line\nSecond line\nDHA\n1-2\nZinc\n120 80\nMore text\nLast words\n42"
        let normalized = OCRConfiguration.normalizeExtractedText(page)
        XCTAssertTrue(normalized.contains("\n1-2\n"), normalized)
        XCTAssertTrue(normalized.contains("120 80"), normalized)
        XCTAssertFalse(normalized.hasSuffix("42"), normalized)
    }

    /// A long paragraph is taken from the text layer when most of its words match what Vision read.
    func testALongParagraphAgreesByWords() {
        let layer = String(repeating: "Supplemental intakes of zinc should be coupled with copper daily to prevent deficiency. ", count: 4)
        var vision = layer.replacingOccurrences(of: "copper", with: "cooper")
        XCTAssertTrue(StructuredDocumentParser.textLayerAgreesForParagraph(layer, withVision: vision))
        vision = String(repeating: "Figure legends describe the mitochondrial pathway in neurons and glia today. ", count: 4)
        XCTAssertFalse(StructuredDocumentParser.textLayerAgreesForParagraph(layer, withVision: vision))
    }

    /// The ll-ligature repair fixes "wil" and leaves real words alone in a document that trips it.
    func testLigatureRepairLeavesRealWordsAlone() {
        let text = "The patient wil folow the plan and wil alow rest. Paralysis was noted on filing. "
            + "Smith et al found a 5 mil film. The colision was smal and overal minor, so it wil heal."
        let repaired = OCRConfiguration.repairLLLigature(text)
        XCTAssertTrue(repaired.contains("will follow"), repaired)
        XCTAssertTrue(repaired.contains("Paralysis"), repaired)
        XCTAssertTrue(repaired.contains("filing"), repaired)
        XCTAssertTrue(repaired.contains("et al found"), repaired)
        XCTAssertTrue(repaired.contains("5 mil film"), repaired)
    }

    /// Fact Check does not support a claim whose values belong to another table row.
    func testFactCheckDoesNotSupportAnotherRowsValue() {
        let table = "ROW 1: PhyCB/Spirulina | Suggested Daily Intake: 100-200 mg/15-30 g\nROW 3: DHA | Suggested Daily Intake: 1-2 g"
        let claim = RAGVerificationResult.ClaimResult(
            claim: "100-200 mg/15-30 g", verdict: .supported, confidence: 0.84, details: "", citations: [], resolvedEvidenceIds: [])
        let checked = VerificationGateService.markingValuesFromOtherRows(
            claim, query: "How much DHA is recommended?", passages: [table])
        XCTAssertEqual(checked.verdict, .unsupported)
        let right = RAGVerificationResult.ClaimResult(
            claim: "DHA: 1-2 g a day", verdict: .supported, confidence: 0.9, details: "", citations: [], resolvedEvidenceIds: [])
        XCTAssertEqual(
            VerificationGateService.markingValuesFromOtherRows(right, query: "How much DHA is recommended?", passages: [table]).verdict,
            .supported)
    }

    /// A line of numbers alone is not a running header, however often such lines appear (measured regression, 2026-11-08).
    func testLinesOfNumbersAreNotRunningHeaders() {
        let pages: [(page: Int, text: String)] = (1...4).map { ($0, "0.25 0.50 1.0\nBody text on page \($0).") }
        XCTAssertFalse(DocumentProcessor.isRunningElement("0.25 0.50 1.0", runningKeys: DocumentProcessor.runningLineKeys(in: pages)))
        // A reference line in a body is kept; only a heading is refused for looking like a citation.
        XCTAssertEqual(DocumentProcessor.withoutRunningLines("Smith J. 2019, 21, 1-10.", runningKeys: []), "Smith J. 2019, 21, 1-10.")
    }

    /// Every reference's DOI has the same digit-masked key; a page of references is not a running footer.
    func testReferenceDOIsAreNotRunningLines() {
        let pages: [(page: Int, text: String)] = (1...4).map {
            ($0, "doi:10.1080/14737175.20\($0)6.120491\($0)\nInt. J. Mol. Sci. 2020, 21, 3624 \($0) of 27\nBody \($0).")
        }
        let keys = DocumentProcessor.runningLineKeys(in: pages)
        XCTAssertFalse(DocumentProcessor.isRunningElement("doi:10.1080/14737175.2016.1204914", runningKeys: keys))
        XCTAssertTrue(DocumentProcessor.isRunningElement("Int. J. Mol. Sci. 2020, 21, 3624 9 of 27", runningKeys: keys))
    }

    /// A table passage split for the token limit keeps its label lines in every part.
    func testTableLabelLinesAreSeparatedFromTheRows() {
        let text = "[Part 2]\nTABLE: Leases\nHEADERS: Unit | notice | deposit\nROW 24: 24 | notice: 54 days | deposit: 2400 dollars"
        let (labels, body) = DocumentProcessor.tableLabelLines(of: text)
        XCTAssertEqual(labels, ["TABLE: Leases", "HEADERS: Unit | notice | deposit"])
        XCTAssertEqual(body, "ROW 24: 24 | notice: 54 days | deposit: 2400 dollars")
        XCTAssertTrue(DocumentProcessor.tableLabelLines(of: "Plain prose.\nMore.").labels.isEmpty)
    }

    /// A row's column names come out for the source lookup even in a part without its HEADERS line.
    func testColumnNamesComeOutOfARowWithoutHeaders() {
        let passage = "[Part 2]\nROW 24: 24 | notice: 54 days | deposit: 2400 dollars"
        XCTAssertEqual(PassageLocator.withoutImportLabels(passage), "24 54 days 2400 dollars")
    }

    /// A text-layer reading cut short by its box, or with lines interleaved, is not the paragraph Vision read.
    func testATruncatedOrScrambledParagraphIsNotTaken() {
        let vision = "Supplemental intakes of zinc should be coupled with copper daily to prevent a deficiency in adults."
        XCTAssertFalse(StructuredDocumentParser.textLayerAgreesForParagraph("Supplemental intakes of zinc should be", withVision: vision))
        let scrambled = "Supplemental be coupled intakes with of copper zinc daily should to prevent adults a in deficiency."
        XCTAssertFalse(StructuredDocumentParser.textLayerAgreesForParagraph(scrambled, withVision: vision))
        XCTAssertTrue(StructuredDocumentParser.textLayerAgreesForParagraph(vision, withVision: vision.replacingOccurrences(of: "copper", with: "cooper")))
        // A short line with two misread words is still the same line.
        XCTAssertTrue(
            StructuredDocumentParser.textLayerAgreesForParagraph(
                "Int. J. Test. Sci. 2020, 21, 3624", withVision: "Int. J. lest. ocl. 2020, 21. 3624"))
    }

    /// The import's own "ROW n" labels are not a table's keywords.
    func testRowLabelsAreNotKeywords() {
        let rows = (1...25).map { "ROW \($0): Valve \($0) | Pressure: \($0 * 10) psi" }.joined(separator: "\n")
        let keywords = DocumentProcessor().extractKeywordsFromStructuredElement(rows, type: "table")
        XCTAssertFalse(keywords.contains { $0.hasPrefix("ROW") }, "\(keywords)")
    }

    /// A footer printed word for word on every page is a running line however few letters it has; a reference's DOI
    /// is not, and a dashed page number is furniture.
    func testExactRepeatedFootersAreRunningLines() {
        let pages: [(page: Int, text: String)] = (1...4).map {
            ($0, "doi:10.1001/jama.2019.21118\nVol. 12, No. 3, 2021\ndoi:10.1080/1473717\($0).2016.120491\($0)\nBody \($0).")
        }
        let keys = DocumentProcessor.runningLineKeys(in: pages)
        XCTAssertTrue(DocumentProcessor.isRunningElement("doi:10.1001/jama.2019.21118", runningKeys: keys))
        XCTAssertTrue(DocumentProcessor.isRunningElement("Vol. 12, No. 3, 2021", runningKeys: keys))
        XCTAssertFalse(DocumentProcessor.isRunningElement("doi:10.1080/14737175.2016.1204914", runningKeys: keys))
        XCTAssertTrue(DocumentProcessor.isRunningElement("- 12 -", runningKeys: []))
    }

    /// A part split again keeps its number.
    func testAPartSplitAgainKeepsItsNumber() {
        XCTAssertEqual(DocumentProcessor.partNumber(of: "[Part 2]\nTABLE: x"), "2")
        XCTAssertEqual(DocumentProcessor.partNumber(of: "[Part 2.1]\nx"), "2.1")
        XCTAssertNil(DocumentProcessor.partNumber(of: "TABLE: x"))
        XCTAssertEqual(PassageLocator.withoutImportLabels("[Part 2.1]\nPlain cell"), "Plain cell")
    }

    /// In a table laid out the other way round (rows are groups, columns nutrients), a value in the DHA column is the
    /// DHA value, even when another table has a row named DHA.
    func testAColumnNamedForTheSubjectHoldsItsValue() {
        let misplaced = VerificationGateService.valuesFromOtherRows(
            question: "How much DHA is recommended?",
            answerValues: NumericValueExtractor.mentions(inAnswer: "DHA: 1-2 g"),
            passages: ["ROW 1: Adults | DHA: 1-2 g | EPA: 0.5 g", "ROW 1: DHA | Upper Limit: 3 g"])
        XCTAssertTrue(misplaced.isEmpty, "\(misplaced)")
    }

    /// A column named like the question ("Daily Dose") does not make every row about it.
    func testAColumnNamedLikeTheQuestionDoesNotGroundAnotherRow() {
        let misplaced = VerificationGateService.valuesFromOtherRows(
            question: "What daily dose of DHA is recommended?",
            answerValues: NumericValueExtractor.mentions(inAnswer: "DHA: 100-200 mg/15-30 g"),
            passages: ["ROW 1: PhyCB/Spirulina | Daily Dose: 100-200 mg/15-30 g\nROW 3: DHA | Daily Dose: 1-2 g"])
        XCTAssertFalse(misplaced.isEmpty)
    }

    /// A text layer that prints no spaces between words is not taken over Vision's spaced reading.
    func testATextLayerWithoutSpacesIsNotTaken() {
        let vision = "which permits unrestricted use, distribution, and reproduction in any medium"
        XCTAssertFalse(
            StructuredDocumentParser.textLayerAgreesForParagraph(
                "whichpermitsunrestricteduse,distribution,andreproductioninanymedium", withVision: vision))
        XCTAssertFalse(StructuredDocumentParser.textLayerAgrees("Vitamin D2000IU", withVision: "Vitamin D 2000 IU"))
    }
}

//
//  PageTextRepairTests.swift
//  OpenIntelligenceTests
//
//  Two ways a PDF page's text was lost before it was stored, found 2026-11-08 by checks written from the page images
//  of eight PDFs (scripts/ingestion_unit_tests.py): a font without its ligature glyphs ("gures", "de ned", "infuence"),
//  and a region Vision's document reading put in no title, table, list or paragraph (the PAH paper's Table 1, 48 rows).
//

import CoreGraphics
import XCTest

@testable import OpenIntelligence

final class PageTextRepairTests: XCTestCase {
    // MARK: - Ligatures

    func testLostLigaturesAreRestoredOnAPageThatShowsTheLoss() {
        let page = """
            The infuence of the gut microbiota on infammatory disease is signifcant. Both authors made the gures and \
            the semi de ned media were prepared as described. The efects were diferent between groups.
            """
        let repaired = LigatureRepair.repair(page)
        for word in ["influence", "inflammatory", "significant", "figures", "effects", "different"] {
            XCTAssertTrue(repaired.contains(word), "\(word) not restored in: \(repaired)")
        }
        XCTAssertFalse(repaired.contains("infuence"))
        XCTAssertTrue(repaired.hasPrefix("The influence"), "the rest of the text keeps its form: \(repaired)")
    }

    func testAPageWithoutTheLossIsUntouched() {
        // Names and short words that a ligature would turn into other words ("Dong" as "Doffing", "re" as "fire") on
        // pages printed correctly, from the same eight PDFs.
        let page = """
            Dong and Chang reported the results in Int J Mol Sci. Res Int was re analysed for the ing and ed forms; \
            the data were collected at baseline and after twelve weeks of treatment in every group.
            """
        XCTAssertEqual(LigatureRepair.repair(page), page)
    }

    func testOneRepairableWordAloneIsNotEnough() {
        let page = "The specifc protocol was followed for every sample collected during the trial at each of the sites."
        XCTAssertEqual(LigatureRepair.repair(page), page, "a single odd word is not evidence of a broken font")
    }

    func testTextLayerWordsJoinOnlyOnOneLine() {
        func word(_ text: String, x: CGFloat, y: CGFloat) -> TextLayerWord {
            TextLayerWord(text: text, box: CGRect(x: x, y: y, width: CGFloat(text.count) * 0.01, height: 0.01))
        }
        let words = [
            word("The", x: 0.1, y: 0.9), word("efects", x: 0.15, y: 0.9), word("of", x: 0.23, y: 0.9),
            word("the", x: 0.26, y: 0.9), word("de", x: 0.3, y: 0.9), word("ned", x: 0.33, y: 0.9),
            word("medium", x: 0.37, y: 0.9), word("were", x: 0.1, y: 0.88), word("diferent.", x: 0.15, y: 0.88),
        ]
        let repaired = LigatureRepair.repair(words: words).map(\.text)
        XCTAssertEqual(repaired, ["The", "effects", "of", "the", "defined", "medium", "were", "different."])
    }

    // MARK: - Text no container holds

    func testABorderlessTableOutsideEveryContainerKeepsEachValueOnItsRow() {
        // Two rows of a table in the left half, a paragraph Vision did hold on the right.
        func cell(_ text: String, _ x: CGFloat, _ y: CGFloat) -> TextLayerWord {
            TextLayerWord(text: text, box: CGRect(x: x, y: y, width: 0.03, height: 0.01))
        }
        let items = [
            cell("NaP", 0.05, 0.80), cell("5.98", 0.15, 0.80), cell("128", 0.25, 0.80), cell("102", 0.35, 0.80),
            cell("AcPy", 0.05, 0.78), cell("8.97", 0.15, 0.78), cell("152", 0.25, 0.78), cell("151", 0.35, 0.78),
            cell("held", 0.6, 0.80), cell("text", 0.64, 0.80),
        ]
        let held = CGRect(x: 0.55, y: 0.7, width: 0.4, height: 0.2)
        let blocks = StructuredDocumentParser.uncoveredBlocks(items: items, covered: [held]).map(\.text)
        XCTAssertEqual(blocks, ["NaP | 5.98 | 128 | 102\nAcPy | 8.97 | 152 | 151"])
    }

    func testEverythingHeldGivesNothing() {
        let items = [TextLayerWord(text: "word", box: CGRect(x: 0.1, y: 0.5, width: 0.05, height: 0.01))]
        XCTAssertEqual(
            StructuredDocumentParser.uncoveredBlocks(items: items, covered: [CGRect(x: 0, y: 0, width: 1, height: 1)]).count,
            0)
    }

    func testTwoColumnsOfLooseProseStayApart() {
        var items: [TextLayerWord] = []
        let left = "one two three four five six seven eight nine".split(separator: " ")
        let right = "alpha beta gamma delta epsilon zeta eta theta iota".split(separator: " ")
        for (index, word) in left.enumerated() {
            items.append(
                TextLayerWord(
                    text: String(word), box: CGRect(x: 0.05 + CGFloat(index) * 0.045, y: 0.5, width: 0.04, height: 0.01)
                ))
        }
        for (index, word) in right.enumerated() {
            items.append(
                TextLayerWord(
                    text: String(word), box: CGRect(x: 0.55 + CGFloat(index) * 0.045, y: 0.5, width: 0.04, height: 0.01)
                ))
        }
        let blocks = StructuredDocumentParser.uncoveredBlocks(items: items, covered: []).map(\.text)
        XCTAssertEqual(blocks, [left.joined(separator: " "), right.joined(separator: " ")])
    }

    // MARK: - Tables from word positions

    /// Words laid out as a table: each cell's words at its column's x, one line per row, `y` falling down the page.
    private func layout(_ lines: [(y: CGFloat, cells: [(x: CGFloat, text: String)])]) -> [TextLayerWord] {
        lines.flatMap { line in
            line.cells.flatMap { cell -> [TextLayerWord] in
                var x = cell.x
                return cell.text.split(separator: " ").map { word in
                    defer { x += CGFloat(word.count) * 0.008 + 0.004 }
                    return TextLayerWord(text: String(word), box: CGRect(x: x, y: line.y, width: CGFloat(word.count) * 0.008, height: 0.01))
                }
            }
        }
    }

    func testATableIsReadFromWordPositionsWithItsHeaderAndWrappedLabel() {
        let words = layout([
            (0.90, [(0.30, "No"), (0.50, "ADHD")]),
            (0.888, [(0.30, "ADHD"), (0.50, "(n = 3026)"), (0.10, "Characteristic"), (0.70, "|SMD|")]),
            (0.86, [(0.10, "Incident MCI or dementia,"), (0.30, "6259 (3.4)"), (0.50, "203 (6.7)"), (0.70, "0.15")]),
            (0.849, [(0.10, "No. (%)")]),
            (0.82, [(0.10, "Depression, No. (%)"), (0.30, "14 186 (7.7)"), (0.50, "993 (32.8)"), (0.70, "0.66")]),
            (0.80, [(0.10, "Anxiety disorder"), (0.30, "11 994 (6.5)"), (0.50, "864 (28.6)"), (0.70, "0.61")]),
            (0.78, [(0.10, "Cancer, No. (%)"), (0.30, "3065 (1.7)"), (0.50, "109 (3.6)"), (0.70, "0.12")]),
        ])
        let tables = TextLayerTableDetector.tables(in: words)
        XCTAssertEqual(tables.count, 1)
        guard let table = tables.first else { return }
        XCTAssertEqual(table.header, ["Characteristic", "No ADHD", "ADHD (n = 3026)", "|SMD|"])
        XCTAssertEqual(table.rows.first, ["Incident MCI or dementia, No. (%)", "6259 (3.4)", "203 (6.7)", "0.15"])
        XCTAssertEqual(table.rows[1], ["Depression, No. (%)", "14 186 (7.7)", "993 (32.8)", "0.66"])
        XCTAssertEqual(table.rows.count, 4)
    }

    func testTwoColumnsOfProseAreNotATable() {
        var lines: [(y: CGFloat, cells: [(x: CGFloat, text: String)])] = []
        for index in 0..<12 {
            lines.append((0.9 - CGFloat(index) * 0.014, [(0.08, "the results of the study were consistent"), (0.55, "across every group that was measured here")]))
        }
        XCTAssertEqual(TextLayerTableDetector.tables(in: layout(lines)), [])
    }

    // MARK: - Running lines

    func testAFooterWithAnEnDashMatchesItsNormalizedLine() {
        let pages = (1...6).map { (page: $0, text: "Body text on page \($0).\nBiochemical Society Transactions (2021) 49 541\u{2013}550") }
        let keys = DocumentProcessor.runningLineKeys(in: pages)
        XCTAssertTrue(DocumentProcessor.isRunningLine("Biochemical Society Transactions (2021) 49 541-550", runningKeys: keys))
    }

    func testABareWebAddressOnEveryPageIsARunningLine() {
        let pages = (1...6).map { (page: $0, text: "Results on page \($0) were reported.\nwww.impactjournals.com/oncotarget") }
        let keys = DocumentProcessor.runningLineKeys(in: pages)
        XCTAssertTrue(DocumentProcessor.isRunningLine("www.impactjournals.com/oncotarget", runningKeys: keys))
        XCTAssertFalse(DocumentProcessor.isBareWebAddress("see www.example.com for details"))
    }

    func testATableGoesBeforeTheFirstParagraphBelowItInItsColumn() {
        // Vision order: left paragraph (top), left paragraph (bottom), right paragraph. A table in the left column
        // between the two left paragraphs.
        let elements = ["left top", "left bottom", "right", "TABLE"]
        let boxes: [CGRect?] = [
            CGRect(x: 0.05, y: 0.7, width: 0.4, height: 0.2), CGRect(x: 0.05, y: 0.1, width: 0.4, height: 0.2),
            CGRect(x: 0.55, y: 0.1, width: 0.4, height: 0.8), CGRect(x: 0.05, y: 0.4, width: 0.4, height: 0.2),
        ]
        XCTAssertEqual(
            StructuredDocumentParser.inPageOrder(elements, boxes: boxes, flow: [0, 1, 2]),
            ["left top", "TABLE", "left bottom", "right"])
    }

    func testABoxWhoseTextLeftOutItsNumbersDoesNotHoldThem() {
        // Vision's paragraph box over the whole table, its text only the header.
        func cell(_ text: String, _ x: CGFloat, _ y: CGFloat) -> TextLayerWord {
            TextLayerWord(text: text, box: CGRect(x: x, y: y, width: 0.03, height: 0.01))
        }
        let items = [
            cell("Retention", 0.15, 0.84), cell("NaP", 0.05, 0.80), cell("5.98", 0.15, 0.80), cell("128", 0.25, 0.80),
            cell("AcPy", 0.05, 0.78), cell("8.97", 0.15, 0.78), cell("152", 0.25, 0.78),
        ]
        let region = StructuredDocumentParser.CoveredRegion(
            box: CGRect(x: 0.0, y: 0.7, width: 0.45, height: 0.2), words: ["retention"])
        let blocks = StructuredDocumentParser.uncoveredBlocks(items: items, regions: [region]).map(\.text)
        XCTAssertEqual(blocks, ["NaP | 5.98 | 128\nAcPy | 8.97 | 152"])
    }

    func testABoxThatMisreadOneWordStillHoldsIt() {
        let words = (0..<10).map { TextLayerWord(text: "word\($0)", box: CGRect(x: 0.05 + CGFloat($0) * 0.04, y: 0.5, width: 0.03, height: 0.01)) }
        var said = Set(words.map { $0.text.lowercased() })
        said.remove("word3")  // OCR read it differently
        let region = StructuredDocumentParser.CoveredRegion(box: CGRect(x: 0, y: 0.4, width: 1, height: 0.2), words: said)
        XCTAssertEqual(StructuredDocumentParser.uncoveredBlocks(items: words, regions: [region]).count, 0)
    }

    // MARK: - Refuting review, 2026-11-08

    /// The layout text of a page loses the header lines its margin rule found, and nothing else.
    func testLayoutTextLosesThePagesMarginLinesOnly() {
        let layout = "Int. J. Test. Sci. 2020, 21, 3624\n1. Introduction\nSeveral nutrients were proposed.\n12"
        let kept = DocumentProcessor.withoutLines(layout, matching: ["Int.  J. Test. Sci. 2020, 21, 3624", "12"])
        XCTAssertEqual(kept, "1. Introduction\nSeveral nutrients were proposed.\n12")
    }

    /// A table stores "10³" as "10^3": the raw word is held by the table's stored text, not stored again.
    func testASuperscriptInATableIsHeldByItsStoredForm() {
        let words = [
            TextLayerWord(text: "10³", box: CGRect(x: 0.1, y: 0.5, width: 0.03, height: 0.01)),
            TextLayerWord(text: "ﬁbres", box: CGRect(x: 0.2, y: 0.5, width: 0.05, height: 0.01)),
        ]
        var region = StructuredDocumentParser.CoveredRegion(
            box: CGRect(x: 0, y: 0.4, width: 1, height: 0.2),
            words: StructuredDocumentParser.coverageTokens("ROW 1: Count | 10^3 fibres"))
        region.allowsMisreads = false
        XCTAssertEqual(StructuredDocumentParser.uncoveredBlocks(items: words, regions: [region]).map(\.text), [])
    }

    func testAJoinRefusedAcrossALineBreakDoesNotCountTowardTheGate() {
        let page = "Both authors prepared all of the gures shown here, and the media were de\nned in the methods section above."
        XCTAssertEqual(LigatureRepair.repair(page), page, "only one repair can apply, so the page is not repaired")
    }

    func testPunctuationBetweenPiecesIsNotJoinedAway() {
        let page = "The infuence and the infammatory response were signifcant, as were the de, ned limits of the study."
        let repaired = LigatureRepair.repair(page)
        XCTAssertTrue(repaired.contains("de, ned"), repaired)
        XCTAssertTrue(repaired.contains("influence"), repaired)
    }

    func testALongTextCellStaysInItsTable() {
        let long = "mitochondrial disorders with stroke like episodes"
        let words = layout(
            (0..<5).map { index in
                (0.9 - CGFloat(index) * 0.02, [(0.05, "Agent\(index)"), (0.15, long), (0.62, "10 mg"), (0.75, "0.1\(index)")])
            })
        let table = TextLayerTableDetector.tables(in: words).first
        XCTAssertEqual(table?.rows.first?[1], long, "a long cell is a cell, not the page's other column")
    }

    func testASectionLabelOnTheNextLineIsANewRow() {
        // Rows one line apart (PDFKit boxes about a line tall), a one-cell section label between finished rows.
        let words = layout([
            (0.900, [(0.10, "Label"), (0.30, "Overall"), (0.50, "ADHD"), (0.70, "SMD")]),
            (0.889, [(0.10, "Female"), (0.30, "107 266 (57.3)"), (0.50, "1866 (61.7)"), (0.70, "0.09")]),
            (0.878, [(0.10, "Race, No. (%)")]),
            (0.867, [(0.10, "Hispanic"), (0.30, "25 429 (13.6)"), (0.50, "193 (6.4)"), (0.70, "0.52")]),
            (0.856, [(0.10, "Incident MCI or"), (0.30, "6462 (3.4)"), (0.50, "203 (6.7)"), (0.70, "0.15")]),
            (0.845, [(0.10, "dementia")]),
            (0.834, [(0.10, "Cancer"), (0.30, "3174 (1.7)"), (0.50, "109 (3.6)"), (0.70, "0.12")]),
        ])
        let rows = TextLayerTableDetector.tables(in: words).first?.rows.map { $0[0] }
        XCTAssertEqual(rows, ["Female", "Race, No. (%)", "Hispanic", "Incident MCI or dementia", "Cancer"])
    }

    func testAListAboveATableKeepsItsPlace() {
        let elements = ["P", "LIST", "TABLE"]
        let boxes: [CGRect?] = [
            CGRect(x: 0.05, y: 0.1, width: 0.4, height: 0.2), CGRect(x: 0.05, y: 0.7, width: 0.4, height: 0.1),
            CGRect(x: 0.05, y: 0.4, width: 0.4, height: 0.2),
        ]
        XCTAssertEqual(StructuredDocumentParser.inPageOrder(elements, boxes: boxes, flow: [0]), ["LIST", "TABLE", "P"])
    }

    func testATableAtTheFootOfTheLeftColumnComesBeforeTheRightColumn() {
        let elements = ["left", "right", "TABLE"]
        let boxes: [CGRect?] = [
            CGRect(x: 0.05, y: 0.5, width: 0.4, height: 0.4), CGRect(x: 0.55, y: 0.1, width: 0.4, height: 0.8),
            CGRect(x: 0.05, y: 0.1, width: 0.4, height: 0.3),
        ]
        XCTAssertEqual(StructuredDocumentParser.inPageOrder(elements, boxes: boxes, flow: [0, 1]), ["left", "TABLE", "right"])
    }

    func testUnspacedScriptsAndSequencesAreNotRunTogetherWords() {
        let japanese = String(repeating: "日本語の文章は単語の間に空白を入れずに書かれるのが普通です。", count: 20)
        XCTAssertFalse(DocumentProcessor.textLayerLacksWordSpaces(japanese))
        let primers = (0..<60).map { _ in "ACGTTGCATGCATGCAAGTC" }.joined(separator: " ")
        XCTAssertFalse(DocumentProcessor.textLayerLacksWordSpaces(primers))
        let runTogether = String(repeating: "theresultsshowedalowerrateofanxiety ", count: 20)
        XCTAssertTrue(DocumentProcessor.textLayerLacksWordSpaces(runTogether))
    }


    func testAFooterOfTextAndAPageNumberStaysARunningLine() {
        // Refuting review, 2026-11-08: trimming a page token off the key took a footer's only number away, so
        // "Smith et al. 12" stopped being a running line. The trim is gone; this keeps it gone.
        let pages = (1...20).map { (page: $0, text: "Body text of page \($0) with no repeats.\nSmith et al. \($0 + 10)") }
        XCTAssertTrue(DocumentProcessor.isRunningLine("Smith et al. 15", runningKeys: DocumentProcessor.runningLineKeys(in: pages)))
    }

    func testARepeatedSectionHeadingWithoutANumberStaysContent() {
        let pages = (1...6).map { (page: $0, text: "Dosage and Administration\nTake \($0) tablets with water.") }
        XCTAssertFalse(
            DocumentProcessor.isRunningLine("Dosage and Administration", runningKeys: DocumentProcessor.runningLineKeys(in: pages)))
    }

    func testPdfplumbersTextStrategyReadsAnAlignedGrid() {
        // Four lines of three left-aligned columns on a 612 x 792 point page, 12 points apart.
        func word(_ text: String, x: Double, line: Int) -> TextLayerWord {
            let top = 100.0 + Double(line) * 12
            return TextLayerWord(
                text: text,
                box: CGRect(x: x / 612, y: (792 - top - 9) / 792, width: Double(text.count) * 5 / 612, height: 9.0 / 792),
                pageSize: CGSize(width: 612, height: 792))
        }
        let words = [
            word("Compound", x: 72, line: 0), word("Time", x: 200, line: 0), word("Ion", x: 300, line: 0),
            word("NaP", x: 72, line: 1), word("5.98", x: 200, line: 1), word("128", x: 300, line: 1),
            word("AcPy", x: 72, line: 2), word("8.97", x: 200, line: 2), word("152", x: 300, line: 2),
            word("BaP", x: 72, line: 3), word("37.24", x: 200, line: 3), word("252", x: 300, line: 3),
        ]
        XCTAssertEqual(
            TextLayerTableDetector.pdfplumberGrid(words: words),
            [["Compound", "Time", "Ion"], ["NaP", "5.98", "128"], ["AcPy", "8.97", "152"], ["BaP", "37.24", "252"]])
    }

    func testMarginaliaDropsARunningHeadAndPageNumberButNotBodyOrATallTitle() {
        let elements: [StructuredElement] = [
            .paragraph(text: "Journal of Food and Drug Analysis 27 (2019) 815-824", pageNumber: 4),
            .title(text: "A Very Large Title Set Near The Top", pageNumber: 4),
            .paragraph(text: "Body text of the page, a long paragraph.", pageNumber: 4),
            .paragraph(text: "818", pageNumber: 4),
        ]
        let boxes: [CGRect?] = [
            CGRect(x: 0.1, y: 0.95, width: 0.6, height: 0.015),  // running head, top 5%
            CGRect(x: 0.1, y: 0.86, width: 0.8, height: 0.05),  // tall title (5% of the page): kept
            CGRect(x: 0.1, y: 0.15, width: 0.8, height: 0.65),  // body
            CGRect(x: 0.48, y: 0.03, width: 0.04, height: 0.012),  // page number, bottom
        ]
        XCTAssertEqual(StructuredDocumentParser.marginalia(elements: elements, boxes: boxes), [0, 3])
    }

    /// The last lines of a column that reach the footer zone are body text, not a footer; the running title beside them
    /// is a footer (fbioe p7, 2026-11-09).
    func testMarginaliaKeepsAColumnsLastLinesInTheFooterZone() {
        let elements: [StructuredElement] = [
            .paragraph(text: "Body text of the page, a long paragraph.", pageNumber: 7),
            .paragraph(text: "Growth of B. lactis HN019 was assessed in a bioreactor on medium 4 under controlled and fixed conditions of pH,", pageNumber: 7),
            .paragraph(text: "Frontiers in Bioengineering and Biotechnology", pageNumber: 7),
        ]
        let boxes: [CGRect?] = [
            CGRect(x: 0.05, y: 0.2, width: 0.9, height: 0.7),
            CGRect(x: 0.05, y: 0.09, width: 0.42, height: 0.025),
            CGRect(x: 0.05, y: 0.03, width: 0.4, height: 0.012),
        ]
        XCTAssertEqual(StructuredDocumentParser.marginalia(elements: elements, boxes: boxes), [2])
    }

    // MARK: - Footnotes and interrupted sentences

    /// Body words 0.012 tall across the page, and smaller footnote words inside `footnoteBox`.
    private func pageWords(footnoteBox: CGRect) -> [TextLayerWord] {
        var words: [TextLayerWord] = []
        for row in 0..<60 {
            words.append(TextLayerWord(text: "body", box: CGRect(x: 0.1, y: 0.2 + Double(row) * 0.012, width: 0.05, height: 0.012)))
        }
        for row in 0..<4 {
            words.append(TextLayerWord(
                text: "note", box: CGRect(x: footnoteBox.minX + 0.01, y: footnoteBox.minY + Double(row) * 0.009, width: 0.04, height: 0.009)))
        }
        return words
    }

    func testAFootnoteAtTheFootOfAColumnGoesAfterTheBody() {
        let footnoteBox = CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.05)
        let elements: [StructuredElement] = [
            .paragraph(text: "Goodwin presents snippets annotated to show when the gaze of a listener turns to meet", pageNumber: 1),
            .paragraph(text: "1 Research conducted during an internship.", pageNumber: 1),
            .paragraph(text: "the gaze of the speaker, and the speaker pauses.", pageNumber: 1),
        ]
        let boxes: [CGRect?] = [CGRect(x: 0.05, y: 0.2, width: 0.4, height: 0.6), footnoteBox, CGRect(x: 0.55, y: 0.2, width: 0.4, height: 0.6)]
        let order = StructuredDocumentParser.withFootnotesLastAndSentencesJoined(
            order: [0, 1, 2], elements: elements, boxes: boxes, words: pageWords(footnoteBox: footnoteBox))
        XCTAssertEqual(order, [0, 2, 1])
    }

    func testASentenceInterruptedByACaptionIsJoined() {
        let elements: [StructuredElement] = [
            .paragraph(text: "Exposure led to a significant increase in respect to untreated cells", pageNumber: 1),
            .paragraph(text: "Figure 7. IL-6 production in Caco-2 cells.", pageNumber: 1),
            .paragraph(text: "(CTR). The following addition decreased the secretion.", pageNumber: 1),
        ]
        let boxes: [CGRect?] = [
            CGRect(x: 0.05, y: 0.6, width: 0.4, height: 0.3), CGRect(x: 0.05, y: 0.3, width: 0.4, height: 0.05),
            CGRect(x: 0.55, y: 0.6, width: 0.4, height: 0.3),
        ]
        XCTAssertEqual(
            StructuredDocumentParser.withFootnotesLastAndSentencesJoined(order: [0, 1, 2], elements: elements, boxes: boxes, words: []),
            [0, 2, 1])
    }

    /// A list or a title after an unfinished line is not an interruption: the paragraph after it stays after it.
    func testAParagraphAfterAListOrTitleKeepsItsPlace() {
        let boxes: [CGRect?] = [
            CGRect(x: 0.05, y: 0.8, width: 0.9, height: 0.05), CGRect(x: 0.05, y: 0.6, width: 0.9, height: 0.15),
            CGRect(x: 0.05, y: 0.3, width: 0.9, height: 0.2),
        ]
        let withList: [StructuredElement] = [
            .paragraph(text: "The inclusion criteria were as follows", pageNumber: 1),
            .list(items: ["adults over 18", "no prior treatment"], pageNumber: 1),
            .paragraph(text: "Patients were then randomised to two arms.", pageNumber: 1),
        ]
        XCTAssertEqual(
            StructuredDocumentParser.withFootnotesLastAndSentencesJoined(order: [0, 1, 2], elements: withList, boxes: boxes, words: []),
            [0, 1, 2])
        let withTitle: [StructuredElement] = [
            .paragraph(text: "Materials and methods", pageNumber: 1),
            .title(text: "2.1 Samples", pageNumber: 1),
            .paragraph(text: "Samples were collected in 2019.", pageNumber: 1),
        ]
        XCTAssertEqual(
            StructuredDocumentParser.withFootnotesLastAndSentencesJoined(order: [0, 1, 2], elements: withTitle, boxes: boxes, words: []),
            [0, 1, 2])
    }

    // MARK: - Other scripts

    func testLinesInOtherScriptsInsideAnEnglishDocumentAreNotGarbage() {
        let lines = [
            "Η Αθήνα είναι η πρωτεύουσα της Ελλάδας και η μεγαλύτερη πόλη της χώρας.",
            "Москва является столицей России и крупнейшим городом страны.",
            "Война и мир (War and Peace)",
            "ירושלים היא בירת ישראל והעיר הגדולה ביותר במדינה.",
            "القاهرة هي عاصمة مصر وأكبر مدنها من حيث عدد السكان.",
            "東京は日本の首都であり、世界最大級の都市です。",
            "भारत की राजधानी नई दिल्ली है और यह एक बड़ा शहर है।",
        ]
        for line in lines {
            XCTAssertFalse(OCRConfiguration.isGarbageText(line, isLatinDocument: true), line)
        }
        XCTAssertTrue(OCRConfiguration.isGarbageText("Сатеgоrу Аssеmblу Ноusing Раrt", isLatinDocument: true))
    }

    func testAWordHyphenatedAcrossALineIsJoinedInAnyScript() {
        XCTAssertTrue(OCRConfiguration.normalizeExtractedText("столица мос-\nква и").contains("москва"))
        XCTAssertTrue(OCRConfiguration.normalizeExtractedText("ein groß-\nartiger Tag").contains("großartiger"))
    }

    func testAChineseTextLayerPassesTheQualityCheck() {
        let text = String(repeating: "本软件许可协议适用于随附的软件副本，请在使用前仔细阅读以下条款。用户同意遵守所有规定。", count: 6)
        XCTAssertTrue(DocumentProcessor.isMostlyUnspacedScript(text))
    }
}

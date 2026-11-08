//
//  TableFidelityTests.swift
//  OpenIntelligenceTests
//
//  A PDF table's passages keep each row's label with its values, and a page's running header is never the table's
//  caption or section (5.8). On the owner's iPhone on 2026-11-07 a journal review's Table 1
//  ("Nutraceuticals | Suggested Daily Intake") was stored under the title "International Journal of" (page 1's
//  masthead, carried nine pages as the section title), its summary passage listed only the first two rows, and
//  "How much DHA is recommended?" was answered with the first row's value. This draws a two-page text-layer PDF with
//  a running header on both pages and a three-column table on page 2, imports it through
//  `DocumentProcessor.processDocument`, and reads the passages it stores.
//

import CoreGraphics
import CoreText
import PDFKit
import XCTest

@testable import OpenIntelligence

@MainActor
final class TableFidelityTests: XCTestCase {
    /// The table drawn on page 2: label, then two values. En dashes on purpose, as journals print ranges.
    private static let header = ["Nutrient", "Daily Dose", "Upper Limit"]
    private static let rows: [[String]] = [
        ["DHA", "1\u{2013}2 g", "3 g"],
        ["Zinc", "30\u{2013}80 mg", "100 mg"],
        ["Taurine", "2\u{2013}6 g", "10 g"],
        ["Magnesium", "200\u{2013}400 mg", "600 mg"],
        ["Vitamin D", "2000\u{2013}10,000 IU", "10,000 IU"],
    ]
    private static let caption = "Table 1. Nutrient doses used in the fixture study. Suggested daily intake ranges."

    /// The running header, printed at the top of both pages as two runs on one baseline, as the journal does.
    private static func runningHeader(page: Int) -> (left: String, right: String) {
        ("Int. J. Test. Sci. 2020, 21, 3624", "\(page) of 2")
    }

    // MARK: - Fixture

    private func twoPageTablePDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "table-fidelity-\(UUID().uuidString.prefix(8)).pdf")
        // A new fingerprint on every run, so no saved checkpoint pages are loaded instead of parsed.
        let marker = UUID().uuidString
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let body = CTFontCreateWithName("Helvetica" as CFString, 10.5, nil)
        let bold = CTFontCreateWithName("Helvetica-Bold" as CFString, 10.5, nil)
        let small = CTFontCreateWithName("Helvetica" as CFString, 8.5, nil)

        func draw(_ text: String, x: CGFloat, y: CGFloat, font: CTFont) {
            let attributed = NSAttributedString(
                string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        func rule(y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
            context.setLineWidth(0.8)
            context.move(to: CGPoint(x: x0, y: y))
            context.addLine(to: CGPoint(x: x1, y: y))
            context.strokePath()
        }
        func header(page: Int) {
            let running = Self.runningHeader(page: page)
            draw(running.left, x: 54, y: 760, font: small)
            draw(running.right, x: 520, y: 760, font: small)
        }
        let prose = [
            "Several nutrients have been proposed for slowing the progression of the condition studied here.",
            "Their doses differ by two orders of magnitude, so each is listed with its usual daily range.",
            "Supplemental intakes above the upper limit have potential for toxicity and should be avoided.",
            "The ranges below were chosen for this fixture and carry no clinical meaning. \(marker)",
        ]

        // Page 1: a heading and prose only.
        context.beginPDFPage(nil)
        header(page: 1)
        draw("1. Introduction", x: 54, y: 700, font: bold)
        for (index, line) in (prose + prose).enumerated() {
            draw(line, x: 54, y: 676 - CGFloat(index) * 15, font: body)
        }
        context.endPDFPage()

        // Page 2: prose, the caption, then a ruled three-column table.
        context.beginPDFPage(nil)
        header(page: 2)
        for (index, line) in prose.enumerated() {
            draw(line, x: 54, y: 700 - CGFloat(index) * 15, font: body)
        }
        draw(Self.caption, x: 72, y: 600, font: body)
        let columns: [CGFloat] = [110, 270, 430]
        rule(y: 588, from: 90, to: 540)
        for (column, title) in Self.header.enumerated() {
            draw(title, x: columns[column], y: 574, font: bold)
        }
        rule(y: 566, from: 90, to: 540)
        for (rowIndex, row) in Self.rows.enumerated() {
            let y = 550 - CGFloat(rowIndex) * 18
            for (column, cell) in row.enumerated() {
                draw(cell, x: columns[column], y: y, font: body)
            }
        }
        rule(y: 550 - CGFloat(Self.rows.count) * 18 + 8, from: 90, to: 540)
        context.endPDFPage()
        context.closePDF()

        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Helpers

    /// A cell or line folded for comparison: dashes to "-", spacing squeezed, lowercased.
    private static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    /// Whether a label or title reads as the running header: its citation line, its "N of M", or its journal name.
    private static func isRunningHeader(_ text: String) -> Bool {
        let value = folded(text)
        return value.contains("int. j.") || value.contains("3624")
            || value.range(of: #"\b\d+ of 2\b"#, options: .regularExpression) != nil
            || value.contains("journal")
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func importFixture() async throws -> [DocumentProcessor.ProcessedChunk] {
        let processor = DocumentProcessor()
        let (_, chunks) = try await processor.processDocument(at: try twoPageTablePDF())
        XCTAssertFalse(chunks.isEmpty, "the import stored no passages")
        return chunks
    }

    // MARK: - Tests

    /// Every row's label and each of its values are on one line of one passage, and that line names the value's
    /// column. The table must arrive as a table: a run of prose that happens to hold the cells does not pass.
    func testEachRowKeepsItsLabelWithItsValuesOnOneLine() async throws {
        let chunks = try await importFixture()
        let tables = chunks.filter { $0.metadata.structureType == "table" }
        XCTAssertFalse(
            tables.isEmpty,
            "no table passage was stored; passages: \(chunks.map { String($0.text.prefix(80)) })")

        let tableLines = tables.flatMap { Self.lines($0.text) }.map(Self.folded)
        for row in Self.rows {
            let label = Self.folded(row[0])
            for (column, value) in row.enumerated().dropFirst() {
                let wanted = Self.folded(value)
                let holding = tableLines.filter { $0.contains(label) && $0.contains(wanted) }
                XCTAssertFalse(
                    holding.isEmpty,
                    "no table line holds \"\(row[0])\" with \"\(value)\"; lines: \(tableLines)")
                // "Row label: value", with the value's column named: "DHA | Daily Dose: 1-2 g | Upper Limit: 3 g".
                let header = Self.folded(Self.header[column])
                XCTAssertTrue(
                    holding.contains { $0.contains(header) },
                    "the line with \"\(row[0])\" and \"\(value)\" does not name its column \"\(Self.header[column])\": "
                        + "\(holding)")
            }
        }

        // The cells are the text layer's characters: the en dash's range and its unit survive, nothing is joined.
        let structural = tables.filter { $0.metadata.chunkType == .tableStructural }
        XCTAssertFalse(structural.isEmpty, "no structural table passage")
        let structuralText = Self.folded(structural.map(\.text).joined(separator: "\n"))
        XCTAssertTrue(structuralText.contains("1-2 g"), "\"1–2 g\" did not survive: \(structuralText)")
        XCTAssertFalse(structuralText.contains("1-28"), "\"1–2 g\" was read as \"1-28\": \(structuralText)")
        XCTAssertNotNil(
            structural.first?.structuredTable, "the structural passage lost its table payload")
        XCTAssertEqual(
            structural.first?.structuredTable?.rows.count, Self.rows.count,
            "the table payload does not hold the five rows: \(String(describing: structural.first?.structuredTable?.rows))")
    }

    /// A summary passage of the table either lists every row with its value or lists none. Two rows presented as
    /// "Representative rows" are what the model answered from on 2026-11-07.
    func testTableSummaryNeverListsASubsetOfRows() async throws {
        let chunks = try await importFixture()
        for summary in chunks where summary.metadata.chunkType == .tableSemantic {
            let text = Self.folded(summary.text)
            let rowsWithValues = Self.rows.filter { text.contains(Self.folded($0[1])) }
            guard !rowsWithValues.isEmpty else { continue }
            XCTAssertEqual(
                rowsWithValues.count, Self.rows.count,
                "the summary gives values for \(rowsWithValues.map { $0[0] }) of \(Self.rows.count) rows: \(summary.text)")
        }
    }

    /// The running header is no passage's caption, table title, section title or section path, and the table's title
    /// is its own caption.
    func testRunningHeaderIsNeverTheCaptionOrSection() async throws {
        let chunks = try await importFixture()
        for chunk in chunks {
            let labels = [chunk.metadata.tableTitle, chunk.metadata.sectionTitle].compactMap { $0 }
                + (chunk.metadata.sectionPath ?? [])
            for label in labels {
                XCTAssertFalse(
                    Self.isRunningHeader(label),
                    "page \(chunk.metadata.pageNumber ?? 0) passage is labelled with the running header: \"\(label)\"")
            }
            if chunk.metadata.structureType == "table" {
                let title = Self.folded(chunk.metadata.tableTitle ?? "")
                XCTAssertTrue(
                    title.contains("nutrient doses") || title.hasPrefix("table 1"),
                    "the table's title is \"\(chunk.metadata.tableTitle ?? "nil")\", not its caption")
                // The page-1 heading is a heading of page 1; it is not the table's title on page 2.
                XCTAssertFalse(title.contains("introduction"), "the table took page 1's heading as its title")
            }
        }
        // The header's text is not in any passage's body either (a passage that opens with it ranks for it).
        let bodies = chunks.map { Self.folded($0.text) }
        XCTAssertFalse(
            bodies.contains { $0.contains("int. j. test. sci.") },
            "a passage still holds the running header's citation line")
    }

    /// The context's line splitter keeps a stored row whole: what Standard's sentence extraction scores and packs for
    /// "How much DHA ...?" is the row with its label, never the value alone.
    func testEvidenceSplitterKeepsEachStoredRowWhole() async throws {
        let chunks = try await importFixture()
        let tables = chunks.filter { $0.metadata.chunkType == .tableStructural }
        XCTAssertFalse(tables.isEmpty, "no structural table passage")
        let units = tables.flatMap { EvidenceLineSplitter.lines(in: $0.text) }
            .flatMap(EvidenceLineSplitter.units(in:))
            .map(Self.folded)
        for row in Self.rows {
            let value = Self.folded(row[1])
            let withValue = units.filter { $0.contains(value) }
            XCTAssertFalse(withValue.isEmpty, "no unit holds \"\(row[1])\": \(units)")
            XCTAssertTrue(
                withValue.allSatisfy { $0.contains(Self.folded(row[0])) },
                "a unit holds \"\(row[1])\" without its label \"\(row[0])\": \(withValue)")
        }
    }
}

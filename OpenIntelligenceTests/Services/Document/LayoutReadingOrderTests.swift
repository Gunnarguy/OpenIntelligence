import PDFKit
import XCTest

@testable import OpenIntelligenceEngine

/// Pins reading order for multi-column PDFs against generated fixtures.
///
/// Device capture 2026-08-19 (`Psychiatry Clin Neurosci — Yagishita 2019`, container `4AF043A3`):
/// stored chunks interleaved the two columns line by line — "…unable to capture dynamic
/// moment-to-moment changes in behavior. **to second timescale, under which most behavioral
/// dynamics have** The dynamics of monoamine function occurs at the sub-second **been studied by
/// electrical re**…" — and glued fragments without separators ("disserotonin"). Downstream, the
/// damage manufactured 208 fake part-number candidates in ExtractiveQA and put four bibliography
/// chunks into a twelve-chunk retrieval.
///
/// The first suspected mechanism — `extractBlocksFromPDFPage` splitting `page.string` into lines
/// and re-finding them by forward-only search — was REFUTED by the four ordered fixtures below,
/// which all passed against it on 2026-08-20. Those fixtures draw each column in reading order,
/// so `page.string` comes back already ordered and never stresses the builder. The interleaved
/// fixture models the property real publisher PDFs have (content-stream order ≠ reading order);
/// its first run is the actual verdict. If it also passes, the device damage entered through a
/// different path — the Vision/OCR route or a downstream merge — and the hunt moves there.
/// These tests generate fixtures where correct reading order is known by construction, so the
/// assertion is against ground truth rather than against whatever PDFKit happens to emit.
final class LayoutReadingOrderTests: XCTestCase {

    // MARK: - Fixture generation

    /// Draw a single-page PDF with `columns` of text laid out left-to-right. Each column's
    /// sentences are distinct, so cross-column interleaving is detectable by substring order.
    private func makeColumnarPDF(columns: [[String]], fontSize: CGFloat = 10) throws -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw NSError(domain: "fixture", code: 1)
        }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "fixture", code: 2)
        }
        ctx.beginPDFPage(nil)

        let margin: CGFloat = 36
        let gutter: CGFloat = 24
        let columnWidth =
            (pageRect.width - 2 * margin - gutter * CGFloat(columns.count - 1))
            / CGFloat(columns.count)

        for (index, columnLines) in columns.enumerated() {
            let x = margin + CGFloat(index) * (columnWidth + gutter)
            var y = pageRect.height - margin - fontSize
            for line in columnLines {
                let attributed = NSAttributedString(
                    string: line,
                    attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)]
                )
                let ctLine = CTLineCreateWithAttributedString(attributed)
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(ctLine, ctx)
                y -= fontSize * 1.6
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()
        guard let document = PDFDocument(data: data as Data) else {
            throw NSError(domain: "fixture", code: 3)
        }
        return document
    }

    /// Index of `needle` in `haystack`, asserting presence.
    private func position(of needle: String, in haystack: String,
                          file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let range = haystack.range(of: needle) else {
            XCTFail("\"\(needle)\" missing from extracted text", file: file, line: line)
            return -1
        }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    /// Draw the same two columns but INTERLEAVE the draw calls (left line 1, right line 1,
    /// left line 2, …). Draw order is content-stream order, so `page.string` comes back scrambled
    /// while the geometry stays cleanly columnar — the property real publisher PDFs have and the
    /// ordered fixtures above cannot model. The four ordered tests all PASSED against the
    /// string-split block builder on 2026-08-20, refuting the first diagnosis; this fixture is the
    /// one that actually stresses reordering.
    private func makeInterleavedTwoColumnPDF(left: [String], right: [String]) throws -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw NSError(domain: "fixture", code: 1)
        }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "fixture", code: 2)
        }
        ctx.beginPDFPage(nil)
        let fontSize: CGFloat = 10
        for i in 0..<max(left.count, right.count) {
            let y = pageRect.height - 36 - fontSize - CGFloat(i) * fontSize * 1.6
            for (x, lines) in [(CGFloat(36), left), (CGFloat(330), right)] where i < lines.count {
                let attributed = NSAttributedString(
                    string: lines[i],
                    attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)]
                )
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
            }
        }
        ctx.endPDFPage(); ctx.closePDF()
        guard let document = PDFDocument(data: data as Data) else {
            throw NSError(domain: "fixture", code: 3)
        }
        return document
    }

    /// The device-capture failure shape, faithfully modelled: content-stream order interleaves the
    /// columns, and the extractor must reorder by geometry. Authored 2026-08-20 after the ordered
    /// fixtures passed; the first run of this test is the actual verdict on the block builder.
    func testInterleavedContentStreamIsReorderedByGeometry() async throws {
        let left = (1...5).map { "Iota left sentence number \($0) belongs to column one." }
        let right = (1...5).map { "Kappa right sentence number \($0) belongs to column two." }
        let pdf = try makeInterleavedTwoColumnPDF(left: left, right: right)
        let page = try XCTUnwrap(pdf.page(at: 0))
        // Precondition: the fixture must actually scramble page.string, or it proves nothing.
        let raw = try XCTUnwrap(page.string)
        let rawLastLeft = position(of: "Iota left sentence number 5", in: raw)
        let rawFirstRight = position(of: "Kappa right sentence number 1", in: raw)
        XCTAssertTrue(rawFirstRight < rawLastLeft,
                      "Fixture failed to model content-stream disorder; page.string is already ordered.")

        let result = try await LayoutAwareExtractor.shared.extractWithLayout(from: page, pageNumber: 1)
        let text = result.readingOrderText
        let lastLeft = left.map { position(of: String($0.prefix(28)), in: text) }.max() ?? -1
        let firstRight = right.map { position(of: String($0.prefix(29)), in: text) }.min() ?? -1
        XCTAssertTrue(lastLeft >= 0 && firstRight >= 0 && lastLeft < firstRight,
                      "Interleaved content stream was not reordered by geometry.\n---\n\(text)")
    }

    // MARK: - The regression

    /// Two columns; every left-column sentence must precede every right-column sentence.
    /// This is the exact failure shape from the device capture.
    func testTwoColumnPageReadsLeftColumnBeforeRight() async throws {
        let left = [
            "Alpha kappa one signals the first premise.",
            "Alpha kappa two extends the first premise.",
            "Alpha kappa three concludes the first premise.",
            "Alpha kappa four restates the first premise.",
            "Alpha kappa five closes the first column.",
        ]
        let right = [
            "Beta lambda one opens the second column.",
            "Beta lambda two continues the second column.",
            "Beta lambda three extends the second column.",
            "Beta lambda four deepens the second column.",
            "Beta lambda five closes the second column.",
        ]
        let pdf = try makeColumnarPDF(columns: [left, right])
        let page = try XCTUnwrap(pdf.page(at: 0))

        let result = try await LayoutAwareExtractor.shared.extractWithLayout(from: page, pageNumber: 1)
        let text = result.readingOrderText

        let lastLeft = left.map { position(of: String($0.prefix(20)), in: text) }.max() ?? -1
        let firstRight = right.map { position(of: String($0.prefix(19)), in: text) }.min() ?? -1
        XCTAssertTrue(
            lastLeft >= 0 && firstRight >= 0 && lastLeft < firstRight,
            "Columns interleaved: last left-column sentence at \(lastLeft), first right-column at \(firstRight).\n---\n\(text)"
        )
    }

    /// Mixed font sizes — a full-width heading above two columns. The heading must come first,
    /// and the columns must still not interleave. This is the "way more than two-column" case:
    /// size changes and full-width elements are where block detection typically breaks.
    func testHeadingAboveTwoColumnsKeepsOrder() async throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        var mediaBox = pageRect
        let ctx = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        ctx.beginPDFPage(nil)

        func draw(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat) {
            let attributed = NSAttributedString(
                string: string,
                attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, size, nil)]
            )
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
        }

        draw("Gamma headline spans the whole page width.", x: 36, y: 740, size: 18)
        var y: CGFloat = 700
        for line in ["Delta one starts the left column.", "Delta two continues the left column.",
                     "Delta three closes the left column."] {
            draw(line, x: 36, y: y, size: 10); y -= 16
        }
        y = 700
        for line in ["Epsilon one starts the right column.", "Epsilon two continues the right column.",
                     "Epsilon three closes the right column."] {
            draw(line, x: 330, y: y, size: 10); y -= 16
        }
        ctx.endPDFPage(); ctx.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(pdf.page(at: 0))

        let result = try await LayoutAwareExtractor.shared.extractWithLayout(from: page, pageNumber: 1)
        let text = result.readingOrderText

        let headline = position(of: "Gamma headline", in: text)
        let lastDelta = position(of: "Delta three", in: text)
        let firstEpsilon = position(of: "Epsilon one", in: text)
        XCTAssertTrue(headline >= 0 && headline < firstEpsilon, "Headline must precede column text.\n---\n\(text)")
        XCTAssertTrue(lastDelta >= 0 && lastDelta < firstEpsilon,
                      "Columns interleaved below the heading.\n---\n\(text)")
    }

    /// No line of the page may be silently dropped. The old block builder lost any line its
    /// forward-only string search failed to re-find; losing text is worse than misordering it.
    func testNoLineIsSilentlyDropped() async throws {
        let left = (1...6).map { "Zeta left sentence number \($0) is present." }
        let right = (1...6).map { "Eta right sentence number \($0) is present." }
        let pdf = try makeColumnarPDF(columns: [left, right])
        let page = try XCTUnwrap(pdf.page(at: 0))

        let result = try await LayoutAwareExtractor.shared.extractWithLayout(from: page, pageNumber: 1)
        for sentence in left + right {
            XCTAssertTrue(
                result.readingOrderText.contains(String(sentence.prefix(24))),
                "Dropped line: \(sentence)"
            )
        }
    }

    /// Single-column pages must keep their natural order — the fix must not regress the easy case.
    func testSingleColumnOrderIsPreserved() async throws {
        let lines = (1...8).map { "Theta paragraph sentence \($0) in strict order." }
        let pdf = try makeColumnarPDF(columns: [lines])
        let page = try XCTUnwrap(pdf.page(at: 0))

        let result = try await LayoutAwareExtractor.shared.extractWithLayout(from: page, pageNumber: 1)
        let text = result.readingOrderText
        var previous = -1
        for line in lines {
            let current = position(of: String(line.prefix(26)), in: text)
            XCTAssertGreaterThan(current, previous, "Order regressed at: \(line)\n---\n\(text)")
            previous = current
        }
    }
}

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO

/// Synthesises ingestion fixtures at test time instead of committing binaries.
///
/// Two reasons this draws the files rather than checking them in. The expectations and the pixels
/// come from the same `TableSpec`, so there is no hand-transcribed ground truth to drift; and this
/// repository lives in iCloud, which duplicates and re-stamps binary files in ways that have broken
/// builds before (`scripts/check_icloud_conflicts.sh`).
///
/// What this cannot do is imitate a real scan. A rasterised page rendered from vector text is
/// cleaner than anything a flatbed produces, so these fixtures catch *structural* regressions —
/// rows collapsing into one line, recovered prose being dropped, figures being discarded — and not
/// OCR accuracy loss. Every defect fixed on 2026-08-08 was structural.
final class IngestionFixtureFactory {

    // MARK: - Content specs

    /// A table plus the prose around it. Drawn into every visual fixture, and the source of every
    /// expectation about those fixtures.
    struct TableSpec {
        let caption: String
        let header: [String]
        let rows: [[String]]
        let prose: [String]

        /// Header first, then body rows. What "row/column association survived" is checked against.
        var allRows: [[String]] { [header] + rows }

        /// Characters actually drawn on the page. Extraction is measured as a fraction of this, so
        /// the tolerance is derived from the fixture rather than picked to make a test pass.
        var drawnCharacterCount: Int {
            let cells = allRows.flatMap { $0 }.reduce(0) { $0 + $1.count }
            let separators = allRows.reduce(0) { $0 + max(0, $1.count - 1) }
            return caption.count + cells + separators + prose.reduce(0) { $0 + $1.count }
        }

        /// Cells that must never be split from their row. Single-token values only, so a match is
        /// unambiguous when the extractor re-spaces a line.
        var rowAssociationProbes: [(label: String, value: String)] {
            rows.compactMap { row in
                guard row.count >= 2 else { return nil }
                return (row[0], row[row.count - 1])
            }
        }
    }

    /// Brake service data. Deliberately unlike anything in `Benchmarks/ResearchFixtures`, so a
    /// retrieval fixture leaking into an extraction assertion would be obvious.
    static let serviceTable = TableSpec(
        caption: "Table 1. Front caliper torque specification",
        header: ["Fastener", "Size", "Torque"],
        rows: [
            ["Caliper bracket bolt", "M12", "115 Nm"],
            ["Caliper guide pin", "M8", "35 Nm"],
            ["Bleed screw", "M7", "9 Nm"],
            ["Rotor retaining screw", "M6", "14 Nm"]
        ],
        prose: [
            "Torque values assume clean dry threads and a calibrated wrench.",
            "Replace the retaining clip whenever the caliper is removed from the bracket.",
            "Do not reuse a guide pin that shows scoring along the sealing surface."
        ]
    )

    /// A page of figures with no table at all. Exercises the `usedStructuredParsing` defect, which
    /// counted only tables and lists and so discarded every figure element on pages like this.
    static let figureCaptions = [
        "Figure 1. Caliper piston seal seating order",
        "Figure 2. Bleed sequence, near side to far side",
        "Figure 3. Guide pin boot orientation"
    ]

    // MARK: - Layout constants

    private enum Layout {
        static let pageSize = CGSize(width: 612, height: 792)   // US Letter at 72 dpi
        static let margin: CGFloat = 54
        static let bodyFontSize: CGFloat = 12
        static let captionFontSize: CGFloat = 11
        static let lineHeight: CGFloat = 22
        /// Column widths in characters. The table is drawn in a monospaced face and padded to these
        /// widths, so each row is a single text run whose columns still line up visually.
        ///
        /// One run per row matters. Drawing each cell as its own run at the same baseline leaves it
        /// to PDFKit whether the row comes back as one line or three, which would make a
        /// row-association assertion a test of the fixture rather than of the pipeline. Real
        /// technical PDFs encode tables this way.
        static let columnCharacterWidths = [26, 8, 8]
        /// Rasterised at 2x so OCR has enough pixels per glyph to be worth measuring.
        static let rasterScale: CGFloat = 2
    }

    // MARK: - Lifecycle

    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("oi-ingestion-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Not private: the Office fixtures live in an extension in `IngestionOfficeFixtures.swift`.
    func fixtureURL(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    // MARK: - PDF fixtures

    /// A PDF with a real embedded text layer. Takes the PDFKit path, no OCR.
    func textLayerPDF(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        let destination = fixtureURL("text_layer_table.pdf")
        try writePDF(to: destination) { context in
            drawTablePage(spec, in: context)
        }
        return destination
    }

    /// A PDF whose only content is a bitmap of the same page. No text layer, so the pipeline must
    /// fall through to Vision OCR — assert on `ocrPagesCount` to prove it did.
    func scannedPDF(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        let page = try rasterisePage { context in
            self.drawTablePage(spec, in: context)
        }
        let destination = fixtureURL("scanned_table.pdf")
        try writePDF(to: destination) { context in
            context.draw(page, in: CGRect(origin: .zero, size: Layout.pageSize))
        }
        return destination
    }

    /// Figures and captions, no table and no list.
    func figureOnlyPDF() throws -> URL {
        let destination = fixtureURL("figures_no_table.pdf")
        try writePDF(to: destination) { context in
            drawFigurePage(in: context)
        }
        return destination
    }

    /// Crisp table, blurred prose. The prose is legible enough for OCR to recover some of it and
    /// degraded enough to pull the page's quality score down, which is the condition under which
    /// `effectiveContent` has to merge rather than choose.
    func partiallyLegibleScanPDF(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        let crisp = try rasterisePage { context in
            self.drawTable(spec, in: context, topY: Layout.pageSize.height - Layout.margin)
        }
        // Transparent, so compositing it over the crisp layer degrades the prose and leaves the
        // table alone. An opaque layer would simply paint the table out.
        let proseOnly = try rasterisePage(opaque: false) { context in
            self.drawProse(spec.prose, in: context, topY: 260)
        }
        let blurredProse = try blur(proseOnly, radius: 2.2)

        let destination = fixtureURL("partially_legible_scan.pdf")
        let full = CGRect(origin: .zero, size: Layout.pageSize)
        try writePDF(to: destination) { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(full)
            context.draw(crisp, in: full)
            context.draw(blurredProse, in: full)
        }
        return destination
    }

    // MARK: - Image fixture

    /// A PNG of the table, standing in for a photographed or screenshotted document. This is the
    /// lane that collapsed every image into a single unbroken line until 2026-08-08.
    func tablePNG(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        let page = try rasterisePage { context in
            self.drawTablePage(spec, in: context)
        }
        let destination = fixtureURL("table_photo.png")
        guard let sink = CGImageDestinationCreateWithURL(
            destination as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw FixtureError.imageEncodingFailed
        }
        CGImageDestinationAddImage(sink, page, nil)
        guard CGImageDestinationFinalize(sink) else { throw FixtureError.imageEncodingFailed }
        return destination
    }

    // MARK: - Text-shaped fixtures

    func csv(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        let destination = fixtureURL("torque_specification.csv")
        let body = spec.allRows
            .map { row in row.map(Self.csvEscaped).joined(separator: ",") }
            .joined(separator: "\n")
        try (body + "\n").write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    private static func csvEscaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Fixtures that exist to pin a failure mode

    /// One second of 16 kHz mono silence, as a structurally valid WAV.
    ///
    /// Authoring real speech audio needs `say`, which fails from an agent shell with `-241` (no
    /// audio session). So this fixture cannot assert a transcription. What it can assert is that a
    /// file with nothing to transcribe fails loudly instead of producing an empty document, which is
    /// the property that actually matters for a silent-corruption sweep.
    func silentWAV() throws -> URL {
        let sampleRate: UInt32 = 16_000
        let sampleCount = Int(sampleRate)
        let bytesPerSample: UInt32 = 2
        let dataBytes = UInt32(sampleCount) * bytesPerSample

        var wav = Data()
        func append(_ ascii: String) { wav.append(contentsOf: Array(ascii.utf8)) }
        func append(le32 value: UInt32) { wav.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }
        func append(le16 value: UInt16) { wav.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }

        append("RIFF")
        append(le32: 36 + dataBytes)
        append("WAVE")
        append("fmt ")
        append(le32: 16)
        append(le16: 1)                                     // PCM
        append(le16: 1)                                     // mono
        append(le32: sampleRate)
        append(le32: sampleRate * bytesPerSample)           // byte rate
        append(le16: UInt16(bytesPerSample))                // block align
        append(le16: 16)                                    // bits per sample
        append("data")
        append(le32: dataBytes)
        wav.append(Data(count: Int(dataBytes)))

        let destination = fixtureURL("silence.wav")
        try wav.write(to: destination)
        return destination
    }

    /// A single-file `.pages`, which is what Pages on iOS always produces.
    ///
    /// The bytes are arbitrary on purpose. `extractTextFromIWorkDocument` only ever inspects
    /// directories, so a single-file iWork document never gets as far as having its contents read;
    /// the content cannot change the outcome. The test asserts the resulting throw.
    func singleFilePagesDocument() throws -> URL {
        let destination = fixtureURL("specification.pages")
        // A real single-file .pages is a ZIP. This carries the ZIP magic number so the fixture is
        // not rejected for a reason unrelated to what is being tested.
        var bytes = Data([0x50, 0x4B, 0x03, 0x04])
        bytes.append(Data(count: 512))
        try bytes.write(to: destination)
        return destination
    }

    /// A `.pages` *package*, the form the extractor does try to read, laid out the way modern iWork
    /// actually lays one out: an `Index` directory of `.iwa` blobs and no XML or text anywhere.
    func modernPagesPackage() throws -> URL {
        let destination = fixtureURL("specification_package.pages")
        let index = destination.appendingPathComponent("Index", isDirectory: true)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        try Data(count: 256).write(to: index.appendingPathComponent("Document.iwa"))
        try Data(count: 128).write(to: index.appendingPathComponent("Metadata.iwa"))
        try Data(count: 64).write(to: destination.appendingPathComponent("preview.jpg"))
        return destination
    }

    // MARK: - Drawing

    private func drawTablePage(_ spec: TableSpec, in context: CGContext) {
        var y = Layout.pageSize.height - Layout.margin
        y = drawTable(spec, in: context, topY: y)
        y -= Layout.lineHeight
        drawProse(spec.prose, in: context, topY: y)
    }

    @discardableResult
    private func drawTable(_ spec: TableSpec, in context: CGContext, topY: CGFloat) -> CGFloat {
        var y = topY
        draw(spec.caption, at: CGPoint(x: Layout.margin, y: y), size: Layout.captionFontSize, in: context)
        y -= Layout.lineHeight * 1.4

        for (rowIndex, row) in spec.allRows.enumerated() {
            draw(
                Self.paddedRow(row),
                at: CGPoint(x: Layout.margin, y: y),
                size: Layout.bodyFontSize,
                bold: rowIndex == 0,
                monospaced: true,
                in: context
            )
            // A ruled line under the header, so the raster fixture has the visual cue Vision uses to
            // decide this region is a table rather than three columns of unrelated text.
            if rowIndex == 0 {
                context.setStrokeColor(gray: 0, alpha: 1)
                context.setLineWidth(0.75)
                context.move(to: CGPoint(x: Layout.margin, y: y - 6))
                context.addLine(to: CGPoint(x: Layout.pageSize.width - Layout.margin, y: y - 6))
                context.strokePath()
            }
            y -= Layout.lineHeight
        }
        return y
    }

    @discardableResult
    private func drawProse(_ lines: [String], in context: CGContext, topY: CGFloat) -> CGFloat {
        var y = topY
        for line in lines {
            draw(line, at: CGPoint(x: Layout.margin, y: y), size: Layout.bodyFontSize, in: context)
            y -= Layout.lineHeight
        }
        return y
    }

    private func drawFigurePage(in context: CGContext) {
        var y = Layout.pageSize.height - Layout.margin
        draw("Caliper Service Diagrams", at: CGPoint(x: Layout.margin, y: y), size: 16, bold: true, in: context)
        y -= Layout.lineHeight * 2

        for caption in Self.figureCaptions {
            // A drawn shape, so the page has genuine non-text visual content to describe.
            let frame = CGRect(x: Layout.margin, y: y - 120, width: 240, height: 110)
            context.setStrokeColor(gray: 0.1, alpha: 1)
            context.setLineWidth(1.5)
            context.stroke(frame)
            context.strokeEllipse(in: frame.insetBy(dx: 40, dy: 22))
            context.move(to: CGPoint(x: frame.minX, y: frame.minY))
            context.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            context.strokePath()

            draw(caption, at: CGPoint(x: Layout.margin, y: y - 140), size: Layout.captionFontSize, in: context)
            y -= 180
        }
    }

    /// One row, padded to the column widths so a monospaced face renders aligned columns.
    private static func paddedRow(_ row: [String]) -> String {
        row.enumerated().map { index, cell -> String in
            // The last column is not padded: trailing spaces carry no visual information and some
            // extractors trim them anyway.
            guard index < row.count - 1 else { return cell }
            let width = Layout.columnCharacterWidths[min(index, Layout.columnCharacterWidths.count - 1)]
            let padding = max(1, width - cell.count)
            return cell + String(repeating: " ", count: padding)
        }.joined()
    }

    private func draw(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        bold: Bool = false,
        monospaced: Bool = false,
        in context: CGContext
    ) {
        let name: String
        if monospaced {
            name = bold ? "Menlo-Bold" : "Menlo"
        } else {
            name = bold ? "Helvetica-Bold" : "Helvetica"
        }
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    // MARK: - Rendering plumbing

    private func writePDF(to destination: URL, _ body: (CGContext) -> Void) throws {
        guard let consumer = CGDataConsumer(url: destination as CFURL) else {
            throw FixtureError.pdfContextUnavailable
        }
        var mediaBox = CGRect(origin: .zero, size: Layout.pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FixtureError.pdfContextUnavailable
        }
        context.beginPDFPage(nil)
        body(context)
        context.endPDFPage()
        context.closePDF()
    }

    private func rasterisePage(opaque: Bool = true, _ body: (CGContext) -> Void) throws -> CGImage {
        let width = Int(Layout.pageSize.width * Layout.rasterScale)
        let height = Int(Layout.pageSize.height * Layout.rasterScale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError.bitmapContextUnavailable
        }
        if opaque {
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.scaleBy(x: Layout.rasterScale, y: Layout.rasterScale)
        body(context)
        guard let image = context.makeImage() else { throw FixtureError.bitmapContextUnavailable }
        return image
    }

    private func blur(_ image: CGImage, radius: Double) throws -> CGImage {
        let source = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { throw FixtureError.blurUnavailable }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { throw FixtureError.blurUnavailable }
        // Blur expands the extent; crop back so the fixture keeps the page geometry.
        let cropped = output.cropped(to: source.extent)
        guard let rendered = CIContext(options: nil).createCGImage(cropped, from: source.extent) else {
            throw FixtureError.blurUnavailable
        }
        return rendered
    }

    enum FixtureError: Error {
        case pdfContextUnavailable
        case bitmapContextUnavailable
        case imageEncodingFailed
        case blurUnavailable
    }
}

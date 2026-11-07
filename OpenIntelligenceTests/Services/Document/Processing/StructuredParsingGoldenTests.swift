//
//  StructuredParsingGoldenTests.swift
//  OpenIntelligenceTests
//
//  Records exactly what `DocumentProcessor.processDocument` makes of a fixed set of PDFs: the document record and every
//  passage (text, parent text, metadata, table payload) and the entities it detected. It exists so breaking
//  `extractWithStructuredParsing` and `createStructureAwareChunks` into steps (2026-11-06,
//  `BenchmarkRuns/2026-11-06-decomposition/PLAN.md`) can be shown to change nothing: record before, record after,
//  compare with `scripts/golden_compare.py`.
//
//  Run only on purpose: it needs `TEST_RUNNER_OI_GOLDEN_DIR`, a folder whose `parse-fixtures/` holds the PDFs
//  (`scripts/golden_compare.py prepare-parse <dir>`), and skips without it. The interrupted-import checkpoints are
//  cleared before every document, or a second read would load pages instead of parsing them.
//

import CoreGraphics
import CoreText
import PDFKit
import XCTest

@testable import OpenIntelligence

final class StructuredParsingGoldenTests: XCTestCase {
    /// Keys that hold a clock time or a duration, so differ between two reads of the same file.
    private static let volatileKeys: Set<String> = []

    /// The 542-page Sportage manual is read only as far as this; its first 40 pages hold its tables, figures and
    /// specification lists, and the whole book would take most of an hour per pass.
    private static let longFileFirstPages: ClosedRange<Int> = 0...39

    func testRecordStructuredParsing() async throws {
        let (dir, label) = try GoldenRecording.destination()
        let factory = try IngestionFixtureFactory()
        addTeardownBlock { factory.cleanUp() }

        var inputs: [(name: String, url: URL, pages: ClosedRange<Int>?)] = []
        let fixtureDir = dir.appendingPathComponent("parse-fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no PDFs in \(fixtureDir.path)")
        for url in files {
            let pages = PDFDocument(url: url)?.pageCount ?? 0
            inputs.append((url.lastPathComponent, url, pages > 60 ? Self.longFileFirstPages : nil))
        }
        // Drawn at test time from the same specs the ingestion tests use: a text layer, a scan (OCR), figures only,
        // and a partly legible scan.
        inputs.append(("factory-text-layer.pdf", try factory.textLayerPDF(), nil))
        inputs.append(("factory-scanned.pdf", try factory.scannedPDF(), nil))
        inputs.append(("factory-figure-only.pdf", try factory.figureOnlyPDF(), nil))
        inputs.append(("factory-partly-legible.pdf", try factory.partiallyLegibleScanPDF(), nil))
        inputs.append(("greek.pdf", try textPDF(in: factory.root, name: "greek.pdf", pages: [Self.greek]), nil))
        inputs.append(("hebrew.pdf", try textPDF(in: factory.root, name: "hebrew.pdf", pages: [Self.hebrew]), nil))

        let checkpoints = AppSupportPaths.localCacheDir().appendingPathComponent(
            "IngestionCheckpoints", isDirectory: true)

        // One read of a document: its record, passages and entities, and the parser's live metrics at the end.
        func read(_ input: (name: String, url: URL, pages: ClosedRange<Int>?), ids: GoldenRecording.Ids) async throws
            -> [String: Any]
        {
                let processor = DocumentProcessor()
                let (document, chunks) = try await processor.processDocument(at: input.url, pageRange: input.pages)
                var passages: [Any] = []
                for chunk in chunks {
                    var entry: [String: Any] = [
                        "text": GoldenRecording.digest(chunk.text),
                        "metadata": try GoldenRecording.normalized(
                            chunk.metadata, dropping: Self.volatileKeys, ids: ids),
                    ]
                    if let parent = chunk.parentText { entry["parent"] = GoldenRecording.digest(parent) }
                    if let table = chunk.structuredTable {
                        entry["table"] = try GoldenRecording.normalized(table, dropping: Self.volatileKeys, ids: ids)
                    }
                    passages.append(entry)
                }
                let metrics = await MainActor.run { processor.liveMetrics }
                return [
                    "metrics": GoldenRecording.reflect(metrics, dropping: Self.volatileKeys, ids: ids),
                    "document": try GoldenRecording.normalized(document, dropping: Self.volatileKeys, ids: ids),
                    "passages": passages,
                    // A detected date is resolved against the clock: "9:14" on one fixture read as 21:14 at 13:45 and
                    // as 09:14 at 14:05 (2026-11-06), so a date entity is recorded by its type only.
                    "entities": processor.lastDetectedEntities.map { $0.type == "date" ? "date|(clock)" : "\($0.type)|\($0.value)" },
                ]
        }

        // The checkpoint files a read leaves, by name, as digests of their bytes.
        func checkpointFiles() -> [String: String] {
            var files: [String: String] = [:]
            let walker = FileManager.default.enumerator(at: checkpoints, includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { continue }
                files[url.lastPathComponent] = GoldenRecording.digest(data.base64EncodedString())
            }
            return files
        }

        func pass() async throws -> [String: Any] {
            var out: [String: Any] = [:]
            for input in inputs {
                try? FileManager.default.removeItem(at: checkpoints)
                let ids = GoldenRecording.Ids()
                var entry = try await read(input, ids: ids)
                // The checkpoints the read wrote, then a second read that resumes from them, as an import that was
                // interrupted does (`loadCheckpointedPage`, the prescan skipping saved pages). Added 2026-11-06 after a
                // review found the first version never reached that path.
                entry["checkpointFiles"] = checkpointFiles()
                entry["resumed"] = try await read(input, ids: GoldenRecording.Ids())
                out[input.name] = entry
            }
            try? FileManager.default.removeItem(at: checkpoints)
            return out
        }

        // `TEST_RUNNER_OI_GOLDEN_PASSES=1` records one pass, for runs after a baseline has shown the two passes agree.
        let passes = Int(ProcessInfo.processInfo.environment["OI_GOLDEN_PASSES"] ?? "") ?? 2
        let first = try await pass()
        let second = passes > 1 ? try await pass() : first
        let unsteady = GoldenRecording.differences(first, second)
        XCTAssertTrue(unsteady.isEmpty, "two passes in one run differ: \(unsteady)")
        try GoldenRecording.write(
            ["label": label, "documents": inputs.count, "unsteady": unsteady, "results": first],
            to: dir.appendingPathComponent("parse-\(label).json"))
    }

    private static let greek = [
        "Η εγγύηση επιστρέφεται μέσα σε εξήντα ημέρες από τη λήξη της μίσθωσης.",
        "Ο ενοικιαστής πληρώνει το ενοίκιο έως την πέμπτη ημέρα κάθε μήνα.",
        "Τα κατοικίδια επιτρέπονται μόνο με γραπτή άδεια του ιδιοκτήτη.",
        "Οι ώρες ησυχίας αρχίζουν στις δέκα το βράδυ κάθε ημέρα.",
    ]

    private static let hebrew = [
        "הפיקדון מוחזר תוך שישים יום מתום חוזה השכירות.",
        "חיות מחמד דורשות אישור בכתב מבעל הדירה.",
        "שעות השקט מתחילות בעשר בלילה בכל יום.",
    ]

    /// A text-layer PDF of the given lines, as `IngestionAccuracyTests.textPDF` draws it, at a fixed path.
    private func textPDF(in folder: URL, name: String, pages: [[String]]) throws -> URL {
        let url = folder.appendingPathComponent(name)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        for lines in pages {
            context.beginPDFPage(nil)
            for (row, text) in lines.enumerated() {
                let attributed = NSAttributedString(
                    string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: 54, y: 730 - CGFloat(row) * 16)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}

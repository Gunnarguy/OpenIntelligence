//
//  ExtractionFidelityRecorder.swift
//  OpenIntelligenceTests
//
//  Imports every PDF in a folder through `DocumentProcessor.processDocument`, the path an import takes, and writes each
//  stored passage to `<folder>/<label>/<file>.passages.json`, so `scripts/extraction_fidelity.py` can score the stored
//  text against the PDF's own text layer (words and numbers kept, tokens invented). It exists because on 2026-11-07 a
//  PDF with a perfect text layer stored its Table 1 as Vision read it ("1-2 g" as "1-28", "IU" as "TU"), and every
//  later stage repeated the error: garbage in, garbage out. 5.8.
//
//  Run only on purpose: it needs `TEST_RUNNER_OI_FIDELITY_DIR` (a folder of PDFs) and skips without it.
//  `TEST_RUNNER_OI_FIDELITY_LABEL` names the run (default "run").
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ExtractionFidelityRecorder: XCTestCase {
    func testRecordStoredPassagesOfEveryPDF() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folderPath = environment["OI_FIDELITY_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_OI_FIDELITY_DIR to a folder of PDFs to record their stored passages")
        }
        let folder = URL(fileURLWithPath: folderPath)
        let label = environment["OI_FIDELITY_LABEL"] ?? "run"
        let output = folder.appendingPathComponent(label, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let pdfs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(pdfs.isEmpty, "no PDF in \(folderPath)")

        for pdf in pdfs {
            // A copy under a fresh name, so no checkpoint of an earlier run is loaded instead of parsed.
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
                "fidelity-\(UUID().uuidString.prefix(8))-\(pdf.lastPathComponent)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: pdf, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }

            let started = Date()
            let processor = DocumentProcessor()
            let (_, chunks) = try await processor.processDocument(at: copy)
            let seconds = Date().timeIntervalSince(started)
            let passages: [[String: Any]] = chunks.map { chunk in
                [
                    "text": chunk.text,
                    "page": chunk.metadata.pageNumber ?? 0,
                    "type": chunk.metadata.chunkType?.rawValue ?? "",
                    "structure": chunk.metadata.structureType ?? "",
                    "section": chunk.metadata.sectionTitle ?? "",
                    "tableTitle": chunk.metadata.tableTitle ?? "",
                ]
            }
            let record: [String: Any] = ["file": pdf.lastPathComponent, "seconds": seconds, "passages": passages]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(
                to: output.appendingPathComponent(pdf.deletingPathExtension().lastPathComponent + ".passages.json"))
        }
    }
}

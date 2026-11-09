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
//  `TEST_RUNNER_OI_FIDELITY_LABEL` names the run (default "run"); `TEST_RUNNER_OI_FIDELITY_ONLY` limits it to the files
//  whose names contain one of its comma-separated parts.
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
        #if !targetEnvironment(simulator)
            // It clears the import checkpoints, which on a Mac host are the real app's (refuting review, 2026-11-08).
            throw XCTSkip("Runs in the iOS Simulator only")
        #endif
        let folder = URL(fileURLWithPath: folderPath)
        let label = environment["OI_FIDELITY_LABEL"] ?? "run"
        let output = folder.appendingPathComponent(label, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // `TEST_RUNNER_OI_FIDELITY_LIST`: a file of PDF paths relative to the folder, one per line (a public benchmark keeps
        // its PDFs in subfolders); otherwise every PDF directly in the folder.
        let listed: [URL]? = environment["OI_FIDELITY_LIST"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .map { $0.split(separator: "\n").map { folder.appendingPathComponent(String($0)) } }
        let pdfs = try (listed ?? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.path < $1.path }
            // `TEST_RUNNER_OI_FIDELITY_ONLY`: comma-separated parts of file names, to record only those files.
            .filter { pdf in
                guard let only = environment["OI_FIDELITY_ONLY"], !only.isEmpty else { return true }
                return only.split(separator: ",").contains { pdf.lastPathComponent.contains($0) }
            }
        XCTAssertFalse(pdfs.isEmpty, "no PDF in \(folderPath)")

        // Checkpoints are keyed by a file's name, size and bytes, not its folder, so an earlier run's are removed.
        let checkpoints = AppSupportPaths.localCacheDir().appendingPathComponent("IngestionCheckpoints", isDirectory: true)
        for pdf in pdfs {
            try? FileManager.default.removeItem(at: checkpoints)
            // A copy in a fresh folder, under its own name: a random name put its digits in every passage's SOURCE
            // line, which the score counted as invented numbers.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "fidelity-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(pdf.lastPathComponent)
            try FileManager.default.copyItem(at: pdf, to: copy)
            defer { try? FileManager.default.removeItem(at: folder) }

            let started = Date()
            let processor = DocumentProcessor()
            let (_, chunks) = try await processor.processDocument(at: copy)
            let seconds = Date().timeIntervalSince(started)
            let passages: [[String: Any]] = chunks.map { chunk in
                var record: [String: Any] = [
                    "text": chunk.text,
                    "page": chunk.metadata.pageNumber ?? 0,
                    "type": chunk.metadata.chunkType?.rawValue ?? "",
                    "structure": chunk.metadata.structureType ?? "",
                    "section": chunk.metadata.sectionTitle ?? "",
                    "tableTitle": chunk.metadata.tableTitle ?? "",
                ]
                // The table's grid as stored, so a scorer can rebuild it as a table (olmOCR-Bench checks a cell against
                // its neighbours and headings).
                if let table = chunk.structuredTable {
                    record["table"] = ["title": table.title, "headers": table.headers, "rows": table.rows]
                }
                return record
            }
            let record: [String: Any] = ["file": pdf.lastPathComponent, "seconds": seconds, "passages": passages]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            // A listed PDF's record is named by its path under the folder, "/" as "__".
            let base = folder.resolvingSymlinksInPath().path + "/"
            let full = pdf.resolvingSymlinksInPath().path
            let relative = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : pdf.lastPathComponent
            let name = (relative as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: "__")
            try data.write(to: output.appendingPathComponent(name + ".passages.json"))
        }
    }
}

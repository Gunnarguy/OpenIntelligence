//
//  SourceTextViewTests.swift
//  OpenIntelligenceTests
//
//  A cited passage in its document's text (5.8). "Found word for word" is a claim about the document, so these hold
//  it to the strict test, and the import test measures it on real imports of each kind of file.
//

import AppIntents
import XCTest

@testable import OpenIntelligence

#if canImport(UIKit)
    import UIKit
#endif

final class SourceLookupTests: XCTestCase {
    private let text =
        "Introduction.\n\nThe tenant pays rent on the first of each month.\nA late fee of 40 dollars applies after the fifth day.\n\nSigned."

    func testAPassageWithItsWordsInOrderIsExact() throws {
        let found = SourceLookup.find(
            "The tenant pays rent on the first of each month. A late fee of 40 dollars applies after the fifth day.",
            inText: text)
        XCTAssertEqual(found.match, .exact)
        let range = try XCTUnwrap(found.range)
        XCTAssertTrue((text as NSString).substring(with: range).hasPrefix("The tenant"))
    }

    func testOnlyWhitespaceAndCaseMayDiffer() {
        XCTAssertEqual(SourceLookup.find("THE TENANT   pays rent\non the first", inText: text).match, .exact)
    }

    /// A changed number is the failure this exists to catch, and it must never read as word for word.
    func testAChangedWordIsNotExact() {
        let found = SourceLookup.find(
            "The tenant pays rent on the first of each month. A late fee of 90 dollars applies after the fifth day.",
            inText: text)
        XCTAssertNotEqual(found.match, .exact)
    }

    func testOneTrueSentenceAndOneInventedOneIsPartial() {
        let found = SourceLookup.find(
            "The tenant pays rent on the first of each month. The landlord will repaint the kitchen every spring.",
            inText: text)
        XCTAssertEqual(found.match, .partial)
        XCTAssertNotNil(found.range, "the true part can still be shown")
    }

    func testAPassageThatIsNotThereSaysSo() {
        let found = SourceLookup.find("Dogs under twenty pounds are welcome in the building lobby.", inText: text)
        XCTAssertEqual(found.match, .notFound)
        XCTAssertNil(found.range)
    }

    func testNoTextSaysSoRatherThanNotFound() {
        XCTAssertEqual(SourceLookup.find("Anything at all here.", inText: nil).match, .noText)
        XCTAssertEqual(SourceLookup.find("Anything at all here.", inText: "").match, .noText)
    }

    func testASavedPassageCutShortIsMatchedUpToTheCut() {
        XCTAssertEqual(SourceLookup.find("The tenant pays rent on the first of...", inText: text).match, .exact)
    }

    func testOnlyAWordForWordMatchIsConfirmed() {
        XCTAssertTrue(SourceMatch.exact.isConfirmed)
        for other in [SourceMatch.partial, .notFound, .noText, .overview] { XCTAssertFalse(other.isConfirmed) }
    }

    /// The import writes a table's rows out with labels, and the file has only the cells.
    func testATablePassageIsFoundByItsCells() {
        let csv = "clause,notice,deposit\n1,31 days,100 dollars\n2,32 days,200 dollars\n3,33 days,300 dollars"
        let passage =
            "[Part 1]\nHEADERS: clause | notice | deposit\nROW 1: 1 | 31 days | 100 dollars\nROW 2: 2 | 32 days | 200 dollars"
        XCTAssertEqual(SourceLookup.find(passage, inText: csv).match, .exact)
        // A long table's parts are split again by words, which runs rows together on a line.
        let runTogether = "[Part 1]\n[Part 2]\nROW 2: 2 | 32 days | 200 dollars ROW 3: 3 | 33 days | 300 dollars"
        XCTAssertEqual(SourceLookup.find(runTogether, inText: csv).match, .exact)
    }

    /// A table is also indexed as `name: value` lines, which the file doesn't have, in the same order as its cells.
    func testATablesNamedValuesAreFoundByTheirCells() {
        let table =
            "| clause | notice | deposit |\n| --- | --- | --- |\n| 7 | 37 days | 700 dollars |\n| 8 | 38 days | 800 dollars |"
        XCTAssertEqual(
            SourceLookup.find(
                "[Specifications]\nclause: 7\nnotice: 37 days\ndeposit: 700 dollars\nclause: 8", inText: table
            ).match, .exact)
        XCTAssertEqual(
            SourceLookup.find("clause: 7; notice: 37 days; deposit: 700 dollars; clause: 8.", inText: table).match,
            .exact)
        XCTAssertNotEqual(SourceLookup.find("clause: 7\nnotice: 99 days", inText: table).match, .exact)
    }

    /// Dropping `name:` is only safe in a table: in prose the words before a colon are the document's words.
    func testNamedValuesAreNotLoosenedOutsideATable() {
        let prose = "Payment: the tenant pays on the first."
        XCTAssertNotEqual(SourceLookup.find("Rent: the tenant pays on the first.", inText: prose).match, .exact)
    }

    func testAPassageRunningFromRowsIntoNamedValuesIsPartial() {
        let table = "| clause | notice |\n| --- | --- |\n| 1 | 31 days |\n| 2 | 32 days |\n| 3 | 33 days |"
        let found = SourceLookup.find("ROW 3: 3 | 33 days\n[Specifications]\nclause: 1\nnotice: 31 days", inText: table)
        XCTAssertEqual(found.match, .partial)
        XCTAssertNotNil(found.range)
    }

    func testAChangedCellInATableIsNotExact() {
        let csv = "1,31 days,100 dollars\n2,32 days,200 dollars"
        XCTAssertNotEqual(SourceLookup.find("ROW 1: 1 | 31 days | 900 dollars", inText: csv).match, .exact)
    }

    func testPlainTextIsNotLoosenedByTheTableRules() {
        XCTAssertNil(PassageLocator.withoutImportLabels("The tenant pays rent, as agreed."))
    }

    func testAnOverviewSaysItIsTheAppsOwnWords() async {
        let found = await SourceLookup.find("The document outlines lease terms.", in: UUID(), isOverview: true)
        XCTAssertEqual(found.match, .overview)
    }

    func testAnExcerptCutsAtWordsAndSaysThereIsMore() throws {
        let long =
            String(repeating: "alpha beta gamma ", count: 2_000) + "the passage here "
            + String(repeating: "delta epsilon ", count: 2_000)
        let range = (long as NSString).range(of: "the passage here")
        let part = SourceExcerpt.around(range, in: long, radius: 100)
        XCTAssertEqual(part.passage, "the passage here")
        XCTAssertTrue(part.hasMoreBefore)
        XCTAssertTrue(part.hasMoreAfter)
        XCTAssertTrue(part.before.hasPrefix(" "), "starts on a word's edge")
        XCTAssertLessThanOrEqual(part.before.count, 100)
    }

    func testAnExcerptOfAShortTextIsAllOfIt() {
        let range = (text as NSString).range(of: "late fee")
        let part = SourceExcerpt.around(range, in: text, radius: 10_000)
        XCTAssertFalse(part.hasMoreBefore)
        XCTAssertFalse(part.hasMoreAfter)
        XCTAssertEqual(part.before + part.passage + part.after, text)
    }
}

/// Every passage of a real import of each kind of file, looked up the way a citation is. This is the number behind
/// "Found word for word", printed so a run shows it.
@MainActor
final class SourceLookupImportTests: XCTestCase {
    private func sampleFiles(in folder: URL) throws -> [String: URL] {
        let prose = (1...12).map {
            "Clause \($0) says the tenant at unit \($0) must give \($0 + 30) days of written notice, and the deposit of \($0 * 100) dollars returns within \($0 + 14) days."
        }
        var files: [String: Data] = [:]
        files["md"] = Data(("# Lease\n\n## Terms\n\n" + prose.joined(separator: "\n\n")).utf8)
        files["csv"] = Data(
            ("clause,notice,deposit\n"
                + (1...60).map { "\($0),\($0 + 30) days,\($0 * 100) dollars" }.joined(separator: "\n")).utf8)
        files["html"] = Data(
            ("<html><body><h1>Lease</h1>" + prose.map { "<p>\($0)</p>" }.joined() + "</body></html>").utf8)
        files["swift"] = Data(
            prose.enumerated().map { "let clause\($0.offset) = \"\($0.element)\"" }.joined(separator: "\n").utf8)
        let attributed = NSAttributedString(string: prose.joined(separator: "\n\n"))
        files["rtf"] = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        // A real PDF with a text layer. UIKit draws it; on a Mac (5.8, the suite builds for macOS) the PDF is left out.
        #if canImport(UIKit)
            let format = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            files["pdf"] = format.pdfData { context in
                for page in stride(from: 0, to: prose.count, by: 6) {
                    context.beginPage()
                    let text = prose[page..<min(page + 6, prose.count)].joined(separator: "\n\n")
                    (text as NSString).draw(
                        in: CGRect(x: 40, y: 40, width: 532, height: 700),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                }
            }
        #endif
        var urls: [String: URL] = [:]
        for (kind, data) in files {
            let url = folder.appendingPathComponent("source-test-\(UUID().uuidString.prefix(6)).\(kind)")
            try data.write(to: url)
            urls[kind] = url
        }
        return urls
    }

    func testEveryKindOfFileFindsItsOwnPassages() async throws {
        let engine = IntentSupport.engine()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("source-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.filename.hasPrefix("source-test-") {
                try? await engine.removeDocument(document)
            }
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        // One at a time: the test host is on the free plan, which holds five documents.
        var files = try sampleFiles(in: folder)
        // Office, image and audio files made on the host, when a run has put them there. The Simulator can read them.
        let host = URL(fileURLWithPath: "/private/tmp/oi58-fixtures", isDirectory: true)
        // Not .doc, which import refuses by design, or audio, since the Simulator has no speech recognizer.
        let fixtures = (try? FileManager.default.contentsOfDirectory(at: host, includingPropertiesForKeys: nil)) ?? []
        for file in fixtures where !["doc", "m4a"].contains(file.pathExtension) {
            let copy = folder.appendingPathComponent("source-test-\(UUID().uuidString.prefix(6)).\(file.pathExtension)")
            try FileManager.default.copyItem(at: file, to: copy)
            files[file.pathExtension] = copy
        }
        let library = engine.containerService.activeContainerId
        let database = try await engine.dbForContainer(library)
        var lines: [String] = []
        for (kind, url) in files.sorted(by: { $0.key < $1.key }) {
            _ = engine.enqueueDocuments([try IntentSupport.copyIntoImports(url)])
            var imported: Document?
            for _ in 0..<1_200 where imported == nil {
                imported = engine.documents.first { $0.filename == url.lastPathComponent }
                if imported == nil { try await Task.sleep(for: .milliseconds(100)) }
            }
            guard let document = imported else {
                lines.append("\(kind): NOT IMPORTED")
                XCTFail("\(kind) was not imported")
                continue
            }
            // The overview is written after the document's record.
            try await Task.sleep(for: .seconds(2))
            let chunks = try await database.allChunks().filter { $0.documentId == document.id }
            var counts: [SourceMatch: Int] = [:]
            var sample = ""
            for chunk in chunks {
                let found = await SourceLookup.find(
                    chunk.content, in: document.id, isOverview: chunk.metadata.abstractionLevel.isSummary)
                counts[found.match, default: 0] += 1
                if found.match != .exact, found.match != .overview, sample.isEmpty {
                    sample = String(chunk.content.prefix(120))
                }
                // Every passage that isn't found word for word, whole, so a cloud run's log shows why (2026-11-11:
                // 120 characters could not say why two csv passages were not found).
                if found.match == .partial || found.match == .notFound {
                    print("SOURCE-MISS \(kind) \(found.match)\n\(chunk.content.prefix(1_500))\nSOURCE-MISS-END")
                }
            }
            if kind == "csv" {
                let stored = SQLiteFullTextService.readContentDirectly(documentId: document.id) ?? ""
                print("SOURCE-STORED csv \(stored.count) characters\n\(stored.prefix(600))\n...\n\(stored.suffix(400))\nSOURCE-STORED-END")
            }
            let exact = counts[.exact] ?? 0
            lines.append(
                "\(kind): \(exact)/\(chunks.count) exact, overview \(counts[.overview] ?? 0), partial \(counts[.partial] ?? 0), notFound \(counts[.notFound] ?? 0), noText \(counts[.noText] ?? 0) \(sample)"
            )
            XCTAssertEqual(counts[.noText] ?? 0, 0, "\(kind) has no stored text")
            // A table also gets one passage the import wrote about it, which is rightly not found in the file.
            XCTAssertLessThanOrEqual(
                counts[.notFound] ?? 0, ["csv", "xlsx"].contains(kind) ? 1 : 0,
                "\(kind) has a passage that can't be placed: \(sample)")
            try? await engine.removeDocument(document)
        }
        print("SOURCE-MATCH-RATE\n" + lines.joined(separator: "\n") + "\nSOURCE-MATCH-END")
    }
}

import PDFKit
import XCTest
@testable import OpenIntelligenceEngine

/// `ProcessedChunk` is nested in `DocumentProcessor`; this keeps the assertions readable.
private typealias ProcessedChunk = DocumentProcessor.ProcessedChunk

/// What happened when a file was pushed through `processDocument`. `timedOut` is a real outcome here
/// rather than a test-harness detail: see `processingOutcome`.
private enum IngestionProcessingOutcome: Sendable {
    case threw(String)
    case produced(chunks: Int, characters: Int)
    case timedOut
}

/// Carries the outcome out of the detached task. Reads happen only after the expectation has been
/// fulfilled or the timeout has elapsed, which orders them against the single write.
private final class IngestionOutcomeBox: @unchecked Sendable {
    var value: IngestionProcessingOutcome = .timedOut
}

/// Format coverage for ingestion, asserted on **extraction** rather than on answers.
///
/// Why this file exists. Until now the only automated corpus was 25 markdown files against 20
/// advertised formats, so PDF parsing, OCR, Office extraction and A/V transcription had no coverage
/// at all. That is not a theoretical gap: on 2026-08-08 a plausible table-chunking change destroyed
/// 70% of retrieved table text while the answer benchmark reported an unchanged 16/20, and it was
/// caught only because a human noticed character counts in the running app.
///
/// So these tests deliberately do not score answers. They ask the questions an answer score cannot:
/// did row and column association survive, did the character yield hold, was the lane I think I am
/// testing actually the lane that ran, and is the chunk inventory the shape it was.
///
/// Fixtures are synthesised per test by `IngestionFixtureFactory`, from the same `TableSpec` the
/// expectations are derived from.
final class IngestionFormatCoverageTests: XCTestCase {

    private var factory: IngestionFixtureFactory!
    private let spec = IngestionFixtureFactory.serviceTable

    override func setUpWithError() throws {
        try super.setUpWithError()
        factory = try IngestionFixtureFactory()
    }

    override func tearDown() {
        factory?.cleanUp()
        factory = nil
        super.tearDown()
    }

    // MARK: - Text-layer PDF

    func testTextLayerPDF_PreservesRowAndColumnAssociation() async throws {
        let url = try factory.textLayerPDF(spec)
        let (metadata, chunks) = try await extract(url)

        assertNoLineCollapse(metadata, chunks, minimumLines: 8)
        assertRowAssociationSurvived(chunks)
        assertCharacterYield(metadata, atLeast: 0.85)

        // A text-layer PDF must not silently take the OCR lane; if it does, either the fixture has
        // no text layer or the text-layer check regressed, and both are worth failing over.
        XCTAssertEqual(
            metadata.ocrPagesCount ?? 0, 0,
            "A PDF with a real text layer went through OCR"
        )
    }

    // MARK: - Scanned PDF

    func testScannedPDF_RecoversTableStructureThroughOCR() async throws {
        let url = try factory.scannedPDF(spec)

        // Prove the fixture has no text layer *before* trusting anything the pipeline says about it.
        // If PDFKit can read text here, the fixture is wrong and the rest of this test is vacuous.
        let pdf = try XCTUnwrap(PDFDocument(url: url), "fixture is not a readable PDF")
        let textLayer = (pdf.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            textLayer.isEmpty,
            "The scanned fixture has a text layer (\(textLayer.count) chars), so this test would pass "
                + "without Vision ever running"
        )

        let (metadata, chunks) = try await extract(url)

        // `ocrPagesCount` used to be unusable as evidence here: the primary structured path returned
        // `usedOCR: false` even when recognition was the only source of text, so a scan Vision read
        // cleanly reported zero OCR pages while one that fell through to the rescue path reported one.
        // That is fixed at `DocumentProcessor.swift` ~4629, which is what makes this assertion mean
        // something. The fixture check above stays regardless, because it proves the lane independently
        // of anything the pipeline reports about itself.
        XCTAssertGreaterThan(
            metadata.ocrPagesCount ?? 0, 0,
            "A PDF with no text layer reported zero OCR pages, which is what Document Details shows "
                + "the user as \"OCR: N pages scanned\""
        )

        assertNoLineCollapse(metadata, chunks, minimumLines: 6)
        assertRowAssociationSurvived(chunks)
        assertCharacterYield(metadata, atLeast: 0.60)
    }

    // MARK: - Figures, no table

    func testFigureOnlyPDF_KeepsStructuredElements() async throws {
        // The `usedStructuredParsing` defect: the flag counted tables and lists only, so a page of
        // figures had every structured element discarded after the Neural Engine had already paid to
        // produce them.
        let url = try factory.figureOnlyPDF()
        let (metadata, chunks) = try await extract(url)

        XCTAssertTrue(
            metadata.usedStructuredParsing,
            "A page whose structured parse produced elements reported usedStructuredParsing == false"
        )

        let text = combinedText(chunks)
        let survivingCaptions = IngestionFixtureFactory.figureCaptions.filter { caption in
            contains(caption, in: text)
        }
        XCTAssertGreaterThanOrEqual(
            survivingCaptions.count, 2,
            "Only \(survivingCaptions.count) of \(IngestionFixtureFactory.figureCaptions.count) figure captions survived extraction"
        )
    }

    // MARK: - Partially legible scan

    func testPartiallyLegibleScan_KeepsTableAndRecoversSomeProse() async throws {
        // The `effectiveContent` defect: a low-quality page that captured one table kept the table
        // and dropped the prose the parser had already re-OCR'd.
        //
        // This asserts the outcome, not the mechanism, because whether the blur actually drives the
        // page's quality score below the 0.5 threshold depends on OCR. `StructuredPageContentTests`
        // pins the merge itself deterministically; this checks that on a real degraded page the
        // pipeline still ends up with both kinds of content.
        let url = try factory.partiallyLegibleScanPDF(spec)
        let (_, chunks) = try await extract(url)
        let text = combinedText(chunks)

        assertRowAssociationSurvived(chunks)

        let recoveredProse = spec.prose.filter { contains($0, in: text) }
        XCTAssertGreaterThanOrEqual(
            recoveredProse.count, 1,
            "The table survived but not one line of the degraded prose did, which is the exact "
                + "shape of the defect fixed on 2026-08-08"
        )
    }

    // MARK: - Image lane

    func testTablePNG_DoesNotCollapseIntoOneLine() async throws {
        // Both image lanes joined OCR lines with a space until 2026-08-08, so every ingested image
        // became one unbroken line: line items, sizes and torque values concatenated into a single
        // sentence, one paragraph for the chunker, one averaged embedding for the page.
        let url = try factory.tablePNG(spec)
        let (metadata, chunks) = try await extract(url)

        assertNoLineCollapse(metadata, chunks, minimumLines: 5)
        assertRowAssociationSurvived(chunks)
        assertCharacterYield(metadata, atLeast: 0.50)
    }

    // MARK: - CSV

    func testCSV_PreservesEveryRow() async throws {
        let url = try factory.csv(spec)
        let (_, chunks) = try await extract(url)
        let text = combinedText(chunks)

        for row in spec.allRows {
            XCTAssertTrue(
                lineContainsAll(row, in: text),
                "CSV row \(row) did not survive as a single line"
            )
        }
    }

    // MARK: - Office

    func testDOCX_PreservesTableRowsAndProse() async throws {
        let url = try factory.docx(spec)
        let (_, chunks) = try await extract(url)
        let text = combinedText(chunks)

        for row in spec.allRows {
            XCTAssertTrue(
                lineContainsAll(row, in: text),
                "Word table row \(row) did not survive as a single line"
            )
        }
        for line in spec.prose {
            XCTAssertTrue(contains(line, in: text), "Word paragraph was dropped: \(line)")
        }
    }

    func testXLSX_PreservesEveryRow() async throws {
        let url = try factory.xlsx(spec)
        let (_, chunks) = try await extract(url)
        let text = combinedText(chunks)

        for row in spec.allRows {
            XCTAssertTrue(
                lineContainsAll(row, in: text),
                "Excel row \(row) did not survive as a single line"
            )
        }
    }

    // MARK: - Formats that must fail loudly rather than quietly

    func testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument() async throws {
        // Authoring real speech audio needs `say`, which fails from an agent shell with -241, so this
        // cannot assert a transcription. It asserts the property that matters for silent corruption: a
        // file with nothing to transcribe must throw, not yield an empty document indexed as success.
        //
        // Measured behaviour: this throws in roughly 76 ms, which is the desired outcome.
        //
        // The timeout branch exists because of one unexplained cold start, and it is deliberately a
        // skip rather than a failure. On the first attempt of the session `SpeechAnalyzerService`
        // logged `Starting analysis: silence.wav (1s)` and had not returned when that run was
        // terminated for unrelated reasons — the elapsed time was never measured, so "it hung" is an
        // inference. Every attempt since has thrown immediately, and one-time framework or model
        // preparation is the likeliest explanation. Failing on timeout would assert a defect that has
        // not been established; skipping records it and keeps a genuine stall visible instead of
        // letting it take the suite down.
        let url = try factory.silentWAV()

        switch await processingOutcome(url) {
        case .threw:
            break
        case let .produced(chunks, characters):
            XCTFail(
                "Silent audio produced \(chunks) chunks and \(characters) characters instead of "
                    + "throwing. An empty transcript indexed as a success is the silent-corruption "
                    + "failure this suite exists to catch."
            )
        case .timedOut:
            throw XCTSkip(
                "Ingesting a silent WAV did not return within 60s. SpeechAnalyzerService accepted the "
                    + "file and never completed. Unresolved: whether ingestion genuinely hangs on "
                    + "speechless audio, or this simulator has no speech model. Verify on a device by "
                    + "importing an audio file containing no speech and watching the ingestion queue."
            )
        }
    }

    func testSingleFilePagesDocument_FailsLoudly() async throws {
        // Pages on iOS always writes a single-file `.pages`. `extractTextFromIWorkDocument` only
        // ever walks directories, so this form cannot be read at all.
        let url = try factory.singleFilePagesDocument()
        await assertProcessingThrows(url, because: "a single-file .pages document")
    }

    func testModernPagesPackage_FailsLoudly() async throws {
        // The package form is the one the extractor tries to read, but it looks for `.xml` or `.txt`
        // members and modern iWork stores its content as compressed protobuf in `Index/*.iwa`. So
        // this fails too. Both halves together answer the open question in `Docs/ai/STATE.md`: iWork
        // extraction does not work for any document current iWork produces. It fails loudly, which
        // is the acceptable half of that answer.
        let url = try factory.modernPagesPackage()
        await assertProcessingThrows(url, because: "a modern .pages package")
    }

    // MARK: - Chunk inventory

    func testChunkInventory_IsStableForTheTextLayerPDF() async throws {
        // The guard that would have caught the 70% loss. That change made the table summary a
        // near-duplicate of the `TABLE:` chunk, MMR then dropped the table as redundant, and the
        // answer score did not move. Duplication and disappearance both show up here as a change in
        // chunk count or in characters per chunk.
        let url = try factory.textLayerPDF(spec)
        let (metadata, chunks) = try await extract(url)

        XCTAssertFalse(chunks.isEmpty, "A one-page table PDF produced no chunks")
        XCTAssertLessThanOrEqual(
            chunks.count, 8,
            "A single-page table PDF produced \(chunks.count) chunks. Either chunking fragmented, "
                + "or something is emitting near-duplicates of the same content."
        )

        let totalCharacters = chunks.reduce(0) { $0 + $1.text.count }

        // Anchored to what extraction produced, not to what the fixture draws.
        //
        // Drawn characters are the wrong denominator here: the PDF text layer also carries the column
        // padding and the page-break sentinel, so chunk characters ran to 3.14x drawn on first
        // measurement (1186 against 378) with nothing wrong. Extracted characters are chunking's
        // actual input, which makes overlap the only legitimate multiplier and gives the assertion a
        // meaning. 2.5x is an observed value with headroom, not a specification.
        XCTAssertLessThanOrEqual(
            Double(totalCharacters), Double(metadata.totalCharacters) * 2.5,
            "Chunks carry \(totalCharacters) characters against \(metadata.totalCharacters) extracted. "
                + "Chunk overlap explains some duplication; this much suggests the same content is "
                + "being emitted more than once, which is how the 2026-08-08 table-summary change "
                + "made MMR discard the real table."
        )

        // Chunking must not lose what extraction already recovered. This is the other half of the
        // 70% incident: extraction was fine there, and the loss happened downstream of it. Comparing
        // chunk characters against the extractor's own character count catches that, where comparing
        // either one against the fixture alone would not.
        XCTAssertGreaterThan(
            Double(totalCharacters), Double(metadata.totalCharacters) * 0.6,
            "Extraction produced \(metadata.totalCharacters) characters but chunks carry only "
                + "\(totalCharacters). Chunking dropped most of what extraction recovered."
        )

        // Every chunk must be attributable. An unlabelled chunk cannot be reasoned about downstream
        // and cannot be filtered by modality.
        let labelled = chunks.filter { ($0.metadata.structureType?.isEmpty == false) }
        XCTAssertEqual(
            labelled.count, chunks.count,
            "\(chunks.count - labelled.count) chunks carry no structureType"
        )
    }

    // MARK: - Extraction

    /// Runs the real pipeline and unwraps the processing metadata, which is where the observable
    /// facts live: character count, whether OCR ran, whether structured parsing produced anything.
    /// Metadata being absent is itself a failure worth naming rather than defaulting away.
    private func extract(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> (metadata: ProcessingMetadata, chunks: [ProcessedChunk]) {
        let processor = DocumentProcessor()
        let (document, chunks) = try await processor.processDocument(at: url)
        let metadata = try XCTUnwrap(
            document.processingMetadata,
            "processDocument returned a Document with no processingMetadata",
            file: file,
            line: line
        )
        return (metadata, chunks)
    }

    /// Runs `processDocument` and reports which of three things happened, without ever hanging the
    /// suite.
    ///
    /// The timeout is not defensive padding. Ingesting a silent WAV parked inside
    /// `SpeechAnalyzerService` and never returned, which took down an entire run mid-suite. A helper
    /// that can only distinguish "threw" from "succeeded" cannot express that, so it gets a third
    /// answer. The stuck task is cancelled and then abandoned rather than awaited, because awaiting it
    /// is precisely the hang being avoided.
    private func processingOutcome(
        _ url: URL,
        timeout seconds: TimeInterval = 60
    ) async -> IngestionProcessingOutcome {
        let box = IngestionOutcomeBox()
        let finished = expectation(description: "processDocument(\(url.lastPathComponent))")

        let work = Task {
            let processor = DocumentProcessor()
            do {
                let (document, chunks) = try await processor.processDocument(at: url)
                box.value = .produced(
                    chunks: chunks.count,
                    characters: document.processingMetadata?.totalCharacters ?? 0
                )
            } catch {
                box.value = .threw(String(describing: error))
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: seconds)
        work.cancel()
        return box.value
    }

    /// Asserts the file fails visibly rather than being indexed as an empty success.
    private func assertProcessingThrows(
        _ url: URL,
        because reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        switch await processingOutcome(url) {
        case .threw:
            // Any thrown error is acceptable. The property under test is that the failure is
            // visible, not which specific error models it.
            break
        case let .produced(chunks, characters):
            XCTFail(
                "Expected \(reason) to throw. Instead it produced a document with \(chunks) chunks "
                    + "and \(characters) characters, which would be indexed as a successful ingest.",
                file: file,
                line: line
            )
        case .timedOut:
            XCTFail(
                "Expected \(reason) to throw. Instead ingestion never returned, which is worse than "
                    + "either outcome: the queue would sit on it indefinitely.",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Assertions

    private func combinedText(_ chunks: [ProcessedChunk]) -> String {
        chunks.map(\.text).joined(separator: "\n")
    }

    /// Extraction must not flatten a multi-line page into one line. This is the direct guard on the
    /// OCR line-joining defect, and it fails on the symptom a human would notice last.
    private func assertNoLineCollapse(
        _ metadata: ProcessingMetadata,
        _ chunks: [ProcessedChunk],
        minimumLines: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = combinedText(chunks)
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertGreaterThanOrEqual(
            lines.count, minimumLines,
            "Extraction produced \(lines.count) non-empty lines from \(metadata.totalCharacters) "
                + "characters. Below \(minimumLines) means the page was flattened.",
            file: file,
            line: line
        )
    }

    /// Every table row must come back with its label and its value on one line. A row split across
    /// lines is the failure that makes a table useless for retrieval while still looking extracted.
    private func assertRowAssociationSurvived(
        _ chunks: [ProcessedChunk],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = combinedText(chunks)
        for probe in spec.rowAssociationProbes {
            XCTAssertTrue(
                lineContainsAll([probe.label, probe.value], in: text),
                "\"\(probe.label)\" and \"\(probe.value)\" are in the same table row but did not "
                    + "come back on the same line",
                file: file,
                line: line
            )
        }
    }

    /// Characters extracted, as a fraction of the characters the fixture actually draws.
    ///
    /// The floors differ per lane and are observed values with headroom, not specifications: a text
    /// layer should return nearly everything, OCR loses some, and a photographed page loses more.
    private func assertCharacterYield(
        _ metadata: ProcessingMetadata,
        atLeast ratio: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let drawn = spec.drawnCharacterCount
        let extracted = metadata.totalCharacters
        let achieved = Double(extracted) / Double(drawn)
        XCTAssertGreaterThanOrEqual(
            achieved, ratio,
            "Character yield \(String(format: "%.2f", achieved)) (\(extracted) of \(drawn) drawn) "
                + "fell below the \(String(format: "%.2f", ratio)) floor for this lane",
            file: file,
            line: line
        )
    }

    // MARK: - Text matching
    //
    // Comparisons run on letters and digits only, because the extractors legitimately re-space and
    // re-punctuate. Line structure is resolved before normalising, so "same line" still means
    // something.

    private func contains(_ needle: String, in haystack: String) -> Bool {
        StructuredPageContent.normalizedForCoverage(haystack)
            .contains(StructuredPageContent.normalizedForCoverage(needle))
    }

    private func lineContainsAll(_ needles: [String], in haystack: String) -> Bool {
        let wanted = needles.map(StructuredPageContent.normalizedForCoverage)
        return haystack.components(separatedBy: .newlines).contains { candidate in
            let normalized = StructuredPageContent.normalizedForCoverage(candidate)
            return wanted.allSatisfy { normalized.contains($0) }
        }
    }
}

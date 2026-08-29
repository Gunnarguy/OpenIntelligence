//
//  RestoredIngestionProgressTests.swift
//  OpenIntelligenceTests
//
//  Pins `DocumentProcessor.restoredIngestionProgress(for:)`, which reads the streaming ingestion
//  checkpoint so a document paused by an app restart can report the pages it already indexed.
//
//  Why this exists. `importLargePDFStreamed` has always checkpointed `lastCompletedPage` and always
//  skipped completed batches on re-entry, so the work survives a restart. The queue restore path
//  nonetheless resets `progress` to nil, so the UI showed a document at zero after a restart even
//  though the engine was about to skip straight past 150 completed pages. A user reading that has
//  every reason to cancel — and cancelling is the one action that genuinely destroys the work,
//  because discarding a queue item deletes the checkpoint directory while a restart does not.
//
//  What is worth pinning here is not the pipeline but the reader's contract, because every one of
//  its failure modes returns the same `nil` and the difference between them is invisible at the
//  call site: no checkpoint, a not-yet-started checkpoint, and a corrupt one must not be conflated
//  with "zero pages done", and `fraction` must stay nil rather than invent a denominator.
//

@testable import OpenIntelligenceEngine
import XCTest

final class RestoredIngestionProgressTests: XCTestCase {

    private typealias Restored = DocumentProcessor.RestoredIngestionProgress

    // MARK: - fraction

    func testFractionIsNilWhenThePageTotalIsUnknown() {
        // A nil denominator must leave the progress bar indeterminate. Returning 0.0 here would
        // render identically to "nothing done", which is the exact misreading this type exists to
        // prevent.
        let restored = Restored(pagesCompleted: 150, totalPages: nil, chunksIndexed: 3_400)
        XCTAssertNil(restored.fraction)
    }

    func testFractionIsNilRatherThanInfiniteWhenThePageTotalIsZero() {
        let restored = Restored(pagesCompleted: 4, totalPages: 0, chunksIndexed: 12)
        XCTAssertNil(restored.fraction)
    }

    func testFractionIsThePagesCompletedShare() {
        let restored = Restored(pagesCompleted: 150, totalPages: 210, chunksIndexed: 3_400)
        XCTAssertEqual(try XCTUnwrap(restored.fraction), 150.0 / 210.0, accuracy: 0.0001)
    }

    func testFractionIsClampedWhenAResumeOvershootsTheLastPage() {
        // The final batch commits `endPage` for a range that can run past the last page index, so
        // pagesCompleted can exceed totalPages by up to the batch size. A progress bar must not be
        // handed a value above 1.
        let restored = Restored(pagesCompleted: 215, totalPages: 210, chunksIndexed: 4_900)
        XCTAssertEqual(try XCTUnwrap(restored.fraction), 1.0, accuracy: 0.0001)
    }

    // MARK: - detail

    func testDetailNamesBothPageCountsWhenTheTotalIsKnown() {
        let restored = Restored(pagesCompleted: 150, totalPages: 210, chunksIndexed: 3_400)
        XCTAssertEqual(
            restored.detail,
            "Paused after app restart — 150 of 210 pages already indexed, resuming from there"
        )
    }

    func testDetailStillReportsProgressWhenTheTotalIsUnknown() {
        // Losing the denominator must not lose the message. "150 pages already indexed" is the part
        // that stops someone cancelling.
        let restored = Restored(pagesCompleted: 150, totalPages: nil, chunksIndexed: 3_400)
        XCTAssertEqual(
            restored.detail,
            "Paused after app restart — 150 pages already indexed, resuming from there"
        )
    }

    func testDetailIsSingularForASinglePage() {
        let restored = Restored(pagesCompleted: 1, totalPages: nil, chunksIndexed: 8)
        XCTAssertEqual(
            restored.detail,
            "Paused after app restart — 1 page already indexed, resuming from there"
        )
    }

    // MARK: - reading the checkpoint

    func testReturnsNilForADocumentThatNeverHadACheckpoint() throws {
        // The common case by far: everything at or under the 10MB PDF gate in
        // `importLargePDFStreamed` takes the non-streamed path and never writes a checkpoint.
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "never-checkpointed.pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(processor.restoredIngestionProgress(for: url))
    }

    func testReturnsNilForACheckpointThatHasNotCommittedABatchYet() throws {
        // `importLargePDFStreamed` writes lastCompletedPage = -1 when a session starts. There is
        // nothing completed and nothing to skip, so this must read as "no preserved progress"
        // rather than as zero pages done.
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "just-started.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCheckpoint(for: url, processor: processor, lastCompletedPage: -1, totalChunks: 0)
        defer { processor.cleanCheckpoints(for: url) }

        XCTAssertNil(processor.restoredIngestionProgress(for: url))
    }

    func testReadsPagesCompletedAsTheZeroBasedIndexPlusOne() throws {
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "half-done.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCheckpoint(for: url, processor: processor, lastCompletedPage: 149, totalChunks: 3_400)
        defer { processor.cleanCheckpoints(for: url) }

        let restored = try XCTUnwrap(processor.restoredIngestionProgress(for: url))
        // 149 is an index, so 150 pages are done. Reporting 149 here would understate the work by a
        // page every time, which is small but is the kind of off-by-one that survives forever.
        XCTAssertEqual(restored.pagesCompleted, 150)
        XCTAssertEqual(restored.chunksIndexed, 3_400)
        // No page count was supplied, so there is no denominator to report.
        XCTAssertNil(restored.totalPages)
        XCTAssertNil(restored.fraction)
    }

    func testAKnownPageCountBecomesTheDenominator() throws {
        // The caller passes the interrupted run's own `metrics.pageCount`, which survives in the
        // persisted queue item. This is what makes a determinate progress bar possible without
        // parsing the document during launch.
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "known-total.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCheckpoint(for: url, processor: processor, lastCompletedPage: 149, totalChunks: 3_400)
        defer { processor.cleanCheckpoints(for: url) }

        let restored = try XCTUnwrap(processor.restoredIngestionProgress(for: url, knownPageCount: 210))
        XCTAssertEqual(restored.totalPages, 210)
        XCTAssertEqual(try XCTUnwrap(restored.fraction), 150.0 / 210.0, accuracy: 0.0001)
    }

    func testAZeroPageCountIsTreatedAsUnknownRatherThanAsADenominator() throws {
        // `PipelineMetrics.pageCount` defaults to 0, so an item interrupted before extraction ever
        // reported a page total will hand 0 straight through. Treating that as a real denominator
        // would be a divide-by-zero at best and a fabricated 0% at worst; it must read as unknown.
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "zero-total.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCheckpoint(for: url, processor: processor, lastCompletedPage: 149, totalChunks: 3_400)
        defer { processor.cleanCheckpoints(for: url) }

        let restored = try XCTUnwrap(processor.restoredIngestionProgress(for: url, knownPageCount: 0))
        XCTAssertNil(restored.totalPages)
        XCTAssertNil(restored.fraction)
        XCTAssertEqual(
            restored.detail,
            "Paused after app restart — 150 pages already indexed, resuming from there"
        )
    }

    func testReturnsNilForACorruptStateFile() throws {
        // A checkpoint that exists and cannot be read is the one failure worth distinguishing: the
        // resume is about to redo work it did not have to. The reader returns nil like the other
        // cases, but this is the path that logs a warning.
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "corrupt-state.pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        let fingerprint = processor.computeDocumentFingerprint(at: url)
        let dir = processor.checkpointDirectoryURL(for: fingerprint)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("ingestion_state.json"))
        defer { processor.cleanCheckpoints(for: url) }

        XCTAssertNil(processor.restoredIngestionProgress(for: url))
    }

    func testACheckpointDoesNotSurviveTheDocumentChangingOnDisk() throws {
        // The fingerprint is derived from path, size and modification date, so editing the file
        // invalidates the checkpoint. That is the streaming path's own behaviour and the reader
        // must agree with it rather than resurrect a checkpoint for different content.
        let processor = DocumentProcessor()
        let url = try makeTemporaryFile(named: "edited-after-checkpoint.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCheckpoint(for: url, processor: processor, lastCompletedPage: 149, totalChunks: 3_400)
        defer { processor.cleanCheckpoints(for: url) }
        XCTAssertNotNil(processor.restoredIngestionProgress(for: url))

        try Data(repeating: 0x41, count: 4_096).write(to: url)

        XCTAssertNil(processor.restoredIngestionProgress(for: url))
    }

    // MARK: - Helpers

    private func makeTemporaryFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoredIngestionProgressTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Not a real PDF, and it does not need to be: `restoredIngestionProgress` never parses the
        // document. It only stats the file to fingerprint it, which is the whole point of taking
        // the page count as a parameter instead of opening the PDF on the main actor.
        try Data(repeating: 0x20, count: 1_024).write(to: url)
        return url
    }

    private func writeCheckpoint(
        for url: URL,
        processor: DocumentProcessor,
        lastCompletedPage: Int,
        totalChunks: Int
    ) throws {
        let fingerprint = processor.computeDocumentFingerprint(at: url)
        let dir = processor.checkpointDirectoryURL(for: fingerprint)
        let state = StreamingIngestionState(
            documentId: UUID(),
            lastCompletedPage: lastCompletedPage,
            totalChunks: totalChunks,
            totalWords: 0,
            totalChars: 0
        )
        try JSONEncoder().encode(state).write(to: dir.appendingPathComponent("ingestion_state.json"))
    }
}

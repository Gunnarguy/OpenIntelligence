//
//  SemanticChunkerLargeTextTests.swift
//  OpenIntelligenceTests
//
//  On 2026-10-09 an 88 MB text file froze an iPhone for minutes and iOS ended the app. Three
//  things in the chunker made that happen: it measured or split the rest of the document for
//  every chunk, it ran on the main actor, and past 50,000 chunks it stopped without a word.
//  These pin what replaced them. That the new code cuts the same chunks as the old was checked
//  outside the suite, old against new on 75 texts (CHANGELOG, 5.7).
//

import Foundation
import XCTest

@testable import OpenIntelligenceEngine

final class SemanticChunkerLargeTextTests: XCTestCase {
    private let documentId = UUID()

    private var config: SemanticChunker.ChunkingConfig {
        SemanticChunker.ChunkingConfig(
            targetSize: 60, minSize: 20, maxSize: 80, overlap: 10, useTopicDetection: true, preserveStructure: true)
    }

    /// Plain sentences in paragraphs, the same every run.
    private func text(sentences: Int) -> String {
        let subjects = [
            "The pump", "A filter", "Each valve", "The operator", "This cycle", "The café log", "Der Zähler",
        ]
        let verbs = ["checks", "records", "flushes", "replaces", "measures", "holds"]
        let objects = ["the pressure", "a sample", "the channel", "every reading", "the detergent level", "42 units"]
        var lines: [String] = []
        var paragraph: [String] = []
        for index in 0..<sentences {
            let sentence =
                "\(subjects[index % subjects.count]) \(verbs[(index / 2) % verbs.count]) "
                + "\(objects[(index / 3) % objects.count]) during step \(index + 1) of the routine."
            paragraph.append(sentence)
            if paragraph.count == 5 {
                lines.append(paragraph.joined(separator: " "))
                paragraph.removeAll()
            }
        }
        if !paragraph.isEmpty { lines.append(paragraph.joined(separator: " ")) }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Offsets

    /// The offsets are kept as the chunker walks forward instead of measured from the start of
    /// the text for every chunk. They still have to be character offsets into the text.
    func testOffsetsAreCharacterOffsetsIntoTheText() {
        let source = text(sentences: 600)
        let characters = Array(source)
        let chunks = SemanticChunker().chunkText(source, documentId: documentId, config: config)
        XCTAssertGreaterThan(chunks.count, 20)

        var checked = 0
        for chunk in chunks {
            let start = chunk.metadata.startOffset
            let end = chunk.metadata.endOffset
            XCTAssertTrue(start >= 0 && end <= characters.count && start < end, "offsets \(start)..<\(end)")
            // A chunk that a short one was merged into holds joined text, which is not a slice of the source.
            guard chunk.content.count == end - start, end <= characters.count else { continue }
            XCTAssertEqual(String(characters[start..<end]), chunk.content, "chunk \(chunk.metadata.chunkIndex)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, chunks.count * 8 / 10, "most chunks are unmerged and were compared")
    }

    func testChunksStartInOrderAndReachTheEndOfTheText() {
        let source = text(sentences: 400)
        let chunks = SemanticChunker().chunkText(source, documentId: documentId, config: config)
        let starts = chunks.map(\.metadata.startOffset)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertEqual(starts.first, 0)
        XCTAssertEqual(chunks.map(\.metadata.endOffset).max(), source.count)
    }

    // MARK: - Off the main actor

    func testTheOffMainActorRunCutsTheSameChunks() async throws {
        let source = text(sentences: 300)
        let here = SemanticChunker().chunkText(source, documentId: documentId, config: config)
        let there = try await SemanticChunker.chunkTextOffMainActor(source, documentId: documentId, config: config)
        XCTAssertEqual(there.map(\.content), here.map(\.content))
        XCTAssertEqual(there.map(\.metadata.startOffset), here.map(\.metadata.startOffset))
        XCTAssertEqual(there.map(\.metadata.endOffset), here.map(\.metadata.endOffset))
        XCTAssertEqual(there.map(\.parentContent), here.map(\.parentContent))
    }

    func testProgressStartsWithTheStructurePassAndNeverGoesBack() async throws {
        let collected = ProgressBox()
        let source = text(sentences: 900)
        let chunks = try await SemanticChunker.chunkTextOffMainActor(
            source, documentId: documentId, config: config, progress: { collected.append($0) })
        let reports = collected.values

        XCTAssertEqual(reports.first?.phase, .findingStructure)
        XCTAssertEqual(reports.last?.phase, .finishing, "sent once, when the last chunk is cut")
        XCTAssertEqual(reports.filter { $0.phase == .finishing }.count, 1)
        let cutting = reports.filter { $0.phase == .cuttingChunks }
        XCTAssertGreaterThan(cutting.count, 1, "a report every 25 chunks; this text has \(chunks.count)")
        XCTAssertEqual(cutting.map(\.chunksCreated), cutting.map(\.chunksCreated).sorted())
        XCTAssertEqual(cutting.map(\.fractionOfText), cutting.map(\.fractionOfText).sorted())
        XCTAssertTrue(cutting.allSatisfy { $0.fractionOfText >= 0 && $0.fractionOfText <= 1 })
        XCTAssertEqual(cutting.first?.chunksCreated, 0)
    }

    func testATaskCancelledBeforeItStartsThrows() async {
        let source = text(sentences: 300)
        let documentId = documentId
        let config = config
        let task = Task {
            try await SemanticChunker.chunkTextOffMainActor(source, documentId: documentId, config: config)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled chunking task should throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// Cancelled from inside the run, at the report for chunk 25. The loop looks at the task before
    /// each chunk, so no later report is sent. Without that look the run would cut every chunk and
    /// only then throw, which is the thing a Cancel button must not wait for.
    func testCancellingDuringTheRunStopsItThere() async {
        let source = text(sentences: 900)
        let documentId = documentId
        let config = config
        let collected = ProgressBox()
        let canceller = TaskCanceller()
        let task = Task {
            try await SemanticChunker.chunkTextOffMainActor(
                source, documentId: documentId, config: config,
                progress: { report in
                    collected.append(report)
                    if report.phase == .cuttingChunks, report.chunksCreated >= 25 { canceller.cancel() }
                })
        }
        canceller.attach { task.cancel() }
        do {
            _ = try await task.value
            XCTFail("a cancelled chunking task should throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        let reports = collected.values
        XCTAssertEqual(reports.filter { $0.phase == .cuttingChunks }.map(\.chunksCreated).max(), 25)
        XCTAssertFalse(reports.contains { $0.phase == .finishing })
    }

    // MARK: - The chunk limit

    /// Through 5.6 the loop stopped at the limit and the rest of the document was never chunked,
    /// with nothing logged and nothing returned to say so.
    func testReachingTheLimitIsRecorded() {
        let source = text(sentences: 400)
        let chunker = SemanticChunker()
        chunker.chunkLimit = 3
        let chunks = chunker.chunkText(source, documentId: documentId, config: config)
        XCTAssertLessThanOrEqual(chunks.count, 3)
        XCTAssertTrue(chunker.stoppedAtChunkLimit)

        let whole = SemanticChunker()
        _ = whole.chunkText(source, documentId: documentId, config: config)
        XCTAssertFalse(whole.stoppedAtChunkLimit)
    }

    func testTheImportPathRefusesATextThatCannotFit() async {
        let source = text(sentences: 400)
        do {
            _ = try await SemanticChunker.chunkTextOffMainActor(
                source, documentId: documentId, config: config, chunkLimit: 3)
            XCTFail("a text over the limit should throw")
        } catch {
            XCTAssertEqual(error as? SemanticChunker.ChunkingError, .tooManyChunks(limit: 3))
        }
    }

    /// 400 sentences are about 4,000 words. Three chunks of at most 80 words cannot hold them,
    /// and that is known from the word count, before any chunk is cut.
    func testFailFastStopsBeforeCuttingWhenTheWordCountAloneSaysSo() {
        let source = text(sentences: 400)
        let chunker = SemanticChunker()
        chunker.chunkLimit = 3
        let chunks = chunker.chunkText(source, documentId: documentId, config: config, failFast: true)
        XCTAssertTrue(chunks.isEmpty)
        XCTAssertTrue(chunker.stoppedAtChunkLimit)
    }

    func testTheShippedLimitIsFiftyThousand() {
        XCTAssertEqual(SemanticChunker.maxChunks, 50_000)
        XCTAssertEqual(SemanticChunker().chunkLimit, SemanticChunker.maxChunks)
    }

    /// About 700 words fit ten chunks of 80 by the word count, so the early check passes. With the
    /// overlap they need more than ten, and that is found in the loop, at the limit.
    func testATextThatOverflowsOnlyBecauseOfOverlapIsCaughtAtTheLimit() async {
        let source = text(sentences: 60)
        let chunker = SemanticChunker()
        chunker.chunkLimit = 10
        let chunks = chunker.chunkText(source, documentId: documentId, config: config, failFast: true)
        XCTAssertFalse(chunks.isEmpty, "the early check did not stop this one")
        XCTAssertLessThanOrEqual(chunks.count, 10)
        XCTAssertTrue(chunker.stoppedAtChunkLimit)

        do {
            _ = try await SemanticChunker.chunkTextOffMainActor(
                source, documentId: documentId, config: config, chunkLimit: 10)
            XCTFail("a text over the limit should throw")
        } catch {
            XCTAssertEqual(error as? SemanticChunker.ChunkingError, .tooManyChunks(limit: 10))
        }
    }

    /// The last chunk the loop cuts is usually the overlap of the one before it, text already in a
    /// chunk. A limit that stops the loop just before it has left nothing out, and is not a refusal.
    func testTheLimitCountsOnlyTextThatIsLeftOver() {
        let source = text(sentences: 60)
        let characters = Array(source)
        var firstLimitThatFits: Int?
        for limit in 1...40 {
            let chunker = SemanticChunker()
            chunker.chunkLimit = limit
            let chunks = chunker.chunkText(source, documentId: documentId, config: config)
            let furthest = chunks.map(\.metadata.endOffset).max() ?? 0
            let wordsLeftOver = characters[min(furthest, characters.count)...].contains { $0.isLetter || $0.isNumber }
            XCTAssertEqual(
                chunker.stoppedAtChunkLimit, wordsLeftOver,
                "limit \(limit): flagged exactly when words are left after the last chunk")
            if !chunker.stoppedAtChunkLimit, firstLimitThatFits == nil { firstLimitThatFits = limit }
        }
        XCTAssertNotNil(firstLimitThatFits)
        XCTAssertGreaterThan(firstLimitThatFits ?? 0, 3, "this text needs more than a few chunks")
    }

    func testTheWordCountRule() {
        XCTAssertFalse(SemanticChunker.exceedsChunkLimit(wordCount: 15_500_000, maxSize: 310))
        XCTAssertTrue(SemanticChunker.exceedsChunkLimit(wordCount: 15_500_001, maxSize: 310))
        XCTAssertTrue(SemanticChunker.exceedsChunkLimit(wordCount: 241, maxSize: 80, chunkLimit: 3))
        XCTAssertFalse(SemanticChunker.exceedsChunkLimit(wordCount: 240, maxSize: 80, chunkLimit: 3))
        // Nothing can be said without a chunk size, and a product too large to hold is not a limit.
        XCTAssertFalse(SemanticChunker.exceedsChunkLimit(wordCount: 1_000_000, maxSize: 0))
        XCTAssertFalse(SemanticChunker.exceedsChunkLimit(wordCount: .max, maxSize: .max, chunkLimit: .max))
    }

    func testTheWordCountOffTheMainActorIsTheTokenizersCount() async {
        let count = await SemanticChunker.wordCountOffMainActor("One two three. Four, five!")
        XCTAssertEqual(count, 5)
    }

    /// The early count is skipped below the size at which a text could first hold too many words.
    func testTheSizeBelowWhichNoTextCanBeTooLong() {
        XCTAssertEqual(DocumentProcessor.largeTextWordCountBytes, 50_000 * 310 * 2)
    }

    // MARK: - What the import shows

    func testChunkingProgressText() {
        XCTAssertEqual(
            DocumentProcessor.chunkingProgressText(chunksCreated: 1, fractionOfText: 0.004), "✂️ Chunking 0% (1 passage)"
        )
        XCTAssertEqual(
            DocumentProcessor.chunkingProgressText(chunksCreated: 1250, fractionOfText: 0.429),
            "✂️ Chunking 42% (\(1250.formatted(.number)) passages)")
        XCTAssertEqual(DocumentProcessor.chunkingPercent(0.999), 99)
        XCTAssertEqual(DocumentProcessor.chunkingPercent(1), 100)
        XCTAssertTrue(
            DocumentProcessor.chunkingProgressText(chunksCreated: 25, fractionOfText: 7).hasPrefix("✂️ Chunking 100%"))
        XCTAssertTrue(
            DocumentProcessor.chunkingProgressText(chunksCreated: 0, fractionOfText: -1).hasPrefix("✂️ Chunking 0%"))
    }

    func testTheTooLongMessageSaysWhatToDo() {
        let message = DocumentProcessingError.tooManyPassages(limit: 500).errorDescription ?? ""
        XCTAssertTrue(message.contains("\(500.formatted(.number)) passages"), message)
        XCTAssertTrue(message.contains("Split it into smaller files"), message)
    }
}

/// Collects progress reports from the pool the chunker runs on.
nonisolated private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SemanticChunker.ChunkingProgress] = []

    func append(_ value: SemanticChunker.ChunkingProgress) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }

    var values: [SemanticChunker.ChunkingProgress] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Cancels a task from inside its own progress callback. The callback can run before the test has
/// the task in hand, so a cancel that arrives first is kept and applied when the task is attached.
nonisolated private final class TaskCanceller: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    private var requested = false

    func attach(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        self.action = action
        let fire = requested
        lock.unlock()
        if fire { action() }
    }

    func cancel() {
        lock.lock()
        requested = true
        let action = action
        lock.unlock()
        action?()
    }
}

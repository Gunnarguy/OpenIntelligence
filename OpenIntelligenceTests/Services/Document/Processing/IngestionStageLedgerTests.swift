//
//  IngestionStageLedgerTests.swift
//  OpenIntelligenceTests
//
//  Pins the conservation bands in `IngestionStageLedger`, and one property of the ledger that is
//  easy to lose in a refactor: it must count the text, never a recorded count.
//
//  Why this exists. `DocumentProcessor.verifyContentCoverage` already compares the extracted text
//  against the finished chunks, so it can say text was lost. It cannot say where, because it is a
//  single end-to-end comparison across four stages. The ledger measures each transition, and what a
//  test can meaningfully pin is not the pipeline (that needs a real document) but the arithmetic and
//  the bands between the readings, which is the part a future edit can get wrong in silence.
//
//  The band values themselves are the assertions here. Loosening `.exact` on `sanitized` or
//  `tokenLimited` to absorb a failure would make the ledger agree with whatever broke, which is the
//  exact failure mode the type was written against, so these tests fail loudly if either moves.
//

@testable import OpenIntelligenceEngine
import XCTest

final class IngestionStageLedgerTests: XCTestCase {

    // MARK: - Conservation bands

    func testExactConservationAdmitsOnlyAnUnchangedCharacterCount() {
        let exact = IngestionConservation.exact
        XCTAssertTrue(exact.admits(1.0))
        // The tolerance exists for grapheme recombination, not for dropped text.
        XCTAssertTrue(exact.admits(1.0005))
        XCTAssertTrue(exact.admits(0.9995))
        XCTAssertFalse(exact.admits(0.99), "a 1% loss is a dropped sentence, not a normalisation artefact")
        XCTAssertFalse(exact.admits(0.45), "the truncation shape must never be admitted")
    }

    func testChunkingBandPermitsOverlapButNotLoss() {
        let chunking = IngestionConservation.atLeast(0.98)
        // Overlap deliberately repeats text, so exceeding 1.0 is correct behaviour and not a fault.
        XCTAssertTrue(chunking.admits(1.25))
        XCTAssertTrue(chunking.admits(0.99))
        XCTAssertFalse(chunking.admits(0.90))
    }

    func testEachStageIsCheckedInTheUnitItActuallyConserves() {
        // `sanitizeProcessedChunkMetadata` rebuilds ChunkMetadata and never reads or writes
        // `chunk.text`, so characters are exactly conserved and anything else is a defect.
        XCTAssertEqual(IngestionStageLedger.Stage.sanitized.conservationFromPredecessor, .exact)

        // `splitOversizedChunkByTokens` is NOT character-preserving: it separates on `.!?\n` with
        // `components(separatedBy:)`, which discards every separator, rejoins with ". ", injects
        // `[Part N]` markers and drops blank-line runs. The first version of this file asserted
        // `.exact` here and would have fired on the first document containing an oversized chunk.
        // Words are what survive.
        XCTAssertEqual(IngestionStageLedger.Stage.tokenLimited.conservationFromPredecessor, .atLeastWords(0.99))
        XCTAssertTrue(IngestionStageLedger.Stage.tokenLimited.conservationFromPredecessor.usesWords)

        XCTAssertEqual(IngestionStageLedger.Stage.chunked.conservationFromPredecessor, .atLeast(0.98))
        XCTAssertFalse(IngestionStageLedger.Stage.chunked.conservationFromPredecessor.usesWords)
    }

    func testTheSplittersRealRewriteIsNotReportedAsALoss() {
        // The regression this file shipped and had to fix. Three sentences become three parts: every
        // terminator is replaced, ". " is inserted, and a "[Part N]" marker is added to each. The
        // character count moves; not one word is lost. This must be silent.
        var ledger = IngestionStageLedger(documentName: "rewritten-by-splitter.pdf")
        let original = "alpha beta gamma. delta epsilon zeta! eta theta iota?"
        ledger.recordExtraction(characters: original.count, words: 9)
        ledger.record(.chunked, chunkTexts: [original])
        ledger.record(.sanitized, chunkTexts: [original])
        ledger.record(.tokenLimited, chunkTexts: [
            "[Part 1]\nalpha beta gamma. ",
            "[Part 2]\ndelta epsilon zeta. ",
            "[Part 3]\neta theta iota. "
        ])

        XCTAssertTrue(
            ledger.anomalies.isEmpty,
            "the splitter adds markers and rewrites separators; no word was lost, so nothing should fire"
        )
    }

    // MARK: - Transitions

    func testAHealthyPipelineProducesNoAnomalies() {
        var ledger = IngestionStageLedger(documentName: "healthy.pdf")
        ledger.recordExtraction(characters: 1000, words: 200)
        // Overlap pushes the chunked total above the source, which is expected.
        ledger.record(.chunked, chunkTexts: [String(repeating: "a", count: 600), String(repeating: "b", count: 550)])
        ledger.record(.sanitized, chunkTexts: [String(repeating: "a", count: 600), String(repeating: "b", count: 550)])
        ledger.record(.tokenLimited, chunkTexts: [
            String(repeating: "a", count: 300), String(repeating: "a", count: 300),
            String(repeating: "b", count: 550)
        ])

        XCTAssertTrue(ledger.anomalies.isEmpty, "splitting one chunk into two conserves every character")
        XCTAssertEqual(ledger.transitions.count, 3)
    }

    func testASplitterThatTruncatesIsCaughtEvenThoughTheChunkCountRises() {
        // The failure this type exists for. Chunk count going UP is what a healthy split looks like,
        // so any check based on counts alone reads this as success. Measured in words, because that
        // is the unit the splitter conserves.
        var ledger = IngestionStageLedger(documentName: "truncating-splitter.pdf")
        let full = (1...100).map { "word\($0)" }.joined(separator: " ")
        ledger.recordExtraction(characters: full.count, words: 100)
        ledger.record(.chunked, chunkTexts: [full])
        ledger.record(.sanitized, chunkTexts: [full])
        // Half the words silently dropped while the chunk count rose from one to two.
        ledger.record(.tokenLimited, chunkTexts: [
            (1...25).map { "word\($0)" }.joined(separator: " "),
            (26...50).map { "word\($0)" }.joined(separator: " ")
        ])

        let anomalies = ledger.anomalies
        XCTAssertEqual(anomalies.count, 1)
        guard let caught = anomalies.first else { return XCTFail("expected the splitter transition to fail") }
        XCTAssertEqual(caught.to, IngestionStageLedger.Stage.tokenLimited.rawValue)
        XCTAssertEqual(caught.chunksIn, 1)
        XCTAssertEqual(caught.chunksOut, 2, "the count rose while the text was cut in half")
    }

    func testALossLocalisesToTheStageThatCausedIt() {
        // The whole point of measuring transitions rather than end-to-end: the report must name the
        // stage, not merely report that something upstream lost text.
        var ledger = IngestionStageLedger(documentName: "lossy-sanitiser.pdf")
        ledger.recordExtraction(characters: 1000, words: 100)
        ledger.record(.chunked, chunkTexts: [String(repeating: "a", count: 1000)])
        ledger.record(.sanitized, chunkTexts: [String(repeating: "a", count: 700)])
        ledger.record(.tokenLimited, chunkTexts: [String(repeating: "a", count: 700)])

        XCTAssertEqual(ledger.anomalies.map(\.to), [IngestionStageLedger.Stage.sanitized.rawValue])
    }

    func testAnEmptyDocumentIsNotAnAnomaly() {
        // A file that extracted nothing is a different problem, reported elsewhere. Dividing by it
        // must not manufacture a conservation failure on top.
        var ledger = IngestionStageLedger(documentName: "empty.txt")
        ledger.recordExtraction(characters: 0, words: 0)
        ledger.record(.chunked, chunkTexts: [])
        XCTAssertTrue(ledger.anomalies.isEmpty)
    }

    // MARK: - Degenerate output

    func testUniformChunkLengthsAreFlagged() {
        // A stage that has stopped varying with its input can still conserve characters perfectly,
        // so no ratio can see it. Only the distribution can.
        var ledger = IngestionStageLedger(documentName: "constant-chunker.pdf")
        ledger.recordExtraction(characters: 2000, words: 400)
        ledger.record(.chunked, chunkTexts: Array(repeating: String(repeating: "a", count: 500), count: 4))
        XCTAssertTrue(ledger.hasDegenerateChunkDistribution)
        XCTAssertTrue(ledger.anomalies.isEmpty, "characters are conserved; only the distribution is wrong")
    }

    func testTwoEqualChunksAreACoincidenceAndNotFlagged() {
        var ledger = IngestionStageLedger(documentName: "short.txt")
        ledger.recordExtraction(characters: 1000, words: 200)
        ledger.record(.chunked, chunkTexts: Array(repeating: String(repeating: "a", count: 500), count: 2))
        XCTAssertFalse(ledger.hasDegenerateChunkDistribution)
    }

    // MARK: - The property that must survive a refactor

    func testTheLedgerCountsTextRatherThanAnyRecordedCount() {
        // If this ever reads `chunk.metadata.characterCount` instead of the text, the audit starts
        // agreeing with a broken counter, and the tokenizer defect is the standing proof that a
        // counter in this pipeline can be wrong while looking plausible.
        var ledger = IngestionStageLedger(documentName: "counted.txt")
        ledger.recordExtraction(characters: 10, words: 1)
        ledger.record(.chunked, chunkTexts: ["abcdefghij"])
        XCTAssertEqual(ledger.readings.last?.characterCount, 10)
        XCTAssertEqual(ledger.transitions.first?.ratio, 1.0)
    }
}

//
//  IngestionStageLedger.swift
//  OpenIntelligence
//
//  Records what each ingestion stage received and what it passed on, so a stage that silently
//  discards text is visible on any document, with no ground truth and no benchmark.
//
//  ## The gap this fills, and the two checks it does NOT replace
//
//  `DocumentProcessor` already carries two guards, and neither covers what this does.
//
//  `verifyTokenizerCounts` encodes a one-word and a 180-word string at tokenizer load and errors if
//  they measure the same, which is the signature of an encoder padding to a fixed width. That is the
//  check for the 2026-08 padding defect, it is behavioural rather than configuration-based, and it is
//  correctly placed. Nothing here duplicates it.
//
//  `verifyContentCoverage` compares the extracted text against the finished chunks. It is END TO END:
//  it can say text was lost, and it cannot say WHERE. On a pipeline with a structure-aware path, a
//  semantic fallback path, a metadata sanitiser and a token-limit splitter, "some text went missing"
//  localises to four candidate stages and a bisect by hand. That is the gap.
//
//  This type measures each transition separately, so a loss names its own stage. It is a complement
//  to the coverage check, not a replacement, and it deliberately asserts a different property:
//  conservation between neighbours rather than coverage against the source.
//
//  ## Why this matters at all
//
//  Several of the most expensive defects in this project share one shape: a stage discards data and
//  every log line still reads healthy. `RetrievalStageMetrics` cannot see that class, because it
//  scores against `expectedSources` and therefore speaks only when handed the answer key — on a
//  benchmark query, never on the real question where the defect ships. Conservation needs no answer
//  key, so it holds on any document a user imports.
//
//  ## Why ratios rather than counts
//
//  `RAGAuditSnapshot` already carries `candidatesCount`, `filteredCount`, `droppedCount` and the
//  rest, and ships on every audited query. Those are absolute numbers with nothing to compare them
//  against, so nobody notices when `droppedCount` is 90% instead of 9%. A ratio has an expectation
//  attached, and an expectation is the part that can be violated.
//
//  ## Why it measures the text and not the metadata
//
//  Every reading below counts `chunk.text.count` directly and never `chunk.metadata.characterCount`.
//  A defect in the counter is precisely one of the things being hunted: the tokenizer bug WAS a
//  counter returning a constant. Trusting a recorded count to audit the stage that recorded it makes
//  the audit agree with the bug.
//
//  ## Scope, deliberately
//
//  This covers the transitions inside `DocumentProcessor`: extraction to chunking, and the two
//  post-passes that follow. It does NOT cover chunking to embedding or embedding to index, because
//  both live in `RAGService.swift`, outside the `Services/Document/**` edit boundary the RepoOS
//  router sets for ingestion work. Those two transitions are the natural next pass and need their
//  own approval.
//
//  Recording is a plain value type built from values already in scope, not a thread-safe collector
//  like `RetrievalTraceCollector`. Retrieval needed a collector because its stages complete across
//  concurrent child tasks; these three run in sequence on one path, so a struct is the honest shape.

import Foundation

/// What one ingestion stage held, measured from the text itself.
struct IngestionStageReading: Sendable, Equatable {
    /// Stage label, e.g. `extraction`, `chunked`, `sanitized`, `token-limited`.
    let stage: String
    /// Number of chunks the stage produced. Zero for `extraction`, which is not yet chunked.
    let chunkCount: Int
    /// Characters the stage was holding, counted from the text rather than from any recorded count.
    let characterCount: Int
    /// Whitespace-separated words the stage was holding, counted the same way.
    ///
    /// Both units are recorded because the stages conserve different things. A stage that rewrites
    /// separators changes the character count without losing a word, and asserting characters there
    /// produces a false alarm; a stage that drops content loses both.
    let wordCount: Int
}

/// What a stage was allowed to do to the text passing through it.
///
/// The band is the whole point. Each one is a claim about the stage that can be checked on any
/// document, and each is written with the reason it holds, so a future change either preserves the
/// reason or changes the band deliberately.
enum IngestionConservation: Sendable, Equatable {
    /// Characters must survive exactly. Only for stages that do not touch the text at all.
    case exact
    /// Characters may fall to `floor` of the input, and may exceed 1.0.
    ///
    /// Chunking exceeds 1.0 because overlap deliberately repeats text.
    case atLeast(Double)
    /// WORDS may fall to `floor` of the input, and may exceed 1.0.
    ///
    /// The unit matters, and getting it wrong is how this file shipped a false alarm on 2026-08-28.
    /// `splitOversizedChunkByTokens` splits on `.!?\n` with `components(separatedBy:)`, which
    /// DISCARDS every separator, then rejoins with `". "` and injects `[Part N]` markers. Blank-line
    /// runs collapse to nothing. No word is lost — both flush paths are present — but the character
    /// count moves in both directions and cannot be asserted. Words are the unit that survives, so
    /// words are the unit checked.
    case atLeastWords(Double)

    /// Which reading this band applies to.
    var usesWords: Bool { if case .atLeastWords = self { return true } else { return false } }

    func admits(_ ratio: Double) -> Bool {
        switch self {
        case .exact:
            // A tolerance, not equality: character counts come from Swift's grapheme-cluster
            // counting, and a normalisation that recombines a decomposed character legitimately
            // changes the count by one or two on a long document. The tolerance is tight enough
            // that a dropped sentence still fails.
            return abs(ratio - 1.0) <= 0.001
        case .atLeast(let floor), .atLeastWords(let floor):
            return ratio >= floor
        }
    }

    var description: String {
        switch self {
        case .exact: return "exactly 1.0 of its characters"
        case .atLeast(let floor): return "at least \(String(format: "%.3f", floor)) of its characters"
        case .atLeastWords(let floor): return "at least \(String(format: "%.3f", floor)) of its words"
        }
    }
}

/// One stage-to-stage transition and whether it stayed inside its band.
struct IngestionTransition: Sendable {
    let from: String
    let to: String
    let ratio: Double
    let conservation: IngestionConservation
    let charactersIn: Int
    let charactersOut: Int
    let chunksIn: Int
    let chunksOut: Int

    var isAnomalous: Bool { !conservation.admits(ratio) }

    /// One line, shaped so a device log can be grepped for it.
    var summary: String {
        String(
            format: "%@ → %@ kept %.4f (%d → %d chars, %d → %d chunks), expected %@",
            from, to, ratio, charactersIn, charactersOut, chunksIn, chunksOut, conservation.description
        )
    }
}

/// Per-document record of what every measured ingestion stage received and passed on.
///
/// Build one per document, record each stage as it completes, then call `emit()`. Recording is
/// cheap: one `reduce` over the chunk texts per stage.
struct IngestionStageLedger: Sendable {

    /// The stage a reading belongs to, and the conservation the transition INTO it must satisfy.
    ///
    /// Ordered as the pipeline runs. `extraction` opens the ledger and has no predecessor.
    enum Stage: String, CaseIterable {
        /// Text handed to chunking, after extraction and normalisation.
        case extraction
        /// Chunks as the chunker produced them, from either the structure-aware or semantic path.
        ///
        /// `.atLeast(0.98)` rather than `.exact`: normalisation collapses whitespace between chunk
        /// boundaries, and overlap can push the ratio above 1.0, which the band permits. A floor of
        /// 0.98 still fails on a dropped paragraph of any real size.
        case chunked
        /// After `sanitizeProcessedChunkMetadata`.
        ///
        /// `.exact`, and this is the sharpest claim in the file. That function sanitises METADATA.
        /// If it changes the text at all, either it has grown a responsibility its name denies or
        /// something is wrong, and either way the ledger should say so rather than absorb it.
        case sanitized
        /// After `enforceTokenLimitOnChunks`.
        ///
        /// Checked in WORDS, not characters, and this band was wrong when first written.
        ///
        /// The stage splits oversized chunks rather than truncating them, so chunk count may rise
        /// while the content survives — which is exactly why a count cannot audit it, since a split
        /// and a truncation both move the number and only one keeps the text. But the split is not
        /// character-preserving: `splitOversizedChunkByTokens` separates on `.!?\n` with
        /// `components(separatedBy:)`, discarding every separator, rejoins with `". "`, injects
        /// `[Part N]` markers, and drops blank-line runs entirely. Asserting `.exact` on characters
        /// here fires on the first document with an oversized chunk, which is a false alarm in the
        /// instrument built to stop false confidence.
        ///
        /// Words are what actually survive. The floor sits just below 1.0 rather than at it because
        /// the markers only ever add, so the true statement is "no word is lost".
        case tokenLimited = "token-limited"

        var conservationFromPredecessor: IngestionConservation {
            switch self {
            case .extraction: return .exact
            case .chunked: return .atLeast(0.98)
            case .sanitized: return .exact
            case .tokenLimited: return .atLeastWords(0.99)
            }
        }
    }

    let documentName: String
    private(set) var readings: [IngestionStageReading] = []

    init(documentName: String) {
        self.documentName = documentName
    }

    /// Record the text handed to chunking. Call once, first.
    mutating func recordExtraction(characters: Int, words: Int) {
        readings.append(
            IngestionStageReading(
                stage: Stage.extraction.rawValue,
                chunkCount: 0,
                characterCount: characters,
                wordCount: words
            )
        )
    }

    /// Record a chunked stage, counting the text itself rather than any recorded metadata.
    ///
    /// Also notes whether every chunk came out the same length, which the reading alone cannot say
    /// because it keeps only the total.
    mutating func record(_ stage: Stage, chunkTexts: [String]) {
        readings.append(
            IngestionStageReading(
                stage: stage.rawValue,
                chunkCount: chunkTexts.count,
                characterCount: chunkTexts.reduce(0) { $0 + $1.count },
                wordCount: chunkTexts.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
            )
        )
        uniformChunkLengths = chunkTexts.count > 3 && Set(chunkTexts.map(\.count)).count == 1
    }

    /// Every consecutive transition, with its band applied.
    var transitions: [IngestionTransition] {
        guard readings.count >= 2 else { return [] }
        let bands = Dictionary(
            uniqueKeysWithValues: Stage.allCases.map { ($0.rawValue, $0.conservationFromPredecessor) }
        )
        return zip(readings, readings.dropFirst()).map { previous, current in
            let band = bands[current.stage] ?? .atLeast(0)
            let inUnits = band.usesWords ? previous.wordCount : previous.characterCount
            let outUnits = band.usesWords ? current.wordCount : current.characterCount
            return IngestionTransition(
                from: previous.stage,
                to: current.stage,
                // A zero input is not a violation of anything, it is an empty document. Reporting 1.0
                // keeps an empty file out of the anomaly list.
                ratio: inUnits == 0 ? 1.0 : Double(outUnits) / Double(inUnits),
                conservation: band,
                charactersIn: previous.characterCount,
                charactersOut: current.characterCount,
                chunksIn: previous.chunkCount,
                chunksOut: current.chunkCount
            )
        }
    }

    /// Transitions that left their band.
    var anomalies: [IngestionTransition] { transitions.filter(\.isAnomalous) }

    /// True when every chunk came out the same length, which no real document produces.
    ///
    /// A stage whose output has stopped varying with its input can still conserve characters in
    /// aggregate, so no ratio can see it. `verifyTokenizerCounts` makes the same argument one layer
    /// down, about the tokenizer; this makes it about the chunker, which that check does not watch.
    /// Only past three chunks, because two chunks of equal length is a coincidence, not a signal.
    var hasDegenerateChunkDistribution: Bool {
        guard let last = readings.last, last.chunkCount > 3 else { return false }
        return uniformChunkLengths
    }

    /// Set by `record(_:chunkTexts:)` for the most recent chunked stage.
    private var uniformChunkLengths = false


    /// Write the ledger to the log, at `warning` when anything is out of band and `info` otherwise.
    ///
    /// Deliberately logs the healthy case too. A line that only ever appears when something is wrong
    /// is a line nobody recognises when it finally appears, and this project has already been caught
    /// by a guard that swallowed its own failure (`probe_afm_advanced_canary.sh || true`).
    func emit() {
        let problems = anomalies
        let degenerate = hasDegenerateChunkDistribution

        if problems.isEmpty && !degenerate {
            let trail = transitions
                .map { String(format: "%@ %.3f", $0.to, $0.ratio) }
                .joined(separator: ", ")
            Log.info("[IngestionLedger] \(documentName): \(trail)", category: .ingestion)
            return
        }

        for transition in problems {
            Log.warning("[IngestionLedger] \(documentName): \(transition.summary)", category: .ingestion)
        }
        if degenerate {
            Log.warning(
                "[IngestionLedger] \(documentName): every chunk came out the same length, " +
                "which no real document produces. A stage has stopped varying with its input.",
                category: .ingestion
            )
        }
    }
}

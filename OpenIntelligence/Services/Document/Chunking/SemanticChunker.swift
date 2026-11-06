//
//  SemanticChunker.swift
//  OpenIntelligence
//
//  Advanced semantic chunking with topic detection and metadata enrichment.
//
//  ## Semantic Boundary Detection
//
//  This chunker implements research-paper-level semantic boundary detection:
//  1. **Embedding-Based Topic Detection**: Computes sentence embeddings and detects
//     topic shifts where cosine similarity between adjacent sentences drops below threshold.
//  2. **Linguistic Cue Detection**: Uses transition phrases as secondary boundary signals.
//  3. **Section Header Detection**: Recognizes markdown headers, numbered sections, etc.
//
//  The embedding approach provides semantically coherent chunks that align with actual
//  topic boundaries rather than arbitrary word counts.
//
//  ## This is not "late chunking"
//
//  Earlier revisions of this file, and the container settings UI, called the above
//  "Late Chunking". That names a different technique. Late chunking (Günther et al.)
//  embeds the *entire document* through a long-context model and then mean-pools the
//  resulting token vectors within each chunk span, so every chunk vector is computed
//  with full-document context in the attention window. What runs here embeds individual
//  sentences to decide *where to cut* and returns boundary positions; the chunks are
//  then embedded independently and carry no cross-chunk context. The two are not
//  interchangeable, and conflating them overstates what the retrieval stack does.
//  Real late chunking is tracked as its own roadmap row.
//
//  See also:
//  - https://developer.apple.com/documentation/naturallanguage
//  - https://developer.apple.com/documentation/accelerate/vdsp
//

import Foundation
import NaturalLanguage
import Accelerate

// Notification name for SemanticChunker diagnostics updates
extension Notification.Name {
    nonisolated static let semanticChunkerDiagnosticsUpdated = Notification.Name("SemanticChunkerDiagnosticsUpdated")
}

/// Enhanced chunking with semantic boundaries and metadata
///
/// `nonisolated` since 5.7. Chunking is CPU work with no UI state, and it ran on the main actor
/// only because that is this module's default. A large text file held the main thread there for
/// minutes, and iOS ended the app when a scene update waited ten seconds for it (an 88 MB file
/// on 2026-10-09). A caller on the main actor can still call `chunkText` directly;
/// `chunkTextOffMainActor` is the entry point that leaves it. An instance is not thread-safe (it
/// caches NaturalLanguage taggers), so make one per task and keep it there.
nonisolated class SemanticChunker {

    // MARK: - Diagnostics

    struct ChunkingDiagnostics: Sendable {
        let language: NLLanguage?
        let languageHypotheses: [NLLanguage: Double]
        let sectionCount: Int
        let topicBoundaryCount: Int
        let embeddingBoundaryCount: Int // New: boundaries detected via embedding similarity
        let totalSentences: Int
        let averageSentenceLengthWords: Double
        let averageWordsPerChunk: Double
        let overlapWords: Int
        let warnings: [String]
    }

    let languageRecognizer = NLLanguageRecognizer()
    var lastDiagnostics: ChunkingDiagnostics?

    /// Optional embedding service for semantic boundary detection
    /// When set, topic boundaries are detected via sentence embedding similarity
    var embeddingService: EmbeddingService?

    /// Threshold for embedding-based topic boundary detection
    /// A drop in cosine similarity below this triggers a chunk boundary
    /// Default 0.65 balances sensitivity with avoiding over-segmentation
    var embeddingSimilarityThreshold: Float = 0.65

    func diagnostics() -> ChunkingDiagnostics? { lastDiagnostics }

    // Notification posted when diagnostics are updated (see global Notification.Name extension)

    // MARK: - Cached NLP Instances (avoid per-chunk allocation)
    // NLTagger and NLTokenizer creation is ~0.5-1ms each.
    // With 200 chunks × 3 taggers + 2 tokenizers = 1000+ allocations → ~0.5-1s wasted.
    // Caching and reusing via .string reassignment eliminates this overhead entirely.

    let cachedWordTokenizer = NLTokenizer(unit: .word)
    let cachedSentenceTokenizer = NLTokenizer(unit: .sentence)
    let cachedNERTagger = NLTagger(tagSchemes: [.nameType])
    let cachedLexicalTagger = NLTagger(tagSchemes: [.lexicalClass])
    let cachedKeywordTagger = NLTagger(tagSchemes: [.lemma, .lexicalClass, .language])

    // MARK: - Progress

    /// Where a chunking run is, for a caller that shows progress.
    struct ChunkingProgress: Sendable {
        enum Phase: Sendable {
            /// The passes over the whole text that find headings, topic words and tables.
            case findingStructure
            case cuttingChunks
            /// Every chunk is cut; short ones are being merged and the run's statistics taken.
            case finishing
        }
        let phase: Phase
        let chunksCreated: Int
        /// The share of the text already cut into chunks, 0 to 1.
        let fractionOfText: Double
    }

    enum ChunkingError: Error, Equatable {
        /// The text needs more chunks than one document may have.
        case tooManyChunks(limit: Int)
    }

    /// The most chunks one document may have (about 65,000 pages at 260 words a chunk). Through
    /// 5.6 a longer text was cut off here without a word; `stoppedAtChunkLimit` now says so.
    static let maxChunks = 50_000

    /// `maxChunks`, as a property so a test can reach the limit with a short text.
    var chunkLimit = SemanticChunker.maxChunks

    /// True when the last run left text unchunked because it reached `chunkLimit`.
    var stoppedAtChunkLimit = false

    /// How many chunks at the start of a text are logged one by one. After these the trace gets
    /// one line a thousand chunks: four lines for every chunk of a long text turned the trace
    /// file over every ten seconds, and the lines that named the file were gone before anyone
    /// could read them (an iPhone, 2026-10-09).
    static let chunksLoggedOneByOne = 40
    var logsEachChunk = true
    /// Chunks of this run that were cut down to `maxSize` words, for the one line at the end.
    var chunksCutToMaxSize = 0

    /// Whether a text of `wordCount` words is certain to need more than `chunkLimit` chunks. A
    /// chunk holds at most `maxSize` words, so more words than that many chunks can hold cannot
    /// fit. False says nothing: overlap makes the real number of chunks higher than this floor.
    static func exceedsChunkLimit(wordCount: Int, maxSize: Int, chunkLimit: Int = maxChunks) -> Bool {
        guard maxSize > 0, chunkLimit >= 0 else { return false }
        let (capacity, overflowed) = chunkLimit.multipliedReportingOverflow(by: maxSize)
        return !overflowed && wordCount > capacity
    }

    /// The words the chunker's tokenizer finds in `text`, counted on the concurrent pool. The
    /// import asks this first for a very large text, so that one which cannot fit is refused
    /// before it is cleaned, stored or scanned.
    @concurrent
    static func wordCountOffMainActor(_ text: String) async -> Int {
        SemanticChunker().tokenWordCount(text)
    }

    /// Chunks on the concurrent pool instead of the caller's actor. Throws when the task is
    /// cancelled, and when the text needs more than `chunkLimit` chunks, so a result cut short
    /// by either never reaches the caller. `progress` is called on that pool: once before the
    /// structure passes, every 25 chunks, and once when the last chunk is cut.
    @concurrent
    static func chunkTextOffMainActor(
        _ text: String,
        documentId: UUID,
        config: ChunkingConfig,
        pageNumbers: [Int: Range<String.Index>]? = nil,
        documentCategory: DocumentSemanticCategory? = nil,
        chunkLimit: Int = SemanticChunker.maxChunks,
        progress: (@Sendable (ChunkingProgress) -> Void)? = nil
    ) async throws -> [EnhancedChunk] {
        let chunker = SemanticChunker()
        chunker.chunkLimit = chunkLimit
        let chunks = chunker.chunkText(
            text,
            documentId: documentId,
            config: config,
            pageNumbers: pageNumbers,
            documentCategory: documentCategory,
            progress: progress,
            failFast: true
        )
        try Task.checkCancellation()
        if chunker.stoppedAtChunkLimit { throw ChunkingError.tooManyChunks(limit: chunkLimit) }
        return chunks
    }

    /// Tells the diagnostics screen about the last run. Its observer is a SwiftUI view, so the
    /// notification is posted on the main thread whichever thread the chunker ran on.
    func publishDiagnostics() {
        let diagnostics = lastDiagnostics
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .semanticChunkerDiagnosticsUpdated, object: diagnostics)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .semanticChunkerDiagnosticsUpdated, object: diagnostics)
            }
        }
    }

}

//
//  SemanticChunker+Chunking.swift
//  OpenIntelligence
//
//  Part of SemanticChunker, moved from SemanticChunker.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import Accelerate

nonisolated extension SemanticChunker {
    // MARK: - Token/Language helpers

    func tokenWordCount(_ text: String) -> Int {
        cachedWordTokenizer.string = text
        var count = 0
        cachedWordTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func estimateSentenceCount(for text: String) -> Int {
        cachedSentenceTokenizer.string = text
        var count = 0
        cachedSentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func averageSentenceLength(for text: String) -> Double {
        cachedSentenceTokenizer.string = text
        var totalWords = 0
        var sentenceCount = 0

        cachedSentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            totalWords += tokenWordCount(sentence)
            sentenceCount += 1
            return true
        }
        guard sentenceCount > 0 else { return 0.0 }
        return Double(totalWords) / Double(sentenceCount)
    }

    private func detectLanguage(for text: String) -> NLLanguage? {
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        return languageRecognizer.dominantLanguage
    }

    private func languageHypotheses(for text: String) -> [NLLanguage: Double] {
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        return languageRecognizer.languageHypotheses(withMaximum: 3)
    }

    struct ChunkingConfig: Sendable {
        // Token limit: CoreML embedding model has 512 token max (510 usable after CLS/SEP)
        // Average English word ≈ 1.3 tokens, but technical text can be 1.5-2.0 tokens/word
        // SAFE LIMIT: 510 tokens / 1.5 tokens/word ≈ 340 max words
        // BUT: RAGService adds contextual prefix (~20 words) during embedding
        // ACTUAL LIMIT: 340 - 30 = 310 words to leave room for prefix

        // The ceilings the ingestion pipeline actually enforces, named so that anything
        // presenting them to a user can read them instead of restating them.
        //
        // `DocumentProcessor` clamps every request to these before chunking, so a preference
        // above them is silently discarded. The Library Settings sliders used to run to 600 and
        // 200 against these 260 and 50, and its Balanced caption promised a "280-400 word
        // target" that the clamp made unreachable. Both were literals typed beside the real
        // values rather than derived from them, which is the failure this exists to prevent.

        /// Hard ceiling on a chunk. 310 words plus the roughly 30 word contextual prefix the
        /// embedding step prepends lands near the Core ML model's 510 token limit.
        static let safeMaxSize = 310
        /// Highest target size the pipeline will honour, leaving room for variance under
        /// `safeMaxSize`.
        static let maxTargetSize = safeMaxSize - 50
        /// Highest overlap the pipeline will honour, capped to prevent index bloat.
        static let maxOverlap = 50
        /// Lowest target size offered, below which chunks stop carrying usable context.
        static let minTargetSize = 100

        var targetSize: Int = maxTargetSize // 260 words ≈ 380 tokens (safe margin)
        var minSize: Int = 80 // Prevent tiny fragments
        var maxSize: Int = safeMaxSize // HARD LIMIT: plus a ~30 word prefix = ~340 total
        var overlap: Int = maxOverlap // ~17% overlap for continuity
        var useTopicDetection: Bool = true
        var preserveStructure: Bool = true
        /// Parent window size in characters for hierarchical context
        /// This expands the chunk by ±N chars (snapped to sentence boundaries)
        /// Reduced from 500→250 to fit more chunks in Apple FM's 4K context window
        var parentWindowChars: Int = 250

        // MARK: - Content-Adaptive Presets

        /// For technical manuals, specs, reference docs - balanced for lookup AND context
        /// CRITICAL: maxSize must stay ≤310 words (340 - 30 for contextual prefix)
        static let technicalReference = ChunkingConfig(
            targetSize: 240,
            minSize: 80,
            maxSize: 310,  // HARD LIMIT: leaves room for ~30 word contextual prefix
            overlap: 45,
            useTopicDetection: true,
            preserveStructure: true
        )

        /// For narrative content (books, articles, reports - longer chunks for coherence)
        /// Still respects 310 word max (leaves room for contextual prefix)
        // 280/55 declared here previously, and `DocumentProcessor` clamps every request to
        // `maxTargetSize` (260) and `maxOverlap` (50), so this preset asked for two values it
        // never received. Office documents and transcripts were already being chunked at 260/50.
        // Set to the real ceilings so the declaration matches what runs; `ChunkingLimitsTests`
        // now asserts that for every preset.
        static let narrative = ChunkingConfig(
            targetSize: maxTargetSize,
            minSize: 100,
            maxSize: safeMaxSize,  // HARD LIMIT: leaves room for ~30 word contextual prefix
            overlap: maxOverlap,
            useTopicDetection: true,
            preserveStructure: true
        )

        /// For code files (preserve function/class boundaries)
        /// Code often tokenizes worse (symbols, camelCase = multiple tokens)
        static let code = ChunkingConfig(
            targetSize: 180,
            minSize: 50,
            maxSize: 280,  // Conservative for code + contextual prefix
            overlap: 35,
            useTopicDetection: false, // Code doesn't have natural topics like prose
            preserveStructure: true
        )

        /// Recommends optimal chunking config based on document type and optional library strategy.
        static func recommended(for documentType: DocumentType, strategyOverride: String? = nil) -> ChunkingConfig {
            let baseline: ChunkingConfig = switch documentType {
            case .pdf:
                // PDFs benefit from larger chunks for complete sections
                .technicalReference

            case .swift, .python, .javascript, .typescript, .java,
                 .cpp, .c, .objc, .go, .rust, .ruby, .php, .html,
                 .css, .json, .xml, .yaml, .sql, .shell, .code:
                .code

            case .markdown, .text, .rtf:
                // Could be either - use balanced default
                ChunkingConfig()

            case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
                // Office docs are usually longer-form
                .narrative

            case .image, .png, .jpeg, .heic, .tiff, .gif:
                // OCR'd images - use technical preset (often scanned manuals)
                .technicalReference

            case .csv:
                // Data files - small chunks
                .technicalReference

            case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
                // Transcribed audio/video - use narrative preset
                .narrative

            case .unknown:
                ChunkingConfig()
            }

            guard let strategyOverride else {
                return baseline
            }

            switch strategyOverride {
            case "densePrecision":
                var config = baseline
                config.targetSize = min(config.targetSize, 190)
                config.minSize = min(config.minSize, 60)
                config.maxSize = min(config.maxSize, 240)
                config.overlap = min(max(config.overlap, 30), 45)
                config.parentWindowChars = min(config.parentWindowChars, 180)
                config.useTopicDetection = true
                config.preserveStructure = true
                return config

            case "elastic":
                var config = baseline
                config.targetSize = min(max(config.targetSize, 300), 310)
                config.minSize = max(config.minSize, 100)
                config.maxSize = 310
                config.overlap = max(config.overlap, 65)
                config.parentWindowChars = max(config.parentWindowChars, 320)
                config.useTopicDetection = true
                config.preserveStructure = true
                return config

            default:
                return baseline
            }
        }
    }

    struct EnhancedChunk: Sendable {
        let content: String
        /// Expanded context window (parent chunk) used for LLM context assembly
        let parentContent: String?
        let metadata: ChunkMetadata
        let embedding: [Float]?

        struct ChunkMetadata: Sendable {
            let documentId: UUID
            let chunkIndex: Int
            let totalChunks: Int
            let pageNumber: Int?
            let sectionTitle: String?
            /// Hierarchical path of section headers leading to this chunk
            /// Example: ["Chapter 5", "5.3 Fluids", "Engine Oil"]
            /// Used for disambiguation: "What's the oil capacity in Chapter 5?" vs "...in Chapter 8?"
            let sectionPath: [String]
            let wordCount: Int
            let characterCount: Int
            let topKeywords: [String]
            let semanticDensity: Float  // How information-dense this chunk is
            let hasNumericData: Bool
            let hasListStructure: Bool
            let startOffset: Int
            let endOffset: Int
            /// Named entities extracted via NLTagger (persons, organizations, places, technical terms)
            /// Used by EntityIndexService for cross-document correlation and GraphRAG-lite expansion
            let entities: [String]
            /// Abbreviation→expansion mappings extracted from inline definitions.
            /// Example: ["ED": "Emotional Dysregulation", "ODD": "Oppositional Defiant Disorder"]
            let abbreviations: [String: String]
            let documentCategory: DocumentSemanticCategory?
            let chunkType: ChunkSemanticType
            let tableTitle: String?
            let hasCrossReferences: Bool
            let resolvedReferences: [String]
        }
    }

    /// Chunk text with semantic boundaries and rich metadata
    func chunkText(
        _ text: String,
        documentId: UUID,
        config: ChunkingConfig = ChunkingConfig(),
        pageNumbers: [Int: Range<String.Index>]? = nil,
        documentCategory: DocumentSemanticCategory? = nil,
        progress: (@Sendable (ChunkingProgress) -> Void)? = nil,
        failFast: Bool = false
    ) -> [EnhancedChunk] {
        Log.debug("[SemanticChunker] Starting advanced chunking", category: .ingestion)
        Log.debug("[SemanticChunker] Target: \(config.targetSize)w, Min: \(config.minSize)w, Max: \(config.maxSize)w", category: .ingestion)
        Log.debug("[SemanticChunker] Overlap: \(config.overlap)w", category: .ingestion)

        stoppedAtChunkLimit = false

        // Safety check: if text is too small, just return one chunk
        let wordCount = tokenWordCount(text)
        if wordCount < config.minSize {
            Log.warning("[SemanticChunker] Text too small (\(wordCount) words); creating single chunk", category: .ingestion)
            let small = createSingleChunk(
                text,
                documentId: documentId,
                pageNumbers: pageNumbers,
                documentCategory: documentCategory
            )
            // Update diagnostics for tiny docs
            self.lastDiagnostics = ChunkingDiagnostics(
                language: detectLanguage(for: text),
                languageHypotheses: languageHypotheses(for: text),
                sectionCount: 0,
                topicBoundaryCount: 0,
                embeddingBoundaryCount: 0,
                totalSentences: estimateSentenceCount(for: text),
                averageSentenceLengthWords: averageSentenceLength(for: text),
                averageWordsPerChunk: Double(small.metadata.wordCount),
                overlapWords: config.overlap,
                warnings: ["Small document: produced single chunk"]
            )
            publishDiagnostics()
            return [small]
        }

        // A chunk holds at most `maxSize` words, so a text with more words than this cannot fit
        // in `chunkLimit` chunks. Said now, before the passes over the whole text.
        if failFast, Self.exceedsChunkLimit(wordCount: wordCount, maxSize: config.maxSize, chunkLimit: chunkLimit) {
            stoppedAtChunkLimit = true
            Log.warning(
                "[SemanticChunker] \(wordCount) words cannot fit in \(chunkLimit) chunks of \(config.maxSize) words; not chunking",
                category: .ingestion)
            return []
        }

        progress?(ChunkingProgress(phase: .findingStructure, chunksCreated: 0, fractionOfText: 0))

        // 1. Detect sections and structure
        let sections = detectSections(text)
        Log.debug("[SemanticChunker] Detected \(sections.count) sections", category: .ingestion)
        if failFast, Task.isCancelled { return [] }

        // 2. Detect topic boundaries if enabled (linguistic cues only in sync version)
        let topicBoundaries = config.useTopicDetection ? detectTopicBoundaries(text) : []
        Log.debug("[SemanticChunker] Detected \(topicBoundaries.count) linguistic topic boundaries", category: .ingestion)
        if failFast, Task.isCancelled { return [] }

        // 2.5. Detect table blocks for atomic preservation
        let tableBlocks = detectTableBlocks(text)

        // 3. Chunk with semantic awareness
        var chunks: [EnhancedChunk] = []
        var currentPosition = text.startIndex
        // The character offset of `currentPosition`, kept as the loop walks forward. Each chunk's
        // offsets come from it; measuring them from the start of the text was a pass over
        // everything before the chunk, for every chunk.
        var positionOffset = 0
        // Counted once, and only for a caller that shows progress.
        let totalCharacters = progress == nil ? 0 : text.count
        // The end of the furthest chunk cut so far, for the limit check after the loop.
        var coveredUpTo = text.startIndex
        var chunkIndex = 0
        let maxChunks = chunkLimit

        chunksCutToMaxSize = 0
        while currentPosition < text.endIndex && chunkIndex < maxChunks {
            logsEachChunk = chunkIndex < Self.chunksLoggedOneByOne
            if logsEachChunk {
                Log.verbose("[SemanticChunker] Processing chunk \(chunkIndex + 1)", category: .ingestion)
            } else if chunkIndex % 1_000 == 0 {
                Log.info("[SemanticChunker] \(chunkIndex) chunks cut so far", category: .ingestion)
            }

            if failFast, Task.isCancelled { return [] }
            if let progress, chunkIndex % 25 == 0 {
                let fraction = totalCharacters > 0 ? min(1, Double(positionOffset) / Double(totalCharacters)) : 0
                progress(ChunkingProgress(phase: .cuttingChunks, chunksCreated: chunkIndex, fractionOfText: fraction))
            }

            // One autorelease pool for each chunk. Cutting a chunk hands its text to Foundation
            // and NaturalLanguage several times, and what they leave behind is released only
            // when a pool drains. With no pool inside the loop that was about 123 KB a chunk,
            // held until the whole text was cut: 392 MB for 4 MB of JSON Lines against 47 MB
            // with the pool (measured 2026-10-09), and an iPhone ended the app for memory near
            // chunk 19,750 of one long text, twice.
            let reachedTheEnd: Bool = autoreleasepool {
                // Safety check: if we're too close to the end, create final chunk and stop.
                // Asked as a walk of at most ten characters. Measuring the distance to the end of the
                // text here cost one pass over the rest of the document for every chunk.
                if text.index(currentPosition, offsetBy: 10, limitedBy: text.endIndex) == nil {
                    // Less than 10 characters remaining - create final micro-chunk if needed
                    if currentPosition < text.endIndex {
                        let finalText = String(text[currentPosition..<text.endIndex])
                        let wordCount = tokenWordCount(finalText)
                        if wordCount > 0 {
                            if logsEachChunk {
                                Log.verbose("[SemanticChunker] Final chunk \(chunkIndex + 1): \(wordCount) words", category: .ingestion)
                            }
                            let metadata = extractMetadata(
                                chunkText: finalText,
                                chunkIndex: chunkIndex,
                                documentId: documentId,
                                range: currentPosition..<text.endIndex,
                                startOffset: positionOffset,
                                in: text,
                                sections: sections,
                                pageNumbers: pageNumbers,
                                documentCategory: documentCategory
                            )
                            let parentContent = buildParentContent(
                                for: currentPosition ..< text.endIndex,
                                in: text,
                                windowChars: config.parentWindowChars
                            )
                            chunks.append(EnhancedChunk(
                                content: finalText,
                                parentContent: parentContent,
                                metadata: metadata,
                                embedding: nil
                            ))
                        }
                    }
                    return true
                }

                // Find optimal chunk end
                var chunkRange = findOptimalChunkRange(
                    in: text,
                    from: currentPosition,
                    config: config,
                    topicBoundaries: topicBoundaries,
                    sections: sections,
                    tableBlocks: tableBlocks
                )

                // Safety check: ensure range is valid and not empty
                guard chunkRange.lowerBound < chunkRange.upperBound else {
                    Log.warning("[SemanticChunker] Empty range detected; stopping chunking", category: .ingestion)
                    return true
                }

                // HARD LIMIT ENFORCEMENT: Truncate chunk to maxSize words
                // This prevents token truncation during embedding (510 token limit)
                var chunkText = String(text[chunkRange])
                var wordCount = tokenWordCount(chunkText)

                if wordCount > config.maxSize {
                    chunksCutToMaxSize += 1
                    if logsEachChunk {
                        Log.warning("[SemanticChunker] HARD LIMIT: Chunk \(chunkIndex + 1) has \(wordCount) words, truncating to \(config.maxSize)", category: .ingestion)
                    }

                    // Use cached NLTokenizer to properly count words (handles tabs, special chars)
                    // This matches how tokenWordCount() works
                    cachedWordTokenizer.string = chunkText

                    var wordRanges: [Range<String.Index>] = []
                    cachedWordTokenizer.enumerateTokens(in: chunkText.startIndex..<chunkText.endIndex) { range, _ in
                        wordRanges.append(range)
                        return wordRanges.count < config.maxSize  // Stop after maxSize words
                    }

                    if let lastRange = wordRanges.last {
                        // Truncate to end of last word within limit, or to the last space before it when one is within
                        // 200 characters (5.7). The tokenizer's words end inside a run of text with no spaces, such as
                        // a JSON record or a line of code, so the cut left half a record at the end of the passage.
                        // Only inside an ASCII run: in Chinese, Japanese or Thai a word's end is the boundary itself,
                        // with no space to look for (review, 2026-10-20).
                        var cut = lastRange.upperBound
                        let cutsARun = cut < chunkText.endIndex && !chunkText[cut].isWhitespace
                            && !chunkText[chunkText.index(before: cut)].isWhitespace
                            && chunkText[cut].isASCII && chunkText[chunkText.index(before: cut)].isASCII
                        if cutsARun, let space = chunkText[..<cut].lastIndex(where: \.isWhitespace),
                            space > chunkText.startIndex, chunkText.distance(from: space, to: cut) <= 200
                        {
                            cut = space
                        }
                        chunkText = String(chunkText[chunkText.startIndex..<cut])

                        // Recalculate the range to match truncated text
                        let newEnd = text.index(currentPosition, offsetBy: chunkText.count, limitedBy: text.endIndex) ?? text.endIndex
                        chunkRange = currentPosition..<newEnd
                    }

                    wordCount = tokenWordCount(chunkText)
                    if logsEachChunk {
                        Log.info("[SemanticChunker] Chunk \(chunkIndex + 1) ACTUALLY truncated to \(wordCount) words", category: .ingestion)
                    }
                }
                if logsEachChunk {
                    Log.verbose("[SemanticChunker] Chunk \(chunkIndex + 1): \(wordCount) words", category: .ingestion)
                }

                // Extract metadata
                let metadata = extractMetadata(
                    chunkText: chunkText,
                    chunkIndex: chunkIndex,
                    documentId: documentId,
                    range: chunkRange,
                    startOffset: positionOffset,
                    in: text,
                    sections: sections,
                    pageNumbers: pageNumbers,
                    documentCategory: documentCategory
                )

                let parentContent = buildParentContent(
                    for: chunkRange,
                    in: text,
                    windowChars: config.parentWindowChars
                )
                chunks.append(EnhancedChunk(
                    content: chunkText,
                    parentContent: parentContent,
                    metadata: metadata,
                    embedding: nil  // Will be added later
                ))

                coveredUpTo = max(coveredUpTo, chunkRange.upperBound)

                // Move to next chunk with overlap
                let nextPosition = advancePosition(
                    from: currentPosition,
                    chunkEnd: chunkRange.upperBound,
                    overlap: config.overlap,
                    in: text
                )

                // Safety check: ensure we're making progress
                if nextPosition <= currentPosition {
                    Log.warning("[SemanticChunker] No progress made; advancing by 1 character to prevent infinite loop", category: .ingestion)
                    currentPosition = text.index(after: currentPosition)
                    positionOffset += 1
                } else {
                    positionOffset += text.distance(from: currentPosition, to: nextPosition)
                    currentPosition = nextPosition
                }

                chunkIndex += 1
                return false
            }
            if reachedTheEnd { break }
        }

        // At the limit the loop's position is the start of the last chunk's overlap, which is
        // text already cut. Only words after the furthest chunk count as left over; a tail of
        // punctuation or spaces is not a chunk when the loop ends by itself either.
        if chunkIndex >= maxChunks, text[coveredUpTo...].contains(where: { $0.isLetter || $0.isNumber }) {
            stoppedAtChunkLimit = true
            Log.warning(
                "[SemanticChunker] Stopped at the \(maxChunks)-chunk limit with text left unchunked", category: .ingestion)
        }

        Log.debug(
            "[SemanticChunker] Created \(chunks.count) semantically-aware chunks (\(chunksCutToMaxSize) cut to the \(config.maxSize)-word limit)",
            category: .ingestion)

        // What follows is the merge and four more passes over the whole text for the run's
        // statistics. A cancelled import does not wait for them.
        if failFast, Task.isCancelled { return [] }
        progress?(ChunkingProgress(phase: .finishing, chunksCreated: chunks.count, fractionOfText: 1))

        // Post-processing: merge micro-chunks (< 15 words) into their preceding sibling
        // These waste embedding computation and pollute the vector store with useless entries
        let minChunkWords = 15
        var mergedChunks: [EnhancedChunk] = []
        for chunk in chunks {
            if chunk.metadata.wordCount < minChunkWords && !mergedChunks.isEmpty {
                // Merge into the last chunk
                let prev = mergedChunks.removeLast()
                let mergedContent = prev.content + "\n" + chunk.content
                let mergedParent = prev.parentContent.map { p in
                    chunk.parentContent.map { p + "\n" + $0 } ?? p
                } ?? chunk.parentContent
                let mergedMeta = EnhancedChunk.ChunkMetadata(
                    documentId: prev.metadata.documentId,
                    chunkIndex: prev.metadata.chunkIndex,
                    totalChunks: prev.metadata.totalChunks,
                    pageNumber: prev.metadata.pageNumber,
                    sectionTitle: prev.metadata.sectionTitle ?? chunk.metadata.sectionTitle,
                    sectionPath: prev.metadata.sectionPath.isEmpty ? chunk.metadata.sectionPath : prev.metadata.sectionPath,
                    wordCount: prev.metadata.wordCount + chunk.metadata.wordCount,
                    characterCount: prev.metadata.characterCount + chunk.metadata.characterCount,
                    topKeywords: Self.orderedUnion(prev.metadata.topKeywords, chunk.metadata.topKeywords),
                    semanticDensity: (prev.metadata.semanticDensity + chunk.metadata.semanticDensity) / 2.0,
                    hasNumericData: prev.metadata.hasNumericData || chunk.metadata.hasNumericData,
                    hasListStructure: prev.metadata.hasListStructure || chunk.metadata.hasListStructure,
                    startOffset: prev.metadata.startOffset,
                    endOffset: chunk.metadata.endOffset,
                    entities: Self.orderedUnion(prev.metadata.entities, chunk.metadata.entities),
                    abbreviations: prev.metadata.abbreviations.merging(chunk.metadata.abbreviations) { first, _ in first },
                    documentCategory: prev.metadata.documentCategory ?? chunk.metadata.documentCategory,
                    chunkType: prev.metadata.chunkType == .warning || chunk.metadata.chunkType == .warning ? .warning : prev.metadata.chunkType,
                    tableTitle: prev.metadata.tableTitle ?? chunk.metadata.tableTitle,
                    hasCrossReferences: prev.metadata.hasCrossReferences || chunk.metadata.hasCrossReferences,
                    resolvedReferences: Array(Set(prev.metadata.resolvedReferences + chunk.metadata.resolvedReferences)).sorted()
                )
                mergedChunks.append(EnhancedChunk(content: mergedContent, parentContent: mergedParent, metadata: mergedMeta, embedding: nil))
                Log.debug("[SemanticChunker] Merged micro-chunk (\(chunk.metadata.wordCount) words) into previous", category: .ingestion)
            } else {
                mergedChunks.append(chunk)
            }
        }

        if mergedChunks.count < chunks.count {
            Log.info("[SemanticChunker] Merged \(chunks.count - mergedChunks.count) micro-chunks (<\(minChunkWords) words)", category: .ingestion)
        }

        let finalChunks = mergedChunks
        printChunkStatistics(finalChunks)

        // Update diagnostics for UI/telemetry
        let avgWordsPerChunk = finalChunks.isEmpty
            ? 0.0
            : Double(finalChunks.map { $0.metadata.wordCount }.reduce(0, +)) / Double(finalChunks.count)

        self.lastDiagnostics = ChunkingDiagnostics(
            language: detectLanguage(for: text),
            languageHypotheses: languageHypotheses(for: text),
            sectionCount: sections.count,
            topicBoundaryCount: topicBoundaries.count,
            embeddingBoundaryCount: 0, // Sync version doesn't use embedding boundaries
            totalSentences: estimateSentenceCount(for: text),
            averageSentenceLengthWords: averageSentenceLength(for: text),
            averageWordsPerChunk: avgWordsPerChunk,
            overlapWords: config.overlap,
            warnings: []
        )
        publishDiagnostics()

        return finalChunks
    }

    // MARK: - Async Chunking with Embedding Boundaries

    /// Chunk text with semantic boundaries detected via sentence embeddings.
    ///
    /// This is the preferred method when an EmbeddingService is available.
    /// It combines three levels of semantic boundary detection:
    /// 1. Section headers (markdown, numbered, ALL CAPS)
    /// 2. Linguistic transition phrases (However, Moreover, etc.)
    /// 3. **Embedding similarity drops** (research-paper level)
    ///
    /// The embedding approach identifies genuine topic shifts by comparing
    /// sentence embeddings and detecting where cosine similarity drops below
    /// the threshold (default 0.65).
    ///
    /// - Note: Pass `ChunkingConfig()` explicitly from MainActor context if needed.
    func chunkTextAsync(
        _ text: String,
        documentId: UUID,
        config: ChunkingConfig,
        pageNumbers: [Int: Range<String.Index>]? = nil,
        documentCategory: DocumentSemanticCategory? = nil
    ) async -> [EnhancedChunk] {
        Log.debug("[SemanticChunker] Starting async chunking with embedding boundaries", category: .ingestion)

        // Detect embedding-based boundaries if service available
        let embeddingBoundaries = await detectEmbeddingBoundaries(text)

        // Merge with linguistic boundaries
        var allBoundaries = config.useTopicDetection ? detectTopicBoundaries(text) : []
        allBoundaries.append(contentsOf: embeddingBoundaries)
        allBoundaries = Array(Set(allBoundaries)).sorted() // Deduplicate and sort

        Log.debug("[SemanticChunker] Total boundaries: \(allBoundaries.count) (embedding: \(embeddingBoundaries.count))", category: .ingestion)

        // Use sync chunking with the combined boundaries
        let chunks = chunkTextWithBoundaries(
            text,
            documentId: documentId,
            config: config,
            topicBoundaries: allBoundaries,
            pageNumbers: pageNumbers,
            documentCategory: documentCategory
        )

        // Update diagnostics with embedding boundary count
        let avgWordsPerChunk = chunks.isEmpty
            ? 0.0
            : Double(chunks.map { $0.metadata.wordCount }.reduce(0, +)) / Double(chunks.count)

        let linguisticCount = config.useTopicDetection ? detectTopicBoundaries(text).count : 0

        self.lastDiagnostics = ChunkingDiagnostics(
            language: detectLanguage(for: text),
            languageHypotheses: languageHypotheses(for: text),
            sectionCount: detectSections(text).count,
            topicBoundaryCount: linguisticCount,
            embeddingBoundaryCount: embeddingBoundaries.count,
            totalSentences: estimateSentenceCount(for: text),
            averageSentenceLengthWords: averageSentenceLength(for: text),
            averageWordsPerChunk: avgWordsPerChunk,
            overlapWords: config.overlap,
            warnings: embeddingService == nil ? ["Embedding service unavailable - using linguistic boundaries only"] : []
        )
        publishDiagnostics()

        return chunks
    }

    /// Internal chunking method that accepts pre-computed topic boundaries
    private func chunkTextWithBoundaries(
        _ text: String,
        documentId: UUID,
        config: ChunkingConfig,
        topicBoundaries: [String.Index],
        pageNumbers: [Int: Range<String.Index>]?,
        documentCategory: DocumentSemanticCategory?
    ) -> [EnhancedChunk] {
        let wordCount = tokenWordCount(text)
        if wordCount < config.minSize {
            return [createSingleChunk(text, documentId: documentId, pageNumbers: pageNumbers, documentCategory: documentCategory)]
        }

        let sections = detectSections(text)
        let tableBlocks = detectTableBlocks(text)

        var chunks: [EnhancedChunk] = []
        var currentPosition = text.startIndex
        var positionOffset = 0
        var chunkIndex = 0
        let maxChunks = chunkLimit

        while currentPosition < text.endIndex, chunkIndex < maxChunks {
            logsEachChunk = chunkIndex < Self.chunksLoggedOneByOne
            // One pool for each chunk, as in `chunkText`.
            let reachedTheEnd: Bool = autoreleasepool {
                if text.index(currentPosition, offsetBy: 10, limitedBy: text.endIndex) == nil {
                    if currentPosition < text.endIndex {
                        let finalText = String(text[currentPosition ..< text.endIndex])
                        let wc = tokenWordCount(finalText)
                        if wc > 0 {
                            let metadata = extractMetadata(
                                chunkText: finalText,
                                chunkIndex: chunkIndex,
                                documentId: documentId,
                                range: currentPosition ..< text.endIndex,
                                startOffset: positionOffset,
                                in: text,
                                sections: sections,
                                pageNumbers: pageNumbers,
                                documentCategory: documentCategory
                            )
                            let parentContent = buildParentContent(
                                for: currentPosition ..< text.endIndex,
                                in: text,
                                windowChars: config.parentWindowChars
                            )
                            chunks.append(EnhancedChunk(
                                content: finalText,
                                parentContent: parentContent,
                                metadata: metadata,
                                embedding: nil
                            ))
                        }
                    }
                    return true
                }

                let chunkRange = findOptimalChunkRange(
                    in: text,
                    from: currentPosition,
                    config: config,
                    topicBoundaries: topicBoundaries,
                    sections: sections,
                    tableBlocks: tableBlocks
                )

                guard chunkRange.lowerBound < chunkRange.upperBound else { return true }

                let chunkText = String(text[chunkRange])
                let metadata = extractMetadata(
                    chunkText: chunkText,
                    chunkIndex: chunkIndex,
                    documentId: documentId,
                    range: chunkRange,
                    startOffset: positionOffset,
                    in: text,
                    sections: sections,
                    pageNumbers: pageNumbers,
                    documentCategory: documentCategory
                )
                let parentContent = buildParentContent(
                    for: chunkRange,
                    in: text,
                    windowChars: config.parentWindowChars
                )
                chunks.append(EnhancedChunk(
                    content: chunkText,
                    parentContent: parentContent,
                    metadata: metadata,
                    embedding: nil
                ))

                let nextPosition = advancePosition(
                    from: currentPosition,
                    chunkEnd: chunkRange.upperBound,
                    overlap: config.overlap,
                    in: text
                )

                if nextPosition <= currentPosition {
                    currentPosition = text.index(after: currentPosition)
                    positionOffset += 1
                } else {
                    positionOffset += text.distance(from: currentPosition, to: nextPosition)
                    currentPosition = nextPosition
                }
                chunkIndex += 1
                return false
            }
            if reachedTheEnd { break }
        }

        Log.debug("[SemanticChunker] Created \(chunks.count) chunks with embedding-aware boundaries", category: .ingestion)
        return chunks
    }

    /// Section with hierarchical level for building section paths
    struct DetectedSection {
        let title: String
        let range: Range<String.Index>
        let level: Int  // 1 = top-level, 2 = subsection, 3 = sub-subsection
    }

}

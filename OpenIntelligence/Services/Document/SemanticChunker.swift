//
//  SemanticChunker.swift
//  OpenIntelligence
//
//  Advanced semantic chunking with topic detection and metadata enrichment.
//
//  ## Semantic Boundary Detection (Late Chunking)
//
//  This chunker implements research-paper-level semantic boundary detection:
//  1. **Embedding-Based Topic Detection**: Computes sentence embeddings and detects
//     topic shifts where cosine similarity between adjacent sentences drops below threshold.
//  2. **Linguistic Cue Detection**: Uses transition phrases as secondary boundary signals.
//  3. **Section Header Detection**: Recognizes markdown headers, numbered sections, etc.
//
//  The embedding approach (sometimes called "Late Chunking" in RAG literature) provides
//  semantically coherent chunks that align with actual topic boundaries rather than
//  arbitrary word counts.
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
    static let semanticChunkerDiagnosticsUpdated = Notification.Name("SemanticChunkerDiagnosticsUpdated")
}

/// Enhanced chunking with semantic boundaries and metadata
class SemanticChunker {

    // MARK: - Diagnostics

    struct ChunkingDiagnostics {
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

    private let languageRecognizer = NLLanguageRecognizer()
    private(set) var lastDiagnostics: ChunkingDiagnostics?

    /// Optional embedding service for semantic boundary detection (Late Chunking)
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

    private let cachedWordTokenizer = NLTokenizer(unit: .word)
    private let cachedSentenceTokenizer = NLTokenizer(unit: .sentence)
    private let cachedNERTagger = NLTagger(tagSchemes: [.nameType])
    private let cachedLexicalTagger = NLTagger(tagSchemes: [.lexicalClass])
    private let cachedKeywordTagger = NLTagger(tagSchemes: [.lemma, .lexicalClass, .language])

    // MARK: - Token/Language helpers

    private func tokenWordCount(_ text: String) -> Int {
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

    struct ChunkingConfig {
        // Token limit: CoreML embedding model has 512 token max (510 usable after CLS/SEP)
        // Average English word ≈ 1.3 tokens, but technical text can be 1.5-2.0 tokens/word
        // SAFE LIMIT: 510 tokens / 1.5 tokens/word ≈ 340 max words
        // BUT: RAGService adds contextual prefix (~20 words) during embedding
        // ACTUAL LIMIT: 340 - 30 = 310 words to leave room for prefix

        var targetSize: Int = 260 // Target ~260 words ≈ 380 tokens (safe margin)
        var minSize: Int = 80 // Prevent tiny fragments
        var maxSize: Int = 310 // HARD LIMIT: 310 words + ~30 word prefix = 340 total
        var overlap: Int = 50 // ~17% overlap for continuity
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
        static let narrative = ChunkingConfig(
            targetSize: 280,
            minSize: 100,
            maxSize: 310,  // HARD LIMIT: leaves room for ~30 word contextual prefix
            overlap: 55,
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

        /// Recommends optimal chunking config based on document type
        static func recommended(for documentType: DocumentType) -> ChunkingConfig {
            switch documentType {
            case .pdf:
                // PDFs benefit from larger chunks for complete sections
                return .technicalReference

            case .swift, .python, .javascript, .typescript, .java,
                 .cpp, .c, .objc, .go, .rust, .ruby, .php, .html,
                 .css, .json, .xml, .yaml, .sql, .shell, .code:
                return .code

            case .markdown, .text, .rtf:
                // Could be either - use balanced default
                return ChunkingConfig()

            case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
                // Office docs are usually longer-form
                return .narrative

            case .image, .png, .jpeg, .heic, .tiff, .gif:
                // OCR'd images - use technical preset (often scanned manuals)
                return .technicalReference

            case .csv:
                // Data files - small chunks
                return .technicalReference

            case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
                // Transcribed audio/video - use narrative preset
                return .narrative

            case .unknown:
                return ChunkingConfig()
            }
        }
    }

    struct EnhancedChunk {
        let content: String
        /// Expanded context window (parent chunk) used for LLM context assembly
        let parentContent: String?
        let metadata: ChunkMetadata
        let embedding: [Float]?

        struct ChunkMetadata {
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
        }
    }

    /// Chunk text with semantic boundaries and rich metadata
    func chunkText(
        _ text: String,
        documentId: UUID,
        config: ChunkingConfig = ChunkingConfig(),
        pageNumbers: [Int: Range<String.Index>]? = nil
    ) -> [EnhancedChunk] {
        Log.debug("[SemanticChunker] Starting advanced chunking", category: .ingestion)
        Log.debug("[SemanticChunker] Target: \(config.targetSize)w, Min: \(config.minSize)w, Max: \(config.maxSize)w", category: .ingestion)
        Log.debug("[SemanticChunker] Overlap: \(config.overlap)w", category: .ingestion)

        // Safety check: if text is too small, just return one chunk
        let wordCount = tokenWordCount(text)
        if wordCount < config.minSize {
            Log.warning("[SemanticChunker] Text too small (\(wordCount) words); creating single chunk", category: .ingestion)
            let small = createSingleChunk(text, documentId: documentId, pageNumbers: pageNumbers)
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
            NotificationCenter.default.post(name: .semanticChunkerDiagnosticsUpdated, object: self.lastDiagnostics)
            return [small]
        }

        // 1. Detect sections and structure
        let sections = detectSections(text)
        Log.debug("[SemanticChunker] Detected \(sections.count) sections", category: .ingestion)

        // 2. Detect topic boundaries if enabled (linguistic cues only in sync version)
        let topicBoundaries = config.useTopicDetection ? detectTopicBoundaries(text) : []
        Log.debug("[SemanticChunker] Detected \(topicBoundaries.count) linguistic topic boundaries", category: .ingestion)

        // 2.5. Detect table blocks for atomic preservation
        let tableBlocks = detectTableBlocks(text)

        // 3. Chunk with semantic awareness
        var chunks: [EnhancedChunk] = []
        var currentPosition = text.startIndex
        var chunkIndex = 0
        // Support documents up to ~65,000 pages (50000 chunks × 260 words × 1.3 pages/260 words)
        let maxChunks = 50000

        while currentPosition < text.endIndex && chunkIndex < maxChunks {
            Log.verbose("[SemanticChunker] Processing chunk \(chunkIndex + 1)", category: .ingestion)

            // Safety check: if we're too close to the end, create final chunk and stop
            let remainingDistance = text.distance(from: currentPosition, to: text.endIndex)
            if remainingDistance < 10 {
                // Less than 10 characters remaining - create final micro-chunk if needed
                if remainingDistance > 0 {
                    let finalText = String(text[currentPosition..<text.endIndex])
                    let wordCount = tokenWordCount(finalText)
                    if wordCount > 0 {
                        Log.verbose("[SemanticChunker] Final chunk \(chunkIndex + 1): \(wordCount) words", category: .ingestion)
                        let metadata = extractMetadata(
                            chunkText: finalText,
                            chunkIndex: chunkIndex,
                            documentId: documentId,
                            range: currentPosition..<text.endIndex,
                            in: text,
                            sections: sections,
                            pageNumbers: pageNumbers
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
                break
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
                break
            }

            // HARD LIMIT ENFORCEMENT: Truncate chunk to maxSize words
            // This prevents token truncation during embedding (510 token limit)
            var chunkText = String(text[chunkRange])
            var wordCount = tokenWordCount(chunkText)

            if wordCount > config.maxSize {
                Log.warning("[SemanticChunker] HARD LIMIT: Chunk \(chunkIndex + 1) has \(wordCount) words, truncating to \(config.maxSize)", category: .ingestion)

                // Use cached NLTokenizer to properly count words (handles tabs, special chars)
                // This matches how tokenWordCount() works
                cachedWordTokenizer.string = chunkText

                var wordRanges: [Range<String.Index>] = []
                cachedWordTokenizer.enumerateTokens(in: chunkText.startIndex..<chunkText.endIndex) { range, _ in
                    wordRanges.append(range)
                    return wordRanges.count < config.maxSize  // Stop after maxSize words
                }

                if let lastRange = wordRanges.last {
                    // Truncate to end of last word within limit
                    chunkText = String(chunkText[chunkText.startIndex..<lastRange.upperBound])

                    // Recalculate the range to match truncated text
                    let newEnd = text.index(currentPosition, offsetBy: chunkText.count, limitedBy: text.endIndex) ?? text.endIndex
                    chunkRange = currentPosition..<newEnd
                }

                wordCount = tokenWordCount(chunkText)
                Log.info("[SemanticChunker] Chunk \(chunkIndex + 1) ACTUALLY truncated to \(wordCount) words", category: .ingestion)
            }
            Log.verbose("[SemanticChunker] Chunk \(chunkIndex + 1): \(tokenWordCount(chunkText)) words", category: .ingestion)

            // Extract metadata
            let metadata = extractMetadata(
                chunkText: chunkText,
                chunkIndex: chunkIndex,
                documentId: documentId,
                range: chunkRange,
                in: text,
                sections: sections,
                pageNumbers: pageNumbers
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
            } else {
                currentPosition = nextPosition
            }

            chunkIndex += 1
        }

        Log.debug("[SemanticChunker] Created \(chunks.count) semantically-aware chunks", category: .ingestion)
        printChunkStatistics(chunks)

        // Update diagnostics for UI/telemetry
        let avgWordsPerChunk = chunks.isEmpty
            ? 0.0
            : Double(chunks.map { $0.metadata.wordCount }.reduce(0, +)) / Double(chunks.count)

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
        NotificationCenter.default.post(name: .semanticChunkerDiagnosticsUpdated, object: self.lastDiagnostics)

        return chunks
    }

    // MARK: - Async Chunking with Embedding Boundaries (Late Chunking)

    /// Chunk text with semantic boundaries detected via sentence embeddings.
    ///
    /// This is the preferred method when an EmbeddingService is available.
    /// It combines three levels of semantic boundary detection:
    /// 1. Section headers (markdown, numbered, ALL CAPS)
    /// 2. Linguistic transition phrases (However, Moreover, etc.)
    /// 3. **Embedding similarity drops** (Late Chunking - research-paper level)
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
        pageNumbers: [Int: Range<String.Index>]? = nil
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
            pageNumbers: pageNumbers
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
        NotificationCenter.default.post(name: .semanticChunkerDiagnosticsUpdated, object: self.lastDiagnostics)

        return chunks
    }

    /// Internal chunking method that accepts pre-computed topic boundaries
    private func chunkTextWithBoundaries(
        _ text: String,
        documentId: UUID,
        config: ChunkingConfig,
        topicBoundaries: [String.Index],
        pageNumbers: [Int: Range<String.Index>]?
    ) -> [EnhancedChunk] {
        let wordCount = tokenWordCount(text)
        if wordCount < config.minSize {
            return [createSingleChunk(text, documentId: documentId, pageNumbers: pageNumbers)]
        }

        let sections = detectSections(text)
        let tableBlocks = detectTableBlocks(text)

        var chunks: [EnhancedChunk] = []
        var currentPosition = text.startIndex
        var chunkIndex = 0
        let maxChunks = 50000  // Support very large documents

        while currentPosition < text.endIndex, chunkIndex < maxChunks {
            let remainingDistance = text.distance(from: currentPosition, to: text.endIndex)
            if remainingDistance < 10 {
                if remainingDistance > 0 {
                    let finalText = String(text[currentPosition ..< text.endIndex])
                    let wc = tokenWordCount(finalText)
                    if wc > 0 {
                        let metadata = extractMetadata(
                            chunkText: finalText,
                            chunkIndex: chunkIndex,
                            documentId: documentId,
                            range: currentPosition ..< text.endIndex,
                            in: text,
                            sections: sections,
                            pageNumbers: pageNumbers
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
                break
            }

            let chunkRange = findOptimalChunkRange(
                in: text,
                from: currentPosition,
                config: config,
                topicBoundaries: topicBoundaries,
                sections: sections,
                tableBlocks: tableBlocks
            )

            guard chunkRange.lowerBound < chunkRange.upperBound else { break }

            let chunkText = String(text[chunkRange])
            let metadata = extractMetadata(
                chunkText: chunkText,
                chunkIndex: chunkIndex,
                documentId: documentId,
                range: chunkRange,
                in: text,
                sections: sections,
                pageNumbers: pageNumbers
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
            } else {
                currentPosition = nextPosition
            }
            chunkIndex += 1
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

    // MARK: - Table Block Detection (Atomic Preservation)

    /// A contiguous block of table data that should not be split during chunking.
    /// Tables (spec sheets, data grids, markdown tables) lose meaning when split
    /// across chunk boundaries. Detected as a pre-pass and treated as atomic units.
    struct TableBlock {
        let range: Range<String.Index>
        let lineCount: Int
    }

    /// Detect contiguous table blocks in text.
    ///
    /// Scans line-by-line for table patterns:
    /// - **Markdown tables**: Lines with 2+ `|` characters (including separator rows like `|---|---|`)
    /// - **Tab-separated data**: Lines with 2+ tab characters and non-whitespace content
    ///
    /// Requires at least 2 consecutive matching lines to form a table block.
    /// Single matching lines are ignored (likely coincidental pipe usage).
    private func detectTableBlocks(_ text: String) -> [TableBlock] {
        var blocks: [TableBlock] = []
        var tableStartLine: String.Index?
        var lastTableLineEnd: String.Index?
        var consecutiveTableLines = 0

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            // Find line end
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])

            if isTableLine(line) {
                if tableStartLine == nil {
                    tableStartLine = lineStart
                }
                // Include the newline in the range so the table block covers full lines
                lastTableLineEnd = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                consecutiveTableLines += 1
            } else {
                // End of potential table block
                if consecutiveTableLines >= 2, let start = tableStartLine, let end = lastTableLineEnd {
                    blocks.append(TableBlock(range: start..<end, lineCount: consecutiveTableLines))
                }
                tableStartLine = nil
                lastTableLineEnd = nil
                consecutiveTableLines = 0
            }

            // Move to next line
            if lineEnd < text.endIndex {
                lineStart = text.index(after: lineEnd)
            } else {
                break
            }
        }

        // Handle table at end of text
        if consecutiveTableLines >= 2, let start = tableStartLine, let end = lastTableLineEnd {
            blocks.append(TableBlock(range: start..<end, lineCount: consecutiveTableLines))
        }

        if !blocks.isEmpty {
            Log.debug("[SemanticChunker] Detected \(blocks.count) table blocks (\(blocks.map { $0.lineCount }.reduce(0, +)) total lines)", category: .ingestion)
        }
        return blocks
    }

    /// Check if a line matches table patterns (markdown pipes or tab-separated columns).
    private func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Markdown table: line has 2+ pipe characters
        let pipeCount = trimmed.filter { $0 == "|" }.count
        if pipeCount >= 2 { return true }

        // Markdown separator row: |---|---| or +---+---+
        if (trimmed.hasPrefix("|") || trimmed.hasPrefix("+")) &&
            trimmed.contains("-") && pipeCount >= 1 {
            return true
        }

        // Tab-separated data: 2+ tabs with actual content between them
        let tabCount = trimmed.filter { $0 == "\t" }.count
        if tabCount >= 2 {
            // Verify there's actual content (not just whitespace with tabs)
            let segments = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            let nonEmptySegments = segments.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if nonEmptySegments.count >= 2 { return true }
        }

        return false
    }

    /// Check if a position falls within any detected table block.
    /// Returns the containing table block, or nil if the position is not inside a table.
    private func tableBlockContaining(_ index: String.Index, in tableBlocks: [TableBlock]) -> TableBlock? {
        return tableBlocks.first { $0.range.contains(index) }
    }

    /// Detect section headers and boundaries with hierarchical levels
    private func detectSections(_ text: String) -> [DetectedSection] {
        var sections: [DetectedSection] = []

        // Patterns with associated hierarchy levels
        // Level 1: Major sections (ALL CAPS, #, single digit like "1.")
        // Level 2: Subsections (##, "1.1", "1.1.")
        // Level 3: Sub-subsections (###, "1.1.1")
        let leveledPatterns: [(pattern: String, level: Int)] = [
            // Markdown headers - level determined by # count
            (#"^#{3}\s+(.+)$"#, 3),      // ### Sub-subsection
            (#"^#{2}\s+(.+)$"#, 2),      // ## Subsection
            (#"^#{1}\s+(.+)$"#, 1),      // # Section
            // Numbered sections - level determined by dot count
            (#"^\d+\.\d+\.\d+\.?\s+(.+)$"#, 3),  // 1.1.1 Sub-subsection
            (#"^\d+\.\d+\.?\s+(.+)$"#, 2),       // 1.1 Subsection
            (#"^\d+\.?\s+([A-Z].+)$"#, 1),       // 1. Section or 1 Section
            // Roman numerals (typically top-level)
            (#"^[IVX]+\.\s+(.+)$"#, 1),
            // ALL CAPS (typically top-level)
            (#"^([A-Z][A-Z\s]{3,}):?\s*$"#, 1),
        ]

        let lines = text.components(separatedBy: .newlines)
        var currentIndex = text.startIndex

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                // Still advance past empty lines
                if let lineRange = text.range(of: line + "\n", range: currentIndex..<text.endIndex) {
                    currentIndex = lineRange.upperBound
                }
                continue
            }

            for (pattern, level) in leveledPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
                   let _ = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    if let lineRange = text.range(of: line, range: currentIndex..<text.endIndex) {
                        // Clean up the title (remove # markers, normalize spacing)
                        var cleanTitle = trimmed
                        if cleanTitle.hasPrefix("#") {
                            cleanTitle = cleanTitle.drop(while: { $0 == "#" || $0 == " " }).description
                        }
                        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

                        sections.append(DetectedSection(
                            title: cleanTitle,
                            range: lineRange,
                            level: level
                        ))
                        break
                    }
                }
            }

            // Advance index
            if let lineRange = text.range(of: line + "\n", range: currentIndex..<text.endIndex) {
                currentIndex = lineRange.upperBound
            }
        }

        return sections
    }

    /// Build hierarchical section path for a given position in text
    /// Returns path like ["Chapter 5", "5.3 Fluids", "Engine Oil"] based on preceding headers
    private func buildSectionPath(
        at position: String.Index,
        sections: [DetectedSection]
    ) -> [String] {
        // Find all sections that precede this position
        let precedingSections = sections.filter { $0.range.lowerBound < position }
        guard !precedingSections.isEmpty else { return [] }

        // Build path by keeping track of current hierarchy
        // When we encounter a section, it replaces everything at its level and below
        var pathStack: [(level: Int, title: String)] = []

        for section in precedingSections {
            // Remove any sections at the same level or deeper
            pathStack.removeAll { $0.level >= section.level }
            // Add this section
            pathStack.append((section.level, section.title))
        }

        // Return just the titles in order
        return pathStack.map { $0.title }
    }

    /// Legacy wrapper for compatibility - returns flat section list
    private func detectSectionsFlat(_ text: String) -> [(title: String, range: Range<String.Index>)] {
        return detectSections(text).map { (title: $0.title, range: $0.range) }
    }

    /// Detect topic boundaries using linguistic cues
    private func detectTopicBoundaries(_ text: String) -> [String.Index] {
        var boundaries: [String.Index] = []

        // Transition words that indicate topic changes
        let transitionPhrases = [
            "However,", "Moreover,", "Furthermore,", "In contrast,", "On the other hand,",
            "Additionally,", "Nevertheless,", "Consequently,", "In conclusion,", "To summarize,"
        ]

        for phrase in transitionPhrases {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: phrase, range: searchRange) {
                boundaries.append(range.lowerBound)
                searchRange = range.upperBound..<text.endIndex
            }
        }

        return boundaries.sorted()
    }

    // MARK: - Embedding-Based Semantic Boundary Detection (Late Chunking)

    /// Detects topic boundaries using sentence embeddings and cosine similarity.
    ///
    /// Algorithm (based on Late Chunking research):
    /// 1. Split text into sentences using NLTokenizer
    /// 2. Generate embeddings for each sentence (batched for efficiency)
    /// 3. Compute cosine similarity between adjacent sentence pairs
    /// 4. Mark boundaries where similarity drops below threshold
    ///
    /// This approach identifies genuine topic shifts rather than relying on
    /// heuristic word counts or transition phrases.
    ///
    /// - Parameters:
    ///   - text: The full document text
    ///   - threshold: Cosine similarity threshold (default from instance property)
    ///
    /// - Returns: Array of text indices where topic boundaries occur
    func detectEmbeddingBoundaries(
        _ text: String,
        threshold: Float? = nil
    ) async -> [String.Index] {
        guard let embeddingService = embeddingService, embeddingService.isAvailable else {
            Log.debug("[SemanticChunker] Embedding service unavailable, skipping embedding boundaries", category: .ingestion)
            return []
        }

        let actualThreshold = threshold ?? embeddingSimilarityThreshold

        // 1. Split into sentences (reuse cached tokenizer)
        cachedSentenceTokenizer.string = text

        var sentences: [(text: String, range: Range<String.Index>)] = []
        cachedSentenceTokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentenceText = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentenceText.count > 10 { // Filter out very short fragments
                sentences.append((sentenceText, range))
            }
            return true
        }

        guard sentences.count >= 2 else {
            Log.debug("[SemanticChunker] Only \(sentences.count) sentences, skipping embedding boundaries", category: .ingestion)
            return []
        }

        // 2. Generate embeddings in batch (efficient for CoreML/NLEmbedding)
        let sentenceTexts = sentences.map { $0.text }
        let embeddings: [[Float]]
        do {
            embeddings = try await embeddingService.generateEmbeddings(for: sentenceTexts)
        } catch {
            Log.error("[SemanticChunker] Failed to generate sentence embeddings: \(error)", category: .ingestion)
            return []
        }

        guard embeddings.count == sentences.count else {
            Log.warning("[SemanticChunker] Embedding count mismatch", category: .ingestion)
            return []
        }

        // 3. Compute pairwise cosine similarity and detect drops
        var boundaries: [String.Index] = []

        for i in 1 ..< embeddings.count {
            let similarity = cosineSimilarityAccelerated(embeddings[i - 1], embeddings[i])

            if similarity < actualThreshold {
                // Topic shift detected - mark boundary at start of new sentence
                boundaries.append(sentences[i].range.lowerBound)
                Log.verbose("[SemanticChunker] Embedding boundary at sentence \(i): similarity=\(String(format: "%.3f", similarity))", category: .ingestion)
            }
        }

        Log.debug("[SemanticChunker] Detected \(boundaries.count) embedding-based topic boundaries from \(sentences.count) sentences", category: .ingestion)
        return boundaries
    }

    /// Accelerate-powered cosine similarity for sentence embeddings
    /// Uses vDSP dot product and modern vDSP.sumOfSquares for L2 norm
    private func cosineSimilarityAccelerated(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        // Dot product via vDSP (Neural Engine optimized)
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))

        // Modern Accelerate API: vDSP.sumOfSquares + sqrt (replaces deprecated cblas_snrm2)
        let normA = sqrt(vDSP.sumOfSquares(a))
        let normB = sqrt(vDSP.sumOfSquares(b))

        let denom = normA * normB
        return denom > 0 ? dot / denom : 0
    }

    /// Find optimal chunk range respecting semantic boundaries
    private func findOptimalChunkRange(
        in text: String,
        from start: String.Index,
        config: ChunkingConfig,
        topicBoundaries: [String.Index],
        sections: [DetectedSection],
        tableBlocks: [TableBlock] = []
    ) -> Range<String.Index> {
        // 1. Calculate permissible range based on word count
        // convert min/max/target words to approximate character offsets
        let minChars = config.minSize * 3 // very loose lower bound
        let maxChars = config.maxSize * 10 // loose upper bound

        let minIndex = text.index(start, offsetBy: minChars, limitedBy: text.endIndex) ?? text.endIndex
        let maxIndex = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex

        // 2. Check for strong semantic boundaries (Sections) within range
        // We prefer to break *before* a new section starts
        // Skip boundaries that fall inside a table block (splitting tables destroys meaning)
        for section in sections {
            let sectionStart = section.range.lowerBound
            if sectionStart > minIndex && sectionStart <= maxIndex {
                // Don't split inside a table
                if tableBlockContaining(sectionStart, in: tableBlocks) != nil { continue }

                let chunkText = text[start..<sectionStart]
                let count = tokenWordCount(String(chunkText))

                if count >= config.minSize && count <= config.maxSize {
                    Log.verbose("[SemanticChunker] Snapping to section: \(section.title)", category: .ingestion)
                    return start..<sectionStart
                }
            }
        }

        // 2.5. Check for table block ends within range (natural break after table completion)
        for table in tableBlocks {
            let tableEnd = table.range.upperBound
            if tableEnd > minIndex && tableEnd <= maxIndex {
                let chunkText = text[start..<tableEnd]
                let count = tokenWordCount(String(chunkText))

                if count >= config.minSize && count <= config.maxSize {
                    Log.verbose("[SemanticChunker] Snapping to table end (\(table.lineCount) lines)", category: .ingestion)
                    return start..<tableEnd
                }
            }
        }

        // 3. Check for topic boundaries within range
        // Skip boundaries inside table blocks
        for boundary in topicBoundaries {
            if boundary > minIndex && boundary <= maxIndex {
                // Don't split inside a table
                if tableBlockContaining(boundary, in: tableBlocks) != nil { continue }

                let chunkText = text[start..<boundary]
                let count = tokenWordCount(String(chunkText))

                if count >= config.minSize && count <= config.maxSize {
                    Log.verbose("[SemanticChunker] Snapping to topic boundary", category: .ingestion)
                    return start..<boundary
                }
            }
        }

        // 4. Fallback to word count + sentence boundary logic
        let remainingText = text[start..<text.endIndex]
        let words = remainingText.split(separator: " ", omittingEmptySubsequences: true)

        // Ideal end position
        let targetEnd = min(config.targetSize, words.count)

        // Safety check: if no words remaining, return minimal range
        guard targetEnd > 0 else {
            // No words left - return a minimal range of 1 character if possible
            if start < text.endIndex {
                let oneCharAfter = text.index(after: start)
                return start..<oneCharAfter
            } else {
                // Already at end - return empty range to signal completion
                return start..<start
            }
        }

        // Simplified approach: use pre-split words array for better performance
        var targetIndex = text.endIndex

        if targetEnd <= words.count {
            // Take the first targetEnd words and find their total length
            let targetWords = words.prefix(targetEnd)
            let approximateLength = targetWords.reduce(0) { $0 + $1.count + 1 } - 1 // -1 for the last space

            // Calculate target position more safely
            let maxOffset = text.distance(from: start, to: text.endIndex)
            let safeOffset = min(approximateLength, maxOffset)

            if safeOffset > 0 {
                targetIndex = text.index(start, offsetBy: safeOffset, limitedBy: text.endIndex) ?? text.endIndex
            } else {
                targetIndex = start
            }
        }

        // Adjust to nearest sentence boundary
        if let sentenceEnd = findNearestSentenceEnd(in: text, near: targetIndex, within: 100) {
            targetIndex = sentenceEnd
        }

        // 5. Table block protection: if the proposed end falls within a table, adjust
        if let table = tableBlockContaining(targetIndex, in: tableBlocks) {
            // Option A: Extend to include the full table (if within word limit)
            let extendedText = String(text[start..<table.range.upperBound])
            let extendedWordCount = tokenWordCount(extendedText)

            if extendedWordCount <= config.maxSize {
                Log.info("[SemanticChunker] Table protection: extended chunk to include \(table.lineCount)-line table (\(extendedWordCount) words)", category: .ingestion)
                targetIndex = table.range.upperBound
            } else if table.range.lowerBound > start {
                // Option B: Snap back to before the table starts
                let truncatedText = String(text[start..<table.range.lowerBound])
                let truncatedWordCount = tokenWordCount(truncatedText)
                if truncatedWordCount >= config.minSize {
                    Log.info("[SemanticChunker] Table protection: snapped chunk end before \(table.lineCount)-line table", category: .ingestion)
                    targetIndex = table.range.lowerBound
                } else {
                    // Option C: Table starts too close to chunk start — include it as oversized
                    // The hard-limit enforcement after findOptimalChunkRange will truncate if needed
                    Log.info("[SemanticChunker] Table protection: including oversized \(table.lineCount)-line table (\(extendedWordCount) words)", category: .ingestion)
                    targetIndex = table.range.upperBound
                }
            } else {
                // Table starts at chunk start — include the whole table
                Log.info("[SemanticChunker] Table protection: table spans from chunk start (\(table.lineCount) lines)", category: .ingestion)
                targetIndex = table.range.upperBound
            }
        }

        return start..<targetIndex
    }

    /// Find nearest sentence boundary
    private func findNearestSentenceEnd(in text: String, near index: String.Index, within distance: Int) -> String.Index? {
        let searchStart = text.index(index, offsetBy: -distance, limitedBy: text.startIndex) ?? text.startIndex
        let searchEnd = text.index(index, offsetBy: distance, limitedBy: text.endIndex) ?? text.endIndex

        // Validate range before creating it
        guard searchStart < searchEnd else {
            // Invalid range - return nil or the index itself
            return nil
        }

        let searchRange = searchStart..<searchEnd

        // Look for sentence endings
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var nearestDistance = Int.max
        var nearestIndex: String.Index?

        for i in text[searchRange].indices {
            if sentenceEnders.contains(text[i].unicodeScalars.first!) {
                let dist = text.distance(from: index, to: i)
                if abs(dist) < nearestDistance {
                    nearestDistance = abs(dist)
                    nearestIndex = text.index(after: i)
                }
            }
        }

        return nearestIndex
    }

    /// Find nearest sentence start by scanning backwards for sentence endings.
    private func findNearestSentenceStart(in text: String, near index: String.Index, within distance: Int) -> String.Index? {
        let searchStart = text.index(index, offsetBy: -distance, limitedBy: text.startIndex) ?? text.startIndex
        let searchEnd = text.index(index, offsetBy: distance, limitedBy: text.endIndex) ?? text.endIndex

        guard searchStart < searchEnd else { return nil }

        let searchRange = searchStart ..< searchEnd
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var nearestDistance = Int.max
        var nearestIndex: String.Index?

        for i in text[searchRange].indices {
            if sentenceEnders.contains(text[i].unicodeScalars.first!) {
                let candidate = text.index(after: i)
                let dist = text.distance(from: candidate, to: index)
                if dist >= 0, dist < nearestDistance {
                    nearestDistance = dist
                    nearestIndex = candidate
                }
            }
        }

        return nearestIndex
    }

    /// Build a parent context window around a chunk range.
    private func buildParentContent(
        for range: Range<String.Index>,
        in text: String,
        windowChars: Int
    ) -> String? {
        guard windowChars > 0 else { return nil }

        let lower = text.index(range.lowerBound, offsetBy: -windowChars, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: windowChars, limitedBy: text.endIndex) ?? text.endIndex

        let start = findNearestSentenceStart(in: text, near: lower, within: 120) ?? lower
        let end = findNearestSentenceEnd(in: text, near: upper, within: 120) ?? upper

        guard start < end else { return String(text[range]) }
        let expanded = String(text[start ..< end])
        let precise = String(text[range])
        if expanded.count <= precise.count { return precise }
        return expanded
    }

    /// Extract rich metadata for chunk
    private func extractMetadata(
        chunkText: String,
        chunkIndex: Int,
        documentId: UUID,
        range: Range<String.Index>,
        in fullText: String,
        sections: [DetectedSection],
        pageNumbers: [Int: Range<String.Index>]?
    ) -> EnhancedChunk.ChunkMetadata {
        let wordCount = tokenWordCount(chunkText)
        let keywords = extractKeywords(chunkText, topN: 5)
        let startOffset = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
        let endOffset = fullText.distance(from: fullText.startIndex, to: range.upperBound)

        // Find section title (immediate parent section)
        let sectionTitle = sections.first { $0.range.lowerBound <= range.lowerBound }?.title

        // Build hierarchical section path
        let sectionPath = buildSectionPath(at: range.lowerBound, sections: sections)

        // Find page number
        let pageNumber = pageNumbers?.first { $0.value.contains(range.lowerBound) }?.key

        // Detect structure
        let hasNumeric = chunkText.rangeOfCharacter(from: .decimalDigits) != nil
        let hasList = chunkText.contains(where: { $0 == "•" || $0 == "-" || $0 == "*" })

        // Calculate semantic density (information richness)
        let uniqueWords = Set(chunkText.lowercased().split(separator: " "))
        let density = Float(uniqueWords.count) / Float(max(wordCount, 1))

        // Extract named entities via NLTagger (persons, organizations, places, technical nouns)
        let entities = extractEntities(chunkText)

        return EnhancedChunk.ChunkMetadata(
            documentId: documentId,
            chunkIndex: chunkIndex,
            totalChunks: 0,  // Will be updated
            pageNumber: pageNumber,
            sectionTitle: sectionTitle,
            sectionPath: sectionPath,
            wordCount: wordCount,
            characterCount: chunkText.count,
            topKeywords: keywords,
            semanticDensity: density,
            hasNumericData: hasNumeric,
            hasListStructure: hasList,
            startOffset: startOffset,
            endOffset: endOffset,
            entities: entities
        )
    }

    // MARK: - Entity Extraction (Connective Tissue for GraphRAG)

    /// Extract named entities from chunk text using NLTagger.
    ///
    /// Uses multiple passes:
    /// 1. **Named Entity Recognition**: PersonalName, PlaceName, OrganizationName
    /// 2. **Technical Terms**: PascalCase identifiers (class names, APIs, frameworks)
    /// 3. **Capitalized Nouns**: Important domain terms that aren't standard NER entities
    ///
    /// These entities are used by:
    /// - `EntityIndexService` for cross-document correlation (Dict<Entity, [ChunkID]>)
    /// - `AgenticOrchestrator.executeGraphExpansion()` for 2-hop retrieval
    ///
    /// - Parameter text: The chunk text to extract entities from
    /// - Returns: Array of unique entity strings (deduplicated, sorted by first occurrence)
    private func extractEntities(_ text: String) -> [String] {
        var entities: [String] = []
        var seen = Set<String>()

        // Pass 1: NLTagger Named Entity Recognition (reuse cached instance)
        cachedNERTagger.string = text

        cachedNERTagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            guard let tag = tag else { return true }

            // Accept persons, organizations, and places
            switch tag {
            case .personalName, .organizationName, .placeName:
                let entity = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = entity.lowercased()
                if entity.count >= 2, entity.count <= 50, !seen.contains(key) {
                    seen.insert(key)
                    entities.append(entity)
                }
            default:
                break
            }
            return true
        }

        // Pass 2: Technical Terms - PascalCase identifiers (class names, APIs, frameworks)
        // Pattern: Word starting with capital followed by lowercase, then another capital
        // Examples: "URLSession", "CoreData", "SwiftUI", "NLTagger"
        let technicalPattern = #"\b([A-Z][a-z]+(?:[A-Z][a-z0-9]*)+)\b"#
        if let regex = try? NSRegularExpression(pattern: technicalPattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            for match in matches.prefix(20) { // Limit to avoid runaway in code-heavy docs
                if let range = Range(match.range, in: text) {
                    let term = String(text[range])
                    let key = term.lowercased()
                    if term.count >= 3, term.count <= 40, !seen.contains(key) {
                        seen.insert(key)
                        entities.append(term)
                    }
                }
            }
        }

        // Pass 3: Capitalized Nouns (important domain terms not caught by NER)
        // Only add if they look like proper nouns (start with capital, not ALL CAPS)
        cachedLexicalTagger.string = text

        cachedLexicalTagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            guard tag == .noun else { return true }

            let word = String(text[range])
            // Check if it starts with capital but isn't all caps (proper noun heuristic)
            guard let first = word.first,
                  first.isUppercase,
                  word.count >= 3,
                  word.count <= 30,
                  word != word.uppercased() // Skip ALL CAPS
            else { return true }

            let key = word.lowercased()
            // Skip common English words that happen to start sentences
            let stopWords: Set<String> = ["the", "this", "that", "these", "those", "there", "then", "when", "where", "which", "what", "who", "how", "why"]
            if !seen.contains(key), !stopWords.contains(key) {
                seen.insert(key)
                entities.append(word)
            }
            return true
        }

        // Return up to 15 entities per chunk (balance between richness and noise)
        return Array(entities.prefix(15))
    }

    /// Extract top keywords using TF-IDF approximation
    /// Also extracts capitalized multi-word phrases (e.g., "Record Button", "Note Recording")
    /// ENHANCED: Also extracts specification values (SAE 0W-20, API SN, etc.) via SpecificationDetector
    private func extractKeywords(_ text: String, topN: Int) -> [String] {
        // Prefer lemma-based counting to normalize inflections (reuse cached instance)
        cachedKeywordTagger.string = text

        var counts: [String: Int] = [:]

        cachedKeywordTagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { lemmaTag, range in
            // Determine POS for filtering
            let pos = cachedKeywordTagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            guard pos == .noun || pos == .verb || pos == .adjective else {
                return true
            }

            let token = String(text[range]).lowercased()
            let lemma = lemmaTag?.rawValue.lowercased() ?? token
            if lemma.count > 2 {
                counts[lemma, default: 0] += 1
            }
            return true
        }

        // Also extract capitalized multi-word phrases (domain-specific terms)
        // e.g., "Record Button", "Note Recording Mode", "Recording Mode Switch"
        let phrasePattern = #"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b"#
        if let regex = try? NSRegularExpression(pattern: phrasePattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let phrase = String(text[range]).lowercased()
                    if phrase.count > 5, phrase.count < 40 {
                        counts[phrase, default: 0] += 2 // Boost multi-word phrases
                    }
                }
            }
        }

        // ENHANCED: Extract specification values (SAE 0W-20, API SN, etc.)
        // These are critical for technical document retrieval (automotive, engineering, medical)
        let specs = SpecificationDetector.detectSpecifications(in: text)
        for spec in specs {
            // Use uppercase for spec values (more recognizable)
            let specKey = spec.value.uppercased()
            counts[specKey, default: 0] += 3 // Boost specs even higher than phrases
        }

        // Return more keywords for richer corpus vocabulary (up to 2x requested)
        return counts.sorted { $0.value > $1.value }
.prefix(topN * 2)
            .map { $0.key }
    }

    /// Advance position with intelligent overlap
    private func advancePosition(
        from start: String.Index,
        chunkEnd: String.Index,
        overlap: Int,
        in text: String
    ) -> String.Index {
        // Move back by overlap words from chunk end
        let overlapRange = text[start..<chunkEnd]
        let words = overlapRange.split(separator: " ")

        if words.count > overlap {
            let overlapWords = words.suffix(overlap)
            let overlapText = overlapWords.joined(separator: " ")
            if let overlapStart = text.range(of: overlapText, range: start..<chunkEnd) {
                return overlapStart.lowerBound
            }
        }

        return chunkEnd
    }

    /// Print chunk statistics
    private func printChunkStatistics(_ chunks: [EnhancedChunk]) {
        let avgWords = chunks.map { $0.metadata.wordCount }.reduce(0, +) / max(chunks.count, 1)
        let avgDensity = chunks.map { $0.metadata.semanticDensity }.reduce(0, +) / Float(max(chunks.count, 1))
        let withSections = chunks.filter { $0.metadata.sectionTitle != nil }.count
        let withNumeric = chunks.filter { $0.metadata.hasNumericData }.count

        Log.debug("[SemanticChunker] Avg words/chunk: \(avgWords)", category: .ingestion)
        Log.debug("[SemanticChunker] Avg semantic density: \(String(format: "%.2f", avgDensity))", category: .ingestion)
        Log.debug("[SemanticChunker] Chunks with sections: \(withSections)", category: .ingestion)
        Log.debug("[SemanticChunker] Chunks with numeric data: \(withNumeric)", category: .ingestion)
    }

    /// Create a single chunk for very small documents
    private func createSingleChunk(
        _ text: String,
        documentId: UUID,
        pageNumbers: [Int: Range<String.Index>]? = nil
    ) -> EnhancedChunk {
        let wordCount = tokenWordCount(text)

        // Extract basic metadata
        let keywords = extractKeywords(text, topN: 5)
        let hasNumeric = text.range(of: #"\d+"#, options: .regularExpression) != nil
        let hasList = text.contains("•") || text.range(of: #"^\d+\."#, options: .regularExpression) != nil
        let entities = extractEntities(text)

        let metadata = EnhancedChunk.ChunkMetadata(
            documentId: documentId,
            chunkIndex: 0,
            totalChunks: 1,
            pageNumber: nil,
            sectionTitle: nil,
            sectionPath: [],  // No section hierarchy for single-chunk docs
            wordCount: wordCount,
            characterCount: text.count,
            topKeywords: keywords,
            semanticDensity: 0.5, // Default for single chunk
            hasNumericData: hasNumeric,
            hasListStructure: hasList,
            startOffset: 0,
            endOffset: text.count,
            entities: entities
        )

        return EnhancedChunk(
            content: text,
            parentContent: text,
            metadata: metadata,
            embedding: nil // Will be added later by RAGService
        )
    }
}

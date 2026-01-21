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

    // MARK: - Token/Language helpers

    private func tokenWordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func estimateSentenceCount(for text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func averageSentenceLength(for text: String) -> Double {
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text
        var totalWords = 0
        var sentenceCount = 0

        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
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
        var targetSize: Int = 350 // Larger chunks for better coherence and context efficiency
        var minSize: Int = 120 // Prevent tiny, useless fragments
        var maxSize: Int = 550 // Allow expansion for complete thoughts
        var overlap: Int = 60 // ~17% overlap - enough for continuity without redundancy
        var useTopicDetection: Bool = true
        var preserveStructure: Bool = true
        /// Parent window size in characters for hierarchical context
        /// This expands the chunk by ±N chars (snapped to sentence boundaries)
        /// Reduced from 500→250 to fit more chunks in Apple FM's 4K context window
        var parentWindowChars: Int = 250

        // MARK: - Content-Adaptive Presets

        /// For technical manuals, specs, reference docs - balanced for lookup AND context
        /// Increased from 150→280w to pack more info per chunk while staying retrievable
        static let technicalReference = ChunkingConfig(
            targetSize: 280,
            minSize: 100,
            maxSize: 450,
            overlap: 50, // ~18% overlap
            useTopicDetection: true,
            preserveStructure: true
        )

        /// For narrative content (books, articles, reports - longer chunks for coherence)
        static let narrative = ChunkingConfig(
            targetSize: 400,
            minSize: 150,
            maxSize: 600,
            overlap: 70, // ~17% overlap
            useTopicDetection: true,
            preserveStructure: true
        )

        /// For code files (preserve function/class boundaries)
        static let code = ChunkingConfig(
            targetSize: 250,
            minSize: 60,
            maxSize: 500,
            overlap: 40, // ~16% overlap - less redundancy for code
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

        // 3. Chunk with semantic awareness
        var chunks: [EnhancedChunk] = []
        var currentPosition = text.startIndex
        var chunkIndex = 0
        let maxChunks = 5000 // Safety limit to prevent runaway loops on malformed input

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
            let chunkRange = findOptimalChunkRange(
                in: text,
                from: currentPosition,
                config: config,
                topicBoundaries: topicBoundaries,
                sections: sections
            )

            // Safety check: ensure range is valid and not empty
            guard chunkRange.lowerBound < chunkRange.upperBound else {
                Log.warning("[SemanticChunker] Empty range detected; stopping chunking", category: .ingestion)
                break
            }

            let chunkText = String(text[chunkRange])
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

        var chunks: [EnhancedChunk] = []
        var currentPosition = text.startIndex
        var chunkIndex = 0
        let maxChunks = 5000

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
                sections: sections
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

    /// Detect section headers and boundaries
    private func detectSections(_ text: String) -> [(title: String, range: Range<String.Index>)] {
        var sections: [(String, Range<String.Index>)] = []

        // Common section patterns
        let patterns = [
            #"^[A-Z][A-Z\s]+:?\s*$"#,  // ALL CAPS HEADERS
            #"^\d+\.\s+[A-Z].*$"#,      // 1. Numbered sections
            #"^[IVX]+\.\s+[A-Z].*$"#,   // I. Roman numerals
            #"^#{1,3}\s+.*$"#           // ## Markdown headers
        ]

        let lines = text.components(separatedBy: .newlines)
        var currentIndex = text.startIndex

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            for pattern in patterns {
                if let _ = trimmed.range(of: pattern, options: .regularExpression) {
                    if let lineRange = text.range(of: line, range: currentIndex..<text.endIndex) {
                        sections.append((trimmed, lineRange))
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

        // 1. Split into sentences
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text

        var sentences: [(text: String, range: Range<String.Index>)] = []
        sentenceTokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
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
        sections: [(title: String, range: Range<String.Index>)]
    ) -> Range<String.Index> {
        // 1. Calculate permissible range based on word count
        // convert min/max/target words to approximate character offsets
        let minChars = config.minSize * 3 // very loose lower bound
        let maxChars = config.maxSize * 10 // loose upper bound

        let minIndex = text.index(start, offsetBy: minChars, limitedBy: text.endIndex) ?? text.endIndex
        let maxIndex = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex

        // 2. Check for strong semantic boundaries (Sections) within range
        // We prefer to break *before* a new section starts
        for section in sections {
            let sectionStart = section.range.lowerBound
            if sectionStart > minIndex && sectionStart <= maxIndex {
                // Found a section start within permissible range.
                // Verify word count is reasonable (closer to target is better, but structure wins)
                let chunkText = text[start..<sectionStart]
                let count = tokenWordCount(String(chunkText))

                if count >= config.minSize && count <= config.maxSize {
                    Log.verbose("[SemanticChunker] Snapping to section: \(section.title)", category: .ingestion)
                    return start..<sectionStart
                }
            }
        }

        // 3. Check for topic boundaries within range
        for boundary in topicBoundaries {
            if boundary > minIndex && boundary <= maxIndex {
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
        sections: [(title: String, range: Range<String.Index>)],
        pageNumbers: [Int: Range<String.Index>]?
    ) -> EnhancedChunk.ChunkMetadata {
        let wordCount = tokenWordCount(chunkText)
        let keywords = extractKeywords(chunkText, topN: 5)
        let startOffset = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
        let endOffset = fullText.distance(from: fullText.startIndex, to: range.upperBound)

        // Find section title
        let sectionTitle = sections.first { $0.range.contains(range.lowerBound) }?.title

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

        // Pass 1: NLTagger Named Entity Recognition
        let nerTagger = NLTagger(tagSchemes: [.nameType])
        nerTagger.string = text

        nerTagger.enumerateTags(
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
        let nounTagger = NLTagger(tagSchemes: [.lexicalClass])
        nounTagger.string = text

        nounTagger.enumerateTags(
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
    private func extractKeywords(_ text: String, topN: Int) -> [String] {
        // Prefer lemma-based counting to normalize inflections
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass, .language])
        tagger.string = text

        var counts: [String: Int] = [:]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { lemmaTag, range in
            // Determine POS for filtering
            let pos = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
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

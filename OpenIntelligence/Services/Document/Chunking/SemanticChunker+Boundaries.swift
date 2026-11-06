//
//  SemanticChunker+Boundaries.swift
//  OpenIntelligence
//
//  Part of SemanticChunker, moved from SemanticChunker.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import Accelerate

nonisolated extension SemanticChunker {
    // MARK: - Embedding-Based Semantic Boundary Detection

    /// Detects topic boundaries using sentence embeddings and cosine similarity.
    ///
    /// Algorithm (semantic breakpoint detection, not late chunking; see file header):
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
        guard let embeddingService = embeddingService, await embeddingService.isAvailable else {
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
    func findOptimalChunkRange(
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
                    if logsEachChunk {
                        Log.verbose("[SemanticChunker] Snapping to table end (\(table.lineCount) lines)", category: .ingestion)
                    }
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
        // Only the first `targetSize` words are used below, so the split stops there and the rest
        // of the text comes back as one unsplit piece. Through 5.6 this split all of it, which
        // walked the rest of the document and built an array of every remaining word for every
        // chunk: 2.2 s a chunk on an 88 MB file on an iPhone 16 Pro Max (2026-10-09), and the
        // reason a large text import did not finish.
        let remainingText = text[start..<text.endIndex]
        let words = remainingText.split(
            separator: " ", maxSplits: max(0, config.targetSize), omittingEmptySubsequences: true)

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

            // Walk to the target and stop at the end of the text. The limit does what a measured
            // distance to the end did here, without the pass over the rest of the text.
            if approximateLength > 0 {
                targetIndex = text.index(start, offsetBy: approximateLength, limitedBy: text.endIndex) ?? text.endIndex
            } else {
                targetIndex = start
            }
        }

        // Adjust to nearest sentence boundary, or else to the nearest place no word is cut (5.7)
        if let sentenceEnd = findNearestSentenceEnd(in: text, near: targetIndex, within: 100) {
            targetIndex = sentenceEnd
        } else if targetIndex > start {
            let snapped = Self.snappedToWordBoundary(targetIndex, in: text, within: 100)
            if snapped > start { targetIndex = snapped }
            if logsEachChunk {
                Log.debug("[SemanticChunker] No sentence ends within 100 characters of the target; the passage ends at a word boundary", category: .ingestion)
            }
        }

        // 5. Table block protection: if the proposed end falls within a table, adjust
        if let table = tableBlockContaining(targetIndex, in: tableBlocks) {
            // Option A: Extend to include the full table (if within word limit)
            let extendedText = String(text[start..<table.range.upperBound])
            let extendedWordCount = tokenWordCount(extendedText)

            if extendedWordCount <= config.maxSize {
                if logsEachChunk { Log.info("[SemanticChunker] Table protection: extended chunk to include \(table.lineCount)-line table (\(extendedWordCount) words)", category: .ingestion) }
                targetIndex = table.range.upperBound
            } else if table.range.lowerBound > start {
                // Option B: Snap back to before the table starts
                let truncatedText = String(text[start..<table.range.lowerBound])
                let truncatedWordCount = tokenWordCount(truncatedText)
                if truncatedWordCount >= config.minSize {
                    if logsEachChunk { Log.info("[SemanticChunker] Table protection: snapped chunk end before \(table.lineCount)-line table", category: .ingestion) }
                    targetIndex = table.range.lowerBound
                } else {
                    // Option C: Table starts too close to chunk start — include it as oversized
                    // The hard-limit enforcement after findOptimalChunkRange will truncate if needed
                    if logsEachChunk { Log.info("[SemanticChunker] Table protection: including oversized \(table.lineCount)-line table (\(extendedWordCount) words)", category: .ingestion) }
                    targetIndex = table.range.upperBound
                }
            } else {
                // Table starts at chunk start — include the whole table
                if logsEachChunk { Log.info("[SemanticChunker] Table protection: table spans from chunk start (\(table.lineCount) lines)", category: .ingestion) }
                targetIndex = table.range.upperBound
            }
        }

        return start..<targetIndex
    }

    /// Find nearest sentence boundary using NLTokenizer for robust detection.
    /// NLTokenizer correctly handles abbreviations ("Dr.", "U.S.A."), decimal numbers ("3.14"),
    /// URLs, and other cases where period ≠ sentence end.
    private func findNearestSentenceEnd(in text: String, near index: String.Index, within distance: Int) -> String.Index? {
        let searchStart = text.index(index, offsetBy: -distance, limitedBy: text.startIndex) ?? text.startIndex
        let searchEnd = text.index(index, offsetBy: distance, limitedBy: text.endIndex) ?? text.endIndex

        // Validate range before creating it
        guard searchStart < searchEnd else {
            return nil
        }

        let searchRange = searchStart..<searchEnd
        let substring = String(text[searchRange])

        // Use NLTokenizer for robust sentence boundary detection
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = substring

        var nearestDistance = Int.max
        var nearestIndex: String.Index?

        sentenceTokenizer.enumerateTokens(in: substring.startIndex..<substring.endIndex) { tokenRange, _ in
            // The end of each sentence token is a sentence boundary
            let boundaryInSubstring = tokenRange.upperBound
            // Map back to the original text index
            let offset = substring.distance(from: substring.startIndex, to: boundaryInSubstring)
            guard let originalIndex = text.index(searchStart, offsetBy: offset, limitedBy: text.endIndex) else {
                return true
            }
            // The last token "ends" wherever the window does: the tokenizer can't see what comes after it, so that end
            // counts only where a sentence really ends (5.7), the mirror of the first token's start in
            // `findNearestSentenceStart`. Through 5.6 a window with no sentence end in it returned its own last
            // character, so a passage could end mid-word.
            if boundaryInSubstring == substring.endIndex, !Self.canEndSentence(at: originalIndex, in: text) {
                return true
            }

            let dist = abs(text.distance(from: index, to: originalIndex))
            if dist < nearestDistance {
                nearestDistance = dist
                nearestIndex = originalIndex
            }
            return true
        }

        return nearestIndex
    }

    /// Sentence ends that a space follows: Latin, Devanagari (danda, double danda), Urdu and Arabic.
    private static let spacedSentenceEnds: Set<Character> = [".", "!", "?", "\u{0964}", "\u{0965}", "\u{06D4}", "\u{061F}"]
    /// Sentence ends that need no space after them: Chinese and Japanese, full width and half width.
    private static let unspacedSentenceEnds: Set<Character> = ["\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{FF61}", "\u{FF0E}"]
    /// Closing quotes and brackets that can stand between a sentence's end and the next sentence.
    private static let closers: Set<Character> = [
        "\"", "'", "\u{201D}", "\u{2019}", ")", "]", "\u{00BB}", "\u{203A}", "\u{300D}", "\u{300F}", "\u{FF09}",
        "\u{300B}", "\u{3009}", "\u{3011}",
    ]

    /// Whether a sentence can end at `index`: the end of the text, at a line break, or after the end of a sentence with
    /// closing quotes or brackets and spaces allowed after it (5.7). After `.`, `!`, `?` and the other spaced ends a space
    /// or the text's end has to follow, so "3.14" and "example.com" don't end sentences; after `。` and the other CJK
    /// ends nothing has to.
    static func canEndSentence(at index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        if text[index].isNewline { return true }
        guard index > text.startIndex else { return false }
        var cursor = text.index(before: index)
        var spaced = text[index].isWhitespace
        while text[cursor].isWhitespace {
            if text[cursor].isNewline { return true }
            spaced = true
            guard cursor > text.startIndex else { return false }
            cursor = text.index(before: cursor)
        }
        while closers.contains(text[cursor]) {
            guard cursor > text.startIndex else { return false }
            cursor = text.index(before: cursor)
        }
        if unspacedSentenceEnds.contains(text[cursor]) { return true }
        return spaced && spacedSentenceEnds.contains(text[cursor])
    }

    /// `index`, or the nearest place within `distance` characters where no word is cut: a space or line break on
    /// either side, the earlier one when two are as near, and `index` itself when a token runs past both (5.7). The
    /// fallback for a chunk's end and its parent window's edges when no sentence ends near them.
    static func snappedToWordBoundary(_ index: String.Index, in text: String, within distance: Int) -> String.Index {
        func isBoundary(_ i: String.Index) -> Bool {
            i == text.startIndex || i == text.endIndex || text[i].isWhitespace || text[text.index(before: i)].isWhitespace
        }
        if isBoundary(index) { return index }
        var back = index
        var forward = index
        for _ in 0..<distance {
            if back > text.startIndex {
                back = text.index(before: back)
                if isBoundary(back) { return back }
            }
            if forward < text.endIndex {
                forward = text.index(after: forward)
                if isBoundary(forward) { return forward }
            }
        }
        return index
    }

    /// Whether a sentence can start at `index`: the start of the text, after a line break, or after the end of a
    /// sentence, with closing quotes or brackets allowed in between (5.7). After `.`, `!`, `?` and the other spaced ends
    /// there has to be a space as well, so "3.14" and "example.com" aren't sentence ends; after `。` and the other CJK
    /// ends there needn't be.
    static func canStartSentence(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        var cursor = text.index(before: index)
        var spaced = false
        while text[cursor].isWhitespace {
            if text[cursor].isNewline { return true }
            spaced = true
            guard cursor > text.startIndex else { return true }
            cursor = text.index(before: cursor)
        }
        while closers.contains(text[cursor]) {
            guard cursor > text.startIndex else { return false }
            cursor = text.index(before: cursor)
        }
        if unspacedSentenceEnds.contains(text[cursor]) { return true }
        return spaced && spacedSentenceEnds.contains(text[cursor])
    }

    /// Find nearest sentence start using NLTokenizer for robust detection.
    /// Handles abbreviations, decimals, URLs correctly.
    func findNearestSentenceStart(in text: String, near index: String.Index, within distance: Int) -> String.Index? {
        let searchStart = text.index(index, offsetBy: -distance, limitedBy: text.startIndex) ?? text.startIndex
        let searchEnd = text.index(index, offsetBy: distance, limitedBy: text.endIndex) ?? text.endIndex

        guard searchStart < searchEnd else { return nil }

        let substring = String(text[searchStart..<searchEnd])
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = substring

        var nearestDistance = Int.max
        var nearestIndex: String.Index?

        var isFirstToken = true
        sentenceTokenizer.enumerateTokens(in: substring.startIndex..<substring.endIndex) { tokenRange, _ in
            // The start of each sentence token is a sentence boundary
            let boundaryInSubstring = tokenRange.lowerBound
            // The first token "starts" wherever the window does, or after its leading spaces: the tokenizer can't see what
            // comes before the window, so that start counts only where a sentence really ends before it (5.7). The tokens
            // after it are the tokenizer's own boundaries, in any script, and count as before. Through 5.6 a window with
            // no sentence start in it returned its own first character, so a passage could start mid-word (reviews of
            // 2026-10-17).
            if isFirstToken {
                isFirstToken = false
                let candidate =
                    text.index(
                        searchStart, offsetBy: substring.distance(from: substring.startIndex, to: boundaryInSubstring),
                        limitedBy: text.endIndex) ?? text.endIndex
                if !Self.canStartSentence(at: candidate, in: text) {
                    return true
                }
            }
            let offset = substring.distance(from: substring.startIndex, to: boundaryInSubstring)
            guard let originalIndex = text.index(searchStart, offsetBy: offset, limitedBy: text.endIndex) else {
                return true
            }

            let dist = text.distance(from: originalIndex, to: index)
            if dist >= 0, dist < nearestDistance {
                nearestDistance = dist
                nearestIndex = originalIndex
            }
            return true
        }

        return nearestIndex
    }

    /// Build a parent context window around a chunk range.
    func buildParentContent(
        for range: Range<String.Index>,
        in text: String,
        windowChars: Int
    ) -> String? {
        guard windowChars > 0 else { return nil }

        let lower = text.index(range.lowerBound, offsetBy: -windowChars, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: windowChars, limitedBy: text.endIndex) ?? text.endIndex

        let start = findNearestSentenceStart(in: text, near: lower, within: 120)
            ?? Self.snappedToWordBoundary(lower, in: text, within: 120)
        let end = findNearestSentenceEnd(in: text, near: upper, within: 120)
            ?? Self.snappedToWordBoundary(upper, in: text, within: 120)

        guard start < end else { return String(text[range]) }
        let expanded = String(text[start ..< end])
        let precise = String(text[range])
        if expanded.count <= precise.count { return precise }
        return expanded
    }

    /// Extract rich metadata for chunk
    func extractMetadata(
        chunkText: String,
        chunkIndex: Int,
        documentId: UUID,
        range: Range<String.Index>,
        startOffset: Int,
        in fullText: String,
        sections: [DetectedSection],
        pageNumbers: [Int: Range<String.Index>]?,
        documentCategory: DocumentSemanticCategory?
    ) -> EnhancedChunk.ChunkMetadata {
        let wordCount = tokenWordCount(chunkText)
        let keywords = extractKeywords(chunkText, topN: 5)
        // `startOffset` is the character offset of `range.lowerBound`, which the caller keeps as
        // it walks forward. Only the chunk itself is measured here.
        let endOffset = startOffset + fullText.distance(from: range.lowerBound, to: range.upperBound)

        // Find section title (immediate parent section)
        // CRITICAL: Must use .last to get the NEAREST preceding section, not the first one in the document
        let sectionTitle = sections.last { $0.range.lowerBound <= range.lowerBound }?.title

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

        // Extract abbreviation→expansion mappings from inline definitions
        let abbreviations = extractAbbreviations(chunkText)

        let resolvedReferences = GraphIndexService.extractReferenceTargets(from: chunkText)
        let inferredChunkType: ChunkSemanticType = isWarningLike(text: chunkText, sectionTitle: sectionTitle) ? .warning : .prose

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
            entities: entities,
            abbreviations: abbreviations,
            documentCategory: documentCategory,
            chunkType: inferredChunkType,
            tableTitle: nil,
            hasCrossReferences: !resolvedReferences.isEmpty,
            resolvedReferences: resolvedReferences
        )
    }

    func isWarningLike(text: String, sectionTitle: String?) -> Bool {
        let combined = [sectionTitle, text.prefix(240).description]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let warningTerms = ["warning", "caution", "danger", "important", "notice", "precaution"]
        return warningTerms.contains(where: { combined.contains($0) })
    }

}

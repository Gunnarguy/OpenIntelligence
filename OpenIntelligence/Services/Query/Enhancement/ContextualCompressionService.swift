//
//  ContextualCompressionService.swift
//  OpenIntelligence
//
//  Contextual Compression - Extract only query-relevant content from chunks
//
//  Problem: Retrieved chunks contain relevant AND irrelevant sentences.
//           Sending all content wastes tokens and dilutes signal.
//
//  Solution: Use LLM to extract only sentences that help answer the query.
//            Can achieve 40-60% token reduction while improving answer quality.
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Compresses retrieved chunks to only query-relevant content
final class ContextualCompressionService: @unchecked Sendable {
    /// Compression configuration
    struct Config: Sendable {
        /// Target compression ratio (0.3 = keep 30% of content)
        let targetCompressionRatio: Double

        /// Minimum sentences to keep per chunk
        let minSentences: Int

        /// Maximum input tokens before chunked processing
        let maxInputTokens: Int

        /// Whether to include contextually related content (not just directly answering)
        let includeRelatedContext: Bool

        nonisolated static var `default`: Config {
            Config(
                targetCompressionRatio: 0.6, // More conservative - keep 60%
                minSentences: 2,
                maxInputTokens: 1500,
                includeRelatedContext: true
            )
        }

        nonisolated static var conservative: Config {
            Config(
                targetCompressionRatio: 0.7, // Keep most context
                minSentences: 3,
                maxInputTokens: 2000,
                includeRelatedContext: true
            )
        }

        /// For "exactly" or detail-oriented queries - keep almost everything relevant
        nonisolated static var verbose: Config {
            Config(
                targetCompressionRatio: 0.85, // Keep 85% - minimal compression
                minSentences: 4,
                maxInputTokens: 2500,
                includeRelatedContext: true
            )
        }

        /// Aggressive compression for simple factual lookups
        nonisolated static var aggressive: Config {
            Config(
                targetCompressionRatio: 0.4,
                minSentences: 1,
                maxInputTokens: 1500,
                includeRelatedContext: false
            )
        }
    }

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private var session: LanguageModelSession?
    #endif

    init() {}

    /// Compress a single chunk to query-relevant content
    /// - Parameters:
    ///   - chunk: The retrieved chunk text
    ///   - query: The user's query
    ///   - sectionTitle: Optional section/topic title for the chunk (helps compression
    ///     understand what the data represents, preventing over-compression when the
    ///     query uses abbreviations like "HRV" but the chunk body has only raw stats)
    ///   - config: Compression settings
    /// - Returns: Compressed content containing only relevant sentences
    func compressChunk(
        _ chunk: String,
        forQuery query: String,
        sectionTitle: String? = nil,
        config: Config = .default
    ) async throws -> CompressionResult {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                return CompressionResult.passthrough(chunk, forQuery: query)
            }

            // Skip compression for short chunks
            let wordCount = chunk.split(separator: " ").count
            if wordCount < 50 {
                return CompressionResult.passthrough(chunk, forQuery: query)
            }

            let startTime = Date()

            // Create session if needed
            if session == nil {
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    return CompressionResult.passthrough(chunk, forQuery: query)
                }
                session = LanguageModelSession(model: model)
            }

            guard let session = session else {
                return CompressionResult.passthrough(chunk, forQuery: query)
            }

            let prompt = buildCompressionPrompt(chunk: chunk, query: query, sectionTitle: sectionTitle, config: config)

            let response = try await session.respond(to: prompt)
            var compressed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // GUARD: Strip query echo from compression output.
            // Apple FM often echoes the query ("What's smart mode?") as a prefix.
            // This fools downstream keyword scoring into thinking irrelevant chunks
            // are highly relevant (they contain the query keywords, not document keywords).
            compressed = stripQueryEcho(compressed, query: query)

            let elapsed = Date().timeIntervalSince(startTime)
            let originalTokens = estimateTokens(chunk)
            let compressedTokens = estimateTokens(compressed)
            let ratio = Double(compressedTokens) / Double(originalTokens)

            // GUARD: If compression EXPANDED the text (ratio > 1.0), the LLM hallucinated
            // new content instead of extracting. Discard and use original.
            if ratio > 1.0 {
                Log.info("[Compression] REJECTED expansion \(originalTokens)→\(compressedTokens) tokens (\(String(format: "%.0f", ratio * 100))%) — using original", category: .retrieval)
                return CompressionResult.passthrough(chunk, forQuery: query)
            }

            Log.info("[Compression] \(originalTokens)→\(compressedTokens) tokens (\(String(format: "%.0f", ratio * 100))%) in \(String(format: "%.0f", elapsed * 1000))ms", category: .retrieval)

            return CompressionResult(
                query: query,
                originalContent: chunk,
                compressedContent: compressed,
                originalTokens: originalTokens,
                compressedTokens: compressedTokens,
                compressionRatio: ratio
            )

        #else
            return CompressionResult.passthrough(chunk, forQuery: query)
        #endif
    }

    /// Compress multiple chunks sequentially with per-chunk error isolation and time budget.
    /// - Parameters:
    ///   - chunks: The chunk texts to compress
    ///   - query: The user's query
    ///   - sectionTitles: Optional section titles for each chunk (parallel array)
    ///   - config: Compression settings
    ///   - totalTimeBudget: Maximum total seconds for all compressions (default 12s)
    func compressChunks(
        _ chunks: [String],
        forQuery query: String,
        sectionTitles: [String?]? = nil,
        config: Config = .default,
        totalTimeBudget: TimeInterval = 12.0
    ) async throws -> [CompressionResult] {
        var results: [CompressionResult] = []
        let batchStart = Date()

        for (index, chunk) in chunks.enumerated() {
            // Time budget check: bail out early if we've spent too long
            let elapsed = Date().timeIntervalSince(batchStart)
            if elapsed >= totalTimeBudget {
                Log.warning("[Compression] Time budget exhausted (\(String(format: "%.1f", elapsed))s/\(String(format: "%.0f", totalTimeBudget))s) after \(index)/\(chunks.count) chunks — using originals for remainder", category: .retrieval)
                // Passthrough remaining chunks
                for remainIdx in index..<chunks.count {
                    results.append(CompressionResult.passthrough(chunks[remainIdx], forQuery: query))
                }
                break
            }

            // Fresh session per chunk to avoid transcript accumulation that overflows
            // the 4096-token context window after 3-4 compressions
            resetSession()

            let title = sectionTitles.flatMap { index < $0.count ? $0[index] : nil }

            // Per-chunk error isolation: one failure doesn't kill the batch
            do {
                let result = try await compressChunk(chunk, forQuery: query, sectionTitle: title, config: config)
                results.append(result)
            } catch {
                Log.warning("[Compression] Chunk \(index + 1)/\(chunks.count) failed: \(error.localizedDescription) — using original", category: .retrieval)
                results.append(CompressionResult.passthrough(chunk, forQuery: query))
            }
        }

        let totalOriginal = results.reduce(0) { $0 + $1.originalTokens }
        let totalCompressed = results.reduce(0) { $0 + $1.compressedTokens }
        let totalElapsed = Date().timeIntervalSince(batchStart)

        if totalOriginal > 0 {
            let overallRatio = Double(totalCompressed) / Double(totalOriginal)
            Log.info("[Compression] Total: \(totalOriginal)→\(totalCompressed) tokens (\(String(format: "%.0f", overallRatio * 100))% of original) in \(String(format: "%.1f", totalElapsed))s", category: .retrieval)
        }

        return results
    }

    private func buildCompressionPrompt(chunk: String, query: String, sectionTitle: String? = nil, config: Config) -> String {
        // Prepend section title so the LLM understands context even when
        // the chunk body is raw data (e.g. "2024: 1,821 records, avg 71.6 ms")
        // and the query uses an abbreviation (e.g. "HRV"). Without this,
        // compression drops to 1% (319→2 tokens) because it can't see the connection.
        let chunkWithContext: String
        if let title = sectionTitle, !title.isEmpty {
            chunkWithContext = "[Section: \(title)]\n\(chunk)"
        } else {
            chunkWithContext = chunk
        }

        if config.includeRelatedContext {
            // Verbose prompt: include related context for comprehensive answers
            return """
            Extract sentences from this text that help answer the question comprehensively.
            Include:
            - Sentences that directly answer the question
            - Related context that provides important background
            - Technical details, specifications, or procedures mentioned

            CRITICAL RULES:
            - Copy sentences EXACTLY from the text — do NOT paraphrase or create new text
            - Do NOT include the question in your output
            - Do NOT add introductions, labels, or commentary
            - If the text does not help answer the question, respond ONLY with "NO_RELEVANT_CONTENT"
            - The text must contain actual answers, not just words that appear in the question

            Question: \(query)

            Text:
            \(chunkWithContext)

            Relevant content:
            """
        } else {
            // Aggressive prompt: only directly answering sentences
            return """
            Extract ONLY the sentences that directly answer the question.
            Remove all unrelated content. Copy exact wording — do NOT paraphrase.
            Do NOT include the question in your output.
            If nothing is relevant, respond with "NO_RELEVANT_CONTENT".

            Question: \(query)

            Text to compress:
            \(chunkWithContext)

            Relevant sentences only:
            """
        }
    }

    private func estimateTokens(_ text: String) -> Int {
        // IMPROVED: Word-count-based estimation with sub-word factor
        // BertTokenizer/WordPiece splits words into sub-tokens. Research shows:
        // - Common English words: ~1.3 tokens/word
        // - Technical text (codes, URLs, paths): ~2.0+ tokens/word
        // - Mixed content: ~1.5 tokens/word average
        // Previous: count/4 ≈ 1 token per 4 chars (massively underestimates technical content)
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let wordCount = words.count
        guard wordCount > 0 else { return 1 }

        // Detect technical density: count words with non-alpha chars (codes, numbers, paths)
        let technicalWords = words.filter { word in
            word.contains(where: { !$0.isLetter && !$0.isWhitespace }) ||
            word.count > 12 // Long words often get sub-tokenized
        }.count
        let technicalRatio = Float(technicalWords) / Float(wordCount)

        // Scale factor: 1.3 for plain English, up to 2.0 for highly technical
        let subwordFactor: Float = 1.3 + (technicalRatio * 0.7)
        return max(1, Int(Float(wordCount) * subwordFactor))
    }

    /// Strip query text that the compression LLM echoed back as a prefix.
    /// Apple FM frequently echoes the question ("What's smart mode?") at the start of
    /// its response. This contaminates keyword scoring downstream.
    private func stripQueryEcho(_ text: String, query: String) -> String {
        var result = text
        let queryTrimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLower = queryTrimmed.lowercased()

        // Strip exact query at start (with optional punctuation/whitespace after)
        let resultLower = result.lowercased()
        if resultLower.hasPrefix(queryLower) {
            let afterQuery = result.index(result.startIndex, offsetBy: queryTrimmed.count)
            var trimPoint = afterQuery
            // Skip trailing punctuation and whitespace after the echoed query
            while trimPoint < result.endIndex {
                let ch = result[trimPoint]
                if ch == " " || ch == "\n" || ch == "-" || ch == ":" || ch == "?" || ch == "!" {
                    trimPoint = result.index(after: trimPoint)
                } else {
                    break
                }
            }
            result = String(result[trimPoint...])
        }

        // Also strip "Context and Related Concepts:" hallucination headers
        // Apple FM frequently generates these instead of extracting text
        let hallucHeaders = [
            "Context and Related Concepts:",
            "Technical Details:",
            "Related Information:"
        ]
        for header in hallucHeaders {
            if let range = result.range(of: header, options: .caseInsensitive) {
                // Remove the header and the line it's on
                let lineStart = result[..<range.lowerBound].lastIndex(of: "\n") ?? result.startIndex
                let lineEnd = result[range.upperBound...].firstIndex(of: "\n") ?? result.endIndex
                result.removeSubrange(lineStart..<lineEnd)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reset session to free memory
    func resetSession() {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                session = nil
            }
        #endif
    }
}

/// Result of contextual compression
struct CompressionResult: Sendable {
    let query: String
    let originalContent: String
    let compressedContent: String
    let originalTokens: Int
    let compressedTokens: Int
    let compressionRatio: Double

    /// Returns true if compression removed content
    nonisolated var wasCompressed: Bool {
        compressionRatio < 0.95
    }

    /// Returns the content to use
    /// If compression found nothing relevant, extracts high-value sentences (with numbers,
    /// entities, or technical terms) rather than blindly taking the first 400 chars.
    /// The chunk passed retrieval so it likely has SOME value — the needle might be in
    /// the middle or end, not the beginning.
    nonisolated var effectiveContent: String {
        if compressedContent.contains("NO_RELEVANT_CONTENT") || compressedContent.isEmpty {
            var extractedSentences = [String]()

            // UNIVERSAL FIX: Extract sentences likely to contain the needle.
            // We use simple substring matching as a fast pass before relying on LLM compression.
            let terms = query.lowercased().split(separator: " ").map { String($0) }

            // Previously took first 400 chars — a needle at char 450 was lost forever.
            // Now: score each sentence by information density (numbers, capitalized terms,
            // colons, units) and take the highest-scoring ones up to 400 chars.
            let sentences = originalContent.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 10 }

            if sentences.count <= 2 {
                // Very short content — return as-is
                return originalContent
            }

            // Score each sentence by information density
            let scored = sentences.map { sentence -> (String, Int) in
                var score = 0
                let lowerSentence = sentence.lowercased()

                // Query matching (highest weight)
                for term in terms {
                    if term.count > 3 && lowerSentence.contains(term) {
                        score += 5
                    }
                }

                // Numbers (specs, measurements, dates, values)
                if sentence.rangeOfCharacter(from: .decimalDigits) != nil { score += 3 }
                // Capitalized words (entities, proper nouns, acronyms)
                let capitalWords = sentence.split(separator: " ").filter { word in
                    guard let first = word.first else { return false }
                    return first.isUppercase && word.count > 1
                }
                score += min(capitalWords.count, 3)
                // Colons (definitions, key-value pairs: "Capacity: 5L")
                if sentence.contains(":") { score += 2 }
                // Technical patterns (units, codes)
                if sentence.range(of: #"[A-Z]{2,}[\s-]?\d+"#, options: .regularExpression) != nil { score += 2 }
                return (sentence, score)
            }
            .sorted { $0.1 > $1.1 }

            // Take top-scoring sentences up to 400 chars
            var fallback = ""
            for (sentence, _) in scored {
                if fallback.count + sentence.count + 2 > 400 { break }
                if !fallback.isEmpty { fallback += ". " }
                fallback += sentence
                extractedSentences.append(sentence)
            }

            if fallback.isEmpty {
                fallback = String(originalContent.prefix(400))
            }

            return fallback.count < originalContent.count ? fallback + "..." : fallback
        }
        return compressedContent
    }

    /// Returns true if compression marked this chunk as irrelevant
    nonisolated var wasMarkedIrrelevant: Bool {
        compressedContent.contains("NO_RELEVANT_CONTENT") || compressedContent.isEmpty
    }

    /// Passthrough result when compression is skipped
    nonisolated static func passthrough(_ content: String, forQuery query: String = "") -> CompressionResult {
        // Word-count-based estimation matching estimateTokens() logic
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let wordCount = words.count
        let technicalWords = words.filter { word in
            word.contains(where: { !$0.isLetter && !$0.isWhitespace }) || word.count > 12
        }.count
        let technicalRatio = wordCount > 0 ? Float(technicalWords) / Float(wordCount) : 0
        let subwordFactor: Float = 1.3 + (technicalRatio * 0.7)
        let tokens = max(1, Int(Float(wordCount) * subwordFactor))
        return CompressionResult(
            query: query,
            originalContent: content,
            compressedContent: content,
            originalTokens: tokens,
            compressedTokens: tokens,
            compressionRatio: 1.0
        )
    }
}

// MARK: - Answer Verification

extension ContextualCompressionService {
    /// Verify that an answer is grounded in the provided context
    /// - Parameters:
    ///   - answer: The generated answer
    ///   - context: The retrieved context chunks
    ///   - query: The original query
    /// - Returns: Verification result with confidence score
    func verifyAnswerGrounding(
        answer: String,
        context: [String],
        query: String
    ) async throws -> GroundingVerification {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                return GroundingVerification.unverified
            }

            if session == nil {
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    return GroundingVerification.unverified
                }
                session = LanguageModelSession(model: model)
            }

            guard let session = session else {
                return GroundingVerification.unverified
            }

            let combinedContext = context.joined(separator: "\n\n---\n\n")

            let prompt = """
            Analyze whether this answer is fully grounded in the provided context.

            Question: \(query)

            Context:
            \(combinedContext.prefix(3000))

            Answer to verify:
            \(answer)

            Respond with ONLY one of:
            - GROUNDED: Answer is fully supported by context
            - PARTIAL: Answer is partially supported but adds unsupported claims
            - UNGROUNDED: Answer contains significant unsupported claims
            - NOT_ANSWERABLE: Context doesn't contain enough info to answer

            Then on a new line, briefly explain why (one sentence).
            """

            let response = try await session.respond(to: prompt)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            return parseGroundingResult(result)

        #else
            return GroundingVerification.unverified
        #endif
    }

    private func parseGroundingResult(_ result: String) -> GroundingVerification {
        let lines = result.components(separatedBy: "\n")
        let firstLine = lines.first?.uppercased() ?? ""
        let explanation = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if firstLine.contains("GROUNDED") && !firstLine.contains("UNGROUNDED") {
            return GroundingVerification(
                status: .grounded,
                confidence: 0.9,
                explanation: explanation
            )
        } else if firstLine.contains("PARTIAL") {
            return GroundingVerification(
                status: .partiallyGrounded,
                confidence: 0.6,
                explanation: explanation
            )
        } else if firstLine.contains("NOT_ANSWERABLE") {
            return GroundingVerification(
                status: .notAnswerable,
                confidence: 0.7,
                explanation: explanation
            )
        } else {
            return GroundingVerification(
                status: .ungrounded,
                confidence: 0.3,
                explanation: explanation
            )
        }
    }
}

/// Result of answer grounding verification
struct GroundingVerification: Sendable {
    enum Status: Sendable {
        case grounded // Answer fully supported
        case partiallyGrounded // Some claims unsupported
        case ungrounded // Significant hallucination
        case notAnswerable // Context insufficient
        case unverified // Couldn't verify (model unavailable)
    }

    let status: Status
    let confidence: Double // 0.0 - 1.0
    let explanation: String

    static let unverified = GroundingVerification(
        status: .unverified,
        confidence: 0.0,
        explanation: "Verification unavailable"
    )
}

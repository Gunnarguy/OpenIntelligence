//
//  AgenticOrchestrator+Retrieval.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

extension AgenticOrchestrator {
    // MARK: - Retrieval Quality Evaluation

    typealias RetrievalQuality = AgenticRetrievalQuality

    // MARK: - Lexical Relevance Check

    /// Stop words to exclude from keyword matching
    private static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
        "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
        "through", "during", "before", "after", "above", "below", "between",
        "under", "again", "further", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "each", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than",
        "too", "very", "just", "also", "now", "what", "which", "who", "whom",
        "this", "that", "these", "those", "am", "it", "its", "i", "me", "my",
        "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
        "he", "him", "his", "she", "her", "hers", "they", "them", "their",
    ]

    /// Check if query keywords appear in retrieved chunks (simple but effective)
    /// Returns 0.0-1.0 representing what fraction of query keywords appear in chunks
    func checkLexicalRelevance(query: String, chunks: [RetrievedChunk]) -> Float {
        // Extract meaningful keywords from query (non-stopwords, 3+ chars)
        let queryWords = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }

        guard !queryWords.isEmpty else { return 0.5 }  // Can't evaluate, assume ok

        // Build combined chunk text
        let chunkText = chunks.prefix(5)
            .map { $0.chunk.contextText.lowercased() }
            .joined(separator: " ")

        // Count how many query keywords appear in chunks
        var matchCount = 0
        for word in queryWords {
            if chunkText.contains(word) {
                matchCount += 1
            }
        }

        let relevance = Float(matchCount) / Float(queryWords.count)
        Log.debug(
            "[LexicalRelevance] \(matchCount)/\(queryWords.count) keywords found = \(String(format: "%.0f%%", relevance * 100))",
            category: .retrieval)

        return relevance
    }
    /// Evaluate retrieval quality based on similarity scores and coverage
    /// NOTE: Semantic similarity scores are inherently lower than people expect.
    /// 0.15-0.25 is often "good enough" for useful retrieval - don't give up too early!
    func evaluateRetrievalQuality(chunks: [RetrievedChunk], query: String) -> RetrievalQuality {
        AgenticPolicyService.retrievalQuality(chunks: chunks, config: config)
    }

    /// Check if a query would benefit from decomposition
    /// Only true for genuinely multi-faceted questions, not just low-confidence single-topic
    func queryBenefitsFromDecomposition(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Multi-faceted indicators
        let multiFacetedPatterns = [
            "compare", "contrast", "versus", " vs ",
            "pros and cons", "advantages and disadvantages",
            "all the ways", "everything about", "complete overview",
            "relationship between .* and",
            "how does .* affect .* and",
            " and also ", " as well as ", " in addition to ",
        ]

        for pattern in multiFacetedPatterns {
            if pattern.contains(".*") {
                if lowercased.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            } else if lowercased.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Check if a query requires an exhaustive/comprehensive answer
    /// These are "what does X do" or "tell me everything about X" type questions
    /// where we need to find ALL relevant info, not just the first confident match
    func queryRequiresExhaustiveAnswer(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Patterns that indicate user wants a complete/comprehensive answer
        let exhaustivePatterns = [
            "what does .* do",
            "what happens when",
            "what can .* do",
            "tell me about",
            "explain .* to me",
            "how does .* work",
            "what are all",
            "list all",
            "everything about",
            "all the features",
            "all the functions",
            "capabilities of",
            "what is .* capable of",
            "describe .*",
            "full explanation",
            "complete overview",
        ]

        for pattern in exhaustivePatterns {
            if pattern.contains(".*") {
                if lowercased.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            } else if lowercased.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Reformulate query based on what we found (or didn't find) in initial retrieval
    func reformulateQuery(
        originalQuery: String,
        retrievedContext: String,
        ragService: RAGService
    ) async throws -> String? {
        let prompt = """
            You are helping improve a search query.The original query found some results, but they may not be ideal.

            Original query: \(originalQuery)

            Content found(excerpt):
                \(retrievedContext.prefix(800))

            Based on the vocabulary and terminology in the retrieved content, suggest ONE improved search query.
                IMPORTANT: The improved query must be about the SAME topic as the original query.
                Use key terms from the documents that relate to the original question.
                Output ONLY the new query phrase, nothing else .
            """

        // A search phrase has no closing full stop, so continuation took it for a cut-off sentence and asked for more,
        // which came back as "... in this libraryusing document specificationswithin this library" on the owner's
        // iPhone (Deep Think, 2026-10-21). A query is one line; nothing is continued (5.7).
        let response = try await ragService.generateWithFreshSession(prompt: prompt, maxTokens: 128, skipContinuation: true)
        let reformulated = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's actually different and reasonable
        if reformulated.count > 10, reformulated.count < 200, reformulated != originalQuery {
            return reformulated
        }
        return nil
    }

    // MARK: - Evidence Budget

    /// Headroom for the chat template, citation scaffolding, and tokenizer disagreement between
    /// our estimate and Apple's actual count.
    private static let evidenceSafetyReserve = 256

    /// Never starve synthesis completely, even if a prompt overruns its own budget.
    private static let minimumEvidenceTokens = 512

    /// What a budgeted assembly kept, and what it threw away.
    ///
    /// The dropped counts exist so truncation cannot be silent. Every prior version of this path
    /// cut evidence with a bare `prefix(_:)` and logged nothing, so a run that answered from 3.5%
    /// of what it retrieved produced a trace identical to one that answered from all of it.
    private struct EvidenceBudget {
        let context: String
        /// The chunks actually rendered, in the order they were rendered. Citation resolution is
        /// positional (`[S1]` resolves to `sourceChunks[0]`), so this must be what travels to
        /// `generateWithProperConsent`, not the caller's original array.
        let chunks: [RetrievedChunk]
        let chunksOffered: Int
        let tokensIncluded: Int
        let tokensDropped: Int
        /// Whether the highest-scoring chunk survived.
        let keptTopChunk: Bool

        var chunksIncluded: Int { chunks.count }
        var chunksDropped: Int { max(0, chunksOffered - chunks.count) }
    }

    /// Evidence tokens available once the system prompt, the query, and the reserved output are
    /// paid for.
    ///
    /// Derived rather than hardcoded. The `prefix(3000)` this replaces was a character count
    /// justified by a comment describing a system prompt it no longer matched.
    private func evidenceTokenBudget(
        systemPrompt: String,
        query: String,
        outputReserve: Int
    ) -> Int {
        // Ask "does this fit on device" using the on-device ratio regardless of where the query is
        // ultimately allowed to run. Deriving the ratio from the assumed destination makes the
        // budget most generous exactly when the device is the destination and least able to hold it.
        let contextSize = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let overhead =
            FoundationModelTokenBudget.estimateTokens(for: systemPrompt, isAppleFMOnDevice: true)
            + FoundationModelTokenBudget.estimateTokens(for: query, isAppleFMOnDevice: true)
            + outputReserve
            + Self.evidenceSafetyReserve
        return max(Self.minimumEvidenceTokens, contextSize - overhead)
    }

    /// Render one evidence block in the `[S1]` form the prompts instruct and the citation
    /// resolver parses (`RAGService.citationRegex` is `\[S\d+\]`).
    private func renderEvidenceBlock(_ retrieved: RetrievedChunk, label: Int) -> String {
        var block = "[S\(label)] From \(retrieved.sourceDocument)"
        if let page = retrieved.pageNumber {
            block += " (Page \(page))"
        }
        block += " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
        block += retrieved.chunk.contextText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        block += "\n\n"
        return block
    }

    /// Pack retrieved evidence into `tokenBudget`, highest-scoring chunk first.
    ///
    /// Rank order is restored here on purpose. `executeFullRetrievalPipeline` finishes with a
    /// lost-in-middle reorder that interleaves the ranked set, so the array arriving here holds
    /// its best chunk near the midpoint — for 85 chunks, at index 42. Packing in array order
    /// therefore discarded the single most relevant chunk first. Packing in score order discards
    /// the least relevant one first, which is the only ordering that makes truncation survivable.
    private func assembleBudgetedEvidence(
        chunks: [RetrievedChunk],
        tokenBudget: Int,
        stage: String
    ) -> EvidenceBudget {
        guard !chunks.isEmpty else {
            return EvidenceBudget(
                context: "",
                chunks: [],
                chunksOffered: 0,
                tokensIncluded: 0,
                tokensDropped: 0,
                keptTopChunk: false
            )
        }

        // Score descending, original position as a deterministic tiebreak. Retrieval here is only
        // ~21% reproducible run to run; an unstable sort would stack a second source of variation
        // on top of that and make any A/B unreadable.
        let ranked = chunks.enumerated().sorted { lhs, rhs in
            if lhs.element.similarityScore != rhs.element.similarityScore {
                return lhs.element.similarityScore > rhs.element.similarityScore
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var context = ""
        var included: [RetrievedChunk] = []
        var tokensIncluded = 0
        var tokensDropped = 0
        var keptTopChunk = false

        for (position, retrieved) in ranked.enumerated() {
            let block = renderEvidenceBlock(retrieved, label: included.count + 1)
            let blockTokens = FoundationModelTokenBudget.estimateTokens(for: block, isAppleFMOnDevice: true)
            let remaining = tokenBudget - tokensIncluded

            if blockTokens <= remaining {
                context += block
                tokensIncluded += blockTokens
                included.append(retrieved)
                if position == 0 { keptTopChunk = true }
                continue
            }

            // The best chunk is never dropped whole. If it alone overruns the budget, cut it at a
            // sentence boundary and keep the head; losing part of the top match still beats losing
            // all of it, which is what the old prefix cut did whenever expansion had run.
            if position == 0, remaining > Self.minimumEvidenceTokens / 2 {
                let charBudget = Int(Double(remaining) * FoundationModelTokenBudget.onDeviceCharsPerToken)
                let trimmed = truncateAtSentenceBoundary(block, limit: charBudget)
                let trimmedTokens = FoundationModelTokenBudget.estimateTokens(for: trimmed, isAppleFMOnDevice: true)
                context += trimmed + "\n\n"
                tokensIncluded += trimmedTokens
                included.append(retrieved)
                keptTopChunk = true
                tokensDropped += max(0, blockTokens - trimmedTokens)
                Log.warning(
                    "[Deep Think] \(stage): top-ranked chunk exceeded the whole evidence budget; "
                        + "kept \(trimmed.count)/\(block.count) chars of it",
                    category: .llm
                )
                continue
            }

            tokensDropped += blockTokens
        }

        let outcome = EvidenceBudget(
            context: context,
            chunks: included,
            chunksOffered: chunks.count,
            tokensIncluded: tokensIncluded,
            tokensDropped: tokensDropped,
            keptTopChunk: keptTopChunk
        )

        // One line, always emitted, naming what was dropped. Silent truncation across fourteen
        // stages is the defect class this pipeline keeps reproducing.
        Log.info(
            "[Deep Think] \(stage) evidence budget: kept \(outcome.chunksIncluded)/\(outcome.chunksOffered) chunks, "
                + "\(outcome.tokensIncluded)/\(tokenBudget) tokens; dropped \(outcome.chunksDropped) chunks "
                + "(~\(outcome.tokensDropped) tokens)",
            category: .llm
        )
        if !outcome.keptTopChunk {
            Log.warning("[Deep Think] \(stage): highest-scoring chunk did not fit the budget", category: .llm)
        }

        return outcome
    }

    /// Direct synthesis when retrieval confidence is high - comprehensive answer
    /// Uses the SAME formatting and consent flow as Standard mode
    /// CRITICAL: Respects 4096 token limit for Apple Foundation Models
    func executeDirectSynthesis(
        query: String,
        searchResults: String,
        chunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let __spSynthesisDirect = PipelineSignposts.synthesis.beginInterval("SynthesisDirect")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisDirect", __spSynthesisDirect) }
        let startTime = Date()

        // Deep Think mode: thorough synthesis with actionable details
        let systemPrompt = """
            Answer using ONLY the provided excerpts [S1], [S2], etc.
            Rules:
            1) Cite sources as [S1], [S2] etc. (NOT URLs)
            2) Extract specific values: numbers, measurements, specs, ratings when present
            3) Be thorough — pull every relevant detail from the excerpts
            4) Write naturally and intelligently — match your format to what the user actually asked
            5) Read OCR'd text carefully for model numbers, specs, and data
            6) NEVER say "I don't have information" — always provide what IS there
            7) ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT expansions. Never expand an abbreviation differently than the glossary defines it.
            """

        let outputReserve = 800
        let budget = evidenceTokenBudget(
            systemPrompt: systemPrompt,
            query: query,
            outputReserve: outputReserve
        )

        // Prefer the chunks. `searchResults` arrives pre-rendered by `executeSearchStepWithChunks`,
        // which itself keeps only `chunks.prefix(10)` of a lost-in-middle-ordered array, so packing
        // from the string cannot recover the top match once expansion has run.
        let evidence = assembleBudgetedEvidence(
            chunks: chunks,
            tokenBudget: budget,
            stage: "DirectSynthesis"
        )

        let context: String
        let sourceChunks: [RetrievedChunk]
        if evidence.chunks.isEmpty {
            // No chunks reached us. Budget the rendered string by tokens rather than a blind
            // character prefix, and say so, so this fallback is visible in the trace.
            let charBudget = Int(Double(budget) * FoundationModelTokenBudget.onDeviceCharsPerToken)
            context = truncateAtSentenceBoundary(searchResults, limit: charBudget)
            sourceChunks = []
            if searchResults.count > context.count {
                Log.warning(
                    "[Deep Think] DirectSynthesis fell back to string budgeting: kept \(context.count)/"
                        + "\(searchResults.count) chars, no chunks available for rank-ordered packing",
                    category: .llm
                )
            }
        } else {
            context = evidence.context
            sourceChunks = evidence.chunks
        }

        // Generate using the main RAGService pipeline which handles:
        // - PCC consent prompts
        // - Cloud transmission recording
        // - Proper execution context routing
        // Use conservative maxTokens to fit in 4096 window
        let response = try await LLMStreamingContext.$handler.withValue(LLMStreamingContext.answerHandler) {
            try await ragService.generateWithProperConsent(
                prompt: query,
                context: context,
                systemPrompt: systemPrompt,
                maxTokens: outputReserve,  // Conservative to stay within 4096 total
                disableTools: true,
                // Citations resolve positionally, so the model must be handed the same ordered subset
                // that was rendered into the prompt.
                sourceChunks: sourceChunks
            )
        }

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Comprehensive synthesis with full chunk context - like Standard mode
    /// This formats chunks properly and provides maximum context to the LLM
    /// Uses the SAME context formatting and system prompt as Standard mode
    /// CRITICAL: Respects 4096 token limit for Apple Foundation Models
    func executeComprehensiveSynthesis(
        query: String,
        chunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let __spSynthesisComprehensive = PipelineSignposts.synthesis.beginInterval("SynthesisComprehensive")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisComprehensive", __spSynthesisComprehensive) }
        let startTime = Date()

        // Format chunks EXACTLY like Standard mode's assembleContext with [S1], [S2] notation
        var contextBuilder = ""
        let maxContextChars = 2800  // Reduced to account for enhanced prompt

        // SENTENCE-LEVEL EXTRACTION: Instead of packing 3-4 whole chunks and
        // hoping the answer is in one of them, extract only query-relevant
        // sentences from ALL candidates. With 2800 chars, this fits targeted
        // data from 8-12 sources instead of 3 whole chunks.
        // Universal across all document types.
        let extraction = await ragService.extractRelevantSentences(
            from: chunks,
            query: query,
            maxChars: maxContextChars,
            compact: true
        )
        contextBuilder = extraction.context
        let usedChunks = extraction.sourcesUsed

        Log.info(
            "[Deep Think] Sentence extraction: \(extraction.sentencesIncluded) sentences from \(usedChunks) sources, \(contextBuilder.count) chars",
            category: .llm)

        // Deep Think mode: comprehensive multi-source synthesis
        let systemPrompt = """
            Answer using excerpts [S1], [S2]. Extract ALL specific values, numbers, specs.
            Read OCR'd text carefully. Write naturally. Cite [S1], [S2] only.
            NEVER say "I don't have information" — provide what IS there.
            ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT expansions.
            If vague, interpret based on document topics.
            """

        // Generate using the main RAGService pipeline which handles:
        // - PCC consent prompts
        // - Cloud transmission recording
        // - Proper execution context routing
        // Use conservative maxTokens to fit in 4096 window
        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: contextBuilder,
            systemPrompt: systemPrompt,
            maxTokens: 800,  // Conservative to stay within 4096 total
            disableTools: true,
            // This path renders `chunks` into `contextBuilder`, so the rendered-evidence
            // fallback already keeps it from abstaining. Passing the chunks themselves
            // upgrades that from a synthetic "there is some evidence" signal to the real
            // count and similarity scores, which is what the planner is meant to judge.
            sourceChunks: chunks
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Truncate text at a sentence boundary, preferring to keep complete sentences
    private func truncateAtSentence(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }

        let truncated = String(text.prefix(maxChars))

        // Find last sentence-ending punctuation
        let sentenceEnders: [Character] = [".", "!", "?"]
        if let lastSentenceEnd = truncated.lastIndex(where: { sentenceEnders.contains($0) }) {
            let endIndex = truncated.index(after: lastSentenceEnd)
            let result = String(truncated[..<endIndex])
            // Only use sentence boundary if we keep at least 60% of the truncated text
            if result.count >= maxChars * 6 / 10 {
                return result
            }
        }

        // Fall back to word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }

        return truncated + "…"
    }

    /// Honest synthesis when confidence is low - acknowledges limitations
    /// Uses proper consent flow for PCC
    private func executeHonestSynthesis(
        query: String,
        searchResults: String,
        confidence: RetrievalQuality,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let __spSynthesisHonest = PipelineSignposts.synthesis.beginInterval("SynthesisHonest")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisHonest", __spSynthesisHonest) }
        let startTime = Date()

        // Truncate to fit in 4096 token budget
        // Enhanced prompt ~250 tokens, query ~50, output ~800 = 1100 overhead
        // Remaining: 4096 - 1100 = 2996 tokens ≈ 4200 chars, use 3000 for safety
        let truncatedResults = String(searchResults.prefix(3000))

        // Even for low-confidence, extract maximum value from available excerpts
        let systemPrompt = """
            The available excerpts may not directly answer the query, but extract MAXIMUM value:
            - Cite sources [S1], [S2] for everything mentioned
            - Include ANY procedures, specifications, or actions found
            - Note related topics that might help the user
            - Be specific about what the excerpts DO cover
            - Include all technical details found, even if tangential
            - ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT expansions
            """

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: truncatedResults,
            systemPrompt: systemPrompt,
            maxTokens: 800,
            disableTools: true
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Decomposed pipeline for genuinely multi-faceted questions
    func executeDecomposedPipeline(
        query: String,
        initialChunks: [RetrievedChunk],
        initialSearchOutput: String,
        steps: inout [ThinkingStep],
        totalTokens: inout Int,
        ragService: RAGService,
        onStep: ((ThinkingStep) async -> Void)?,
        startTime: Date
    ) async throws -> AgenticResult {
        let __spSynthesisDecomposed = PipelineSignposts.synthesis.beginInterval("SynthesisDecomposed")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisDecomposed", __spSynthesisDecomposed) }
        var allRetrievedChunks = initialChunks

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        let plannedSubQueries = await plannerSubQueries(for: query)
        let planningStep: ThinkingStep
        let subQueries: [String]

        if !plannedSubQueries.isEmpty {
            planningStep = ThinkingStep(
                id: UUID(),
                type: .planning,
                input: query,
                output: plannedSubQueries.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(
                    separator: "\n"),
                tokensUsed: 0,
                duration: 0,
                timestamp: Date()
            )
            subQueries = plannedSubQueries
        } else {
            planningStep = try await executePlanningStep(query: query, ragService: ragService)
            subQueries = parseSubQueries(from: planningStep.output)
        }

        steps.append(planningStep)
        totalTokens += planningStep.tokensUsed
        await onStep?(planningStep)

        // Execute sub-queries
        var searchResults: [(query: String, result: String)] = [(query, initialSearchOutput)]

        for subQuery in subQueries.prefix(config.maxSteps - 2) {

            guard totalTokens < config.maxTotalTokens else { break }

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: subQuery,
                ragService: ragService,
                onDetailedEvent: detailedForwarder
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            searchResults.append((subQuery, searchStep.output))

            for chunk in chunks {
                if !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }
            }

            await onStep?(searchStep)
        }

        // Final synthesis
        _ = compressSearchResults(searchResults)  // Compressed for potential future use
        let synthesisStep = try await executeSynthesisStep(
            query: query,
            steps: steps,
            ragService: ragService
        )
        steps.append(synthesisStep)
        totalTokens += synthesisStep.tokensUsed
        await onStep?(synthesisStep)

        return AgenticResult(
            finalAnswer: synthesisStep.output,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: 0.7,
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    // MARK: - Individual Step Executors

    private func executePlanningStep(query: String, ragService: RAGService) async throws -> ThinkingStep {
        let startTime = Date()

        let planningPrompt = """
            You are a research planning assistant. Break down this query into 2-4 focused sub-questions that can be answered independently.

            Query: \(query)

            Output format:
            1. [First sub-question]
            2. [Second sub-question]
            ...

            Keep each sub-question focused and searchable. Do not answer the questions, just list them.
            """

        // Use a fresh, minimal session for planning
        let response = try await ragService.generateWithFreshSession(
            prompt: planningPrompt,
            maxTokens: 256
        )

        return ThinkingStep(
            id: UUID(),
            type: .planning,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    private func executeSearchStep(subQuery: String, ragService: RAGService) async throws -> ThinkingStep {
        let startTime = Date()

        // Use the RAG pipeline to search documents
        let searchResult = try await ragService.searchDocuments(
            query: subQuery,
            topK: 12,
            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .focusedSubquery)
        )

        return ThinkingStep(
            id: UUID(),
            type: .searching,
            input: subQuery,
            output: searchResult,
            tokensUsed: searchResult.split(separator: " ").count,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Search step using the FULL Standard pipeline (HyDE, re-ranking, MMR) - not just basic search
    /// - Parameter onDetailedEvent: Optional callback to emit verbose thinking events (for ThinkingView)
    func executeSearchStepWithChunks(
        subQuery: String,
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()

        // Emit: Starting this search
        await onDetailedEvent?(.retrieval, "Searching", "Query: \"\(subQuery.prefix(40))...\"")

        // Use the FULL hybrid search pipeline with re-ranking and MMR (like Standard mode)
        // This gives us HyDE, AI re-ranking, MMR diversification - everything Standard mode does
        let chunks = try await ragService.executeFullRetrievalPipeline(
            query: subQuery,
            topK: 20,
            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .search),
            qualityMode: qualityMode,
            onDetailedEvent: onDetailedEvent
        )

        // Format for LLM consumption - include more context since we have better chunks
        var searchResult =
            chunks.isEmpty
            ? "No relevant information found for: \(subQuery)"
            : "Found \(chunks.count) relevant chunks (re-ranked by relevance):\n\n"

        for (index, retrieved) in chunks.prefix(10).enumerated() {

            searchResult += "[\(index + 1)] From \(retrieved.sourceDocument)"
            if let page = retrieved.pageNumber {
                searchResult += " (Page \(page))"
            }
            searchResult += " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.contextText.trimmingCharacters(
                in: .whitespacesAndNewlines)
            // Include more text since our chunks are better quality now
            let preview = fullText.count > 1000 ? String(fullText.prefix(1000)) + " [...]" : fullText
            searchResult += preview
            searchResult += "\n\n"
        }

        let step = ThinkingStep(
            id: UUID(),
            type: .searching,
            input: subQuery,
            output: searchResult,
            tokensUsed: searchResult.split(separator: " ").count,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )

        return (step, chunks)
    }

    // MARK: - Multi-Query Search (Universal Semantic Coverage)

    /// Generate diverse search queries using LLM to cover all semantic angles of the question.
    /// This is the key to universal retrieval - we don't hardcode synonyms, we let the LLM
    /// understand the user's INTENT and generate queries that would find relevant content.
    ///
    /// For "What dosage should I take?", the LLM might generate:
    /// - "recommended dosage amount"
    /// - "dose quantity milligrams"
    /// - "administration instructions"
    /// - "prescribing guidelines"
    func generateSearchQueries(
        originalQuery: String,
        ragService: RAGService
    ) async throws -> [String] {
        let planningProfile = await QueryProfileService.shared.buildProfile(
            for: originalQuery,
            routingEnabled: false
        )
        let executionPlan = await QueryExecutionPlannerService.shared.buildPlan(
            for: originalQuery,
            profile: planningProfile,
            requestedQualityMode: qualityMode,
            allowToolCalling: true
        )

        var queries = executionPlan.searchQueries
        if executionPlan.executionMode == .directLookup || queries.count >= 3 {
            Log.info("[MultiQuery] Planner generated \(queries.count) search queries: \(queries)", category: .retrieval)
            return Array(queries.prefix(5))
        }

        let prompt = """
            Write concrete search phrases for the exact question below.

            Rules:
            - Keep the same entities, units, and objects from the question.
            - Do not add placeholders, brackets, examples, or unknown make/model text.
            - Return only search phrases, one per line.

            Question: \(originalQuery)

            1. \(originalQuery)
            2.
            3.
            4.
            """

        // Multi-query expansion is an *optimization*: it widens retrieval with
        // extra search phrasings. It is not load-bearing — `deterministicSearchQueries`
        // already covers the case where the model returns nothing useful.
        //
        // Previously this used `try await`, so any generation failure propagated
        // out and killed the whole Deep Think query. Observed on macOS: Apple's
        // SDK threw `GenerationError` ("Failed to parse generated content") in
        // this step, and the user's entire request failed with it — despite
        // retrieval being perfectly capable of proceeding on the deterministic
        // phrasings. A helper step must not be able to take down the answer.
        let response: LLMResponse?
        do {
            response = try await ragService.generateWithFreshSession(
                prompt: prompt,
                maxTokens: 200
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.warning(
                "[MultiQuery] Expansion generation failed; continuing with deterministic "
                    + "search phrases. type=\(type(of: error)) "
                    + "full=\(String(describing: error))",
                category: .retrieval
            )
            response = nil
        }

        // Parse numbered lines or JSON array from response
        if queries.isEmpty {
            queries = deterministicSearchQueries(for: originalQuery)
        }

        guard let response else {
            Log.info("[MultiQuery] Using \(queries.count) deterministic search queries", category: .retrieval)
            return Array(queries.prefix(5))
        }

        func appendIfUseful(_ candidate: String) {
            let queryText = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableGeneratedSearchQuery(queryText, originalQuery: originalQuery) else { return }
            guard !queries.contains(where: { $0.caseInsensitiveCompare(queryText) == .orderedSame }) else { return }
            queries.append(queryText)
        }

        // Try JSON array first
        if let jsonStart = response.text.firstIndex(of: "["),
            let jsonEnd = response.text.lastIndex(of: "]")
        {
            let jsonString = String(response.text[jsonStart...jsonEnd])
            if let data = jsonString.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String]
            {
                for q in parsed { appendIfUseful(q) }
            }
        }

        // Fallback: parse numbered lines (e.g., "2. some query", "3. another query")
        if queries.count <= 4 {
            // Apple FM often puts ALL queries on one line: "query1? 2. query2 3. query3 4. query4"
            // First, try splitting on mid-line numbered patterns before falling back to newline split
            let fullText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let midLinePattern = #"\s*\d+[\.\)]\s+"#
            if let regex = try? NSRegularExpression(pattern: midLinePattern) {
                let range = NSRange(fullText.startIndex..., in: fullText)
                let matches = regex.matches(in: fullText, range: range)
                if matches.count >= 2 {
                    // Found multiple numbered items on potentially one line — split on them
                    var splitQueries: [String] = []
                    var lastEnd = fullText.startIndex
                    for match in matches {
                        if let matchRange = Range(match.range, in: fullText) {
                            let segment = String(fullText[lastEnd..<matchRange.lowerBound]).trimmingCharacters(
                                in: .whitespacesAndNewlines)
                            if !segment.isEmpty && segment.count > 3 {
                                splitQueries.append(segment)
                            }
                            lastEnd = matchRange.upperBound
                        }
                    }
                    // Don't forget the last segment after the final number
                    let lastSegment = String(fullText[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lastSegment.isEmpty && lastSegment.count > 3 {
                        splitQueries.append(lastSegment)
                    }
                    for q in splitQueries { appendIfUseful(q) }
                }
            }

            // If mid-line split didn't work, try line-by-line
            if queries.count <= 4 {
                let lines = response.text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Match "2. query text" or "- query text" patterns
                    if let dotRange = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                        let queryText = String(trimmed[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        appendIfUseful(queryText)
                    } else if trimmed.hasPrefix("- ") {
                        let queryText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        appendIfUseful(queryText)
                    }
                }
            }
        }

        Log.info("[MultiQuery] Generated \(queries.count) search queries: \(queries)", category: .retrieval)
        return Array(queries.prefix(5))  // Cap at 5 to limit latency
    }

    private func plannerSubQueries(for query: String) async -> [String] {
        let planningProfile = await QueryProfileService.shared.buildProfile(
            for: query,
            routingEnabled: false
        )
        let executionPlan = await QueryExecutionPlannerService.shared.buildPlan(
            for: query,
            profile: planningProfile,
            requestedQualityMode: qualityMode,
            allowToolCalling: true
        )
        return Array(executionPlan.subqueries.prefix(4))
    }

    private func deterministicSearchQueries(for originalQuery: String) -> [String] {
        let original = originalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return [] }

        let lower = original.lowercased()
        var queries: [String] = [original]

        let hasFuelTerm = ["gas", "gasoline", "fuel"].contains { lower.contains($0) }
        let hasCapacityTerm = [
            "capacity", "capacities", "hold", "holds", "holding", "volume", "amount", "how many", "how much",
        ].contains { lower.contains($0) }
        let hasLiquidUnit = ["gallon", "gallons", "gal", "liter", "liters", "litre", "litres"].contains {
            lower.contains($0)
        }

        if hasFuelTerm && (hasCapacityTerm || hasLiquidUnit) {
            queries.append("fuel gasoline gal capacity")
            queries.append("fuel tank capacity US gal")
            queries.append("gasoline fuel capacity liters gallons")
        } else if hasCapacityTerm || hasLiquidUnit {
            queries.append("\(original) capacity volume")
            if hasLiquidUnit {
                queries.append("\(original) gal liters")
            }
        }

        let stopWords: Set<String> = [
            "what", "which", "when", "where", "why", "how", "many", "much",
            "does", "this", "that", "these", "those", "the", "and", "for",
            "with", "from", "can", "could", "would", "should", "have", "has",
            "had", "its", "into", "about",
        ]
        let keyTerms =
            lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        if keyTerms.count >= 2 {
            queries.append(keyTerms.prefix(6).joined(separator: " "))
        }

        return uniqueSearchQueries(queries)
    }

    private func isUsableGeneratedSearchQuery(_ candidate: String, originalQuery: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3, trimmed.count <= 160 else { return false }

        let lower = trimmed.lowercased()
        let rejectedFragments = [
            "[", "]", "{", "}", "<", ">",
            "make and model", "car make", "specific make", "specific model",
            "insert", "placeholder", "example", "your query", "search phrase",
        ]
        guard !rejectedFragments.contains(where: { lower.contains($0) }) else { return false }
        guard lower != originalQuery.lowercased() else { return false }

        let originalTerms = Set(
            originalQuery.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )
        let candidateTerms = Set(
            lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )

        if originalTerms.isEmpty || candidateTerms.isEmpty {
            return true
        }

        let overlap = originalTerms.intersection(candidateTerms)
        if !overlap.isEmpty { return true }

        // Allow safe concept normalizations for common specification language.
        if originalTerms.contains("gas") && candidateTerms.intersection(["fuel", "gasoline"]).isEmpty == false {
            return true
        }
        if originalTerms.contains("gallons")
            && candidateTerms.intersection(["gal", "liters", "capacity"]).isEmpty == false
        {
            return true
        }
        if originalTerms.contains("hold") && candidateTerms.intersection(["capacity", "volume"]).isEmpty == false {
            return true
        }

        return false
    }

    private func uniqueSearchQueries(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    /// Execute multi-query search: search with multiple query variations and fuse results.
    /// Uses Reciprocal Rank Fusion (RRF) to combine rankings from different queries.
    /// - Parameter onDetailedEvent: Optional callback to emit verbose thinking events (for ThinkingView)
    /// Internal, not private, so `DeepThinkRetrievalGoldenTests` can record what it returns.
    func executeMultiQuerySearch(
        queries: [String],
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()

        await onDetailedEvent?(.retrieval, "Multi-query search", "Searching \(queries.count) query variations")

        var allResults: [[RetrievedChunk]] = []

        // The first search alone, then the rest two at a time, instead of all five one after another (5.8, 2026-11-07).
        // The five searches took 17.1 s on average one after another on the owner's iPhone (2026-11-04, about 3.6 s
        // each), and no search reads another's result. The results are put back in query order before the fusion below,
        // so its ranks and its first-seen tie-break see exactly the lists the loop used to append; only the order of the
        // progress events changes. The first runs alone because a search builds the library's vocabulary when it is not
        // cached yet, and searches started together would each build it. Two at a time, not five: each search's
        // reranker already runs up to four Core ML predictions at once (`RAGEngine`), and four remaining searches take
        // two rounds at two or at three (review, 2026-11-07).
        let maxConcurrentSearches = 2
        let mode = qualityMode
        let search: @Sendable (Int, String) async throws -> (Int, [RetrievedChunk]) = { index, query in
            await onDetailedEvent?(.retrieval, "Query \(index + 1)/\(queries.count)", "\"\(query.prefix(40))...\"")

            // Show full pipeline details for ALL queries (not just first)
            // Deep Think users want to see VECTOR, BM25, RRF, MMR, RERANK for each search
            let chunks = try await ragService.executeFullRetrievalPipeline(
                query: query,
                topK: 15,
                minSimilarity: 0.05,  // Very low - we'll use RRF to rank
                qualityMode: mode,
                onDetailedEvent: onDetailedEvent  // Always forward events
            )

            // Show result count for each query
            await onDetailedEvent?(.retrieval, "Query \(index + 1) done", "\(chunks.count) chunks retrieved")
            return (index, chunks)
        }
        var resultsByQuery: [Int: [RetrievedChunk]] = [:]
        if !queries.isEmpty, !Task.isCancelled {
            let (index, chunks) = try await search(0, queries[0])
            resultsByQuery[index] = chunks
        }
        try await withThrowingTaskGroup(of: (Int, [RetrievedChunk]).self) { group in
            var nextQuery = resultsByQuery.isEmpty ? queries.count : 1
            while nextQuery < queries.count, nextQuery < 1 + maxConcurrentSearches, !Task.isCancelled {
                let index = nextQuery, query = queries[index]
                group.addTask { try await search(index, query) }
                nextQuery += 1
            }
            while let (index, chunks) = try await group.next() {
                resultsByQuery[index] = chunks
                if nextQuery < queries.count, !Task.isCancelled {
                    let next = nextQuery, query = queries[next]
                    group.addTask { try await search(next, query) }
                    nextQuery += 1
                }
            }
        }
        for index in queries.indices {
            if let chunks = resultsByQuery[index] { allResults.append(chunks) }
        }

        await onDetailedEvent?(.rrf, "Fusing results", "RRF across \(allResults.count) result sets")

        // Reciprocal Rank Fusion across all query results
        // Track both RRF score (for multi-query consensus) AND original reranker score (for relevance)
        var chunkScores: [UUID: (chunk: RetrievedChunk, rrfScore: Float, maxRerankerScore: Float)] = [:]
        // Where each passage first appeared across the searches, in order (5.8). The sort below breaks a tie in the
        // blended score by it. It sorted the dictionary's values with no tie-break, and a dictionary's order differs
        // between two dictionaries in one process, so tied passages came back in a different order, and a different
        // twenty survived the cut, each time the same question was asked: 28 of 57 fused searches differed between two
        // passes over an unchanged library while all 703 single searches matched (`DeepThinkRetrievalGoldenTests`,
        // 2026-11-05). Earlier query and higher rank first is the order the searches themselves gave.
        var firstSeen: [UUID: Int] = [:]
        let k: Float = 60.0  // RRF constant

        for results in allResults {
            for (rank, chunk) in results.enumerated() {
                let rrfScore = 1.0 / (k + Float(rank + 1))
                if firstSeen[chunk.chunk.id] == nil { firstSeen[chunk.chunk.id] = firstSeen.count }

                if let existing = chunkScores[chunk.chunk.id] {
                    // Chunk seen in multiple queries - boost RRF score, keep max reranker score
                    chunkScores[chunk.chunk.id] = (
                        existing.chunk,
                        existing.rrfScore + rrfScore,
                        max(existing.maxRerankerScore, chunk.similarityScore)
                    )
                } else {
                    chunkScores[chunk.chunk.id] = (chunk, rrfScore, chunk.similarityScore)
                }
            }
        }

        // Sort by BLENDED score: 60% reranker (relevance) + 40% RRF (multi-query consensus)
        // CRITICAL: Pure reranker sorting lets a single high-scoring irrelevant chunk dominate.
        // E.g., a "radiator overheating" chunk scores 0.78 reranker for "fuel tank capacity"
        // because it mentions fuel gauge + engine + vehicle (lots of term overlap).
        // But the actual spec table only appears in 1-2 queries with lower reranker score.
        // RRF consensus rewards chunks that appear across MULTIPLE differently-worded queries,
        // which is a strong signal that the chunk actually addresses the topic.
        let maxRRF = chunkScores.values.map { $0.rrfScore }.max() ?? 1.0
        // The 5.8 audit switch (development builds): off, the weight on fusion is 0 and the reranker's score decides.
        let blendOff = RetrievalAblation.isOff(.multiQueryBlend)
        let rerankWeight: Float = blendOff ? 1 : 0.6
        let rrfWeight: Float = blendOff ? 0 : 0.4
        let fusedResults = chunkScores.values
            .sorted {
                let normRRF0 = $0.rrfScore / max(maxRRF, 0.001)
                let normRRF1 = $1.rrfScore / max(maxRRF, 0.001)
                let blended0 = $0.maxRerankerScore * rerankWeight + normRRF0 * rrfWeight
                let blended1 = $1.maxRerankerScore * rerankWeight + normRRF1 * rrfWeight
                if blended0 != blended1 { return blended0 > blended1 }
                return firstSeen[$0.chunk.chunk.id, default: .max] < firstSeen[$1.chunk.chunk.id, default: .max]
            }
            .prefix(20)
            .enumerated()
            .map { (index, retrieved) -> RetrievedChunk in
                // Use the reranker score as the similarity - this is what the reasoning chain needs
                return RetrievedChunk(
                    chunk: retrieved.chunk.chunk,
                    similarityScore: retrieved.maxRerankerScore,  // Actual relevance from reranker
                    rank: index + 1,
                    sourceDocument: retrieved.chunk.sourceDocument,
                    pageNumber: retrieved.chunk.pageNumber
                )
            }

        let resultChunks = Array(fusedResults)

        // Log top chunk for debugging - this should now show the most RELEVANT chunk
        if let topChunk = resultChunks.first {
            let preview = String(topChunk.chunk.content.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            Log.debug(
                "[MultiQuery] Top chunk (reranker score \(String(format: "%.2f", topChunk.similarityScore))): \(preview)...",
                category: .retrieval)
        }

        // Format for logging
        var searchResult = "Multi-query search with \(queries.count) variations:\n"
        searchResult += "Queries: \(queries.joined(separator: " | "))\n\n"
        searchResult += "Found \(resultChunks.count) unique chunks after RRF fusion\n"

        let step = ThinkingStep(
            id: UUID(),
            type: .searching,
            input: queries.first ?? "",
            output: searchResult,
            tokensUsed: 0,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )

        Log.info(
            "[MultiQuery] Fused \(allResults.map { $0.count }.reduce(0, +)) results into \(resultChunks.count) unique chunks",
            category: .retrieval)

        return (step, resultChunks)
    }

    /// Validate that retrieved chunks actually address the semantic intent of the question.
    /// This catches cases where retrieval grabbed related but wrong content.
    /// Returns (isValid, reason) - if invalid, reason explains what's missing.
    func validateSemanticIntent(
        query: String,
        chunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> (isValid: Bool, reason: String) {
        guard !chunks.isEmpty else {
            return (false, "No chunks retrieved")
        }

        // Quick heuristic check first - if top chunks have high scores, likely good
        let topScore = chunks.first?.similarityScore ?? 0
        if topScore > 0.6 {
            return (true, "High confidence match")
        }

        // Fast path: Check lexical overlap first (cheaper than LLM call)
        let lexicalScore = checkLexicalRelevance(query: query, chunks: chunks)
        if lexicalScore >= 0.5 {
            // At least half the query keywords found - likely relevant
            return (true, "Good keyword overlap (\(Int(lexicalScore * 100))%)")
        }

        if lexicalScore < 0.1 {
            // Almost no keyword overlap - clearly irrelevant
            return (false, "No keyword overlap with query")
        }

        // For borderline cases (10-50% overlap), ask LLM to verify
        let chunkPreviews = chunks.prefix(3).map { chunk in
            let content = chunk.chunk.contextText
            return String(content.prefix(300))
        }.joined(separator: "\n---\n")

        let prompt = """
            Question: \(query)

            Retrieved content:
            \(chunkPreviews)

            Does this content contain information to answer the question?
            Reply with ONLY one word: YES or NO
            """

        // A one-word YES or NO is complete as it stands; no continuation turn (5.8, 2026-11-07, as for the reformulation above).
        let response = try await ragService.generateWithFreshSession(
            prompt: prompt,
            maxTokens: 10,
            skipContinuation: true
        )

        let answer = response.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = answer.contains("yes")

        Log.debug(
            "[SemanticValidation] Query '\(query.prefix(40))...' → \(isValid ? "VALID" : "INVALID")",
            category: .retrieval)

        return (isValid, isValid ? "Content matches intent" : "Content does not address the question")
    }

    // MARK: - Cross-Reference Resolution

    /// Resolve cross-references found in retrieved chunks.
    /// Technical documents frequently say "see page X" or "given in 'Section Name'".
    /// The actual data (spec tables, procedures) lives in the referenced section, but
    /// the reranker consistently scores prose descriptions higher than structured tables.
    /// This method follows those references to retrieve the actual data chunks.
    ///
    /// Example: A chunk says "The fuel tank capacity is given in 'Recommended lubricants
    /// and capacities' on page 9-7." — this method retrieves chunks from that section.
    func resolveCrossReferences(
        chunks: [RetrievedChunk],
        query: String,
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> [RetrievedChunk] {
        // Cross-reference patterns common in technical documents
        // Each captures the section name or page reference
        // Use try?/compactMap instead of try! to prevent crashes from invalid regex
        let crossRefPatterns: [(regex: NSRegularExpression, captureGroup: Int)] = [
            // QUOTED: "given in 'Recommended lubricants and capacities' on page 9-7"
            // NOTE: In raw strings #"..."#, \u{} is literal text, NOT a Unicode escape.
            // ICU regex (NSRegularExpression) uses \x{HHHH} for Unicode code points.
            (
                pattern:
                    #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
                options: NSRegularExpression.Options.caseInsensitive, group: 1
            ),
            // QUOTED: "see 'Section Name'" or "refer to 'Section Name'"
            (
                pattern:
                    #"(?:see|refer\s+to|check|consult)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
                options: .caseInsensitive, group: 1
            ),
            // QUOTED: "in the 'Section Name' section/table/chapter"
            (
                pattern:
                    #"in\s+(?:the\s+)?['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]\s+(?:section|table|chapter|page)"#,
                options: .caseInsensitive, group: 1
            ),
            // UNQUOTED (case-insensitive): "given in recommended lubricants and capacities on page 9-7"
            (
                pattern:
                    #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
                options: .caseInsensitive, group: 1
            ),
            // UNQUOTED: "see section name on page X" or "refer to section name on page X"
            (
                pattern:
                    #"(?:see|refer\s+to|check|consult)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
                options: .caseInsensitive, group: 1
            ),
            // CATCH-ALL: "given in <any text> on page" — most permissive fallback
            (
                pattern:
                    #"(?:given|found|listed|shown|described|specified|provided)\s+(?:in|under|at)\s+(?:the\s+)?(.{5,80})\s+on\s+page"#,
                options: .caseInsensitive, group: 1
            ),
        ].compactMap { item -> (regex: NSRegularExpression, captureGroup: Int)? in
            let (pattern, options, group) = item
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                Log.error("[CrossRef] Failed to compile regex: \(pattern.prefix(60))...", category: .retrieval)
                return nil
            }
            return (regex, group)
        }

        var referencedSections: Set<String> = []
        let existingIds = Set(chunks.map { $0.chunk.id })

        // Scan top chunks for cross-references
        for chunk in chunks.prefix(12) {
            let content = chunk.chunk.content
            let range = NSRange(content.startIndex..., in: content)

            for (regex, group) in crossRefPatterns {
                let matches = regex.matches(in: content, range: range)
                for match in matches {
                    guard match.numberOfRanges > group,
                        let captureRange = Range(match.range(at: group), in: content)
                    else { continue }
                    let reference = String(content[captureRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Skip very short references or pure page numbers
                    if reference.count >= 5,
                        reference.range(of: #"^\d+[-–]?\d*$"#, options: .regularExpression) == nil
                    {
                        referencedSections.insert(reference)
                    }
                }
            }
        }

        guard !referencedSections.isEmpty else { return [] }

        Log.info(
            "[CrossRef] Found \(referencedSections.count) cross-references: \(referencedSections.joined(separator: ", "))",
            category: .retrieval)
        await onDetailedEvent?(
            .retrieval, "Cross-references", "Following \(referencedSections.count) document references")

        var additionalChunks: [RetrievedChunk] = []

        // Follow each cross-reference (limit to 3 to bound latency)
        for section in referencedSections.prefix(3) {
            await onDetailedEvent?(.retrieval, "Following ref", "Retrieving: \"\(section.prefix(40))\"")

            // Search for the referenced section using the full retrieval pipeline
            let sectionChunks = try await ragService.executeFullRetrievalPipeline(
                query: section,
                topK: 5,
                minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .crossReference),
                qualityMode: qualityMode,
                onDetailedEvent: nil  // Don't spam detailed events for sub-searches
            )

            var addedFromSection = 0
            for chunk in sectionChunks where !existingIds.contains(chunk.chunk.id) {
                // Boost cross-referenced chunks: the DOCUMENT itself said to look here.
                // Floor at 0.55 ensures these compete with reranker-favored prose chunks.
                // Cap preserves ordering among cross-ref results.
                let boostedScore = max(chunk.similarityScore, 0.55)
                let boosted = RetrievedChunk(
                    chunk: chunk.chunk,
                    similarityScore: boostedScore,
                    rank: chunk.rank,
                    sourceDocument: chunk.sourceDocument,
                    pageNumber: chunk.pageNumber
                )
                additionalChunks.append(boosted)
                addedFromSection += 1
            }

            Log.info(
                "[CrossRef] '\(section.prefix(40))': retrieved \(sectionChunks.count) chunks, \(addedFromSection) new",
                category: .retrieval)
        }

        if !additionalChunks.isEmpty {
            await onDetailedEvent?(
                .retrieval, "Cross-ref resolved", "+\(additionalChunks.count) chunks from referenced sections")

            let crossRefStep = ThinkingStep(
                id: UUID(),
                type: .searching,
                input: "Cross-reference resolution",
                output: "Followed \(referencedSections.count) document references → +\(additionalChunks.count) chunks",
                tokensUsed: 0,
                duration: 0.3,
                timestamp: Date()
            )
            // Log only, don't append to steps (caller handles that)
            Log.info("[CrossRef] \(crossRefStep.output)", category: .retrieval)
        }

        return additionalChunks
    }

    // MARK: - Graph Expansion (GraphRAG-lite)

    func executeGraphExpansion(
        query: String,
        initialChunks: [RetrievedChunk],
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()
        guard !initialChunks.isEmpty else {
            return (
                ThinkingStep(
                    id: UUID(),
                    type: .expanding,
                    input: query,
                    output: "",
                    tokensUsed: 0,
                    duration: Date().timeIntervalSince(startTime),
                    timestamp: startTime
                ),
                []
            )
        }

        await onDetailedEvent?(.agentic, "Graph expansion", "Extracting entities for hop search")

        let contextText =
            initialChunks
            .map { $0.chunk.contextText }
            .joined(separator: "\n")

        let entityPrompt = """
            Extract 3-5 important terms from this text that would be good search queries. Look for:
            - Product names, model numbers, or device names
            - Technical terms, features, or specifications
            - Actions, buttons, or UI elements mentioned
            - Error codes or status indicators

            Return a JSON array of strings, like: ["term1", "term2", "term3"]

            Text:
            \(contextText.prefix(2000))
            """

        let response = try await ragService.generateWithFreshSession(
            prompt: entityPrompt,
            maxTokens: 200
        )

        var entities = parseEntityList(from: response.text)
        entities = entities.filter { $0.count >= 3 }
        entities = Array(entities.prefix(3))

        if entities.isEmpty {
            entities = heuristicEntityFallback(from: contextText, excluding: query)
        }

        await onDetailedEvent?(
            .parentDoc, "Entity hop",
            "Searching \(entities.count) entities: \(entities.prefix(3).joined(separator: ", "))")

        var expandedChunks: [RetrievedChunk] = []

        for (idx, entity) in entities.enumerated() {
            if Task.isCancelled { break }
            await onDetailedEvent?(.parentDoc, "Hop \(idx + 1)/\(entities.count)", "\"\(entity)\"")

            // Use full pipeline for entity hop searches (shows VECTOR, BM25, RRF, MMR)
            let hopChunks = try await ragService.executeFullRetrievalPipeline(
                query: entity,
                topK: 4,
                minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .graphExpansion),
                qualityMode: qualityMode,
                onDetailedEvent: onDetailedEvent
            )
            for chunk in hopChunks where !expandedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                expandedChunks.append(chunk)
            }
        }

        await onDetailedEvent?(.parentDoc, "Graph complete", "+\(expandedChunks.count) chunks from entity hops")

        let output =
            entities.isEmpty
            ? "No graph entities identified"
            : "Entities: \(entities.joined(separator: ", ")) → +\(expandedChunks.count) chunks"

        let step = ThinkingStep(
            id: UUID(),
            type: .expanding,
            input: query,
            output: output,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )

        return (step, expandedChunks)
    }

    private func parseEntityList(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
            let list = try? JSONDecoder().decode([String].self, from: data)
        {
            return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        let cleaned =
            trimmed
            .replacingOccurrences(of: #"[\n\r]"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"[\[\]\"]"#, with: "", options: .regularExpression)

        return
            cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func heuristicEntityFallback(from text: String, excluding query: String) -> [String] {
        let pattern = #"\b[A-Z][A-Za-z0-9_]{2,}\b"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, options: [], range: nsRange) ?? []

        var candidates: [String] = []
        for match in matches {
            if let range = Range(match.range, in: text) {
                let term = String(text[range])
                if !query.contains(term) && !candidates.contains(term) {
                    candidates.append(term)
                }
            }
        }

        return Array(candidates.prefix(3))
    }

    private func executeAnalysisStep(
        query: String,
        searchResults: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let analysisPrompt = """
            Analyze these search results to answer the original question.

            Original Question: \(query)

            Search Results:
            \(searchResults)

            Provide a comprehensive answer based on the evidence. Rate your confidence (0.0-1.0) at the end.
            Format: [Answer text] CONFIDENCE: [0.X]
            """

        let response = try await ragService.generateWithFreshSession(
            prompt: analysisPrompt,
            maxTokens: 700
        )

        return ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Analyzing \(searchResults.prefix(50))...",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    private func executeRefinementStep(
        query: String,
        currentAnswer: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let refinementPrompt = """
            The current answer may be incomplete or uncertain. Search for additional evidence to strengthen it.

            Question: \(query)
            Current Answer: \(currentAnswer.prefix(500))

            What additional information would make this answer more complete? Provide refined answer with updated confidence.
            """

        let response = try await ragService.generateWithFreshSession(
            prompt: refinementPrompt,
            maxTokens: 512
        )

        return ThinkingStep(
            id: UUID(),
            type: .refining,
            input: "Refining answer...",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    private func executeSynthesisStep(
        query: String,
        steps: [ThinkingStep],
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let systemPrompt = """
            Synthesize findings into a comprehensive answer. Cite [S1], [S2] when available.
            Format with ### section headers, bullets only for actual lists, **bold** sparingly for key terms.
            Separate sections with blank lines for readability.
            """

        let outputReserve = 800
        let budget = evidenceTokenBudget(
            systemPrompt: systemPrompt,
            query: query,
            outputReserve: outputReserve
        )

        // This path summarizes prior reasoning steps rather than ranked chunks, so there is no
        // relevance order to pack against. It had two stacked cuts instead: a fixed
        // `prefix(150)` per step, then a `prefix(3000)` over the join. The per-step cut was the
        // more destructive of the two, since 150 characters truncates most steps mid-sentence
        // before the overall budget is even consulted.
        let header = "Research Steps:\n"
        let headerTokens = FoundationModelTokenBudget.estimateTokens(for: header, isAppleFMOnDevice: true)
        let bodyBudget = max(Self.minimumEvidenceTokens, budget - headerTokens)
        let bodyCharBudget = Int(Double(bodyBudget) * FoundationModelTokenBudget.onDeviceCharsPerToken)

        // Share the budget evenly across steps, then let the sentence-boundary trim reclaim what
        // short steps do not use.
        let perStepCharBudget = max(200, bodyCharBudget / max(1, steps.count))
        var droppedChars = 0
        let stepSummary = steps.map { step -> String in
            let body = truncateAtSentenceBoundary(step.output, limit: perStepCharBudget)
            droppedChars += max(0, step.output.count - body.count)
            return "\(step.type.rawValue): \(body)"
        }.joined(separator: "\n")

        let fitted = truncateAtSentenceBoundary(stepSummary, limit: bodyCharBudget)
        droppedChars += max(0, stepSummary.count - fitted.count)

        Log.info(
            "[Deep Think] SynthesisStep budget: \(steps.count) steps, kept \(fitted.count) chars "
                + "(~\(FoundationModelTokenBudget.estimateTokens(for: fitted, isAppleFMOnDevice: true))/\(bodyBudget) tokens); "
                + "dropped ~\(droppedChars) chars",
            category: .llm
        )

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: header + fitted,
            systemPrompt: systemPrompt,
            maxTokens: outputReserve,
            disableTools: true
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Final synthesis",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    // MARK: - Helpers

    private func parseSubQueries(from planningOutput: String) -> [String] {
        // Parse numbered list from planning output
        let lines = planningOutput.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match patterns like "1. ", "2. ", "- ", "• "
            if let range = trimmed.range(of: #"^(\d+\.|[-•])\s*"#, options: .regularExpression) {
                let query = String(trimmed[range.upperBound...])
                return query.isEmpty ? nil : query
            }
            return nil
        }
    }

    private func compressSearchResults(_ results: [(query: String, result: String)]) -> String {
        // Compress to fit within context window
        let maxPerResult = 800
        return results.map { pair in
            let truncated = String(pair.result.prefix(maxPerResult))
            return "[\(pair.query)]\n\(truncated)"
        }.joined(separator: "\n\n---\n\n")
    }

    private func extractConfidence(from text: String) -> Float {
        // Look for CONFIDENCE: 0.X pattern
        if let range = text.range(of: #"CONFIDENCE:\s*(0?\.\d+|1\.0)"#, options: .regularExpression) {
            let confidenceStr = text[range].replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(
                in: .whitespaces)
            return Float(confidenceStr) ?? 0.5
        }
        return 0.5  // Default confidence if not specified
    }

    private func countSources(in searchResult: String) -> Int {
        // Count citation patterns like [1], [Doc: X], etc.
        let pattern = #"\[(?:Doc:|Source:|\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        return regex?.numberOfMatches(in: searchResult, range: NSRange(searchResult.startIndex..., in: searchResult))
            ?? 0
    }

}

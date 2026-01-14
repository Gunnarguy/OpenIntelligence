//
//  AgenticOrchestrator.swift
//  OpenIntelligence
//
//  Retrieval-first agentic reasoning that escalates based on confidence.
//  Key insight: Don't decide complexity upfront - let retrieval results guide the pipeline.
//

import Foundation

/// Represents one step in the agentic reasoning loop
struct ThinkingStep: Identifiable, Sendable {
    let id: UUID
    let type: StepType
    let input: String
    let output: String
    let tokensUsed: Int
    let duration: TimeInterval
    let timestamp: Date

    enum StepType: String, Sendable {
        case planning = "🎯 Planning"
        case searching = "🔍 Searching"
        case analyzing = "🧠 Analyzing"
        case synthesizing = "✨ Synthesizing"
        case refining = "🔧 Refining"
        case reformulating = "🔄 Reformulating" // New: query reformulation step

        /// Display name for UI
        var displayName: String { rawValue }

        /// Map to ThinkingEvent.Kind for UI integration
        var thinkingKind: ThinkingEvent.Kind {
            switch self {
            case .planning: return .planning
            case .searching, .reformulating: return .retrieval
            case .analyzing: return .rerank
            case .synthesizing, .refining: return .generation
            }
        }
    }
}

/// Configuration for the agentic loop
struct AgenticConfig: Sendable {
    /// Maximum thinking steps before forcing synthesis
    let maxSteps: Int

    /// Maximum total tokens across all steps
    let maxTotalTokens: Int

    /// Whether to stream intermediate results
    let streamIntermediateResults: Bool

    /// Minimum confidence threshold to stop early (high = good enough to answer)
    let confidenceThreshold: Float

    /// Similarity threshold below which we escalate to deeper retrieval
    let escalationThreshold: Float

    nonisolated static let defaultConfig = AgenticConfig(
        maxSteps: 5,
        maxTotalTokens: 16000,
        streamIntermediateResults: true,
        confidenceThreshold: 0.85,
        escalationThreshold: 0.35 // If top result < 35% similarity, try harder
    )

    nonisolated static let fast = AgenticConfig(
        maxSteps: 2,
        maxTotalTokens: 8000,
        streamIntermediateResults: false,
        confidenceThreshold: 0.7,
        escalationThreshold: 0.25
    )

    nonisolated static let thorough = AgenticConfig(
        maxSteps: 8,
        maxTotalTokens: 32000,
        streamIntermediateResults: true,
        confidenceThreshold: 0.95,
        escalationThreshold: 0.45 // Higher bar = more likely to escalate
    )
}

/// Result of the agentic reasoning loop
struct AgenticResult: Sendable {
    let finalAnswer: String
    let steps: [ThinkingStep]
    let totalTokens: Int
    let totalDuration: TimeInterval
    let confidence: Float
    let sourcesUsed: Int
    /// All chunks retrieved across tool calls (for UnifiedMetricsBar)
    let retrievedChunks: [RetrievedChunk]

    /// Compressed summary of the reasoning chain (for UI display)
    var reasoningSummary: String {
        steps.map { "• \($0.type.rawValue): \($0.output.prefix(100))..." }.joined(separator: "\n")
    }
}

/// Retrieval-first agentic orchestrator
/// Key principle: Retrieve FIRST, then decide if escalation is needed based on results
@MainActor
final class AgenticOrchestrator: Sendable {
    private weak var ragService: RAGService?
    private let config: AgenticConfig

    init(ragService: RAGService, config: AgenticConfig = .defaultConfig) {
        self.ragService = ragService
        self.config = config
    }

    /// Execute a retrieval-first reasoning loop
    ///
    /// STRATEGY:
    /// 1. Initial retrieval with the ORIGINAL query (no decomposition)
    /// 2. EVALUATE results - are they good enough?
    /// 3. If yes → synthesize immediately
    /// 4. If no → escalate: reformulate query OR decompose for multi-faceted questions
    /// 5. Final synthesis with accumulated context
    func execute(
        query: String,
        initialContext: String = "",
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        let startTime = Date()
        var allRetrievedChunks: [RetrievedChunk] = []

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Initial Retrieval (with ORIGINAL query - no decomposition)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Agentic] Step 1: Initial retrieval with original query", category: .llm)

        let (initialSearchStep, initialChunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService
        )
        steps.append(initialSearchStep)
        totalTokens += initialSearchStep.tokensUsed
        allRetrievedChunks.append(contentsOf: initialChunks)
        await onStep?(initialSearchStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Evaluate Retrieval Quality
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let retrievalQuality = evaluateRetrievalQuality(chunks: initialChunks, query: query)
        Log.info("[Agentic] Retrieval quality: \(retrievalQuality.description)", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // DECISION POINT: Based on retrieval quality
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        switch retrievalQuality {
        case .excellent, .good:
            // HIGH CONFIDENCE: Go straight to synthesis
            Log.info("[Agentic] High confidence retrieval → direct synthesis", category: .llm)

            let synthesisStep = try await executeDirectSynthesis(
                query: query,
                searchResults: initialSearchStep.output,
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
                confidence: retrievalQuality.confidenceScore,
                sourcesUsed: initialChunks.count,
                retrievedChunks: allRetrievedChunks
            )

        case .moderate:
            // MEDIUM CONFIDENCE: Try query reformulation before decomposing
            Log.info("[Agentic] Moderate confidence → trying query reformulation", category: .llm)

            let reformulatedQuery = try await reformulateQuery(
                originalQuery: query,
                retrievedContext: initialSearchStep.output,
                ragService: ragService
            )

            if let reformulatedQuery = reformulatedQuery, reformulatedQuery != query {
                let reformulationStep = ThinkingStep(
                    id: UUID(),
                    type: .reformulating,
                    input: query,
                    output: "Reformulated: \(reformulatedQuery)",
                    tokensUsed: 20,
                    duration: 0.1,
                    timestamp: Date()
                )
                steps.append(reformulationStep)
                await onStep?(reformulationStep)

                // Search again with reformulated query
                let (reformulatedSearchStep, reformulatedChunks) = try await executeSearchStepWithChunks(
                    subQuery: reformulatedQuery,
                    ragService: ragService
                )
                steps.append(reformulatedSearchStep)
                totalTokens += reformulatedSearchStep.tokensUsed

                // Merge chunks (dedupe)
                for chunk in reformulatedChunks {
                    if !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                        allRetrievedChunks.append(chunk)
                    }
                }
                await onStep?(reformulatedSearchStep)

                // Re-evaluate
                let newQuality = evaluateRetrievalQuality(chunks: allRetrievedChunks, query: query)
                if newQuality.confidenceScore > retrievalQuality.confidenceScore {
                    Log.info("[Agentic] Reformulation improved results → synthesizing", category: .llm)

                    // Combine both search results
                    let combinedResults = initialSearchStep.output + "\n\n---\n\n" + reformulatedSearchStep.output

                    let synthesisStep = try await executeDirectSynthesis(
                        query: query,
                        searchResults: combinedResults,
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
                        confidence: newQuality.confidenceScore,
                        sourcesUsed: allRetrievedChunks.count,
                        retrievedChunks: allRetrievedChunks
                    )
                }
            }

            // Reformulation didn't help enough - fall through to decomposition
            fallthrough

        case .low:
            // LOW CONFIDENCE: Check if decomposition makes sense
            Log.info("[Agentic] Low confidence → checking if decomposition helps", category: .llm)

            // Only decompose if query has multi-faceted structure
            if queryBenefitsFromDecomposition(query) {
                return try await executeDecomposedPipeline(
                    query: query,
                    initialChunks: allRetrievedChunks,
                    initialSearchOutput: initialSearchStep.output,
                    steps: &steps,
                    totalTokens: &totalTokens,
                    ragService: ragService,
                    onStep: onStep,
                    startTime: startTime
                )
            } else {
                // Single-topic query with low results - be honest about it
                Log.info("[Agentic] Single-topic query, low confidence → honest synthesis", category: .llm)

                let synthesisStep = try await executeHonestSynthesis(
                    query: query,
                    searchResults: initialSearchStep.output,
                    confidence: retrievalQuality,
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
                    confidence: retrievalQuality.confidenceScore,
                    sourcesUsed: allRetrievedChunks.count,
                    retrievedChunks: allRetrievedChunks
                )
            }
        }
    }

    // MARK: - Retrieval Quality Evaluation

    private enum RetrievalQuality {
        case excellent // Top results > 0.5 similarity, good coverage
        case good // Top results > 0.35 similarity
        case moderate // Top results 0.2-0.35 similarity
        case low // Top results < 0.2 similarity or no results

        var confidenceScore: Float {
            switch self {
            case .excellent: return 0.9
            case .good: return 0.75
            case .moderate: return 0.5
            case .low: return 0.3
            }
        }

        var description: String {
            switch self {
            case .excellent: return "Excellent (>50% match)"
            case .good: return "Good (35-50% match)"
            case .moderate: return "Moderate (20-35% match)"
            case .low: return "Low (<20% match)"
            }
        }
    }

    /// Evaluate retrieval quality based on similarity scores and coverage
    private func evaluateRetrievalQuality(chunks: [RetrievedChunk], query: String) -> RetrievalQuality {
        guard !chunks.isEmpty else { return .low }

        let topScore = chunks.first?.similarityScore ?? 0
        let top3Avg = chunks.prefix(3).map { $0.similarityScore }.reduce(0, +) / Float(min(3, chunks.count))

        // Primary signal: top similarity score
        if topScore > 0.5 {
            return .excellent
        } else if topScore > 0.35 {
            return .good
        } else if topScore > 0.2 || top3Avg > 0.25 {
            return .moderate
        } else {
            return .low
        }
    }

    /// Check if a query would benefit from decomposition
    /// Only true for genuinely multi-faceted questions, not just low-confidence single-topic
    private func queryBenefitsFromDecomposition(_ query: String) -> Bool {
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

    /// Reformulate query based on what we found (or didn't find) in initial retrieval
    private func reformulateQuery(
        originalQuery: String,
        retrievedContext: String,
        ragService: RAGService
    ) async throws -> String? {
        let prompt = """
        The following search for a document returned limited results.

        Original query: \(originalQuery)

        Retrieved (partial): \(retrievedContext.prefix(500))

        Based on the terminology found in the retrieved content, suggest ONE alternative query that might find more relevant information. Use similar vocabulary to what appears in the documents. Output ONLY the new query, nothing else.
        """

        let response = try await ragService.generateWithFreshSession(prompt: prompt, maxTokens: 64)
        let reformulated = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's actually different and reasonable
        if reformulated.count > 10, reformulated.count < 200, reformulated != originalQuery {
            return reformulated
        }
        return nil
    }

    /// Direct synthesis when retrieval confidence is high
    private func executeDirectSynthesis(
        query: String,
        searchResults: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let prompt = """
        Answer the following question based on the search results provided.

        Question: \(query)

        Search Results:
        \(searchResults)

        Provide a clear, accurate answer. If citing specific information, reference the source.
        """

        let response = try await ragService.generateWithFreshSession(prompt: prompt, maxTokens: 1024)

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

    /// Honest synthesis when confidence is low - acknowledges limitations
    private func executeHonestSynthesis(
        query: String,
        searchResults: String,
        confidence: RetrievalQuality,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let prompt = """
        Answer the following question based on the search results. The search returned limited matches, so be clear about what you found and what's uncertain.

        Question: \(query)

        Search Results:
        \(searchResults)

        Provide the best answer you can based on available information. If the documents don't directly address the question, say so clearly rather than guessing.
        """

        let response = try await ragService.generateWithFreshSession(prompt: prompt, maxTokens: 1024)

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
    private func executeDecomposedPipeline(
        query: String,
        initialChunks: [RetrievedChunk],
        initialSearchOutput: String,
        steps: inout [ThinkingStep],
        totalTokens: inout Int,
        ragService: RAGService,
        onStep: ((ThinkingStep) async -> Void)?,
        startTime: Date
    ) async throws -> AgenticResult {
        var allRetrievedChunks = initialChunks

        // Planning step to decompose
        let planningStep = try await executePlanningStep(query: query, ragService: ragService)
        steps.append(planningStep)
        totalTokens += planningStep.tokensUsed
        await onStep?(planningStep)

        let subQueries = parseSubQueries(from: planningStep.output)

        // Execute sub-queries
        var searchResults: [(query: String, result: String)] = [(query, initialSearchOutput)]

        for subQuery in subQueries.prefix(config.maxSteps - 2) {
            

            guard totalTokens < config.maxTotalTokens else { break }

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: subQuery,
                ragService: ragService
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
        _ = compressSearchResults(searchResults) // Compressed for potential future use
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
            minSimilarity: 0.25
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

    /// Search step that also returns the raw chunks for UI display
    private func executeSearchStepWithChunks(subQuery: String, ragService: RAGService) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()

        // Get raw chunks for metrics bar - use higher topK for large documents
        let chunks = try await ragService.searchDocumentsRaw(query: subQuery, topK: 12, minSimilarity: 0.25)

        // Format for LLM consumption
        var searchResult = chunks.isEmpty
            ? "No relevant information found for: \(subQuery)"
            : "Found \(chunks.count) relevant chunks:\n\n"

        for (index, retrieved) in chunks.enumerated() {
            searchResult += "[\(index + 1)] From \(retrieved.sourceDocument)"
            if let page = retrieved.pageNumber {
                searchResult += " (Page \(page))"
            }
            searchResult += " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
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
            maxTokens: 1024
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

        // Compress all previous steps into a summary
        let stepSummary = steps.map { step in
            "\(step.type.rawValue): \(step.output.prefix(200))"
        }.joined(separator: "\n\n")

        let synthesisPrompt = """
        Synthesize a final, comprehensive answer from this research chain.

        Original Question: \(query)

        Research Steps:
        \(stepSummary)

        Provide a clear, well-structured final answer. Include specific citations where possible.
        """

        let response = try await ragService.generateWithFreshSession(
            prompt: synthesisPrompt,
            maxTokens: 1500
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
            let confidenceStr = text[range].replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces)
            return Float(confidenceStr) ?? 0.5
        }
        return 0.5 // Default confidence if not specified
    }

    private func countSources(in searchResult: String) -> Int {
        // Count citation patterns like [1], [Doc: X], etc.
        let pattern = #"\[(?:Doc:|Source:|\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        return regex?.numberOfMatches(in: searchResult, range: NSRange(searchResult.startIndex..., in: searchResult)) ?? 0
    }
}

// MARK: - Errors

enum AgenticError: LocalizedError {
    case serviceUnavailable
    case maxStepsExceeded
    case tokenLimitReached
    case planningFailed

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "RAG service unavailable"
        case .maxStepsExceeded:
            return "Maximum reasoning steps exceeded"
        case .tokenLimitReached:
            return "Token limit reached across sessions"
        case .planningFailed:
            return "Failed to decompose query into sub-questions"
        }
    }
}

// MARK: - RAGService Extension

extension RAGService {
    /// Generate with a fresh session (no accumulated context)
    /// Used by AgenticOrchestrator for each thinking step
    func generateWithFreshSession(prompt: String, maxTokens: Int) async throws -> LLMResponse {
        // This creates a new session, executes the prompt, and returns
        // The session is NOT stored, so it doesn't pollute the main conversation

        #if canImport(FoundationModels)
            // Create a temporary AppleFoundationLLMService instance
            let tempService = AppleFoundationLLMService()

            // Ensure cleanup on exit
            defer {
                tempService.resetSession(clearTools: true)
            }

            let config = InferenceConfig(
                maxTokens: maxTokens,
                temperature: 0.7,
                systemPrompt: "You are a focused research assistant. Be concise and precise."
            )

            return try await tempService.generate(
                prompt: prompt,
                context: nil,
                config: config
            )
        #else
            throw LLMError.modelUnavailable
        #endif
    }
}

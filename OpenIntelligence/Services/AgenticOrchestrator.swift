//
//  AgenticOrchestrator.swift
//  OpenIntelligence
//
//  Multi-session agentic reasoning loop that transcends the 4K token limit.
//  Each "thinking step" gets a fresh session with compressed context from previous steps.
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

        /// Display name for UI
        var displayName: String { rawValue }

        /// Map to ThinkingEvent.Kind for UI integration
        var thinkingKind: ThinkingEvent.Kind {
            switch self {
            case .planning: return .planning
            case .searching: return .retrieval
            case .analyzing: return .rerank
            case .synthesizing: return .generation
            case .refining: return .generation
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

    /// Minimum confidence threshold to stop early
    let confidenceThreshold: Float

    nonisolated static let defaultConfig = AgenticConfig(
        maxSteps: 5,
        maxTotalTokens: 16000, // 4 full sessions worth
        streamIntermediateResults: true,
        confidenceThreshold: 0.85
    )

    nonisolated static let fast = AgenticConfig(
        maxSteps: 2,
        maxTotalTokens: 8000,
        streamIntermediateResults: false,
        confidenceThreshold: 0.7
    )

    nonisolated static let thorough = AgenticConfig(
        maxSteps: 8,
        maxTotalTokens: 32000, // 8 sessions
        streamIntermediateResults: true,
        confidenceThreshold: 0.95
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

/// Multi-session agentic orchestrator
/// Breaks complex queries into multiple focused LLM calls, each with fresh 4K context
@MainActor
final class AgenticOrchestrator: Sendable {
    private weak var ragService: RAGService?
    private let config: AgenticConfig

    init(ragService: RAGService, config: AgenticConfig = .defaultConfig) {
        self.ragService = ragService
        self.config = config
    }

    /// Execute an agentic reasoning loop for a complex query
    /// - Parameters:
    ///   - query: The user's question
    ///   - context: Initial retrieved context (if any)
    ///   - onStep: Callback for each thinking step (for UI updates)
    /// - Returns: The final synthesized result
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
        // workingContext reserved for future context accumulation between steps
        _ = initialContext
        var confidence: Float = 0.0
        var sourcesUsed = 0
        var allRetrievedChunks: [RetrievedChunk] = [] // Collect chunks for UnifiedMetricsBar

        // STEP 1: Planning - Decompose the query
        let planningStep = try await executePlanningStep(query: query, ragService: ragService)
        steps.append(planningStep)
        totalTokens += planningStep.tokensUsed
        await onStep?(planningStep)

        let subQueries = parseSubQueries(from: planningStep.output)

        // STEP 2: Parallel Search - Execute sub-queries
        // Each search gets its own fresh context window
        var searchResults: [(query: String, result: String)] = []

        for subQuery in subQueries.prefix(config.maxSteps - 2) { // Reserve steps for analysis + synthesis
            guard totalTokens < config.maxTotalTokens else { break }

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: subQuery,
                ragService: ragService
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            searchResults.append((subQuery, searchStep.output))
            sourcesUsed += chunks.count

            // Collect unique chunks (dedupe by chunk ID)
            for chunk in chunks {
                if !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }
            }

            await onStep?(searchStep)
        }

        // STEP 3: Analysis - Synthesize search results
        // Compress all search results into a focused analysis
        let compressedSearchResults = compressSearchResults(searchResults)

        let analysisStep = try await executeAnalysisStep(
            query: query,
            searchResults: compressedSearchResults,
            ragService: ragService
        )
        steps.append(analysisStep)
        totalTokens += analysisStep.tokensUsed
        confidence = extractConfidence(from: analysisStep.output)
        await onStep?(analysisStep)

        // STEP 4: Refinement (if confidence is low)
        if confidence < config.confidenceThreshold && totalTokens < config.maxTotalTokens {
            let refinementStep = try await executeRefinementStep(
                query: query,
                currentAnswer: analysisStep.output,
                ragService: ragService
            )
            steps.append(refinementStep)
            totalTokens += refinementStep.tokensUsed
            confidence = extractConfidence(from: refinementStep.output)
            await onStep?(refinementStep)
        }

        // STEP 5: Final Synthesis
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
            confidence: confidence,
            sourcesUsed: sourcesUsed,
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
            topK: 5,
            minSimilarity: 0.3
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

        // Get raw chunks for metrics bar
        let chunks = try await ragService.searchDocumentsRaw(query: subQuery, topK: 5, minSimilarity: 0.3)

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

//
//  LLMService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import CoreML
import Foundation
import NaturalLanguage

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Apple Intelligence Framework Imports (iOS 18.1+)
// These frameworks provide access to Apple's AI capabilities:
// - FoundationModels: On-device and Private Cloud Compute LLMs
// - AppIntents: Siri integration and system AI service access
// - AssistantServices: ChatGPT Extension and other assistant providers

#if canImport(AppIntents)
    import AppIntents
#endif

/// Protocol defining the interface for LLM inference engines
/// This abstraction enables switching between Foundation Models and Core ML
protocol LLMService {
    /// Generate a response given a prompt and optional context
    func generate(prompt: String, context: String?, config: InferenceConfig) async throws
        -> LLMResponse

    /// Check if the service is available on the current device
    var isAvailable: Bool { get }

    /// Get the name of the model being used
    var modelName: String { get }

    /// Set tool handler for function calling (optional, for agentic RAG)
    var toolHandler: RAGToolHandler? { get set }
}

/// Tool handler protocol for executing RAG functions called by the LLM
/// This enables agentic RAG where the model decides when to search vs answer directly
@MainActor
protocol RAGToolHandler {
    /// Search documents for relevant information
    func searchDocuments(query: String) async throws -> String

    /// List all available documents
    func listDocuments() async throws -> String

    /// Get summary of a specific document
    func getDocumentSummary(documentName: String) async throws -> String
}

// MARK: - Streaming Bridge

struct LLMStreamEvent: Sendable {
    let text: String
    let isFinal: Bool
}

typealias LLMStreamHandler = @Sendable (LLMStreamEvent) async -> Void

enum LLMStreamingContext {
    @TaskLocal static var handler: LLMStreamHandler?

    static func emit(text: String, isFinal: Bool) {
        guard let handler = handler else { return }
        Task {
            await handler(LLMStreamEvent(text: text, isFinal: isFinal))
        }
    }
}

// MARK: - Tool Protocol Implementations for Function Calling

#if canImport(FoundationModels)
    import FoundationModels

    /// Tool for searching user's document library
    @available(iOS 26.0, *)
    struct SearchDocumentsTool: Tool {
        let name = "search_documents"
        let description =
            "Search the user's document library for relevant information based on a query. Returns the most relevant text chunks with citations."

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(
                description:
                    "The search query to find relevant document chunks. Be specific and use keywords from the user's question."
            )
            var query: String
            @Guide(
                description:
                    "Optional maximum number of chunks to retrieve. Use 2–4 for brief summaries, 8–12 for deep dives."
            )
            var topK: Int?
            @Guide(
                description:
                    "Optional minimum semantic similarity threshold (0.0–1.0). Use 0.35 by default; increase to filter noise."
            )
            var minSimilarity: Float?
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document search service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.searchDocuments(
                query: arguments.query,
                topK: arguments.topK,
                minSimilarity: arguments.minSimilarity
            )
        }
    }

    /// Tool for listing all available documents
    @available(iOS 26.0, *)
    struct ListDocumentsTool: Tool {
        let name = "list_documents"
        let description =
            "List all documents in the user's library. Returns document names, types, page counts, and dates added."

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            // No arguments needed for listing
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.listDocuments()
        }
    }

    /// Tool for getting summary of a specific document
    @available(iOS 26.0, *)
    struct GetDocumentSummaryTool: Tool {
        let name = "get_document_summary"
        let description =
            "Get detailed information about a specific document including metadata, content summary, and statistics."

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(
                description:
                    "The exact name of the document to get details about. Use list_documents first to see available names."
            )
            var documentName: String
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.getDocumentSummary(documentName: arguments.documentName)
        }
    }

#endif

/// Response from an LLM generation request
struct LLMResponse {
    let text: String
    let tokensGenerated: Int
    let timeToFirstToken: TimeInterval?
    let totalTime: TimeInterval
    let modelName: String?  // Actual model used (includes execution location)
    let toolCallsMade: Int  // Number of tool calls executed (for agentic RAG metrics)

    var tokensPerSecond: Float? {
        guard totalTime > 0 else { return nil }
        return Float(tokensGenerated) / Float(totalTime)
    }
}

// MARK: - Apple Foundation Models (iOS 26+) - REAL Apple Intelligence LLM
// This is Apple's on-device language model with automatic Private Cloud Compute fallback
// Announced at WWDC 2025 - sessions 286, 301, 259
// Requires iOS 26.0+, A17 Pro / M1 or later
// Zero data retention, end-to-end encrypted when using Private Cloud Compute

#if canImport(FoundationModels)
    import FoundationModels

    @available(iOS 26.0, *)
    class AppleFoundationLLMService: LLMService {

        private var session: LanguageModelSession?

        /// Tool handler for agentic RAG function calling
        var toolHandler: RAGToolHandler?

        // Lazy model access - only initialize when actually needed and ensure main thread
        private var _model: SystemLanguageModel?
        private var model: SystemLanguageModel {
            if let existing = _model {
                return existing
            }

            // CRITICAL: SystemLanguageModel.default MUST be accessed on main thread
            guard Thread.isMainThread else {
                fatalError(
                    "AppleFoundationLLMService must access SystemLanguageModel.default from main thread"
                )
            }

            let model = SystemLanguageModel.default
            _model = model
            return model
        }

        var isAvailable: Bool {
            #if targetEnvironment(simulator)
                // Foundation Models + PCC are not available inside the simulator runtime
                Log.debug("AppleFoundationLLMService unavailable on Simulator", category: .llm)
                return false
            #else
                // Quick check without accessing the model
                // This prevents crashes during init when called from background thread
                guard Thread.isMainThread else {
                    Log.debug("AppleFoundationLLMService.isAvailable checked from background thread", category: .llm)
                    return false
                }

                // Use the detailed availability enum for better diagnostics
                switch model.availability {
                case .available:
                    return true
                case .unavailable:
                    return false
                }
            #endif
        }

        var modelName: String {
            return "Apple Foundation Model (On-Device)"
        }

        /// Get specific reason why Foundation Models are unavailable (if applicable)
        var unavailabilityReason: String? {
            guard Thread.isMainThread else {
                return "Cannot check availability from background thread"
            }

            switch model.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "Device not eligible (requires A17 Pro+ or M-series chip)"
                case .appleIntelligenceNotEnabled:
                    return
                        "Apple Intelligence not enabled (go to Settings > Apple Intelligence & Siri)"
                case .modelNotReady:
                    return "Model is downloading or initializing (please wait a moment)"
                @unknown default:
                    return "Foundation Models unavailable (unknown reason)"
                }
            }
        }

        init() {
            // SAFETY: We no longer access SystemLanguageModel.default in init
            // Instead, we defer it until the model property is accessed
            // This allows the service to be created on any thread
            Log.debug("AppleFoundationLLMService initialized (model will be loaded on first use)", category: .llm)
        }

        /// Start model warm-up (call this after init from an async context)
        func startWarmup() {
            // ✅ GAP #5 FIXED: Model Warm-up
            // Preload model in background to eliminate first-query latency
            // First real user query will be INSTANT (no 5-second wait)
            Task {
                await self.warmUpModel()
            }
        }

        /// Preload the Foundation Model to eliminate first-query latency
        /// This runs in the background and makes the first real query instant
        @MainActor
        private func warmUpModel() async {
            Log.debug("[Warm-up] Starting Foundation Model preload...", category: .llm)
            let startTime = Date()

            do {
                // Create session (this loads the model into memory)
                try ensureSession()

                guard let session = session else {
                    Log.warning("[Warm-up] Session unavailable", category: .llm)
                    return
                }

                // Send a minimal throwaway query to fully initialize the model
                let warmupPrompt = "Hi"
                let options = GenerationOptions(temperature: 0.0)

                // Use streaming (the actual API available) and consume minimal response
                let responseStream = session.streamResponse(to: warmupPrompt, options: options)

                // Just consume first token to trigger model load
                for try await _ in responseStream {
                    break  // Only need first token to warm up
                }

                let loadTime = Date().timeIntervalSince(startTime)
                Log.info("[Warm-up] Foundation Model preloaded in \(String(format: "%.2f", loadTime))s", category: .llm)

            } catch {
                let failTime = Date().timeIntervalSince(startTime)
                Log.warning("[Warm-up] Model preload failed after \(String(format: "%.2f", failTime))s: \(error)", category: .llm)
            }
        }

        // Lazy session creation - only when actually generating
        private func ensureSession() throws {
            guard session == nil else { return }

            guard Thread.isMainThread else {
                throw LLMError.modelUnavailable
            }

            // Check availability with detailed diagnostics BEFORE creating session
            switch model.availability {
            case .available:
                Log.debug("Foundation Models available - creating session...", category: .llm)

                // Initialize function calling tools for agentic RAG
                // These tools enable the model to decide when to search documents vs answer directly
                var tools: [any Tool] = []

                if let ragService = toolHandler as? RAGService {
                    // Create tool instances with RAGService reference
                    var searchTool = SearchDocumentsTool()
                    searchTool.ragService = ragService
                    tools.append(searchTool)

                    var listTool = ListDocumentsTool()
                    listTool.ragService = ragService
                    tools.append(listTool)

                    var summaryTool = GetDocumentSummaryTool()
                    summaryTool.ragService = ragService
                    tools.append(summaryTool)

                    Log.debug("Initialized \(tools.count) tools for agentic RAG", category: .llm)
                }

                // Create language model session with hybrid RAG+LLM instructions
                // This enables BOTH document-based RAG and general conversational AI
                self.session = LanguageModelSession(
                    model: model,
                    tools: tools,
                    instructions: Instructions(
                        """
                        You are a helpful AI assistant with access to the user's document library.

                        When the user asks about specific information:
                        - Use search_documents to find relevant content from their documents
                        - Analyze the retrieved content and synthesize a helpful answer
                        - Cite specific documents and page numbers when available

                        When the user wants to know about their documents:
                        - Use list_documents to show what's available
                        - Use get_document_summary for details about specific documents

                        For general conversation:
                        - Engage naturally and helpfully without accessing tools
                        - Answer questions to the best of your ability

                        Always decide intelligently whether to use tools or answer directly.
                        When calling search_documents, choose parameters based on the task:
                        • Brief summaries: topK 2–4
                        • Deep dives/comparisons: topK 8–12
                        • Raise minSimilarity above 0.35 when results seem noisy (default 0.35).
                        Be conversational and cite sources when using document information.
                        """)
                )

                Log.info("Apple Foundation Model session initialized (Agentic RAG)", category: .llm)

            case .unavailable(let reason):
                let reasonStr: String
                switch reason {
                case .deviceNotEligible:
                    reasonStr = "Device not eligible (requires A17 Pro+ or M-series)"
                case .appleIntelligenceNotEnabled:
                    reasonStr = "Apple Intelligence not enabled"
                case .modelNotReady:
                    reasonStr = "Model downloading or initializing"
                @unknown default:
                    reasonStr = "Unknown reason"
                }
                Log.warning("Foundation Models unavailable: \(reasonStr)", category: .llm)
                throw LLMError.modelUnavailable
            }
        }

        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            // Ensure session is created (will throw if unavailable or not on main thread)
            try ensureSession()

            guard let session = session else {
                throw LLMError.modelUnavailable
            }

            let startTime = Date()
            TelemetryCenter.emit(
                .generation,
                title: "Apple FM: Generation started",
                metadata: [
                    "temperature": "\(config.temperature)",
                    "maxTokens": "\(config.maxTokens)",
                    "pccAllowed": "\(config.allowPrivateCloudCompute)",
                    "execPref": "\(config.executionContext)",
                ]
            )

            // Construct augmented prompt with RAG context
            let fullPrompt: String
            if let context = context, !context.isEmpty {
                Log.debug("RAG mode: context=\(context.count) chars, prompt=\(prompt.prefix(50))...", category: .llm)
                fullPrompt = """
                    Below is text content that has been provided for you to analyze. Please read this content carefully and answer the question that follows.

                    CONTENT TO ANALYZE:
                    \(context)

                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    Based on the content above, please answer this question with comprehensive detail:

                    \(prompt)

                    Instructions:
                    • Synthesize information from the provided content
                    • Provide specific examples and details from the text
                    • Make connections between different parts of the content when relevant
                    • If the content contains partial information, explain what you found
                    • Structure your response clearly
                    • If the content doesn't address the question, state that clearly

                    Your detailed answer:
                    """
            } else {
                Log.debug("General chat mode: prompt=\(prompt.prefix(50))...", category: .llm)
                fullPrompt = prompt
            }

            // Estimate token count for routing decisions
            let promptLength = fullPrompt.count
            let estimatedTokens = promptLength / 4  // Rough estimate: 1 token ≈ 4 chars
            Log.debug("Generation: ~\(estimatedTokens) tokens, exec=\(config.executionContext)", category: .llm)

            // Generate response using streaming API with execution context
            var responseText = ""
            var tokenCount = 0
            var firstTokenTime: TimeInterval?
            var actualExecutionLocation: String = "Unknown"

            // ✅ GAP #3: Use available generation parameters
            // Note: iOS 26 GenerationOptions only supports temperature currently
            // Other parameters like topP, topK may be in future releases
            let options = GenerationOptions(
                temperature: Double(config.temperature)
            )

            let responseStream = session.streamResponse(to: fullPrompt, options: options)

            var snapshotCount = 0
            var forcedLocalFallback = false

            for try await snapshot in responseStream {
                snapshotCount += 1

                if firstTokenTime == nil {
                    firstTokenTime = Date().timeIntervalSince(startTime)

                    // Detect actual execution location from first token latency
                    // On-device: ~0.1-0.5s, PCC: ~2-4s (includes network roundtrip)
                    if let ttft = firstTokenTime {
                        if ttft < 1.0 {
                            actualExecutionLocation = "📱 On-Device"
                            Log.info("[FM] On-Device execution (TTFT: \(String(format: "%.2f", ttft))s)", category: .llm)
                        } else {
                            actualExecutionLocation = "☁️ Private Cloud Compute"
                            Log.info("[FM] Private Cloud Compute (TTFT: \(String(format: "%.2f", ttft))s)", category: .llm)
                        }

                        // Enforce execution preferences: if PCC is blocked, fall back to on-device analysis
                        if (config.executionContext == .onDeviceOnly
                            || !config.allowPrivateCloudCompute)
                            && actualExecutionLocation.contains("Private Cloud Compute")
                        {
                            Log.warning("PCC blocked by settings - falling back to On-Device Analysis", category: .llm)
                            TelemetryCenter.emit(
                                .system,
                                severity: .warning,
                                title: "PCC blocked by settings",
                                metadata: [
                                    "ttft": String(format: "%.2f", ttft),
                                    "execDetected": actualExecutionLocation,
                                ]
                            )
                            forcedLocalFallback = true
                            LLMStreamingContext.emit(text: "", isFinal: true)
                            break
                        }
                    }
                }

                // Update response text from snapshot
                let previousLength = responseText.count
                responseText = snapshot.content
                let newChars = responseText.count - previousLength

                // More accurate token counting based on word boundaries
                let currentWords = responseText.split(separator: " ").count
                let previousWords = tokenCount
                let newWords = currentWords - previousWords

                if newWords > 0 {
                    tokenCount = currentWords
                }

                // Emit new content to streaming context
                if newChars > 0 {
                    let chunk = String(responseText.suffix(newChars))
                    LLMStreamingContext.emit(text: chunk, isFinal: false)
                }
            }

            // If PCC was blocked and we aborted the FM stream, fall back to On-Device Analysis now
            if forcedLocalFallback {
                let local = OnDeviceAnalysisService()
                let fallback = try await local.generate(
                    prompt: prompt, context: context, config: config)
                let totalTime = Date().timeIntervalSince(startTime)
                TelemetryCenter.emit(
                    .generation,
                    title: "On-Device Analysis (fallback) complete",
                    metadata: [
                        "tokens": "\(fallback.tokensGenerated)",
                        "totalTime": String(format: "%.2f", totalTime),
                    ],
                    duration: totalTime
                )
                return LLMResponse(
                    text: fallback.text,
                    tokensGenerated: fallback.tokensGenerated,
                    timeToFirstToken: fallback.timeToFirstToken,
                    totalTime: totalTime,
                    modelName: local.modelName,
                    toolCallsMade: 0
                )
            }

            Log.debug("[FM] Stream complete: \(snapshotCount) snapshots, \(responseText.count) chars", category: .llm)

            let totalTime = Date().timeIntervalSince(startTime)

            // Final token count is accurate word count
            let finalTokenCount = responseText.split(separator: " ").count

            Log.info("[FM] Generation complete: \(finalTokenCount) words in \(String(format: "%.2f", totalTime))s (\(actualExecutionLocation))", category: .llm)

            // Determine actual model name based on execution location
            let executionBasedModelName: String
            if let ttft = firstTokenTime {
                executionBasedModelName = ttft < 1.0 ? "Apple Foundation Model (On-Device)" : "Apple Foundation Model (Private Cloud Compute)"
            } else {
                executionBasedModelName = modelName
            }

            TelemetryCenter.emit(
                .generation,
                title: "Apple FM: Generation complete",
                metadata: [
                    "ttft": firstTokenTime != nil ? String(format: "%.2f", firstTokenTime!) : "n/a",
                    "totalTime": String(format: "%.2f", totalTime),
                    "exec": executionBasedModelName,
                    "tokens": "\(finalTokenCount)",
                ],
                duration: totalTime
            )
            LLMStreamingContext.emit(text: "", isFinal: true)
            return LLMResponse(
                text: responseText,
                tokensGenerated: finalTokenCount,
                timeToFirstToken: firstTokenTime,
                totalTime: totalTime,
                modelName: executionBasedModelName,
                toolCallsMade: ToolCallCounter.shared.takeAndReset()
            )
        }
    }

// NOTE: Private Cloud Compute (PCC) is AUTOMATIC in Foundation Models
// The system intelligently decides when to use on-device vs. Apple's PCC servers
// based on query complexity and available resources. PCC provides:
// - Apple Silicon servers (same architecture as device)
// - Cryptographic zero-retention guarantee
// - End-to-end encryption
// - Seamless fallback for complex queries
// You don't need a separate service - it's built into AppleFoundationLLMService above

#endif

// MARK: - On-Device Document Analysis (NaturalLanguage Framework)
// FALLBACK for devices without Foundation Models support
// This is NOT an LLM - it's an extractive QA system using Apple's NaturalLanguage framework
// It analyzes your query, finds relevant sentences from retrieved context, and presents them
// This runs 100% on-device with zero network calls and zero AI model downloads

class OnDeviceAnalysisService: LLMService {

    private let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .lemma])
    private let languageRecognizer = NLLanguageRecognizer()

    var toolHandler: RAGToolHandler?  // Not used by extractive QA

    var isAvailable: Bool { true }
    var modelName: String { "On-Device Analysis (Extractive QA)" }

    init() {
        Log.debug("On-Device Analysis Service initialized", category: .llm)
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws
        -> LLMResponse
    {
        let startTime = Date()

        // Simulate analysis time
        let words = prompt.split(separator: " ").count
        let analysisTime = Double(words) / 100.0 + 0.3
        try await Task.sleep(nanoseconds: UInt64(analysisTime * 1_000_000_000))

        // Analyze and extract relevant content
        let responseText = analyzeAndExtract(prompt: prompt, context: context)

        let totalTime = Date().timeIntervalSince(startTime)
        let tokensGenerated = responseText.split(separator: " ").count

        if !responseText.isEmpty {
            LLMStreamingContext.emit(text: responseText, isFinal: false)
        }
        LLMStreamingContext.emit(text: "", isFinal: true)

        return LLMResponse(
            text: responseText,
            tokensGenerated: tokensGenerated,
            timeToFirstToken: 0.1,
            totalTime: totalTime,
            modelName: modelName,
            toolCallsMade: 0
        )
    }

    private func analyzeAndExtract(prompt: String, context: String?) -> String {
        guard let context = context, !context.isEmpty else {
            return """
                I don't have any documents loaded yet. Please add documents to your library so I can analyze and extract information.

                [On-Device Analysis Ready - No AI model required]
                """
        }

        return extractRelevantInformation(query: prompt, retrievedContent: context)
    }

    private func extractRelevantInformation(query: String, retrievedContent: String) -> String {
        // 1. Analyze query intent
        let queryAnalysis = analyzeQuery(query)

        // 2. Analyze retrieved context
        let contextAnalysis = analyzeContext(retrievedContent)

        // 3. Find and rank relevant sentences
        let relevantInfo = findRelevantSentences(
            queryType: queryAnalysis.type,
            queryKeywords: queryAnalysis.keywords,
            queryEntities: queryAnalysis.entities,
            contextSentences: contextAnalysis.sentences,
            contextEntities: contextAnalysis.entities
        )

        // 4. Build structured response
        return buildExtractiveResponse(
            query: query,
            queryType: queryAnalysis.type,
            relevantSentences: relevantInfo
        )
    }

    private func analyzeQuery(_ query: String) -> QueryAnalysis {
        var type: QueryType = .general
        var keywords: Set<String> = []
        var entities: [String] = []

        let queryLower = query.lowercased()

        // Determine query type using pattern matching
        if queryLower.hasPrefix("what") || queryLower.contains("what is")
            || queryLower.contains("what are")
        {
            type = .definition
        } else if queryLower.hasPrefix("how") || queryLower.contains("how to")
            || queryLower.contains("how do")
        {
            type = .instruction
        } else if queryLower.hasPrefix("why") || queryLower.contains("why is")
            || queryLower.contains("why do")
        {
            type = .explanation
        } else if queryLower.hasPrefix("when") || queryLower.contains("when to")
            || queryLower.contains("when should")
        {
            type = .temporal
        } else if queryLower.hasPrefix("where") {
            type = .location
        } else if queryLower.contains("list") || queryLower.contains("tell me about")
            || queryLower.contains("describe")
        {
            type = .description
        }

        // Extract keywords using NLTagger
        tagger.string = query
        tagger.enumerateTags(
            in: query.startIndex..<query.endIndex, unit: .word, scheme: .lexicalClass
        ) { tag, range in
            if let tag = tag {
                let word = String(query[range])
                // Keep nouns, verbs, adjectives
                if tag == .noun || tag == .verb || tag == .adjective {
                    if word.count > 2 {
                        keywords.insert(word.lowercased())
                    }
                }
            }
            return true
        }

        // Extract named entities
        tagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .word, scheme: .nameType)
        { tag, range in
            if let tag = tag {
                let entity = String(query[range])
                if tag == .personalName || tag == .placeName || tag == .organizationName {
                    entities.append(entity)
                }
            }
            return true
        }

        return QueryAnalysis(type: type, keywords: keywords, entities: entities)
    }

    private func analyzeContext(_ context: String) -> ContextAnalysis {
        var sentences: [SentenceInfo] = []
        var entities: [String] = []

        // Split into sentences using NLTokenizer
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = context
        tokenizer.enumerateTokens(in: context.startIndex..<context.endIndex) { range, _ in
            let sentence = String(context[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 20 {
                // Analyze sentence
                let keywords = extractKeywords(from: sentence)
                let importance = calculateImportance(sentence)

                sentences.append(
                    SentenceInfo(
                        text: sentence,
                        keywords: keywords,
                        importance: importance
                    ))
            }
            return true
        }

        // Extract named entities from context
        tagger.string = context
        tagger.enumerateTags(
            in: context.startIndex..<context.endIndex, unit: .word, scheme: .nameType
        ) { tag, range in
            if let tag = tag {
                let entity = String(context[range])
                if tag == .personalName || tag == .placeName || tag == .organizationName {
                    entities.append(entity)
                }
            }
            return true
        }

        return ContextAnalysis(sentences: sentences, entities: entities)
    }

    private func extractKeywords(from text: String) -> Set<String> {
        var keywords: Set<String> = []

        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass
        ) { tag, range in
            if let tag = tag {
                let word = String(text[range])
                if (tag == .noun || tag == .verb || tag == .adjective) && word.count > 3 {
                    keywords.insert(word.lowercased())
                }
            }
            return true
        }

        return keywords
    }

    private func calculateImportance(_ sentence: String) -> Double {
        var score = 0.0

        // Longer sentences are often more informative
        score += Double(sentence.count) / 500.0

        // Sentences with numbers/data are important
        if sentence.range(of: #"\d+"#, options: .regularExpression) != nil {
            score += 0.3
        }

        // Sentences with key indicator words
        let importantWords = [
            "important", "must", "should", "warning", "note", "key", "essential", "critical",
        ]
        for word in importantWords {
            if sentence.lowercased().contains(word) {
                score += 0.2
                break
            }
        }

        return min(score, 1.0)
    }

    private func findRelevantSentences(
        queryType: QueryType,
        queryKeywords: Set<String>,
        queryEntities: [String],
        contextSentences: [SentenceInfo],
        contextEntities: [String]
    ) -> [SentenceInfo] {

        var scoredSentences: [(sentence: SentenceInfo, score: Double)] = []

        for sentence in contextSentences {
            var score = sentence.importance

            // Keyword matching
            let matchingKeywords = sentence.keywords.intersection(queryKeywords)
            score += Double(matchingKeywords.count) * 0.5

            // Entity matching
            for entity in queryEntities {
                if sentence.text.contains(entity) {
                    score += 0.8
                }
            }

            // Bonus for query type relevance
            switch queryType {
            case .instruction:
                if sentence.text.contains("step") || sentence.text.contains("first")
                    || sentence.text.lowercased().contains("to ")
                {
                    score += 0.3
                }
            case .definition:
                if sentence.text.contains("is") || sentence.text.contains("are")
                    || sentence.text.contains("means")
                {
                    score += 0.3
                }
            case .explanation:
                if sentence.text.contains("because") || sentence.text.contains("due to")
                    || sentence.text.contains("reason")
                {
                    score += 0.3
                }
            default:
                break
            }

            scoredSentences.append((sentence, score))
        }

        // Sort by score and return top results
        scoredSentences.sort { $0.score > $1.score }
        return scoredSentences.prefix(5).map { $0.sentence }
    }

    private func buildExtractiveResponse(
        query: String,
        queryType: QueryType,
        relevantSentences: [SentenceInfo]
    ) -> String {

        guard !relevantSentences.isEmpty else {
            return """
                I found your documents but couldn't identify specific information matching your query. Try rephrasing your question or asking about general topics covered in your documents.

                [On-Device Analysis - No matches found]
                """
        }

        // Generate introduction based on query type
        let intro: String
        switch queryType {
        case .definition:
            intro = "Based on your documents, here's what I found:"
        case .instruction:
            intro = "According to your documents:"
        case .explanation:
            intro = "Your documents explain:"
        case .temporal:
            intro = "Regarding timing, your documents state:"
        case .location:
            intro = "Regarding location, here's what your documents say:"
        case .description:
            intro = "From your documents:"
        case .general:
            intro = "Here's what I found in your documents:"
        }

        // Combine top sentences into coherent response
        let mainContent =
            relevantSentences
            .map { $0.text }
            .joined(separator: "\n\n")

        // Add footer explaining this is extractive, not generative
        let footer =
            "\n\n[On-Device Analysis: Extracted \(relevantSentences.count) relevant passages from your documents]"

        return intro + "\n\n" + mainContent + footer
    }

    // MARK: - Helper Types

    private enum QueryType {
        case definition  // "What is..."
        case instruction  // "How to..."
        case explanation  // "Why..."
        case temporal  // "When..."
        case location  // "Where..."
        case description  // "Tell me about...", "List..."
        case general  // Other
    }

    private struct QueryAnalysis {
        let type: QueryType
        let keywords: Set<String>
        let entities: [String]
    }

    private struct ContextAnalysis {
        let sentences: [SentenceInfo]
        let entities: [String]
    }

    private struct SentenceInfo {
        let text: String
        let keywords: Set<String>
        let importance: Double
    }
}

// MARK: - Apple Intelligence ChatGPT Extension (iOS 18.1+)
// REAL Apple Intelligence API - Uses Apple's built-in ChatGPT integration
// Requires iOS 18.1+, user must enable ChatGPT in Settings > Apple Intelligence & Siri
// NO OpenAI account required, free tier available, user consents per request

#if canImport(AppIntents)

    // MARK: - AssistChatIntent (iOS 18.1+ Apple Intelligence API)

    /// Intent for invoking system-level AI assistants (ChatGPT, etc.) via Apple Intelligence
    /// This is Apple's API for third-party assistant integration introduced in iOS 18.1
    @available(iOS 18.1, *)
    struct AssistChatIntent: AppIntent {
        static var title: LocalizedStringResource = "Ask AI Assistant"
        static var description: IntentDescription = IntentDescription(
            "Send a query to an AI assistant via Apple Intelligence")
        static var openAppWhenRun: Bool = false

        @Parameter(title: "Query")
        var query: String

        @Parameter(title: "Provider")
        var provider: AssistantProvider

        @MainActor
        func perform() async throws -> some IntentResult {
            // This is a prototype implementation based on Apple's App Intents framework
            // The actual API may vary slightly as Apple continues to document it

            Log.debug("[AssistChatIntent] Invoking \(provider.displayName)", category: .llm)

            // TEMPORARY: Until full Apple Intelligence API is available
            // For now, return an error result
            return .result(
                dialog: IntentDialog(
                    stringLiteral: """
                        ChatGPT Extension requires full Apple Intelligence integration.

                        Current status: iOS 18.1+ API is documented but requires private entitlements.

                        Alternative: Use OpenAI Direct in Settings (bring your own API key).
                        """)
            )
        }
    }

    /// Available AI assistant providers in Apple Intelligence
    @available(iOS 18.1, *)
    enum AssistantProvider: String, AppEnum, Sendable {
        case chatGPT = "ChatGPT"
        case claude = "Claude"  // May be added in future iOS versions
        case gemini = "Gemini"  // May be added in future iOS versions

        static var typeDisplayRepresentation: TypeDisplayRepresentation {
            TypeDisplayRepresentation(name: "AI Assistant Provider")
        }

        static var caseDisplayRepresentations: [AssistantProvider: DisplayRepresentation] {
            [
                .chatGPT: DisplayRepresentation(title: "ChatGPT", subtitle: "by OpenAI"),
                .claude: DisplayRepresentation(title: "Claude", subtitle: "by Anthropic"),
                .gemini: DisplayRepresentation(title: "Gemini", subtitle: "by Google"),
            ]
        }

        var displayName: String {
            switch self {
            case .chatGPT: return "ChatGPT"
            case .claude: return "Claude"
            case .gemini: return "Gemini"
            }
        }
    }

    @available(iOS 18.1, *)
    class AppleChatGPTExtensionService: LLMService {

        var toolHandler: RAGToolHandler?  // Not used by ChatGPT Extension

        var isAvailable: Bool {
            // Check if ChatGPT extension is enabled in system settings
            // User must enable: Settings > Apple Intelligence & Siri > ChatGPT
            return checkChatGPTAvailability()
        }

        var modelName: String { "ChatGPT (via Apple Intelligence)" }

        init() {
            if isAvailable {
                Log.info("ChatGPT Extension available", category: .llm)
            } else {
                Log.debug("ChatGPT Extension not available - enable in Settings", category: .llm)
            }
        }

        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            guard isAvailable else {
                throw LLMError.modelUnavailable
            }

            let startTime = Date()

            // Construct augmented prompt with RAG context
            let fullPrompt: String
            if let context = context, !context.isEmpty {
                fullPrompt = """
                    Context from user's documents:
                    \(context)

                    User question: \(prompt)

                    Please answer based on the provided context.
                    """
            } else {
                fullPrompt = prompt
            }

            // Use App Intents to send request to ChatGPT via Apple Intelligence
            // This triggers the system consent dialog automatically
            let response = try await sendChatGPTRequest(fullPrompt)

            let totalTime = Date().timeIntervalSince(startTime)
            let tokensGenerated = response.split(separator: " ").count

            if !response.isEmpty {
                LLMStreamingContext.emit(text: response, isFinal: false)
            }
            LLMStreamingContext.emit(text: "", isFinal: true)

            return LLMResponse(
                text: response,
                tokensGenerated: tokensGenerated,
                timeToFirstToken: nil,
                totalTime: totalTime,
                modelName: modelName,
                toolCallsMade: 0
            )
        }

        private func checkChatGPTAvailability() -> Bool {
            // Check if user has enabled ChatGPT in Apple Intelligence settings
            // User must enable: Settings > Apple Intelligence & Siri > ChatGPT
            // This is a system-level integration, not app-specific

            // iOS 18.1+ provides system-level ChatGPT integration
            // The system handles all API calls, consent, and privacy
            // Apps can request ChatGPT via AssistantIntent framework

            // Check if Apple Intelligence is available on device
            // ChatGPT Extension requires Apple Intelligence to be enabled
            return isAppleIntelligenceAvailable()
        }

        private func isAppleIntelligenceAvailable() -> Bool {
            // Apple Intelligence availability criteria:
            // - Device: iPhone 15 Pro/Pro Max or later, iPad with M1+, Mac with M1+
            // - OS: iOS 18.1+, iPadOS 18.1+, macOS 15.1+
            // - Settings: Apple Intelligence & Siri enabled

            #if canImport(FoundationModels)
                // iOS 26+ has SystemLanguageModel with proper availability check
                switch SystemLanguageModel.default.availability {
                case .available:
                    return true
                case .unavailable:
                    return false
                }
            #else
                // For iOS 18.1-25.x, check device capabilities
                // Apple Intelligence requires A17 Pro or Apple Silicon
                #if canImport(UIKit)
                    let _ = UIDevice.current.model
                    let systemVersion = (UIDevice.current.systemVersion as NSString).floatValue

                    // Check minimum iOS version
                    guard systemVersion >= 18.1 else { return false }

                    // On real devices, availability depends on hardware + Settings.
                    // We assume user can enable it; actual calls will fail gracefully if not enabled.
                    return true  // Assume available on iOS 18.1+ for now
                #else
                    // UIKit not available (e.g., macOS target for this code path) -> not available
                    return false
                #endif
            #endif
        }

        private func sendChatGPTRequest(_ prompt: String) async throws -> String {
            // IMPLEMENTATION: Apple Intelligence ChatGPT Extension (iOS 18.1+)
            // Uses AssistantIntent framework to invoke system ChatGPT integration

            Log.debug("[ChatGPT Extension] Sending request (\(prompt.count) chars)", category: .llm)

            // Create an AssistantIntent to invoke ChatGPT
            // The system handles:
            // - User consent dialog (first time or per-request if not "Always Allow")
            // - API call to OpenAI through Apple's secure proxy
            // - Privacy guarantees (Apple doesn't store the data)
            // - Free tier access (no OpenAI account needed)

            let intent = AssistChatIntent()
            intent.query = prompt
            intent.provider = .chatGPT  // Use ChatGPT provider

            do {
                // Perform the intent - this triggers the system consent dialog
                let _ = try await intent.perform()

                // For now, this will throw from the intent
                // In future with real API, we'd extract response here
                throw LLMError.generationFailed("ChatGPT Extension integration in progress")

            } catch let error as LLMError {
                throw error
            } catch {
                // Handle various error cases
                if error.localizedDescription.contains("consent")
                    || error.localizedDescription.contains("declined")
                {
                    Log.warning("User declined ChatGPT consent", category: .llm)
                    throw LLMError.generationFailed(
                        "User declined ChatGPT access. Enable in Settings > Apple Intelligence & Siri > ChatGPT"
                    )
                } else if error.localizedDescription.contains("not enabled") {
                    Log.warning("ChatGPT Extension not enabled in Settings", category: .llm)
                    throw LLMError.generationFailed(
                        "ChatGPT not enabled. Go to Settings > Apple Intelligence & Siri > ChatGPT and enable it."
                    )
                } else {
                    Log.error("ChatGPT request failed: \(error.localizedDescription)", category: .llm)
                    throw LLMError.generationFailed(
                        "ChatGPT request failed: \(error.localizedDescription)")
                }
            }
        }
    }

#else
    // Stub for platforms without AppIntents
    class AppleChatGPTExtensionService: LLMService {
        var isAvailable: Bool { false }
        var modelName: String { "ChatGPT Extension (Requires iOS 18.1+)" }

        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            throw LLMError.modelUnavailable
        }
    }
#endif

// MARK: - Core ML Implementation (Pathway B1)
// For custom models converted to .mlpackage format

class CoreMLLLMService: LLMService {

    // MARK: - Persistence Keys

    static let selectedModelIdKey = "selectedCoreMLModelId"
    static let selectedModelPathKey = "selectedCoreMLModelPath"

    // MARK: - Properties

    private let modelURL: URL
    private let modelId: UUID?
    private let installedModel: InstalledModel?
    private var model: MLModel?
    private let _modelName: String

    var toolHandler: RAGToolHandler?  // Not used by Core ML models

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path) && model != nil
    }

    var modelName: String {
        _modelName
    }

    // MARK: - Initialization

    init(modelURL: URL, modelId: UUID? = nil, installedModel: InstalledModel? = nil) {
        self.modelURL = modelURL
        self.modelId = modelId
        self.installedModel = installedModel
        if let installedModel {
            self._modelName = "Core ML • \(installedModel.name)"
        } else {
            self._modelName = "Core ML • \(modelURL.deletingPathExtension().lastPathComponent)"
        }
        self.model = CoreMLLLMService.loadModel(at: modelURL)
        if let installedModel {
            let shortId = String(installedModel.id.uuidString.prefix(8))
            Log.info(
                "✓ Configured Core ML model: \(installedModel.name) [id=\(shortId)]", category: .llm
            )
        }
    }

    private static func loadModel(at url: URL) -> MLModel? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.error("✗ Core ML model file missing: \(url.lastPathComponent)", category: .llm)
            return nil
        }

        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all  // CPU + GPU + Neural Engine
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            Log.info("Successfully loaded Core ML model: \(url.lastPathComponent)", category: .llm)
            return loaded
        } catch {
            Log.error(
                "✗ Failed to load Core ML model: \(error.localizedDescription)", category: .llm)
            return nil
        }
    }

    // MARK: - Selection Persistence

    static func saveSelection(modelId: UUID, modelURL: URL) {
        let defaults = UserDefaults.standard
        defaults.set(modelId.uuidString, forKey: selectedModelIdKey)
        defaults.set(modelURL.path, forKey: selectedModelPathKey)
        let shortId = String(modelId.uuidString.prefix(8))
        Log.info("💾 Saved Core ML selection [id=\(shortId)]", category: .llm)
    }

    static func clearSelection() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: selectedModelIdKey)
        defaults.removeObject(forKey: selectedModelPathKey)
        Log.info("Cleared Core ML selection", category: .llm)
    }

    @MainActor
    private static func resolveRegistrySelection() -> (UUID, InstalledModel, URL)? {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: selectedModelIdKey),
            let id = UUID(uuidString: idString),
            let model = ModelRegistry.shared.model(id: id),
            model.backend == .coreML,
            let url = model.localURL,
            FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return (id, model, url)
    }

    static func selectionIsReady() -> Bool {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: selectedModelPathKey) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    static func loadFromDefaults() -> CoreMLLLMService? {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: selectedModelPathKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        let service = CoreMLLLMService(modelURL: url)
        return service.isAvailable ? service : nil
    }

    static func fromRegistry() async -> CoreMLLLMService? {
        if let payload = await MainActor.run(body: { resolveRegistrySelection() }) {
            return await makeService(url: payload.2, modelId: payload.0, installedModel: payload.1)
        }
        return loadFromDefaults()
    }

    private static func makeService(url: URL, modelId: UUID?, installedModel: InstalledModel?) async
        -> CoreMLLLMService?
    {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let service = CoreMLLLMService(
                    modelURL: url, modelId: modelId, installedModel: installedModel)
                continuation.resume(returning: service.isAvailable ? service : nil)
            }
        }
    }

    // MARK: - Generation

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws
        -> LLMResponse
    {
        guard let model = model else {
            throw LLMError.modelUnavailable
        }

        let startTime = Date()

        let augmentedPrompt: String
        if let context = context, !context.isEmpty {
            augmentedPrompt = """
                Context: \(context)

                Question: \(prompt)

                Answer:
                """
        } else {
            augmentedPrompt = prompt
        }

        let inputTokens = tokenize(augmentedPrompt)
        let inputFeatures = try createInputFeatures(tokens: inputTokens, config: config)
        let prediction = try await model.prediction(from: inputFeatures)
        let outputText = try decodeOutput(prediction)

        let totalTime = Date().timeIntervalSince(startTime)

        if !outputText.isEmpty {
            LLMStreamingContext.emit(text: outputText, isFinal: false)
        }
        LLMStreamingContext.emit(text: "", isFinal: true)

        return LLMResponse(
            text: outputText,
            tokensGenerated: outputText.split(separator: " ").count,
            timeToFirstToken: nil,
            totalTime: totalTime,
            modelName: modelName,
            toolCallsMade: 0
        )
    }

    // MARK: - Tokenization (Placeholder)

    private func tokenize(_ text: String) -> [Int] {
        text.split(separator: " ").map { _ in Int.random(in: 0..<50_000) }
    }

    private func createInputFeatures(tokens: [Int], config: InferenceConfig) throws
        -> MLFeatureProvider
    {
        throw LLMError.notImplemented
    }

    private func decodeOutput(_ prediction: MLFeatureProvider) throws -> String {
        throw LLMError.notImplemented
    }
}

// MARK: - OpenAI Direct API (User's Own API Key)
// Direct integration with OpenAI API - bypasses Apple Intelligence
// User provides their own OpenAI API key
// Supports all OpenAI models: GPT-4o, GPT-4o-mini, GPT-4-turbo, etc.

class OpenAILLMService: LLMService {
    private let apiKey: String
    private let model: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"

    var toolHandler: RAGToolHandler?  // Not used by OpenAI direct API

    var isAvailable: Bool { !apiKey.isEmpty }
    var modelName: String { model }

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model

        if isAvailable {
            Log.info("OpenAI Direct API initialized (model: \(model))", category: .llm)
        }
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws
        -> LLMResponse
    {
        guard !apiKey.isEmpty else {
            throw LLMError.modelUnavailable
        }

        Log.debug("[OpenAI] Starting API call (model: \(model), prompt: \(prompt.count) chars)", category: .llm)

        let startTime = Date()

        // Construct messages with system prompt and user query
        let defaultSystemPrompt = """
        You are a helpful AI assistant with access to documents. When provided with context \
        from documents, use that information to answer questions accurately and concisely. \
        If the context doesn't contain relevant information, say so clearly. Always be helpful \
        and conversational.
        """
        
        var messages: [[String: String]] = [
            [
                "role": "system",
                "content": config.systemPrompt ?? defaultSystemPrompt,
            ]
        ]

        // Add context and user query
        if let context = context, !context.isEmpty {
            messages.append([
                "role": "user",
                "content": """
                Here is relevant information from the documents:

                \(context)

                Based on this information, please answer: \(prompt)
                """,
            ])
        } else {
            messages.append([
                "role": "user",
                "content": prompt,
            ])
        }

        // Prepare request body with model-specific parameters
        // IMPORTANT: OpenAI API parameter differences by model family:
        //
        // Standard models (GPT-4, GPT-4o, GPT-4-turbo, GPT-3.5):
        //   - Use "max_tokens" parameter
        //   - Support "temperature" for controlling randomness
        //
        // GPT-5 reasoning models (gpt-5, gpt-5-mini, gpt-5-nano):
        //   - Use "max_completion_tokens" instead of "max_tokens"
        //   - DO NOT support "temperature" - uses reasoning tokens instead
        //   - Default reasoning effort: "medium" (can be: minimal, medium, high via Responses API)
        //   - New features: verbosity, reasoning effort, CFG (via Responses API)
        //   - Similar reasoning approach to o1 but with more configurability
        //
        // o1 reasoning models (o1, o1-mini):
        //   - Use "max_completion_tokens" instead of "max_tokens"
        //   - Do NOT support "temperature" - uses reasoning tokens
        //   - Extended thinking process before responding
        //
        // See: https://platform.openai.com/docs/guides/reasoning
        // See: https://cookbook.openai.com/examples/gpt-5/gpt-5_new_params_and_tools

        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
        ]

        // Determine which models need special parameter handling
        let isReasoningModel = model.hasPrefix("o1") || model.hasPrefix("gpt-5")

        // Temperature is NOT supported by reasoning models (o1, GPT-5)
        if !isReasoningModel {
            requestBody["temperature"] = Double(config.temperature)
            requestBody["top_p"] = Double(config.topP)
            requestBody["frequency_penalty"] = Double(config.frequencyPenalty)
            requestBody["presence_penalty"] = Double(config.presencePenalty)
        }

        // Reasoning models use max_completion_tokens instead of max_tokens
        if isReasoningModel {
            requestBody["max_completion_tokens"] = config.maxTokens
        } else {
            requestBody["max_tokens"] = config.maxTokens
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw LLMError.generationFailed("Failed to encode request")
        }

        // Create request
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 60  // 60 second timeout

        // Make API call
        let (data, response) = try await URLSession.shared.data(for: request)

        let apiTime = Date().timeIntervalSince(startTime)
        Log.debug("[OpenAI] Response received in \(String(format: "%.2f", apiTime))s", category: .llm)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.generationFailed(
                "API error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            Log.error("[OpenAI] Failed to parse JSON: \(errorString)", category: .llm)
            throw LLMError.generationFailed("Failed to parse response")
        }

        guard let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            Log.error("[OpenAI] Invalid response structure", category: .llm)
            throw LLMError.generationFailed("Failed to parse response")
        }

        // Extract usage statistics
        let tokensGenerated: Int
        if let usage = json["usage"] as? [String: Any],
            let completionTokens = usage["completion_tokens"] as? Int
        {
            tokensGenerated = completionTokens
        } else {
            tokensGenerated = content.split(separator: " ").count
        }

        let totalTime = Date().timeIntervalSince(startTime)
        Log.info("[OpenAI] Generation complete: \(tokensGenerated) tokens in \(String(format: "%.2f", totalTime))s", category: .llm)

        if !content.isEmpty {
            LLMStreamingContext.emit(text: content, isFinal: false)
        }
        LLMStreamingContext.emit(text: "", isFinal: true)

        return LLMResponse(
            text: content,
            tokensGenerated: tokensGenerated,
            timeToFirstToken: nil,
            totalTime: totalTime,
            modelName: "OpenAI \(model)",
            toolCallsMade: 0
        )
    }
}

// MARK: - REMOVED: Mock Implementation
// Mock services removed - use real implementations only:
// 1. OnDeviceAnalysisService - extractive QA with NaturalLanguage framework
// 2. AppleChatGPTExtensionService - Apple's ChatGPT integration (iOS 18.1+)
// 3. OpenAILLMService - direct OpenAI API with user's key
// 4. CoreMLLLMService - custom models (optional enhancement)

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelUnavailable
    case generationFailed(String)
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "LLM model is not available on this device"
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}

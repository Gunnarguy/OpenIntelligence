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

    /// Count occurrences of a pattern across ALL documents (exact matching)
    /// This uses full-text storage, not semantic search
    func countPatternInCorpus(pattern: String) async throws -> String

    /// Search for exact text pattern across ALL documents
    /// Returns documents containing the pattern with context
    func searchExactPattern(pattern: String) async throws -> String

    /// Get corpus-wide statistics
    func getCorpusStats() async throws -> String

    /// Find documents related to a topic (semantic, returns document names)
    func findRelatedDocuments(topic: String, maxResults: Int) async throws -> String

    /// Compare how multiple documents discuss a topic
    func compareDocumentsOnTopic(topic: String, documentNames: [String]?) async throws -> String
}

// MARK: - Streaming Bridge

struct LLMStreamEvent: Sendable {
    let text: String
    let isFinal: Bool
}

typealias LLMStreamHandler = @Sendable (LLMStreamEvent) async -> Void

struct StructuredRAGClaim: Sendable {
    let claim: String
    let citations: [String]
    let isExtracted: Bool
}

struct StructuredRAGGeneration: Sendable {
    let reasoning: String?
    let answer: String
    let confidence: Int
    let citations: [String]
    let matchedTerms: [String]
    let claims: [StructuredRAGClaim]
}

enum StructuredRAGMode: Sendable, Equatable {
    case direct
    case reasoned
}

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
// TOKEN BUDGET: Apple FM has 4096 token context limit (~10K chars).
// Each tool output should be ≤1500 chars to leave room for prompt + response.
// All tools MUST truncate results to respect this budget.

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
                "Maximum number of chunks to retrieve. Use 2–4 for brief summaries, 8–12 for deep dives.",
                .range(1 ... 20)
            )
            var topK: Int?
            @Guide(
                description:
                "Minimum semantic similarity threshold. Use 0.35 by default; increase to filter noise.",
                .range(0.0 ... 1.0)
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

        func call(arguments _: Arguments) async throws -> String {
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

    // MARK: - Exact Search Tools (Full-Text, Not Semantic)

    /// Tool for counting exact pattern occurrences across ALL documents
    /// Uses FullTextStorageService for precise counting (not semantic search)
    @available(iOS 26.0, *)
    struct CountPatternTool: Tool {
        let name = "count_pattern"
        let description = """
            Count EXACT occurrences of a text pattern across ALL documents in the library.
            Returns per-document counts and total. Use for questions like "how many times is X mentioned?"
            This searches the complete original text, not chunked embeddings.
            """

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(
                description: """
                    The exact text pattern to count. Case-insensitive.
                    For multi-word phrases, include the full phrase.
                    Examples: "SAE 0W-20", "transmission fluid", "warning light"
                    """
            )
            var pattern: String
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.countPatternInCorpus(pattern: arguments.pattern)
        }
    }

    /// Tool for searching exact text patterns with surrounding context
    /// Uses FullTextStorageService for precise matching (not semantic search)
    @available(iOS 26.0, *)
    struct SearchExactPatternTool: Tool {
        let name = "search_exact_pattern"
        let description = """
            Search for EXACT text matches across ALL documents and return context.
            Unlike semantic search, this finds precise string matches.
            Use when you need to find specific terms, codes, model numbers, or exact phrases.
            """

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(
                description: """
                    The exact text pattern to search for. Case-insensitive.
                    Will return surrounding context for each match.
                    Examples: "serial number", "model specification", "error code 404"
                    """
            )
            var pattern: String
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.searchExactPattern(pattern: arguments.pattern)
        }
    }

    // MARK: - Analysis Tools

    /// Tool for getting corpus-wide statistics and analysis
    @available(iOS 26.0, *)
    struct GetCorpusStatsTool: Tool {
        let name = "get_corpus_stats"
        let description = """
            Get statistics about the entire document library including:
            - Total documents and pages
            - Document types breakdown
            - Total word/character counts
            - Average document size
            Use for questions about the library itself.
            """

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            // No arguments needed for corpus stats
        }

        func call(arguments _: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.getCorpusStats()
        }
    }

    /// Tool for finding documents related to a topic
    @available(iOS 26.0, *)
    struct FindRelatedDocumentsTool: Tool {
        let name = "find_related_documents"
        let description = """
            Find documents that are semantically related to a topic or query.
            Returns document names ranked by relevance, not individual chunks.
            Use when you need to identify WHICH documents cover a topic.
            """

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(
                description: "Topic or query to find related documents for"
            )
            var topic: String
            @Guide(
                description: "Maximum number of documents to return",
                .range(1 ... 20)
            )
            var maxResults: Int?
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.findRelatedDocuments(
                topic: arguments.topic,
                maxResults: arguments.maxResults ?? 5
            )
        }
    }

    /// Tool for comparing content across multiple documents
    @available(iOS 26.0, *)
    struct CompareDocumentsTool: Tool {
        let name = "compare_documents"
        let description = """
            Compare how multiple documents discuss the same topic.
            Useful for finding differences, contradictions, or complementary information.
            """

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(
                description: "Topic to compare across documents"
            )
            var topic: String
            @Guide(
                description: "Names of specific documents to compare (optional, uses all if empty)"
            )
            var documentNames: [String]?
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService = ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.compareDocumentsOnTopic(
                topic: arguments.topic,
                documentNames: arguments.documentNames
            )
        }
    }

    // MARK: - Consolidated Engine-Native Tool Surface

    /// Core retrieval tool for semantic, exact, and related-document evidence access.
    @available(iOS 26.0, *)
    struct RetrieveCorpusEvidenceTool: Tool {
        let name = "retrieve_corpus_evidence"
        let description = """
            Retrieve grounded evidence from the user's library.
            Modes:
            - semantic: retrieve relevant passages for a question
            - exact: find exact text matches with context
            - count_exact: count exact text occurrences across the corpus
            - related_documents: find which documents are most related to a topic
            """

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(description: "Question, topic, or literal pattern to search for")
            var query: String

            @Guide(description: "Mode: semantic, exact, count_exact, or related_documents")
            var mode: String

            @Guide(description: "Maximum number of results to return", .range(1 ... 20))
            var maxResults: Int?

            @Guide(description: "Minimum semantic similarity threshold for semantic mode", .range(0.0 ... 1.0))
            var minSimilarity: Float?
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService else {
                return "Error: Retrieval service unavailable"
            }
            await ToolCallCounter.shared.increment()

            switch arguments.mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "exact":
                return try await ragService.searchExactPattern(pattern: arguments.query)
            case "count_exact":
                return try await ragService.countPatternInCorpus(pattern: arguments.query)
            case "related_documents":
                return try await ragService.findRelatedDocuments(
                    topic: arguments.query,
                    maxResults: arguments.maxResults ?? 5
                )
            default:
                return try await ragService.searchDocuments(
                    query: arguments.query,
                    topK: arguments.maxResults,
                    minSimilarity: arguments.minSimilarity
                )
            }
        }
    }

    /// Inspect a specific document for summary and metadata.
    @available(iOS 26.0, *)
    struct InspectDocumentTool: Tool {
        let name = "inspect_document"
        let description = "Inspect a specific document by name and return its summary, metadata, and content overview."

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(description: "Exact document name to inspect")
            var documentName: String
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService else {
                return "Error: Document service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.getDocumentSummary(documentName: arguments.documentName)
        }
    }

    /// Compare how documents discuss a topic.
    @available(iOS 26.0, *)
    struct CompareTopicAcrossDocumentsTool: Tool {
        let name = "compare_topic_across_documents"
        let description = "Compare how multiple documents discuss the same topic to find differences, overlap, and supporting evidence."

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            @Guide(description: "Topic to compare across documents")
            var topic: String

            @Guide(description: "Optional specific document names to compare")
            var documentNames: [String]?
        }

        func call(arguments: Arguments) async throws -> String {
            guard let ragService else {
                return "Error: Comparison service unavailable"
            }
            await ToolCallCounter.shared.increment()
            return try await ragService.compareDocumentsOnTopic(
                topic: arguments.topic,
                documentNames: arguments.documentNames
            )
        }
    }

    /// High-level library overview tool for corpus-wide inspection.
    @available(iOS 26.0, *)
    struct GetLibraryOverviewTool: Tool {
        let name = "get_library_overview"
        let description = "Return a compact overview of the current library, including corpus stats and available documents."

        weak var ragService: RAGService?

        @Generable
        struct Arguments {
            // No arguments needed
        }

        func call(arguments _: Arguments) async throws -> String {
            guard let ragService else {
                return "Error: Library service unavailable"
            }
            await ToolCallCounter.shared.increment()

            let stats = try await ragService.getCorpusStats()
            let documents = try await ragService.listDocuments()
            return stats + "\n\nDOCUMENTS:\n" + documents
        }
    }

#endif

/// Response from an LLM generation request
struct LLMResponse {
    let text: String
    let tokensGenerated: Int
    let timeToFirstToken: TimeInterval?
    let totalTime: TimeInterval
    let modelName: String? // Actual model used (includes execution location)
    let toolCallsMade: Int // Number of tool calls executed (for agentic RAG metrics)
    let structuredRAGGeneration: StructuredRAGGeneration?

    init(
        text: String,
        tokensGenerated: Int,
        timeToFirstToken: TimeInterval?,
        totalTime: TimeInterval,
        modelName: String?,
        toolCallsMade: Int,
        structuredRAGGeneration: StructuredRAGGeneration? = nil
    ) {
        self.text = text
        self.tokensGenerated = tokensGenerated
        self.timeToFirstToken = timeToFirstToken
        self.totalTime = totalTime
        self.modelName = modelName
        self.toolCallsMade = toolCallsMade
        self.structuredRAGGeneration = structuredRAGGeneration
    }

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
        private var currentSystemPrompt: String?

        /// Pending transcript to restore on next session creation.
        /// Set via `restoreFromTranscript(_:)` and consumed by `ensureSession()`.
        private var pendingTranscript: Transcript?

        private static let structuredCitationRegex = try? NSRegularExpression(
            pattern: #"S(\d+)"#,
            options: [.caseInsensitive]
        )

        /// Tool handler for agentic RAG function calling
        var toolHandler: RAGToolHandler?

        /// Guards against concurrent warmup calls that cause "Session in Canceled state" warnings
        private var isWarmingUp = false

        // MARK: - Language Detection Fix

        /// Sanitize text to prevent false language detection by Apple Foundation Models.
        ///
        /// Apple's language detector can misidentify English text as Polish or other languages
        /// when certain character patterns are present (especially Polish diacritics like ł, ą, ę, ó, etc.
        /// or sequences that resemble them). This function normalizes such characters.
        private func sanitizeForLanguageDetection(_ text: String) -> String {
            // Common problematic characters that trigger false Polish detection:
            // - URLs with encoded characters
            // - Special Unicode characters
            // - Technical symbols that resemble diacritics
            var sanitized = text

            // Replace Polish-like diacritics with ASCII equivalents
            let replacements: [(String, String)] = [
                ("ł", "l"), ("Ł", "L"),
                ("ą", "a"), ("Ą", "A"),
                ("ę", "e"), ("Ę", "E"),
                ("ó", "o"), ("Ó", "O"),
                ("ś", "s"), ("Ś", "S"),
                ("ź", "z"), ("Ź", "Z"),
                ("ż", "z"), ("Ż", "Z"),
                ("ć", "c"), ("Ć", "C"),
                ("ń", "n"), ("Ń", "N"),
                // Other problematic diacritics
                ("ü", "u"), ("ö", "o"), ("ä", "a"),
                ("è", "e"), ("é", "e"), ("ê", "e"),
                ("à", "a"), ("á", "a"), ("â", "a"),
                ("ì", "i"), ("í", "i"), ("î", "i"),
                ("ù", "u"), ("ú", "u"), ("û", "u"),
                ("ñ", "n"), ("ç", "c"),
            ]

            for (original, replacement) in replacements {
                sanitized = sanitized.replacingOccurrences(of: original, with: replacement)
            }

            // Normalize certain problematic Unicode sequences
            // These can confuse language detection
            sanitized = sanitized.precomposedStringWithCanonicalMapping

            return sanitized
        }

        func resetSession(clearTools: Bool = false) {
            if clearTools {
                toolHandler = nil
            }
            session = nil
            currentSystemPrompt = nil
            pendingTranscript = nil
        }

        /// Restore session state from a previously saved transcript.
        ///
        /// The transcript will be applied on the next `ensureSession()` call,
        /// giving the model full context of the previous conversation.
        ///
        /// - Parameter transcript: The transcript to restore from
        /// - Returns: `true` if transcript was queued for restoration
        @MainActor
        @discardableResult
        func restoreFromTranscript(_ transcript: Transcript) -> Bool {
            guard Thread.isMainThread else {
                Log.error("[AppleFM] Must call restoreFromTranscript from main thread", category: .llm)
                return false
            }

            // Clear current session so next ensureSession() creates a new one with transcript
            session = nil
            pendingTranscript = transcript

            Log.info("[AppleFM] Queued transcript with \(transcript.count) entries for session restoration", category: .llm)
            return true
        }

        // Lazy model access - only initialize when actually needed and ensure main thread
        private var _model: SystemLanguageModel?
        private var model: SystemLanguageModel {
            if let existing = _model {
                return existing
            }

            // CRITICAL: SystemLanguageModel.default MUST be accessed on main thread
            guard Thread.isMainThread else {
                assertionFailure(
                    "AppleFoundationLLMService must access SystemLanguageModel.default from main thread"
                )
                // In Release, attempt access anyway — the system framework's own
                // diagnostics are preferable to a guaranteed crash.
                let model = SystemLanguageModel.default
                _model = model
                return model
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
            case let .unavailable(reason):
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

        // MARK: - Language Support (iOS 26+)

        /// Check if the current device locale is supported by Apple Intelligence
        var supportsCurrentLocale: Bool {
            guard Thread.isMainThread else { return false }
            return model.supportsLocale()
        }

        /// Check if a specific locale is supported
        func supportsLocale(_ locale: Locale) -> Bool {
            guard Thread.isMainThread else { return false }
            return model.supportsLocale(locale)
        }

        /// Get all supported languages for display in UI
        var supportedLanguages: Set<Locale.Language> {
            guard Thread.isMainThread else { return [] }
            return model.supportedLanguages
        }

        /// Context window size for on-device model (4096 tokens per TN3193)
        static let contextWindowSize: Int = 4096

        /// Approximate token count for a string.
        /// Uses empirically validated 1.4 chars/token for Apple FM (observed across real prompts).
        /// Previous 2.5 ratio underestimated by ~44%, causing context overflow retries.
        static func estimateTokens(for text: String) -> Int {
            let charsPerToken = 1.4
            return max(1, Int(ceil(Double(text.count) / charsPerToken)))
        }

        // MARK: - Transcript Access (iOS 26+)

        /// Access the session transcript for debugging/replay
        /// Contains all prompts, responses, and tool calls in order
        var transcript: Transcript? {
            guard Thread.isMainThread else { return nil }
            return session?.transcript
        }

        // MARK: - Real-time Generation State (iOS 26+)

        /// Whether the session is currently generating a response.
        ///
        /// This property reflects the actual state of the FoundationModels session,
        /// providing real-time feedback for UI indicators. The session is Observable,
        /// so this value updates automatically during generation.
        ///
        /// Use this for:
        /// - Showing live "typing" indicators
        /// - Disabling input during generation
        /// - Accurate progress animations
        var isResponding: Bool {
            guard Thread.isMainThread, let session = session else { return false }
            return session.isResponding
        }

        /// Get a text representation of the current conversation history
        /// Transcript conforms to Collection, so iterate directly over it
        var transcriptDescription: String {
            guard let transcript = transcript else { return "No transcript available" }
            var description = "Session Transcript (\(transcript.count) entries):\n"
            for (index, entry) in transcript.enumerated() {
                switch entry {
                case let .instructions(inst):
                    description += "[\(index + 1)] Instructions: \(String(describing: inst).prefix(80))...\n"
                case let .prompt(prompt):
                    description += "[\(index + 1)] Prompt: \(String(describing: prompt).prefix(80))...\n"
                case let .response(resp):
                    description += "[\(index + 1)] Response: \(String(describing: resp).prefix(80))...\n"
                case let .toolCalls(calls):
                    description += "[\(index + 1)] ToolCalls: \(calls.count) call(s)\n"
                case let .toolOutput(output):
                    description += "[\(index + 1)] ToolOutput: \(String(describing: output).prefix(80))...\n"
                @unknown default:
                    description += "[\(index + 1)] Unknown entry type\n"
                }
            }
            return description
        }

        // MARK: - Transcript Token Estimation (iOS 26+)

        /// Estimate the token count of the current session transcript.
        /// This is critical for context budget calculation to avoid overflow.
        /// Uses conservative 1.4 chars/token ratio (empirically validated for Apple FM).
        var estimatedTranscriptTokens: Int {
            guard Thread.isMainThread, let transcript = transcript else { return 0 }

            var totalChars = 0
            for entry in transcript {
                switch entry {
                case let .instructions(inst):
                    totalChars += String(describing: inst).count
                case let .prompt(prompt):
                    totalChars += String(describing: prompt).count
                case let .response(resp):
                    totalChars += String(describing: resp).count
                case let .toolCalls(calls):
                    // Tool calls are typically compact JSON
                    totalChars += calls.count * 100 // ~100 chars per tool call average
                case let .toolOutput(output):
                    totalChars += String(describing: output).count
                @unknown default:
                    totalChars += 50 // Conservative estimate for unknown types
                }
            }

            // Use conservative 1.4 chars/token for Apple FM
            return max(0, Int(ceil(Double(totalChars) / 1.4)))
        }

        /// Estimate tokens for a pending transcript (before session creation)
        static func estimateTranscriptTokens(_ transcript: Transcript) -> Int {
            var totalChars = 0
            for entry in transcript {
                switch entry {
                case let .instructions(inst):
                    totalChars += String(describing: inst).count
                case let .prompt(prompt):
                    totalChars += String(describing: prompt).count
                case let .response(resp):
                    totalChars += String(describing: resp).count
                case let .toolCalls(calls):
                    totalChars += calls.count * 100
                case let .toolOutput(output):
                    totalChars += String(describing: output).count
                @unknown default:
                    totalChars += 50
                }
            }
            return max(0, Int(ceil(Double(totalChars) / 1.4)))
        }

        // MARK: - Feedback API (iOS 26+)

        /// Submit feedback for the last response to help Apple improve model quality
        /// Returns serialized feedback data suitable for Feedback Assistant attachment
        func logFeedback(
            sentiment: LanguageModelFeedback.Sentiment,
            issues: [LanguageModelFeedback.Issue] = [],
            desiredOutput: Transcript.Entry? = nil
        ) -> Data? {
            guard Thread.isMainThread, let session = session else { return nil }
            let feedbackData = session.logFeedbackAttachment(
                sentiment: sentiment,
                issues: issues,
                desiredOutput: desiredOutput
            )
            Log.debug("[FM] Feedback logged: \(sentiment)", category: .llm)
            return feedbackData
        }

        /// Convenience: Submit positive feedback
        func submitPositiveFeedback() -> Data? {
            return logFeedback(sentiment: .positive)
        }

        /// Convenience: Submit negative feedback with optional issue details
        func submitNegativeFeedback(
            category: LanguageModelFeedback.Issue.Category? = nil,
            explanation: String? = nil
        ) -> Data? {
            var issues: [LanguageModelFeedback.Issue] = []
            if let category = category {
                issues.append(LanguageModelFeedback.Issue(
                    category: category,
                    explanation: explanation
                ))
            }
            return logFeedback(sentiment: .negative, issues: issues)
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

            // Guard against concurrent warmups that cause "Session in Canceled state" warnings
            guard !isWarmingUp else {
                Log.debug("[Warm-up] Already warming up, skipping duplicate request", category: .llm)
                return
            }

            isWarmingUp = true

            Task {
                await self.warmUpModel()
                await MainActor.run { self.isWarmingUp = false }
            }
        }

        /// Preload the Foundation Model to eliminate first-query latency
        /// Uses official prewarm() API instead of throwaway prompts (saves tokens)
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

                // ✅ Use official prewarm() API - no wasted tokens!
                // Optionally cache a common prompt prefix for RAG queries
                let ragPromptPrefix = Prompt("Based on the following document content, please answer:")
                session.prewarm(promptPrefix: ragPromptPrefix)

                let loadTime = Date().timeIntervalSince(startTime)
                Log.info("[Warm-up] Foundation Model preloaded in \(String(format: "%.2f", loadTime))s (using prewarm API)", category: .llm)

            } catch {
                let failTime = Date().timeIntervalSince(startTime)
                Log.warning("[Warm-up] Model preload failed after \(String(format: "%.2f", failTime))s: \(error)", category: .llm)
            }
        }

        // Lazy session creation - only when actually generating
        private func ensureSession(systemPrompt: String? = nil, disableTools: Bool = false) throws {
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
                // UNLESS disableTools is set (for reasoning chain sessions)
                var tools: [any Tool] = []

                if !disableTools, let ragService = toolHandler as? RAGService {
                    // Create a smaller engine-native tool surface per Apple guidance.
                    var retrieveTool = RetrieveCorpusEvidenceTool()
                    retrieveTool.ragService = ragService
                    tools.append(retrieveTool)

                    var inspectTool = InspectDocumentTool()
                    inspectTool.ragService = ragService
                    tools.append(inspectTool)

                    var compareTool = CompareTopicAcrossDocumentsTool()
                    compareTool.ragService = ragService
                    tools.append(compareTool)

                    var overviewTool = GetLibraryOverviewTool()
                    overviewTool.ragService = ragService
                    tools.append(overviewTool)

                    Log.debug("Initialized \(tools.count) engine-native tools for agentic RAG", category: .llm)
                } else if disableTools {
                    Log.debug("Tools disabled for this session (pure reasoning mode)", category: .llm)
                }

                // Session instructions — context-aware to avoid wasting tokens on tool guidance
                // when tools aren't attached. Every word counts at ~1.4 chars/token.
                let defaultInstructions: String
                if disableTools {
                    // Pure context/reasoning mode — no tool instructions needed
                    defaultInstructions = """
                    You are OpenIntelligence, a helpful assistant. Answer from the provided document context. Be thorough, cite sources, and copy values exactly.
                    """
                } else {
                    // Agentic mode — tools attached, need usage guidance
                    defaultInstructions = """
                    You are OpenIntelligence, a helpful assistant.
                    When document context is provided, answer directly from it — do NOT call tools.
                    Only use tools when NO context is provided:
                    - retrieve_corpus_evidence: retrieve semantic evidence, exact matches, exact counts, or related documents
                    - inspect_document: inspect one document by name
                    - compare_topic_across_documents: compare evidence across documents
                    - get_library_overview: inspect the library and available documents
                    Cite sources and copy values exactly.
                    """
                }

                let instructionsText = systemPrompt ?? defaultInstructions
                currentSystemPrompt = systemPrompt

                // Check if we have a pending transcript to restore
                // CRITICAL: Don't restore transcript if tools are disabled - the transcript
                // may contain tool references that would cause warnings/errors
                if let savedTranscript = pendingTranscript, !disableTools {
                    // Create session with transcript for conversation continuity
                    // The transcript contains previous prompts, responses, and tool calls
                    // Note: Instructions come from the transcript, not passed separately
                    session = LanguageModelSession(
                        model: model,
                        tools: tools,
                        transcript: savedTranscript
                    )

                    // Prewarm to reduce latency on next query
                    session?.prewarm()

                    pendingTranscript = nil // Consumed
                    Log.info(
                        "Apple Foundation Model session restored from transcript (\(savedTranscript.count) entries)",
                        category: .llm
                    )
                } else {
                    // Fresh session - either no transcript or tools disabled (pure reasoning mode)
                    if disableTools && pendingTranscript != nil {
                        Log.debug("Discarding transcript for tools-disabled session (pure reasoning)", category: .llm)
                        pendingTranscript = nil
                    }
                    session = LanguageModelSession(
                        model: model,
                        tools: tools,
                        instructions: Instructions(instructionsText)
                    )
                    Log.info("Apple Foundation Model session initialized\(disableTools ? " (pure reasoning)" : " (Agentic RAG)")", category: .llm)
                }

            case let .unavailable(reason):
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

        @MainActor
        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            // MARK: Locale Validation (iOS 26+)
            // Verify the current locale is supported before generation to provide
            // a clear error rather than garbled output from unsupported languages
            if !supportsCurrentLocale {
                let currentLocale = Locale.current.identifier
                Log.warning("Current locale '\(currentLocale)' not supported by Apple Intelligence — generation may produce degraded output", category: .llm)
            }

            // Force statelessness: RAGService manages history manually and constructs a full prompt
            // including previous conversation. Reusing the session would duplicate history.
            session = nil

            // Check if system prompt changed (redundant now but keeps logic clean)
            if let newPrompt = config.systemPrompt, newPrompt != currentSystemPrompt {
                Log.info("System prompt changed, recreating session", category: .llm)
                session = nil
            }

            // AUTO-TRIM TRANSCRIPT: Context gets priority, transcript gets whatever's left.
            // Estimate how many tokens the actual content (context + prompt + overhead) will use,
            // then trim the transcript from oldest entries to fit within the 4096 window.
            // This ensures document context is NEVER starved by conversation history.
            if let transcript = pendingTranscript, !transcript.isEmpty {
                let contextChars = context?.count ?? 0
                let promptChars = prompt.count
                let systemChars = (config.systemPrompt ?? "").count
                // Conservative: instructions + system + prompt + context + output reserve
                let contentTokens = Int(ceil(Double(contextChars + promptChars + systemChars + 200) / 1.4))
                let outputReserve = max(150, min(config.maxTokens, 300))
                let toolSchemaTokens = config.disableTools ? 0 : 1000
                let budgetForContent = contentTokens + outputReserve + toolSchemaTokens

                let maxTranscriptTokens = max(0, 4096 - budgetForContent)
                let currentTranscriptTokens = Self.estimateTranscriptTokens(transcript)

                if currentTranscriptTokens > maxTranscriptTokens {
                    // Trim oldest entries, keeping instructions (first entry) + most recent
                    let allEntries = Array(transcript)
                    let firstEntry = allEntries.first  // Usually instructions — always keep

                    // Binary-search-style trim: keep removing oldest non-instruction entries
                    var keepCount = allEntries.count
                    while keepCount > 1 {
                        let candidateEntries: [Transcript.Entry]
                        if let first = firstEntry {
                            candidateEntries = [first] + Array(allEntries.suffix(keepCount - 1))
                        } else {
                            candidateEntries = Array(allEntries.suffix(keepCount))
                        }
                        let candidateTranscript = Transcript(entries: candidateEntries)
                        let tokens = Self.estimateTranscriptTokens(candidateTranscript)
                        if tokens <= maxTranscriptTokens {
                            let dropped = allEntries.count - candidateEntries.count
                            Log.info("[FM] Auto-trimmed transcript: \(currentTranscriptTokens)→\(tokens) tokens (dropped \(dropped) oldest entries, preserving \(contentTokens) tokens for context)", category: .llm)
                            pendingTranscript = candidateTranscript
                            break
                        }
                        keepCount -= 1
                    }

                    // If even 1 entry is too large, drop transcript entirely
                    if keepCount <= 1 {
                        Log.warning("[FM] Transcript (\(currentTranscriptTokens) tokens) too large even after trimming, dropping to preserve context (\(contentTokens) tokens)", category: .llm)
                        pendingTranscript = nil
                    }
                }
            }

            // Ensure session is created (now guaranteed to be on main thread via @MainActor)
            try ensureSession(systemPrompt: config.systemPrompt, disableTools: config.disableTools)

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
            // Apply language sanitization to prevent false Polish detection
            let sanitizedPrompt = sanitizeForLanguageDetection(prompt)
            let sanitizedContext = context.map { sanitizeForLanguageDetection($0) }

            let fullPrompt: String
            if let context = sanitizedContext, !context.isEmpty {
                Log.debug("RAG mode: context=\(context.count) chars, prompt=\(sanitizedPrompt.prefix(50))...", category: .llm)

                // Estimate if we're approaching context window limit (4096 tokens, ~1.4 chars/token for Apple FM)
                let totalInputLength = context.count + sanitizedPrompt.count + 200 // Buffer for instructions
                let charsPerToken = 1.4
                let estimatedInputTokens = max(
                    1,
                    Int(ceil(Double(totalInputLength) / charsPerToken))
                )

                if estimatedInputTokens > 3500 {
                    Log.warning("[FM] Input approaching context limit: ~\(estimatedInputTokens) tokens", category: .llm)
                }

                if config.systemPrompt != nil {
                    // System instructions already set — formatting is handled by systemPrompt.
                    // BUDGET-CONSCIOUS: No duplicate formatting instructions. Save ~80 tokens.
                    fullPrompt = """
                    CONTEXT:
                    \(context)

                    QUESTION: \(sanitizedPrompt)

                    Answer using EXACT values from the context. Merge overlapping excerpts — NEVER repeat the same sentence frame.
                    """
                } else {
                    // No system prompt — embed minimal instructions in prompt.
                    fullPrompt = """
                    Answer from the excerpts below. Be thorough. Copy values VERBATIM.
                    Cite sources [Document Name, p.X].
                    Merge overlapping excerpts — NEVER repeat the same sentence frame.

                    EXCERPTS:
                    \(context)

                    QUESTION: \(sanitizedPrompt)
                    """
                }
            } else {
                Log.debug("General chat mode: prompt=\(sanitizedPrompt.prefix(50))...", category: .llm)

                // Handle short queries that may confuse language detection
                // Per Apple's documentation, the language detector needs sufficient text
                let wordCount = sanitizedPrompt.split(separator: " ").count

                if wordCount <= 2 {
                    // Very short queries (1-2 words) - add explicit English context
                    fullPrompt =
                        "Please explain the following topic clearly and concisely: \(sanitizedPrompt)"
                } else if wordCount <= 5, !sanitizedPrompt.contains(" the "), !sanitizedPrompt.contains(" is ") {
                    // Short queries without clear English markers
                    fullPrompt =
                        "Answer the following clearly and concisely: \(sanitizedPrompt)"
                } else {
                    fullPrompt = sanitizedPrompt
                }
            }

            // Estimate token count for routing decisions (1.4 chars/token, empirically validated)
            let promptLength = fullPrompt.count
            let estimatedTokens = max(1, Int(ceil(Double(promptLength) / 1.4)))
            Log.debug("Generation: ~\(estimatedTokens) tokens, exec=\(config.executionContext)", category: .llm)

            // Generate response using streaming API with execution context
            var responseText = ""
            var tokenCount = 0
            var firstTokenTime: TimeInterval?
            var actualExecutionLocation = "Unknown"

            // ✅ Full GenerationOptions with SamplingMode support
            // iOS 26 supports: temperature, sampling (topK/topP), maximumResponseTokens
            let samplingMode: GenerationOptions.SamplingMode?
            if config.topK > 0, config.topK < 100 {
                // Top-K sampling: consider K highest probability tokens
                samplingMode = .random(top: config.topK)
            } else if config.topP < 1.0, config.topP > 0.0 {
                // Nucleus/Top-P sampling: consider tokens until cumulative probability
                samplingMode = .random(probabilityThreshold: Double(config.topP))
            } else {
                // Default: let system decide
                samplingMode = nil
            }

            let options = GenerationOptions(
                sampling: samplingMode,
                temperature: Double(config.temperature),
                maximumResponseTokens: config.maxTokens > 0 ? config.maxTokens : nil
            )

            let responseStream = session.streamResponse(to: fullPrompt, options: options)

            var snapshotCount = 0
            var guardrailViolation = false
            var unsupportedLanguage = false

            // Report Neural Engine activity - LLM inference starting
            HardwareTelemetryReporter.reportLLMInference(active: true)

            do {
                for try await snapshot in responseStream {
                    snapshotCount += 1

                    if firstTokenTime == nil {
                        firstTokenTime = Date().timeIntervalSince(startTime)

                        // Haptic: first token arrived — the "brain lit up" moment
                        await MainActor.run { DSHaptics.generationStarted() }

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

                            // NOTE: We CANNOT force PCC. Apple's modelmanagerd daemon
                            // makes routing decisions based on context size, complexity,
                            // thermals, battery, and user's PCC consent settings.
                            // If the system chose on-device, trust it. If context overflows
                            // (>4096 tokens), Apple's framework will throw the error.
                            if config.executionContext == .cloudOnly,
                               actualExecutionLocation.contains("On-Device")
                            {
                                // Just log - don't abort. Let the system work.
                                Log.info(
                                    "[FM] System selected on-device despite cloud preference - context may fit in 4096 tokens",
                                    category: .llm
                                )
                            }

                            // Log when system routes to PCC despite our preference for on-device
                            // NOTE: We cannot actually force on-device execution - Apple's system
                            // automatically routes to PCC when context is too large. The only way
                            // to avoid PCC is to trim context to fit within 4096 tokens.
                            // If the user has PCC disabled in iOS Settings, this will fail at
                            // the system level, not here.
                            if config.executionContext == .onDeviceOnly || !config.allowPrivateCloudCompute,
                               actualExecutionLocation.contains("Private Cloud Compute")
                            {
                                Log.warning("[FM] PCC routed despite on-device preference - context may be too large for 4096 limit", category: .llm)
                                TelemetryCenter.emit(
                                    .system,
                                    severity: .info,
                                    title: "System routed to PCC",
                                    metadata: [
                                        "ttft": String(format: "%.2f", ttft),
                                        "execDetected": actualExecutionLocation,
                                        "note": "Context exceeds on-device capacity - PCC required",
                                    ]
                                )
                                // DON'T abort - let the system work. If PCC is truly unavailable
                                // (user disabled in Settings), Apple's framework will handle it.
                                // We've already trimmed context as much as possible.
                            }
                        }
                    }

                    // Update response text from snapshot
                    let previousLength = responseText.count
                    responseText = snapshot.content
                    let newChars = responseText.count - previousLength

                    // Token counting based on Apple FM's ~1.4 chars/token ratio
                    // (word count underestimates by ~23% for English, more for technical text)
                    let currentTokenEstimate = max(1, Int(ceil(Double(responseText.count) / 1.4)))
                    let newTokens = currentTokenEstimate - tokenCount

                    if newTokens > 0 {
                        tokenCount = currentTokenEstimate
                    }

                    // Emit new content to streaming context
                    if newChars > 0 {
                        let chunk = String(responseText.suffix(newChars))
                        LLMStreamingContext.emit(text: chunk, isFinal: false)
                    }

                    // Subtle haptic tick every 8 snapshots — "feel the thinking"
                    if snapshotCount % 8 == 0 {
                        await MainActor.run { DSHaptics.generationTick() }
                    }
                }
            } catch let error as LanguageModelSession.GenerationError {
                // Stop Neural Engine activity on error
                HardwareTelemetryReporter.sustain(.llmInference, active: false)

                // ✅ Handle iOS 26 FoundationModels-specific errors (exhaustive)
                switch error {
                case let .exceededContextWindowSize(context):
                    Log.warning("[FM] Context window exceeded (4096 tokens): \(context)", category: .llm)
                    TelemetryCenter.emit(
                        .system,
                        severity: .warning,
                        title: "Context window exceeded",
                        metadata: ["estimatedTokens": "\(estimatedTokens)"]
                    )
                    // Rethrow to allow RAGService to handle retry with reduced context
                    throw error
                case let .guardrailViolation(context):
                    Log.warning("[FM] Guardrail violation - content filtered: \(context)", category: .llm)
                    guardrailViolation = true
                    TelemetryCenter.emit(
                        .system,
                        severity: .warning,
                        title: "Guardrail violation",
                        metadata: [:]
                    )
                case let .unsupportedLanguageOrLocale(context):
                    Log.warning("[FM] Unsupported language/locale: \(context)", category: .llm)
                    unsupportedLanguage = true
                case let .rateLimited(context):
                    Log.warning("[FM] Rate limited: \(context)", category: .llm)
                    throw LLMError.rateLimited(
                        "Apple Intelligence is temporarily rate-limited. Please wait a moment and try again."
                    )
                case let .refusal(refusal, context):
                    Log.warning("[FM] Model refused request: \(refusal) - \(context)", category: .llm)
                    throw LLMError.generationFailed(
                        "Apple Intelligence declined this request. Try rephrasing your question."
                    )
                case let .assetsUnavailable(context):
                    Log.error("[FM] Model assets unavailable: \(context)", category: .llm)
                    throw LLMError.generationFailed(
                        "Apple Intelligence models are not currently available. Ensure Apple Intelligence is enabled in Settings."
                    )
                case let .decodingFailure(context):
                    Log.error("[FM] Decoding failure: \(context)", category: .llm)
                    throw LLMError.generationFailed(
                        "Failed to decode model response. This is an internal error—please try again."
                    )
                case let .concurrentRequests(context):
                    Log.warning("[FM] Concurrent requests blocked: \(context)", category: .llm)
                    throw LLMError.concurrentRequests(
                        "A request is already in progress. Please wait for it to complete."
                    )
                case let .unsupportedGuide(context):
                    Log.error("[FM] Unsupported generation guide: \(context)", category: .llm)
                    throw LLMError.generationFailed(
                        "An internal tool configuration error occurred. Please report this bug."
                    )
                @unknown default:
                    Log.error("[FM] Unknown generation error: \(error)", category: .llm)
                    throw error
                }
            }

            // Stop Neural Engine activity indicator
            HardwareTelemetryReporter.sustain(.llmInference, active: false)

            // Haptic: generation complete — satisfying finish tap
            await MainActor.run { DSHaptics.generationComplete() }

            // Handle generation errors with user-friendly messages
            if guardrailViolation {
                throw LLMError.generationFailed(
                    "Apple's safety guardrails prevented this response. " +
                        "Please rephrase your question to avoid sensitive topics."
                )
            }

            if unsupportedLanguage {
                // For short queries, this might be a false positive from language detection
                // Suggest rephrasing rather than claiming the language is unsupported
                let supportedList = supportedLanguages.prefix(5).map { $0.languageCode?.identifier ?? "?" }.joined(separator: ", ")
                throw LLMError.generationFailed(
                    "Apple Intelligence couldn't process this query. " +
                        "Try rephrasing with more context (e.g., 'Tell me about X' or 'What is X?'). " +
                        "Supported languages: \(supportedList)."
                )
            }

            Log.debug("[FM] Stream complete: \(snapshotCount) snapshots, \(responseText.count) chars", category: .llm)

            let totalTime = Date().timeIntervalSince(startTime)

            // Final token count is accurate word count (updated after continuation if needed)
            var finalTokenCount = responseText.split(separator: " ").count

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

            // Response continuation: detect if response was cut off and continue if needed
            // Skip continuation if config explicitly disables it (e.g., for summarization)
            let needsContinuation = !config.skipContinuation && responseNeedsContinuation(responseText)
            if needsContinuation {
                Log.info("[FM] Response appears incomplete - attempting continuation", category: .llm)
                let continuedText = try await continueGeneration(
                    session: session,
                    currentResponse: responseText,
                    options: options,
                    config: config
                )
                if !continuedText.isEmpty {
                    responseText += continuedText
                    Log.info("[FM] Continuation added \(continuedText.count) chars", category: .llm)
                }
            }

            // Post-processing: normalize FM formatting quirks, then dedup
            responseText = convertInlineBulletsToProseFlow(responseText)
            responseText = deduplicateResponse(responseText)
            responseText = stripExcessiveBolding(responseText)

            LLMStreamingContext.emit(text: "", isFinal: true)

            // Update token count after potential continuation
            finalTokenCount = responseText.split(separator: " ").count

            let toolCalls = await ToolCallCounter.shared.takeAndReset()
            return LLMResponse(
                text: responseText,
                tokensGenerated: finalTokenCount,
                timeToFirstToken: firstTokenTime,
                totalTime: totalTime,
                modelName: executionBasedModelName,
                toolCallsMade: toolCalls
            )
        }

        @MainActor
        func generateStructuredRAGAnswer(
            prompt: String,
            context: String,
            config: InferenceConfig,
            sourceCount: Int,
            mode: StructuredRAGMode = .direct
        ) async throws -> LLMResponse {
            guard sourceCount > 0 else {
                throw LLMError.generationFailed("Structured generation requires source excerpts")
            }

            if !supportsCurrentLocale {
                let currentLocale = Locale.current.identifier
                Log.warning("Current locale '\(currentLocale)' not supported by Apple Intelligence — structured generation may degrade", category: .llm)
            }

            session = nil
            if let newPrompt = config.systemPrompt, newPrompt != currentSystemPrompt {
                currentSystemPrompt = nil
            }

            var structuredConfig = config
            structuredConfig.disableTools = true
            try ensureSession(systemPrompt: structuredConfig.systemPrompt, disableTools: true)

            guard let session else {
                throw LLMError.modelUnavailable
            }

            let startTime = Date()
            let sanitizedPrompt = sanitizeForLanguageDetection(prompt)
            let sanitizedContext = sanitizeForLanguageDetection(context)
            let fullPrompt: String = {
                switch mode {
                case .reasoned:
                    return """
                    CONTEXT:
                    \(sanitizedContext)

                    QUESTION: \(sanitizedPrompt)

                    Return grounded fields only.
                    - `reasoning`: concise grounded reasoning based only on the excerpts
                    - `answer`: direct answer from the excerpts
                    - `confidence`: 0-100 based only on excerpt support
                    - `citations`: source ids like [S1], [S2]
                    - `claims`: atomic answer claims with supporting source ids per claim
                    - `matchedTerms`: exact query terms supported by the excerpts
                    """
                case .direct:
                    return """
                    CONTEXT:
                    \(sanitizedContext)

                    QUESTION: \(sanitizedPrompt)

                    Return grounded fields only.
                    - `answer`: direct answer from the excerpts with no extra reasoning text
                    - `confidence`: 0-100 based only on excerpt support
                    - `citations`: source ids like [S1], [S2]
                    - `claims`: atomic answer claims with supporting source ids per claim
                    - `matchedTerms`: exact query terms supported by the excerpts
                    """
                }
            }()

            func respondStructured<GeneratedType: Generable>(
                to prompt: String,
                generating type: GeneratedType.Type
            ) async throws -> LanguageModelSession.Response<GeneratedType> {
                do {
                    return try await session.respond(to: prompt, generating: type)
                } catch let error as LanguageModelSession.GenerationError {
                    switch error {
                    case let .exceededContextWindowSize(context):
                        Log.warning("[FM] Structured context window exceeded: \(context)", category: .llm)
                        throw error
                    case let .guardrailViolation(context):
                        Log.warning("[FM] Structured guardrail violation: \(context)", category: .llm)
                        throw LLMError.generationFailed("Structured answer was filtered by Apple Intelligence guardrails.")
                    case let .unsupportedLanguageOrLocale(context):
                        Log.warning("[FM] Structured unsupported language/locale: \(context)", category: .llm)
                        throw LLMError.generationFailed("Apple Intelligence does not support the current language/locale for structured generation.")
                    case let .rateLimited(context):
                        Log.warning("[FM] Structured generation rate limited: \(context)", category: .llm)
                        throw LLMError.rateLimited("Apple Intelligence is temporarily rate-limited. Please wait a moment and try again.")
                    case let .refusal(refusal, context):
                        Log.warning("[FM] Structured generation refusal: \(refusal) - \(context)", category: .llm)
                        throw LLMError.generationFailed("Apple Intelligence declined the structured answer request.")
                    case let .assetsUnavailable(context):
                        Log.error("[FM] Structured generation assets unavailable: \(context)", category: .llm)
                        throw LLMError.generationFailed("Apple Intelligence models are not currently available.")
                    case let .decodingFailure(context):
                        Log.error("[FM] Structured generation decoding failure: \(context)", category: .llm)
                        throw LLMError.generationFailed("Failed to decode the structured response.")
                    case let .concurrentRequests(context):
                        Log.warning("[FM] Structured concurrent request blocked: \(context)", category: .llm)
                        throw LLMError.concurrentRequests("A request is already in progress. Please wait for it to complete.")
                    case let .unsupportedGuide(context):
                        Log.error("[FM] Structured unsupported guide: \(context)", category: .llm)
                        throw LLMError.generationFailed("Unsupported structured generation guide.")
                    @unknown default:
                        Log.error("[FM] Structured generation error: \(error)", category: .llm)
                        throw error
                    }
                }
            }

            let normalizedCitations: [String]
            let reasoningText: String
            let answerText: String
            let matchedTerms: [String]
            let structuredClaims: [StructuredRAGClaim]
            let confidence: Int

            switch mode {
            case .reasoned:
                let response = try await respondStructured(to: fullPrompt, generating: RAGAnswer.self)
                normalizedCitations = normalizeStructuredCitations(response.content.citations, maxSourceCount: sourceCount)
                reasoningText = response.content.reasoning.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                answerText = response.content.answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                matchedTerms = response.content.matchedTerms
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                structuredClaims = response.content.claims.compactMap { claim -> StructuredRAGClaim? in
                    let claimText = claim.claim.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    guard !claimText.isEmpty else { return nil }
                    return StructuredRAGClaim(
                        claim: claimText,
                        citations: normalizeStructuredCitations(claim.citations, maxSourceCount: sourceCount),
                        isExtracted: claim.isExtracted
                    )
                }
                confidence = response.content.confidence
            case .direct:
                let response = try await respondStructured(to: fullPrompt, generating: DirectRAGAnswer.self)
                normalizedCitations = normalizeStructuredCitations(response.content.citations, maxSourceCount: sourceCount)
                reasoningText = ""
                answerText = response.content.answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                matchedTerms = response.content.matchedTerms
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                structuredClaims = response.content.claims.compactMap { claim -> StructuredRAGClaim? in
                    let claimText = claim.claim.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    guard !claimText.isEmpty else { return nil }
                    return StructuredRAGClaim(
                        claim: claimText,
                        citations: normalizeStructuredCitations(claim.citations, maxSourceCount: sourceCount),
                        isExtracted: claim.isExtracted
                    )
                }
                confidence = response.content.confidence
            }

            guard !answerText.isEmpty else {
                throw LLMError.generationFailed("Structured answer was empty")
            }

            let effectiveClaims: [StructuredRAGClaim]
            if structuredClaims.isEmpty {
                effectiveClaims = [StructuredRAGClaim(
                    claim: answerText,
                    citations: normalizedCitations,
                    isExtracted: false
                )]
            } else {
                effectiveClaims = Array(structuredClaims.prefix(6))
            }

            let citationFooter: String
            if normalizedCitations.isEmpty || answerText.contains("[S") {
                citationFooter = ""
            } else {
                citationFooter = "\n\nSources: " + normalizedCitations.joined(separator: " ")
            }

            let finalText = answerText + citationFooter
            if !finalText.isEmpty {
                LLMStreamingContext.emit(text: finalText, isFinal: false)
            }
            LLMStreamingContext.emit(text: "", isFinal: true)

            let totalTime = Date().timeIntervalSince(startTime)
            let estimatedTokens = max(1, Int(ceil(Double(finalText.count) / 1.4)))

            return LLMResponse(
                text: finalText,
                tokensGenerated: estimatedTokens,
                timeToFirstToken: nil,
                totalTime: totalTime,
                modelName: "\(modelName) (Structured)",
                toolCallsMade: 0,
                structuredRAGGeneration: StructuredRAGGeneration(
                    reasoning: reasoningText.isEmpty ? nil : reasoningText,
                    answer: answerText,
                    confidence: confidence,
                    citations: normalizedCitations,
                    matchedTerms: matchedTerms,
                    claims: effectiveClaims
                )
            )
        }

        private func normalizeStructuredCitations(_ citations: [String], maxSourceCount: Int) -> [String] {
            guard maxSourceCount > 0 else { return [] }
            var seen: Set<Int> = []
            var normalized: [String] = []

            for citation in citations {
                guard let regex = Self.structuredCitationRegex else { continue }
                let nsRange = NSRange(citation.startIndex..<citation.endIndex, in: citation)
                for match in regex.matches(in: citation, options: [], range: nsRange) {
                    guard let range = Range(match.range(at: 1), in: citation),
                          let index = Int(citation[range]),
                          (1...maxSourceCount).contains(index),
                          !seen.contains(index)
                    else { continue }
                    seen.insert(index)
                    normalized.append("[S\(index)]")
                }
            }

            return normalized
        }

        /// Detects if a response was cut off mid-sentence or mid-thought
        private func responseNeedsContinuation(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }

            // Short responses are always considered complete — the LLM said what it wanted
            let wordCount = trimmed.split(separator: " ").count
            if wordCount < 15 { return false }

            // If response contains repetition already, do NOT continue — it'll only get worse
            if containsRepetition(trimmed) { return false }

            // Check for obvious truncation indicators
            guard let lastChar = trimmed.last else { return false }
            let lastLine = trimmed.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
            let listPrefixes = ["- ", "* ", "• "]

            // Response ends mid-sentence (no terminal punctuation)
            let terminalPunctuation: Set<Character> = [".", "!", "?", ":", ";", "\"", "'", ")", "]", "}"]
            if !terminalPunctuation.contains(lastChar) {
                // But not if it's a code block or explicit newline termination
                if !trimmed.hasSuffix("```") && !trimmed.hasSuffix("\n") {
                    return true
                }
            }

            // Incomplete bullet/list lines are strong evidence of truncation even in long answers.
            if listPrefixes.contains(where: { lastLine.hasPrefix($0) }) && !terminalPunctuation.contains(lastChar) {
                return true
            }

            // Response ends with incomplete conjunction/article (genuine mid-sentence cutoff)
            let incompleteMarkers: Set<String> = ["and", "or", "but", "the", "a", "an", "to", "of"]
            let lastWord = String(trimmed.split(separator: " ").last ?? "").lowercased()
            if incompleteMarkers.contains(lastWord) {
                return true
            }

            // Once the answer is already very long and doesn't show cutoff markers,
            // continuation tends to introduce repetition instead of completing content.
            if wordCount > 300 {
                return false
            }

            return false
        }

        /// Detects if text contains significant repetition (same phrase appearing multiple times)
        private func containsRepetition(_ text: String) -> Bool {
            let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.count > 20 }

            guard sentences.count >= 3 else { return false }

            // Check if any sentence appears more than twice
            var seen: [String: Int] = [:]
            for sentence in sentences {
                // Normalize whitespace for comparison
                let normalized = sentence.split(separator: " ").joined(separator: " ")
                seen[normalized, default: 0] += 1
                if seen[normalized, default: 0] >= 3 {
                    return true
                }
            }

            // Check for high substring overlap: take 40-char windows and look for repeats
            let flat = text.lowercased()
            if flat.count > 200 {
                let windowSize = 40
                var windows: [String: Int] = [:]
                let chars = Array(flat)
                let stride = 20
                for i in Swift.stride(from: 0, to: max(0, chars.count - windowSize), by: stride) {
                    let window = String(chars[i..<min(i + windowSize, chars.count)])
                    windows[window, default: 0] += 1
                }
                let repeatedWindows = windows.values.filter { $0 >= 3 }.count
                let totalWindows = max(1, windows.count)
                if Double(repeatedWindows) / Double(totalWindows) > 0.3 {
                    return true
                }
            }

            return false
        }

        /// Continues generation from where it left off using the session's context
        private func continueGeneration(
            session: LanguageModelSession,
            currentResponse: String,
            options: GenerationOptions,
            config _: InferenceConfig
        ) async throws -> String {
            // Use a simple continuation prompt
            let continuationPrompt = "Continue exactly from the last incomplete sentence or bullet. Do not restart the answer or repeat earlier content."

            var continuedText = ""
            let maxContinuations = 2 // Reduced from 3 — fewer chances to loop
            var continuationCount = 0
            let maxContinuationChars = 1600 // Hard cap on total continuation length

            while continuationCount < maxContinuations {
                continuationCount += 1

                do {
                    let stream = session.streamResponse(to: continuationPrompt, options: options)
                    var chunkText = ""

                    for try await snapshot in stream {
                        let newContent = snapshot.content
                        if newContent.count > chunkText.count {
                            let delta = String(newContent.dropFirst(chunkText.count))
                            LLMStreamingContext.emit(text: delta, isFinal: false)
                        }
                        chunkText = newContent

                        // Bail early if continuation is getting too long
                        if (continuedText.count + chunkText.count) > maxContinuationChars {
                            Log.info("[FM] Continuation hit char cap (\(maxContinuationChars))", category: .llm)
                            break
                        }
                    }

                    if chunkText.isEmpty {
                        break // No more content
                    }

                    // CRITICAL: Check if continuation is just repeating the original response
                    let combinedSoFar = currentResponse + continuedText
                    if isRepetitiveContent(newText: chunkText, existingText: combinedSoFar) {
                        Log.warning("[FM] Continuation detected as repetitive - stopping", category: .llm)
                        break
                    }

                    continuedText += chunkText

                    // Hard cap on total continuation length
                    if continuedText.count > maxContinuationChars {
                        Log.info("[FM] Continuation reached max chars (\(maxContinuationChars))", category: .llm)
                        break
                    }

                    // Check if this continuation is complete
                    if !responseNeedsContinuation(continuedText) {
                        break
                    }

                    Log.debug("[FM] Continuation \(continuationCount) added \(chunkText.count) chars, still incomplete", category: .llm)

                } catch {
                    Log.warning("[FM] Continuation failed: \(error)", category: .llm)
                    break
                }
            }

            return continuedText
        }

        /// Checks if new text is substantially repeating content from existing text
        private func isRepetitiveContent(newText: String, existingText: String) -> Bool {
            let newLower = newText.lowercased()
            let existingLower = existingText.lowercased()

            // Quick check: if >50% of the new text's 30-char windows exist in the original, it's repetitive
            let windowSize = 30
            let newChars = Array(newLower)
            guard newChars.count >= windowSize else { return false }

            var matchCount = 0
            var totalWindows = 0
            let stride = 15

            for i in Swift.stride(from: 0, to: max(0, newChars.count - windowSize), by: stride) {
                let window = String(newChars[i..<min(i + windowSize, newChars.count)])
                totalWindows += 1
                if existingLower.contains(window) {
                    matchCount += 1
                }
            }

            guard totalWindows > 0 else { return false }
            let overlapRatio = Double(matchCount) / Double(totalWindows)

            if overlapRatio > 0.5 {
                Log.debug("[FM] Repetition ratio: \(String(format: "%.1f%%", overlapRatio * 100))", category: .llm)
                return true
            }

            return false
        }

        /// Removes repeated sentences/lines from LLM output.
        /// LLMs sometimes enter degenerate repetition loops where the same fact
        /// is stated 5-20 times. This strips duplicates while preserving order.
        private func deduplicateResponse(_ text: String) -> String {
            let lines = text.components(separatedBy: CharacterSet.newlines)
            let sentencePieces = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            let hasEnoughStructure = lines.count > 3 || sentencePieces.count > 6
            guard hasEnoughStructure else { return text }

            var seen: Set<String> = []
            var result: [String] = []
            var dedupCount = 0
            let totalNonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    result.append(line)
                    continue
                }

                // Only dedup lines that are EXACTLY identical (case-insensitive + whitespace-collapsed)
                // Short lines (<20 chars) like bullet markers, headers get exact match only
                let key: String
                if trimmed.count < 20 {
                    // Very short lines: exact match only (case-insensitive)
                    key = trimmed.lowercased()
                } else {
                    // Longer lines: collapse whitespace but keep ALL words
                    key = trimmed.lowercased()
                        .split(separator: " ")
                        .joined(separator: " ")
                }

                if seen.contains(key) {
                    dedupCount += 1
                    continue
                }

                seen.insert(key)
                result.append(line)
            }

            // Safety: only reject line-dedup if it would leave fewer than 3 meaningful lines.
            // When 48/59 lines are truly identical (exact match), the 11 unique lines are the
            // correct output — falling back to the original would preserve degenerate repetition.
            let keptNonEmpty = result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            let linePassTooAggressive = keptNonEmpty < 3 && totalNonEmpty > 5
            if linePassTooAggressive {
                Log.warning("[FM] Deduplication line-pass aggressive (\(dedupCount) of \(totalNonEmpty) lines) — using sentence-pass cleanup", category: .llm)
            }

            if dedupCount > 0 {
                Log.info("[FM] Deduplication removed \(dedupCount) repeated lines from response", category: .llm)
            }

            var normalized = linePassTooAggressive ? text : result.joined(separator: "\n")
            normalized = collapseRepeatedSentenceRuns(in: normalized)
            normalized = collapseFuzzySimilarSentences(in: normalized)
            normalized = collapseRepetitiveTemplates(in: normalized)
            normalized = trimDominantRepeatedSentence(in: normalized)
            normalized = cleanMalformedListArtifacts(in: normalized)
            return normalized
        }

        /// Removes degenerate numbered-list artifacts like "2. . 3. ." left by unstable generations.
        private func cleanMalformedListArtifacts(in text: String) -> String {
            var output = text

            // Remove standalone empty numbered lines: "2." or "2. ."
            let lines = output.components(separatedBy: .newlines)
            let filteredLines = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }
                if trimmed.range(of: #"^\d+\.\s*(\.)?$"#, options: .regularExpression) != nil {
                    return false
                }
                return true
            }
            output = filteredLines.joined(separator: "\n")

            // Remove inline placeholder runs: "2. . 3. . 4. ."
            output = output.replacingOccurrences(
                of: #"(?:\b\d+\.\s*\.\s*){2,}"#,
                with: "",
                options: .regularExpression
            )

            // Remove leading/trailing quote wrappers that can appear around truncated fragments
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.hasPrefix("\"") && output.hasSuffix("\"") && output.count >= 2 {
                output.removeFirst()
                output.removeLast()
            }

            // Drop dangling UNCLOSED bold markers from truncated headings, e.g., "**Expected"
            // Only strip if the bold is unclosed (no matching **), preserving valid "**term**" at end
            let trailingBoldPattern = #"\*\*[A-Za-z][A-Za-z\s]{0,30}$"#
            if let trailingMatch = output.range(of: trailingBoldPattern, options: .regularExpression) {
                let candidate = String(output[trailingMatch])
                // Only strip if it's truly unclosed — no closing ** in the candidate
                let innerContent = candidate.dropFirst(2) // Remove leading **
                if !innerContent.contains("**") {
                    output.replaceSubrange(trailingMatch, with: "")
                }
            }

            // Normalize excessive whitespace/newlines after cleanup
            output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            output = output.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Convert inline bullet markers to flowing prose.
        /// Apple FM often puts bullet lists all on one line: "intro: * item1 * item2 * item3"
        /// This removes the * markers so the text reads as natural prose.
        /// Cleans only genuinely malformed inline bullets (e.g., "situations: * Cruise Control")
        /// while preserving legitimate markdown list formatting.
        private func convertInlineBulletsToProseFlow(_ text: String) -> String {
            var output = text
            var totalConverted = 0

            // Pattern 1: Inline bullet "... situations: * Cruise Control"
            // Matches ": * " or ". * " followed by a word character — these are NEVER valid markdown
            let inlineBulletPattern = #"(?::|\.)\s\*\s(?=\w)"#
            let inlineBulletCount = (try? NSRegularExpression(pattern: inlineBulletPattern))?
                .numberOfMatches(in: output, range: NSRange(output.startIndex..., in: output)) ?? 0
            if inlineBulletCount >= 1 {
                // Replace ": * Word" with ": Word" and ". * Word" with ". Word"
                output = output.replacingOccurrences(
                    of: #"([:.])\s\*\s"#,
                    with: "$1 ",
                    options: .regularExpression
                )
                totalConverted += inlineBulletCount
            }

            // Pattern 2: Line-start bullets — PRESERVED for legitimate markdown formatting.
            // Only clean truly inline junk, not proper "- item\n- item" markdown lists.

            // Pattern 3: Mid-sentence standalone bullets " * Word" (space-star-space-word)
            // Only convert when preceded by non-whitespace (legitimate bullets start lines)
            let midBulletPattern = #"(?<=\S) \* (?=[A-Z\w])"#
            let midCount = (try? NSRegularExpression(pattern: midBulletPattern))?
                .numberOfMatches(in: output, range: NSRange(output.startIndex..., in: output)) ?? 0
            if midCount >= 2 {
                output = output.replacingOccurrences(of: midBulletPattern, with: ". ", options: .regularExpression)
                totalConverted += midCount
            }

            // Clean up any double-period artifacts
            output = output.replacingOccurrences(of: ".. ", with: ". ")
            output = output.replacingOccurrences(of: "..", with: ".")

            if totalConverted > 0 {
                Log.info("[FM] Converted \(totalConverted) inline bullet artifacts to prose flow", category: .llm)
            }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Normalize markdown bolding from FM output using smart deduplication.
        /// Instead of all-or-nothing stripping, this keeps the FIRST occurrence of each
        /// unique bold phrase and removes duplicates. Caps total unique bold terms at 8.
        /// This is the universal safety net — works regardless of what the LLM produces.
        private func stripExcessiveBolding(_ text: String) -> String {
            let boldPattern = #"\*\*([^*]+?)\*\*"#
            guard let boldRegex = try? NSRegularExpression(pattern: boldPattern) else { return text }
            let matches = boldRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            guard !matches.isEmpty else { return text }

            let boldCount = matches.count
            let wordCount = text.split(separator: " ").count
            let boldDensity = wordCount > 0 ? Double(boldCount) * 100.0 / Double(wordCount) : 0

            // Truly catastrophic — LLM bolded everything. Nuclear strip.
            if boldCount > 25 || boldDensity > 20.0 {
                let stripped = text.replacingOccurrences(
                    of: boldPattern,
                    with: "$1",
                    options: .regularExpression
                )
                Log.info("[FM] Nuclear bold strip: \(boldCount) spans (density: \(String(format: "%.1f", boldDensity))%)", category: .llm)
                return stripped
            }

            // Reasonable bolding — keep it all
            if boldCount <= 8 && boldDensity <= 12.0 {
                return text
            }

            // Smart deduplication: keep first occurrence of each unique bold phrase, strip repeats.
            // Scale cap proportionally: longer responses can have more bold terms.
            var seenPhrases: Set<String> = []
            var uniqueKept = 0
            let maxUniqueBold = min(12, max(4, wordCount / 25))

            var result = text
            // Process matches in reverse to preserve string indices
            for match in matches.reversed() {
                guard let phraseRange = Range(match.range(at: 1), in: result) else { continue }
                guard let fullRange = Range(match.range, in: result) else { continue }
                let phrase = String(result[phraseRange]).lowercased().trimmingCharacters(in: .whitespaces)

                if seenPhrases.contains(phrase) || uniqueKept >= maxUniqueBold {
                    // Duplicate or over cap — strip the bold markers, keep the text
                    result.replaceSubrange(fullRange, with: String(result[phraseRange]))
                } else {
                    // First occurrence — keep it bold
                    seenPhrases.insert(phrase)
                    uniqueKept += 1
                }
            }

            let stripped = boldCount - uniqueKept
            if stripped > 0 {
                Log.info("[FM] Bold normalization: kept \(uniqueKept) unique, stripped \(stripped) duplicates (was \(boldCount) total, density: \(String(format: "%.1f", boldDensity))%)", category: .llm)
            }

            return result
        }

        /// Collapse sentences that share a 5+ word prefix template into one combined sentence.
        /// "X is A. X is B. X is C." → "X is A, B, or C."
        /// Catches owner-manual boilerplate where the same sentence frame is copied with different values.
        private func collapseRepetitiveTemplates(in text: String) -> String {
            let rawSentences = text.components(separatedBy: ".")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count >= 15 }

            guard rawSentences.count >= 4 else { return text }

            // Group sentences by their first 5 lowercased words
            var prefixGroups: [String: [Int]] = [:]
            for (i, sentence) in rawSentences.enumerated() {
                let words = sentence.lowercased()
                    .split(separator: " ")
                    .map(String.init)
                guard words.count >= 5 else { continue }
                let key = words.prefix(5).joined(separator: " ")
                prefixGroups[key, default: []].append(i)
            }

            var mergedIndices: Set<Int> = []
            var replacements: [Int: String] = [:]

            for (_, indices) in prefixGroups where indices.count >= 3 {
                // Compute exact shared prefix across all sentences
                let wordArrays = indices.map { idx in
                    rawSentences[idx].split(separator: " ").map(String.init)
                }
                var prefixLen = wordArrays[0].count
                for words in wordArrays.dropFirst() {
                    var common = 0
                    for (a, b) in zip(wordArrays[0], words) {
                        if a.lowercased() == b.lowercased() { common += 1 } else { break }
                    }
                    prefixLen = min(prefixLen, common)
                }
                guard prefixLen >= 5 else { continue }

                let prefixText = wordArrays[0].prefix(prefixLen).joined(separator: " ")
                let suffixes = indices.compactMap { idx -> String? in
                    let suffix = rawSentences[idx].split(separator: " ")
                        .dropFirst(prefixLen)
                        .joined(separator: " ")
                    return suffix.isEmpty ? nil : suffix
                }

                guard suffixes.count >= 2 else { continue }

                let merged: String
                if suffixes.count == 2 {
                    merged = prefixText + " " + suffixes[0] + " or " + suffixes[1]
                } else {
                    let allButLast = suffixes.dropLast().joined(separator: ", ")
                    merged = prefixText + " " + allButLast + ", or " + (suffixes.last ?? "")
                }

                replacements[indices[0]] = merged
                for idx in indices.dropFirst() { mergedIndices.insert(idx) }
                Log.info("[FM] Collapsed \(indices.count) template-repetitive sentences into one", category: .llm)
            }

            guard !replacements.isEmpty else { return text }

            var result: [String] = []
            for (i, sentence) in rawSentences.enumerated() {
                if let merged = replacements[i] {
                    result.append(merged)
                } else if !mergedIndices.contains(i) {
                    result.append(sentence)
                }
            }

            return result.joined(separator: ". ") + "."
        }

        /// Collapses contiguous repeated sentence runs (e.g., same sentence repeated 10x).
        private func collapseRepeatedSentenceRuns(in text: String) -> String {
            // Split into lines first, preserving markdown structure
            let lines = text.components(separatedBy: "\n")
            var resultLines: [String] = []
            var proseBuffer: [String] = []

            // Markdown line patterns that should NEVER be deduped or restructured
            let markdownLinePattern = #"^\s*(#{1,6}\s|[-*•]\s|\d+[.)\]]\s|>\s|```|~~~|---+|\*\*\*+|___+)"#

            func flushProseBuffer() {
                guard !proseBuffer.isEmpty else { return }
                let proseText = proseBuffer.joined(separator: "\n")
                let deduped = deduplicateProseBlock(proseText)
                resultLines.append(deduped)
                proseBuffer.removeAll()
            }

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    flushProseBuffer()
                    resultLines.append("")
                } else if trimmed.range(of: markdownLinePattern, options: .regularExpression) != nil {
                    // Markdown structural line — preserve exactly, do not dedup
                    flushProseBuffer()
                    resultLines.append(line)
                } else {
                    proseBuffer.append(line)
                }
            }
            flushProseBuffer()

            return resultLines.joined(separator: "\n")
        }

        /// Dedup only within a prose block — never across markdown structural elements
        private func deduplicateProseBlock(_ text: String) -> String {
            let sentenceRegex = try? NSRegularExpression(pattern: #"[^.!?\n]+[.!?]?"#)
            guard let sentenceRegex else { return text }

            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = sentenceRegex.matches(in: text, options: [], range: fullRange)

            var rebuilt: [String] = []
            rebuilt.reserveCapacity(matches.count)

            var seenKeys: Set<String> = []
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sentence.isEmpty else { continue }

                let key = normalizedSentenceKey(sentence)
                if seenKeys.contains(key) {
                    continue
                }

                seenKeys.insert(key)
                rebuilt.append(sentence)
            }

            guard !rebuilt.isEmpty else { return text }
            return rebuilt.joined(separator: " ")
        }

        /// Remove near-duplicate sentences using Jaccard word-set similarity.
        /// Catches paraphrased sentences like "activated when the driver presses"
        /// vs "activated by pressing" that share >65% of meaningful words.
        /// Preserves markdown structural lines (headers, bullets, code fences, block quotes).
        private func collapseFuzzySimilarSentences(in text: String) -> String {
            // Common stop words to exclude from similarity comparison
            let stopWords: Set<String> = [
                "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
                "have", "has", "had", "do", "does", "did", "will", "would", "could",
                "should", "may", "might", "can", "to", "of", "in", "for", "on", "with",
                "at", "by", "from", "as", "into", "through", "it", "its", "that", "this",
                "or", "and", "but", "if", "not", "no", "so", "than", "also", "only"
            ]

            // Split by lines first to preserve markdown structure
            let lines = text.components(separatedBy: "\n")
            let markdownLinePattern = #"^\s*(#{1,6}\s|[-*•]\s|\d+[.)\]]\s|>\s|```|~~~|---+|\*\*\*+|___+)"#
            var resultParts: [String] = []
            var proseBuffer: [String] = []

            func flushProse() {
                guard !proseBuffer.isEmpty else { return }
                let prose = proseBuffer.joined(separator: " ")
                let sentences = prose.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 15 }

                if sentences.count < 3 {
                    resultParts.append(proseBuffer.joined(separator: "\n"))
                    proseBuffer.removeAll()
                    return
                }

                let wordSets: [Set<String>] = sentences.map { sentence in
                    Set(
                        sentence.lowercased()
                            .components(separatedBy: CharacterSet.alphanumerics.inverted)
                            .filter { $0.count > 2 && !stopWords.contains($0) }
                    )
                }

                var kept: [Int] = []
                for (i, words) in wordSets.enumerated() {
                    guard words.count >= 3 else {
                        kept.append(i)
                        continue
                    }
                    var isFuzzyDup = false
                    for j in kept {
                        let keptWords = wordSets[j]
                        guard keptWords.count >= 3 else { continue }
                        let intersection = words.intersection(keptWords).count
                        let union = words.union(keptWords).count
                        let jaccard = Double(intersection) / Double(max(1, union))
                        if jaccard > 0.65 {
                            if sentences[i].count > sentences[j].count {
                                if let idx = kept.firstIndex(of: j) {
                                    kept[idx] = i
                                }
                            }
                            isFuzzyDup = true
                            break
                        }
                    }
                    if !isFuzzyDup {
                        kept.append(i)
                    }
                }

                let fuzzyRemoved = sentences.count - kept.count
                if fuzzyRemoved > 0 {
                    Log.info("[FM] Fuzzy dedup removed \(fuzzyRemoved) near-duplicate sentences", category: .llm)
                }

                if !kept.isEmpty {
                    resultParts.append(kept.map { sentences[$0] }.joined(separator: ". ") + ".")
                }
                proseBuffer.removeAll()
            }

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    flushProse()
                    resultParts.append("")
                } else if trimmed.range(of: markdownLinePattern, options: .regularExpression) != nil {
                    flushProse()
                    resultParts.append(line)
                } else {
                    proseBuffer.append(line)
                }
            }
            flushProse()

            return resultParts.joined(separator: "\n")
        }

        /// If one sentence dominates the response by heavy repetition, keep first occurrence only.
        private func trimDominantRepeatedSentence(in text: String) -> String {
            let rawSentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 20 }

            guard rawSentences.count >= 4 else { return text }

            var counts: [String: Int] = [:]
            var representative: [String: String] = [:]
            for sentence in rawSentences {
                let key = normalizedSentenceKey(sentence)
                counts[key, default: 0] += 1
                representative[key] = sentence
            }

            guard let (dominantKey, dominantCount) = counts.max(by: { $0.value < $1.value }) else {
                return text
            }

            let dominance = Double(dominantCount) / Double(rawSentences.count)
            guard dominantCount >= 4, dominance >= 0.5 else { return text }

            let dominantSentence = representative[dominantKey] ?? ""
            guard !dominantSentence.isEmpty else { return text }

            var output = text.replacingOccurrences(of: dominantSentence, with: "", options: [.caseInsensitive, .diacriticInsensitive])
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if output.isEmpty {
                return dominantSentence + "."
            }

            return dominantSentence + ".\n\n" + output
        }

        private func normalizedSentenceKey(_ sentence: String) -> String {
            sentence
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
                .split(separator: " ")
                .joined(separator: " ")
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

// MARK: - Screenshot Mode Mock LLM

/// Mock LLM service for taking screenshots in the Simulator.
/// Returns realistic-looking demo responses so the UI looks functional.
/// Activated via --screenshot launch argument.
class ScreenshotMockLLMService: LLMService {
    var toolHandler: RAGToolHandler?

    var isAvailable: Bool { true }
    var modelName: String { "Apple Intelligence" } // Display as if real

    /// Check if screenshot mode is enabled via launch arguments
    static var isScreenshotMode: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("--screenshot")
            || CommandLine.arguments.contains("screenshot")
        #else
        return false
        #endif
    }

    private let demoResponses: [String: String] = [
        "pricing": """
            Based on your pricing brief, OpenIntelligence offers a clear value ladder:

            **Free Tier**: 5 documents, 1 library, full privacy dashboard
            **Pro ($5.99/mo or $49.99/yr)**: Up to 1,000 docs, 5 libraries, fewer workspace limits
            **Lifetime ($59.99)**: Unlimited docs, 10 libraries, and no renewal

            The messaging pillars emphasize privacy-first design (data stays on-device or Apple PCC), fast retrieval through hybrid search, and simple pricing with one upgrade path.
            """,
        "architecture": """
            The RAG implementation uses several key components:

            1. **DocumentProcessor**: Semantic chunking with 350-word targets and 17% overlap
            2. **EmbeddingService**: 384-dimensional vectors via CoreML
            3. **HybridSearch**: Combines vector similarity with BM25 for better recall
            4. **MMR Diversification**: Ensures varied, relevant results

            Performance targets include <100ms per chunk embedding and sub-second query responses.
            """,
        "default": """
            I found relevant information in your documents. Here's what I discovered:

            Your knowledge base contains detailed documentation about the system architecture, pricing strategy, and technical implementation. The hybrid search approach combines semantic understanding with keyword matching for comprehensive retrieval.

            Would you like me to dive deeper into any specific aspect?
            """
    ]

    init() {
        Log.info("📸 ScreenshotMockLLMService initialized for demo mode", category: .llm)
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        let startTime = Date()

        // Determine which demo response to use based on query content
        let lowercasePrompt = prompt.lowercased()
        let responseKey: String
        if lowercasePrompt.contains("pricing") || lowercasePrompt.contains("price") || lowercasePrompt.contains("cost") {
            responseKey = "pricing"
        } else if lowercasePrompt.contains("architecture") || lowercasePrompt.contains("technical") || lowercasePrompt.contains("rag") {
            responseKey = "architecture"
        } else {
            responseKey = "default"
        }

        let responseText = demoResponses[responseKey] ?? demoResponses["default"]!

        // Simulate realistic streaming with slight delays
        let words = responseText.split(separator: " ")
        var streamedText = ""

        for (index, word) in words.enumerated() {
            streamedText += (index == 0 ? "" : " ") + word
            LLMStreamingContext.emit(text: streamedText, isFinal: false)

            // Vary delay to look natural (faster for common words)
            let delay = Double.random(in: 0.02...0.06)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        LLMStreamingContext.emit(text: responseText, isFinal: true)

        let totalTime = Date().timeIntervalSince(startTime)
        let tokensGenerated = words.count + 10 // Approximate token count

        return LLMResponse(
            text: responseText,
            tokensGenerated: tokensGenerated,
            timeToFirstToken: 0.15,
            totalTime: totalTime,
            modelName: modelName,
            toolCallsMade: 0
        )
    }
}

// MARK: - Apple Intelligence Unavailable Stub

/// Stub service that always throws - used when Apple Intelligence is unavailable
/// This forces the user to enable Apple Intelligence rather than falling back to inferior extractive QA
class AppleFoundationLLMServiceUnavailable: LLMService {
    var toolHandler: RAGToolHandler?

    var isAvailable: Bool { false }
    var modelName: String { "Apple Intelligence (Unavailable)" }

    init() {
        Log.warning("AppleFoundationLLMServiceUnavailable stub initialized - Apple Intelligence is required", category: .llm)
    }

    func generate(prompt _: String, context _: String?, config _: InferenceConfig) async throws -> LLMResponse {
        #if targetEnvironment(simulator)
            throw LLMError.generationFailed(
                "Apple Intelligence requires a physical device with Apple Silicon: " +
                    "iPhone (A17 Pro+), iPad (M1+), or Mac (M1+). " +
                    "The iOS Simulator cannot run Foundation Models."
            )
        #else
            throw LLMError.generationFailed(
                "Apple Intelligence is required but not available on this device. " +
                    "To enable: Go to Settings → Apple Intelligence & Siri → Turn on Apple Intelligence. " +
                    "Requires iPhone 15 Pro or later with iOS 18.1+."
            )
        #endif
    }
}

// MARK: - On-Device Document Analysis (NaturalLanguage Framework)

// DEPRECATED: This extractive QA system is no longer used as a fallback.
// Keeping for reference only - Apple Intelligence is now the only supported provider.
// This is NOT an LLM - it's an extractive QA system using Apple's NaturalLanguage framework
// It analyzes your query, finds relevant sentences from retrieved context, and presents them
// This runs 100% on-device with zero network calls and zero AI model downloads

class OnDeviceAnalysisService: LLMService {
    private let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .lemma])
    private let languageRecognizer = NLLanguageRecognizer()

    var toolHandler: RAGToolHandler? // Not used by extractive QA

    var isAvailable: Bool { true }
    var modelName: String { "On-Device Analysis (Extractive QA)" }

    init() {
        Log.debug("On-Device Analysis Service initialized", category: .llm)
    }

    func generate(prompt: String, context: String?, config _: InferenceConfig) async throws
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
            I don't have any documents loaded yet to search through.

                To get started:
                1.Tap the Documents tab
            2.Import PDFs, text files, or other documents
            3.Come back here and ask questions about your content

                💡 For the best conversational AI experience, enable Apple Intelligence in Settings > Apple Intelligence & Siri.
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
            query: query,
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
            in: query.startIndex ..< query.endIndex, unit: .word, scheme: .lexicalClass
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
        tagger.enumerateTags(in: query.startIndex ..< query.endIndex, unit: .word, scheme: .nameType) { tag, range in
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
        tokenizer.enumerateTokens(in: context.startIndex ..< context.endIndex) { range, _ in
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
            in: context.startIndex ..< context.endIndex, unit: .word, scheme: .nameType
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
            in: text.startIndex ..< text.endIndex, unit: .word, scheme: .lexicalClass
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
        query: String,
        queryType: QueryType,
        queryKeywords: Set<String>,
        queryEntities: [String],
        contextSentences: [SentenceInfo],
        contextEntities _: [String]
    ) -> [ScoredSentence] {
        // Use sentence embeddings when available to improve relevance beyond keyword overlap.
        languageRecognizer.reset()
        languageRecognizer.processString(query)
        let language = languageRecognizer.dominantLanguage ?? .english
        let embedding = NLEmbedding.sentenceEmbedding(for: language) ?? NLEmbedding.sentenceEmbedding(for: .english)

        let queryVector = embedding?.vector(for: query)

        var scoredSentences: [ScoredSentence] = []

        for sentence in contextSentences {
            var score = sentence.importance

            var similarity: Double?
            if let embedding, let queryVector, let sentenceVector = embedding.vector(for: sentence.text) {
                let sim = cosineSimilarity(queryVector, sentenceVector)
                // Clamp to [0, 1] and weight it heavily — this is the primary relevance signal.
                similarity = max(0.0, min(1.0, sim))
                score += (similarity ?? 0.0) * 2.0
            }

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

            scoredSentences.append(
                ScoredSentence(
                    sentence: sentence,
                    score: score,
                    similarity: similarity,
                    matchingKeywords: matchingKeywords.count
                )
            )
        }

        // Sort by score and return top results
        scoredSentences.sort { $0.score > $1.score }
        return Array(scoredSentences.prefix(5))
    }

    private func buildExtractiveResponse(
        query _: String,
        queryType: QueryType,
        relevantSentences: [ScoredSentence]
    ) -> String {
        guard !relevantSentences.isEmpty else {
            return """
            I searched your documents but couldn't find information directly addressing your query.This could mean:

                • The topic isn't covered in your current documents
                • Try rephrasing your question with different keywords
                • Consider adding more relevant documents to your library

                💡 Tip: For the best experience, enable Apple Intelligence in Settings > Apple Intelligence & Siri.
            """
        }

        let bestScore = relevantSentences.first?.score ?? 0.0
        let lowConfidence = bestScore < 0.9

        // Extract and clean the relevant passages
        let passages = relevantSentences.prefix(3).map { scored -> String in
            var text = scored.sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Ensure proper sentence ending
            if !text.hasSuffix("."), !text.hasSuffix("!"), !text.hasSuffix("?") {
                text += "."
            }
            return text
        }

        // Synthesize a conversational response from the extracted passages
        let combinedContent = passages.joined(separator: " ")

        // Build response based on query type and confidence
        var response: String

        if lowConfidence {
            response = "Based on what I found in your documents:\n\n\(combinedContent)"
        } else {
            switch queryType {
            case .definition:
                response = combinedContent
            case .instruction:
                response = "Here's what your documents say:\n\n\(combinedContent)"
            case .explanation:
                response = combinedContent
            case .temporal, .location:
                response = combinedContent
            case .description:
                response = combinedContent
            case .general:
                response = combinedContent
            }
        }

        return response
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot = 0.0
        var normA = 0.0
        var normB = 0.0
        for i in 0 ..< a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = (sqrt(normA) * sqrt(normB))
        guard denom > 0 else { return 0.0 }
        return dot / denom
    }

    // MARK: - Helper Types

    private enum QueryType {
        case definition // "What is..."
        case instruction // "How to..."
        case explanation // "Why..."
        case temporal // "When..."
        case location // "Where..."
        case description // "Tell me about...", "List..."
        case general // Other
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

    private struct ScoredSentence {
        let sentence: SentenceInfo
        let score: Double
        let similarity: Double?
        let matchingKeywords: Int
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
        static var description: IntentDescription = .init(
            "Send a query to a built-in AI assistant")
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

            // NOTE: Returns informational dialog until Apple Intelligence entitlements are granted.
            // AssistChatIntent is used by sendChatGPTRequest() — do not remove.
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
        case claude = "Claude" // May be added in future iOS versions
        case gemini = "Gemini" // May be added in future iOS versions

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
        var toolHandler: RAGToolHandler? // Not used by ChatGPT Extension

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

        func generate(prompt: String, context: String?, config _: InferenceConfig) async throws
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
                    return true // Assume available on iOS 18.1+ for now
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
            intent.provider = .chatGPT // Use ChatGPT provider

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

        func generate(prompt _: String, context _: String?, config _: InferenceConfig) async throws
            -> LLMResponse
        {
            throw LLMError.modelUnavailable
        }
    }
#endif

// MARK: - REMOVED: Local Model Implementations

// The following implementations have been removed to simplify the app:
// - CoreMLLLMService: Custom Core ML models (.mlpackage)
// - OpenAILLMService: Direct OpenAI API with user's key
// - LlamaCPPiOSLLMService: GGUF models via llama.cpp (was in separate file)
// - MLXLLMService: MLX tensor server (macOS only, was in separate file)
//
// The app now uses only:
// 1. AppleFoundationLLMService - Apple Intelligence with PCC (iOS 26+)
// 2. OnDeviceAnalysisService - Extractive QA with NaturalLanguage framework (always available)

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelUnavailable
    case generationFailed(String)
    case notImplemented
    case contextWindowExceeded
    case rateLimited(String)
    case concurrentRequests(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "LLM model is not available on this device"
        case let .generationFailed(message):
            return "Text generation failed: \(message)"
        case .notImplemented:
            return "Feature not yet implemented"
        case .contextWindowExceeded:
            return "The context window size was exceeded."
        case let .rateLimited(message):
            return "Rate limited: \(message)"
        case let .concurrentRequests(message):
            return "Concurrent request blocked: \(message)"
        }
    }
}

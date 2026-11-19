//
//  LLMService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import CoreML
import Foundation
import NaturalLanguage
import os

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Apple Intelligence Framework Imports (iOS 18.1+)

// These frameworks provide access to Apple's AI capabilities:
// - FoundationModels: On-device and Private Cloud Compute LLMs
// - AppIntents: Siri integration and system AI service access
// - AssistantServices: ChatGPT Extension and other assistant providers

#if canImport(AppIntents) && !OPENINTELLIGENCE_ENGINE_SDK
    import AppIntents
#endif

/// Protocol defining the interface for LLM inference engines
/// This abstraction enables switching between Foundation Models and Core ML
protocol LLMService {
    /// Generate a response given a prompt and optional context
    func generate(
        prompt: String, context: String?, config: InferenceConfig
    ) async throws
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
    let reasoning: String?
    let isFinal: Bool

    init(text: String, reasoning: String? = nil, isFinal: Bool) {
        self.text = text
        self.reasoning = reasoning
        self.isFinal = isFinal
    }
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

    /// The chat's handler, parked while a Deep Think or Maximum answer is being reasoned out.
    ///
    /// Those modes make dozens of model calls before their answer exists, and every one of them
    /// streams through `handler`. `AgenticOrchestrator.execute` therefore clears `handler` for the
    /// whole run and parks the chat's here, and the calls that write the final answer stream
    /// through `answerHandler`. Until 5.4 the chat passed no handler at all in those modes, so the
    /// answer appeared all at once when every later stage had finished.
    @TaskLocal static var finalAnswerHandler: LLMStreamHandler?

    /// Where the text of a final answer streams: the parked chat handler inside an agentic run,
    /// the ordinary one anywhere else.
    static var answerHandler: LLMStreamHandler? {
        // Returned directly rather than bound: an `if let` binding or `??` converts the task-local
        // closure and draws a Sendable warning, while a plain return does not.
        if finalAnswerHandler != nil { return finalAnswerHandler }
        return handler
    }

    static func emit(text: String, reasoning: String? = nil, isFinal: Bool) {
        guard let handler = handler else { return }
        Task {
            await handler(LLMStreamEvent(text: text, reasoning: reasoning, isFinal: isFinal))
        }
    }
}

// MARK: - Tool Protocol Implementations for Function Calling
// Moved to FoundationModelToolRegistry.swift

/// Response from an LLM generation request
/// What Apple reports about the work it actually did for one generation.
///
/// Every figure here comes from `LanguageModelSession.usage`, new in iOS and macOS 27. Until this
/// existed the app could only report what it *asked* for; these are what the model spent.
///
/// `reasoningTokens` is the useful one and the reason this type exists. It is the only signal in
/// the public SDK that distinguishes a model that reasoned from one that answered directly, which
/// makes it the cheapest available proof that Private Cloud Compute did the work rather than a
/// silent on-device fallback. `LanguageModelSession.Response` carries no route or backend field,
/// so the app's own `actualRoute` is otherwise the only claim about where an answer came from,
/// and it is a claim about intent rather than an observation of outcome.
/// `[evidence_level: code_verified, confidence: exact, evidence_source:
/// FoundationModels.swiftinterface, Xcode 27A266a: LanguageModelSession.usage is
/// @available(iOS 27.0, macOS 27.0, ...), Usage.Output declares totalTokenCount and
/// reasoningTokenCount, Usage.Input declares totalTokenCount and cachedTokenCount]`
nonisolated struct GenerationUsage: Equatable, Codable, Sendable {
    /// Tokens the model produced, as Apple counts them, not as the app counts words.
    let outputTokens: Int
    /// Of those, the ones spent reasoning rather than writing. Zero on the on-device model,
    /// which does not support reasoning at all.
    let reasoningTokens: Int
    /// Tokens in the prompt Apple actually processed.
    let inputTokens: Int
    /// Of those, the ones served from cache rather than recomputed. Nothing in the app has ever
    /// looked at prompt caching; this is the first measurement of it.
    let cachedInputTokens: Int

    /// True when the model demonstrably reasoned. Not a substitute for the route, but the only
    /// outcome-based evidence available that a reasoning-capable backend served the request.
    var didReason: Bool { reasoningTokens > 0 }

    var summary: String {
        "in=\(inputTokens)(cached \(cachedInputTokens)) out=\(outputTokens) reasoning=\(reasoningTokens)"
    }

    /// Two generations' figures added up (5.7): an answer makes several model calls, and its count is all of them.
    static func + (lhs: GenerationUsage, rhs: GenerationUsage) -> GenerationUsage {
        GenerationUsage(
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningTokens: lhs.reasoningTokens + rhs.reasoningTokens,
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens)
    }
}

/// Adds up Apple's usage over every model call one answer makes (5.7). `RAGService.query` sets one for the
/// answer, `LLMService` adds each generation's figures where it reads them, and `finalizeResponse` puts the
/// total in the answer's metadata. Deep Think and Maximum make several calls, and Standard can rewrite the
/// question and check the answer as well as write it, so the total is what the answer cost, not its last call.
nonisolated final class AnswerUsageTally: @unchecked Sendable {
    @TaskLocal static var current: AnswerUsageTally?
    private let lock = NSLock()
    private var sum: GenerationUsage?

    func add(_ usage: GenerationUsage?) {
        guard let usage else { return }
        lock.lock()
        sum = sum.map { $0 + usage } ?? usage
        lock.unlock()
    }

    var total: GenerationUsage? {
        lock.lock()
        defer { lock.unlock() }
        return sum
    }
}

/// What "tokens per second" means everywhere in the app (5.8, 2026-11-18): how fast the answer's text was written.
///
/// It is the answer's output tokens over the time from its first visible text to its last, so reading the prompt
/// (prefill, up to about 6,000 tokens on device), retrieval and every Deep Think step before the answer are left out.
/// Until 5.8 the saved figure divided by the whole call, prefill included, and Deep Think and Maximum divided every
/// call's tokens by the whole run, so the bar read 1 to 5 while the answer was visibly written faster.
nonisolated enum AnswerWritingSpeed {
    /// A writing window shorter than this gives no rate: an answer that arrives in one or two pieces has no measurable
    /// writing time, and dividing by a few milliseconds reads as thousands of tokens per second.
    static let minimumWindow: TimeInterval = 0.25

    /// Tokens over the writing window, `lastTextAt - firstTextAt` (seconds from any common origin). Nil when the
    /// window is unknown or shorter than `minimumWindow`, or when no tokens were written.
    static func tokensPerSecond(writtenTokens: Int, firstTextAt: TimeInterval?, lastTextAt: TimeInterval?) -> Float? {
        guard let firstTextAt, let lastTextAt, writtenTokens > 0 else { return nil }
        let window = lastTextAt - firstTextAt
        guard window >= minimumWindow else { return nil }
        return Float(Double(writtenTokens) / window)
    }

    /// The answer's written tokens. Apple's count (`GenerationUsage`, iOS and macOS 27) less its reasoning tokens when
    /// that count covers only the answer's text; otherwise the app's estimator on the text
    /// (`FoundationModelTokenBudget.estimateTokens`, 1.4 characters a token on device, 2.5 in the cloud).
    /// `usageCoversText` is false when the call also wrote tool calls, a continuation or a resumed tail, which
    /// Apple's count includes and the writing window does not.
    static func writtenTokens(usage: GenerationUsage?, usageCoversText: Bool, text: String, onDevice: Bool) -> Int {
        if usageCoversText, let usage {
            let written = usage.outputTokens - usage.reasoningTokens
            if written > 0 { return written }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return FoundationModelTokenBudget.estimateTokens(for: trimmed, isAppleFMOnDevice: onDevice)
    }

    /// The live figure while an answer streams into the chat: tokens received after the first piece over the time
    /// since that piece arrived. The first piece is left out of the count because it arrived at the window's start.
    /// Zero (the bar shows "–") until text has been written for `minimumWindow`.
    static func liveTokensPerSecond(
        charactersAfterFirstPiece: Int, elapsedSinceFirstPiece: TimeInterval, onDevice: Bool
    )
        -> Double
    {
        guard elapsedSinceFirstPiece >= minimumWindow, charactersAfterFirstPiece > 0 else { return 0 }
        let tokens = FoundationModelTokenBudget.estimateTokens(
            charsCount: charactersAfterFirstPiece, isAppleFMOnDevice: onDevice)
        return Double(tokens) / elapsedSinceFirstPiece
    }

    /// One model call made during a Deep Think or Maximum run: its text, its writing speed, and whether it streamed
    /// into the chat (`LLMStreamingContext.answerHandler`, the calls that write the final answer).
    struct Call: Sendable, Equatable {
        let text: String
        let tokensPerSecond: Float?
        let streamedToChat: Bool
    }

    /// The writing speed of the call whose text became the final answer: the latest call of at least 60 characters
    /// whose text the answer contains (matched on a 60-character slice from the call's middle, which the answer's
    /// cleanup of openings, endings and links leaves alone), else the latest call that streamed into the chat, else
    /// nil. A shorter call (a check's "supported", a value) is never taken: its text can sit inside any answer.
    static func finalAnswerSpeed(finalAnswer: String, calls: [Call]) -> Float? {
        let answer = normalized(finalAnswer)
        if !answer.isEmpty {
            for call in calls.reversed() {
                let text = normalized(call.text)
                guard text.count >= 60 else { continue }
                let probeLength = 60
                let start = text.index(text.startIndex, offsetBy: (text.count - probeLength) / 2)
                let probe = text[start..<text.index(start, offsetBy: probeLength)]
                if answer.contains(probe) { return call.tokensPerSecond }
            }
        }
        return calls.last(where: \.streamedToChat)?.tokensPerSecond
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}

/// Collects the model calls of one Deep Think or Maximum run (5.8), so the answer's tokens per second is the final
/// answer's own writing speed (`AnswerWritingSpeed.finalAnswerSpeed`). Bound by `executeAgenticQuery` around the
/// orchestrator; `generateWithProperConsent`, which every synthesis goes through, records each call.
nonisolated final class AgenticAnswerWritingMeter: @unchecked Sendable {
    @TaskLocal static var current: AgenticAnswerWritingMeter?
    private let lock = NSLock()
    private var recorded: [AnswerWritingSpeed.Call] = []

    func record(text: String, tokensPerSecond: Float?, streamedToChat: Bool) {
        let call = AnswerWritingSpeed.Call(text: text, tokensPerSecond: tokensPerSecond, streamedToChat: streamedToChat)
        lock.lock()
        recorded.append(call)
        lock.unlock()
    }

    var calls: [AnswerWritingSpeed.Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

struct LLMResponse {
    let text: String
    let tokensGenerated: Int
    let timeToFirstToken: TimeInterval?
    let totalTime: TimeInterval
    let modelName: String?  // Actual model used (includes execution location)
    let toolCallsMade: Int  // Number of tool calls executed (for agentic RAG metrics)
    let structuredRAGGeneration: StructuredRAGGeneration?
    let executionReceipt: ModelExecutionReceipt?
    /// Apple's own accounting for this generation. `nil` below iOS/macOS 27, where the API does
    /// not exist, and `nil` on the non-Apple paths.
    let usage: GenerationUsage?
    /// True when the model failed partway and this is the text it had streamed so far (5.8). A caller that needs the
    /// whole text (Deep Think's synthesis) must not take it as finished: on the owner's iPhone on 2026-11-10 a synthesis
    /// cut off at 37 tokens when iOS took back the background time was saved as the answer, ending at "or **dementia".
    let streamCutOff: Bool
    /// True when what cut the stream off was Apple's guardrail (`ModelErrorClassifier.Kind.contentFiltered`, 5.8): the
    /// text is the start of an answer the model was stopped from giving, so it is a refusal and never goes back into a
    /// prompt (`ConversationContextRules`).
    let cutOffByGuardrail: Bool

    init(
        text: String,
        tokensGenerated: Int,
        timeToFirstToken: TimeInterval?,
        totalTime: TimeInterval,
        modelName: String?,
        toolCallsMade: Int,
        structuredRAGGeneration: StructuredRAGGeneration? = nil,
        executionReceipt: ModelExecutionReceipt? = nil,
        usage: GenerationUsage? = nil,
        streamCutOff: Bool = false,
        cutOffByGuardrail: Bool = false,
        writingSpeed: WritingSpeed = .notMeasured
    ) {
        self.writingSpeed = writingSpeed
        self.streamCutOff = streamCutOff
        self.cutOffByGuardrail = cutOffByGuardrail
        self.text = text
        self.tokensGenerated = tokensGenerated
        self.timeToFirstToken = timeToFirstToken
        self.totalTime = totalTime
        self.modelName = modelName
        self.toolCallsMade = toolCallsMade
        self.structuredRAGGeneration = structuredRAGGeneration
        self.executionReceipt = executionReceipt
        self.usage = usage
    }

    /// The answer's writing speed as the generating call measured it (5.8, `AnswerWritingSpeed`): `.measured(nil)`
    /// when it watched the text arrive and found no writing window to measure, `.notMeasured` on paths that did not
    /// watch the stream.
    nonisolated enum WritingSpeed: Sendable, Equatable {
        case notMeasured
        case measured(Float?)
    }
    let writingSpeed: WritingSpeed

    /// How fast this response's text was written (5.8, `AnswerWritingSpeed`): output tokens over the time from the
    /// first text to the last, never over the whole call. Until 5.8 this was `tokensGenerated / totalTime`, which
    /// counted reading the prompt as writing time. Where the call measured it, that figure; otherwise
    /// `tokensGenerated` over `totalTime - timeToFirstToken`, nil without a time to first token.
    var tokensPerSecond: Float? {
        switch writingSpeed {
        case .measured(let speed):
            return speed
        case .notMeasured:
            return AnswerWritingSpeed.tokensPerSecond(
                writtenTokens: tokensGenerated, firstTextAt: timeToFirstToken, lastTextAt: totalTime)
        }
    }
}

// MARK: - Screenshot Mode Mock LLM

/// Mock LLM service for taking screenshots in the Simulator.
/// Returns realistic-looking demo responses so the UI looks functional.
/// Activated via --screenshot launch argument.
class ScreenshotMockLLMService: LLMService {
    var toolHandler: RAGToolHandler?

    var isAvailable: Bool { true }
    var modelName: String { "Apple Intelligence" }  // Display as if real

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
        "roadmap": """
        Based on your roadmap brief, OpenIntelligence is focused on a clear prototype path:

        **Ingestion**: improve file import, parsing coverage, and document normalization.
        **Retrieval**: strengthen hybrid search, re-ranking, and library-scoped context selection.
        **Review**: make citations, source snippets, and warning signals easier to inspect.

        The implementation emphasizes local-first files, source-backed answers, and visible retrieval behavior.
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

        Your knowledge base contains detailed documentation about the system architecture, retrieval pipeline, and technical implementation. The hybrid search approach combines semantic understanding with keyword matching for comprehensive retrieval.

        Would you like me to dive deeper into any specific aspect?
        """,
    ]

    init() {
        Log.info("📸 ScreenshotMockLLMService initialized for demo mode", category: .llm)
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        let startTime = Date()

        // Determine which demo response to use based on query content
        let lowercasePrompt = prompt.lowercased()
        let responseKey: String
        if lowercasePrompt.contains("roadmap") || lowercasePrompt.contains("plan") || lowercasePrompt.contains("next") {
            responseKey = "roadmap"
        } else if lowercasePrompt.contains("architecture") || lowercasePrompt.contains("technical")
            || lowercasePrompt.contains("rag")
        {
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
        let tokensGenerated = words.count + 10  // Approximate token count

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
        Log.warning(
            "AppleFoundationLLMServiceUnavailable stub initialized - Apple Intelligence is required", category: .llm)
    }

    func generate(prompt _: String, context _: String?, config _: InferenceConfig) async throws -> LLMResponse {
        #if targetEnvironment(simulator)
            throw LLMError.generationFailed(
                "Apple Intelligence requires a physical device: \(AppleIntelligenceCopy.supportedDevices). "
                    + "The iOS Simulator cannot run Foundation Models."
            )
        #else
            throw LLMError.modelUnavailable
        #endif
    }
}

// MARK: - REMOVED: Local Model Implementations

// The following implementations have been removed to simplify the app:
// - CoreMLLLMService: Custom Core ML models (.mlpackage)
// - OpenAILLMService: Direct OpenAI API with user's key
// - LlamaCPPiOSLLMService: GGUF models via llama.cpp (was in separate file)
// - MLXLLMService: MLX tensor server (macOS only, was in separate file)
//
// The app now uses only:
// 1. AppleFoundationLLMService - Apple Intelligence with PCC (iOS 26+)

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
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        case .notImplemented:
            return "Feature not yet implemented"
        case .contextWindowExceeded:
            return "The context window size was exceeded."
        case .rateLimited(let message):
            return "Rate limited: \(message)"
        case .concurrentRequests(let message):
            return "Concurrent request blocked: \(message)"
        }
    }
}

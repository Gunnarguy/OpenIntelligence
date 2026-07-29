//
//  LLMService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import CoreML
import Foundation
import os
import NaturalLanguage

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
struct LLMResponse {
    let text: String
    let tokensGenerated: Int
    let timeToFirstToken: TimeInterval?
    let totalTime: TimeInterval
    let modelName: String? // Actual model used (includes execution location)
    let toolCallsMade: Int // Number of tool calls executed (for agentic RAG metrics)
    let structuredRAGGeneration: StructuredRAGGeneration?
    let executionReceipt: ModelExecutionReceipt?

    init(
        text: String,
        tokensGenerated: Int,
        timeToFirstToken: TimeInterval?,
        totalTime: TimeInterval,
        modelName: String?,
        toolCallsMade: Int,
        structuredRAGGeneration: StructuredRAGGeneration? = nil,
        executionReceipt: ModelExecutionReceipt? = nil
    ) {
        self.text = text
        self.tokensGenerated = tokensGenerated
        self.timeToFirstToken = timeToFirstToken
        self.totalTime = totalTime
        self.modelName = modelName
        self.toolCallsMade = toolCallsMade
        self.structuredRAGGeneration = structuredRAGGeneration
        self.executionReceipt = executionReceipt
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

        /// Tool handler for agentic RAG function calling
        var toolHandler: RAGToolHandler?

        /// Guards against concurrent warmup calls that cause "Session in Canceled state" warnings
        private var isWarmingUp = false

        private func sanitizeForLanguageDetection(_ text: String) -> String {
            return FoundationModelPromptCompiler.sanitizeForLanguageDetection(text)
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
            return "Apple Intelligence"
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

        /// Context window size for on-device model
        static var onDeviceContextWindowSize: Int {
            return 4096
        }
        
        /// Conservative PCC context-window value for synchronous compatibility callers.
        /// Runtime routing obtains the live SDK value asynchronously through
        /// `LiveFoundationModelCapabilityProvider`.
        static var pccContextWindowSize: Int {
            32768
        }

        /// Approximate token count for a string.
        /// Uses empirically validated 1.4 chars/token for Apple FM (observed across real prompts).
        /// Previous 2.5 ratio underestimated by ~44%, causing context overflow retries.
        static func estimateTokens(for text: String) -> Int {
            return FoundationModelTokenBudget.estimateTokens(for: text, isAppleFMOnDevice: true)
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
                #if compiler(>=6.4)
                case let .reasoning(reasoning):
                    description += "[\(index + 1)] Reasoning: \(String(describing: reasoning).prefix(80))...\n"
                #endif
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
            return FoundationModelTranscriptStore.estimateTranscriptTokens(transcript)
        }

        /// Estimate tokens for a pending transcript (before session creation)
        static func estimateTranscriptTokens(_ transcript: Transcript) -> Int {
            return FoundationModelTranscriptStore.estimateTranscriptTokens(transcript)
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
            Log.debug("AppleFoundationLLMService initialized (model will be loaded on first use)", category: .llm)
        }

        /// Start model warm-up (call this after init from an async context)
        func startWarmup() {
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
        @MainActor
        private func warmUpModel() async {
            Log.debug("[Warm-up] Starting Foundation Model preload...", category: .llm)
            let startTime = Date()

            do {
                // Create session (this loads the model into memory)
                _ = try ensureSession(route: .automatic)

                guard let session = session else {
                    Log.warning("[Warm-up] Session unavailable", category: .llm)
                    return
                }

                // Use official prewarm() API - no wasted tokens!
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
        private func ensureSession(route: AppleFoundationModelRoute, systemPrompt: String? = nil, disableTools: Bool = false) throws -> AppleFoundationModelRoute {
            guard Thread.isMainThread else {
                throw LLMError.modelUnavailable
            }

            if session == nil {
                let result = try FoundationModelSessionFactory.createSession(
                    route: route,
                    toolHandler: toolHandler,
                    systemPrompt: systemPrompt,
                    disableTools: disableTools,
                    pendingTranscript: pendingTranscript
                )

                session = result.session
                currentSystemPrompt = result.currentSystemPrompt
                if result.pendingTranscriptConsumed {
                    pendingTranscript = nil
                } else if disableTools && pendingTranscript != nil {
                    pendingTranscript = nil
                }
                
                return result.actualRoute
            }
            return route
        }

        @MainActor
        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            let __spGenerate = PipelineSignposts.synthesis.beginInterval("Generate")
            defer { PipelineSignposts.synthesis.endInterval("Generate", __spGenerate) }
            // Verify the current locale is supported before generation
            if !supportsCurrentLocale {
                let currentLocale = Locale.current.identifier
                Log.warning("Current locale '\(currentLocale)' not supported by Apple Intelligence — generation may produce degraded output", category: .llm)
            }

            // Force statelessness
            session = nil

            // Check if system prompt changed
            if let newPrompt = config.systemPrompt, newPrompt != currentSystemPrompt {
                Log.info("System prompt changed, recreating session", category: .llm)
                session = nil
            }

            // AUTO-TRIM TRANSCRIPT
            if let transcript = pendingTranscript, !transcript.isEmpty {
                pendingTranscript = FoundationModelTranscriptStore.trimTranscript(
                    transcript,
                    context: context,
                    prompt: prompt,
                    config: config
                )
            }

            // Construct augmented prompt with RAG context
            let fullPrompt = FoundationModelPromptCompiler.compilePrompt(
                prompt: prompt,
                context: context,
                systemPrompt: config.systemPrompt,
                disableTools: config.disableTools
            )

            // Estimate token count for routing decisions
            _ = fullPrompt.count
            let estimatedTokens = FoundationModelTokenBudget.estimateTokens(for: fullPrompt, isAppleFMOnDevice: !config.allowPrivateCloudCompute)
            Log.debug("Generation: ~\(estimatedTokens) tokens, exec=\(config.executionContext)", category: .llm)

            // Route policy
            let queryType: FoundationModelRoutePolicy.QueryType
            switch config.qualityMode.canonical {
            case .standard: queryType = .standard
            case .deepThink: queryType = .deepThink
            case .maximum: queryType = .maximum
            default: queryType = .standard
            }

            let targetRoute = FoundationModelRoutePolicy.determineRoute(
                queryType: queryType,
                estimatedContextTokens: estimatedTokens,
                config: config
            )

            // Ensure session is created with correct route
            let actualRoute = try ensureSession(route: targetRoute, systemPrompt: config.systemPrompt, disableTools: config.disableTools)

            guard let session = session else {
                throw LLMError.modelUnavailable
            }

            let executionBasedModelName: String
            switch actualRoute {
            case .onDevice:
                executionBasedModelName = "Apple Intelligence (On-Device)"
            case .onDeviceAdvanced:
                executionBasedModelName = "Apple Intelligence (On-Device)"
            case .privateCloudCompute:
                executionBasedModelName = "Apple Intelligence (PCC)"
            case .automatic:
                executionBasedModelName = modelName
            }

            // Post notification for route resolution in real-time
            NotificationCenter.default.post(
                name: NSNotification.Name("ActiveModelRouteResolved"),
                object: nil,
                userInfo: [
                    "modelName": executionBasedModelName,
                    "executionPath": {
                        if case .privateCloudCompute = actualRoute { return "privateCloudCompute" }
                        return "onDevice"
                    }(),
                    "planID": config.modelExecutionPlan?.id.uuidString ?? "direct",
                    "intendedPath": config.modelExecutionPlan?.intendedTarget.rawValue ?? "direct"
                ]
            )

            let startTime = Date()
            TelemetryCenter.emit(
                .generation,
                title: "Apple FM: Generation started",
                metadata: [
                    "temperature": "\(config.temperature)",
                    "maxTokens": "\(config.maxTokens)",
                    "pccAllowed": "\(config.allowPrivateCloudCompute)",
                    "execPref": "\(config.executionContext)",
                    "route": "\(actualRoute)"
                ]
            )

            // Generate response using streaming API with execution context
            var responseText = ""
            var tokenCount = 0
            var firstTokenTime: TimeInterval?
            
            let actualExecutionLocation: String
            
            switch actualRoute {
            case .onDevice:
                actualExecutionLocation = "📱 On-Device"
            case .onDeviceAdvanced:
                actualExecutionLocation = "📱 On-Device"
            case .privateCloudCompute(let reasoning):
                actualExecutionLocation = "☁️ Private Cloud Compute (Server)"
                _ = reasoning
            case .automatic:
                actualExecutionLocation = "Unknown"
            }

            let samplingMode: GenerationOptions.SamplingMode?
            if config.topK > 0, config.topK < 100 {
                samplingMode = .random(top: config.topK)
            } else if config.topP < 1.0, config.topP > 0.0 {
                samplingMode = .random(probabilityThreshold: Double(config.topP))
            } else {
                samplingMode = nil
            }

            #if compiler(>=6.4)
            let options = GenerationOptions(
                samplingMode: samplingMode,
                temperature: Double(config.temperature),
                maximumResponseTokens: config.maxTokens > 0 ? config.maxTokens : nil
            )
            #else
            let options = GenerationOptions(
                sampling: samplingMode,
                temperature: Double(config.temperature),
                maximumResponseTokens: config.maxTokens > 0 ? config.maxTokens : nil
            )
            #endif

            let responseStream: LanguageModelSession.ResponseStream<String>
            #if compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, *),
               case let .privateCloudCompute(reasoning) = actualRoute,
               reasoning != .none
            {
                let reasoningLevel: FoundationModels.ContextOptions.ReasoningLevel
                switch reasoning {
                case .deep: reasoningLevel = .deep
                case .moderate: reasoningLevel = .moderate
                case .light: reasoningLevel = .light
                case .none: reasoningLevel = .light
                }
                let contextOptions = FoundationModels.ContextOptions(reasoningLevel: reasoningLevel)
                responseStream = session.streamResponse(
                    to: fullPrompt,
                    options: options,
                    contextOptions: contextOptions
                )
            } else {
                responseStream = session.streamResponse(to: fullPrompt, options: options)
            }
            #else
            responseStream = session.streamResponse(to: fullPrompt, options: options)
            #endif

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

                        // Haptic: first token arrived
                        await MainActor.run { DSHaptics.generationStarted() }

                        if let ttft = firstTokenTime {
                            Log.info("[FM] First token in \(String(format: "%.2f", ttft))s (\(actualExecutionLocation))", category: .llm)
                        }
                    }

                    // Detect phase from transcript
                    if let lastEntry = session.transcript.last {
                        switch lastEntry {
                        case .response:
                            // Update response text from snapshot
                            let previousLength = responseText.count
                            responseText = snapshot.content
                            let newChars = responseText.count - previousLength
                            
                            if newChars > 0 {
                                let chunk = String(responseText.suffix(newChars))
                                LLMStreamingContext.emit(text: chunk, isFinal: false)
                            }
                            
                        default:
                            // For other entry types, we don't stream to the chat bubble yet
                            break
                        }
                    }

                    // Update token metrics (approximate based on total generated so far)
                    let currentTokenEstimate = max(1, Int(ceil(Double(snapshot.content.count) / 1.4)))
                    let newTokens = currentTokenEstimate - tokenCount
                    if newTokens > 0 {
                        tokenCount = currentTokenEstimate
                    }

                    // Subtle haptic tick
                    if snapshotCount % 8 == 0 {
                        await MainActor.run { DSHaptics.generationTick() }
                    }
                }
            } catch let error as LanguageModelSession.GenerationError {
                // Stop Neural Engine activity on error
                HardwareTelemetryReporter.sustain(.llmInference, active: false)

                let mapped = FoundationModelErrorMapper.mapError(error, isStructured: false, estimatedTokens: estimatedTokens)
                switch mapped {
                case let .throwError(mappedError):
                    throw mappedError
                case let .setFlags(violation, unsupported):
                    guardrailViolation = violation
                    unsupportedLanguage = unsupported
                }
            }

            // Stop Neural Engine activity indicator
            HardwareTelemetryReporter.sustain(.llmInference, active: false)

            // Haptic: generation complete
            await MainActor.run { DSHaptics.generationComplete() }

            // Handle generation errors with user-friendly messages
            if guardrailViolation {
                throw LLMError.generationFailed(
                    "Apple's safety guardrails prevented this response. " +
                        "Please rephrase your question to avoid sensitive topics."
                )
            }

            if unsupportedLanguage {
                let supportedList = supportedLanguages.prefix(5).map { $0.languageCode?.identifier ?? "?" }.joined(separator: ", ")
                throw LLMError.generationFailed(
                    "Apple Intelligence couldn't process this query. " +
                        "Try rephrasing with more context (e.g., 'Tell me about X' or 'What is X?'). " +
                        "Supported languages: \(supportedList)."
                )
            }

            Log.debug("[FM] Stream complete: \(snapshotCount) snapshots, \(responseText.count) chars", category: .llm)

            let totalTime = Date().timeIntervalSince(startTime)
            var finalTokenCount = responseText.split(separator: " ").count

            Log.info("[FM] Generation complete: \(finalTokenCount) words in \(String(format: "%.2f", totalTime))s (\(actualExecutionLocation))", category: .llm)

            // Using executionBasedModelName resolved at the start of generation

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

            // Response continuation
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

            // Post-processing
            responseText = convertInlineBulletsToProseFlow(responseText)
            responseText = deduplicateResponse(responseText)
            responseText = stripExcessiveBolding(responseText)

            LLMStreamingContext.emit(text: "", isFinal: true)
            finalTokenCount = responseText.split(separator: " ").count

            let toolCalls = await ToolCallCounter.shared.takeAndReset()
            let actualTarget: ModelExecutionTarget
            if case .privateCloudCompute = actualRoute {
                actualTarget = .privateCloudCompute
            } else {
                actualTarget = .onDevice
            }
            let executionReceipt = config.modelExecutionPlan.map { plan in
                ModelExecutionReceipt(
                    planID: plan.id,
                    policyVersion: plan.policyVersion,
                    intendedTarget: plan.intendedTarget,
                    attempts: [
                        ModelExecutionAttempt(
                            target: actualTarget,
                            startedAt: startTime,
                            result: .succeeded
                        ),
                    ],
                    actualTarget: actualTarget,
                    completedTarget: actualTarget,
                    fallbackReason: plan.intendedTarget == actualTarget
                        ? nil
                        : (plan.plannerFallbackReason ?? plan.fallback.reason),
                    pccQuotaAtPlanning: plan.pccQuotaAtPlanning
                )
            }
            return LLMResponse(
                text: responseText,
                tokensGenerated: finalTokenCount,
                timeToFirstToken: firstTokenTime,
                totalTime: totalTime,
                modelName: executionBasedModelName,
                toolCallsMade: toolCalls,
                executionReceipt: executionReceipt
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
            
            let estimatedTokens = FoundationModelTokenBudget.estimateTokens(for: prompt + context, isAppleFMOnDevice: !config.allowPrivateCloudCompute)
            let queryType: FoundationModelRoutePolicy.QueryType
            switch config.qualityMode.canonical {
            case .standard: queryType = .standard
            case .deepThink: queryType = .deepThink
            case .maximum: queryType = .maximum
            default: queryType = .standard
            }
            let targetRoute = FoundationModelRoutePolicy.determineRoute(
                queryType: queryType,
                estimatedContextTokens: estimatedTokens,
                config: config
            )
            
            let actualRoute = try ensureSession(route: targetRoute, systemPrompt: structuredConfig.systemPrompt, disableTools: true)

            guard let session = session else {
                throw LLMError.modelUnavailable
            }

            let executionBasedModelName: String
            switch actualRoute {
            case .onDevice:
                executionBasedModelName = "Apple Intelligence (On-Device)"
            case .onDeviceAdvanced:
                executionBasedModelName = "Apple Intelligence (On-Device)"
            case .privateCloudCompute:
                executionBasedModelName = "Apple Intelligence (PCC)"
            case .automatic:
                executionBasedModelName = modelName
            }

            // Post notification for route resolution in real-time
            NotificationCenter.default.post(
                name: NSNotification.Name("ActiveModelRouteResolved"),
                object: nil,
                userInfo: [
                    "modelName": executionBasedModelName,
                    "executionPath": {
                        if case .privateCloudCompute = actualRoute { return "privateCloudCompute" }
                        return "onDevice"
                    }(),
                    "planID": config.modelExecutionPlan?.id.uuidString ?? "direct",
                    "intendedPath": config.modelExecutionPlan?.intendedTarget.rawValue ?? "direct"
                ]
            )

            let generationStartedAt = Date()
            let response = try await FoundationModelStructuredGenerator.generateStructuredRAGAnswer(
                session: session,
                modelName: executionBasedModelName,
                prompt: prompt,
                context: context,
                config: config,
                sourceCount: sourceCount,
                mode: mode
            )
            let actualTarget: ModelExecutionTarget
            if case .privateCloudCompute = actualRoute {
                actualTarget = .privateCloudCompute
            } else {
                actualTarget = .onDevice
            }
            let executionReceipt = config.modelExecutionPlan.map { plan in
                ModelExecutionReceipt(
                    planID: plan.id,
                    policyVersion: plan.policyVersion,
                    intendedTarget: plan.intendedTarget,
                    attempts: [
                        ModelExecutionAttempt(
                            target: actualTarget,
                            startedAt: generationStartedAt,
                            result: .succeeded
                        ),
                    ],
                    actualTarget: actualTarget,
                    completedTarget: actualTarget,
                    fallbackReason: plan.intendedTarget == actualTarget
                        ? nil
                        : (plan.plannerFallbackReason ?? plan.fallback.reason),
                    pccQuotaAtPlanning: plan.pccQuotaAtPlanning
                )
            }
            return LLMResponse(
                text: response.text,
                tokensGenerated: response.tokensGenerated,
                timeToFirstToken: response.timeToFirstToken,
                totalTime: response.totalTime,
                modelName: response.modelName,
                toolCallsMade: response.toolCallsMade,
                structuredRAGGeneration: response.structuredRAGGeneration,
                executionReceipt: executionReceipt
            )
        }
        /// Detects if a response was cut off mid-sentence or mid-thought
        private func responseNeedsContinuation(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }

            let terminalPunctuation: Set<Character> = [".", "!", "?", ":", ";", "\"", "'", ")", "]", "}"]
            guard let lastChar = trimmed.last else { return false }
            let lastLine = trimmed.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
            let listPrefixes = ["- ", "* ", "• "]
            let incompleteMarkers: Set<String> = ["and", "or", "but", "the", "a", "an", "to", "of"]
            let lastWord = String(trimmed.split(separator: " ").last ?? "").lowercased()
            let looksStandaloneValue = wordCountLooksLikeStandaloneValue(trimmed)

            // Very short value answers are usually complete even without a final period.
            // For other short answers, still allow continuation when they clearly end mid-thought.
            let wordCount = trimmed.split(separator: " ").count
            if wordCount < 15 {
                if looksStandaloneValue {
                    return false
                }

                if !terminalPunctuation.contains(lastChar) {
                    return true
                }

                if listPrefixes.contains(where: { lastLine.hasPrefix($0) }) && !terminalPunctuation.contains(lastChar) {
                    return true
                }

                if incompleteMarkers.contains(lastWord) {
                    return true
                }

                return false
            }

            // If response contains repetition already, do NOT continue — it'll only get worse
            if containsRepetition(trimmed) { return false }

            // Check for obvious truncation indicators
            // Response ends mid-sentence (no terminal punctuation)
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

        private func wordCountLooksLikeStandaloneValue(_ text: String) -> Bool {
            text.range(
                of: #"^\s*(?:[A-Z]{2,}|\d+(?:[.,]\d+)?(?:\s*[A-Za-z%/.-]+){0,3}|[A-Za-z]+\s*:\s*\d+(?:[.,]\d+)?(?:\s*[A-Za-z%/.-]+){0,3})(?:\s*\[[^\]]+\])?\s*$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
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
        if lowercasePrompt.contains("roadmap") || lowercasePrompt.contains("plan") || lowercasePrompt.contains("next") {
            responseKey = "roadmap"
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

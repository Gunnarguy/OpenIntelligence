//
//  RAGService+Agentic.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

// MARK: - RAGService Extension

extension RAGService {

    /// Execute a light reasoning chain for Standard mode
    /// Uses 3 sessions × 4096 = 12K+ effective tokens (vs single 4K)
    ///
    /// ## When to Use
    /// - Standard mode with good retrieval quality (top similarity > 0.5)
    /// - Complex multi-hop questions that benefit from deeper analysis
    /// - When context exceeds single session budget
    ///
    /// This is a lighter version of Deep Think's reasoning chain:
    /// - 3 sessions instead of 4-5
    /// - Faster execution for responsive Standard mode
    /// - Still multiplies effective context by 3×
    func executeStandardReasoningChain(
        query: String,
        chunks: [RetrievedChunk],
        onProgress: ((String, String) async -> Void)? = nil  // (title, detail)
    ) async throws -> ReasoningChainResult {
        let orchestrator = AgenticOrchestrator(ragService: self, config: .fast, qualityMode: .standard)
        let complexity = QueryComplexityAnalyzer.shared.analyze(query).complexity
        let reasoningConfig: ReasoningChainConfig = complexity == .simple ? .light : .standard
        let totalSessions = reasoningConfig.sessionCount

        // Track session number for UI
        var sessionNum = 0

        // Emit progress for UI with meaningful descriptions
        let onStep: (ThinkingStep) async -> Void = { step in
            sessionNum += 1

            // Build a nice title showing progress
            let phaseEmoji: String
            let phaseName: String

            switch step.type {
            case .searching:
                phaseEmoji = "🔍"
                phaseName = "Analyzing evidence"
            case .analyzing:
                phaseEmoji = "🧠"
                phaseName = "Finding patterns"
            case .synthesizing:
                phaseEmoji = "✨"
                phaseName = "Synthesizing answer"
            default:
                phaseEmoji = "💭"
                phaseName = "Reasoning"
            }

            let title = "\(phaseEmoji) \(phaseName) (\(sessionNum)/\(totalSessions))"

            // Show a snippet of what the model discovered (first 80 chars of insight)
            let insightPreview = step.output
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail =
                insightPreview.isEmpty
                ? "Processing..."
                : String(insightPreview.prefix(80)) + (insightPreview.count > 80 ? "..." : "")

            await onProgress?(title, detail)
        }

        return try await orchestrator.executeReasoningChain(
            query: query,
            chunks: chunks,
            config: reasoningConfig,
            onStep: onStep
        )
    }

    /// Generate with a fresh session (no accumulated context)
    /// Used by AgenticOrchestrator for each thinking step
    func generateWithFreshSession(prompt: String, maxTokens: Int, skipContinuation: Bool = false) async throws -> LLMResponse {
        try Task.checkCancellation()
        #if canImport(FoundationModels)
            // Create a temporary AppleFoundationLLMService for isolated generation
            let tempService = AppleFoundationLLMService()

            // Ensure cleanup on exit
            defer {
                tempService.resetSession(clearTools: true)
            }

            var config = InferenceConfig(
                maxTokens: maxTokens,
                temperature: 0.7,
                systemPrompt: "You are an expert research analyst. Be concise and precise."
            )
            // Agentic planning and evidence analysis remain local. Only the
            // final post-retrieval synthesis may be selected for PCC.
            config.executionContext = .onDeviceOnly
            config.allowPrivateCloudCompute = false
            config.skipContinuation = skipContinuation

            // A rate limit is waited out here too (5.8): these calls (planning, search phrases, intent checks,
            // reformulation) did not reach the retry ladder in `RAGService`, so with the app in the background,
            // where iOS rate-limits the on-device model, one refusal failed the whole answer. In the background
            // the call waits for the app to come back; in front it backs off 2, 5 and 12 seconds.
            let backoffSeconds = [2, 5, 12]
            var attempt = 0
            while true {
                do {
                    return try await tempService.generate(prompt: prompt, context: nil, config: config)
                } catch {
                    guard ModelErrorClassifier.kind(of: error) == .rateLimited, attempt < backoffSeconds.count
                    else { throw error }
                    let waited = await RAGService.waitWhileAppIsInBackground()
                    if waited < 1 {
                        try? await Task.sleep(for: .seconds(backoffSeconds[attempt]))
                    }
                    try Task.checkCancellation()
                    attempt += 1
                }
            }
        #else
            throw LLMError.modelUnavailable
        #endif
    }

    /// Generate with proper PCC consent flow - used for Deep Think final synthesis
    /// This goes through the main LLM service with full consent prompts and transmission recording
    /// Matches Standard mode's quality and consent behavior
    func generateWithProperConsent(
        prompt: String,
        context: String,
        systemPrompt: String,
        maxTokens: Int,
        disableTools: Bool = false,
        // Optional so "the caller tuned this step deliberately" and "the caller said nothing" are
        // distinguishable, which they were not when the default was a literal 0.5. Exactly one of
        // the twelve call sites in this file passes a value; the rest were silently taking 0.5,
        // so the comment below about exploration versus synthesis described an intent the code had
        // stopped expressing.
        temperature: Float? = nil,
        qualityMode: RAGQualityMode = .deepThink,
        sourceChunks: [RetrievedChunk] = [],
        forceOnDevice: Bool = false
    ) async throws -> LLMResponse {
        try Task.checkCancellation()

        // Precedence: a step that named its own temperature keeps it, then the query's adaptive
        // profile, then the old default. This is what carries adaptive profiles into Deep Think and
        // Maximum, which previously could not reach them at all.
        //
        // `maxTokens` is deliberately NOT taken from the profile here. The agentic path runs many
        // sessions with per-step budgets chosen for what each step is doing, and a single
        // intent-derived ceiling applied to all of them would truncate mid-chain work that has
        // nothing to do with how long the final answer should be.
        let profile = await MainActor.run { self.activeAdaptiveProfile }
        let effectiveTemperature = temperature ?? profile?.temperature ?? 0.5
        // Which of the three this step used. Until 5.7 nothing recorded a step's temperature, so
        // nothing showed the profile reaching a generation (roadmap row "Adaptive profiles cannot
        // reach Deep Think or Maximum").
        Log.info(
            "[Agentic] Step temperature \(effectiveTemperature) from "
                + (temperature != nil ? "the step" : profile != nil ? "the adaptive profile" : "the default"),
            category: .llm)

        var config = InferenceConfig(
            maxTokens: maxTokens,
            temperature: effectiveTemperature,
            systemPrompt: systemPrompt
        )
        // Tools disabled for Maximum mode sessions to prevent context overflow
        // The chunks are pre-gathered and passed directly in the prompt
        config.disableTools = disableTools
        config.qualityMode = qualityMode

        // The user's model-picker choice, captured for this query in
        // `executeAgenticQuery`. Carry it onto the config *before* planning, so
        // the planner's `allowsPCC` reflects what was actually selected. Without
        // this the fields below keep their defaults (.automatic / .automatic /
        // true) and the picker is inert for Deep Think and Maximum.
        let userRouting = await MainActor.run { self.activeUserRoutingPreference }
        config.fmPreference = userRouting.fmPreference
        config.executionContext = userRouting.executionContext
        config.allowPrivateCloudCompute = userRouting.allowPrivateCloudCompute

        let networkAvailable = NetworkMonitor.shared.isConnected
        let pccSuppressed = await MainActor.run { self.isPCCSuppressedForDeepThink() }
        let isAppleFM = llmService is AppleFoundationLLMService
        // `forceOnDevice` is for callers whose prompts are deliberately built to
        // a local budget. The reasoning-chain sessions are the case that matters:
        // `buildChainPrompt` truncates context and insights to fit 4096 tokens and
        // disables tools to save the ~400-token schema. Once those sessions start
        // passing real chunks (below), the planner sees sufficient evidence and
        // would happily route each one to PCC — turning eight local passes into
        // eight ~8s cloud round-trips plus quota, for prompts already sized for
        // on-device. Exploration stays local; the final synthesis, which passes
        // its own chunks and is not budget-capped, is where escalation belongs.
        //
        // That pin is a heuristic about prompt budgets, so an explicit PCC
        // selection outranks it — otherwise choosing PCC would still produce
        // eight local sessions, which is what device logs showed before this.
        // `requiresOnDevice`, by contrast, is the user's instruction and is
        // absolute: On-Device means no PCC for any call in the query, synthesis
        // included. Once it is set, the planner sees `allowsPCC: false`, targets
        // `.onDevice`, and the existing `.onDevice` branch below both keeps
        // execution local and trims the context to the local budget.
        let budgetPin = forceOnDevice && !userRouting.explicitlyPrefersPCC
        if !isAppleFM || !networkAvailable || pccSuppressed
            || userRouting.requiresOnDevice || budgetPin
        {
            config.allowPrivateCloudCompute = false
            config.executionContext = .onDeviceOnly
        }

        let consentState = await MainActor.run {
            cloudConsent[.applePCC] ?? .notDetermined
        }

        // `sourceChunks` defaults to [] and 13 of this function's 14 call sites
        // rely on that default — the agentic steps pass their evidence as an
        // already-rendered `context` string rather than as chunks. The planner
        // decides sufficiency from `chunkCount > 0 && topScore >= 0.20`, so
        // every one of those calls looked like zero evidence, planned
        // `.abstain`, and (before this change) threw a bogus
        // "model isn't available" error at the user.
        //
        // That is what made Deep Think and Maximum look broken: they route
        // through this path, Standard does not. Retrieval had genuinely
        // succeeded — the reasoning chain was holding thousands of characters
        // of on-target evidence at the moment the planner declared there was
        // none.
        //
        // Sufficiency must be judged on the evidence actually being sent. When
        // a caller supplies context but no chunks, derive the signal from the
        // context itself instead of defaulting to "insufficient". Callers that
        // *do* pass chunks keep the precise scores.
        let renderedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let planningChunks = sourceChunks
        let hasRenderedEvidence = sourceChunks.isEmpty && !renderedContext.isEmpty

        let planned = await makePostRetrievalModelPlan(
            prompt: prompt,
            context: context,
            config: config,
            chunks: planningChunks,
            consentState: consentState,
            networkAvailable: networkAvailable,
            requiresMultiDocumentSynthesis: Set(sourceChunks.map { $0.chunk.documentId }).count > 1,
            hasRenderedEvidence: hasRenderedEvidence
        )
        let plan = planned.plan
        config.modelExecutionPlan = plan
        var routedContext = context
        var routedSourceChunks = sourceChunks

        switch plan.synthesisTarget {
        case .privateCloudCompute:
            let maximumCloudCharacters = max(
                800,
                min(
                    12_000,
                    Int(
                        Double(plan.contextBudget.remaining + plan.contextBudget.evidence)
                            * FoundationModelTokenBudget.cloudFallbackCharsPerToken)
                )
            )
            if hasRenderedEvidence {
                // The step's evidence is already rendered, with the chain's own labels (13 of this function's 14
                // call sites, above). The envelope is built from chunks, so from none it was empty, and the step
                // reached Private Cloud Compute with no evidence at all (found by review, 2026-10-20, read in code).
                // The rendered evidence goes instead, cut to the same budget.
                routedContext = String(context.prefix(maximumCloudCharacters))
            } else {
                let envelope = CloudEvidenceMinimizer().makeEnvelope(
                    plan: plan,
                    query: prompt,
                    chunks: sourceChunks,
                    maximumCharacters: maximumCloudCharacters
                )
                routedContext = renderCloudEvidenceEnvelope(envelope)
                // In the envelope's order, which its [S1], [S2] ... labels number (5.7).
                routedSourceChunks = Self.passages(sourceChunks, inTheOrderOf: envelope)
            }
            // What the step carries to Private Cloud Compute (5.8 journal): sizes only. Through 5.7 a step with rendered
            // evidence carried none.
            VerificationJournal.record(
                "agentic.cloudStep",
                ["evidence": hasRenderedEvidence ? "rendered" : "envelope", "contextChars": "\(routedContext.count)",
                    "passages": "\(routedSourceChunks.count)", "budget": "\(maximumCloudCharacters)"])
            do {
                try await ensureConsentForDeepThink(
                    service: llmService,
                    prompt: prompt,
                    context: routedContext,
                    sourceChunks: routedSourceChunks.map(\.chunk),
                    allowPrivateCloudCompute: true,
                    modelExecutionPlan: plan
                )
            } catch let error as RAGServiceError {
                if plan.fallback.target == .onDevice,
                    case .cloudConsentDenied(_) = error
                {
                    config.allowPrivateCloudCompute = false
                    config.executionContext = .onDeviceOnly
                } else if plan.fallback.target == .onDevice,
                    case .cloudConsentUnavailable(_) = error
                {
                    config.allowPrivateCloudCompute = false
                    config.executionContext = .onDeviceOnly
                } else {
                    throw error
                }
            }
        case .onDevice, .deterministic:
            config.allowPrivateCloudCompute = false
            config.executionContext = .onDeviceOnly
            if !planned.localBudget.fits {
                routedContext = String(routedContext.prefix(8_500))
            }
        case .abstain:
            // The planner chose to abstain because `evidence.isSufficient` was
            // false — a designed, correct outcome, not a failure. This used to
            // `throw RAGServiceError.modelNotAvailable`, which surfaced to the
            // user as "The selected model isn't available right now. Please try
            // again." That message is wrong in every respect: the model is fine,
            // retrying will not help, and the app's actual behavior — declining
            // to answer when the evidence does not support one — is a feature
            // rather than an outage.
            //
            // It also mostly hit Deep Think and Maximum: they route through this
            // planner path, while Standard does not, which made the modes look
            // broken when they were in fact abstaining.
            //
            // Return a grounded abstention so the verification story holds and
            // the user learns something actionable about their library.
            Log.info(
                "[ModelRouter] Planner abstained "
                    + "(\(plan.stages.first(where: { $0.role == .synthesize })?.reason.rawValue ?? "unknown"), "
                    + "chunks=\(plan.evidence.chunkCount) topScore=\(plan.evidence.topScore)); "
                    + "returning grounded abstention instead of an availability error",
                category: .llm
            )
            let abstention = """
                I couldn't find enough supporting evidence in this library to answer that reliably.

                Rather than guess, I'm stopping here. You could try rephrasing the question, \
                selecting a different library, or adding a document that covers it.
                """
            return LLMResponse(
                text: abstention,
                tokensGenerated: 0,
                timeToFirstToken: 0,
                totalTime: 0,
                modelName: "Abstained (insufficient evidence)",
                toolCallsMade: 0
            )
        }

        return try await generateWithFallback(
            prompt: prompt,
            context: routedContext,
            config: config,
            sourceChunks: routedSourceChunks.map(\.chunk),
            allowStructuredRAG: false
        )
    }
}

//
//  AgenticOrchestrator+Research.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

extension AgenticOrchestrator {
    // MARK: - Recursive Research Loop

    /// Execute a recursive research loop that allows the LLM to autonomously search.
    ///
    /// ## Overview
    ///
    /// This implements a true autonomous research loop where the LLM can:
    /// 1. Analyze the question and current context
    /// 2. Decide whether to answer or search for more information
    /// 3. Output `[SEARCH: query]` to trigger additional retrieval
    /// 4. Output `[ANSWER]` when confident enough to respond
    ///
    /// ## Protocol
    ///
    /// The LLM responds with special tokens:
    /// - `[SEARCH: your search query]` - Request additional document search
    /// - `[ANSWER]` followed by the response - Provide final answer
    ///
    /// The loop continues until:
    /// - LLM outputs `[ANSWER]`
    /// - Maximum iterations reached (default: 7)
    /// - Token budget exhausted
    ///
    /// ## Example Flow
    ///
    /// ```
    /// User: "What is the relationship between CoreData and SwiftData?"
    ///
    /// Iteration 1:
    /// LLM: "[SEARCH: CoreData SwiftData migration]"
    /// → System retrieves chunks about CoreData/SwiftData migration
    ///
    /// Iteration 2:
    /// LLM: "[SEARCH: SwiftData @Model macro]"
    /// → System retrieves chunks about SwiftData modeling
    ///
    /// Iteration 3:
    /// LLM: "[ANSWER]
    /// CoreData and SwiftData share..."
    /// ```
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - maxIterations: Maximum number of search iterations (default: 7)
    ///   - onStep: Callback for streaming thinking steps to UI
    /// - Returns: AgenticResult with final answer and all thinking steps
    /// Wall-clock ceiling for one recursive-research call, in seconds.
    ///
    /// Deliberately generous: this is a ceiling that stops a pathological query from hanging, not a
    /// tuning knob. Healthy cases in the smoke runs complete their whole query in 230 to 370
    /// seconds, and the cases that reach this loop at all are the minority that retrieved beyond the
    /// 20-chunk fusion cap.
    private var researchTimeBudget: TimeInterval { 180 }

    func executeRecursiveResearch(
        query: String,
        maxIterations: Int = 7,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        var allRetrievedChunks: [RetrievedChunk] = []
        let startTime = Date()

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        // Accumulate context across iterations
        var accumulatedContext = ""
        var iteration = 0

        Log.info("[RecursiveResearch] Starting recursive research loop for: \(query.prefix(50))...", category: .llm)

        // Initial retrieval to seed the context
        let (initialStep, initialChunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
        )
        steps.append(initialStep)
        totalTokens += initialStep.tokensUsed
        allRetrievedChunks.append(contentsOf: initialChunks)
        accumulatedContext = initialStep.output
        await onStep?(initialStep)

        // Recursive loop.
        //
        // The loop is bounded by iterations and tokens but was not bounded by time, and each
        // iteration runs a full retrieval pipeline plus a generation. That is unbounded work in
        // practice: a single case in the 184c562 smoke exceeded a 1500 second budget here and
        // returned nothing at all, where the same case previously escaped quickly only because it
        // took a bad answer. Removing the bad answer is correct, but it exposed that this loop can
        // spend arbitrarily long and still have nothing to show.
        //
        // The caller always already holds the reasoning chain's answer, so running out of time here
        // costs an enhancement rather than the response. This bounds the enhancement.
        let researchDeadline = Date().addingTimeInterval(researchTimeBudget)

        while iteration < maxIterations && totalTokens < config.maxTotalTokens {
            iteration += 1

            if Task.isCancelled {
                Log.info("[RecursiveResearch] Task cancelled at iteration \(iteration)", category: .llm)
                break
            }

            if Date() >= researchDeadline {
                Log.warning(
                    "[RecursiveResearch] Time budget of \(Int(researchTimeBudget))s exhausted at iteration "
                        + "\(iteration)/\(maxIterations); returning what research has so far and letting the "
                        + "caller keep the chain's answer",
                    category: .llm
                )
                break
            }

            Log.debug("[RecursiveResearch] Iteration \(iteration)/\(maxIterations)", category: .llm)

            // Ask the LLM to analyze context and decide next action
            let decision = try await getResearchDecision(
                query: query,
                currentContext: accumulatedContext,
                iteration: iteration,
                ragService: ragService,
                sourceChunks: allRetrievedChunks
            )

            totalTokens += decision.tokensUsed

            // Parse the decision
            let (action, content) = parseResearchDecision(decision.text)

            switch action {
            case .answer:
                // LLM is confident - create final synthesis step
                let synthesisStep = ThinkingStep(
                    id: UUID(),
                    type: .synthesizing,
                    input: "Final answer after \(iteration) iterations",
                    output: content,
                    tokensUsed: decision.tokensUsed,
                    duration: decision.duration,
                    timestamp: Date()
                )
                steps.append(synthesisStep)
                await onStep?(synthesisStep)

                Log.info("[RecursiveResearch] Completed with answer at iteration \(iteration)", category: .llm)

                return AgenticResult(
                    finalAnswer: content,
                    steps: steps,
                    totalTokens: totalTokens,
                    totalDuration: Date().timeIntervalSince(startTime),
                    confidence: estimateConfidence(from: content),
                    sourcesUsed: allRetrievedChunks.count,
                    retrievedChunks: allRetrievedChunks
                )

            case .search(let searchQuery):
                // LLM wants more information - execute search
                Log.debug("[RecursiveResearch] LLM requested search: \(searchQuery)", category: .llm)

                let searchStep = ThinkingStep(
                    id: UUID(),
                    type: .searching,
                    input: searchQuery,
                    output: "Searching for: \(searchQuery)",
                    tokensUsed: 0,
                    duration: 0,
                    timestamp: Date()
                )
                steps.append(searchStep)
                await onStep?(searchStep)

                // Execute the search
                let (resultStep, chunks) = try await executeSearchStepWithChunks(
                    subQuery: searchQuery,
                    ragService: ragService,
                    onDetailedEvent: detailedForwarder
                )
                steps.append(resultStep)
                totalTokens += resultStep.tokensUsed
                await onStep?(resultStep)

                // Add new chunks to accumulated context
                for chunk in chunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }

                // Append to context (with deduplication)
                accumulatedContext += "\n\n--- Search '\(searchQuery)' ---\n\(resultStep.output)"

                // Trim context buffer if getting too long (we truncate to 2000 chars before sending to LLM anyway)
                if accumulatedContext.count > 8000 {
                    accumulatedContext = String(accumulatedContext.suffix(6000))
                }

            case .thinking(let thought):
                // LLM is thinking but hasn't decided - log and continue
                let thinkingStep = ThinkingStep(
                    id: UUID(),
                    type: .analyzing,
                    input: "Analyzing...",
                    output: thought,
                    tokensUsed: decision.tokensUsed,
                    duration: decision.duration,
                    timestamp: Date()
                )
                steps.append(thinkingStep)
                await onStep?(thinkingStep)
            }
        }

        // Reached max iterations - force synthesis
        Log.warning("[RecursiveResearch] Reached max iterations (\(maxIterations)), forcing synthesis", category: .llm)

        let forcedSynthesis = try await executeForcedSynthesis(
            query: query,
            accumulatedContext: accumulatedContext,
            ragService: ragService
        )
        steps.append(forcedSynthesis)
        totalTokens += forcedSynthesis.tokensUsed
        await onStep?(forcedSynthesis)

        return AgenticResult(
            finalAnswer: forcedSynthesis.output,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: 0.6,  // Lower confidence since we hit iteration limit
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    // MARK: - Recursive Research Helpers

    /// Research action parsed from LLM output
    private enum ResearchAction {
        case answer(text: String)
        case search(query: String)
        case thinking(thought: String)
    }

    /// Ask LLM to decide whether to search or answer
    private func getResearchDecision(
        query: String,
        currentContext: String,
        iteration: Int,
        ragService: RAGService,
        /// Everything retrieved so far in this recursive loop, for post-retrieval
        /// planning. `currentContext` is embedded in the prompt below and `context`
        /// is passed empty to avoid double-rendering, which left the planner seeing
        /// no evidence at all: it abstained, and the abstention text came back in
        /// place of an `[ANSWER]`/`[SEARCH:]` decision the loop could parse.
        sourceChunks: [RetrievedChunk]
    ) async throws -> (text: String, tokensUsed: Int, duration: TimeInterval) {
        let startTime = Date()

        // Truncate context to ~2000 chars (~1400 tokens) to leave room for prompt overhead
        let truncatedContext = String(currentContext.prefix(2000))

        let prompt = """
            QUESTION: \(query)

            CONTEXT:
            \(truncatedContext)

            Reply with ONE of these two lines and nothing else:
            [ANSWER] then the answer itself
            [SEARCH: the specific words to look up] if the context above is not enough

            Write real search words. Do not reply with the word "query".
            Iteration \(iteration)/7.
            """

        Log.debug("[RecursiveResearch] Decision prompt: \(prompt.count) chars", category: .llm)

        let response = try await ragService.generateWithProperConsent(
            prompt: prompt,
            context: "",
            systemPrompt: "You are a research assistant deciding whether to search or answer.",
            // This prompt asks for "[ANSWER] (your answer)", so the cap has to cover a whole answer
            // and 600 tokens does not reliably. Truncation here does not degrade the response, it
            // erases it: the transcript delta comes back empty and the SDK reports
            // "Session ended without producing a response". Raised to match the reasoning chain's
            // headroom, where every generation finished far under a 700 token cap.
            maxTokens: 900,
            disableTools: true,
            sourceChunks: sourceChunks,
            // A routing decision, not an evidence synthesis. Keep it local.
            forceOnDevice: true
        )

        let duration = Date().timeIntervalSince(startTime)
        return (response.text, response.tokensGenerated, duration)
    }

    /// Parse LLM output into action
    private func parseResearchDecision(_ text: String) -> (ResearchAction, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for [ANSWER] token
        if let answerRange = trimmed.range(of: "[ANSWER]", options: .caseInsensitive) {
            let answer = String(trimmed[answerRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.answer(text: answer), answer)
        }

        // Check for [SEARCH: query] token
        let searchPattern = #"\[SEARCH:\s*(.+?)\]"#
        if let regex = try? NSRegularExpression(pattern: searchPattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let queryRange = Range(match.range(at: 1), in: trimmed)
        {
            let searchQuery = String(trimmed[queryRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // The model copying the prompt's own placeholder is not a search request.
            //
            // The instruction used to read `[SEARCH: query]`, and the on-device model echoed the
            // word back: **49 of 59 recursive searches in the 2026-08-15 run looked up the literal
            // string "query"**, across 16 of the 17 cases that reached this loop. Each one retrieved
            // nothing useful, the loop burned every iteration, and `executeForcedSynthesis` then
            // emitted a stub in place of the chain's answer. The prompt above now names a slot
            // rather than showing a word to copy, and this guard exists because a wording change
            // alone is not a guarantee on a small model.
            let placeholders: Set<String> = [
                "query", "the query", "your query", "search query", "search terms",
                "the specific words to look up", "keywords", "search",
            ]
            if placeholders.contains(searchQuery.lowercased()) {
                Log.warning(
                    "[RecursiveResearch] Model echoed the search placeholder (\(searchQuery)) instead of "
                        + "search terms; treating as thinking rather than running a meaningless retrieval",
                    category: .llm
                )
                return (.thinking(thought: trimmed), trimmed)
            }

            return (.search(query: searchQuery), searchQuery)
        }

        // Neither token found - treat as thinking
        return (.thinking(thought: trimmed), trimmed)
    }

    /// Force synthesis when iteration limit reached
    private func executeForcedSynthesis(
        query: String,
        accumulatedContext: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        // Short system prompt to maximize context budget
        let systemPrompt = """
            Provide best answer with available data. Cite [S1], [S2]. Note any gaps.
            """

        // Truncate to fit 4096 token limit
        let contextToUse = String(accumulatedContext.prefix(3500))

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: contextToUse,
            systemPrompt: systemPrompt,
            maxTokens: 800,
            disableTools: true
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Forced synthesis after max iterations",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Estimate confidence from answer text (heuristic)
    private func estimateConfidence(from answer: String) -> Float {
        let lowConfidenceIndicators = [
            "i'm not sure", "i don't know", "unclear", "might be",
            "possibly", "perhaps", "uncertain", "limited information",
            "couldn't find", "no information",
        ]

        let lowercased = answer.lowercased()
        var confidence: Float = 0.8  // Base confidence

        for indicator in lowConfidenceIndicators {
            if lowercased.contains(indicator) {
                confidence -= 0.1
            }
        }

        // Length bonus (longer answers tend to be more complete)
        if answer.count > 500 { confidence += 0.05 }
        if answer.count > 1000 { confidence += 0.05 }

        return max(0.3, min(0.95, confidence))
    }

    /// True when an "answer" is really just retrieved chunks pasted back.
    ///
    /// Recursive research can return the evidence it gathered rather than a written
    /// answer. That output is worthless to a user and, because it contains no
    /// hedging language, it slips past `answerIndicatesRetrievalMiss` and is allowed
    /// to replace a perfectly good synthesis. Seen on device: a 91%-confidence
    /// eight-session answer swapped for text beginning `[S1] Apple Intelligence
    /// powers OpenIntelligence via WWDC26 FoundationModels...`, copied verbatim out
    /// of the source document.
    ///
    /// A real synthesis never opens with a source marker — every synthesis prompt
    /// asks for prose with `###` headers — so requiring both a leading marker and
    /// several source-prefixed blocks keeps this narrow.
    func looksLikeRawEvidenceDump(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[S") else { return false }
        let sourcePrefixedBlocks =
            trimmed
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[S") }
            .count
        return sourcePrefixedBlocks >= 2
    }

    /// Detect if an answer indicates the initial retrieval missed relevant content
    /// This catches cases where the model says "I cannot find" but the answer exists in different chunks
    /// that weren't retrieved because of semantic mismatch (e.g., "oil pressure" vs "oil type/viscosity")
    func answerIndicatesRetrievalMiss(_ answer: String) -> Bool {
        let lowercased = answer.lowercased()

        // A grounded answer is *allowed* to say what the documents do not cover.
        // `buildSessionObjective` explicitly instructs the final session to "state
        // that the documents do not fully resolve them instead of inferring beyond
        // the evidence", and both "documents do not" and "do not specify" appear in
        // the list below — so the app was telling the model to hedge and then
        // classifying that hedge as a retrieval failure.
        //
        // Observed on device: an 8-session synthesis at 91% confidence tripped this,
        // was discarded, and recursive research replaced it with raw retrieved chunks
        // pasted back to the user. The replacement passed the guard at the call site
        // precisely because an evidence dump contains no hedging language.
        //
        // The original intent — catching retrieval that grabbed the wrong content,
        // "oil pressure" instead of "oil type" — produces a short, uncited answer.
        // A long answer carrying source citations is the opposite of that: it is a
        // grounded synthesis that happens to note a gap, which is the behaviour the
        // reasoning chain is designed to produce.
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let citationMarkers = trimmedAnswer.components(separatedBy: "[S").count - 1
        if trimmedAnswer.count >= 800 && citationMarkers >= 2 {
            return false
        }

        // Strong indicators that retrieval grabbed wrong content
        let retrievalMissIndicators = [
            "cannot determine",
            "cannot find",
            "not able to find",
            "no information about",
            "does not specify",
            "does not explicitly",
            "doesn't specify",
            "doesn't explicitly",
            "do not specify",
            "do not explicitly",
            "doesn't contain",
            "does not contain",
            "not mentioned",
            "no mention of",
            "unable to locate",
            "unable to find",
            "not provided in",
            "not stated in",
            "documents don't",
            "documents do not",
        ]

        for indicator in retrievalMissIndicators {
            if lowercased.contains(indicator) {
                Log.debug("[Agentic] Answer contains retrieval miss indicator: '\(indicator)'", category: .llm)
                return true
            }
        }

        return false
    }

}

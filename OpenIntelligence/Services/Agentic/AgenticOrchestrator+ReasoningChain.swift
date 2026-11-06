//
//  AgenticOrchestrator+ReasoningChain.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

extension AgenticOrchestrator {
    // MARK: - Reasoning Chain (Session Chaining)

    /// Execute a reasoning chain that multiplies effective context by chaining sessions
    ///
    /// ## Architecture (Per TN3193)
    ///
    /// Apple FM has a hard 4096 token limit per session. We outsmart this by:
    ///
    /// ```
    /// Session 1 (4096 tokens): Retrieve + First Pass Analysis
    ///    ↓ condensed insight (~500 chars)
    /// Session 2 (4096 tokens): New retrieval + Refine understanding
    ///    ↓ condensed insight
    /// Session 3 (4096 tokens): Pattern recognition across insights
    ///    ↓ condensed insight
    /// Session 4 (4096 tokens): Final synthesis with full reasoning
    /// ```
    ///
    /// **Effective context: 4 × 4096 = 16,384+ tokens** (vs single 4096)
    ///
    /// Each session:
    /// - Has fresh 4096 token budget
    /// - Receives previous insight as "priming" context
    /// - Focuses on a specific reasoning task
    /// - Outputs condensed insight for next session
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - chunks: Retrieved document chunks
    ///   - config: Chain configuration (default: 4 sessions)
    ///   - onStep: Callback for streaming thinking steps
    ///   - forceConfidenceReporting: When true, always include confidence in steps (for multi-chain mode)
    /// - Returns: ReasoningChainResult with synthesized answer

    /// Choose which sections to read, before reading any of them.
    ///
    /// A section title costs about fifty characters; a chunk of body text costs several hundred.
    /// Twenty titles therefore fit in one 3500 character session window where three chunks do not,
    /// which makes a routing turn the cheapest possible first move: show the model the table of
    /// contents of what retrieval found and let it choose. The alternative, which is what happened
    /// before, is that cosine similarity chooses on its behalf before anything has been read, and
    /// the chain then spends its whole budget on that guess.
    ///
    /// **This reorders and never drops.** Unselected chunks move behind the selected ones rather
    /// than disappearing, and every failure path returns the input untouched, so a wrong routing
    /// decision costs ordering rather than evidence. That matters on a path with no test coverage:
    /// the only guaranteed cost is one extra generation, and the worst case is the ordering the
    /// chain already had.
    private func routeChunksByTitle(
        query: String,
        chunks: [RetrievedChunk],
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async -> [RetrievedChunk] {
        // Below four chunks the windows already cover everything, so routing buys nothing and
        // still costs a generation.
        guard chunks.count >= 4, let ragService = ragService, !Task.isCancelled else { return chunks }

        func menuLabel(_ candidate: RetrievedChunk) -> String {
            if let section = candidate.chunk.metadata.sectionTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines), !section.isEmpty
            {
                return section
            }
            // No structured section: the opening of the text is still a better menu entry than an
            // index, and this is exactly the case the routing turn exists to disambiguate.
            let body = candidate.chunk.contextText
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(body.prefix(60))
        }

        var menu = ""
        var listed = 0
        for (index, candidate) in chunks.enumerated() {
            let document = URL(fileURLWithPath: candidate.sourceDocument).lastPathComponent
            let suffix = document.isEmpty ? "" : " (\(document))"
            let line = "\(index + 1). \(menuLabel(candidate))\(suffix)\n"
            // Hard ceiling so the menu itself can never overrun the window it is meant to save.
            if menu.count + line.count > 1800 { break }
            menu += line
            listed += 1
        }
        guard listed >= 4 else { return chunks }

        let prompt = """
            QUESTION: \(query)

            SECTIONS AVAILABLE:
            \(menu)
            Which sections would answer the question? Reply with their numbers only, most useful first,
            at most 8, separated by commas. No other text.
            """

        // Do NOT swallow the error with `try?`. The first device run of this feature failed and
        // logged only "unavailable", which named the symptom and hid the cause, so a second run was
        // needed to learn nothing. A fallback that cannot say why it fell back is a fallback that
        // never gets fixed.
        let response: LLMResponse
        do {
            // 256, not 64. An Instruments trace of the Foundation Models template on device
            // (iPhone 16 Pro Max, iOS 27.0) caught this exactly: for this call Apple recorded
            // `maximumResponseTokens: 64`, `generatedTokenCount: 64`, `deltasCount: 2`,
            // `assets: ""` and a delta transcript of `{"entries":[]}`. The model ran into the
            // output cap, the resulting transcript delta was empty, and the SDK surfaced that as
            // ParsingError / "Session ended without producing a response", which describes the
            // symptom and hides the cause.
            //
            // The reply itself is a dozen characters, but the cap has to cover whatever the model
            // emits on the way there, and 64 tokens does not. Every generation that succeeded in
            // the same trace finished well under its cap: 107, 111, 85 and 321 tokens against caps
            // of 700 and 1500. Input size was never the variable; four earlier hypotheses (rate
            // limiting, guided generation, prompt size, empty context) were each investigated and
            // ruled out before the trace made the output cap visible.
            response = try await ragService.generateWithFreshSession(prompt: prompt, maxTokens: 256)
        } catch {
            Log.warning(
                "[ReasoningChain] Title routing generation failed (\(type(of: error))): "
                    + "\(error.localizedDescription). Keeping retrieval order.",
                category: .llm
            )
            return chunks
        }
        guard !Task.isCancelled else { return chunks }

        var seen = Set<Int>()
        var selected: [Int] = []
        for token in response.text.split(whereSeparator: { !$0.isNumber }) {
            guard let value = Int(token), (1...listed).contains(value) else { continue }
            let index = value - 1
            if seen.insert(index).inserted { selected.append(index) }
            if selected.count >= 8 { break }
        }
        guard !selected.isEmpty else {
            // Log what it actually said. The parser accepts any digits anywhere, so reaching here
            // means the reply contained no number in range, and the only way to fix that is to see
            // the wording that produced it.
            Log.warning(
                "[ReasoningChain] Title routing returned no usable selection from "
                    + "\(listed) options; reply was: \(response.text.prefix(120)). Keeping retrieval order.",
                category: .llm
            )
            return chunks
        }

        let reordered =
            selected.map { chunks[$0] }
            + chunks.enumerated()
            .filter { !seen.contains($0.offset) }
            .map(\.element)

        Log.info(
            "[ReasoningChain] Title routing: model chose \(selected.count) of \(listed) sections "
                + "(\(selected.map { String($0 + 1) }.joined(separator: ","))); reordered, none dropped",
            category: .llm
        )
        await onStep?(
            ThinkingStep(
                id: UUID(),
                type: .searching,
                input: "Choosing sections to read",
                output: "Selected \(selected.count) of \(listed) available sections",
                tokensUsed: response.tokensGenerated,
                duration: 0.2,
                timestamp: Date()
            ))
        return reordered
    }

    func executeReasoningChain(
        query: String,
        chunks: [RetrievedChunk],
        config: ReasoningChainConfig = .standard,
        onStep: ((ThinkingStep) async -> Void)? = nil,
        forceConfidenceReporting: Bool = false
    ) async throws -> ReasoningChainResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        let reasoningPolicy = AgenticPolicyService.reasoningPolicy(
            for: config,
            agenticConfig: self.config,
            forceConfidenceReporting: forceConfidenceReporting
        )

        var chainInsights: [String] = []
        var totalTokens = 0
        var allSources: Set<String> = []
        var actualSessionCount = 0
        var cumulativeConfidence: Float = reasoningPolicy.initialConfidence
        let queryEnhancer = QueryEnhancementService()
        var evidenceTracker = FactBank()
        if reasoningPolicy.usesEvidenceDrivenStopping {
            evidenceTracker.queryIntent = queryEnhancer.classifyIntent(query)
            evidenceTracker.initializeWithQuery(query)
        }
        var lowNoveltyStreak = 0
        var saturationStreak = 0
        var usedWindowSources: Set<String> = []

        Log.info(
            "[ReasoningChain] Starting \(reasoningPolicy.isDeepThinkMode ? "dynamic 4-8" : String(config.sessionCount))-session chain for: \(query.prefix(40))... (confidence reporting: \(reasoningPolicy.shouldReportConfidence), threshold: \(Int(reasoningPolicy.confidenceThreshold * 100))%)",
            category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // CHUNK ROTATION: Each session sees a sliding window of chunks
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Session 1: chunks [0..3], Session 2: [2..5], Session 3: [4..7], etc.
        // This ensures the answer gets found even when the reranker is wrong.
        // Multi-session value = depth (repeated reasoning) + breadth (more chunks).

        // For multi-session modes, use smaller context to leave room for accumulated insights
        // Deep Think (4-8 sessions) and Maximum (up to 50) both need room for insight chains
        //
        // FIXED TOKEN BUDGET (context no longer doubled):
        // 4096 total - 80 (system) - 30 (LLM wrapper) - 500 (output) = 3486 tokens ≈ 4880 chars
        // Session 1 (no insights): context up to 4000 chars, prompt text ~300 chars = 4300 (fits)
        // Session 2+ (with insights): context ≤ 2200 + insights ≤ 1200 + prompt ~300 = 3700 (fits)
        // buildChainPrompt handles the per-session budget split (4000 for S1, 2200 for S2+)
        let maxChunksPerSession = (reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode) ? 4 : 6
        let contextBudget =
            reasoningPolicy.isUnlimitedMode
            ? 3000 : (reasoningPolicy.isDeepThinkMode ? 3500 : (config.maxContextPerSession - 500))

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // SESSION CONTEXT ROTATION: Different sessions see different chunks
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Previous approach: ALL sessions see the same top-4 chunks.
        // Problem: If reranker scored wrong chunks highest (common for broad-topic
        // queries), ALL sessions reason over irrelevant content and the actual
        // answer chunk is never seen.
        //
        // New approach: Session N sees chunks [N*stride..N*stride+perSession].
        //
        // The stride was `chunksPerSession / 2`, a deliberate 50% overlap "for continuity". That
        // is cheap in a large context window and expensive in a 4096 token one. A Deep Think
        // session gets 3500 characters, so half-overlap spends ~1750 of them re-reading text the
        // previous session already read: across eight sessions, roughly four entire session budgets
        // returned to material already seen. With 20 chunks and 4 per session, half-overlap covers
        // 18 of them in eight sessions and reads each twice; disjoint covers all 20 in five.
        //
        // Continuity is supposed to come from the carried state, which is what PRIOR FINDINGS and
        // the FactBank are for, not from re-reading raw text. Windows are disjoint now. The
        // wrap-around below still repeats windows once the pool is exhausted, which is the correct
        // behaviour: at that point every chunk has been seen and depth is all that is left.
        // One routing turn before any reading. See `routeChunksByTitle`: it reorders by the model's
        // own choice of sections and never drops, so the worst case is the retrieval order this
        // line used to receive unconditionally.
        let routedChunks = await routeChunksByTitle(query: query, chunks: chunks, onStep: onStep)

        // Whole chunks, counted in tokens against the live window (5.6). When the SDK can count
        // exactly, a Deep Think or Maximum chain session reads its chunks whole instead of the
        // sentences extracted below, which keep a sentence only when it, its heading or the line
        // before it matches a keyword of the question. `nil` keeps the character-sized path: an OS
        // that cannot count, a failed count, a mode this plan does not cover, or sessions that may
        // leave the device. 700 is a session's response limit. See `SessionEvidencePlan`.
        let evidenceWindowTokens = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let firstSessionTokenBudget = SessionEvidencePlan.evidenceTokenBudget(
            contextSize: evidenceWindowTokens, outputReserve: 700,
            carriedChars: SessionEvidencePlan.carriedChars(questionLength: query.count, isFirstSession: true))
        let laterSessionTokenBudget = SessionEvidencePlan.evidenceTokenBudget(
            contextSize: evidenceWindowTokens, outputReserve: 700,
            carriedChars: SessionEvidencePlan.carriedChars(questionLength: query.count, isFirstSession: false))
        let wholeChunkCap = SessionEvidencePlan.chainChunkCap(
            contextSize: evidenceWindowTokens, poolSize: routedChunks.count, legacyCount: maxChunksPerSession)
        // With Private Cloud Compute chosen in the picker a chain session is not pinned to the device
        // (`generateWithProperConsent`, `budgetPin`), and this plan is sized for the on-device window.
        // Those sessions keep the character-sized path, so this change sends no more text off device.
        let sessionsMayLeaveDevice = await MainActor.run { ragService.activeUserRoutingPreference.explicitlyPrefersPCC }
        let chunkTokenCounts: [Int]? =
            ((reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode) && !sessionsMayLeaveDevice)
            ? await SessionEvidenceTokenCounter.counts(
                for: routedChunks.prefix(SessionEvidencePlan.maxPlannedChunks).enumerated().map {
                    SessionEvidencePlan.block(for: $0.element, label: $0.offset + 1)
                })
            : nil

        let chunksPerSession = min(maxChunksPerSession, routedChunks.count)
        let stride = max(1, chunksPerSession)

        // Use dynamic max for Deep Think mode (can go up to 8 sessions)
        let effectiveMaxSessions =
            reasoningPolicy.isDeepThinkMode ? reasoningPolicy.maxSessionsForMode : config.sessionCount

        // Build ALL session contexts upfront; each session gets a sliding window
        var sessionContexts: [String] = []
        var sessionOffset = 0
        let totalAvailableChunks = routedChunks.count

        // Generate enough context windows for all possible sessions
        var sessionSourceSets: [Set<String>] = []
        var sessionContextIsWhole: [Bool] = []
        var sessionWindowRanges: [Range<Int>] = []
        while sessionContexts.count < effectiveMaxSessions {
            var startIdx = min(sessionOffset, max(0, totalAvailableChunks - chunksPerSession))
            var endIdx = min(startIdx + chunksPerSession, totalAvailableChunks)
            // A whole-chunk window starts where the last one ended and takes as many chunks as fit
            // the token budget. It is used only when it holds at least as many chunks as the
            // character-sized window would, so it never adds sessions.
            var wholeWindowTokens: Int?
            let evidenceTokenBudget = sessionContexts.isEmpty ? firstSessionTokenBudget : laterSessionTokenBudget
            if let chunkTokenCounts, sessionOffset < totalAvailableChunks {
                let planned = SessionEvidencePlan.window(
                    start: sessionOffset, tokenCounts: chunkTokenCounts, budget: evidenceTokenBudget,
                    cap: wholeChunkCap, legacyCount: chunksPerSession)
                if planned.wholeChunks {
                    startIdx = sessionOffset
                    endIdx = planned.end
                    wholeWindowTokens = planned.tokens
                }
            }

            // SENTENCE-LEVEL EXTRACTION: Instead of packing 3-4 whole chunks per session,
            // extract only query-relevant sentences from the window's chunks.
            // With 3000-3500 char budgets per session, this fits targeted data from
            // ALL chunks in the window instead of truncating at 2-3 whole chunks.
            // Universal across all document types — same extraction as Standard pipeline.
            let windowChunks = Array(routedChunks[startIdx..<endIdx])
            for c in windowChunks { allSources.insert(c.sourceDocument) }
            sessionSourceSets.append(Set(windowChunks.map(\.sourceDocument)))

            // `labelOffset` makes the window's labels global positions in `routedChunks` instead of
            // restarting at [S1] every session. Without it, session 2's [S1] and session 1's [S1]
            // name different chunks in the same answer, and `verifyCitations` cannot resolve either.
            var ctx = ""
            var extractedSentences = 0
            var extractedSources = 0
            if wholeWindowTokens == nil {
                let extraction = await ragService.extractRelevantSentences(
                    from: windowChunks,
                    query: query,
                    maxChars: contextBudget,
                    compact: true,
                    labelOffset: startIdx
                )
                ctx = extraction.context
                extractedSentences = extraction.sentencesIncluded
                extractedSources = extraction.sourcesUsed
            }

            // FALLBACK: If keyword extraction returned nothing useful (common when cross-reference
            // chunks don't contain the original query's keywords), use raw chunk content.
            // These chunks were retrieved by the vector/reranker pipeline for relevance,
            // so they're worth including even if keyword matching is too strict.
            //
            // The test is "too small to reason over", not "empty". It was `isEmpty`, and a device
            // log shows what that let through: extraction returned the section label
            // `[S1] 4 Reprocessing` followed by the source filename, 67 characters against a
            // 3000+ character budget, carrying no document content at all. That is not empty, so
            // this fallback never fired, and Deep Think ran eight sessions over the document's
            // table of contents. Its insights degenerated to "[S1] contains a section titled" and
            // the final generation failed to parse. A context that cannot answer anything should
            // be replaced by raw chunk text for the same reason an empty one is.
            let trimmedCtx = ctx.trimmingCharacters(in: .whitespacesAndNewlines)
            let minimumUsefulContext = max(200, contextBudget / 8)
            if wholeWindowTokens == nil && trimmedCtx.count < minimumUsefulContext && !windowChunks.isEmpty {
                var rawContext = ""
                for (idx, wc) in windowChunks.enumerated() {
                    let content = wc.chunk.contextText
                    // Global position, matching the `labelOffset` on the extraction path above.
                    let sourceLabel = "[S\(startIdx + idx + 1)] (\(wc.sourceDocument))"
                    let truncated = String(content.prefix(contextBudget / max(windowChunks.count, 1)))
                    if rawContext.count + truncated.count + sourceLabel.count + 10 < contextBudget {
                        rawContext += sourceLabel + "\n" + truncated + "\n\n---\n"
                    }
                }
                ctx = rawContext
                Log.debug(
                    "[ReasoningChain] Session \(sessionContexts.count + 1): keyword extraction returned \(trimmedCtx.count) chars, below the \(minimumUsefulContext) needed; using raw chunk content (\(ctx.count) chars)",
                    category: .retrieval)
            } else if wholeWindowTokens == nil {
                Log.debug(
                    "[ReasoningChain] Session \(sessionContexts.count + 1): \(extractedSentences) sentences from \(extractedSources) sources (\(ctx.count) chars)",
                    category: .retrieval)
                VerificationJournal.record(
                    "deepthink.session",
                    ["session": "\(sessionContexts.count + 1)", "path": "sentences", "chunks": "\(windowChunks.count)",
                        "tokens": "0", "window": "\(evidenceWindowTokens)", "chars": "\(ctx.count)"])
            }

            if let wholeWindowTokens {
                ctx = SessionEvidencePlan.wholeChunkContext(windowChunks, firstLabel: startIdx + 1)
                Log.debug(
                    "[ReasoningChain] Session \(sessionContexts.count + 1): \(windowChunks.count) whole chunks, "
                        + "\(wholeWindowTokens) of \(evidenceTokenBudget) evidence tokens, window \(evidenceWindowTokens) "
                        + "(\(ctx.count) chars)",
                    category: .retrieval)
                // The session's token plan (5.8 journal): the Log.debug line above reaches the trace only at verbose.
                VerificationJournal.record(
                    "deepthink.session",
                    ["session": "\(sessionContexts.count + 1)", "path": "wholeChunks", "chunks": "\(windowChunks.count)",
                        "tokens": "\(wholeWindowTokens)", "budget": "\(evidenceTokenBudget)",
                        "window": "\(evidenceWindowTokens)", "chars": "\(ctx.count)"])
            }

            sessionContexts.append(ctx)
            sessionContextIsWhole.append(wholeWindowTokens != nil)
            sessionWindowRanges.append(startIdx..<endIdx)
            sessionOffset += wholeWindowTokens != nil ? max(1, endIdx - startIdx) : stride

            // Stop when the corpus runs out, instead of wrapping and re-reading it.
            //
            // This used to reset `sessionOffset` to 0 and keep building until it had
            // `effectiveMaxSessions` windows. Deep Think asks for 8. A 20-chunk library at 4
            // chunks per session yields 5 distinct windows, so offsets went 0, 4, 8, 12, 16 and
            // then 0, 4, 8 again — sessions 6, 7 and 8 were byte-identical rebuilds of 1, 2 and 3.
            //
            // A device capture on 2026-08-18 shows it exactly: sessions 6/7/8 logged the same
            // sentence counts, source counts and character counts as 1/2/3, from the same starting
            // labels. Three of eight generations at roughly 35 seconds each, re-reading text the
            // model had already been given, in a query that took 279 seconds.
            //
            // Re-reading cannot introduce evidence the model has not already seen, so what those
            // sessions buy is at most another pass over the same material. That is not worth a
            // third of the wall clock, and the chain already has a confidence-based early exit for
            // when it has learned enough. Sessions are now capped at the number of distinct windows
            // the corpus can actually produce.
            if sessionOffset >= totalAvailableChunks {
                if sessionContexts.count < effectiveMaxSessions {
                    Log.info(
                        "[ReasoningChain] Corpus exhausted after \(sessionContexts.count) distinct window(s); "
                            + "capping below the \(effectiveMaxSessions) sessions this mode allows rather than "
                            + "re-reading windows already covered.",
                        category: .llm
                    )
                }
                break
            }
        }

        // For logging, use the first session's context
        let sharedContext = sessionContexts.first ?? ""
        Log.debug(
            "[ReasoningChain] Built \(sessionContexts.count) rotating contexts (first: \(sharedContext.count) chars, \(chunksPerSession) chunks/session, stride \(stride))",
            category: .retrieval)

        if reasoningPolicy.isUnlimitedMode {
            Log.info(
                "[ReasoningChain] UNLIMITED MODE: Will keep reasoning until \(Int(reasoningPolicy.confidenceThreshold * 100))% confident or \(config.sessionCount) sessions max",
                category: .llm)
        } else if reasoningPolicy.isDeepThinkMode {
            Log.info(
                "[ReasoningChain] DEEP THINK MODE: Dynamic 4-8 sessions, targeting \(Int(reasoningPolicy.confidenceThreshold * 100))% confidence",
                category: .llm)
        }

        // Run one session per distinct window, not one per session the mode allows.
        //
        // Capping the window count alone is not enough: this loop ran `effectiveMaxSessions`
        // times and `contextIndex` clamps with `min(sessionIndex, sessionContexts.count - 1)`, so
        // any surplus sessions would all re-read the *last* window instead of the first three.
        // Same wasted generations, different text. The early-exit checks inside the loop still
        // apply, so a chain that reaches its confidence target still stops sooner than this.
        let plannedSessions = min(effectiveMaxSessions, max(1, sessionContexts.count))
        for sessionIndex in 0..<plannedSessions {
            let sessionNum = sessionIndex + 1
            actualSessionCount = sessionNum

            if reasoningPolicy.isUnlimitedMode {
                Log.debug(
                    "[ReasoningChain] Session \(sessionNum) (unlimited mode, confidence: \(Int(cumulativeConfidence * 100))%)",
                    category: .llm)
            } else if reasoningPolicy.isDeepThinkMode {
                Log.debug(
                    "[ReasoningChain] Session \(sessionNum)/4-8 (deep think, confidence: \(Int(cumulativeConfidence * 100))%)",
                    category: .llm)
            } else {
                Log.debug("[ReasoningChain] Session \(sessionNum)/\(config.sessionCount)", category: .llm)
            }

            // A one second gap between sessions while the system asks apps to scale back (iOS 27).
            // The session count is not cut: the answer stays as deep, and takes longer.
            if sessionIndex > 0, await SystemResourceAdvice.easeOff(for: .seconds(1)) {
                Log.debug("[ReasoningChain] Eased off before session \(sessionNum): the system asked for less", category: .llm)
            }

            if Task.isCancelled { break }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Dynamic session stopping based on confidence
            // - Maximum (unlimited): min 8 sessions, target 98%
            // - Deep Think: min 4 sessions, target 85%, max 8 sessions
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if sessionIndex >= reasoningPolicy.minSessionsBeforeEarlyStop {
                if reasoningPolicy.usesEvidenceDrivenStopping {
                    let evidenceCoverageTarget = reasoningPolicy.evidenceCoverageTarget(
                        for: evidenceTracker.subQuestions.count
                    )
                    let sourceCoverage = Float(usedWindowSources.count) / Float(max(allSources.count, 1))
                    let noveltyExhausted = reasoningPolicy.noveltyExhausted(
                        lowNoveltyStreak: lowNoveltyStreak,
                        saturationStreak: saturationStreak,
                        sourceCoverage: sourceCoverage
                    )

                    if cumulativeConfidence >= reasoningPolicy.confidenceThreshold,
                        evidenceTracker.subQuestionConfidence >= evidenceCoverageTarget,
                        noveltyExhausted
                    {
                        let modeName = reasoningPolicy.isUnlimitedMode ? "Maximum" : "Deep Think"
                        Log.info(
                            "[ReasoningChain] \(modeName) mode: stopping at \(Int(cumulativeConfidence * 100))% confidence, coverage=\(Int(evidenceTracker.subQuestionConfidence * 100))%, sourceCoverage=\(Int(sourceCoverage * 100))%, lowNovelty=\(lowNoveltyStreak), saturation=\(saturationStreak)",
                            category: .llm
                        )
                        break
                    }
                } else if cumulativeConfidence >= reasoningPolicy.confidenceThreshold {
                    let modeName = reasoningPolicy.isUnlimitedMode ? "Maximum" : "Deep Think"
                    Log.info(
                        "[ReasoningChain] \(modeName) mode: Stopping at \(Int(cumulativeConfidence * 100))% confidence (threshold: \(Int(reasoningPolicy.confidenceThreshold * 100))%)",
                        category: .llm)
                    break
                }
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Each session gets a ROTATED context window for chunk diversity
            // Session 1 sees chunks [0..3], Session 2 sees [2..5], etc.
            // This ensures the answer chunk gets seen even if reranker is wrong
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let contextIndex = min(sessionIndex, sessionContexts.count - 1)
            let sessionContext = sessionContexts[contextIndex]

            // SKIP sessions with empty context — calling the LLM with no documents
            // wastes tokens and produces garbage like "No new information" or refusals.
            // The sliding window can exhaust relevant chunks before all sessions run.
            if sessionContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sessionIndex > 0 {
                Log.debug("[ReasoningChain] Session \(sessionNum) skipped — empty context window", category: .retrieval)
                continue
            }

            // DEBUG: Log what context is actually being passed
            Log.debug(
                "[ReasoningChain] Session \(sessionNum) context (\(sessionContext.count) chars): \(sessionContext.prefix(500))...",
                category: .retrieval)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Build session prompt based on position in chain
            // For unlimited/deep think mode, dynamically determine if this should be the "final" session
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let effectiveSessionCount =
                (reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode)
                ? max(effectiveMaxSessions, sessionNum + 3) : config.sessionCount

            // For unlimited mode, use sliding window of recent insights to prevent context overflow
            // Keep only the last 3 insights (each ~500 chars) to stay well under 4096 token limit
            // ALSO apply to Deep Think mode to prevent context overflow on 4-8 sessions
            let insightsForPrompt: [String]
            if (reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode) && chainInsights.count > 3 {
                // Condense older insights into a brief summary + keep recent 2
                // FIXED: Was truncating to 100 chars each, losing most accumulated knowledge.
                // Now keep 250 chars per older insight (2.5x more) and 800 char cap on condensed.
                let oldInsightsCount = chainInsights.count - 2
                // Cut at sentence boundaries. A raw `prefix()` ends the findings block
                // mid-word, and this runs upstream of `buildChainPrompt`, so it is the
                // first place the prompt can be garbled. It also fires exactly at
                // session 5 (`chainInsights.count > 3`), which is where degraded,
                // JSON-shaped insights started in device runs.
                let condensedOld =
                    "Prior findings (\(oldInsightsCount) sessions): "
                    + chainInsights.prefix(oldInsightsCount)
                    .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 }
                    .map { truncateAtSentenceBoundary($0, limit: 250) }
                    .joined(separator: " | ")
                insightsForPrompt =
                    [truncateAtSentenceBoundary(condensedOld, limit: 800)]
                    + Array(chainInsights.suffix(2))
                Log.debug(
                    "[ReasoningChain] \(reasoningPolicy.isUnlimitedMode ? "Unlimited" : "Deep Think") mode: condensed \(chainInsights.count) insights to \(insightsForPrompt.count) for prompt",
                    category: .llm)
            } else {
                insightsForPrompt = chainInsights
            }

            let sessionObjective =
                reasoningPolicy.usesEvidenceDrivenStopping
                ? buildSessionObjective(
                    query: query,
                    factBank: evidenceTracker,
                    sessionIndex: sessionIndex,
                    sessionCount: effectiveSessionCount
                )
                : nil

            let (prompt, systemPrompt) = buildChainPrompt(
                sessionIndex: sessionIndex,
                sessionCount: effectiveSessionCount,
                query: query,
                context: sessionContext,
                previousInsights: insightsForPrompt,
                maxInsightLength: reasoningPolicy.isUnlimitedMode
                    ? 600 : (reasoningPolicy.isDeepThinkMode ? 800 : config.maxInsightLength),
                sessionObjective: sessionObjective,
                evidenceState: evidenceStateLine(evidenceTracker),
                wholeChunkContext: sessionContextIsWhole.indices.contains(contextIndex)
                    && sessionContextIsWhole[contextIndex]
            )

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Execute session with proper consent + context overflow recovery
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            // FIXED: Reduce maxTokens to leave room for context within 4096 limit
            // Budget: system(100) + prompt+context+insights(~2500) + output(700) = ~3300 tokens
            // Increased from 500 to give sessions room for detailed prose instead of truncated bullets
            let sessionMaxTokens = reasoningPolicy.isUnlimitedMode ? 700 : (reasoningPolicy.isDeepThinkMode ? 700 : 600)

            // FIXED: Disable tools for ALL sessions — multi-query retrieval already
            // gathered all needed chunks. Session 1 tool calls waste tokens on useless
            // searches like search_exact_pattern("What's the button do?") which matches nothing.
            // Tool schema alone costs ~400 tokens we can't afford in a 4096 budget.
            let disableToolsForSession = true

            // Attempt execution with automatic context reduction on overflow
            var sessionPrompt = prompt
            let maxRetries = 2

            // CRITICAL FIX: Pass context as empty string to generateWithProperConsent.
            // buildChainPrompt() already embeds DOCUMENTS: in the prompt text.
            // Passing context AGAIN causes LLMService to wrap CONTEXT: around BOTH,
            // resulting in context appearing TWICE in the LLM input — doubling token usage.
            // This was the root cause of constant context overflow (4521+ tokens on a 4096 limit).
            var response: LLMResponse? = nil
            for retryCount in 0...maxRetries {
                // Check cancellation before each LLM call — if user sent a new query,
                // the RAGService cancels this task and we should stop immediately.
                if Task.isCancelled {
                    Log.info("[ReasoningChain] Cancelled before session \(sessionNum) LLM call", category: .llm)
                    break
                }
                do {
                    response = try await ragService.generateWithProperConsent(
                        prompt: sessionPrompt,
                        context: "",
                        systemPrompt: systemPrompt,
                        maxTokens: sessionMaxTokens,
                        disableTools: disableToolsForSession,
                        // The evidence for this session is real, but it lives inside
                        // `sessionPrompt` (see the context: "" note above), so the
                        // planner could not see it and judged every session
                        // `insufficientEvidence` → `.abstain`. All eight sessions then
                        // returned the abstention text as their "insight", which got
                        // condensed and fed to the final synthesis — telling the
                        // synthesizer there was no evidence while twenty chunks sat
                        // beside it. `sourceChunks` is planning-only and is never
                        // rendered into the prompt, so passing it here restores an
                        // honest sufficiency signal without reintroducing the context
                        // doubling that the empty `context` guards against.
                        sourceChunks: chunks,
                        forceOnDevice: true
                    )
                    break  // Success - exit retry loop
                } catch {
                    // By the error's type (`ModelErrorClassifier`). The words "context", "exceeded",
                    // "4096" and "token" were tested one at a time here, so the unsupported-language
                    // message ("Try rephrasing with more context") was treated as an overflow.
                    let failureKind = ModelErrorClassifier.kind(of: error)
                    let isContextOverflow = failureKind == .contextOverflow
                    let retriesLeft = retryCount < maxRetries
                    VerificationJournal.record(
                        "model.failure",
                        ["kind": "\(failureKind)", "mode": "agentic",
                            "action": isContextOverflow && retriesLeft
                                ? "shrinkPrompt"
                                : (failureKind == .transient || failureKind == .rateLimited) && retriesLeft
                                    ? "retrySamePrompt" : "endSession"])

                    if isContextOverflow && retryCount < maxRetries {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) context overflow, retry \(retryCount + 1)/\(maxRetries) with reduced prompt",
                            category: .llm)

                        // Reduce prompt by truncating context and insights more aggressively
                        let reductionFactor = 1.0 - (Double(retryCount + 1) * 0.3)  // 70%, then 40%
                        let reducedInsights = insightsForPrompt.map {
                            String($0.prefix(Int(Double($0.count) * reductionFactor)))
                        }
                        // A whole-chunk window that overflowed goes back to sentence extraction over
                        // the same chunks before it is cut. A raw prefix of whole chunks is the first
                        // chunk and part of the second, and windows are disjoint, so the rest of this
                        // window would never be read.
                        var overflowBase = sessionContext
                        if sessionContextIsWhole.indices.contains(contextIndex), sessionContextIsWhole[contextIndex],
                            sessionWindowRanges.indices.contains(contextIndex)
                        {
                            let windowRange = sessionWindowRanges[contextIndex]
                            let extraction = await ragService.extractRelevantSentences(
                                from: Array(routedChunks[windowRange]),
                                query: query,
                                maxChars: contextBudget,
                                compact: true,
                                labelOffset: windowRange.lowerBound
                            )
                            if extraction.context.trimmingCharacters(in: .whitespacesAndNewlines).count >= 200 {
                                overflowBase = extraction.context
                            }
                        }
                        let reducedContext = String(
                            overflowBase.prefix(Int(Double(overflowBase.count) * reductionFactor)))

                        // Rebuild prompt with reduced content
                        let (reducedPrompt, _) = buildChainPrompt(
                            sessionIndex: sessionIndex,
                            sessionCount: effectiveSessionCount,
                            query: query,
                            context: reducedContext,
                            previousInsights: reducedInsights,
                            maxInsightLength: Int(Double(config.maxInsightLength) * reductionFactor),
                            sessionObjective: sessionObjective
                        )
                        sessionPrompt = reducedPrompt
                        continue
                    }

                    // A transient decode failure from the on-device model, seen on
                    // device as `ParsingError` / "Session ended without producing a
                    // response". It is the same failure that hits MultiQuery
                    // expansion and SmartReply intermittently, and it is more likely
                    // immediately after a rate-limit backoff. Nothing about the
                    // prompt is wrong, so retry it unchanged rather than shrinking
                    // it — the overflow path above would reduce a prompt that was
                    // never too large. Matching on the SDK type as well as the text
                    // because `localizedDescription` collapses to the same generic
                    // "Failed to parse generated content" for several causes.
                    // The classifier knows both messages the app writes for an unreadable
                    // response. The text test here knew one, so "could not be parsed" was never
                    // retried.
                    let isTransientGenerationFailure = failureKind == .transient || failureKind == .rateLimited

                    if isTransientGenerationFailure && retryCount < maxRetries {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) transient generation failure "
                                + "(\(type(of: error))), retry \(retryCount + 1)/\(maxRetries) with the "
                                + "same prompt after a short backoff",
                            category: .llm
                        )
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        continue
                    }

                    // Out of retries for this session. Leave `response` nil and let
                    // the guard below decide whether the chain can carry on; a dead
                    // session is not necessarily a dead query.
                    if chainInsights.isEmpty {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) failed with no insights yet: "
                                + "\(type(of: error)) — \(error.localizedDescription)",
                            category: .llm
                        )
                        break
                    }
                    Log.warning(
                        "[ReasoningChain] Session \(sessionNum) failed, terminating chain early: \(error)",
                        category: .llm)
                    // Return result with what we've accumulated so far
                    return ReasoningChainResult(
                        finalAnswer: cleanupFinalAnswer(chainInsights.last ?? "Unable to complete analysis."),
                        chainInsights: chainInsights,
                        totalTokens: totalTokens,
                        sessionCount: sessionNum - 1,
                        confidence: cumulativeConfidence,
                        sources: Array(allSources),
                        evidenceCoverage: evidenceTracker.subQuestionConfidence,
                        evidenceCoverageTarget: reasoningPolicy.evidenceCoverageTarget(
                            for: evidenceTracker.subQuestions.count
                        ),
                        unansweredQuestions: evidenceTracker.unansweredQuestions,
                        routedChunks: routedChunks
                    )
                }
            }

            // If we exhausted retries without success, use what we have
            guard let successResponse = response else {
                if chainInsights.isEmpty {
                    // One dead session must not destroy the query. Each session reads
                    // a *different* rotating window of the same retrieved evidence, so
                    // a later one can succeed where this one did not.
                    //
                    // Before this, a single transient `ParsingError` on session 1 threw
                    // the whole query away and the user got "Failed to parse generated
                    // content" with no answer — observed on device, with seven untried
                    // context windows still available and retrieval having succeeded.
                    if sessionIndex < effectiveMaxSessions - 1 {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) produced nothing; advancing to the "
                                + "next context window (\(effectiveMaxSessions - sessionNum) remaining)",
                            category: .llm
                        )
                        continue
                    }
                    // Every session failed. `contextWindowExceeded` was misleading here
                    // — the last failure was usually a decode error, not an overflow.
                    Log.error(
                        "[ReasoningChain] All \(effectiveMaxSessions) sessions failed to produce an insight",
                        category: .llm
                    )
                    throw LLMError.generationFailed(
                        "The on-device model did not return a usable response across "
                            + "\(effectiveMaxSessions) reasoning sessions."
                    )
                }
                Log.warning(
                    "[ReasoningChain] Session \(sessionNum) exhausted retries, using accumulated insights",
                    category: .llm)
                return ReasoningChainResult(
                    finalAnswer: cleanupFinalAnswer(chainInsights.last ?? "Unable to complete analysis."),
                    chainInsights: chainInsights,
                    totalTokens: totalTokens,
                    sessionCount: sessionNum - 1,
                    confidence: cumulativeConfidence,
                    sources: Array(allSources),
                    evidenceCoverage: evidenceTracker.subQuestionConfidence,
                    evidenceCoverageTarget: reasoningPolicy.evidenceCoverageTarget(
                        for: evidenceTracker.subQuestions.count
                    ),
                    unansweredQuestions: evidenceTracker.unansweredQuestions,
                    routedChunks: routedChunks
                )
            }

            totalTokens += successResponse.tokensGenerated

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Check for early completion signal
            // If the model says "ANSWER COMPLETE" or "NOT FOUND", stop early
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let responseText = successResponse.text.uppercased()
            let isAnswerComplete =
                responseText.contains("ANSWER COMPLETE") || responseText.contains("NOT FOUND IN DOCUMENTS")
                || responseText.contains("DOCUMENTS DO NOT CONTAIN")

            if isAnswerComplete && sessionNum >= 2 {
                Log.info(
                    "[ReasoningChain] Early termination: model signaled answer complete — breaking to synthesis",
                    category: .llm)
                // Don't append a near-empty termination response to insights.
                // Break out of the session loop and let synthesis handle the final answer.
                // This ensures Deep Think and Maximum modes always run their synthesis pass
                // instead of returning raw concatenated insights.
                break
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Extract insight to pass to next session
            // For FINAL session, keep FULL response (don't truncate!)
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            let isFinalSession = sessionIndex == config.sessionCount - 1
            let insight: String

            if isFinalSession {
                // For final synthesis, extract the full answer (not truncated)
                insight = extractFinalAnswer(from: successResponse.text)
            } else {
                // For intermediate sessions, extract condensed insight.
                // Strip echoed prompt headers and invented tool-call syntax first —
                // otherwise a contaminated insight becomes the next session's PRIOR
                // FINDINGS and teaches the next model to produce the same thing.
                insight = stripPromptEchoAndToolNoise(
                    from: extractInsight(from: successResponse.text, maxLength: config.maxInsightLength),
                    systemPrompt: systemPrompt
                )
            }

            // Filter out "no new information" responses — they pollute the chain
            // and cause synthesis to include garbage like "No new information found."
            let isEmptyInsight = isUnusableInsight(insight)
            if isEmptyInsight && !isFinalSession {
                Log.debug(
                    "[ReasoningChain] Session \(sessionNum) returned empty/refusal insight — skipping", category: .llm)
                continue
            }

            var evidenceConfidence: Float? = nil
            var evidenceCoverage: Float = 0
            var evidenceNovelty: Float = 0
            var evidenceSaturation: Float = 0

            if reasoningPolicy.usesEvidenceDrivenStopping {
                if contextIndex < sessionSourceSets.count {
                    usedWindowSources.formUnion(sessionSourceSets[contextIndex])
                }

                let factUpdate = evidenceTracker.addFacts(from: insight)
                evidenceCoverage = evidenceTracker.subQuestionConfidence
                evidenceNovelty = factUpdate.noveltyScore

                if factUpdate.addedFacts == 0 || factUpdate.noveltyScore < reasoningPolicy.lowNoveltyThreshold {
                    lowNoveltyStreak += 1
                } else {
                    lowNoveltyStreak = 0
                }

                let usedSourceCoverage = Float(usedWindowSources.count) / Float(max(allSources.count, 1))
                let (calculatedConfidence, saturationScore) = AgenticPolicyService.calculateProgressConfidence(
                    allInsights: chainInsights + [insight],
                    query: query,
                    sessionNum: sessionNum,
                    subQuestionConfidence: evidenceCoverage,
                    noveltyScore: factUpdate.noveltyScore,
                    sourceCoverage: usedSourceCoverage,
                    maxConfidence: reasoningPolicy.maxConfidence,
                    sessionBudget: effectiveMaxSessions
                )
                evidenceConfidence = calculatedConfidence
                evidenceSaturation = saturationScore

                if reasoningPolicy.shouldTreatAsSaturated(
                    saturationScore: saturationScore,
                    noveltyScore: factUpdate.noveltyScore,
                    newlyAnsweredSubQuestions: factUpdate.newlyAnsweredSubQuestions
                ) {
                    saturationStreak += 1
                } else {
                    saturationStreak = 0
                }
            }

            // Parse confidence if present, or estimate based on response quality
            // Do this BEFORE appending insight so we can compare with previous insights
            if let conf = parseConfidence(from: successResponse.text) {
                if let evidenceConfidence {
                    let blendedConfidence = min(
                        (evidenceConfidence * 0.8) + (conf * 0.2), reasoningPolicy.maxConfidence)
                    cumulativeConfidence = max(cumulativeConfidence, blendedConfidence)
                } else {
                    cumulativeConfidence = (cumulativeConfidence + conf) / 2
                }
            } else if let evidenceConfidence {
                cumulativeConfidence = max(cumulativeConfidence, min(evidenceConfidence, reasoningPolicy.maxConfidence))
                Log.info(
                    "[ReasoningChain] Evidence confidence: \(Int(cumulativeConfidence * 100))% (coverage: \(Int(evidenceCoverage * 100))%, novelty: \(Int(evidenceNovelty * 100))%, saturation: \(Int(evidenceSaturation * 100))%, lowNovelty=\(lowNoveltyStreak), saturationStreak=\(saturationStreak))",
                    category: .llm
                )
            } else if reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode {
                // Heuristic confidence for Maximum mode:
                // Designed to require 8-15+ sessions before hitting 98%
                // Each component is conservative to ensure deep exploration

                // 1. Session contribution (up to 55%) - more sessions = more exploration
                // DEEP THINK: 8% per session (4 sessions = 32%, 6 = 48%, 7 = 55% cap)
                // MAXIMUM MODE: 3% per session for visible progress (more conservative for long runs)
                // Deep Think needs 85% reachable: 55% session + 20% length + 10% citations = 85%
                let sessionContributionRate: Float = reasoningPolicy.isDeepThinkMode ? 0.08 : 0.03
                let sessionContribution = min(sessionContributionRate * Float(sessionNum), 0.55)

                // 2. Length contribution (up to 20%) - longer insights = more substance
                // Requires 2500+ chars for full bonus
                let lengthContribution = min(Float(insight.count) / 2500.0, 0.20)

                // 3. Citation bonus (up to 10%) - grounded in sources
                let hasCitations = insight.contains("[S") || insight.contains("S1") || insight.contains("S2")
                let citationBonus: Float = hasCitations ? 0.10 : 0

                // 4. Repetition detection (up to 25%) - if repeating, we've exhausted the topic
                // Compare current insight with PREVIOUS insights (before appending)
                // MAXIMUM MODE: Much higher thresholds - designed for deep exploration with many documents
                var repetitionBonus: Float = 0

                // Require more sessions before checking repetition in Maximum mode
                let minSessionsForRepetitionCheck = reasoningPolicy.repetitionCheckStartSession

                if chainInsights.count >= minSessionsForRepetitionCheck {
                    // Use more unique words (min 4 chars, take more words for better sampling)
                    let currentWords = Set(
                        insight.lowercased().split(separator: " ")
                            .filter { $0.count > 4 && !Self.commonStopWords.contains(String($0)) }
                            .prefix(100))
                    var similarityCount = 0
                    var maxOverlapRatio: Float = 0
                    var consecutiveSimilar = 0
                    var lastWasSimilar = false

                    // Check last 4 previous insights (not including current)
                    for prevInsight in chainInsights.suffix(4) {
                        let prevWords = Set(
                            prevInsight.lowercased().split(separator: " ")
                                .filter { $0.count > 4 && !Self.commonStopWords.contains(String($0)) }
                                .prefix(100))
                        let overlap = currentWords.intersection(prevWords).count
                        let overlapRatio = Float(overlap) / Float(max(currentWords.count, 1))
                        maxOverlapRatio = max(maxOverlapRatio, overlapRatio)

                        // Higher threshold for Maximum mode (65% vs 50%)
                        let similarityThreshold = reasoningPolicy.repetitionSimilarityThreshold
                        if overlapRatio > similarityThreshold {
                            similarityCount += 1
                            if lastWasSimilar { consecutiveSimilar += 1 }
                            lastWasSimilar = true
                        } else {
                            lastWasSimilar = false
                        }
                    }

                    // MAXIMUM MODE: Require 3 consecutive similar OR 90%+ overlap before forcing termination
                    // Standard mode: 3+ similar OR 75%+ overlap
                    let forceTerminationThreshold = reasoningPolicy.repetitionForceTerminationThreshold
                    let forceTerminationCount = reasoningPolicy.repetitionForceTerminationCount
                    let requireConsecutive = reasoningPolicy.repetitionRequiresConsecutive

                    let shouldForceTerminate =
                        requireConsecutive
                        ? (consecutiveSimilar >= forceTerminationCount || maxOverlapRatio > forceTerminationThreshold)
                        : (similarityCount >= forceTerminationCount || maxOverlapRatio > forceTerminationThreshold)

                    if shouldForceTerminate {
                        // Repetition means we're STUCK, NOT that we found the correct answer.
                        // Don't boost confidence — the answer may be completely wrong.
                        // Just set a termination flag so the loop exits.
                        repetitionBonus = 0.0
                        Log.info(
                            "[ReasoningChain] Strong repetition detected (\(similarityCount)/4 similar, consecutive: \(consecutiveSimilar), max overlap: \(Int(maxOverlapRatio * 100))%) - stopping to avoid loops",
                            category: .llm)

                        // FIXED: Do NOT set confidence to threshold. That caused 85% confidence
                        // on wrong answers just because the LLM repeated itself.
                        // Instead, just break out of the session loop.
                        let minSessionsBeforeForceStop = reasoningPolicy.minSessionsBeforeRepetitionStop
                        if sessionNum >= minSessionsBeforeForceStop {
                            Log.info(
                                "[ReasoningChain] Forcing early termination due to repetition loop (after \(sessionNum) sessions)",
                                category: .llm)
                            // DON'T touch cumulativeConfidence — keep it at whatever it actually is
                            // The loop will exit because we'll set a flag below
                            chainInsights.append(insight)  // Save last insight before breaking
                            break  // Exit the session loop immediately
                        } else {
                            Log.info(
                                "[ReasoningChain] Repetition detected but continuing (session \(sessionNum) < \(minSessionsBeforeForceStop) minimum)",
                                category: .llm)
                        }
                    } else if similarityCount >= 2 || maxOverlapRatio > 0.60 {
                        // Moderate repetition - slight penalty, not bonus
                        repetitionBonus = 0.0  // Don't reward repetition
                        Log.info(
                            "[ReasoningChain] Moderate repetition detected (overlap: \(Int(maxOverlapRatio * 100))%) - no confidence boost",
                            category: .llm)
                    }
                }

                // 5. Exhaustion bonus (up to 15%) - if we're deep in sessions, boost confidence
                // Only kicks in after 10+ sessions (conservative for Maximum mode)
                let exhaustionBonus: Float =
                    sessionNum >= 15 ? 0.15 : (sessionNum >= 12 ? 0.10 : (sessionNum >= 10 ? 0.05 : 0))

                // Only calculate confidence normally if we haven't forced termination
                let confidenceCap = reasoningPolicy.maxConfidence
                if cumulativeConfidence < confidenceCap {
                    let estimatedConfidence =
                        sessionContribution + lengthContribution + citationBonus + repetitionBonus + exhaustionBonus
                    cumulativeConfidence = max(cumulativeConfidence, min(estimatedConfidence, confidenceCap))
                }

                Log.info(
                    "[ReasoningChain] Confidence: \(Int(cumulativeConfidence * 100))% (session: \(Int(sessionContribution * 100))%, length: \(Int(lengthContribution * 100))%, citations: \(Int(citationBonus * 100))%, repetition: \(Int(repetitionBonus * 100))%, exhaustion: \(Int(exhaustionBonus * 100))%)",
                    category: .llm)
            }

            // Append insight AFTER confidence check (so we compare with previous insights)
            chainInsights.append(insight)

            // Emit thinking step
            // Session 0 was labelled `.searching` and therefore displayed as
            // RETRIEVAL, but retrieval completed before the chain started; session 0
            // is the initial *analysis* pass over that evidence.
            let stepType: ThinkingStep.StepType =
                switch sessionIndex {
                case config.sessionCount - 1: .synthesizing
                default: .analyzing
                }

            let step = ThinkingStep(
                id: UUID(),
                type: stepType,
                input: "Session \(sessionNum): \(sessionPromptDescription(sessionIndex, config.sessionCount))",
                output: isFinalSession ? "Synthesizing final answer..." : insight,
                tokensUsed: successResponse.tokensGenerated,
                duration: 0.5,
                timestamp: Date(),
                confidence: reasoningPolicy.shouldReportConfidence ? cumulativeConfidence : nil
            )
            await onStep?(step)

            Log.debug("[ReasoningChain] Session \(sessionNum) insight: \(insight.prefix(80))...", category: .llm)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Final synthesis from chain
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // For UNLIMITED MODE: Run a dedicated exhaustive synthesis pass
        // This ensures we get a comprehensive answer, not just the last insight
        let finalAnswer: String
        if reasoningPolicy.isUnlimitedMode, chainInsights.count >= 3 {
            Log.info(
                "[ReasoningChain] Running exhaustive synthesis for Maximum mode (\(chainInsights.count) insights)...",
                category: .llm)

            // CRITICAL: Apple FM API enforces 4096 token limit for BOTH on-device AND PCC
            // (TN3193: The 65K server capacity is NOT exposed via FoundationModels framework)
            // Budget: ~1500 tokens for insights, ~500 for prompt overhead, ~2000 for output
            let maxInsightChars = 5000  // ~1250 tokens for insights (conservative)
            var condensedInsights: [String] = []
            var totalChars = 0

            // Take insights from end (most refined) to beginning, but include more
            for insight in chainInsights.reversed() {
                let trimmed = insight.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if totalChars + trimmed.count <= maxInsightChars {
                    condensedInsights.insert(trimmed, at: 0)
                    totalChars += trimmed.count
                } else if condensedInsights.isEmpty {
                    // At least include a truncated version of the last insight
                    condensedInsights.append(String(trimmed.prefix(maxInsightChars)))
                    break
                } else {
                    break
                }
            }

            Log.info(
                "[ReasoningChain] Synthesis will use \(condensedInsights.count)/\(chainInsights.count) insights (\(totalChars) chars)",
                category: .llm)

            let insightsSummary = condensedInsights.enumerated()
                .map { "[\($0.offset + 1)] \($0.element)" }
                .joined(separator: "\n\n")

            // PCC can handle much larger prompts (65K context)
            // Structure the prompt for comprehensive synthesis
            var exhaustivePrompt = "ORIGINAL QUESTION: " + query + "\n\n"
            exhaustivePrompt += "RESEARCH FINDINGS (" + String(actualSessionCount) + " deep-dive sessions):\n"
            exhaustivePrompt += insightsSummary + "\n\n"
            exhaustivePrompt += "TASK: Synthesize an answer that DIRECTLY addresses: \"" + query + "\"\n\n"
            exhaustivePrompt += "REQUIREMENTS:\n"
            exhaustivePrompt += "- First, verify the findings actually answer the original question\n"
            exhaustivePrompt += "- Include specific values, numbers, and specifications found\n"
            exhaustivePrompt += "- Cite specific sources as [S1], [S2], etc.\n"
            exhaustivePrompt += "- Be thorough but stay focused on what was asked\n"
            exhaustivePrompt += "- Write in detailed prose with complete sentences and full paragraphs\n"
            exhaustivePrompt += "- Use ### section headers and **bold** sparingly for key terms\n"
            exhaustivePrompt += "- Use bullet points ONLY for actual lists of items or specifications\n\n"
            exhaustivePrompt += "DIRECT ANSWER:"

            var exhaustiveSystemPrompt = "You synthesize research into a direct, comprehensive answer. "
            exhaustiveSystemPrompt += "First verify the findings answer the original question. "
            exhaustiveSystemPrompt += "If findings are about something else, note that clearly. "
            exhaustiveSystemPrompt += "Include all specific values, numbers, and specifications. "
            exhaustiveSystemPrompt += "Write in detailed prose with complete sentences and natural paragraphs. "
            exhaustiveSystemPrompt +=
                "Use ### headers and **bold** sparingly for key terms. Only use bullets for actual lists."

            // Apple FM API: 4096 token limit applies to BOTH on-device and PCC
            // The 65K server capacity is internal to Apple, not exposed to developers (TN3193)
            // Budget: Total 4096 = ~1500 prompt + ~1500 insights + ~1000 buffer → leaves ~1000-1500 for output
            let synthesisMaxTokens = 1500  // Realistic within 4096 total budget

            do {
                Log.info(
                    "[ReasoningChain] Exhaustive synthesis: requesting up to \(synthesisMaxTokens) tokens (4096 total limit)",
                    category: .llm)
                let synthesisResponse = try await LLMStreamingContext.$handler.withValue(LLMStreamingContext.answerHandler) {
                    try await ragService.generateWithProperConsent(
                        prompt: exhaustivePrompt,
                        context: "",
                        systemPrompt: exhaustiveSystemPrompt,
                        maxTokens: synthesisMaxTokens,
                        disableTools: true,
                        qualityMode: .maximum,
                        sourceChunks: chunks
                    )
                }
                // Clean up the synthesis output
                finalAnswer = cleanupFinalAnswer(synthesisResponse.text)
                totalTokens += synthesisResponse.tokensGenerated
                Log.info(
                    "[ReasoningChain] Exhaustive synthesis: generated \(synthesisResponse.tokensGenerated) tokens (\(finalAnswer.count) chars)",
                    category: .llm)
            } catch {
                Log.warning(
                    "[ReasoningChain] Exhaustive synthesis failed, using last insight: \(error)", category: .llm)
                finalAnswer = cleanupFinalAnswer(
                    chainInsights.last ?? "Unable to synthesize answer from reasoning chain.")
            }
        } else if reasoningPolicy.isDeepThinkMode, chainInsights.count >= 2 {
            // DEEP THINK MODE: Run a synthesis pass to combine all session findings.
            // Without this, the answer is just the last raw insight (which might be
            // "No new information found" if the last session had no new details).
            // Synthesis merges ALL accumulated findings into one comprehensive answer.
            Log.info(
                "[ReasoningChain] Running Deep Think synthesis (\(chainInsights.count) insights)...", category: .llm)

            // Budget for Deep Think synthesis: keep it tight within 4096
            let maxInsightChars = 3000
            var condensedInsights: [String] = []
            var totalChars = 0

            // Include all insights, truncating individual ones if needed
            for insight in chainInsights {
                let trimmed = insight.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Skip empty or "no new info" insights
                if trimmed.count < 20 || trimmed.lowercased().contains("no new information") {
                    continue
                }
                if totalChars + trimmed.count <= maxInsightChars {
                    condensedInsights.append(trimmed)
                    totalChars += trimmed.count
                } else {
                    // Truncate and include
                    let remaining = maxInsightChars - totalChars
                    if remaining > 100 {
                        condensedInsights.append(String(trimmed.prefix(remaining)))
                    }
                    break
                }
            }

            if condensedInsights.isEmpty {
                // All insights were empty/trivial — fall back to last one
                finalAnswer = cleanupFinalAnswer(
                    chainInsights.last ?? "Unable to synthesize answer from reasoning chain.")
            } else {
                let insightsSummary = condensedInsights.enumerated()
                    .map { "[\($0.offset + 1)] \($0.element)" }
                    .joined(separator: "\n")

                // The findings carry the sessions' own labels ([S5], [S13]); the synthesis sees no passages. The prompt
                // ended "Cite as [S1], [S2].", and the model copied the example: on the owner's iPhone (2026-10-21) a
                // two-document comparison's write-up scored citations 0/5 in Self-RAG, because its labels pointed at
                // passages that did not hold the claims (5.7).
                let synthesisPrompt = """
                    QUESTION: \(query)

                    ALL FINDINGS:
                    \(insightsSummary)

                    Write a comprehensive, detailed answer to: "\(query)"
                    Combine ALL findings into flowing prose with complete sentences and full paragraphs.
                    Use ### section headers to organize topics. Use **bold** sparingly for key terms only.
                    Write naturally — use paragraphs for explanations, and bullets only for actual sequential steps or specification lists.
                    Include every relevant detail found across all sessions.
                    The findings already carry source labels such as [S5] or [S13]. Keep each label with the sentence it supports, written exactly as it appears in the findings. Never invent a label, renumber one, or move a label to a sentence it did not support.
                    """

                let synthesisSystemPrompt =
                    "Combine all research findings into one comprehensive, well-written answer. Write in detailed prose with complete sentences and natural paragraphs. Use ### headers to organize sections. Use **bold** sparingly for key terms only. Only use bullet points for actual lists of items."

                do {
                    let synthesisResponse = try await LLMStreamingContext.$handler.withValue(LLMStreamingContext.answerHandler) {
                        try await ragService.generateWithProperConsent(
                            prompt: synthesisPrompt,
                            context: "",
                            systemPrompt: synthesisSystemPrompt,
                            maxTokens: 1500,
                            disableTools: true,
                            qualityMode: .deepThink,
                            sourceChunks: chunks
                        )
                    }
                    finalAnswer = cleanupFinalAnswer(synthesisResponse.text)
                    totalTokens += synthesisResponse.tokensGenerated
                    Log.info(
                        "[ReasoningChain] Deep Think synthesis: \(synthesisResponse.tokensGenerated) tokens (\(finalAnswer.count) chars)",
                        category: .llm)
                } catch {
                    Log.warning(
                        "[ReasoningChain] Deep Think synthesis failed, using combined insights: \(error)",
                        category: .llm)
                    // Fallback: concatenate all non-trivial insights
                    finalAnswer = cleanupFinalAnswer(condensedInsights.joined(separator: "\n\n"))
                }
            }
        } else {
            // Standard mode: The last insight IS the final answer (session N is synthesis)
            finalAnswer = cleanupFinalAnswer(chainInsights.last ?? "Unable to synthesize answer from reasoning chain.")
        }

        if reasoningPolicy.isUnlimitedMode {
            Log.info(
                "[ReasoningChain] UNLIMITED MODE completed: \(actualSessionCount) sessions, \(totalTokens) tokens, \(Int(cumulativeConfidence * 100))% confidence",
                category: .llm)
        } else {
            Log.info(
                "[ReasoningChain] Completed \(actualSessionCount) sessions, \(totalTokens) total tokens", category: .llm
            )
        }

        return ReasoningChainResult(
            finalAnswer: finalAnswer,
            chainInsights: chainInsights,
            totalTokens: totalTokens,
            sessionCount: actualSessionCount,
            confidence: cumulativeConfidence,  // Don't artificially floor, report honestly
            sources: Array(allSources),
            evidenceCoverage: evidenceTracker.subQuestionConfidence,
            evidenceCoverageTarget: reasoningPolicy.evidenceCoverageTarget(
                for: evidenceTracker.subQuestions.count
            ),
            unansweredQuestions: evidenceTracker.unansweredQuestions,
            routedChunks: routedChunks
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
}

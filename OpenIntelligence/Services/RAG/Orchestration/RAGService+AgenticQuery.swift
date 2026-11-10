//
//  RAGService+AgenticQuery.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Thinking Timeline Helpers

    @MainActor
    func resetThinkingTimeline() {
        thinkingEvents.removeAll(keepingCapacity: false)
    }

    func emitThinkingEvent(
        _ kind: ThinkingEvent.Kind,
        title: String,
        detail: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.thinkingEvents.count >= Self.thinkingEventLimit {
                let overflow = self.thinkingEvents.count - Self.thinkingEventLimit + 1
                if overflow > 0 {
                    self.thinkingEvents.removeFirst(overflow)
                }
            }
            self.thinkingEvents.append(ThinkingEvent(kind: kind, title: title, detail: detail))
        }
    }

    @MainActor
    private func beginSelfTuning(for containerId: UUID) -> Bool {
        if selfTuningInFlight.contains(containerId) {
            return false
        }
        selfTuningInFlight.insert(containerId)
        return true
    }

    @MainActor
    private func finishSelfTuning(for containerId: UUID) {
        selfTuningInFlight.remove(containerId)
    }

    private func handleSelfTuning(
        for containerId: UUID,
        report: LibraryIntelligenceCenter.IntelligenceReport,
        triggerAllowsScheduling: Bool
    ) async {
        // IMPORTANT:
        // Self-tuning rebuilds call `reembedDocuments()`, which removes and re-adds documents.
        // `addDocument()` triggers `refreshIntelligence(force: true)`, which can re-enter this
        // method. Without a guard, we can accidentally schedule a *new* rebuild while the
        // current rebuild is still running, creating an infinite “re-upload/re-embed” loop.
        let isSelfTuningInFlight = await MainActor.run { self.selfTuningInFlight.contains(containerId) }
        if isSelfTuningInFlight {
            return
        }

        // CRITICAL FIX: Skip self-tuning if we just finished ingesting documents.
        // This prevents the scenario where processing a large PDF completes and then
        // immediately triggers re-embedding of ALL documents including what was just processed.
        // Self-tuning should wait until the user's batch is fully complete.
        let isInCooldown = await MainActor.run { () -> Bool in
            if let lastCompletion = self.lastIngestionCompletionTime[containerId] {
                let elapsed = Date().timeIntervalSince(lastCompletion)
                if elapsed < Self.selfTuningCooldownSeconds {
                    Log.info(
                        "[SelfTuning] Skipping auto-rebuild for container \(containerId) - "
                            + "in cooldown period (\(String(format: "%.1f", elapsed))s < \(Self.selfTuningCooldownSeconds)s)",
                        category: .ingestion
                    )
                    return true
                }
            }
            return false
        }
        if isInCooldown {
            return
        }

        guard
            let container = await MainActor.run(
                resultType: KnowledgeContainer?.self,
                body: {
                    self.containerService.containers.first { $0.id == containerId }
                }
            )
        else { return }
        guard container.autoAdaptDimension else { return }

        let (updated, reasons) = Self.resolveAutoAdjustments(for: container, report: report)
        if updated != container {
            await MainActor.run {
                self.containerService.updateContainer(updated)
            }
        }

        if triggerAllowsScheduling, !reasons.isEmpty, !report.corpus.isEstimate {
            scheduleSelfTuningRebuild(for: containerId, reasons: reasons)
        }
    }

    private func executeAgenticPrecisionLookupIfAvailable(
        question: String,
        containerId: UUID,
        qualityMode: RAGQualityMode,
        startTime: Date
    ) async throws -> RAGResponse? {
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
        guard !isConceptualLookupQuery(question),
            answerIntent.isExtractiveFirst || isPrecisionValueQuery(question)
        else {
            return nil
        }

        emitThinkingEvent(
            .retrieval,
            title: "Precision lookup",
            detail: "Checking exact source values before multi-session reasoning"
        )

        func buildPrecisionResponse(
            directAnswer: String,
            precisionChunks: [RetrievedChunk],
            retrievalTime: TimeInterval,
            strategy: String
        ) async -> RAGResponse? {
            // A value lifted from a source skips the whole reasoning run, so it has to answer the question: a page
            // range or a table cell can match "how much" and say nothing (`AnswerResponsivenessJudge`). One that does
            // not answer falls through to the full run.
            let directJudgment = await judgeResponsiveness(question: question, answer: directAnswer, stage: "extracted")
            if directJudgment?.verdict == AnswerResponsiveness.none {
                emitThinkingEvent(
                    .retrieval,
                    title: "Exact value set aside",
                    detail: "It doesn't answer the question; reasoning it out instead"
                )
                return nil
            }
            emitThinkingEvent(
                .generation,
                title: "Direct answer locked",
                detail: "Exact value extracted from retrieved source"
            )
            let precisionConfidence = max(0.90, precisionChunks.first?.similarityScore ?? 0.0)
            emitThinkingEvent(
                .confidence,
                title: "Confidence: very high",
                detail: "\(String(format: "%.0f%%", precisionConfidence * 100)) source-locked"
            )

            var precisionAnswer = directAnswer
            var precisionWarnings: [String] = []
            var gatingDecision = "agentic_precision_extractive_override"
            var finalConfidence = precisionConfidence
            var structuredAnswer = StructuredAnswer.from(
                response: directAnswer,
                retrievedChunks: precisionChunks,
                answerIntent: answerIntent,
                verificationResult: nil,
                loops: 1
            )

            #if canImport(FoundationModels)
                if #available(iOS 26.0, *),
                    let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                        query: question,
                        candidateAnswer: directAnswer,
                        retrievedChunks: precisionChunks,
                        answerIntent: answerIntent,
                        verificationResult: nil,
                        isSourceLocked: true
                    )
                {
                    precisionAnswer = sourceOnlyOutcome.finalAnswer
                    structuredAnswer = sourceOnlyOutcome.structuredAnswer
                    gatingDecision = appendedGatingDecision(
                        gatingDecision,
                        sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                    )
                    precisionWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                    if sourceOnlyOutcome.shouldAbstain,
                        let abstentionReason = sourceOnlyOutcome.abstentionReason
                    {
                        precisionWarnings.append(abstentionReason)
                    }
                    finalConfidence =
                        sourceOnlyOutcome.shouldAbstain
                        ? min(precisionConfidence, 0.35)
                        : min(precisionConfidence, max(sourceOnlyOutcome.fidelityScore, 0.75))
                }
            #endif

            let precisionJudgment =
                precisionAnswer == directAnswer
                ? directJudgment
                : await judgeResponsiveness(question: question, answer: precisionAnswer, stage: "final")
            if let precisionJudgment {
                gatingDecision = appendedGatingDecision(gatingDecision, precisionJudgment.gatingToken)
            }

            let metadata = ResponseMetadata(
                timeToFirstToken: retrievalTime,
                totalGenerationTime: Date().timeIntervalSince(startTime),
                tokensGenerated: 0,
                tokensPerSecond: nil,
                modelUsed: "Direct Source Extraction (\(qualityMode.displayName))",
                retrievalTime: retrievalTime,
                retrievalConfigSummary: strategy,
                gatingDecision: gatingDecision,
                toolCallsMade: 0,
                usedAgenticMode: true,
                qualityModeName: qualityMode.displayName,
                originalQuery: question,
                reasoningTrace: [
                    "Precision lookup: found a high-confidence numeric source span and skipped multi-session synthesis."
                ]
            )

            await MainActor.run {
                self.deepThinkLiveSteps = 1
                self.deepThinkLiveConfidence = precisionConfidence
                self.deepThinkLiveTokens = 0
            }

            return RAGResponse(
                queryId: UUID(),
                retrievedChunks: precisionChunks,
                generatedResponse: resolvedDisplayResponse(
                    fallback: precisionAnswer,
                    structuredAnswer: structuredAnswer
                ),
                metadata: metadata,
                confidenceScore: finalConfidence,
                qualityWarnings: precisionWarnings,
                structuredAnswer: structuredAnswer
            )
        }

        let retrievalStart = Date()

        let embeddingContext = await resolveEmbeddingContext()
        let db = await dbFor(embeddingContext.containerId)
        let allChunks = RAGQueryScope.apply(to: try await db.readableChunks())  // narrowed when the question names documents
        let sniperChunks = specTableSniper(
            query: question,
            allChunks: allChunks,
            excludeIds: []
        )
        if let directAnswer = await highPrecisionLookupOverrideAnswer(
            question: question,
            answerIntent: answerIntent,
            retrievedChunks: sniperChunks
        ) {
            let retrievalTime = Date().timeIntervalSince(retrievalStart)
            emitThinkingEvent(
                .retrieval,
                title: "Spec sniper",
                detail: "+\(sniperChunks.count) targeted chunks via keyword+number co-occurrence"
            )
            return await buildPrecisionResponse(
                directAnswer: directAnswer,
                precisionChunks: sniperChunks,
                retrievalTime: retrievalTime,
                strategy: "Agentic precision lookup"
            )
        }

        let precisionChunks = try await executeFullRetrievalPipeline(
            query: question,
            topK: max(24, qualityMode.initialTopK),
            minSimilarity: 0.03,
            qualityMode: qualityMode,
            onDetailedEvent: nil
        )
        let retrievalTime = Date().timeIntervalSince(retrievalStart)

        guard
            let directAnswer = await highPrecisionLookupOverrideAnswer(
                question: question,
                answerIntent: answerIntent,
                retrievedChunks: precisionChunks
            )
        else {
            emitThinkingEvent(
                .verification,
                title: "Precision lookup",
                detail: "No high-confidence source span locked"
            )
            return nil
        }

        return await buildPrecisionResponse(
            directAnswer: directAnswer,
            precisionChunks: precisionChunks,
            retrievalTime: retrievalTime,
            strategy: "Agentic precision lookup"
        )
    }

    // MARK: - Agentic Query Execution

    /// Execute a multi-session agentic query for complex reasoning
    /// This bypasses the single-session 4K limit by orchestrating multiple focused LLM calls

    /// Log which document each `[Sn]` label the model was shown actually resolves to.
    ///
    /// Nothing printed this, which is why citation labels could point at the wrong document for an
    /// unknown length of time while every guard passed: the indices were in range, the chunks were
    /// real, and only the mapping was wrong. With this line a cited answer can be checked against
    /// its sources by reading one entry.
    ///
    /// Shared between the standard and agentic routes on purpose. The first version lived inline in
    /// the standard path only, and the first device capture after it shipped contained zero citation
    /// maps, because Deep Think does not take that path. Writing a second copy for the agentic route
    /// is how five call sites came to independently assume `prefix(used)`; there is one copy.
    func logCitationMap(_ chunks: [RetrievedChunk], rescued: Int = 0, route: String) {
        guard !chunks.isEmpty else { return }
        let map = chunks.enumerated().map { index, chunk -> String in
            let name = URL(fileURLWithPath: chunk.sourceDocument).lastPathComponent
            let page = chunk.pageNumber.map { " p.\($0)" } ?? ""
            let section = chunk.chunk.metadata.sectionTitle.map { " \($0)" } ?? ""
            return "S\(index + 1)=\(name.isEmpty ? "?" : name)\(page)\(section)"
        }.joined(separator: " | ")
        Log.info(
            "[RAG] Citation map (\(route), \(chunks.count) sources"
                + "\(rescued == 0 ? "" : ", \(rescued) via rescue")): \(map)",
            category: .retrieval
        )
    }

    func executeAgenticQuery(
        question: String,
        containerId: UUID,
        config: InferenceConfig?,
        qualityMode: RAGQualityMode,
        runtimeContext: QueryRuntimeContext
    ) async throws -> RAGResponse {
        // Deep Think and Maximum search through `resolveEmbeddingContext()`, which reads this and
        // falls back to the active library. Standard sets it further down; this path returned
        // before that line, so a question aimed at another library searched the active one. Only
        // the chat reached this path through 5.6, always with the active library.
        await MainActor.run { self.currentQueryContainerId = containerId }
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }

        // Capture the user's routing choice for the whole query. Every generation
        // in the agentic path reads this back; without it the model picker has no
        // effect on Deep Think or Maximum at all.
        await MainActor.run {
            self.activeUserRoutingPreference = UserRoutingPreference(config: config)
        }
        let routingPreference = await MainActor.run { self.activeUserRoutingPreference }

        // Adaptive generation profile for this query, if the owner turned the feature on. Resolved
        // here rather than in the caller because Deep Think and Maximum return into this function
        // before the Standard path's gate is reached, which is why the feature used to apply to
        // Standard only.
        //
        // Cleared on the way out so a later query that is not agentic, or runs with the toggle off,
        // cannot pick up a stale profile from this one.
        #if canImport(FoundationModels)
            let agenticProfile: FoundationModelGenerationProfile? =
                UserDefaults.standard.bool(forKey: "adaptiveInferenceProfiles")
                ? FoundationModelDynamicProfileRegistry
                    .profile(for: runtimeContext.queryProfile.answerIntent).generation
                : nil
            await MainActor.run { self.activeAdaptiveProfile = agenticProfile }
            defer { Task { @MainActor in self.activeAdaptiveProfile = nil } }
            if let agenticProfile {
                Log.info(
                    "[AdaptiveProfile] agentic intent=\(runtimeContext.queryProfile.answerIntent.rawValue) "
                        + "temperature=\(agenticProfile.temperature) [\(agenticProfile.rationale)]",
                    category: .llm
                )
            }
        #endif
        Log.info(
            "[QueryRuntime] User routing preference: \(routingPreference.fmPreference.rawValue) "
                + "(execContext=\(routingPreference.executionContext), "
                + "allowPCC=\(routingPreference.allowPrivateCloudCompute), "
                + "resolvesTo=\(routingPreference.requiresOnDevice ? "on-device only" : routingPreference.explicitlyPrefersPCC ? "PCC preferred" : "hybrid"))",
            category: .pipeline
        )

        let selectedContainer = await MainActor.run {
            self.containerService.containers.first { $0.id == containerId }
        }
        let selectedContainerName = selectedContainer?.name ?? "Library"
        let selectedRetrievalConfig = selectedContainer?.retrievalConfig ?? .default

        // Check if user selected Maximum (unlimited) mode
        let isUnlimitedMode = qualityMode.isUnlimitedMode
        let modeLabel = isUnlimitedMode ? "MAXIMUM REASONING MODE" : "AGENTIC REASONING MODE"

        // Pipeline Trace: Agentic mode header
        let raptorSummariesEnabled = await MainActor.run { settingsStore?.enableDocumentSummaries ?? true }
        let raptorRoutingEnabled = await MainActor.run { settingsStore?.enableQueryRouting ?? true }
        Log.pipelineHeader(
            mode: isUnlimitedMode ? "Maximum" : "Deep Think",
            raptorSummaries: raptorSummariesEnabled,
            raptorRouting: raptorRoutingEnabled
        )

        // Pipeline Trace: Agentic orchestration step
        Log.pipelineStep(
            "A", title: "Agentic Orchestration",
            details: [
                ("type", isUnlimitedMode ? "unlimited" : "multi-session"),
                ("confTarget", isUnlimitedMode ? "98%" : "85%"),
            ])

        Log.box(
            modeLabel,
            level: .info,
            category: .pipeline,
            content: [
                "📝 Query: \(question)",
                "🧠 Multi-session orchestration active",
                isUnlimitedMode ? "🔥 Unlimited reasoning until 98% confident" : "⚡ Bypassing 4K single-session limit",
            ]
        )

        // Use unlimited config for Maximum mode, otherwise device-optimized
        let deviceService = DeviceCapabilityService.shared
        let optimizedConfig: AgenticConfig
        if isUnlimitedMode {
            optimizedConfig = qualityMode.agenticConfig  // .unlimited config
            Log.info(
                "[Pipeline] Using MAXIMUM mode (unlimited reasoning, 98% confidence threshold)", category: .pipeline)
        } else {
            optimizedConfig = deviceService.optimizedAgenticConfig()
        }

        let modeTitle = isUnlimitedMode ? "Maximum Mode" : "Deep Think Mode"
        // Sessions, not the orchestrator's step budget (5.7): Deep Think's chain stops at 8 sessions on every device
        // (`AgenticPolicyService.maxSessionsForMode`), where this printed 5 on an iPhone 15 Pro and 13 on an 18 GB M3
        // Pro; what differs by device is the confidence it aims for. Maximum's step budget is its 50 sessions.
        let modeDetail =
            isUnlimitedMode
            ? "Reasoning until \(Int(optimizedConfig.confidenceThreshold * 100))% confident (up to \(optimizedConfig.maxSteps) sessions)"
            : "Starting multi-step reasoning (a chain of up to 8 sessions, aiming for \(Int(optimizedConfig.confidenceThreshold * 100))% confidence on the \(deviceService.chipName))"

        // Always start agentic work from a clean FM session.
        // Reusing transcript state across Go Deeper or repeated Deep Think queries
        // is what causes the visible freezes in chat.
        await MainActor.run {
            self.cancelActiveGeneration(resetSession: true)
        }

        emitThinkingEvent(
            .planning,
            title: modeTitle,
            detail: modeDetail
        )

        let startTime = Date()

        do {
            if let precisionResponse = try await executeAgenticPrecisionLookupIfAvailable(
                question: question,
                containerId: containerId,
                qualityMode: qualityMode,
                startTime: startTime
            ) {
                return precisionResponse
            }
        } catch {
            Log.warning(
                "[AgenticPrecision] Direct lookup failed, continuing with agentic reasoning: \(error.localizedDescription)",
                category: .retrieval)
            emitThinkingEvent(.warning, title: "Precision lookup fallback", detail: "Continuing with Deep Think")
        }

        let orchestrator = AgenticOrchestrator(ragService: self, config: optimizedConfig, qualityMode: qualityMode)
        // This answer's live counters start at zero (5.8): they were reset only on clearing the chat or switching mode
        // or library, so the panel carried counts over from earlier answers.
        await MainActor.run {
            self.deepThinkLiveTokens = 0
            self.deepThinkLiveSteps = 0
            self.deepThinkLiveConfidence = 0
        }

        // Wrap execution in a tracked task so it can be cancelled by subsequent queries
        let agenticTask = Task<RAGResponse, Error> { [weak self] in
            try Task.checkCancellation()
            guard let self else { throw CancellationError() }

            let result = try await orchestrator.execute(
                query: question,
                initialContext: "",
                onStep: { [weak self] step in
                    // Stream thinking steps to UI AND update live counters
                    await MainActor.run {
                        // Update live token counter for real-time UI (reset when this answer started, below)
                        self?.deepThinkLiveTokens += step.tokensUsed

                        // Only count actual LLM reasoning sessions, NOT pipeline events
                        // Pipeline events have tokensUsed == 0 (they're just status updates)
                        // Retrieval steps (.searching, .expanding) don't count as reasoning sessions
                        let isLLMReasoningSession: Bool = {
                            switch step.type {
                            case .planning, .analyzing, .synthesizing, .refining, .reformulating, .verifying:
                                return step.tokensUsed > 0  // Must have actual tokens to count
                            case .searching, .expanding:
                                return false  // Retrieval, not reasoning
                            }
                        }()

                        if isLLMReasoningSession {
                            self?.deepThinkLiveSteps += 1
                        }

                        // Update live confidence for Maximum mode
                        if let confidence = step.confidence {
                            self?.deepThinkLiveConfidence = confidence
                        }

                        // Check if this is a detailed sub-step (pipeline internals)
                        // Detailed steps from makeDetailedEventForwarder use format: "KIND|Title: Detail"
                        // This preserves the original ThinkingEvent.Kind (e.g., .vectorSearch, .bm25, .mmr)
                        if step.output.contains("|") {
                            // Parse the encoded format: "kindRawValue|Title: Detail"
                            guard let pipeIndex = step.output.firstIndex(of: "|") else { return }
                            let kindRaw = String(step.output[..<pipeIndex])
                            let rest = String(step.output[step.output.index(after: pipeIndex)...])

                            // Parse title and detail from "Title: Detail" format
                            let parts = rest.split(separator: ":", maxSplits: 1)
                            let title = String(parts.first ?? "Processing")
                            let detail = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                            // Recover the original ThinkingEvent.Kind for proper UI display
                            let eventKind = ThinkingEvent.Kind(rawValue: kindRaw) ?? step.type.thinkingKind
                            self?.emitThinkingEvent(eventKind, title: title, detail: detail)
                        } else if step.tokensUsed == 0 && step.output.contains(": ") {
                            // Legacy format without kind encoding (fallback)
                            let parts = step.output.split(separator: ":", maxSplits: 1)
                            let title = String(parts.first ?? "Processing")
                            let detail = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                            self?.emitThinkingEvent(
                                step.type.thinkingKind,
                                title: title,
                                detail: detail
                            )
                        } else if step.input.hasPrefix("Session ") {
                            // This is a reasoning session from Maximum mode - show session details
                            let sessionInfo = step.input  // e.g., "Session 5/25"
                            let confidence = step.confidence ?? 0
                            let saturation = step.tokensUsed > 300 ? "deep" : "scanning"

                            let metricsString =
                                "\(Int(confidence * 100))% confident • \(step.tokensUsed) tokens • \(saturation)"
                            let cleanOutput = step.output.replacingOccurrences(of: "\n", with: " ")
                            let detail = cleanOutput.isEmpty ? metricsString : "\(cleanOutput) • \(metricsString)"

                            self?.emitThinkingEvent(
                                step.type.thinkingKind,
                                title: sessionInfo,
                                detail: detail
                            )
                        } else {
                            // Regular reasoning step - use standard format
                            // Plain words only (5.8): "Tokens: 4, Duration: 0.2s" read as internal values, and the
                            // durations were constants the steps set (0.2 s, 0.5 s), never measured.
                            var metrics: [String] = []
                            if let confidence = step.confidence { metrics.append("\(Int(confidence * 100))% confident") }
                            if step.tokensUsed > 0 { metrics.append("\(step.tokensUsed) tokens") }
                            let metricsString = metrics.joined(separator: " • ")

                            let cleanOutput = step.output.replacingOccurrences(of: "\n", with: " ")
                            let detail =
                                metricsString.isEmpty
                                ? cleanOutput : (cleanOutput.isEmpty ? metricsString : "\(cleanOutput) • \(metricsString)")

                            self?.emitThinkingEvent(
                                step.type.thinkingKind,
                                title: step.type.displayName,
                                detail: detail
                            )
                        }
                    }
                }
            )

            let totalTime = Date().timeIntervalSince(startTime)

            logCitationMap(result.retrievedChunks, route: "agentic")
            Log.info(
                "[Agentic] Complete: \(result.steps.count) steps, \(result.totalTokens) tokens, \(String(format: "%.1f", totalTime))s",
                category: .pipeline)

            // Pipeline Trace: Agentic completion
            Log.pipelineComplete(
                totalDuration: totalTime,
                chunksRetrieved: result.steps.count,  // Steps as "chunks" for agentic
                tokensUsed: result.totalTokens,
                confidence: Double(result.confidence)
            )

            emitThinkingEvent(
                .generation,
                title: "Synthesis complete",
                detail:
                    "\(result.steps.count) reasoning steps, confidence: \(String(format: "%.0f%%", result.confidence * 100))"
            )

            // Set audit snapshot for UI with agentic-appropriate values
            // Agentic mode uses multiple small calls - show TOTAL usage across all calls
            // This makes the UI reflect the true "thinking" capacity used
            let totalTokensUsed = result.totalTokens
            let estimatedContextChars = totalTokensUsed * 3  // ~3 chars per token

            // Count LLM calls from step types (each non-search step = 1 LLM call)
            let llmCallCount = result.steps.filter { step in
                switch step.type {
                case .planning, .analyzing, .synthesizing, .refining, .reformulating, .verifying:
                    return true
                case .searching, .expanding:
                    return false  // These are retrieval, not LLM calls
                }
            }.count

            // Similarity telemetry, measured rather than asserted.
            //
            // These three were hardcoded to 0.7 / 0.5 / 0.5 on the agentic path, so every Deep Think
            // and Maximum answer displayed the same constant match score in the UI, and an 83-case
            // benchmark recorded `top_similarity` of exactly 0.7 on all 82 rows while the standard
            // path varied between 0.80 and 1.27. A number the user reads as a measurement has to be
            // one.
            let agenticSims = result.retrievedChunks
                .map(\.similarityScore)
                .sorted(by: >)
            let agenticTopSim = agenticSims.first ?? 0
            let agenticSecondSim = agenticSims.count > 1 ? agenticSims[1] : 0
            let agenticAvgTop5 =
                agenticSims.isEmpty
                ? 0
                : agenticSims.prefix(5).reduce(0, +) / Float(min(5, agenticSims.count))

            let agenticAudit = RAGAuditSnapshot(
                timestamp: Date(),
                query: question,
                containerId: containerId,
                containerName: selectedContainerName,
                embeddingProviderId: "agentic",
                embeddingDim: 512,
                vectorDBKind: .persistentJSON,
                chunkingTargetWords: 300,
                chunkingOverlapWords: 50,
                chunkingSource: "agentic",
                qualityModeName: isUnlimitedMode ? "Maximum" : "Deep Think",
                retrievalConfig: selectedRetrievalConfig,
                lenientRetrieval: true,
                dynamicMin: 0.3,
                topSim: agenticTopSim,
                secondSim: agenticSecondSim,
                avgTop5: agenticAvgTop5,
                acceptanceOverride: false,
                totalStoredChunks: result.retrievedChunks.count,
                candidatesCount: result.retrievedChunks.count,
                rerankedCount: result.retrievedChunks.count,
                filteredCount: 0,
                droppedCount: 0,
                mmrSelectedCount: result.retrievedChunks.count,
                uniqueDocCount: Set(result.retrievedChunks.map { $0.chunk.documentId }).count,
                contextStrategy: "recursive_rag",
                contextChars: estimatedContextChars,  // Total chars across all calls
                contextWords: totalTokensUsed / 2,
                contextChunksUsed: result.retrievedChunks.count,
                maxContextChars: 0,  // Not meaningful for recursive RAG
                baseWindowTokens: 4096,  // Per-call limit (for reference)
                safetyTokens: 200,
                promptOverheadTokens: 100,
                questionTokens: question.count / 4,
                reservedOutputTokens: 800,
                availableContextTokens: 4096,  // Per-call available (for reference)
                executionContext: .automatic,
                allowPrivateCloudCompute: true,
                networkConnected: NetworkMonitor.shared.isConnected,
                wantsCloudContext: true,
                reliabilityModeEnabled: true,
                allowUngroundedFallback: false,
                modelName: "Apple Foundation Model (Agentic)",
                featureFlags: RAGAuditFeatureFlags(
                    answerIntent: isUnlimitedMode ? "maximum_agentic" : "deep_think_agentic",
                    queryWasRewritten: result.steps.contains { $0.type == .reformulating },
                    queryExpansionCount: 0,
                    usedHyDE: false,
                    usedIterativeRetrieval: false,
                    iterativePassCount: 0,
                    usedQueryRouting: raptorRoutingEnabled,
                    usedSummaryRouting: false,
                    usedParentDocumentRetrieval: false,
                    usedCorrectiveRetrieval: false,
                    usedContextualCompression: false,
                    usedGraphPacking: result.steps.contains { $0.type == .expanding },
                    usedRetrievalCascade: result.steps.contains { $0.type == .reformulating },
                    usedSupplementaryVectorSearch: false,
                    usedFullUnlimitedReasoning: isUnlimitedMode && llmCallCount >= 8
                ),
                isRecursiveRAG: true,  // This tells UI to show tokens, not percentage
                totalTokensAcrossCalls: totalTokensUsed,
                llmCallCount: max(1, llmCallCount)
            )
            await MainActor.run {
                self.lastAuditSnapshot = agenticAudit
            }

            // Build RAGResponse from agentic result - include collected chunks for UI
            // Extract reasoning trace from steps for UI display (like Standard mode does)
            let reasoningTrace: [String]? = {
                // Filter to analysis/synthesis steps (not searching/expanding)
                let reasoningSteps = result.steps.filter { step in
                    switch step.type {
                    case .analyzing, .synthesizing, .refining, .reformulating, .verifying:
                        return true
                    case .planning, .searching, .expanding:
                        return false  // Skip retrieval steps
                    }
                }

                guard reasoningSteps.count > 1 else { return nil }

                // Format with session labels (matching Standard mode style)
                let sessionLabels = ["🔍 Analyzing Evidence", "🧠 Finding Patterns", "💡 Refining", "✨ Synthesis"]
                return reasoningSteps.dropLast().enumerated().map { idx, step in
                    let label = idx < sessionLabels.count ? sessionLabels[idx] : "Session \(idx + 1)"
                    let cleanInsight = step.output
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "INSIGHT:", with: "")
                        .replacingOccurrences(of: "REASONING:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return "\(label): \(cleanInsight)"
                }
            }()

            // The reasoning trace is shown to the user and included in the exported pipeline
            // trace, but `verifyCitations` only ever inspected the final answer, so a citation
            // here pointing past the end of the source list reached the screen unchecked. Device
            // 2026-08-19 displayed `[S13]` and `[S17]` against a 12-source list in silence.
            //
            // This logs rather than rewrites: a dangling citation means the source list and the
            // labels have diverged, and silently renumbering would hide that divergence instead
            // of surfacing it.
            if let reasoningTrace {
                let dangling = AgenticOrchestrator.danglingCitations(
                    in: reasoningTrace.joined(separator: "\n"),
                    sourceCount: result.retrievedChunks.count
                )
                if !dangling.isEmpty {
                    Log.warning(
                        "[RAGService] Reasoning trace cites \(dangling.map { "[S\($0)]" }.joined(separator: ", ")) "
                            + "against \(result.retrievedChunks.count) source(s). The labels and the reported source "
                            + "list have diverged; the citations are unresolvable for the reader.",
                        category: .llm
                    )
                }
            }

            let agenticAnswerIntent = QueryEnhancementService().classifyAnswerIntent(question)
            let generatedAgenticAnswer = repairMalformedURLs(cleanupResponseText(result.finalAnswer))
            var extractiveAgenticAnswer = await highPrecisionLookupOverrideAnswer(
                question: question,
                answerIntent: agenticAnswerIntent,
                retrievedChunks: result.retrievedChunks
            )
            // The run's own answer stands when the extracted value does not answer the question (5.8): a value lifted
            // from a source can be a page range or a table cell of another row.
            if let extracted = extractiveAgenticAnswer,
                await judgeResponsiveness(question: question, answer: extracted, stage: "extracted")?.verdict
                    == AnswerResponsiveness.none
            {
                Log.info("[Responsiveness] The extracted value does not answer the question; keeping the run's answer", category: .llm)
                extractiveAgenticAnswer = nil
            }
            let baseAgenticAnswer = extractiveAgenticAnswer ?? generatedAgenticAnswer
            var agenticAnswer = baseAgenticAnswer
            var agenticWarnings: [String] = []
            var agenticConfidence = result.confidence
            var gatingDecision: String?
            var structuredAnswer = StructuredAnswer.from(
                response: baseAgenticAnswer,
                retrievedChunks: result.retrievedChunks,
                answerIntent: agenticAnswerIntent,
                verificationResult: nil,
                loops: max(1, result.steps.count)
            )

            #if canImport(FoundationModels)
                if #available(iOS 26.0, *),
                    let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                        query: question,
                        candidateAnswer: baseAgenticAnswer,
                        retrievedChunks: result.retrievedChunks,
                        answerIntent: agenticAnswerIntent,
                        verificationResult: nil,
                        isSourceLocked: extractiveAgenticAnswer != nil
                    )
                {
                    agenticAnswer = sourceOnlyOutcome.finalAnswer
                    structuredAnswer = sourceOnlyOutcome.structuredAnswer
                    gatingDecision = sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                    agenticWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                    if sourceOnlyOutcome.shouldAbstain,
                        let abstentionReason = sourceOnlyOutcome.abstentionReason
                    {
                        agenticWarnings.append(abstentionReason)
                    }
                    agenticConfidence =
                        sourceOnlyOutcome.shouldAbstain
                        ? min(result.confidence, 0.35)
                        : min(result.confidence, max(sourceOnlyOutcome.fidelityScore, 0.75))
                }
            #endif

            // Deep Think and Maximum run the verification gates too (5.7, roadmap row "The Verified
            // badge shows for answers whose checks failed or never ran, and Deep Think and Maximum
            // run no verification gates"). Every mode was listed as verifying
            // (`RAGQualityMode.usesVerificationGates`), and these two returned before the gates, so
            // their answers read Not Checked unless the source-only check ran. The gates label the
            // answer and leave it as written: the badge and the warnings say what passed. Standard
            // abstains when its gates fail, but these answers took minutes, and a structured answer
            // rebuilt from a failed check can turn into a refusal (`resolvedDisplayResponse`), so the
            // result is not passed into it. Skipped when the source-only check ran, which is a check.
            var ranAgenticGates = false
            if gatingDecision == nil, qualityMode.usesVerificationGates {
                ranAgenticGates = true
                let gated = await verifyAgenticAnswer(
                    question: question,
                    answer: agenticAnswer,
                    chunks: result.retrievedChunks,
                    containerId: containerId,
                    answerIntent: agenticAnswerIntent,
                    qualityMode: qualityMode)
                gatingDecision = gated.summary
                if let gates = gated.result, !gates.passed {
                    for gateResult in gates.gateResults where !gateResult.passed {
                        agenticWarnings.append("Verification \(gateResult.gate.rawValue): \(gateResult.details)")
                    }
                }
            }

            let displayResponseText = resolvedDisplayResponse(
                fallback: agenticAnswer,
                structuredAnswer: structuredAnswer
            )
            // Whether the answer shown answers the question (5.8, `AnswerResponsivenessJudge`). Deep Think and Maximum
            // are labelled and not rewritten: their answer took minutes, and the verdict goes on the badge and warnings.
            if let judgment = await judgeResponsiveness(question: question, answer: displayResponseText, stage: "final") {
                // With no check behind the answer, only a "none" is written: "answers:full" alone would turn an
                // answer that `ReviewPromptService` counts as verified (no string, sources found) into Not Checked.
                if gatingDecision != nil || judgment.verdict == .none {
                    gatingDecision = appendedGatingDecision(gatingDecision, judgment.gatingToken)
                }
                if judgment.verdict != .full, !judgment.missing.isEmpty {
                    agenticWarnings.append("May not fully answer the question: \(judgment.missing)")
                }
            }
            // Fact Check for the claims the answer lists (5.8, 2026-11-07), after the displayed text is fixed so the
            // answer the user reads is unchanged. Only where the gates ran: the source-only check builds its own.
            if ranAgenticGates {
                structuredAnswer = await factCheckedAgenticAnswer(
                    structuredAnswer, answer: agenticAnswer, chunks: result.retrievedChunks, question: question,
                    answerIntent: agenticAnswerIntent, qualityMode: qualityMode)
            }

            return RAGResponse(
                queryId: UUID(),
                retrievedChunks: result.retrievedChunks,
                generatedResponse: displayResponseText,
                metadata: ResponseMetadata(
                    timeToFirstToken: totalTime / Double(max(1, result.steps.count)),  // Estimate TTFT per step
                    totalGenerationTime: totalTime,
                    tokensGenerated: result.totalTokens,
                    tokensPerSecond: Float(result.totalTokens) / Float(totalTime),
                    modelUsed: "Apple Foundation Model (Agentic)",
                    retrievalTime: 0,
                    retrievalConfigSummary: "Agentic",
                    gatingDecision: gatingDecision,
                    toolCallsMade: result.steps.filter { $0.type == .searching }.count,
                    usedAgenticMode: true,  // Agentic (deep) mode was used
                    qualityModeName: isUnlimitedMode ? "Maximum" : "Deep Think",
                    originalQuery: question,
                    reasoningTrace: reasoningTrace,  // Now includes the thinking steps!
                    executionRoute: runtimeContext.executionRoute,
                    tokenBudget: ResponseMetadata.TokenBudget(
                        totalLimit: runtimeContext.tokenBudget.totalLimit,
                        systemPrompt: runtimeContext.tokenBudget.systemPrompt,
                        retrievedContext: 0,  // Agentic context varies per step
                        generation: result.totalTokens,
                        remaining: runtimeContext.tokenBudget.totalLimit - runtimeContext.tokenBudget.systemPrompt
                            - result.totalTokens
                    )
                ),
                confidenceScore: agenticConfidence,
                qualityWarnings: agenticWarnings,
                structuredAnswer: structuredAnswer
            )
        }

        // Track this task so subsequent queries can cancel it
        await MainActor.run {
            self.activeAgenticTask = agenticTask
        }

        do {
            let response = try await withTaskCancellationHandler {
                try await agenticTask.value
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelActiveGeneration(resetSession: true)
                }
            }
            await MainActor.run { self.activeAgenticTask = nil }

            if response.metadata.usedAgenticMode {
                return await finalizeResponse(
                    query: question,
                    containerId: containerId,
                    containerName: selectedContainerName,
                    response: response
                )
            }

            return response
        } catch is CancellationError {
            await MainActor.run {
                self.cancelActiveGeneration(resetSession: true)
            }
            Log.info("[Agentic] Query cancelled (user sent new message)", category: .pipeline)
            throw CancellationError()
        } catch {
            await MainActor.run { self.activeAgenticTask = nil }
            if shouldFallbackAgenticPrecisionQuery(error: error, question: question) {
                Log.warning(
                    "[Agentic] Precision lookup fallback: rerouting to standard retrieval pipeline", category: .pipeline
                )
                await MainActor.run {
                    self.resetThinkingTimeline()
                }
                return try await self.queryInternal(
                    question,
                    topK: 3,
                    config: config,
                    containerId: containerId,
                    qualityModeOverride: .standard
                )
            }
            // Log the FULL error, not just localizedDescription. Apple's
            // FoundationModels errors carry their diagnostic payload in
            // associated values — GenerationError.decodingFailure(Context)
            // reduces to the bare string "Failed to parse generated content"
            // under localizedDescription, discarding the reason and the
            // offending content. String(describing:) preserves the case and
            // its associated values, which is what makes these debuggable.
            Log.error(
                "[Agentic] Failed: \(error.localizedDescription)\n"
                    + "         type: \(type(of: error))\n"
                    + "         full: \(String(describing: error))",
                category: .pipeline
            )
            throw error
        }
    }

}

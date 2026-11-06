//
//  ChatScreen+Sending.swift
//  OpenIntelligence
//
//  Part of ChatScreen, moved from ChatScreen.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import Combine
import Foundation
import StoreKit
import SwiftUI
import TipKit
import Translation

#if os(iOS)
    import PDFKit
    import VisionKit
#endif

extension ChatScreen {
    // MARK: - Attachment Handling

    /// Combined send: process attachments FIRST, wait for completion, THEN send query
    /// This ensures documents are indexed before the RAG query runs
    func sendMessageWithAttachments(_ query: String, _ urls: [URL]) {
        guard !query.isEmpty else { return }

        // If no attachments, just send the message directly
        guard !urls.isEmpty else {
            sendMessage(query)
            return
        }

        // Prevent concurrent operations
        guard !isProcessing else { return }

        let count = urls.count
        let noun = count == 1 ? "file" : "files"

        // Show processing state
        isProcessing = true
        stage = .embedding

        // Show immediate feedback
        toastManager.show(
            ToastItem(
                title: "Processing \(count) \(noun) before query...",
                icon: "doc.badge.gearshape",
                tint: DSColors.accent
            ),
            duration: 3.0
        )

        Task {
            let result = await ragService.ingestDocuments(urls)
            let successCount = result.successCount
            _ = result.failureCount

            // Refresh counts
            await recalcActiveCounts()

            // Step 2: Now send the query (documents are indexed!)
            await MainActor.run {
                if successCount > 0 {
                    // Show success before sending query
                    toastManager.show(
                        ToastItem(
                            title:
                                "Added \(successCount) \(successCount == 1 ? "document" : "documents") • Querying...",
                            icon: "checkmark.circle.fill",
                            tint: .green,
                            haptic: false
                        ),
                        duration: 2.0
                    )
                    DSHaptics.success()

                    // Reset processing state so sendMessage can start fresh
                    isProcessing = false

                    // Now send the actual query against the newly indexed content
                    sendMessage(query)
                } else {
                    // All attachments failed - still send query but warn user
                    isProcessing = false
                    toastManager.show(
                        ToastItem(
                            title: "Failed to process attachments",
                            icon: "xmark.circle.fill",
                            tint: .red
                        ),
                        duration: 3.0
                    )
                    DSHaptics.warning()

                    // Still send the query (might work with existing docs)
                    sendMessage(query)
                }
            }
        }
    }

    /// Legacy: Ingest attachments (documents, photos, camera captures) into the active container
    /// Note: Prefer sendMessageWithAttachments() for combined send operations
    private func handleAttachments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let count = urls.count
        let noun = count == 1 ? "file" : "files"

        // Show immediate feedback
        toastManager.show(
            ToastItem(
                title: "Processing \(count) \(noun)...",
                icon: "doc.badge.gearshape",
                tint: DSColors.accent
            ),
            duration: 2.0
        )

        Task {
            var successCount = 0
            var failCount = 0

            for (index, url) in urls.enumerated() {
                // Update toast to show progress
                await MainActor.run {
                    toastManager.show(
                        ToastItem(
                            title: "Processing \(index + 1)/\(count): \(url.lastPathComponent)",
                            icon: "doc.badge.gearshape",
                            tint: DSColors.accent
                        ),
                        duration: 2.0
                    )
                }

                do {
                    try await ragService.addDocument(at: url)
                    successCount += 1
                    Log.info("[ChatScreen] Ingested attachment: \(url.lastPathComponent)", category: .ingestion)
                } catch {
                    failCount += 1
                    Log.error("[ChatScreen] Failed to ingest \(url.lastPathComponent): \(error)", category: .ingestion)
                }
            }

            // Refresh counts
            await recalcActiveCounts()

            // Show completion feedback
            await MainActor.run {
                if failCount == 0 {
                    toastManager.show(
                        ToastItem(
                            title: "Added \(successCount) \(successCount == 1 ? "document" : "documents")",
                            icon: "checkmark.circle.fill",
                            tint: .green,
                            haptic: false
                        ),
                        duration: 2.0
                    )
                    DSHaptics.success()
                } else if successCount > 0 {
                    toastManager.show(
                        ToastItem(
                            title: "Added \(successCount), failed \(failCount)",
                            icon: "exclamationmark.triangle.fill",
                            tint: .orange
                        ),
                        duration: 3.0
                    )
                    DSHaptics.warning()
                } else {
                    toastManager.show(
                        ToastItem(
                            title: "Failed to process attachments",
                            icon: "xmark.circle.fill",
                            tint: .red
                        ),
                        duration: 3.0
                    )
                    DSHaptics.warning()
                }
            }
        }
    }

    func sendMessage(_ text: String) {
        // The composer takes a question while the previous answer is only being checked. That
        // answer is finished first, so it keeps its sources and lands above the new question;
        // cancelling it, which is what this path used to do mid-answer, would discard both.
        if isCheckingFinishedAnswer, let finishing = currentQueryTask {
            // One question waits at a time. A second send used to queue a second question, which
            // then cancelled the first on arrival, and the first never got an answer.
            guard questionAfterCheck == nil else { return }
            questionAfterCheck = text
            ragService.finishAnswerNow()
            pushToast("Sends once this answer is saved", icon: "arrow.up.circle.fill", tint: DSColors.accent)
            Task { @MainActor in
                await finishing.value
                // Cleared by a new chat, a cleared chat or a library switch, which end the wait.
                guard let waiting = questionAfterCheck else { return }
                questionAfterCheck = nil
                sendMessageNow(waiting)
            }
            return
        }
        sendMessageNow(text)
    }

    private func sendMessageNow(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // A Maximum run is spent here, before anything else happens, because this is the
        // one place every Maximum answer passes through. `consumeMaximumModeUseIfNeeded`
        // existed since May 2026 with no caller, so the "3 left today" label never moved
        // and the paywall's headline promise gated nothing. Paid tiers return unlimited.
        if effectiveQualityMode.canonical == .maximum {
            switch entitlementStore.consumeMaximumModeUseIfNeeded() {
            case .allowedUnlimited, .allowedMetered:
                break
            case .blocked(_, let dailyLimit, _):
                maximumModeLimitDialogMessage =
                    "Free users get \(dailyLimit) Maximum runs per day. Switch to Standard or Deep Think, or upgrade for unlimited Maximum mode."
                showMaximumModeLimitDialog = true
                return
            }
        }

        // Haptic feedback for sending a message
        DSHaptics.messageSent()

        // Cancel any background follow-up generation from the prior answer.
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil
        followUpSuggestions = []

        // Cancel the in-flight foreground query if one is still actively processing.
        // If the UI is already idle, treat any stored task handle as stale completion work
        // rather than canceling it during a follow-up tap.
        if let existingTask = currentQueryTask {
            if isProcessing {
                existingTask.cancel()
                cancelInFlightQueryWork()
                // Brief yield to let cancellation propagate
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                }
            } else {
                cancelInFlightQueryWork(resetLLMSession: false)
            }
        }

        // Reset streaming state from any previous query
        if isProcessing {
            resetStreamingState()
            isProcessing = false
            stage = .idle
        }

        onboardingStore.markAskedFirstQuery()

        // Append user message with selected container (override or active)
        var userMessage = ChatMessage(role: .user, content: query)
        let usedContainerId =
            messageContainerOverride ?? ragService.containerService.activeContainerId
        userMessage.containerId = usedContainerId
        messages.append(userMessage)
        persistChatHistory(for: usedContainerId)
        // Which library is asked in, and when, for Siri's suggestions (5.7): the one the question
        // goes to, which a one-question override can make other than the open one.
        SiriDonations.libraryUsed(ragService.containerService.containers.first { $0.id == usedContainerId })
        // Reset override after one use
        self.messageContainerOverride = nil

        // Reset and start processing
        isProcessing = true
        stage = .embedding
        let processingStart = Date()
        queryStart = processingStart
        nowTick = processingStart
        if VerificationJournal.isEnabled {
            let first = Self.answersThisLaunch == 0
            if first { MainThreadWatchdog.shared.phase = "firstQuestion" }
            VerificationJournal.record(
                "answer.start", .started,
                ["mode": "\(effectiveQualityMode)", "passages": "\(activeLibraryPassages)", "first": "\(first)",
                    "stallFree": "\(MainThreadWatchdog.shared.stallFree(since: Self.chatFirstShownAt ?? VerificationJournal.launchedAt))",
                    "watchdog": "\(MainThreadWatchdog.shared.isRunning)"])
        }
        // Initialize execution location based on selected model
        if settings.selectedModel == .appleIntelligence {
            execution = .onDevice
        } else if settings.selectedModel == .onDeviceAnalysis {
            execution = .onDevice
        } else {
            execution = .unknown
        }
        ttft = nil

        // Capture values for async task (query may be clarified asynchronously)
        let capturedTopK = retrievalTopK
        let capturedMaxTokens = maxTokens
        let capturedTemperature = temperature
        let capturedTopP = topP
        let capturedSamplingStrategy = SamplingStrategy(rawValue: samplingStrategyRaw) ?? .topK
        let capturedSamplingTopK = samplingTopK
        let capturedSeed: UInt64? = seedStorage >= 0 ? UInt64(seedStorage) : nil
        let capturedFrequencyPenalty = frequencyPenalty
        let capturedPresencePenalty = presencePenalty
        let capturedRepetitionPenalty = repetitionPenalty
        let capturedSystemPrompt = systemPrompt
        let capturedContextLength = contextLength
        let baseExecutionContext = settings.executionContext
        let capturedFmPreference = settings.fmPreference.canonical
        let capturedExecutionContext: ExecutionContext
        let capturedAllowPCC: Bool
        switch capturedFmPreference {
        case .automatic:
            capturedExecutionContext =
                baseExecutionContext == .automatic ? .preferCloud : baseExecutionContext
            capturedAllowPCC = baseExecutionContext != .onDeviceOnly
        case .core3B, .advanced20B:
            capturedExecutionContext = .onDeviceOnly
            capturedAllowPCC = false
        case .privateCloudCompute:
            capturedExecutionContext = .cloudOnly
            // The privacy setting remains authoritative. If PCC is disabled,
            // the planner records the requested cloud route and completes locally.
            capturedAllowPCC = baseExecutionContext != .onDeviceOnly
        }
        requestedExecutionContext = capturedExecutionContext
        let capturedUsedContainerId = usedContainerId
        currentQueryContainerId = usedContainerId
        let querySessionId = UUID()
        currentQuerySessionId = querySessionId
        resetStreamingState()
        continuedQueryCoordinator.begin(query: query, sessionId: querySessionId)

        // Track this task for potential cancellation
        currentQueryTask = Task(priority: .userInitiated) { [weak ragService] in
            guard let capturedService = ragService else { return }

            // Guarantee cleanup even on cancellation or error
            defer {
                Task { @MainActor in
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.currentQuerySessionId = nil
                    self.currentQueryTask = nil
                    self.isProcessing = false
                    if self.stage == .generating || self.stage == .searching || self.stage == .embedding {
                        self.stage = .idle
                    }
                }
            }

            do {
                // Check for cancellation before starting work
                try Task.checkCancellation()

                // Resolve low-signal follow-ups ("yes", "ok", etc.) to the last meaningful query.
                let isLowSignal = isLowSignalQuery(query)
                let capturedQuery = isLowSignal ? (lastSemanticQuery ?? query) : query
                if !isLowSignal {
                    await MainActor.run {
                        self.lastSemanticQuery = query
                    }
                }

                // Check for cancellation after query resolution
                try Task.checkCancellation()

                // Use the user's raw prompt for RAG.
                // QueryRewriterService inside RAGService already handles ambiguity and follow-ups.
                // A hidden Writing Tools proofread pass here can silently change short safety queries
                // before retrieval, which makes the system feel like it ignored the user's wording.

                // Check for cancellation before embedding
                try Task.checkCancellation()

                // Stage 1: Embedding
                await MainActor.run {
                    self.stage = .embedding
                    self.embeddingStart = Date()
                    self.embeddingElapsedFinal = nil
                    self.searchingStart = nil
                    self.searchingElapsedFinal = nil
                    self.generatingStartTS = nil
                    self.generatingElapsedFinal = nil
                    self.continuedQueryCoordinator.markEmbedding()
                    // UnifiedMetricsBar, or the answer's bubble with details off, shows the stage - no toast needed
                    DSHaptics.processingPulse()  // Feel the pipeline starting
                }
                try? await Task.sleep(nanoseconds: 250_000_000)

                // Check for cancellation before searching
                try Task.checkCancellation()

                // Stage 2: Searching
                await MainActor.run {
                    self.stage = .searching
                    self.searchingStart = Date()
                    if let embStart = self.embeddingStart {
                        self.embeddingElapsedFinal = Date().timeIntervalSince(embStart)
                    }
                    self.continuedQueryCoordinator.markSearching()
                    // UnifiedMetricsBar, or the answer's bubble with details off, shows the stage - no toast needed
                    DSHaptics.processingPulse()  // Feel the search starting
                }

                let config = InferenceConfig(
                    maxTokens: capturedMaxTokens,
                    temperature: Float(capturedTemperature),
                    topP: Float(capturedTopP),
                    // Was hardcoded 40. The Top-K slider in Model Parameters wrote to no
                    // key at all, so moving it changed nothing, and this value could not
                    // be influenced from the UI even after sampling became selectable.
                    topK: capturedSamplingTopK,
                    samplingStrategy: capturedSamplingStrategy,
                    seed: capturedSeed,
                    fmPreference: capturedFmPreference,
                    useKVCache: true,
                    systemPrompt: capturedSystemPrompt,
                    contextLength: capturedContextLength,
                    frequencyPenalty: Float(capturedFrequencyPenalty),
                    presencePenalty: Float(capturedPresencePenalty),
                    repetitionPenalty: Float(capturedRepetitionPenalty),
                    executionContext: capturedExecutionContext,
                    allowPrivateCloudCompute: capturedAllowPCC
                )

                // Every mode streams. Deep Think and Maximum used to pass nil here because each of
                // their dozens of model calls would have streamed into the bubble; since 5.4
                // `AgenticOrchestrator.execute` holds this handler back for the calls that write
                // the final answer, so those modes show their answer as it is written instead of
                // all at once when every later stage has finished.
                let queryStreamHandler: LLMStreamHandler = { event in
                    await MainActor.run {
                        if event.isFinal {
                            // Freeze the timer immediately when the LLM finishes
                            if let genStart = self.generationStart {
                                self.generatingElapsedFinal = Date().timeIntervalSince(genStart)
                            }
                            self.isStreamFinished = true
                            // DO NOT flush - let the pump finish naturally for a smooth end
                        } else {
                            self.continuedQueryCoordinator.markFirstToken()
                            self.enqueueStreamingText(event.text)
                        }
                    }
                }

                // Check for cancellation before generation
                try Task.checkCancellation()

                // Stage 3: Generating
                await MainActor.run {
                    self.stage = .generating
                    self.generationStart = Date()
                    self.generatingStartTS = self.generationStart
                    self.resetSpeedTracking()
                    if let searchStart = self.searchingStart, let genStart = self.generationStart {
                        self.searchingElapsedFinal = genStart.timeIntervalSince(searchStart)
                    }
                    self.continuedQueryCoordinator.markGenerating()
                    // UnifiedMetricsBar, or the answer's bubble with details off, shows the stage - no toast needed
                    DSHaptics.messageReceived()  // Feel the response starting
                }

                let response = try await capturedService.query(
                    capturedQuery,
                    topK: capturedTopK,
                    config: config,
                    containerId: capturedUsedContainerId,
                    streamHandler: queryStreamHandler
                )

                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId,
                        self.ragService.containerService.activeContainerId == capturedUsedContainerId
                    else { return }
                    self.currentRetrievedChunks = response.retrievedChunks
                    self.currentMetadata = response.metadata
                    self.currentStructuredAnswer = response.structuredAnswer
                    // Sources tray will show this - no separate toast needed
                }

                if let first = response.metadata.timeToFirstToken {
                    await MainActor.run {
                        guard self.currentQuerySessionId == querySessionId,
                            self.ragService.containerService.activeContainerId == capturedUsedContainerId
                        else { return }
                        self.ttft = first
                    }
                }

                // Snapshot thinking events before they get cleared on next query
                let capturedThinkingEvents = await MainActor.run { self.thinkingEvents }

                var assistant = ChatMessage(
                    role: .assistant,
                    content: sanitizeFinalResponse(response.generatedResponse),
                    metadata: response.metadata,
                    retrievedChunks: response.retrievedChunks,
                    structuredAnswer: response.structuredAnswer
                )
                assistant.containerId = capturedUsedContainerId
                assistant.traceQuery = query
                assistant.thinkingEvents = capturedThinkingEvents

                // Build pipeline trace from thinking events for later export
                if !capturedThinkingEvents.isEmpty {
                    let sorted = capturedThinkingEvents.sorted { $0.timestamp < $1.timestamp }
                    let baseTime = sorted.first?.timestamp ?? Date()
                    assistant.pipelineTrace = sorted.map { event in
                        let elapsed = event.timestamp.timeIntervalSince(baseTime)
                        let time = String(format: "+%06.0fms", elapsed * 1000)
                        let detail = event.detail.map { " │ \($0)" } ?? ""
                        return "\(time) [\(event.kind.displayName)] \(event.title)\(detail)"
                    }
                }

                // Wait for streaming pump to finish so the transition is smooth and avoids bursty text jumps
                while true {
                    let done = await MainActor.run { self.streamingBuffer.isEmpty && self.streamingPumpTask == nil }
                    if done { break }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }

                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.continuedQueryCoordinator.complete(sessionId: querySessionId, success: true)
                    // flushStreamingBufferToVisibleText already handled cleanup when isFinal arrived
                    // No need to reset again here - would race with final flush
                    self.appendAndPersistMessage(assistant, for: capturedUsedContainerId)
                    TourContext.answers += 1
                    // What the device checks close on (5.8): the mode, the badge, how many passages, how long.
                    VerificationJournal.record(
                        "answer.done", .ok,
                        durationMs: self.generationStart.map { Date().timeIntervalSince($0) * 1000 },
                        [
                            "mode": "\(self.effectiveQualityMode)",
                            "badge": "\(VerificationOutcome.from(gatingDecision: response.metadata.gatingDecision ?? "", claims: response.structuredAnswer?.claims ?? []))",
                            "gating": response.metadata.gatingDecision.map { String($0.prefix(40)) } ?? "none",
                            "sources": "\(response.retrievedChunks.count)",
                            "library": VerificationJournal.anon(capturedUsedContainerId),
                            "inFront": "\(self.isAppeared)",
                            // The app's state when the answer finished, which `inFront` isn't: leaving the app
                            // doesn't make the chat disappear. Read now, from the same source the import's
                            // `background` uses, not the view's scene phase captured when the question was asked.
                            "scene": RAGService.appIsInBackground ? "background" : "foreground",
                            "voiceOver": "\(VerificationJournal.voiceOverOn)",
                            "first": "\(Self.answersThisLaunch == 0)",
                            "libraryPassages": "\(self.activeLibraryPassages)",
                            "stallFree": "\(MainThreadWatchdog.shared.stallFree(since: self.queryStart ?? Date()))",
                            // Whether `stallFree` means anything: false when the watchdog never started.
                            "watchdog": "\(MainThreadWatchdog.shared.isRunning)",
                        ])
                    if VerificationJournal.isEnabled {
                        Self.answersThisLaunch += 1
                        MainThreadWatchdog.shared.phase = "other"
                    }
                    // A finished answer is the only moment the app asks for a rating (see
                    // ReviewPromptService for when).
                    ReviewPromptService.shared.noteAnswer(
                        gatingDecision: response.metadata.gatingDecision,
                        retrievedSourceCount: response.retrievedChunks.count,
                        claims: response.structuredAnswer?.claims ?? [])
                    // And the one unprompted look at the plans, after real use, free tier
                    // only, once per install. See PlanAskService. Never on the answer that just
                    // asked for a rating, so the two sheets don't land together; it waits for the next.
                    if !ReviewPromptService.shared.wantsPrompt {
                        PlanAskService.shared.noteAnswer(
                            gatingDecision: response.metadata.gatingDecision,
                            retrievedSourceCount: response.retrievedChunks.count,
                            isFreeTier: !self.entitlementStore.effectiveTier.isAtLeast(.pro),
                            claims: response.structuredAnswer?.claims ?? [])
                    }

                    if let genStart = self.generatingStartTS {
                        self.generatingElapsedFinal = Date().timeIntervalSince(genStart)
                    }

                    if self.ragService.containerService.activeContainerId == capturedUsedContainerId {
                        self.stage = .complete

                        // The only answer haptic used to fire as generation started, so an answer
                        // finishing on another tab, or during a check after its text had stopped,
                        // ended with no signal at all.
                        DSHaptics.success()
                        if !self.isAppeared {
                            ChatAnswerNotice.shared.answerFinishedOffScreen()
                        }

                        // The token count is a technical detail: the plain chat (5.7) ends on the answer itself
                        // and the haptic above, and Technical Details keeps the toast.
                        self.toastManager.clearAll()
                        if self.settings.showTechnicalDetails {
                            let tokenCount = response.metadata.tokensGenerated
                            self.pushToast(
                                tokenCount > 0 ? "Done • \(tokenCount) tokens" : "Complete",
                                icon: "checkmark.circle.fill",
                                tint: .green
                            )
                        }

                        // Mark the foreground answer as complete immediately.
                        // Any smart replies generated after this point are background work.
                        self.isProcessing = false
                        self.stage = .idle
                        self.resetStreamingState()
                        self.generationStart = nil

                        // Sever the foreground query handle now that the visible answer is done.
                        // This prevents a follow-up tap from racing stale cleanup from the
                        // previous turn and making the conversation behave like single-turn only.
                        self.currentQuerySessionId = nil
                        self.currentQueryTask = nil

                    }
                }

                // Generate follow-up suggestions in the background. These should never
                // keep the main chat in a "generating" state after the answer is visible.
                let enableSmartReplies = await MainActor.run { self.settings.enableSmartReplies }
                let smartReplyCount = await MainActor.run { self.settings.smartReplyCount }
                if enableSmartReplies {
                    await MainActor.run {
                        self.followUpSuggestionsTask?.cancel()
                        self.followUpSuggestionsTask = Task(priority: .utility) {
                            let suggestions = await SmartReplyService.shared.generateFollowUps(
                                query: capturedQuery,
                                response: response.generatedResponse,
                                retrievedChunks: response.retrievedChunks,
                                maxSuggestions: smartReplyCount
                            )

                            guard !Task.isCancelled else { return }

                            await MainActor.run {
                                guard !self.isProcessing,
                                    self.ragService.containerService.activeContainerId == capturedUsedContainerId
                                else { return }
                                self.followUpSuggestions = suggestions
                                self.followUpSuggestionsTask = nil
                            }
                        }
                    }
                }
            } catch {
                Log.error("Query failed: \(error.localizedDescription)", category: .llm)
                VerificationJournal.record(
                    "answer.done", error is CancellationError || Task.isCancelled ? .cancelled : .failed,
                    ["error": String(describing: type(of: error))])
                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.continuedQueryCoordinator.complete(sessionId: querySessionId, success: false)

                    // If the user switched libraries, suppress stale cancellation/error UI in the new context
                    guard self.ragService.containerService.activeContainerId == capturedUsedContainerId else {
                        self.stage = .idle
                        self.resetStreamingState()
                        self.generationStart = nil
                        return
                    }

                    if case RAGServiceError.maximumModeQuotaReached(let limit) = error {
                        self.stage = .idle
                        self.resetStreamingState()
                        self.generationStart = nil
                        self.maximumModeLimitDialogMessage =
                            "Free users get \(limit) Maximum runs per day. Switch to Standard or Deep Think, or upgrade for unlimited Maximum mode."
                        self.showMaximumModeLimitDialog = true
                        self.toastManager.clearAll()
                        self.pushToast("Maximum capped for today", icon: "flame.fill", tint: .orange)
                        return
                    }

                    let friendlyMessage = userFacingErrorMessage(error)
                    self.toastManager.clearAll()
                    if !self.isAppeared {
                        ChatAnswerNotice.shared.answerFinishedOffScreen()
                    }

                    self.flushStreamingBufferToVisibleText()
                    let partial = self.streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sanitizedPartial = self.sanitizeFinalResponse(partial)
                    let preservedAsAnswer = self.shouldKeepPartialResponseAsAnswer(sanitizedPartial)

                    if let partialContent = self.partialResponseMessageContent(
                        sanitizedPartial: sanitizedPartial,
                        failureMessage: friendlyMessage
                    ) {
                        if preservedAsAnswer {
                            self.pushToast("Saved partial answer", icon: "checkmark.circle.fill", tint: .orange)
                        } else {
                            let toastTitle = friendlyMessage.count > 42 ? "Couldn't complete" : friendlyMessage
                            self.pushToast(toastTitle, icon: "exclamationmark.triangle.fill", tint: .red)
                        }

                        var partialMessage = ChatMessage(
                            role: .assistant,
                            content: partialContent
                        )
                        partialMessage.containerId = capturedUsedContainerId
                        self.appendAndPersistMessage(partialMessage, for: capturedUsedContainerId)
                    } else {
                        let toastTitle = friendlyMessage.count > 42 ? "Couldn't complete" : friendlyMessage
                        self.pushToast(toastTitle, icon: "exclamationmark.triangle.fill", tint: .red)

                        var errorMsg = ChatMessage(
                            role: .assistant,
                            content: "\(friendlyMessage)\n\nPlease try again."
                        )
                        errorMsg.containerId = capturedUsedContainerId
                        self.appendAndPersistMessage(errorMsg, for: capturedUsedContainerId)
                    }

                    self.stage = .idle
                    self.resetStreamingState()
                    self.generationStart = nil
                }
            }
        }
    }

    func sendSuggestedPrompt(_ prompt: String) {
        DSHaptics.selection()
        sendMessage(prompt)
    }

    func presentMaximumModePaywall() {
        planEntryPoint = .maximumModeLimit
        showPlanSheet = true
    }

    private func isLowSignalQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let words = normalized.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        if words.count <= 1 {
            return ["yes", "y", "yeah", "yep", "ok", "okay", "sure", "continue", "go", "more"]
                .contains(normalized)
        }
        if words.count <= 2 {
            return [
                "go on",
                "keep going",
                "continue on",
                "sounds good",
                "that works",
                "do it",
                "please do",
            ].contains(normalized)
        }
        return false
    }

    // MARK: - Toasts

    func pushToast(_ title: String, icon: String, tint: Color) {
        let toast = ToastItem(title: title, icon: icon, tint: tint)
        toastManager.show(toast, duration: 2.0)
    }

}

//
//  ChatScreen+Body.swift
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
    // MARK: - Metrics Bar Helpers (split to avoid type-check timeout)

    /// Build the primary metrics bar when consolidatedMetricsData is available
    @ViewBuilder
    func primaryMetricsBar(metricsData: ConsolidatedMetrics) -> some View {
        let deepThinkTokens =
            isProcessing
            ? ragService.deepThinkLiveTokens
            : (ragService.lastAuditSnapshot?.totalTokensAcrossCalls ?? ragService.deepThinkLiveTokens)
        let audit = ragService.lastAuditSnapshot
        let liveReasoningEvent = thinkingEvents.last

        UnifiedMetricsBar(
            stage: stage,
            execution: metricsData.execution,
            isProcessing: isProcessing,
            qualityMode: effectiveQualityMode,
            isLLMActivelyGenerating: ragService.isLLMResponding,
            contextTokens: metricsData.isRecursiveRAG ? deepThinkTokens : actualContextTokensUsed,
            maxContextTokens: maxContextTokensForUI,
            tokensGenerated: metricsData.tokens,
            tokensPerSecond: metricsData.tokensPerSecond,
            characterCount: metricsData.characterCount,
            elapsedTime: metricsData.elapsed,
            speedHistory: metricsData.isStreaming ? speedHistory : [],
            ttft: metricsData.ttft,
            sourceCount: metricsData.sourceCount,
            averageSourceScore: metricsData.averageScore,
            totalDocuments: activeDocCount,
            totalChunks: activeChunkCount,
            coveredDocuments: coveredDocCount,
            toolCallCount: metricsData.toolCallCount,
            modelName: metricsData.modelName,
            requestedExecutionContext: requestedExecutionContext,
            vectorWeight: metricsData.vectorWeight,
            lexicalWeight: metricsData.lexicalWeight,
            originalQuery: messages.last(where: { $0.role == .user })?.content ?? "",
            queryIntent: metricsData.queryIntent,
            hierarchicalChunkingActive: metricsData.hierarchicalChunkingActive,
            parentChunksUsed: metricsData.parentChunksUsed,
            siblingChunksAdded: metricsData.siblingChunksAdded,
            graphExpansionActive: metricsData.graphExpansionActive,
            graphEntitiesExtracted: metricsData.graphEntitiesExtracted,
            intentAwareWeightsActive: metricsData.intentAwareWeightsActive,
            isRecursiveRAG: metricsData.isRecursiveRAG,
            recursiveCallCount: metricsData.recursiveCallCount,
            totalStoredChunks: audit?.totalStoredChunks ?? 0,
            candidatesCount: audit?.candidatesCount ?? 0,
            rerankedCount: audit?.rerankedCount ?? 0,
            filteredCount: audit?.filteredCount ?? 0,
            droppedCount: audit?.droppedCount ?? 0,
            mmrSelectedCount: audit?.mmrSelectedCount ?? 0,
            uniqueDocCount: audit?.uniqueDocCount ?? 0,
            baseWindowTokens: audit?.baseWindowTokens ?? 0,
            safetyTokens: audit?.safetyTokens ?? 0,
            promptOverheadTokens: audit?.promptOverheadTokens ?? 0,
            questionTokens: audit?.questionTokens ?? 0,
            reservedOutputTokens: audit?.reservedOutputTokens ?? 0,
            availableContextTokens: audit?.availableContextTokens ?? 0,
            lenientRetrieval: audit?.lenientRetrieval ?? false,
            dynamicMinThreshold: audit?.dynamicMin ?? 0,
            topSimilarity: audit?.topSim ?? 0,
            secondSimilarity: audit?.secondSim ?? 0,
            avgTop5Similarity: audit?.avgTop5 ?? 0,
            acceptanceOverride: audit?.acceptanceOverride ?? false,
            containerName: audit?.containerName ?? "",
            embeddingDim: audit?.embeddingDim ?? 512,
            vectorDBKind: audit?.vectorDBKind.rawValue ?? "",
            chunkingTargetWords: audit?.chunkingTargetWords ?? 0,
            chunkingOverlapWords: audit?.chunkingOverlapWords ?? 0,
            contextStrategy: audit?.contextStrategy ?? "",
            embeddingElapsed: embeddingElapsedFinal ?? 0,
            searchElapsed: searchingElapsedFinal ?? 0,
            generationElapsed: generatingElapsedFinal ?? 0,
            liveConfidence: ragService.deepThinkLiveConfidence,
            isMaximumMode: effectiveQualityMode.isUnlimitedMode,
            maximumModeSessionCount: ragService.deepThinkLiveSteps,
            liveReasoningTitle: liveReasoningEvent?.title ?? "",
            liveReasoningDetail: liveReasoningEvent?.detail ?? "",
            liveReasoningKind: liveReasoningEvent?.kind,
            thinkingEvents: thinkingEvents,
            onTapDetails: !metricsData.isStreaming ? { showRetrievedDetails = true } : nil
        )
    }

    /// Build the minimal metrics bar when processing but no consolidated data yet
    @ViewBuilder
    func minimalMetricsBar() -> some View {
        let auditSnapshot = ragService.lastAuditSnapshot
        let minimalVectorWt = Double(auditSnapshot?.retrievalConfig.vectorWeight ?? 0.6)
        let minimalLexicalWt = Double(auditSnapshot?.retrievalConfig.lexicalWeight ?? 0.4)
        let liveReasoningEvent = thinkingEvents.last
        let liveTokens = liveOutputTokensForMetrics

        UnifiedMetricsBar(
            stage: stage,
            execution: execution,
            isProcessing: isProcessing,
            qualityMode: effectiveQualityMode,
            isLLMActivelyGenerating: ragService.isLLMResponding,
            contextTokens: auditSnapshot?.isRecursiveRAG == true
                ? max(liveTokens, auditSnapshot?.totalTokensAcrossCalls ?? 0) : actualContextTokensUsed,
            maxContextTokens: maxContextTokensForUI,
            tokensGenerated: liveTokens,
            tokensPerSecond: liveTokensPerSecondForMetrics,
            characterCount: streamingText.count,
            elapsedTime: liveProcessingElapsedTime,
            speedHistory: [],
            ttft: ttft,
            sourceCount: currentRetrievedChunks.count,
            averageSourceScore: averageSourceScore,
            totalDocuments: activeDocCount,
            totalChunks: activeChunkCount,
            coveredDocuments: coveredDocCount,
            toolCallCount: 0,
            modelName: inferredModelName,
            requestedExecutionContext: requestedExecutionContext,
            vectorWeight: minimalVectorWt,
            lexicalWeight: minimalLexicalWt,
            originalQuery: messages.last(where: { $0.role == .user })?.content ?? "",
            queryIntent: deriveQueryIntent(from: auditSnapshot?.retrievalConfig),
            hierarchicalChunkingActive: auditSnapshot?.contextStrategy == "parent_expanded",
            parentChunksUsed: 0,
            siblingChunksAdded: 0,
            graphExpansionActive: effectiveQualityMode == .deepThink,
            graphEntitiesExtracted: 0,
            intentAwareWeightsActive: true,
            isRecursiveRAG: auditSnapshot?.isRecursiveRAG ?? (effectiveQualityMode == .deepThink),
            recursiveCallCount: auditSnapshot?.llmCallCount ?? 1,
            totalStoredChunks: auditSnapshot?.totalStoredChunks ?? 0,
            candidatesCount: auditSnapshot?.candidatesCount ?? 0,
            rerankedCount: auditSnapshot?.rerankedCount ?? 0,
            filteredCount: auditSnapshot?.filteredCount ?? 0,
            droppedCount: auditSnapshot?.droppedCount ?? 0,
            mmrSelectedCount: auditSnapshot?.mmrSelectedCount ?? 0,
            uniqueDocCount: auditSnapshot?.uniqueDocCount ?? 0,
            baseWindowTokens: auditSnapshot?.baseWindowTokens ?? 0,
            safetyTokens: auditSnapshot?.safetyTokens ?? 0,
            promptOverheadTokens: auditSnapshot?.promptOverheadTokens ?? 0,
            questionTokens: auditSnapshot?.questionTokens ?? 0,
            reservedOutputTokens: auditSnapshot?.reservedOutputTokens ?? 0,
            availableContextTokens: auditSnapshot?.availableContextTokens ?? 0,
            lenientRetrieval: auditSnapshot?.lenientRetrieval ?? false,
            dynamicMinThreshold: auditSnapshot?.dynamicMin ?? 0,
            topSimilarity: auditSnapshot?.topSim ?? 0,
            secondSimilarity: auditSnapshot?.secondSim ?? 0,
            avgTop5Similarity: auditSnapshot?.avgTop5 ?? 0,
            acceptanceOverride: auditSnapshot?.acceptanceOverride ?? false,
            containerName: auditSnapshot?.containerName ?? "",
            embeddingDim: auditSnapshot?.embeddingDim ?? 512,
            vectorDBKind: auditSnapshot?.vectorDBKind.rawValue ?? "",
            chunkingTargetWords: auditSnapshot?.chunkingTargetWords ?? 0,
            chunkingOverlapWords: auditSnapshot?.chunkingOverlapWords ?? 0,
            contextStrategy: auditSnapshot?.contextStrategy ?? "",
            embeddingElapsed: embeddingElapsedFinal ?? 0,
            searchElapsed: searchingElapsedFinal ?? 0,
            generationElapsed: generatingElapsedFinal ?? 0,
            liveConfidence: ragService.deepThinkLiveConfidence,
            isMaximumMode: effectiveQualityMode.isUnlimitedMode,
            maximumModeSessionCount: ragService.deepThinkLiveSteps,
            liveReasoningTitle: liveReasoningEvent?.title ?? "",
            liveReasoningDetail: liveReasoningEvent?.detail ?? "",
            liveReasoningKind: liveReasoningEvent?.kind,
            thinkingEvents: thinkingEvents,
            onTapDetails: nil
        )
    }

    // `body` is split into three layers (chatLifecycleLayer → chatPresentationLayer
    // → body) because the original single ~430-line modifier chain exceeded the
    // Swift type-checker budget on slower CI hardware ("unable to type-check this
    // expression in reasonable time"). Pure mechanical split: modifier order and
    // the resulting view tree are unchanged.
    private var chatLifecycleLayer: some View {
        ZStack(alignment: .top) {
            mainContentArea

            // Toast overlay (appears above everything) - minimal use
            ToastStackView(items: toastManager.toasts, maxVisible: 1)
                .padding(.top, 60)

            IngestionQueueOverlay(
                items: ragService.ingestionItems,
                onCancelItem: { ragService.cancelIngestionItem($0) },
                onCancelAll: { ragService.cancelAllIngestion() },
                onContinuePaused: { ragService.continuePausedIngestionQueue() },
                onDiscardPaused: { ragService.discardPausedIngestionQueue() },
                onStopAndDismiss: { ragService.stopAndDismissIngestionQueue() },
                onPause: { ragService.pauseIngestionQueue() },
                pausedByPerson: ragService.ingestionPausedByPerson,
                isAutomatic: WatchedFolderService.shared.isOnlyWatchedWork(ragService.ingestionItems)
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Motherboard HUD - Full-screen X-ray overlay
            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    // Hit-testing intentionally enabled: the overlay is
                    // internally touch-transparent except the draggable legend.
                    .transition(.opacity)
            }

            writingToolsProgressOverlay

            if showThreadSidebar {
                ThreadSidebarView(
                    ragService: ragService,
                    isPresented: $showThreadSidebar,
                    onThreadSelected: { threadId in
                        let containerId = ragService.containerService.activeContainerId
                        let loadedMessages = ragService.loadThread(threadId, for: containerId)
                        messages = loadedMessages
                        withAnimation(DSAnimations.snappySpring) {
                            showThreadSidebar = false
                        }
                    }
                )
                .transition(.move(edge: .leading))
                .zIndex(100)
            }
        }
        // MARK: - Vision Capture
        //
        // Enabled 2026-09-11, having been commented out since v1. What changed is the detector
        // behind it, not the screen. `YOLODetectionService` searched the bundle for four YOLOv3
        // `.mlmodelc` files that have never existed in this repository, so it always fell through
        // to scene classification, which carries no spatial extent, and handed each label a
        // full-frame rectangle so the overlay had something to draw. The screen could not have
        // boxed anything except an animal. `LiveObjectDetectionService` replaced it with detectors
        // that ship in the OS, four of which return real geometry.
        //
        // iOS only: `CameraVisionOverlayView` is inside `#if os(iOS)` and has no macOS equivalent.
        // `NSCameraUsageDescription` is set via INFOPLIST_KEY in the project, so the permission
        // prompt has copy to show.
        #if os(iOS) && DEBUG
            .fullScreenCover(isPresented: $showVisionCapture) {
                CameraVisionOverlayView(
                    ragService: ragService,
                    containerService: ragService.containerService
                )
            }
        #endif
        #if os(iOS)
            .fullScreenCover(isPresented: $showDocumentScanner) {
                SystemDocumentScanner(
                    onScan: { scan in
                        showDocumentScanner = false
                        storeScan(scan)
                    },
                    onDismiss: { error in
                        showDocumentScanner = false
                        if let error {
                            Log.error("[Scan] The scanner failed: \(error.localizedDescription)", category: .ingestion)
                        }
                    }
                )
                .ignoresSafeArea()
            }
        #endif
        .navigationTitle("Chat")
        .imagePlaygroundSupport()
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(processingClock) { _ in
            if isProcessing {
                nowTick = Date()
            }
        }
        // Start/stop the 5 Hz timer based on processing state. The comment always said
        // this saved battery when idle; it now does, because the `false` branch exists.
        .onChange(of: isProcessing) { _, newValue in
            if newValue {
                startProcessingClock()
            } else {
                processingClockConnection?.cancel()
                processingClockConnection = nil
            }
        }
        .onDisappear {
            processingClockConnection?.cancel()
            processingClockConnection = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            continuedQueryCoordinator.handleScenePhaseChange(newPhase, isProcessing: isProcessing)
            if newPhase != .active {
            }
        }
        // Recalculate counts when active container changes
        .task(id: ragService.containerService.activeContainerId) {

            // Don't load persisted history in screenshot demo mode - let seedFullDemoContent() handle it
            #if DEBUG
                if didSeedScreenshotDemo { return }
            #endif
            let activeId = ragService.containerService.activeContainerId
            let isSameChatContainer = (lastLoadedChatContainerId == activeId)
            let isSameDocsContainer = (lastProcessedContainerId == activeId)

            // The cancellation below used to sit above this guard and therefore ran on every
            // appearance, not only on a real container change. `.task(id:)` restarts whenever the
            // view reappears, so switching to Documents and back mid-answer cancelled the query
            // and called `resetStreamingState()`, discarding the partial text with no message and
            // no error. The explicit Stop button (`stopGeneration()`) keeps the partial answer, so
            // the accidental path destroyed more than the deliberate one.
            //
            // The comment below names cross-container bleed as the thing being prevented, and a
            // container change is the only case that can produce it. Everything else in this task
            // — history reload, suggested-question invalidation, count recalculation — was already
            // gated on `isSameChatContainer`; only this block was left ungated.
            //
            // Scene-phase cancellation and manual stop are untouched.
            if !isSameChatContainer {
                // Cancel any in-flight query from the previous library to prevent cross-container bleed
                continuedQueryCoordinator.cancelCurrentQuery()
                questionAfterCheck = nil
                currentQuerySessionId = nil
                currentQueryTask?.cancel()
                currentQueryTask = nil

                // Reset transient generation state for the newly active library
                if isProcessing {
                    resetStreamingState()
                    isProcessing = false
                    stage = .idle
                }
                messages = await ragService.preloadChatHistory(for: activeId)
                guard !Task.isCancelled,
                    ragService.containerService.activeContainerId == activeId
                else { return }

                lastLoadedChatContainerId = activeId
                await recalcActiveCounts()

                // Clear stale per-conversation state from previous library
                followUpSuggestionsTask?.cancel()
                followUpSuggestions = []
                thinkingEvents = []
                speedHistory = []
            }

            if !isSameDocsContainer {
                // Immediately clear old suggested questions so stale pills never flash
                dynamicSuggestedQuestions = []
                dynamicQuestionDetails = [:]

                // Invalidate cached questions for the new container before regenerating
                lastProcessedContainerId = activeId
                lastProcessedDocuments = ragService.documents
                await suggestedQuestionsService.invalidateCache(for: activeId)
                needsSuggestedQuestionsRefresh = false
                refreshDynamicQuestions()
            } else {
                if needsSuggestedQuestionsRefresh || dynamicSuggestedQuestions.isEmpty {
                    needsSuggestedQuestionsRefresh = false
                    refreshDynamicQuestions()
                }
            }
        }
        // React to document ingestion/removal immediately
        .onReceive(ragService.$documents) { newDocs in
            let activeId = ragService.containerService.activeContainerId
            guard lastProcessedContainerId != activeId || lastProcessedDocuments != newDocs else { return }
            lastProcessedContainerId = activeId
            lastProcessedDocuments = newDocs

            Task {
                await recalcActiveCounts()
                // Invalidate stale questions and regenerate from new content
                await suggestedQuestionsService.invalidateCache(for: activeId)
                if isAppeared {
                    refreshDynamicQuestions()
                } else {
                    needsSuggestedQuestionsRefresh = true
                }
            }
        }
        // Ensure counts refresh if the user switches containers outside this view
        .onReceive(ragService.containerService.$activeContainerId) { _ in
            Task { await recalcActiveCounts() }
        }
        .onReceive(ragService.$thinkingEvents) { events in
            // Each new step moves the background progress while no text has arrived yet. The
            // array is replaced wholesale on reset, so only a new last event counts as a step.
            if isProcessing, stage == .generating, let latest = events.last,
                latest.id != thinkingEvents.last?.id
            {
                continuedQueryCoordinator.markStep()
            }
            thinkingEvents = events
        }
        .onChange(of: isCheckingFinishedAnswer) { _, checking in
            if checking {
                continuedQueryCoordinator.markChecking()
            }
        }
        .onReceive(ragService.$pendingCloudConsent) { record in
            activeCloudConsent = record
        }
    }

    private var chatPresentationLayer: some View {
        chatLifecycleLayer
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(DSAnimations.snappySpring) {
                                Tour.used(.sidebar)
                                showThreadSidebar.toggle()
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .imageScale(.large)
                                .tour(.sidebar, in: Tour.chat)
                        }
                    }

                    // MARK: - AI Hub (RAG Transforms + Image Playground)
                    ToolbarItem(placement: .topBarTrailing) {
                        aiHubToolbarButton
                    }

                    // MARK: - Chat Actions (New / Clear)
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                guard !isProcessing else { return }
                                newChat()
                            } label: {
                                Label("New Chat", systemImage: "square.and.pencil")
                            }
                            .disabled(messages.isEmpty)

                            Menu {
                                ForEach(ConversationExporter.Format.allCases, id: \.self) { format in
                                    Button(format.menuTitle) {
                                        exportConversation(format)
                                    }
                                }
                            } label: {
                                Label("Export Conversation", systemImage: "square.and.arrow.up")
                            }
                            .disabled(messages.isEmpty || isProcessing)

                            Button(role: .destructive) {
                                guard !isProcessing else { return }
                                clearChat()
                            } label: {
                                Label("Clear Chat", systemImage: "trash")
                            }
                            .disabled(messages.isEmpty)

                            // The chat's technical view (5.7), also in Settings, Appearance. The menu is open with an
                            // empty chat for it; the chat actions above stay off until there is a chat.
                            Divider()
                            Toggle(isOn: $settings.showTechnicalDetails) {
                                Label("Technical Details", systemImage: "waveform.path.ecg")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .tour(.moreMenu, in: Tour.chat)
                                .imageScale(.large)
                        }
                        .animation(nil, value: messages.count)
                    }
                #else
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation(DSAnimations.snappySpring) {
                                Tour.used(.sidebar)
                                showThreadSidebar.toggle()
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .imageScale(.large)
                                .tour(.sidebar, in: Tour.chat)
                        }
                    }

                    ToolbarItem {
                        Menu {
                            Button {
                                guard !isProcessing else { return }
                                newChat()
                            } label: {
                                Label("New Chat", systemImage: "square.and.pencil")
                            }
                            .disabled(messages.isEmpty)

                            Menu {
                                ForEach(ConversationExporter.Format.allCases, id: \.self) { format in
                                    Button(format.menuTitle) {
                                        exportConversation(format)
                                    }
                                }
                            } label: {
                                Label("Export Conversation", systemImage: "square.and.arrow.up")
                            }
                            .disabled(messages.isEmpty || isProcessing)

                            Button(role: .destructive) {
                                guard !isProcessing else { return }
                                clearChat()
                            } label: {
                                Label("Clear Chat", systemImage: "trash")
                            }
                            .disabled(messages.isEmpty)

                            // The chat's technical view (5.7), also in Settings, Appearance. The menu is open with an
                            // empty chat for it; the chat actions above stay off until there is a chat.
                            Divider()
                            Toggle(isOn: $settings.showTechnicalDetails) {
                                Label("Technical Details", systemImage: "waveform.path.ecg")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .tour(.moreMenu, in: Tour.chat)
                                .imageScale(.large)
                        }
                        .animation(nil, value: messages.count)
                    }
                #endif
            }
            .sheet(isPresented: $showRetrievedDetails) {
                if let meta = currentMetadata {
                    ChatResponseDetailsView(
                        metadata: meta,
                        retrievedChunks: currentRetrievedChunks,
                        structuredAnswer: currentStructuredAnswer
                    )
                    // The library's documents, so a source can open its page (5.7).
                    .environment(\.libraryDocumentLookup, documentLookup)
                } else {
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text("Retrieved Sources")
                            .font(DSTypography.title)
                        if currentRetrievedChunks.isEmpty {
                            Text("Searching…")
                                .font(DSTypography.body)
                                .foregroundStyle(DSColors.secondaryText)
                        } else {
                            SourceChipsView(chunks: currentRetrievedChunks, onTap: {}) { chunk in
                                openedSourceChunk = OpenedRetrievedChunk(chunk: chunk)
                            }
                            .sheet(item: $openedSourceChunk) { opened in
                                RetrievedSourceScreen(chunk: opened.chunk, lookup: documentLookup)
                            }
                        }
                    }
                    .padding()
                }
            }
            .onReceive(AppNavigationRequest.shared.changes) { _ in
                takeNavigationRequest()
            }
            .onReceive(PlanAskService.shared.$wantsAsk) { wants in
                // Two seconds after the answer has landed, like the rating request, so the
                // sheet never covers the answer itself; and never on top of another sheet.
                guard wants, !showPlanSheet, activeCloudConsent == nil else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !showPlanSheet else { return }
                    planEntryPoint = .momentOfValue
                    showPlanSheet = true
                    PlanAskService.shared.didAsk()
                    VerificationJournal.record("plans.askedAfterAnswer")
                }
            }
            .sheet(isPresented: $showPlanSheet) {
                PlanUpgradeSheet(entryPoint: planEntryPoint)
            }
            #if DEBUG
                .sheet(item: $storeScenePage) { scene in
                    SourcePageView(
                        document: scene.document, pageNumber: scene.page, passage: scene.passage, chunk: scene.chunk)
                }
            #endif
            .sheet(item: $activeCloudConsent) { record in
                CloudConsentPromptView(record: record) { decision in
                    Task { await ragService.resolveCloudConsent(decision: decision) }
                }
                .interactiveDismissDisabled(true)
                #if os(iOS)
                    .presentationDetents([.height(580), .large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(DSCorners.sheet)
                    .presentationBackground(.ultraThinMaterial)
                #endif
            }
            .confirmationDialog(
                "Maximum mode limit reached",
                isPresented: $showMaximumModeLimitDialog,
                titleVisibility: .visible
            ) {
                Button("Switch to Standard") {
                    settings.ragQualityMode = .standard
                    ragService.resetDeepThinkLiveMetrics()
                }
                Button("Switch to Deep Think") {
                    settings.ragQualityMode = .deepThink
                    ragService.resetDeepThinkLiveMetrics()
                }
                Button("See Plans") {
                    presentMaximumModePaywall()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(maximumModeLimitDialogMessage)
            }
            .alert(
                "Help Me Improve",
                isPresented: $showFeedbackEmailPrompt
            ) {
                Button("Send Feedback 💬") {
                    openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "In-App Negative Feedback"))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "I'm sorry that answer wasn't helpful. Please send me your feedback so I can improve OpenIntelligence!"
                )
            }
    }

    var body: some View {
        chatPresentationLayer
            // A cited passage's sheet asks for the document's own record, file address included.
            .environment(\.libraryDocumentLookup, documentLookup)
            .onAppear {
                documentLookup.ragService = ragService
                let ragService = self.ragService
                continuedQueryCoordinator.expirationHandler = { [weak ragService] in
                    ragService?.cancelActiveGeneration(resetSession: true)
                    Task { @MainActor in
                        self.keepAnswerStoppedByBackgroundExpiry()
                        // Ends the answer for everything that follows it: the Deep Think Live Activity
                        // read "running" after an expiry and stayed in the Dynamic Island until the next
                        // answer (the owner's iPhone, 2026-11-04), because the session id is cleared here
                        // and the query's own end no longer matches it.
                        self.continuedQueryCoordinator.cancelCurrentQuery()
                        self.currentQueryTask?.cancel()
                        self.currentQueryTask = nil
                        self.currentQuerySessionId = nil
                        self.isProcessing = false
                        self.stage = .idle
                        self.resetStreamingState()
                        self.generationStart = nil
                    }
                }
                continuedQueryCoordinator.handleScenePhaseChange(scenePhase, isProcessing: isProcessing)
                ChatAnswerNotice.shared.chatAppeared()
                // `.onDisappear` stops the elapsed clock, and nothing restarted it for an answer
                // still running on return, so the timer stood frozen at the moment the tab was left.
                if isProcessing {
                    startProcessingClock()
                    VerificationJournal.record("chat.clockResumed", ["mode": "\(effectiveQualityMode)"])
                }
                // Seed screenshot demo FIRST before loading persisted history
                seedScreenshotDemoIfNeeded()
                entitlementStore.refreshTransientState()
                isAppeared = true
                // With `chat.disappear` and `library.setActive`, the event log shows whether the chat was on screen
                // when it went blank (5.8, the owner's iPhone, 2026-11-03).
                VerificationJournal.record(
                    "chat.appear",
                    ["messages": "\(messages.count)", "windows": "\(visibleWindowCount)",
                        "engines": "\(RAGService.liveEngineCount)"])
                if VerificationJournal.isEnabled, Self.chatFirstShownAt == nil {
                    Self.chatFirstShownAt = Date()
                    VerificationJournal.record(
                        "launch.chatUsable",
                        ["passages": "\(activeLibraryPassages)",
                            "ms": "\(Int(Date().timeIntervalSince(VerificationJournal.launchedAt) * 1000))",
                            "stallFree": "\(MainThreadWatchdog.shared.stallFree(since: VerificationJournal.launchedAt))",
                            "watchdog": "\(MainThreadWatchdog.shared.isRunning)"])
                    MainThreadWatchdog.shared.phase = "chatOpen"
                }
                Task { await TourContext.chatOpened.donate() }
                if needsSuggestedQuestionsRefresh || dynamicSuggestedQuestions.isEmpty {
                    needsSuggestedQuestionsRefresh = false
                    refreshDynamicQuestions()
                }
            }
            .onDisappear {
                isAppeared = false
                VerificationJournal.record("chat.disappear")
            }
            // The Stop button on the answer's Live Activity (5.7, `StopLongAnswerIntent`): stops the
            // answer like the chat's own stop button, only if the Live Activity is the running one's.
            .onReceive(NotificationCenter.default.publisher(for: .stopLongAnswer)) { notification in
                VerificationJournal.record("answer.stopRequested", ["source": "liveActivity"])
                #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
                    guard let sessionID = notification.userInfo?["sessionID"] as? String,
                        QueryLiveActivityService.shared.isRunningActivity(sessionID: sessionID)
                    else { return }
                    stopGeneration()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ActiveModelRouteResolved"))) {
                notification in
                guard let pathString = notification.userInfo?["executionPath"] as? String else { return }
                switch pathString {
                case "onDevice":
                    self.execution = .onDevice
                case "privateCloudCompute":
                    self.execution = .privateCloudCompute
                default:
                    break
                }
            }
            // MARK: - NSUserActivity / Handoff
            .userActivity(AppActivity.chat) { activity in
                activity.title = "Chat with Documents"
                activity.isEligibleForSearch = true
                activity.isEligibleForHandoff = true
                #if os(iOS)
                    activity.isEligibleForPrediction = true
                #endif
                activity.userInfo = AppActivity.userInfo(library: ragService.containerService.activeContainerId)
                // What Siri and Apple Intelligence take "this" to mean here: the open conversation,
                // or its library before the first answer saves one (5.7).
                activity.appEntityIdentifier =
                    ragService.activeThreadId.map(EntityIdentifier.conversation)
                    ?? .library(ragService.containerService.activeContainerId)
            }
            // MARK: - Translation Overlay
            #if !targetEnvironment(macCatalyst)
                .translationPresentation(isPresented: $showTranslation, text: translationText)
            #endif
            // MARK: - WritingTools Result Sheet
            .sheet(isPresented: $showWritingToolsResult) {
                WritingToolsResultSheet(
                    title: writingToolsTitle,
                    result: writingToolsResult,
                    onCopy: {
                        SystemClipboard.copy(writingToolsResult)
                        DSHaptics.success()
                        toastManager.show(
                            ToastItem(title: "Copied to clipboard", icon: "doc.on.doc", tint: .green),
                            duration: 1.5
                        )
                    },
                    onInsertAsReply: {
                        showWritingToolsResult = false
                        let writingMessage = ChatMessage(
                            role: .assistant,
                            content: "**\(writingToolsTitle):**\n\n\(writingToolsResult)"
                        )
                        messages.append(writingMessage)
                    },
                    onFeedback: { isPositive in
                        // Log quality signal to pipeline observability.
                        // When LanguageModelSession.logFeedbackAttachment is wired through the
                        // service layer, re-route here for official Apple FM telemetry.
                        let signal = isPositive ? "positive" : "negative"
                        Log.info("[AIHub] User feedback '\(signal)' for \(writingToolsTitle)", category: .pipeline)
                        DSHaptics.selection()
                        toastManager.show(
                            ToastItem(
                                title: isPositive ? "Thanks for the feedback!" : "Got it — we'll improve",
                                icon: isPositive ? "hand.thumbsup.fill" : "hand.thumbsdown.fill",
                                tint: isPositive ? .green : .orange
                            ),
                            duration: 2.0
                        )
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $conversationExport) { file in
                ActivityView(activityItems: [file.url])
            }
    }

    private var streamingTokensApprox: Int {
        streamingText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var streamingElapsedTime: TimeInterval {
        guard let start = generationStart else { return 0 }
        if let final = generatingElapsedFinal { return final }
        return max(0, nowTick.timeIntervalSince(start))
    }

    private var streamingTokensPerSecond: Double {
        let elapsed = streamingElapsedTime
        guard elapsed > 0.1 else { return 0 }
        return Double(streamingTokensApprox) / elapsed
    }

    /// Live elapsed time for the unified bar while a query is in any active stage.
    /// Standard streaming switches to `streamingElapsedTime` once output begins; this
    /// keeps retrieval and non-streaming Deep Think / Maximum runs visibly alive too.
    private var liveProcessingElapsedTime: TimeInterval {
        let _ = nowTick
        if stage == .generating, generationStart != nil {
            return streamingElapsedTime
        }

        guard isProcessing else {
            return generatingElapsedFinal ?? 0
        }

        guard let start = queryStart ?? embeddingStart ?? searchingStart ?? generationStart else {
            return 0
        }

        return max(0, nowTick.timeIntervalSince(start))
    }

    private var liveOutputTokensForMetrics: Int {
        if streamingTokensApprox > 0 {
            return streamingTokensApprox
        }

        if ragService.deepThinkLiveTokens > 0 {
            return ragService.deepThinkLiveTokens
        }

        if let totalTokens = ragService.lastAuditSnapshot?.totalTokensAcrossCalls, totalTokens > 0 {
            return totalTokens
        }

        return 0
    }

    private var liveTokensPerSecondForMetrics: Double {
        let elapsed = liveProcessingElapsedTime
        guard elapsed > 0.1 else { return 0 }
        return Double(liveOutputTokensForMetrics) / elapsed
    }

    /// Infer model name from settings when metadata isn't available yet
    private var inferredModelName: String {
        // Screenshot demo always shows "Apple Intelligence"
        #if DEBUG
            if didSeedScreenshotDemo {
                return "Apple Intelligence"
            }
        #endif
        // Use settings EnvironmentObject
        switch settings.selectedModel {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .onDeviceAnalysis:
            return "On-Device Analysis"
        }
    }

    /// Quality mode - returns Deep Think during screenshot demo for consistent visuals
    var effectiveQualityMode: RAGQualityMode {
        #if DEBUG
            // The store scenes are Standard answers; forcing Deep Think here made the metrics strip
            // disagree with the mode pill in the listing screenshots.
            if didSeedScreenshotDemo, LaunchArguments.valueEither(for: "screenshot-store") == nil {
                return .deepThink
            }
        #endif
        return settings.ragQualityMode
    }

    /// Average score of retrieved sources for quality indicator
    private var averageSourceScore: Float? {
        guard !currentRetrievedChunks.isEmpty else { return nil }
        let total = currentRetrievedChunks.reduce(into: 0.0) { acc, chunk in acc += Double(chunk.similarityScore) }
        return Float(total / Double(currentRetrievedChunks.count))
    }

    /// Derive query intent label from retrieval config weights
    private func deriveQueryIntent(from config: RetrievalConfig?) -> String {
        guard let config else { return "" }
        // Infer intent from weight distribution
        if config.lexicalWeight > 0.55 {
            return "keyword"
        } else if config.vectorWeight > 0.65 {
            return "conceptual"
        } else {
            return "balanced"
        }
    }

    /// Consolidated metrics data for the unified header bar
    /// Returns data during streaming OR after completion (when we have metadata)
    var consolidatedMetricsData: ConsolidatedMetrics? {
        // Extract advanced RAG features from audit snapshot
        let audit = ragService.lastAuditSnapshot
        let isHierarchical = audit?.contextStrategy == "parent_expanded"
        let queryIntentName = deriveQueryIntent(from: audit?.retrievalConfig)
        // Deep Think mode is recursive even if audit snapshot isn't ready yet
        let isRecursive = audit?.isRecursiveRAG ?? (effectiveQualityMode == .deepThink)
        // Use live counters during processing, final count after completion
        let liveSteps = ragService.deepThinkLiveSteps
        // While an answer runs, `lastAuditSnapshot` is still the previous answer's, so its count would win: on his
        // iPhone on 2026-11-05 the panel read "1 reasoning sessions" during Session 4 (5.8).
        let callCount =
            isProcessing && isRecursive
            ? max(1, liveSteps)
            : (audit?.llmCallCount ?? (isRecursive ? liveSteps : 1))

        // Extract actual search weights from RetrievalConfig (dynamic per query intent)
        let retrievalConfig = audit?.retrievalConfig
        let vectorWt = Double(retrievalConfig?.vectorWeight ?? 0.6)
        let lexicalWt = Double(retrievalConfig?.lexicalWeight ?? 0.4)
        let mmrLambdaVal = Double(retrievalConfig?.mmrLambda ?? 0.6)

        // Case 1: Currently streaming
        if isProcessing, stage == .generating, !streamingText.isEmpty, generationStart != nil {
            return ConsolidatedMetrics(
                tokens: streamingTokensApprox,
                tokensPerSecond: streamingTokensPerSecond,
                characterCount: streamingText.count,
                elapsed: streamingElapsedTime,
                execution: execution,
                modelName: currentMetadata?.modelUsed ?? inferredModelName,
                ttft: ttft,
                toolCallCount: currentMetadata?.toolCallsMade ?? 0,
                sourceCount: currentRetrievedChunks.count,
                averageScore: averageSourceScore,
                isStreaming: true,
                hierarchicalChunkingActive: isHierarchical,
                parentChunksUsed: isHierarchical ? (audit?.contextChunksUsed ?? 0) : 0,
                siblingChunksAdded: 0,
                graphExpansionActive: effectiveQualityMode == .deepThink,
                graphEntitiesExtracted: 0,
                intentAwareWeightsActive: true,
                queryIntent: queryIntentName,
                isRecursiveRAG: isRecursive,
                recursiveCallCount: callCount,
                vectorWeight: vectorWt,
                lexicalWeight: lexicalWt,
                mmrLambda: mmrLambdaVal
            )
        }

        // Case 2: Completed response with metadata available
        if let meta = currentMetadata, !isProcessing {
            return ConsolidatedMetrics(
                tokens: meta.tokensGenerated,
                tokensPerSecond: Double(meta.tokensPerSecond ?? 0),
                characterCount: messages.last(where: { $0.role == .assistant })?.content.count ?? 0,
                elapsed: generatingElapsedFinal ?? 0,
                execution: execution,
                modelName: meta.modelUsed,
                ttft: meta.timeToFirstToken,
                toolCallCount: meta.toolCallsMade ?? 0,
                sourceCount: currentRetrievedChunks.count,
                averageScore: averageSourceScore,
                isStreaming: false,
                hierarchicalChunkingActive: isHierarchical,
                parentChunksUsed: isHierarchical ? (audit?.contextChunksUsed ?? 0) : 0,
                siblingChunksAdded: 0,
                graphExpansionActive: effectiveQualityMode == .deepThink,
                graphEntitiesExtracted: 0,
                intentAwareWeightsActive: true,
                queryIntent: queryIntentName,
                isRecursiveRAG: isRecursive,
                recursiveCallCount: callCount,
                vectorWeight: vectorWt,
                lexicalWeight: lexicalWt,
                mmrLambda: mmrLambdaVal
            )
        }

        return nil
    }

    /// Estimated context tokens based on retrieved chunks, conversation history, and current query
    /// Used by UnifiedMetricsBar to show context window usage
    var estimatedContextTokens: Int {
        let charsPerToken = 2.5
        func estimateTokens(_ chars: Int) -> Int {
            max(1, Int(ceil(Double(chars) / charsPerToken)))
        }

        // Estimate from retrieved chunks (conservative for on-device)
        let chunksTokens = currentRetrievedChunks.reduce(0) { acc, chunk in
            acc + estimateTokens(chunk.chunk.content.count)
        }

        // Conversation history (last 4 turns, 300 chars each max - mirrors RAGService injection)
        // RAGService injects: "PREVIOUS CONVERSATION:\nUser: ...\nAssistant: ...\n\nCURRENT QUESTION: "
        let historyMessages =
            messages
            .filter { $0.role != .system }
            .suffix(4)  // Last 4 turns (2 user + 2 assistant typically)
        let historyTokens = historyMessages.reduce(0) { acc, msg in
            let truncatedLength = min(msg.content.count, 300)
            return acc + estimateTokens(truncatedLength + 15)  // +15 for "User: " or "Assistant: " prefix
        }

        let historyFramingTokens = historyMessages.isEmpty ? 0 : 30  // "PREVIOUS CONVERSATION:\n" + "\nCURRENT QUESTION: "

        // Current prompt length
        let lastUserTokens = estimateTokens(
            messages.last(where: { $0.role == .user })?.content.count ?? 0
        )

        // System prompt (if set)
        let systemTokens = estimateTokens(systemPrompt.count)

        // Buffer for instruction framing
        let templateOverheadTokens = 200

        return min(
            maxContextTokensForUI,
            chunksTokens + historyTokens + historyFramingTokens + lastUserTokens + systemTokens + templateOverheadTokens
        )
    }

    /// Update speed history for sparkline - called when streamingText changes
    func updateSpeedHistory() {
        let currentTokens = streamingTokensApprox
        let now = Date()
        let interval = now.timeIntervalSince(lastSpeedSampleTime)

        // Sample every ~5 tokens or 0.3s, whichever comes first
        if currentTokens - lastSpeedSampleTokens >= 5 || interval >= 0.3 {
            if interval > 0.05 {
                let recentSpeed = Double(currentTokens - lastSpeedSampleTokens) / interval
                speedHistory.append(recentSpeed)
                // Keep last 30 samples
                if speedHistory.count > 30 {
                    speedHistory.removeFirst()
                }
            }
            lastSpeedSampleTokens = currentTokens
            lastSpeedSampleTime = now
        }
    }

    /// Reset speed tracking when starting a new generation
    func resetSpeedTracking() {
        speedHistory = []
        lastSpeedSampleTokens = 0
        lastSpeedSampleTime = Date()
    }

    private func seedScreenshotDemoIfNeeded() {
        #if DEBUG
            guard !didSeedScreenshotDemo else { return }
            guard LaunchArguments.has("--screenshot") || LaunchArguments.has("screenshot") else { return }

            // App Store listing scenes. See `seedStoreScene`.
            if let storeScene = LaunchArguments.valueEither(for: "screenshot-store") {
                didSeedScreenshotDemo = true
                onboardingStore.markAskedFirstQuery()
                seedStoreScene(storeScene)
                return
            }

            let wantsHero = LaunchArguments.has("--screenshot-chat-hero") || LaunchArguments.has("screenshot-chat-hero")
            let wantsDemo = LaunchArguments.has("--screenshot-chat-demo") || LaunchArguments.has("screenshot-chat-demo")
            let wantsSources =
                LaunchArguments.has("--screenshot-chat-sources") || LaunchArguments.has("screenshot-chat-sources")
            let wantsDetails =
                LaunchArguments.has("--screenshot-chat-details") || LaunchArguments.has("screenshot-chat-details")
            let wantsConsent =
                LaunchArguments.has("--screenshot-cloud-consent") || LaunchArguments.has("screenshot-cloud-consent")
            let wantsThinking =
                LaunchArguments.has("--screenshot-chat-thinking") || LaunchArguments.has("screenshot-chat-thinking")
            let wantsFullDemo =
                LaunchArguments.has("--screenshot-chat-full") || LaunchArguments.has("screenshot-chat-full")

            guard
                wantsHero || wantsDemo || wantsSources || wantsDetails || wantsConsent || wantsThinking || wantsFullDemo
            else { return }
            didSeedScreenshotDemo = true

            // IMPORTANT: Clear ALL state first to override any persisted chat history
            messages = []
            streamingText = ""
            currentRetrievedChunks = []
            currentMetadata = nil
            currentStructuredAnswer = nil
            showRetrievedDetails = false
            activeCloudConsent = nil
            thinkingEvents = []

            // Mark onboarding complete so starter prompts don't appear
            onboardingStore.markAskedFirstQuery()

            // 1) Full demo first (highest priority - includes everything beautiful)
            if wantsFullDemo {
                seedFullDemoContent()
                return
            }

            // 2) Cloud consent modal (if requested)
            if wantsConsent {
                activeCloudConsent = CloudTransmissionRecord(
                    provider: .applePCC,
                    modelName: "Apple Private Cloud Compute",
                    promptPreview: "Summarize the attached library and cite sources.",
                    promptCharacterCount: 1480,
                    contextChunkCount: 3,
                    contextHashes: ["a9f3…", "c18b…", "09d1…"],
                    estimatedBytes: 32000
                )
            }

            // 2) Chat hero (blank chat with starter prompts)
            if wantsHero {
                messages = []
                return
            }

            // 3) Base chat demo
            messages = [
                ChatMessage(role: .user, content: "Summarize the roadmap brief in three source-backed bullets."),
                ChatMessage(
                    role: .assistant,
                    content:
                        "• Privacy-first: Your docs stay on-device by default, with Apple Private Cloud Compute for eligible higher-capacity requests.\n"
                        + "• Fast, grounded answers: Hybrid search + re-ranking helps keep responses tied to your library.\n"
                        + "• Review path: citations, evidence snippets, and warning signals make source checks easier."
                ),
            ]

            // 4) Sources tray / details sheet
            if wantsSources || wantsDetails {
                let docId = UUID()
                func makeChunk(rank: Int, title: String, page: Int, snippet: String, score: Float) -> RetrievedChunk {
                    let meta = ChunkMetadata(
                        chunkIndex: rank,
                        pageNumber: page,
                        sectionTitle: title,
                        keywords: ["privacy", "retrieval", "roadmap"],
                        hasNumericData: true,
                        hasListStructure: true,
                        wordCount: snippet.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
                        characterCount: snippet.count
                    )
                    let chunk = DocumentChunk(
                        documentId: docId,
                        content: snippet,
                        embedding: [0, 0, 0, 0],
                        metadata: meta
                    )
                    return RetrievedChunk(
                        chunk: chunk,
                        similarityScore: score,
                        rank: rank,
                        sourceDocument: "Sample Roadmap Brief",
                        pageNumber: page
                    )
                }

                currentRetrievedChunks = [
                    makeChunk(
                        rank: 1,
                        title: "Prototype Scope",
                        page: 1,
                        snippet:
                            "The prototype supports local document import, library isolation, retrieval, citations, and evidence review.",
                        score: 0.86
                    ),
                    makeChunk(
                        rank: 2,
                        title: "Design Pillars",
                        page: 1,
                        snippet:
                            "Local-first files, source-backed answers, and visible retrieval diagnostics are the core design pillars.",
                        score: 0.81
                    ),
                    makeChunk(
                        rank: 3,
                        title: "Roadmap Tasks",
                        page: 1,
                        snippet:
                            "Improve ingestion coverage, benchmark retrieval behavior, and document known build limitations.",
                        score: 0.77
                    ),
                ]

                currentMetadata = ResponseMetadata(
                    timeToFirstToken: 0.35,
                    totalGenerationTime: 1.9,
                    tokensGenerated: 168,
                    tokensPerSecond: 62,
                    modelUsed: "On-device / PCC (auto)",
                    retrievalTime: 0.12,
                    retrievalConfigSummary: "Balanced",
                    gatingDecision: "allowed",
                    toolCallsMade: 2,
                    embeddingProvider: "nl_embedding"
                )

                if wantsDetails {
                    showRetrievedDetails = true
                }
            }

            // 5) Thinking events timeline (Deep Think / Maximum mode showcase)
            if wantsThinking {
                thinkingEvents = [
                    ThinkingEvent(
                        kind: .planning, title: "Query analysis", detail: "Identified: roadmap summary request"),
                    ThinkingEvent(
                        kind: .queryRewrite, title: "Multi-query expansion", detail: "Generated 4 search variations"),
                    ThinkingEvent(
                        kind: .vectorSearch, title: "Semantic search", detail: "384-dim embeddings • cosine similarity"),
                    ThinkingEvent(kind: .bm25, title: "Keyword search", detail: "BM25 scoring • k1=1.2, b=0.75"),
                    ThinkingEvent(kind: .rrf, title: "RRF fusion", detail: "Merged rankings • k=60"),
                    ThinkingEvent(kind: .mmr, title: "MMR diversification", detail: "λ=0.6 • reduced redundancy"),
                    ThinkingEvent(kind: .rerank, title: "Re-ranking", detail: "Cross-encoder • top 5 → 3"),
                    ThinkingEvent(kind: .context, title: "Context ready", detail: "3 chunks • 847 words"),
                    ThinkingEvent(
                        kind: .generation, title: "Generating response", detail: "Apple Intelligence • on-device"),
                ]
            }
        #endif
    }

    #if DEBUG
        /// The App Store listing scenes, written 2026-09-22. The earlier demo scenes above showed a
        /// fictional roadmap and figures nobody measured ("65 tok/s", "384-dim embeddings"). These use
        /// the app's real grounded-answer view, so the listing shows what a user actually sees:
        /// verified claims with page quotes, a refusal with its Information Gaps panel, the sources
        /// sheet, and the Private Cloud Compute consent sheet. The one figure shown, 27 tokens a
        /// second on device, is the measured A18 Pro number. DEBUG only; nothing here ships.
        ///
        /// `--screenshot --screenshot-tab chat --screenshot-store answer|refusal|sources|consent|page`
        ///
        /// `page` (added 2026-10-17) opens the first claim's passage on page 7 of a lease PDF drawn for the scene
        /// (`StoreScenePDF`), as tapping the claim does in 5.7: the real page view with the passage highlighted. iOS only.
        private func seedStoreScene(_ scene: String) {
            streamingText = ""
            currentStructuredAnswer = nil
            showRetrievedDetails = false
            activeCloudConsent = nil
            thinkingEvents = []

            let docId = UUID()
            func chunk(
                _ rank: Int, _ doc: String, _ page: Int, _ section: String, _ text: String, _ score: Float
            )
                -> RetrievedChunk
            {
                let meta = ChunkMetadata(
                    chunkIndex: rank,
                    pageNumber: page,
                    sectionTitle: section,
                    keywords: ["lease", "termination", "notice"],
                    hasNumericData: true,
                    hasListStructure: false,
                    wordCount: text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
                    characterCount: text.count
                )
                return RetrievedChunk(
                    chunk: DocumentChunk(documentId: docId, content: text, embedding: [0, 0, 0, 0], metadata: meta),
                    similarityScore: score,
                    rank: rank,
                    sourceDocument: doc,
                    pageNumber: page
                )
            }

            let s1 =
                "After the initial twelve-month term, either party may terminate this lease with sixty (60) days' written notice."
            let s2 =
                "Tenant may terminate before the end of the initial term by paying an early termination fee equal to two (2) months' rent."
            let s3 = "All notices under this lease must be delivered in writing to the management office."
            let chunks = [
                chunk(1, "Apartment Lease.pdf", 7, "Termination", s1, 0.91),
                chunk(2, "Apartment Lease.pdf", 8, "Early Termination", s2, 0.87),
                chunk(3, "House Rules.pdf", 2, "Notices", s3, 0.74),
            ]

            let answerText =
                "After the first 12 months, either of you can end the lease with 60 days' written notice. Ending it earlier costs two months' rent."
            let answered = StructuredAnswer.Builder()
                .setAnswerType(.lookup)
                .setAnswer(answerText)
                .addEvidence(
                    id: "S1", page: 7, quote: s1, documentName: "Apartment Lease.pdf", sectionPath: ["Termination"]
                )
                .addEvidence(
                    id: "S2", page: 8, quote: s2, documentName: "Apartment Lease.pdf",
                    sectionPath: ["Early Termination"]
                )
                .addEvidence(id: "S3", page: 2, quote: s3, documentName: "House Rules.pdf", sectionPath: ["Notices"])
                .addClaim(
                    "Either party can end the lease with 60 days' written notice after the first 12 months.",
                    evidenceIds: ["S1"], confidence: 0.96, verificationVerdict: .supported
                )
                .addClaim(
                    "Ending it before then costs a fee of two months' rent.",
                    evidenceIds: ["S2"], confidence: 0.94, verificationVerdict: .supported
                )
                .addClaim(
                    "Notice has to be in writing, delivered to the management office.",
                    evidenceIds: ["S3"], confidence: 0.9, verificationVerdict: .supported
                )
                .setTopScore(0.91)
                .build()
            let answeredMeta = ResponseMetadata(
                timeToFirstToken: 0.6,
                totalGenerationTime: 3.1,
                tokensGenerated: 84,
                tokensPerSecond: 27,
                modelUsed: "Apple Intelligence (on-device)",
                retrievalTime: 0.21,
                retrievalConfigSummary: "Balanced",
                gatingDecision: "verified:94%",
                toolCallsMade: 0,
                embeddingProvider: "coreml_sentence_embedding"
            )

            let refusalText =
                "Your documents don't say whether pets are allowed. I searched Apartment Lease.pdf and House Rules.pdf, and neither one mentions pets, so I won't guess."
            let refused = StructuredAnswer.Builder()
                .setRefuse(true)
                .setAnswer(refusalText)
                .addMissing("A pet policy. Neither Apartment Lease.pdf nor House Rules.pdf mentions pets.")
                .setTopScore(0.31)
                .build()
            let refusedMeta = ResponseMetadata(
                timeToFirstToken: 0.4,
                totalGenerationTime: 1.2,
                tokensGenerated: 38,
                tokensPerSecond: 27,
                modelUsed: "Apple Intelligence (on-device)",
                retrievalTime: 0.19,
                retrievalConfigSummary: "Balanced",
                gatingDecision: nil,
                toolCallsMade: 0,
                embeddingProvider: "coreml_sentence_embedding"
            )

            let askTermination = ChatMessage(role: .user, content: "How much notice do I need to give to end my lease?")
            let termination = ChatMessage(
                role: .assistant, content: answerText, metadata: answeredMeta,
                retrievedChunks: chunks, structuredAnswer: answered)

            messages = [askTermination, termination]
            currentRetrievedChunks = chunks
            // Left nil except for the sources sheet, which reads it: with it set, a live metrics
            // strip sits above the conversation and crowds the scene.
            currentMetadata = nil

            switch scene.lowercased() {
            case "refusal":
                messages += [
                    ChatMessage(role: .user, content: "Am I allowed to have a dog?"),
                    ChatMessage(
                        role: .assistant, content: refusalText, metadata: refusedMeta,
                        retrievedChunks: [], structuredAnswer: refused),
                ]
                currentRetrievedChunks = []
            case "sources":
                currentMetadata = answeredMeta
                showRetrievedDetails = true
            case "page":
                #if os(iOS)
                    if let url = StoreScenePDF.lease(termination: s1, earlyTermination: s2) {
                        let lease = Document(filename: "Apartment Lease.pdf", fileURL: url, contentType: .pdf)
                        storeScenePage = StoreScenePage(document: lease, page: 7, passage: s1, chunk: chunks[0])
                    }
                #endif
            case "consent":
                activeCloudConsent = CloudTransmissionRecord(
                    provider: .applePCC,
                    modelName: "Apple Private Cloud Compute",
                    promptPreview: "Compare the termination terms in both leases and cite the pages.",
                    promptCharacterCount: 612,
                    contextChunkCount: 4,
                    contextHashes: ["7c1e…", "a902…", "3fd4…", "e81b…"],
                    estimatedBytes: 14000
                )
            default:
                break
            }
        }
    #endif

    /// Seeds a comprehensive full demo for App Store screenshots
    /// Includes: polished conversation, thinking timeline, sources, metadata
    private func seedFullDemoContent() {
        // Thinking events - show the RAG pipeline in action
        thinkingEvents = [
            ThinkingEvent(kind: .planning, title: "Query analysis", detail: "Identified: roadmap + privacy request"),
            ThinkingEvent(kind: .queryRewrite, title: "Multi-query expansion", detail: "Generated 4 search variations"),
            ThinkingEvent(
                kind: .vectorSearch, title: "Semantic search", detail: "384-dim embeddings • cosine similarity"),
            ThinkingEvent(kind: .bm25, title: "Keyword search", detail: "BM25 scoring • k1=1.2, b=0.75"),
            ThinkingEvent(kind: .rrf, title: "RRF fusion", detail: "Merged rankings • k=60"),
            ThinkingEvent(kind: .mmr, title: "MMR diversification", detail: "λ=0.6 • reduced redundancy"),
            ThinkingEvent(kind: .rerank, title: "Re-ranking", detail: "Cross-encoder • top 5 → 3"),
            ThinkingEvent(kind: .context, title: "Context ready", detail: "3 chunks • 847 words"),
            ThinkingEvent(kind: .generation, title: "Generating response", detail: "Apple Intelligence"),
        ]

        // Demo conversation with polished response
        let demoMetadata = ResponseMetadata(
            timeToFirstToken: 0.28,
            totalGenerationTime: 2.4,
            tokensGenerated: 156,
            tokensPerSecond: 65,
            modelUsed: "Apple Intelligence",
            retrievalTime: 0.18,
            retrievalConfigSummary: "Balanced",
            gatingDecision: "allowed",
            toolCallsMade: 0,
            embeddingProvider: "coreml_sentence_embedding",
            usedAgenticMode: true,
            qualityModeName: "Deep Think",
            reasoningTrace: [
                "🔍 Analyzing query intent: roadmap + privacy information requested",
                "📚 Retrieved 3 highly relevant chunks from roadmap brief",
                "🧠 Synthesizing multi-source response with citations",
            ]
        )

        messages = [
            ChatMessage(role: .user, content: "What are the key roadmap items and privacy features?"),
            ChatMessage(
                role: .assistant,
                content: """
                    Based on your documents, here's a comprehensive overview:

                    ## Roadmap Items
                    • **Ingestion**: expand parsing coverage and document normalization
                    • **Retrieval**: improve hybrid search, re-ranking, and context selection
                    • **Review**: make citations, source snippets, and warnings easier to inspect

                    ## Privacy Architecture
                    Reading, searching and citing happen **on your device**. An answer goes to Apple's Private Cloud Compute only with your permission, and Apple states it keeps nothing after answering.

                    The hybrid search combines semantic understanding with keyword matching for accurate, grounded responses. [S1] [S2]
                    """,
                metadata: demoMetadata,
                retrievedChunks: nil
            ),
        ]

        // Source chunks for the sources tray
        let docId = UUID()
        func makeChunk(rank: Int, title: String, page: Int, snippet: String, score: Float) -> RetrievedChunk {
            let meta = ChunkMetadata(
                chunkIndex: rank,
                pageNumber: page,
                sectionTitle: title,
                keywords: ["privacy", "roadmap", "retrieval"],
                hasNumericData: true,
                hasListStructure: true,
                wordCount: snippet.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
                characterCount: snippet.count
            )
            let chunk = DocumentChunk(
                documentId: docId,
                content: snippet,
                embedding: [0, 0, 0, 0],
                metadata: meta
            )
            return RetrievedChunk(
                chunk: chunk,
                similarityScore: score,
                rank: rank,
                sourceDocument: "Sample Roadmap Brief.md",
                pageNumber: page
            )
        }

        currentRetrievedChunks = [
            makeChunk(
                rank: 1,
                title: "Prototype Scope",
                page: 1,
                snippet: "Ingestion, retrieval, and review are the main prototype workstreams for this snapshot.",
                score: 0.92
            ),
            makeChunk(
                rank: 2,
                title: "Privacy Architecture",
                page: 1,
                snippet:
                    "Privacy-first: reading and searching stay on the device; an answer goes to Apple's Private Cloud Compute only with permission. No third-party cloud.",
                score: 0.88
            ),
            makeChunk(
                rank: 3,
                title: "Hybrid Search",
                page: 2,
                snippet:
                    "Combines semantic embeddings with BM25 keyword matching. MMR ensures diverse, non-redundant results.",
                score: 0.84
            ),
        ]

        currentMetadata = demoMetadata
    }

    // MARK: - Active-container counts

    func recalcActiveCounts() async {
        await MainActor.run {
            let activeId = ragService.containerService.activeContainerId
            let defaultId = ragService.containerService.containers.first?.id

            // Match Visualizations/Documents parity for legacy docs
            let docsForActive = ragService.documents.filter { doc in
                if let cid = doc.containerId {
                    return cid == activeId
                } else {
                    return activeId == defaultId
                }
            }

            // Use document.totalChunks sum - reactive since $documents is @Published
            // This avoids async database queries that might return stale data
            self.activeDocCount = docsForActive.count
            self.activeChunkCount = docsForActive.reduce(0) { $0 + $1.totalChunks }
        }
    }

    // MARK: - Derived counters
    private var latestRetrievedCount: Int {
        messages.last(where: { $0.role == .assistant })?.retrievedChunks?.count ?? 0
    }

    private var coveredDocCount: Int {
        let names = currentRetrievedChunks.map { $0.sourceDocument }.filter { !$0.isEmpty }
        return Set(names).count
    }

    private var tokensApprox: Int {
        // Approximate tokens by whitespace-separated words
        let words = streamingText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return words.count
    }

    private var tokensPerSecondApprox: Double {
        guard let start = generationStart else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(tokensApprox) / elapsed
    }

    // Live per-stage elapsed timers
    private var embeddingElapsedDisplay: TimeInterval? {
        let _ = nowTick
        if let final = embeddingElapsedFinal, stage != .embedding { return final }
        guard let start = embeddingStart else { return embeddingElapsedFinal }
        return Date().timeIntervalSince(start)
    }
    private var searchingElapsedDisplay: TimeInterval? {
        let _ = nowTick
        if let final = searchingElapsedFinal,
            stage == .generating || stage == .complete || stage == .idle
        {
            return final
        }
        guard let start = searchingStart else { return searchingElapsedFinal }
        return Date().timeIntervalSince(start)
    }
    private var generatingElapsedDisplay: TimeInterval? {
        let _ = nowTick
        if stage == .generating, let start = generatingStartTS {
            return Date().timeIntervalSince(start)
        }
        return generatingElapsedFinal
    }

}

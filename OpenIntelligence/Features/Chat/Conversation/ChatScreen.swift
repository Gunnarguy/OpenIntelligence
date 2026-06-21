//
//  ChatScreen.swift
//  OpenIntelligence
//
//  Created by Cline on 10/28/25.
//

import Combine
import Foundation
import StoreKit
import SwiftUI
import Translation

/// Data container for unified metrics bar (shown during streaming AND after completion)
private struct ConsolidatedMetrics {
    let tokens: Int
    let tokensPerSecond: Double
    let characterCount: Int
    let elapsed: TimeInterval
    let execution: ChatExecutionLocation
    let modelName: String
    let ttft: TimeInterval?
    let toolCallCount: Int
    let sourceCount: Int
    let averageScore: Float?
    let isStreaming: Bool

    // Advanced RAG features (FullBlownUpgrade)
    var hierarchicalChunkingActive: Bool = false
    var parentChunksUsed: Int = 0
    var siblingChunksAdded: Int = 0
    var graphExpansionActive: Bool = false
    var graphEntitiesExtracted: Int = 0
    var intentAwareWeightsActive: Bool = true
    var queryIntent: String = ""

    // Recursive RAG metrics (Deep Think mode)
    var isRecursiveRAG: Bool = false
    var recursiveCallCount: Int = 1

    // Hybrid search weights (from RetrievalConfig - dynamic per query intent)
    // Default: 40% vector / 60% lexical (favors keyword matching)
    // Keyword queries: 25% / 75% | Conceptual queries: 55% / 45%
    var vectorWeight: Double = 0.4
    var lexicalWeight: Double = 0.6
    var mmrLambda: Double = 0.6
}

@MainActor
private final class ContinuedQueryCoordinator: ObservableObject {
    var expirationHandler: (() -> Void)?

    private var trackedSessionId: UUID?
    private var lastFinishedSessionId: UUID?
    private var lastFinishedSuccess: Bool?
    private var title: String = "Answering your question"
    private var queryPreview: String = ""
    private var firstTokenObserved = false

    init() {
        QueryRuntimeBridge.shared.configureContinuedQuery(
            run: { [weak self] in
                guard let self else { return false }
                return await self.awaitTrackedQueryCompletion()
            },
            expiration: { [weak self] in
                self?.expirationHandler?()
            }
        )
    }

    func begin(query: String, sessionId: UUID) {
        trackedSessionId = sessionId
        lastFinishedSessionId = nil
        lastFinishedSuccess = nil
        firstTokenObserved = false
        title = "Answering your question"
        queryPreview = Self.makeQueryPreview(from: query)

        QueryRuntimeBridge.shared.beginUserInitiatedQuery(
            title: title,
            subtitle: queryPreview
        )
        reportProgress(subtitle: "Preparing answer", fraction: 0.02)
    }

    func markEmbedding() {
        reportProgress(subtitle: "Understanding your question", fraction: 0.12)
    }

    func markSearching() {
        reportProgress(subtitle: "Searching this library", fraction: 0.36)
    }

    func markGenerating() {
        reportProgress(subtitle: "Building the answer", fraction: 0.62)
    }

    func markFirstToken() {
        guard !firstTokenObserved else { return }
        firstTokenObserved = true
        reportProgress(subtitle: "Writing the answer", fraction: 0.82)
    }

    func handleScenePhaseChange(_ phase: ScenePhase, isProcessing: Bool) {
        guard trackedSessionId != nil else {
            if phase == .active {
                QueryRuntimeBridge.shared.endForegroundFallbackQueryExtension()
            }
            return
        }

        switch phase {
        case .inactive, .background:
            guard isProcessing else { return }
            QueryRuntimeBridge.shared.beginForegroundFallbackQueryExtensionIfNeeded(
                reason: "App moved to the background while answering a question."
            )
        case .active:
            QueryRuntimeBridge.shared.endForegroundFallbackQueryExtension()
        @unknown default:
            break
        }
    }

    func complete(sessionId: UUID, success: Bool) {
        guard trackedSessionId == sessionId else { return }

        lastFinishedSessionId = sessionId
        lastFinishedSuccess = success
        QueryRuntimeBridge.shared.completeUserInitiatedQuery(success: success)
        trackedSessionId = nil
        firstTokenObserved = false
    }

    func cancelCurrentQuery() {
        guard let trackedSessionId else {
            QueryRuntimeBridge.shared.endForegroundFallbackQueryExtension()
            return
        }

        complete(sessionId: trackedSessionId, success: false)
    }

    private func reportProgress(subtitle: String, fraction: Double) {
        guard trackedSessionId != nil else { return }

        QueryRuntimeBridge.shared.updateContinuedQueryProgress(
            title: title,
            subtitle: subtitle,
            fraction: fraction
        )
    }

    private func awaitTrackedQueryCompletion() async -> Bool {
        while !Task.isCancelled {
            if let trackedSessionId,
               trackedSessionId == lastFinishedSessionId,
               let lastFinishedSuccess {
                return lastFinishedSuccess
            }

            if trackedSessionId == nil {
                return lastFinishedSuccess ?? false
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        return false
    }

    private static func makeQueryPreview(from query: String) -> String {
        let collapsed = query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 72 else { return collapsed }
        return String(collapsed.prefix(69)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

// ChatV2 entry point (feature-flagged from ContentView)
@MainActor
struct ChatScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @ObservedObject var ragService: RAGService

    init(ragService: RAGService) {
        self.ragService = ragService
    }

    @AppStorage("retrievalTopK") private var retrievalTopK: Int = 3
    @State private var showScrollToBottom: Bool = false
    @State private var messages: [ChatMessage] = []
    @State private var didSeedScreenshotDemo: Bool = false
    @State private var streamingText: String = ""
    @State private var streamingBuffer: String = ""
    @State private var streamingPumpTask: Task<Void, Never>? = nil
    @State private var currentQueryTask: Task<Void, Never>? = nil // Track current query for cancellation
    @State private var currentQuerySessionId: UUID? = nil
    @State private var queryStart: Date? = nil
    @State private var hasReceivedStreamToken: Bool = false
    @State private var generationStart: Date? = nil
    // Per-stage timing
    @State private var embeddingStart: Date? = nil
    @State private var searchingStart: Date? = nil
    @State private var generatingStartTS: Date? = nil
    @State private var embeddingElapsedFinal: TimeInterval? = nil
    @State private var searchingElapsedFinal: TimeInterval? = nil
    @State private var generatingElapsedFinal: TimeInterval? = nil
    @State private var isStreamFinished: Bool = false
    // Live clock tick to drive elapsed UI — only connected during processing to save battery
    @State private var nowTick: Date = Date()
    @State private var processingClock = Timer.publish(every: 0.2, on: .main, in: .common)
    // Ephemeral UI and retrieval
    @StateObject private var toastManager = ToastManager()
    @State private var currentRetrievedChunks: [RetrievedChunk] = []
    @State private var currentMetadata: ResponseMetadata? = nil
    @State private var currentStructuredAnswer: StructuredAnswer? = nil
    @State private var showRetrievedDetails: Bool = false
    @State private var thinkingEvents: [ThinkingEvent] = []
    @State private var requestedExecutionContext: ExecutionContext = .automatic

    // Processing State
    @State private var isProcessing: Bool = false
    @State private var stage: ChatProcessingStage = .idle
    @State private var execution: ChatExecutionLocation = .unknown
    @State private var ttft: TimeInterval?

    // Active-container scoped counts for status bar
    @State private var activeDocCount: Int = 0
    @State private var activeChunkCount: Int = 0

    // One-off per-message container override
    @State private var messageContainerOverride: UUID? = nil

    // Cloud consent prompt state
    @State private var activeCloudConsent: CloudTransmissionRecord? = nil

    // Translation overlay
    @State private var translationText: String = ""
    @State private var showTranslation: Bool = false

    // WritingTools overlay
    @State private var writingToolsResult: String = ""
    @State private var writingToolsTitle: String = ""
    @State private var showWritingToolsResult: Bool = false
    @State private var writingToolsProcessing: Bool = false

    // Vision Capture overlay
    @State private var showVisionCapture: Bool = false
    @State private var showPlanSheet: Bool = false
    @State private var planEntryPoint: PlanUpgradeEntryPoint = .maximumModeLimit
    @State private var showMaximumModeLimitDialog: Bool = false
    @State private var maximumModeLimitDialogMessage: String = ""

    // Hardware telemetry for Motherboard HUD visibility
    private var hardwareTelemetry = HardwareTelemetryState.shared

    // Dynamic suggested questions
    @State private var dynamicSuggestedQuestions: [String] = []
    @State private var dynamicQuestionCategories: [String: SuggestedQuestionsService.QuestionCategory] = [:]
    @State private var dynamicQuestionDetails: [String: SuggestedQuestionsService.SuggestedQuestion] = [:]
    @State private var suggestedQuestionsTask: Task<Void, Never>? = nil
    @State private var isRefreshingSuggestions = false
    private let suggestedQuestionsService = SuggestedQuestionsService.shared
    @State private var lastProcessedContainerId: UUID? = nil
    @State private var lastLoadedChatContainerId: UUID? = nil
    @State private var lastProcessedDocuments: [Document]? = nil
    @State private var isAppeared = false
    @State private var needsSuggestedQuestionsRefresh = false

    // Smart Reply follow-up suggestions (shown after AI response)
    @State private var followUpSuggestions: [SmartReply] = []
    @State private var followUpSuggestionsTask: Task<Void, Never>? = nil
    @State private var reviewPromptTask: Task<Void, Never>? = nil
    @State private var showFriendlyReviewPrompt = false
    @State private var showFeedbackEmailPrompt = false

    // Speed history for sparkline graph
    @State private var speedHistory: [Double] = []
    @State private var lastSpeedSampleTokens: Int = 0
    @State private var lastSpeedSampleTime: Date = .init()
    @State private var lastSemanticQuery: String? = nil
    @StateObject private var continuedQueryCoordinator = ContinuedQueryCoordinator()

    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    // Settings (synchronized with SettingsView via @AppStorage)
    @AppStorage("llmTemperature") private var temperature: Double = 0.7
    @AppStorage("llmMaxTokens") private var maxTokens: Int = 512
    @AppStorage("llmTopP") private var topP: Double = 0.9
    @AppStorage("llmFrequencyPenalty") private var frequencyPenalty: Double = 0.0
    @AppStorage("llmPresencePenalty") private var presencePenalty: Double = 0.0
    @AppStorage("llmRepetitionPenalty") private var repetitionPenalty: Double = 1.0
    @AppStorage("llmSystemPrompt") private var systemPrompt: String = "You are a helpful assistant."
    @AppStorage("llmContextLength") private var contextLength: Int = 2048

    /// Context tokens actually used (from audit) or estimated
    /// Uses real values from RAGService when available for accuracy
    private var actualContextTokensUsed: Int {
        // Prefer real audit data when available
        if let audit = ragService.lastAuditSnapshot {
            // Convert chars to tokens (audit has contextChars)
            return max(1, audit.contextChars / 3) // ~3 chars per token conservative
        }
        return estimatedContextTokens
    }

    /// Max context tokens - use audit's availableContextTokens when available
    /// This reflects the ACTUAL budget RAGService computed, not a hardcoded value
    private var maxContextTokensForUI: Int {
        if let audit = ragService.lastAuditSnapshot {
            // Show available context budget (what was actually allocated)
            return audit.availableContextTokens > 0 ? audit.availableContextTokens : audit.baseWindowTokens
        }

        // Fallback to base window tokens
        return 4096
    }

    // MARK: - Metrics Bar Helpers (split to avoid type-check timeout)

    /// Build the primary metrics bar when consolidatedMetricsData is available
    @ViewBuilder
    private func primaryMetricsBar(metricsData: ConsolidatedMetrics) -> some View {
        let deepThinkTokens = isProcessing ? ragService.deepThinkLiveTokens : (ragService.lastAuditSnapshot?.totalTokensAcrossCalls ?? ragService.deepThinkLiveTokens)
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
    private func minimalMetricsBar() -> some View {
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
            contextTokens: auditSnapshot?.isRecursiveRAG == true ? max(liveTokens, auditSnapshot?.totalTokensAcrossCalls ?? 0) : actualContextTokensUsed,
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

    var body: some View {
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
                onDiscardPaused: { ragService.discardPausedIngestionQueue() }
            )
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Motherboard HUD - Full-screen X-ray overlay
            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            writingToolsProgressOverlay
        }
        // MARK: - Vision Capture (v2 feature - disabled for v1 App Store release)
        // .fullScreenCover(isPresented: $showVisionCapture) {
        //     CameraVisionOverlayView(
        //         ragService: ragService,
        //         containerService: ragService.containerService
        //     )
        // }
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
        // Start/stop the 5 Hz timer based on processing state — saves battery when idle
        .onChange(of: isProcessing) { _, newValue in
            if newValue {
                processingClock = Timer.publish(every: 0.2, on: .main, in: .common)
                _ = processingClock.connect()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            continuedQueryCoordinator.handleScenePhaseChange(newPhase, isProcessing: isProcessing)
            if newPhase != .active {
                reviewPromptTask?.cancel()
                reviewPromptTask = nil
            }
        }
        // Recalculate counts when active container changes
        .task(id: ragService.containerService.activeContainerId) {
            reviewPromptTask?.cancel()
            reviewPromptTask = nil

            // Cancel any in-flight query from the previous library to prevent cross-container bleed
            continuedQueryCoordinator.cancelCurrentQuery()
            currentQuerySessionId = nil
            currentQueryTask?.cancel()
            currentQueryTask = nil

            // Reset transient generation state for the newly active library
            if isProcessing {
                resetStreamingState()
                isProcessing = false
                stage = .idle
            }

            // Don't load persisted history in screenshot demo mode - let seedFullDemoContent() handle it
            #if DEBUG
            if didSeedScreenshotDemo { return }
            #endif
            let activeId = ragService.containerService.activeContainerId
            let isSameChatContainer = (lastLoadedChatContainerId == activeId)
            let isSameDocsContainer = (lastProcessedContainerId == activeId)

            if !isSameChatContainer {
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
                dynamicQuestionCategories = [:]
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
            thinkingEvents = events
        }
        .onReceive(ragService.$pendingCloudConsent) { record in
            activeCloudConsent = record
        }
        .toolbar {
            #if os(iOS)
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

                        Button(role: .destructive) {
                            guard !isProcessing else { return }
                            clearChat()
                        } label: {
                            Label("Clear Chat", systemImage: "trash")
                        }
                        .disabled(messages.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .opacity(messages.isEmpty ? 0.5 : 1.0)
                    }
                    .disabled(messages.isEmpty)
                    .animation(nil, value: messages.count)
                }
            #else
                ToolbarItem {
                    Menu {
                        Button {
                            guard !isProcessing else { return }
                            newChat()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .disabled(messages.isEmpty)

                        Button(role: .destructive) {
                            guard !isProcessing else { return }
                            clearChat()
                        } label: {
                            Label("Clear Chat", systemImage: "trash")
                        }
                        .disabled(messages.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .opacity(messages.isEmpty ? 0.5 : 1.0)
                    }
                    .disabled(messages.isEmpty)
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
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    Text("Retrieved Sources")
                        .font(DSTypography.title)
                    if currentRetrievedChunks.isEmpty {
                        Text("Searching…")
                            .font(DSTypography.body)
                            .foregroundColor(DSColors.secondaryText)
                    } else {
                        SourceChipsView(chunks: currentRetrievedChunks) {}
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanUpgradeSheet(entryPoint: planEntryPoint)
        }
        .sheet(item: $activeCloudConsent) { record in
            CloudConsentPromptView(record: record) { decision in
                Task { await ragService.resolveCloudConsent(decision: decision) }
            }
            .interactiveDismissDisabled(true)
#if os(iOS)
            .presentationDetents([.height(580), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
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
            "Enjoying OpenIntelligence?",
            isPresented: $showFriendlyReviewPrompt
        ) {
            Button("I love it! ❤️") {
                requestReview()
            }
            Button("Write a Review ✍️") {
                openURL(OpenIntelligenceLinks.writeReviewURL)
            }
            Button("Needs improvement 💬") {
                openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "In-App Feedback Prompt"))
            }
            Button("Maybe later", role: .cancel) {}
        } message: {
            Text("OpenIntelligence is fully on-device and private. A quick rating or review helps the app grow and keeps me building!")
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
            Text("I'm sorry that answer wasn't helpful. Please send me your feedback so I can improve OpenIntelligence!")
        }
.onAppear {
    let ragService = self.ragService
    continuedQueryCoordinator.expirationHandler = { [weak ragService] in
        ragService?.cancelActiveGeneration(resetSession: true)
        Task { @MainActor in
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
    // Seed screenshot demo FIRST before loading persisted history
    seedScreenshotDemoIfNeeded()
    entitlementStore.refreshTransientState()
    isAppeared = true
    if needsSuggestedQuestionsRefresh || dynamicSuggestedQuestions.isEmpty {
        needsSuggestedQuestionsRefresh = false
        refreshDynamicQuestions()
    }
}
.onDisappear {
    isAppeared = false
}
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ActiveModelRouteResolved"))) { notification in
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
.userActivity("com.openintelligence.chat") { activity in
    activity.title = "Chat with Documents"
    activity.isEligibleForSearch = true
    activity.isEligibleForHandoff = true
    #if os(iOS)
    activity.isEligibleForPrediction = true
    #endif
    if let containerId = ragService.containerService.activeContainerId as UUID? {
        activity.userInfo = ["containerId": containerId]
    }
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
            #if canImport(UIKit)
            UIPasteboard.general.string = writingToolsResult
            #endif
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
    private var effectiveQualityMode: RAGQualityMode {
        #if DEBUG
        if didSeedScreenshotDemo {
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
    private var consolidatedMetricsData: ConsolidatedMetrics? {
        // Extract advanced RAG features from audit snapshot
        let audit = ragService.lastAuditSnapshot
        let isHierarchical = audit?.contextStrategy == "parent_expanded"
        let queryIntentName = deriveQueryIntent(from: audit?.retrievalConfig)
        // Deep Think mode is recursive even if audit snapshot isn't ready yet
        let isRecursive = audit?.isRecursiveRAG ?? (effectiveQualityMode == .deepThink)
        // Use live counters during processing, final count after completion
        let liveSteps = ragService.deepThinkLiveSteps
        let callCount = audit?.llmCallCount ?? (isRecursive ? liveSteps : 1)

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
    private var estimatedContextTokens: Int {
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
        let historyMessages = messages
            .filter { $0.role != .system }
            .suffix(4) // Last 4 turns (2 user + 2 assistant typically)
        let historyTokens = historyMessages.reduce(0) { acc, msg in
            let truncatedLength = min(msg.content.count, 300)
            return acc + estimateTokens(truncatedLength + 15) // +15 for "User: " or "Assistant: " prefix
        }

        let historyFramingTokens = historyMessages.isEmpty ? 0 : 30 // "PREVIOUS CONVERSATION:\n" + "\nCURRENT QUESTION: "

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
    private func updateSpeedHistory() {
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
    private func resetSpeedTracking() {
        speedHistory = []
        lastSpeedSampleTokens = 0
        lastSpeedSampleTime = Date()
    }

    private func seedScreenshotDemoIfNeeded() {
        #if DEBUG
            guard !didSeedScreenshotDemo else { return }
            guard LaunchArguments.has("--screenshot") || LaunchArguments.has("screenshot") else { return }

            let wantsHero = LaunchArguments.has("--screenshot-chat-hero") || LaunchArguments.has("screenshot-chat-hero")
            let wantsDemo = LaunchArguments.has("--screenshot-chat-demo") || LaunchArguments.has("screenshot-chat-demo")
            let wantsSources = LaunchArguments.has("--screenshot-chat-sources") || LaunchArguments.has("screenshot-chat-sources")
            let wantsDetails = LaunchArguments.has("--screenshot-chat-details") || LaunchArguments.has("screenshot-chat-details")
            let wantsConsent = LaunchArguments.has("--screenshot-cloud-consent") || LaunchArguments.has("screenshot-cloud-consent")
            let wantsThinking = LaunchArguments.has("--screenshot-chat-thinking") || LaunchArguments.has("screenshot-chat-thinking")
            let wantsFullDemo = LaunchArguments.has("--screenshot-chat-full") || LaunchArguments.has("screenshot-chat-full")

            guard wantsHero || wantsDemo || wantsSources || wantsDetails || wantsConsent || wantsThinking || wantsFullDemo else { return }
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
                    "• Privacy-first: Your docs stay on-device by default, with Apple Private Cloud Compute for eligible higher-capacity requests.\n" +
                        "• Fast, grounded answers: Hybrid search + re-ranking helps keep responses tied to your library.\n" +
                        "• Review path: citations, evidence snippets, and warning signals make source checks easier."
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
                        snippet: "The prototype supports local document import, library isolation, retrieval, citations, and evidence review.",
                        score: 0.86
                    ),
                    makeChunk(
                        rank: 2,
                        title: "Design Pillars",
                        page: 1,
                        snippet: "Local-first files, source-backed answers, and visible retrieval diagnostics are the core design pillars.",
                        score: 0.81
                    ),
                    makeChunk(
                        rank: 3,
                        title: "Roadmap Tasks",
                        page: 1,
                        snippet: "Improve ingestion coverage, benchmark retrieval behavior, and document known build limitations.",
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
                    ThinkingEvent(kind: .planning, title: "Query analysis", detail: "Identified: roadmap summary request"),
                    ThinkingEvent(kind: .queryRewrite, title: "Multi-query expansion", detail: "Generated 4 search variations"),
                    ThinkingEvent(kind: .vectorSearch, title: "Semantic search", detail: "384-dim embeddings • cosine similarity"),
                    ThinkingEvent(kind: .bm25, title: "Keyword search", detail: "BM25 scoring • k1=1.2, b=0.75"),
                    ThinkingEvent(kind: .rrf, title: "RRF fusion", detail: "Merged rankings • k=60"),
                    ThinkingEvent(kind: .mmr, title: "MMR diversification", detail: "λ=0.6 • reduced redundancy"),
                    ThinkingEvent(kind: .rerank, title: "Re-ranking", detail: "Cross-encoder • top 5 → 3"),
                    ThinkingEvent(kind: .context, title: "Context ready", detail: "3 chunks • 847 words"),
                    ThinkingEvent(kind: .generation, title: "Generating response", detail: "Apple Intelligence • on-device"),
                ]
            }
        #endif
    }

    /// Seeds a comprehensive full demo for App Store screenshots
    /// Includes: polished conversation, thinking timeline, sources, metadata
    private func seedFullDemoContent() {
        // Thinking events - show the RAG pipeline in action
        thinkingEvents = [
            ThinkingEvent(kind: .planning, title: "Query analysis", detail: "Identified: roadmap + privacy request"),
            ThinkingEvent(kind: .queryRewrite, title: "Multi-query expansion", detail: "Generated 4 search variations"),
            ThinkingEvent(kind: .vectorSearch, title: "Semantic search", detail: "384-dim embeddings • cosine similarity"),
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
                "🧠 Synthesizing multi-source response with citations"
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
                All processing happens **on-device by default**. When additional compute is needed, Apple's Private Cloud Compute ensures your data never leaves Apple's secure enclaves.

                The hybrid search combines semantic understanding with keyword matching for accurate, grounded responses. [S1] [S2]
                """,
                metadata: demoMetadata,
                retrievedChunks: nil
            )
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
                snippet: "Privacy-first: Data stays on-device or Apple PCC. No third-party cloud. Secure enclave processing.",
                score: 0.88
            ),
            makeChunk(
                rank: 3,
                title: "Hybrid Search",
                page: 2,
                snippet: "Combines semantic embeddings with BM25 keyword matching. MMR ensures diverse, non-redundant results.",
                score: 0.84
            ),
        ]

        currentMetadata = demoMetadata
    }

    // MARK: - Active-container counts

    private func recalcActiveCounts() async {
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

    // MARK: - Send Message
    private var shouldShowFirstQueryHero: Bool {
        // Show the hero (with dynamic suggested questions) whenever the chat is empty —
        // not just before the first-ever query. hasAskedFirstQuery is an onboarding
        // completion flag, not a display gate. Gating on it permanently hides suggested
        // questions after the very first message the user ever sends.
        messages.isEmpty
    }

    /// Starter prompts - prefer curated sample-workspace questions, then dynamic questions.
    /// If a library does not yield grounded prompts yet, fail closed instead of inventing them.
    private var starterPrompts: [String] {
        if let sampleWorkspaceStarterPrompts = sampleWorkspaceStarterPrompts {
            return sampleWorkspaceStarterPrompts
        }

        // If we have dynamic questions based on library content, use them
        if !dynamicSuggestedQuestions.isEmpty {
            return dynamicSuggestedQuestions
        }

        // If no documents, show onboarding prompts
        if activeDocCount == 0 {
            return [
                "Import a document from the Documents tab to get started.",
                "What file types does OpenIntelligence handle best?",
                "How do answers stay tied to the source?",
                "When does processing stay on-device?"
            ]
        }

        return []
    }

    private var activeDocumentsForStarterPrompts: [Document] {
        let activeId = ragService.containerService.activeContainerId
        let defaultId = ragService.containerService.containers.first?.id

        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            }
            return activeId == defaultId
        }
    }

    private var sampleWorkspaceStarterPrompts: [String]? {
        let activeNames = Set(
            activeDocumentsForStarterPrompts.map {
                normalizeStarterWorkspaceDocumentName(starterDisplayDocumentName($0.filename))
            }
        )
        let sampleNames: Set<String> = [
            "openintelligence roadmap",
            "rag technical architecture",
            "apple intelligence & private cloud compute",
        ]

        guard activeNames.intersection(sampleNames).count >= 2 else { return nil }

        return [
            "How does OpenIntelligence work around the 4,096-token model limit?",
            "What file types does OpenIntelligence handle best?",
            "Why is OpenIntelligence different from a generic AI chat app?",
            "When does processing stay on-device, and when does Apple Private Cloud Compute step in?"
        ]
    }

    private func starterDisplayDocumentName(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeStarterWorkspaceDocumentName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate dynamic suggested questions based on library content
    private func refreshDynamicQuestions() {
        refreshSuggestedQuestions(force: false)
    }

    /// Generate suggested questions, optionally forcing a refresh (bypasses cache, avoids repeats)
    private func refreshSuggestedQuestions(force: Bool) {
        suggestedQuestionsTask?.cancel()
        if force {
            isRefreshingSuggestions = true
        }
        suggestedQuestionsTask = Task {
            defer {
                isRefreshingSuggestions = false
            }
            let containerId = ragService.containerService.activeContainerId

            // Get documents for the active container
            let documents = ragService.documents.filter { doc in
                if let docContainerId = doc.containerId {
                    return docContainerId == containerId
                }
                return containerId == ragService.containerService.containers.first?.id
            }

            guard !documents.isEmpty else {
                dynamicSuggestedQuestions = []
                dynamicQuestionCategories = [:]
                dynamicQuestionDetails = [:]
                return
            }

            // Scale the analysis sample with library size so large containers do not
            // collapse into vague, library-wide suggestions.
            do {
                let hasValidCache: Bool
                if force {
                    hasValidCache = false
                } else {
                    hasValidCache = await suggestedQuestionsService.hasValidCache(for: containerId, documentCount: documents.count)
                }

                let sampleChunks: [DocumentChunk]
                if hasValidCache {
                    sampleChunks = []
                } else {
                    let sampleLimit = min(max(documents.count * 4, 50), 160)
                    sampleChunks = try await ragService.getSampleChunks(for: containerId, limit: sampleLimit)
                }

                let questions = await suggestedQuestionsService.generateQuestions(
                    for: containerId,
                    documents: documents,
                    sampleChunks: sampleChunks,
                    count: 10,
                    forceRefresh: force
                )

                guard !Task.isCancelled else { return }

                // Verify we're still on the same container — prevents race where
                // a slow LLM generation from container A overwrites container B's state
                guard ragService.containerService.activeContainerId == containerId else {
                    Log.debug("[ChatScreen] Discarding stale questions for container \(containerId.uuidString.prefix(8)) — user switched")
                    return
                }

                dynamicSuggestedQuestions = questions.map { $0.text }
                dynamicQuestionCategories = Dictionary(
                    uniqueKeysWithValues: questions.map { ($0.text, $0.category) }
                )
                dynamicQuestionDetails = Dictionary(
                    uniqueKeysWithValues: questions.map { ($0.text, $0) }
                )
                Log.debug("[ChatScreen] Generated \(questions.count) dynamic suggested questions (force: \(force))")
            } catch {
                Log.warning("[ChatScreen] Failed to generate dynamic questions: \(error.localizedDescription)")
                dynamicSuggestedQuestions = []
                dynamicQuestionCategories = [:]
                dynamicQuestionDetails = [:]
            }
        }
    }

    private func persistChatHistory(for containerId: UUID?) {
        ragService.persistChatHistory(messages, for: containerId)
    }

    private func appendAndPersistMessage(_ message: ChatMessage, for containerId: UUID) {
        if ragService.containerService.activeContainerId == containerId {
            messages.append(message)
            persistChatHistory(for: containerId)
            return
        }

        var history = ragService.chatHistory(for: containerId)
        history.append(message)
        ragService.persistChatHistory(history, for: containerId)
    }

    private func newChat() {
        // Cancel any in-flight query task
        cancelInFlightQueryWork()
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil

        // Reset processing state
        if isProcessing {
            resetStreamingState()
            isProcessing = false
        }

        messages.removeAll()
        stage = .idle
        execution = .unknown
        ttft = nil
        generationStart = nil
        queryStart = nil
        embeddingStart = nil
        searchingStart = nil
        generatingStartTS = nil
        embeddingElapsedFinal = nil
        searchingElapsedFinal = nil
        generatingElapsedFinal = nil
        currentRetrievedChunks = []
        currentMetadata = nil
        currentStructuredAnswer = nil
        followUpSuggestions = []
        toastManager.clearAll()
        showRetrievedDetails = false
        thinkingEvents.removeAll()
        requestedExecutionContext = .automatic
        ragService.clearChatHistory(for: ragService.containerService.activeContainerId)
    }

    private func clearChat() {
        // Cancel any in-flight query task
        cancelInFlightQueryWork()
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil

        // Reset processing state
        if isProcessing {
            resetStreamingState()
            isProcessing = false
        }

        messages.removeAll()
        stage = .idle
        generationStart = nil
        queryStart = nil
        embeddingStart = nil
        searchingStart = nil
        generatingStartTS = nil
        embeddingElapsedFinal = nil
        searchingElapsedFinal = nil
        generatingElapsedFinal = nil
        currentRetrievedChunks = []
        currentMetadata = nil
        currentStructuredAnswer = nil
        followUpSuggestions = []
        toastManager.clearAll()
        showRetrievedDetails = false
        thinkingEvents.removeAll()
        requestedExecutionContext = .automatic
        ragService.clearChatHistory(for: ragService.containerService.activeContainerId)
    }

    /// Stops generation immediately and preserves partial response
    private func stopGeneration() {
        guard isProcessing else { return }

        // Cancel the running query task
        cancelInFlightQueryWork()

        // Flush any buffered text immediately
        flushStreamingBufferToVisibleText()

        // If we have partial text, save it as a message
        let sanitizedPartial = sanitizeFinalResponse(streamingText)
        if let partialContent = partialResponseMessageContent(
            sanitizedPartial: sanitizedPartial,
            userInitiatedStop: true
        ) {
            var partial = ChatMessage(
                role: .assistant,
                content: partialContent
            )
            partial.containerId = ragService.containerService.activeContainerId
            appendAndPersistMessage(partial, for: partial.containerId ?? ragService.containerService.activeContainerId)
        }

        // Reset all processing state
        resetStreamingState()
        isProcessing = false
        stage = .idle
        DSHaptics.selection()
    }

    /// Regenerates a response by finding the preceding user query
    private func regenerateResponse(for message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard !isProcessing else { return }

        // Find the user message that preceded this assistant response
        if let index = messages.firstIndex(where: { $0.id == message.id }),
           index > 0 {
            let previousMessage = messages[index - 1]
            if previousMessage.role == .user {
                // Remove the assistant response we're regenerating
                messages.remove(at: index)

                // Remove the user message too (sendMessage will re-add it)
                messages.remove(at: index - 1)

                // Re-send the query
                DSHaptics.selection()
                sendMessage(previousMessage.content)
            }
        }
    }

    /// Re-queries the last question using forced agentic (deep reasoning) mode.
    /// Called when user taps "Go Deeper" on a single-pass response.
    private func goDeeper() {
        guard !isProcessing else { return }

        DSHaptics.selection()
        cancelInFlightQueryWork()
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil
        followUpSuggestions = []

        // Show immediate feedback
        toastManager.show(
            ToastItem(
                title: "Diving deeper with multi-step reasoning...",
                icon: "brain",
                tint: .purple
            ),
            duration: 2.0
        )

        let querySessionId = UUID()
        currentQuerySessionId = querySessionId

        currentQueryTask = Task(priority: .userInitiated) { [weak ragService] in
            guard let capturedService = ragService else { return }

            defer {
                Task { @MainActor in
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.currentQuerySessionId = nil
                    self.currentQueryTask = nil
                    self.isProcessing = false
                    if self.stage == .searching || self.stage == .generating {
                        self.stage = .idle
                    }
                }
            }

            await MainActor.run {
                self.isProcessing = true
                self.stage = .searching
                self.resetStreamingState()
                let start = Date()
                self.queryStart = start
                self.nowTick = start
                self.generationStart = start
            }

            do {
                if let response = try await capturedService.reQueryWithAgenticMode(streamHandler: nil) {
                    await MainActor.run {
                        guard self.currentQuerySessionId == querySessionId else { return }
                        let containerId = capturedService.containerService.activeContainerId
                        // Add the deeper response as a new assistant message
                        var deeperMessage = ChatMessage(
                            role: .assistant,
                            content: sanitizeFinalResponse(response.generatedResponse),
                            metadata: response.metadata,
                            retrievedChunks: response.retrievedChunks,
                            structuredAnswer: response.structuredAnswer
                        )
                        deeperMessage.containerId = containerId
                        deeperMessage.thinkingEvents = self.thinkingEvents
                        self.appendAndPersistMessage(deeperMessage, for: containerId)

                        self.currentRetrievedChunks = response.retrievedChunks
                        self.currentMetadata = response.metadata
                        self.currentStructuredAnswer = response.structuredAnswer
                        if let start = self.queryStart {
                            self.generatingElapsedFinal = Date().timeIntervalSince(start)
                        }
                        self.resetStreamingState()
                        self.stage = .idle

                        DSHaptics.success()
                    }
                } else {
                    await MainActor.run {
                        guard self.currentQuerySessionId == querySessionId else { return }
                        toastManager.show(
                            ToastItem(
                                title: "No previous query to analyze deeper",
                                icon: "exclamationmark.triangle",
                                tint: .orange
                            ),
                            duration: 2.0
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.resetStreamingState()
                }
            } catch {
                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId else { return }
                    toastManager.show(
                        ToastItem(
                            title: "Deeper analysis failed: \(error.localizedDescription)",
                            icon: "xmark.circle",
                            tint: .red
                        ),
                        duration: 3.0
                    )
                    self.resetStreamingState()
                }
            }
        }
    }

    // MARK: - AI Hub Helpers

    /// Whether there are any assistant messages to operate on
    private var hasAssistantMessages: Bool {
        messages.contains { $0.role == .assistant }
    }

    /// Text content of the last assistant message (for Writing Tools / Image Playground)
    private var lastAssistantMessageText: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }

    /// Present Image Playground with enriched concepts from the last assistant response
    private func illustrateLastResponse() {
        guard let text = lastAssistantMessageText else { return }

        // Wire Image Playground pipeline events into the thinking stream
        ImagePlaygroundService.shared.onThinkingEvent = { event in
            Task { @MainActor in
                thinkingEvents.append(event)
            }
        }

        ImagePlaygroundService.shared.presentPlaygroundFromResponse(text)
    }

    // MARK: - Main Content Area

    @ViewBuilder private var mainContentArea: some View {
        VStack(spacing: 0) {
            CompactChatHeader(
                containerService: ragService.containerService,
                docCount: activeDocCount,
                chunkCount: activeChunkCount,
                ragService: ragService,
                messageContainerOverride: $messageContainerOverride,
                onMaximumModeBlocked: presentMaximumModePaywall
            )

            if let metricsData = consolidatedMetricsData {
                primaryMetricsBar(metricsData: metricsData)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: metricsData.tokens)
            } else if isProcessing || currentRetrievedChunks.count > 0 {
                minimalMetricsBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }

            chatContentArea
            followUpSuggestionsBar

            Divider().opacity(0.5)

            ChatComposerV2(
                isProcessing: isProcessing,
                onSend: sendMessage,
                onStop: stopGeneration,
                onAttach: nil,
                onSendWithAttachments: sendMessageWithAttachments,
                onVisionCapture: nil
            )
        }
    }

    @ViewBuilder private var chatContentArea: some View {
        if shouldShowFirstQueryHero {
            ScrollView {
                FirstQueryPromptView(
                    hasDocuments: activeDocCount > 0,
                    prompts: starterPrompts,
                    categories: dynamicQuestionCategories,
                    questionDetails: dynamicQuestionDetails,
                    libraryDocumentCount: activeDocCount,
                    isRefreshing: isRefreshingSuggestions,
                    onPromptSelected: sendSuggestedPrompt,
                    onRefresh: { refreshSuggestedQuestions(force: true) }
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
        } else {
            MessageListV2(
                messages: $messages,
                thinkingEvents: $thinkingEvents,
                streamingText: streamingText,
                isStreaming: isProcessing,
                qualityMode: effectiveQualityMode,
                generationStart: generationStart,
                onRegenerate: { message in regenerateResponse(for: message) },
                onGoDeeper: { goDeeper() },
                onThumbsUp: {
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, *) {
                        ragService.submitPositiveFeedback()
                    }
                    #endif
                    DSHaptics.success()
                    triggerThumbsUpReviewPrompt()
                },
                onThumbsDown: {
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, *) {
                        ragService.submitNegativeFeedback()
                    }
                    #endif
                    DSHaptics.warning()
                    showFeedbackEmailPrompt = true
                },
                onTranslate: { text in
                    translationText = text
                    showTranslation = true
                }
            )
        }
    }

    @ViewBuilder private var followUpSuggestionsBar: some View {
        if !followUpSuggestions.isEmpty && !isProcessing {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(followUpSuggestions) { suggestion in
                        Button {
                            DSHaptics.selection()
                            followUpSuggestions = []
                            sendMessage(suggestion.text)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: suggestion.category.iconName)
                                    .font(.caption2)
                                Text(suggestion.text)
                                    .font(.caption)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DSColors.surface)
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
            }
            .padding(.vertical, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: followUpSuggestions.isEmpty)
        }
    }

    @ViewBuilder private var writingToolsProgressOverlay: some View {
        if writingToolsProcessing {
            VStack(spacing: 12) {
                Spacer()
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("\(writingToolsTitle)…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial.opacity(0.95))
                .background(DSColors.accent.opacity(0.6))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: writingToolsProcessing)
        }
    }

    // MARK: - AI Hub Toolbar Button

    /// Extracted into its own @ViewBuilder to prevent type-checker timeout in body.
    @ViewBuilder private var aiHubToolbarButton: some View {
        Menu {
            Button {
                guard let text = lastAssistantMessageText else { return }
                performTransformAction(.keyFacts, on: text)
            } label: {
                Label("Key Facts", systemImage: "list.bullet.rectangle")
            }

            Button {
                guard let text = lastAssistantMessageText else { return }
                performTransformAction(.stepByStep, on: text)
            } label: {
                Label("Step-by-Step", systemImage: "checklist")
            }

            Button {
                guard let text = lastAssistantMessageText else { return }
                performTransformAction(.simplify, on: text)
            } label: {
                Label("Plain English", systemImage: "text.bubble")
            }

            Button {
                guard let text = lastAssistantMessageText else { return }
                let q = messages.last(where: { $0.role == .user })?.content ?? ""
                performTransformAction(.whatsMissing, on: text, question: q)
            } label: {
                Label("What's Missing?", systemImage: "questionmark.circle")
            }

            Button {
                illustrateLastResponse()
            } label: {
                Label("Illustrate", systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            Image(systemName: "apple.intelligence")
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hasAssistantMessages ? DSColors.accent : .secondary)
        }
        .disabled(!hasAssistantMessages || isProcessing || writingToolsProcessing)
    }

    // MARK: - WritingTools Actions

    // MARK: - Response Transform Actions (RAG-grounded)

    enum TransformAction {
        case keyFacts, stepByStep, simplify, whatsMissing

        var title: String {
            switch self {
            case .keyFacts: return "Key Facts"
            case .stepByStep: return "Step-by-Step"
            case .simplify: return "Plain English"
            case .whatsMissing: return "What's Missing?"
            }
        }

        var icon: String {
            switch self {
            case .keyFacts: return "list.bullet.rectangle"
            case .stepByStep: return "checklist"
            case .simplify: return "text.bubble"
            case .whatsMissing: return "questionmark.circle"
            }
        }
    }

    /// Transforms the last AI response using RAG-grounded context (source chunks + response).
    /// Each action receives the retrieved chunks so output is backed by the user's actual documents.
    private func performTransformAction(_ action: TransformAction, on text: String, question: String = "") {
        guard !writingToolsProcessing else { return }
        DSHaptics.selection()

        writingToolsProcessing = true
        writingToolsTitle = action.title

        // Capture the source chunks that backed this response
        let chunks = currentRetrievedChunks

        // Pre-warm the FM session — reduces first-token latency for the transform.
        // Fire-and-forget: best-effort, silently ignores errors.
        let prewarmService = ResponseTransformService()
        prewarmService.prewarmSession(responsePrefix: String(text.prefix(300)))

        Task {
            do {
                let service = ResponseTransformService()
                let result: String

                switch action {
                case .keyFacts:
                    result = try await service.keyFacts(response: text, chunks: chunks)
                case .stepByStep:
                    result = try await service.stepByStep(response: text, chunks: chunks)
                case .simplify:
                    result = try await service.simplify(response: text, chunks: chunks)
                case .whatsMissing:
                    result = try await service.whatsMissing(response: text, question: question, chunks: chunks)
                }

                await MainActor.run {
                    writingToolsResult = result
                    showWritingToolsResult = true
                    writingToolsProcessing = false
                    DSHaptics.success()
                }
            } catch {
                await MainActor.run {
                    writingToolsProcessing = false
                    let errorMsg = error.localizedDescription
                    let isRateLimit = errorMsg.lowercased().contains("rate") || errorMsg.lowercased().contains("limit")

                    toastManager.show(
                        ToastItem(
                            title: isRateLimit
                                ? "\(action.title) rate-limited — try again"
                                : "\(action.title) failed — try again",
                            icon: "exclamationmark.triangle",
                            tint: .orange
                        ),
                        duration: 4.0
                    )
                }
            }
        }
    }

    // MARK: - Attachment Handling

    /// Combined send: process attachments FIRST, wait for completion, THEN send query
    /// This ensures documents are indexed before the RAG query runs
    private func sendMessageWithAttachments(_ query: String, _ urls: [URL]) {
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
                            title: "Added \(successCount) \(successCount == 1 ? "document" : "documents") • Querying...",
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

    private func sendMessage(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        reviewPromptTask?.cancel()
        reviewPromptTask = nil

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
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
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
        // Reset override after one use
        self.messageContainerOverride = nil

        // Reset and start processing
        isProcessing = true
        stage = .embedding
        let processingStart = Date()
        queryStart = processingStart
        nowTick = processingStart
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
        let capturedFrequencyPenalty = frequencyPenalty
        let capturedPresencePenalty = presencePenalty
        let capturedRepetitionPenalty = repetitionPenalty
        let capturedSystemPrompt = systemPrompt
        let capturedContextLength = contextLength
        let baseExecutionContext = settings.executionContext
        let capturedExecutionContext: ExecutionContext =
            baseExecutionContext == .automatic ? .preferCloud : baseExecutionContext
        let capturedAllowPCC = baseExecutionContext != .onDeviceOnly
        let capturedQualityMode = effectiveQualityMode.canonical
        let capturedFmPreference = settings.fmPreference
        requestedExecutionContext = capturedExecutionContext
        let capturedUsedContainerId = usedContainerId
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
                    // StatusPillV2 shows stage - no toast needed
                    DSHaptics.processingPulse() // Feel the pipeline starting
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
                    // StatusPillV2 shows stage - no toast needed
                    DSHaptics.processingPulse() // Feel the search starting
                }

                let config = InferenceConfig(
                    maxTokens: capturedMaxTokens,
                    temperature: Float(capturedTemperature),
                    topP: Float(capturedTopP),
                    topK: 40,
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

                let queryStreamHandler: LLMStreamHandler?
                if capturedQualityMode == .standard {
                    queryStreamHandler = { event in
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
                } else {
                    queryStreamHandler = nil
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
                    // StatusPillV2 shows stage - no toast needed
                    DSHaptics.messageReceived() // Feel the response starting
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

                    if let genStart = self.generatingStartTS {
                        self.generatingElapsedFinal = Date().timeIntervalSince(genStart)
                    }

                    if self.ragService.containerService.activeContainerId == capturedUsedContainerId {
                        self.stage = .complete

                        // Show completion toast with token count
                        let tokenCount = response.metadata.tokensGenerated
                        self.toastManager.clearAll()
                        self.pushToast(
                            tokenCount > 0 ? "Done • \(tokenCount) tokens" : "Complete",
                            icon: "checkmark.circle.fill",
                            tint: .green
                        )

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

                        self.scheduleReviewPromptIfEligible(
                            response: response,
                            renderedResponse: assistant.content,
                            qualityMode: capturedQualityMode
                        )
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

                    if case let RAGServiceError.maximumModeQuotaReached(limit) = error {
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

    private func sendSuggestedPrompt(_ prompt: String) {
        DSHaptics.selection()
        sendMessage(prompt)
    }

    private var canPresentScheduledReviewPrompt: Bool {
        #if DEBUG
        if didSeedScreenshotDemo {
            return false
        }
        #endif

        return scenePhase == .active
            && !isProcessing
            && currentQueryTask == nil
            && activeCloudConsent == nil
            && !showRetrievedDetails
            && !showPlanSheet
            && !showVisionCapture
                && !writingToolsProcessing
            && !showWritingToolsResult
            && !showTranslation
            && !showMaximumModeLimitDialog
            && !showFriendlyReviewPrompt
    }

    private func scheduleReviewPromptIfEligible(
        response: RAGResponse,
        renderedResponse: String,
        qualityMode: RAGQualityMode
    ) {
        guard AppReviewPromptTracker.registerSuccessfulAnswer(
            qualityMode: qualityMode,
            retrievedChunkCount: response.retrievedChunks.count,
            responseLength: renderedResponse.count
        ) else { return }

        reviewPromptTask?.cancel()
        reviewPromptTask = Task { @MainActor in
            defer { reviewPromptTask = nil }

            try? await Task.sleep(nanoseconds: AppReviewPromptPolicy.promptDelayNanoseconds)
            guard !Task.isCancelled, canPresentScheduledReviewPrompt else { return }

            AppReviewPromptTracker.markPromptAttempted()
            showFriendlyReviewPrompt = true
        }
    }

    private func triggerThumbsUpReviewPrompt() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard !currentVersion.isEmpty else { return }

        let lastPrompted = UserDefaults.standard.string(forKey: "appReview.lastPromptedVersion")
        if lastPrompted == currentVersion { return }

        if let lastPromptAttemptedAt = UserDefaults.standard.object(forKey: "appReview.lastPromptAttemptedAt") as? Date,
           Date().timeIntervalSince(lastPromptAttemptedAt) < AppReviewPromptPolicy.minimumPromptCooldown {
            return
        }

        AppReviewPromptTracker.markPromptAttempted()
        showFriendlyReviewPrompt = true
    }

    private func presentMaximumModePaywall() {
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

    private func pushToast(_ title: String, icon: String, tint: Color) {
        let toast = ToastItem(title: title, icon: icon, tint: tint)
        toastManager.show(toast, duration: 2.0)
    }

    // MARK: - Streaming Cadence Helpers

    /// Clears any live streaming UI/buffer state (used before/after each query and on cancel).
    private func resetStreamingState() {
        streamingPumpTask?.cancel()
        streamingPumpTask = nil
        streamingBuffer.removeAll(keepingCapacity: true)
        streamingText = ""
        hasReceivedStreamToken = false
        isStreamFinished = false
    }

    private func cancelInFlightQueryWork(resetLLMSession: Bool = true) {
        continuedQueryCoordinator.cancelCurrentQuery()
        currentQuerySessionId = nil
        currentQueryTask?.cancel()
        currentQueryTask = nil
        queryStart = nil
        ragService.cancelActiveGeneration(resetSession: resetLLMSession)
    }

    /// Queues incoming streamed text and starts the drip pump when idle.
    private func enqueueStreamingText(_ incoming: String) {
        guard
            let sanitized = sanitizeStreamChunk(
                incoming,
                isFirstChunk: !hasReceivedStreamToken
            ), !sanitized.isEmpty
        else { return }
        streamingBuffer.append(sanitized)
        hasReceivedStreamToken = true
        if streamingPumpTask == nil {
            streamingPumpTask = Task { await pumpStreamingBuffer() }
        }
    }

    /// Forces any buffered characters to render immediately (typically when the stream closes).
    private func flushStreamingBufferToVisibleText() {
        streamingPumpTask?.cancel()
        streamingPumpTask = nil
        guard !streamingBuffer.isEmpty else { return }
        streamingText.append(streamingBuffer)
        streamingBuffer.removeAll(keepingCapacity: true)
    }

    /// Drips buffered characters into the visible text at a steady cadence to avoid bursty dumps.
    @MainActor
    private func pumpStreamingBuffer(chunkSize: Int = 50, cadence: UInt64 = 80_000_000) async {
        defer { streamingPumpTask = nil }
        while !Task.isCancelled {
            guard !streamingBuffer.isEmpty else { return }
            let backlog = streamingBuffer.count
            let adaptiveChunkSize: Int
            let adaptiveCadence: UInt64

            if backlog > 1200 {
                adaptiveChunkSize = max(120, chunkSize)
                adaptiveCadence = 40_000_000
            } else if backlog > 400 {
                adaptiveChunkSize = max(80, chunkSize)
                adaptiveCadence = 60_000_000
            } else {
                adaptiveChunkSize = isStreamFinished ? max(100, chunkSize) : chunkSize
                adaptiveCadence = isStreamFinished ? 20_000_000 : cadence
            }

            let takeCount = min(adaptiveChunkSize, streamingBuffer.count)
            let nextChunk = String(streamingBuffer.prefix(takeCount))
            streamingBuffer.removeFirst(takeCount)

            // Force immediate UI update with explicit animation
            withAnimation(.linear(duration: 0.04)) {
                streamingText.append(nextChunk)
            }

            // Update speed history for the sparkline
            updateSpeedHistory()

            do {
                try await Task.sleep(nanoseconds: adaptiveCadence)
            } catch {
                return
            }
        }
    }

    /// Cleans streamed chunks before they reach the UI, stripping stray control characters and the recurring "null" artifact reported in the stream gutter.
    private func sanitizeStreamChunk(_ chunk: String, isFirstChunk: Bool) -> String? {
        guard !chunk.isEmpty else { return nil }

        // Remove null scalars and non-printable control characters while preserving whitespace/newlines for Markdown layout.
        var cleaned = chunk.replacingOccurrences(of: "\u{0000}", with: "")
        let disallowedControls = CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines)
        if cleaned.rangeOfCharacter(from: disallowedControls) != nil {
            cleaned = cleaned.components(separatedBy: disallowedControls).joined()
        }

        guard !cleaned.isEmpty else { return nil }

        // On the first chunk, strip common malformed prefixes that appear from certain LLM streams
        if isFirstChunk {
            // Pattern matches: "null", "(null)", "null -", "null:", "null\n", etc.
            if let range = cleaned.range(
                of: #"^\s*(?:\(null\)|null)[\s\-–—:]*"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let removed = cleaned[range]
                cleaned = String(cleaned[range.upperBound...])
                let prefixSample = removed.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefixSample.isEmpty {
                    Log.warning(
                        "Dropped malformed stream prefix: \(prefixSample)",
                        category: .streaming
                    )
                    TelemetryCenter.emit(
                        .system,
                        severity: .warning,
                        title: "Trimmed malformed stream prefix",
                        metadata: ["prefix": prefixSample]
                    )
                }
            }
        }

        // Also strip standalone "null" if the entire chunk is just "null"
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "null" {
            Log.debug("Dropped standalone 'null' chunk", category: .streaming)
            return nil
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Sanitizes the final response text before displaying in message bubble.
    /// Strips leading "null" artifacts and other malformed prefixes.
    private func sanitizeFinalResponse(_ text: String) -> String {
        var cleaned = text

        // Strip leading "null" or "(null)" with optional separator
        if let range = cleaned.range(
            of: #"^\s*(?:\(null\)|null)[\s\-–—:]*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let removed = cleaned[range]
            cleaned = String(cleaned[range.upperBound...])
            let prefixSample = removed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefixSample.isEmpty {
                Log.warning("Stripped malformed response prefix: \(prefixSample)", category: .llm)
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the text to persist for an interrupted response.
    /// Strong partial answers are kept as-is; weak fragments stay visibly marked as partial.
    private func partialResponseMessageContent(
        sanitizedPartial: String,
        failureMessage: String? = nil,
        userInitiatedStop: Bool = false
    ) -> String? {
        let cleaned = sanitizedPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if userInitiatedStop || shouldKeepPartialResponseAsAnswer(cleaned) {
            return cleaned
        }

        guard let failureMessage, !failureMessage.isEmpty else {
            return cleaned + "\n\n*(Partial answer)*"
        }

        return cleaned + "\n\n*(Partial answer. \(failureMessage))*"
    }

    /// Heuristic for deciding whether an interrupted response is already useful enough
    /// to keep without an inline failure footer.
    private func shouldKeepPartialResponseAsAnswer(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 180 else { return false }

        let hasCitations = trimmed.range(of: #"\[S\d+\]"#, options: .regularExpression) != nil
        if hasCitations { return true }

        let sentenceCount = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
            .count

        if sentenceCount >= 4 { return true }
        if sentenceCount >= 3 && trimmed.count >= 240 { return true }

        let hasStructuredLayout = trimmed.contains("\n### ") ||
            trimmed.contains("\n## ") ||
            trimmed.contains("\n- ") ||
            trimmed.contains("\n1. ")

        return hasStructuredLayout && sentenceCount >= 2 && trimmed.count >= 220
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        if error is CancellationError {
            return "Generation canceled."
        }

        if let ragError = error as? RAGServiceError {
            switch ragError {
            case .emptyQuery:
                return "Type a question to get started."
            case .noDocumentsAvailable:
                return "No documents yet. Add files to enable grounded answers."
            case .noRelevantContext:
                return "I couldn't find relevant info in your library. Try rephrasing."
            case .retrievalFailed:
                return "Retrieval failed. Please try again."
            case .modelNotAvailable:
                return "The selected model isn't available right now."
            case let .maximumModeQuotaReached(limit):
                return "Maximum is capped at \(limit) uses per day on Free. Switch modes or upgrade for unlimited Maximum."
            case .cloudConsentDenied:
                return "Cloud processing was declined. Switch to on-device or try again."
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "You're offline. Reconnect and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return "Network error. Please try again."
            }
        }

        // Handle LLM-specific errors
        if let llmError = error as? LLMError {
            switch llmError {
            case .contextWindowExceeded:
                return "Deep Think ran too long. Try Standard mode or a shorter question."
            case .generationFailed(let message):
                if message.contains("decode") || message.contains("internal") {
                    return "AI processing limit reached. Try Standard mode instead."
                }
                return message
            case .modelUnavailable:
                return "Apple Intelligence isn't available. Enable it in Settings."
            case .notImplemented:
                return "This feature isn't available yet."
            case .rateLimited:
                return "AI is temporarily busy. Please wait a moment and try again."
            case .concurrentRequests:
                return "A request is already in progress. Please wait for it to finish."
            }
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("exceededcontextwindowsize") {
            return "Deep Think ran too long. Try Standard mode or a shorter question."
        }
        if message.contains("decode") || message.contains("json") {
            return "AI processing limit reached. Try Standard mode instead."
        }

        return "Something went wrong. Please try again."
    }
}

// MARK: - Header

struct ChatHeader: View {
    let onNewChat: () -> Void
    let onClearChat: () -> Void
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Chat")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()

            Menu {
                Button {
                    onNewChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                Button(role: .destructive) {
                    onClearChat()
                } label: {
                    Label("Clear Chat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Context / Status Bar

struct ContextStatusBarView: View {
    let docCount: Int
    let chunkCount: Int
    let usedK: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.caption2)
                .foregroundColor(.green)

            Text("\(docCount) document\(docCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("•")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("\(chunkCount) chunks")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Text("k used: \(usedK)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.05))
    }
}

// MARK: - Compact Chat Header V2

/// Modern, minimal header with inline container picker strip, model status, and document stats
struct CompactChatHeader: View {
    @ObservedObject var containerService: ContainerService
    @EnvironmentObject private var settings: SettingsStore
    let docCount: Int
    let chunkCount: Int
    let ragService: RAGService
    @Binding var messageContainerOverride: UUID?
    var onMaximumModeBlocked: (() -> Void)? = nil

    @State private var showModelDetails = false
    @State private var deviceCapabilities = DeviceCapabilities()

    private var activeContainer: KnowledgeContainer? {
        containerService.activeContainer
    }

    var body: some View {
        VStack(spacing: 10) {
            // Top row: Library picker strip (scrollable)
            libraryPickerStrip

            // Bottom row: Model status + Quality mode picker + Stats
            HStack(spacing: 10) {
                // Always show quality mode picker - Deep Think is useful for all users
                QualityModeQuickPicker(selectedMode: $settings.ragQualityMode, onMaximumModeBlocked: onMaximumModeBlocked) { _, _ in
                    // Reset stale Deep Think/Maximum metrics when mode changes
                    ragService.resetDeepThinkLiveMetrics()
                }

                // Model indicator (compact)
                ModelStatusIndicator()

                Spacer()

                // Stats for active container
                HStack(spacing: 8) {
                    StatChip(icon: "doc.fill", value: "\(docCount)", color: .blue)
                    StatChip(icon: "square.grid.3x3.fill", value: "\(chunkCount)", color: .purple)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
.onAppear {
    deviceCapabilities = RAGService.checkDeviceCapabilities()
}
    }

    // MARK: - Library Picker Strip

    private var libraryPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        libraryPillList
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                HStack(spacing: 8) {
                    libraryPillList
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var libraryPillList: some View {
        ForEach(containerService.containers) { container in
            ContainerPill(
                container: container,
                isSelected: containerService.activeContainerId == container.id,
                canDelete: false,
                badgeText: documentCountText(for: container),
                badgeStyle: .count
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    containerService.setActive(container.id)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func documentCountText(for container: KnowledgeContainer) -> String? {
        let count = containerService.documentCount(for: container.id)
        return count > 0 ? "\(count)" : nil
    }
}

/// Quick picker for quality mode - shows in chat header
/// Dropdown menu to switch between Standard and Deep Think
struct QualityModeQuickPicker: View {
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Binding var selectedMode: RAGQualityMode
    var onMaximumModeBlocked: (() -> Void)? = nil
    /// Called when mode changes, passing old and new mode
    var onModeChange: ((RAGQualityMode, RAGQualityMode) -> Void)?

    var body: some View {
        Menu {
            ForEach(RAGQualityMode.userVisibleCases, id: \.id) { mode in
                Button {
                    guard canSelect(mode) else { return }
                    let previousMode = selectedMode
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedMode = mode
                    }
                    DSHaptics.selection()

                    // Notify parent to reset stale metrics when mode changes
                    if previousMode.canonical != mode.canonical {
                        onModeChange?(previousMode, mode)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: mode.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(modeColor.opacity(0.14))
                        .frame(width: 20, height: 20)
                    Image(systemName: selectedMode.canonical.icon)
                        .font(.system(size: 10, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedMode.canonical.displayName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(modeTagline)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(modeColor.opacity(0.85))
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(modeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(modeColor.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(modeColor.opacity(0.22), lineWidth: 1)
                    )
            )
        }
    }

    private var modeTagline: String {
        switch selectedMode.canonical {
        case .standard: return "Fastest"
        case .deepThink: return "Iterative"
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return "Unlimited"
            }
            return "\(entitlementStore.maximumModeRemainingUses) left"
        default: return "Fastest"
        }
    }

    private var modeColor: Color {
        switch selectedMode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .blue
        }
    }

    private func canSelect(_ mode: RAGQualityMode) -> Bool {
        guard mode.canonical == .maximum else { return true }
        guard entitlementStore.canUseMaximumModeNow else {
            onMaximumModeBlocked?()
            return false
        }
        return true
    }
}

/// Reliability-first indicator (shown when advanced tuning is disabled).
struct AccuracyModeBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Reliability First")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.12))
        )
    }
}

/// Small stat chip for header
private struct StatChip: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Optional Placeholder (not used, kept for reference)

struct MessageListEmptyContent: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.15), .blue.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 8) {
                    Text("New Chat UI (V2)")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(
                        "A modern, modular interface is being enabled behind a feature flag. This is the initial scaffold."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ChatV2FeatureRow(
                        icon: "brain.head.profile", title: "Semantic Search",
                        description: "Context-aware retrieval from your documents.")
                    ChatV2FeatureRow(
                        icon: "sparkles", title: "AI Generation",
                        description: "Grounded answers with clear citations.")
                    ChatV2FeatureRow(
                        icon: "lock.shield", title: "Privacy First",
                        description: "On-Device or Private Cloud Compute.")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - First-Query Guidance

private struct FirstQueryPromptView: View {
    let hasDocuments: Bool
    let prompts: [String]
    let categories: [String: SuggestedQuestionsService.QuestionCategory]
    let questionDetails: [String: SuggestedQuestionsService.SuggestedQuestion]
    let libraryDocumentCount: Int
    let isRefreshing: Bool
    let onPromptSelected: (String) -> Void
    let onRefresh: () -> Void

    private var sourceDocumentCount: Int {
        Set(questionDetails.values.flatMap(\.relevantDocuments)).count
    }

    private var headerText: String {
        hasDocuments ? "What would you like to know?" : "Get started"
    }

    private var supportingText: String {
        guard hasDocuments else {
            return "Import documents from the Documents tab, then try one of these prompts."
        }

        guard !prompts.isEmpty else {
            return "No grounded suggestions are ready yet. Ask about a specific warning, requirement, step, setting, or value in this library."
        }

        guard !questionDetails.isEmpty else {
            return "Suggestions are generated from specific passages in this library."
        }

        if libraryDocumentCount > sourceDocumentCount && sourceDocumentCount > 0 {
            return "This batch is pulled from \(sourceDocumentCount) of \(libraryDocumentCount) docs in this library. Refresh for a different slice."
        }

        return "Suggestions are generated from specific passages in this library."
    }

    private func sourceLine(for prompt: String) -> String? {
        guard let detail = questionDetails[prompt],
              let primaryDoc = detail.relevantDocuments.first
        else {
            return nil
        }

        let extraDocCount = max(0, detail.relevantDocuments.count - 1)
        let section = detail.sourceSections.first?.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = [primaryDoc]
        if let section, !section.isEmpty {
            parts.append(section)
        }
        if extraDocCount > 0 {
            parts.append("+\(extraDocCount) more")
        }

        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DSColors.accent, DSColors.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: DSColors.accent.opacity(0.3), radius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headerText)
                        .font(DSTypography.title)
                        .foregroundStyle(DSColors.primaryText)

                    Text(supportingText)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if hasDocuments {
                    Button {
                        DSHaptics.selection()
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DSColors.accent)
                            .padding(8)
                            .background(DSColors.accent.opacity(0.1))
                            .clipShape(Circle())
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: isRefreshing
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh suggestions")
                }
            }

            if !prompts.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            onPromptSelected(prompt)
                        } label: {
                            HStack(spacing: DSSpacing.md) {
                                if let category = categories[prompt] {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle()
                                                .fill(DSColors.accent.gradient)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prompt)
                                        .font(DSTypography.body.weight(.medium))
                                        .foregroundStyle(DSColors.primaryText)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if let source = sourceLine(for: prompt) {
                                        Text(source)
                                            .font(DSTypography.meta)
                                            .foregroundStyle(DSColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: DSSpacing.sm)

                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(DSColors.accent)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .padding(DSSpacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background {
                            if #available(iOS 26.0, *) {
                                Color.clear
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                                    .fill(DSColors.surface)
                                    .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                            }
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                    .fill(DSColors.surfaceElevated)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .strokeBorder(DSColors.accent.opacity(0.1), lineWidth: 1)
        }
    }
}

struct ChatV2FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Composer Placeholder (legacy stub, not used in flow)

struct ComposerStub: View {
    @State private var text: String = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message AI...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DSColors.surface)
                )

            Button {
                // Send (disabled in scaffold)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 36, height: 36)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .disabled(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DSColors.background)
    }
}

private enum AppReviewPromptPolicy {
    static let minimumSuccessfulAnswers = 3
    static let minimumDistinctUsageDays = 2
    static let minimumPromptCooldown: TimeInterval = 14 * 24 * 60 * 60
    static let minimumMeaningfulResponseCharacters = 120
    static let minimumRetrievedSources = 1
    static let promptDelayNanoseconds: UInt64 = 4_000_000_000
}

private enum AppReviewPromptTracker {
    private enum Keys {
        static let successfulAnswerCount = "appReview.successfulAnswerCount"
        static let distinctUsageDays = "appReview.distinctUsageDays"
        static let hasCompletedHighEffortAnswer = "appReview.hasCompletedHighEffortAnswer"
        static let lastPromptedVersion = "appReview.lastPromptedVersion"
        static let lastPromptAttemptedAt = "appReview.lastPromptAttemptedAt"
    }

    private static let defaults = UserDefaults.standard
    private static let calendar = Calendar.autoupdatingCurrent

    static func registerSuccessfulAnswer(
        qualityMode: RAGQualityMode,
        retrievedChunkCount: Int,
        responseLength: Int,
        now: Date = Date()
    ) -> Bool {
        guard retrievedChunkCount >= AppReviewPromptPolicy.minimumRetrievedSources,
              responseLength >= AppReviewPromptPolicy.minimumMeaningfulResponseCharacters
        else {
            return false
        }

        let currentVersion = currentAppVersion
        guard !currentVersion.isEmpty else { return false }
        guard defaults.string(forKey: Keys.lastPromptedVersion) != currentVersion else { return false }

        if let lastPromptAttemptedAt = defaults.object(forKey: Keys.lastPromptAttemptedAt) as? Date,
           now.timeIntervalSince(lastPromptAttemptedAt) < AppReviewPromptPolicy.minimumPromptCooldown {
            return false
        }

        defaults.set(defaults.integer(forKey: Keys.successfulAnswerCount) + 1, forKey: Keys.successfulAnswerCount)

        if qualityMode.qualifiesForReviewAcceleration {
            defaults.set(true, forKey: Keys.hasCompletedHighEffortAnswer)
        }

        storeDistinctUsageDay(now)

        let successfulAnswerCount = defaults.integer(forKey: Keys.successfulAnswerCount)
        guard successfulAnswerCount >= AppReviewPromptPolicy.minimumSuccessfulAnswers else {
            return false
        }

        let distinctUsageDayCount = (defaults.array(forKey: Keys.distinctUsageDays) as? [String] ?? []).count
        let hasCompletedHighEffortAnswer = defaults.bool(forKey: Keys.hasCompletedHighEffortAnswer)

        return distinctUsageDayCount >= AppReviewPromptPolicy.minimumDistinctUsageDays
            || hasCompletedHighEffortAnswer
    }

    static func markPromptAttempted(now: Date = Date()) {
        let currentVersion = currentAppVersion
        guard !currentVersion.isEmpty else { return }

        defaults.set(currentVersion, forKey: Keys.lastPromptedVersion)
        defaults.set(now, forKey: Keys.lastPromptAttemptedAt)
    }

    private static func storeDistinctUsageDay(_ date: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        let dayKey = String(Int(startOfDay.timeIntervalSince1970))
        var storedDays = defaults.array(forKey: Keys.distinctUsageDays) as? [String] ?? []

        if !storedDays.contains(dayKey) {
            storedDays.append(dayKey)
            storedDays = Array(storedDays.suffix(14))
            defaults.set(storedDays, forKey: Keys.distinctUsageDays)
        }
    }

    private static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

private extension RAGQualityMode {
    var qualifiesForReviewAcceleration: Bool {
        switch canonical {
        case .deepThink, .maximum:
            return true
        default:
            return false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ChatScreen(ragService: RAGService())
    }
    #if os(iOS)
        .navigationViewStyle(.stack)
    #endif
}

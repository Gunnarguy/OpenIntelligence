//
//  ChatScreen.swift
//  OpenIntelligence
//
//  Created by Cline on 10/28/25.
//

import Combine
import Foundation
import SwiftUI

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

// ChatV2 entry point (feature-flagged from ContentView)
@MainActor
struct ChatScreen: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var ragService: RAGService
    @AppStorage("retrievalTopK") private var retrievalTopK: Int = 3
    @State private var showScrollToBottom: Bool = false
    @State private var messages: [ChatMessage] = []
    @State private var didSeedScreenshotDemo: Bool = false
    @State private var streamingText: String = ""
    @State private var streamingBuffer: String = ""
    @State private var streamingPumpTask: Task<Void, Never>? = nil
    @State private var currentQueryTask: Task<Void, Never>? = nil // Track current query for cancellation
    @State private var hasReceivedStreamToken: Bool = false
    @State private var generationStart: Date? = nil
    // Per-stage timing
    @State private var embeddingStart: Date? = nil
    @State private var searchingStart: Date? = nil
    @State private var generatingStartTS: Date? = nil
    @State private var embeddingElapsedFinal: TimeInterval? = nil
    @State private var searchingElapsedFinal: TimeInterval? = nil
    @State private var generatingElapsedFinal: TimeInterval? = nil
    // Live clock tick to drive elapsed UI
    @State private var nowTick: Date = Date()
    @State private var processingClock = Timer.publish(every: 0.2, on: .main, in: .common)
        .autoconnect()
    // Ephemeral UI and retrieval
    @StateObject private var toastManager = ToastManager()
    @State private var currentRetrievedChunks: [RetrievedChunk] = []
    @State private var currentMetadata: ResponseMetadata? = nil
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

    // Speed history for sparkline graph
    @State private var speedHistory: [Double] = []
    @State private var lastSpeedSampleTokens: Int = 0
    @State private var lastSpeedSampleTime: Date = .init()
    @State private var lastSemanticQuery: String? = nil

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

    var body: some View {
        ZStack(alignment: .top) {
            // Main content VStack
            VStack(spacing: 0) {
                // Compact header with container, model status, and stats
                CompactChatHeader(
                    containerService: ragService.containerService,
                    docCount: activeDocCount,
                    chunkCount: activeChunkCount,
                    ragService: ragService,
                    messageContainerOverride: $messageContainerOverride
                )

                // UNIFIED METRICS BAR - The ONE bar to rule them all
                // Shows execution location, context usage, generation speed, sources, quality mode
                // Visible during processing and persists after completion
                if let metricsData = consolidatedMetricsData {
                    // For Deep Think, use live token counter during processing, final count after
                    let deepThinkTokens = isProcessing ? ragService.deepThinkLiveTokens : (ragService.lastAuditSnapshot?.totalTokensAcrossCalls ?? ragService.deepThinkLiveTokens)
                    let audit = ragService.lastAuditSnapshot

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
                        // Query understanding
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
                        // Full Transparency Dashboard data from audit snapshot
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
                        onTapDetails: !metricsData.isStreaming ? { showRetrievedDetails = true } : nil
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: metricsData.tokens)
                } else if isProcessing || currentRetrievedChunks.count > 0 {
                    // Show minimal bar when processing starts (before generating)
                    let auditSnapshot = ragService.lastAuditSnapshot
                    let minimalVectorWt = Double(auditSnapshot?.retrievalConfig.vectorWeight ?? 0.6)
                    let minimalLexicalWt = Double(auditSnapshot?.retrievalConfig.lexicalWeight ?? 0.4)
                    UnifiedMetricsBar(
                        stage: stage,
                        execution: execution,
                        isProcessing: isProcessing,
                        qualityMode: effectiveQualityMode,
                        isLLMActivelyGenerating: ragService.isLLMResponding,
                        contextTokens: auditSnapshot?.isRecursiveRAG == true ? (auditSnapshot?.totalTokensAcrossCalls ?? actualContextTokensUsed) : actualContextTokensUsed,
                        maxContextTokens: maxContextTokensForUI,
                        tokensGenerated: 0,
                        tokensPerSecond: 0,
                        characterCount: 0,
                        elapsedTime: 0,
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
                        // Full Transparency Dashboard data from audit snapshot
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
                        onTapDetails: nil
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }

                // Main content area
                if shouldShowFirstQueryHero {
                    FirstQueryPromptView(
                        hasDocuments: activeDocCount > 0,
                        prompts: starterPrompts,
                        onPromptSelected: sendSuggestedPrompt
                    )
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.md)
                } else {
                    MessageListV2(
                        messages: $messages,
                        streamingText: streamingText,
                        isStreaming: isProcessing,
                        generationStart: generationStart,
                        onRegenerate: { message in
                            regenerateResponse(for: message)
                        },
                        onGoDeeper: {
                            goDeeper()
                        },
                        onThumbsUp: {
                                #if canImport(FoundationModels)
                                    if #available(iOS 26.0, *) {
                                        ragService.submitPositiveFeedback()
                                        DSHaptics.success()
                                    }
                                #endif
                            },
                        onThumbsDown: {
                                #if canImport(FoundationModels)
                                    if #available(iOS 26.0, *) {
                                        ragService.submitNegativeFeedback()
                                        DSHaptics.warning()
                                    }
                                #endif
                        }
                    )
                }

                // NOTE: Sources are shown inline in MessageBubbleV2 for completed messages.
                // The RetrievalSourcesTray is removed to avoid duplication.
                // Status is now handled by UnifiedMetricsBar above

                // Collapsible thinking stream (already compact)
                if !thinkingEvents.isEmpty {
                    ThinkingStreamView(events: thinkingEvents)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.bottom, DSSpacing.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider()
                    .opacity(0.5)

                // Modern composer with stop button support and attachments
                // Uses combined send to ensure attachments are processed BEFORE query
                ChatComposerV2(
                    isProcessing: isProcessing,
                    onSend: sendMessage,
                    onStop: stopGeneration,
                    onSendWithAttachments: sendMessageWithAttachments
                )
            }

            // Toast overlay (appears above everything) - minimal use
            ToastStackView(items: toastManager.toasts, maxVisible: 1)
                .padding(.top, 60) // Below nav bar

            IngestionQueueOverlay(items: ragService.ingestionItems)
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
.navigationTitle("Chat")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(processingClock) { _ in
            if isProcessing {
                nowTick = Date()
            }
        }
        // Recalculate counts when active container changes
        .task(id: ragService.containerService.activeContainerId) {
            // Don't load persisted history in screenshot demo mode - let seedFullDemoContent() handle it
            #if DEBUG
            if didSeedScreenshotDemo { return }
            #endif
            let activeId = ragService.containerService.activeContainerId
            messages = ragService.chatHistory(for: activeId)
            await recalcActiveCounts()
        }
        // React to document ingestion/removal immediately
        .onReceive(ragService.$documents) { _ in
            Task { await recalcActiveCounts() }
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
                    retrievedChunks: currentRetrievedChunks
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
        .sheet(item: $activeCloudConsent) { record in
            CloudConsentPromptView(record: record) { decision in
                Task { await ragService.resolveCloudConsent(decision: decision) }
            }
            .interactiveDismissDisabled(true)
#if os(iOS)
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
            .presentationBackground(.ultraThinMaterial)
#endif
        }
.onAppear {
    // Seed screenshot demo FIRST before loading persisted history
    seedScreenshotDemoIfNeeded()

    // Only load persisted history if not in screenshot demo mode
    #if DEBUG
    if !didSeedScreenshotDemo {
        let activeId = ragService.containerService.activeContainerId
        messages = ragService.chatHistory(for: activeId)
    }
    #else
    let activeId = ragService.containerService.activeContainerId
    messages = ragService.chatHistory(for: activeId)
    #endif
}
    }

    private var streamingTokensApprox: Int {
        streamingText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var streamingElapsedTime: TimeInterval {
        guard let start = generationStart else { return 0 }
        return max(0, nowTick.timeIntervalSince(start))
    }

    private var streamingTokensPerSecond: Double {
        let elapsed = streamingElapsedTime
        guard elapsed > 0.1 else { return 0 }
        return Double(streamingTokensApprox) / elapsed
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
                ChatMessage(role: .user, content: "Summarize the pricing brief in three customer-ready bullets."),
                ChatMessage(
                    role: .assistant,
                    content:
                    "• Privacy-first: Your docs stay on-device by default, with optional Private Cloud Compute.\n" +
                        "• Fast, grounded answers: Hybrid search + re-ranking helps keep responses tied to your library.\n" +
                        "• Upgrade when ready: Pro unlocks unlimited docs, more libraries, and priority ingestion."
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
                        keywords: ["privacy", "retrieval", "pricing"],
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
                        sourceDocument: "Sample Pricing Brief",
                        pageNumber: page
                    )
                }

                currentRetrievedChunks = [
                    makeChunk(
                        rank: 1,
                        title: "Value Ladder",
                        page: 1,
                        snippet: "Pro unlocks unlimited docs, 5 libraries, and priority ingestion. Lifetime gives you all Pro features forever.",
                        score: 0.86
                    ),
                    makeChunk(
                        rank: 2,
                        title: "Messaging Pillars",
                        page: 1,
                        snippet: "Privacy-first: data stays on-device or Apple PCC. Retrieval speed: hybrid search + MMR. Collaboration: share libraries.",
                        score: 0.81
                    ),
                    makeChunk(
                        rank: 3,
                        title: "Launch Tasks",
                        page: 1,
                        snippet: "Sync App Store screenshots, include privacy copy, and instrument upgrade funnels.",
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
                    ThinkingEvent(kind: .planning, title: "Query analysis", detail: "Identified: pricing summary request"),
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
            ThinkingEvent(kind: .planning, title: "Query analysis", detail: "Identified: pricing + privacy request"),
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
                "🔍 Analyzing query intent: pricing + privacy information requested",
                "📚 Retrieved 3 highly relevant chunks from pricing brief",
                "🧠 Synthesizing multi-source response with citations"
            ]
        )

        messages = [
            ChatMessage(role: .user, content: "What are the key pricing tiers and privacy features?"),
            ChatMessage(
                role: .assistant,
                content: """
                Based on your documents, here's a comprehensive overview:

                ## Pricing Tiers
                • **Free**: 5 documents, 1 library, full privacy dashboard
                • **Pro** ($5.99/mo or $49.99/yr): Unlimited docs, 5 libraries, priority ingestion
                • **Lifetime** ($59.99): All Pro features forever, 10 libraries

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
                keywords: ["privacy", "pricing", "retrieval"],
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
                sourceDocument: "Sample Pricing Brief.md",
                pageNumber: page
            )
        }

        currentRetrievedChunks = [
            makeChunk(
                rank: 1,
                title: "Value Ladder",
                page: 1,
                snippet: "Free: 5 docs, 1 library. Pro ($5.99/mo): Unlimited docs, 5 libraries. Lifetime ($59.99): All Pro features forever.",
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
        messages.isEmpty && !onboardingStore.hasAskedFirstQuery
    }

    private var starterPrompts: [String] {
        [
            "Summarize the pricing brief in three customer-ready bullets.",
            "What architecture choices keep the retrieval engine private?",
            "Give me launch talking points for the Pro plan.",
            "List risks reviewers should know before monetization."
        ]
    }

    private func persistChatHistory(for containerId: UUID?) {
        ragService.persistChatHistory(messages, for: containerId)
    }

    private func newChat() {
        // Cancel any in-flight query task
        currentQueryTask?.cancel()
        currentQueryTask = nil

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
        embeddingStart = nil
        searchingStart = nil
        generatingStartTS = nil
        embeddingElapsedFinal = nil
        searchingElapsedFinal = nil
        generatingElapsedFinal = nil
        currentRetrievedChunks = []
        currentMetadata = nil
        toastManager.clearAll()
        showRetrievedDetails = false
        thinkingEvents.removeAll()
        requestedExecutionContext = .automatic
        ragService.clearChatHistory(for: ragService.containerService.activeContainerId)
    }

    private func clearChat() {
        // Cancel any in-flight query task
        currentQueryTask?.cancel()
        currentQueryTask = nil

        // Reset processing state
        if isProcessing {
            resetStreamingState()
            isProcessing = false
        }

        messages.removeAll()
        stage = .idle
        generationStart = nil
        embeddingStart = nil
        searchingStart = nil
        generatingStartTS = nil
        embeddingElapsedFinal = nil
        searchingElapsedFinal = nil
        generatingElapsedFinal = nil
        currentRetrievedChunks = []
        currentMetadata = nil
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
        currentQueryTask?.cancel()
        currentQueryTask = nil

        // Flush any buffered text immediately
        flushStreamingBufferToVisibleText()

        // If we have partial text, save it as a message
        if !streamingText.isEmpty {
            var partial = ChatMessage(
                role: .assistant,
                content: streamingText + "\n\n*(Generation stopped)*"
            )
            partial.containerId = ragService.containerService.activeContainerId
            messages.append(partial)
            persistChatHistory(for: partial.containerId)
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

        // Show immediate feedback
        toastManager.show(
            ToastItem(
                title: "Diving deeper with multi-step reasoning...",
                icon: "brain",
                tint: .purple
            ),
            duration: 2.0
        )

        Task {
            isProcessing = true
            stage = .searching // Use searching stage for agentic re-query
            streamingText = ""
            generationStart = Date()

            do {
                // Create inline stream handler for this re-query
                // Note: Can't use [weak self] because ChatScreen is a struct
                let goDeeperStreamHandler: LLMStreamHandler = { event in
                    Task { @MainActor in
                        self.streamingText += event.text
                    }
                }

                if let response = try await ragService.reQueryWithAgenticMode(streamHandler: goDeeperStreamHandler) {
                    await MainActor.run {
                        // Add the deeper response as a new assistant message
                        let deeperMessage = ChatMessage(
                            role: .assistant,
                            content: response.generatedResponse,
                            metadata: response.metadata,
                            retrievedChunks: response.retrievedChunks
                        )
                        messages.append(deeperMessage)

                        streamingText = ""
                        isProcessing = false
                        stage = .complete

                        DSHaptics.success()
                    }
                } else {
                    await MainActor.run {
                        toastManager.show(
                            ToastItem(
                                title: "No previous query to analyze deeper",
                                icon: "exclamationmark.triangle",
                                tint: .orange
                            ),
                            duration: 2.0
                        )
                        isProcessing = false
                        stage = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    toastManager.show(
                        ToastItem(
                            title: "Deeper analysis failed: \(error.localizedDescription)",
                            icon: "xmark.circle",
                            tint: .red
                        ),
                        duration: 3.0
                    )
                    isProcessing = false
                    stage = .idle
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

        // Cancel any existing query - "cancel and replace" strategy
        // This prevents memory leaks from orphaned tasks on back-to-back queries
        if let existingTask = currentQueryTask {
            existingTask.cancel()
            currentQueryTask = nil
            // Brief yield to let cancellation propagate
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
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
        // For Apple Intelligence, assume on-device initially (the common case)
        // We'll update to .privateCloudCompute if TTFT indicates PCC was used
        execution = settings.selectedModel == .appleIntelligence ? .onDevice : .unknown
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
        requestedExecutionContext = capturedExecutionContext
        let capturedUsedContainerId = usedContainerId
        resetStreamingState()

        // Track this task for potential cancellation
        currentQueryTask = Task(priority: .userInitiated) { [weak ragService] in
            guard let capturedService = ragService else { return }

            // Guarantee cleanup even on cancellation or error
            defer {
                Task { @MainActor in
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
                var capturedQuery = isLowSignal ? (lastSemanticQuery ?? query) : query
                if !isLowSignal {
                    await MainActor.run {
                        self.lastSemanticQuery = query
                    }
                }

                // Check for cancellation after query resolution
                try Task.checkCancellation()

                // Clarify the user's query using Writing Tools if available (improves retrieval quality)
                if !isLowSignal, let clarified = try? await WritingToolsService().clarifyQuery(query) {
                    capturedQuery = clarified
                }

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
                    // StatusPillV2 shows stage - no toast needed
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
                    // StatusPillV2 shows stage - no toast needed
                }

                let config = InferenceConfig(
                    maxTokens: capturedMaxTokens,
                    temperature: Float(capturedTemperature),
                    topP: Float(capturedTopP),
                    topK: 40,
                    useKVCache: true,
                    systemPrompt: capturedSystemPrompt,
                    contextLength: capturedContextLength,
                    frequencyPenalty: Float(capturedFrequencyPenalty),
                    presencePenalty: Float(capturedPresencePenalty),
                    repetitionPenalty: Float(capturedRepetitionPenalty),
                    executionContext: capturedExecutionContext,
                    allowPrivateCloudCompute: capturedAllowPCC
                )

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
                    // StatusPillV2 shows stage - no toast needed
                }

                let response = try await capturedService.query(
                    capturedQuery,
                    topK: capturedTopK,
                    config: config,
                    containerId: capturedUsedContainerId,
                    streamHandler: { event in
                        await MainActor.run {
                            if event.isFinal {
                                self.flushStreamingBufferToVisibleText()
                            } else {
                                self.enqueueStreamingText(event.text)
                            }
                        }
                    }
                )

                await MainActor.run {
                    self.currentRetrievedChunks = response.retrievedChunks
                    self.currentMetadata = response.metadata
                    // Sources tray will show this - no separate toast needed
                }

                // Update execution badge based on TTFT heuristic
                // Only upgrade to PCC if TTFT indicates cloud latency (>1s)
                if let first = response.metadata.timeToFirstToken {
                    await MainActor.run {
                        self.ttft = first
                        // If TTFT > 1 second, it likely went through PCC
                        if first >= 1.0 {
                            self.execution = .privateCloudCompute
                        }
                        // TTFT shown in StatusPill - no toast needed
                    }
                }

                var assistant = ChatMessage(
                    role: .assistant,
                    content: sanitizeFinalResponse(response.generatedResponse),
                    metadata: response.metadata,
                    retrievedChunks: response.retrievedChunks
                )
                assistant.containerId = capturedUsedContainerId

                await MainActor.run {
                    // flushStreamingBufferToVisibleText already handled cleanup when isFinal arrived
                    // No need to reset again here - would race with final flush
                    self.messages.append(assistant)
                    self.persistChatHistory(for: capturedUsedContainerId)
                    self.stage = .complete

                    // Show completion toast with token count
                    let tokenCount = response.metadata.tokensGenerated
                    self.toastManager.clearAll()
                    self.pushToast(
                        tokenCount > 0 ? "Done • \(tokenCount) tokens" : "Complete",
                        icon: "checkmark.circle.fill",
                        tint: .green
                    )
                }

                try? await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    if let genStart = self.generatingStartTS {
                        self.generatingElapsedFinal = Date().timeIntervalSince(genStart)
                    }
                    self.stage = .idle
                    self.resetStreamingState()  // Final cleanup after everything settles
                    self.generationStart = nil
                }
            } catch {
                Log.error("Query failed: \(error.localizedDescription)", category: .llm)
                await MainActor.run {
                    let friendlyMessage = userFacingErrorMessage(error)

                    self.toastManager.clearAll()
                    let toastTitle = friendlyMessage.count > 42 ? "Couldn't complete" : friendlyMessage
                    self.pushToast(toastTitle, icon: "exclamationmark.triangle.fill", tint: .red)

                    self.flushStreamingBufferToVisibleText()
                    let partial = self.streamingText.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !partial.isEmpty {
                        let note = "\n\n*(Generation stopped. \(friendlyMessage))*"
                        var partialMessage = ChatMessage(
                            role: .assistant,
                            content: partial + note
                        )
                        partialMessage.containerId = capturedUsedContainerId
                        self.messages.append(partialMessage)
                    } else {
                        var errorMsg = ChatMessage(
                            role: .assistant,
                            content: "\(friendlyMessage)\n\nPlease try again."
                        )
                        errorMsg.containerId = capturedUsedContainerId
                        self.messages.append(errorMsg)
                    }

                    self.persistChatHistory(for: capturedUsedContainerId)

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
                adaptiveChunkSize = chunkSize
                adaptiveCadence = cadence
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

        let message = error.localizedDescription.lowercased()
        if message.contains("exceededcontextwindowsize") {
            return "That request is too large. Try a shorter question."
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

    @State private var showModelDetails = false
    @State private var deviceCapabilities = DeviceCapabilities()

    private var activeContainer: KnowledgeContainer? {
        containerService.activeContainer
    }

    var body: some View {
        VStack(spacing: 10) {
            // Top row: Library picker strip (scrollable)
            libraryPickerStrip

            // Bottom row: Quality mode picker + Model status + Stats
            HStack(spacing: 10) {
                // Always show quality mode picker - Deep Think is useful for all users
                QualityModeQuickPicker(selectedMode: $settings.ragQualityMode) { _, _ in
                    // Reset stale Deep Think/Maximum metrics when mode changes
                    ragService.resetDeepThinkLiveMetrics()
                }

                // Model indicator (compact)
                ModelStatusIndicator(deviceCapabilities: deviceCapabilities)

                Spacer()

                // Stats for active container
                HStack(spacing: 8) {
                    StatChip(icon: "doc.fill", value: "\(docCount)", color: .blue)
                    StatChip(icon: "square.grid.3x3.fill", value: "\(chunkCount)", color: .purple)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
.onAppear {
    deviceCapabilities = RAGService.checkDeviceCapabilities()
}
    }

    // MARK: - Library Picker Strip

    private var libraryPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(containerService.containers) { container in
                    LibraryChip(
                        container: container,
                        isActive: containerService.activeContainerId == container.id,
                        docCount: containerService.documentCount(for: container.id)
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            containerService.setActive(container.id)
                        }
                    }
                }
            }
        }
    }
}

/// Quick picker for quality mode - shows in chat header
/// Dropdown menu to switch between Standard and Deep Think
struct QualityModeQuickPicker: View {
    @Binding var selectedMode: RAGQualityMode
    /// Called when mode changes, passing old and new mode
    var onModeChange: ((RAGQualityMode, RAGQualityMode) -> Void)?

    var body: some View {
        Menu {
            ForEach(RAGQualityMode.userVisibleCases, id: \.id) { mode in
                Button {
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
            HStack(spacing: 4) {
                Image(systemName: selectedMode.canonical.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(selectedMode.canonical.displayName)
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(modeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(modeColor.opacity(0.12))
            )
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

/// Library chip for horizontal picker strip in chat header
private struct LibraryChip: View {
    let container: KnowledgeContainer
    let isActive: Bool
    let docCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: container.icon)
                    .font(.system(size: 11, weight: .medium))

                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                // Show doc count badge for active container
                if docCount > 0 {
                    Text("\(docCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .white.opacity(0.9) : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isActive ? .white.opacity(0.25) : Color.secondary.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? DSColors.accent : Color(.systemGray6))
            )
            .foregroundStyle(isActive ? .white : DSColors.primaryText)
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isActive ? DSColors.accent.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
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
    let onPromptSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "sparkles")
                    .imageScale(.large)
                    .foregroundStyle(DSColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask your first grounded question")
                        .font(DSTypography.title)
                    Text(hasDocuments
                        ? "These prompts lean on your imported workspace so you can feel the retrieval stack in action."
                        : "Import documents from the Documents tab, then try one of these prompts to exercise retrieval.")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        onPromptSelected(prompt)
                    } label: {
                        HStack {
                            Text(prompt)
                                .font(DSTypography.body)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: DSSpacing.sm)
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(DSColors.accent)
                        }
                        .padding(.vertical, DSSpacing.xs)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                            .fill(DSColors.surface)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
                    )
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(DSColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .strokeBorder(DSColors.accent.opacity(0.15), lineWidth: 1)
        )
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

// MARK: - Preview

#Preview {
    NavigationView {
        ChatScreen(ragService: RAGService())
    }
    #if os(iOS)
        .navigationViewStyle(.stack)
    #endif
}

//
//  ChatScreen.swift
//  OpenIntelligence
//
//  Created by Cline on 10/28/25.
//

import Combine
import Foundation
import SwiftUI

// ChatV2 entry point (feature-flagged from ContentView)
@MainActor
struct ChatScreen: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @ObservedObject var ragService: RAGService
    @AppStorage("retrievalTopK") private var retrievalTopK: Int = 3
    @State private var showScrollToBottom: Bool = false
    @State private var messages: [ChatMessage] = []
    @State private var streamingText: String = ""
    @State private var streamingBuffer: String = ""
    @State private var streamingPumpTask: Task<Void, Never>? = nil
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
    @State private var toasts: [ToastItem] = []
    @State private var currentRetrievedChunks: [RetrievedChunk] = []
    @State private var currentMetadata: ResponseMetadata? = nil
    @State private var showRetrievedDetails: Bool = false

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

    // Settings (synchronized with SettingsView via @AppStorage)
    @AppStorage("llmTemperature") private var temperature: Double = 0.7
    @AppStorage("llmMaxTokens") private var maxTokens: Int = 500
    @AppStorage("allowPrivateCloudCompute") private var allowPrivateCloudCompute: Bool = true
    @AppStorage("executionContextRaw") private var executionContextRaw: String = "automatic"

    var body: some View {
        VStack(spacing: 0) {
            // Header removed (moved actions to NavigationBar toolbar)

            // Container selector (scopes chat retrieval)
            ContainerPickerStrip(containerService: ragService.containerService)
                .padding(.horizontal)

            // One-off override (applies to next message only)
            HStack(spacing: DSSpacing.sm) {
                Text("This message:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Library", selection: $messageContainerOverride) {
                    // Nil = use pinned active container
                    let activeName = ragService.containerService.activeContainer?.name ?? "Active"
                    Text("Active: \(activeName)").tag(Optional<UUID>.none)
                    ForEach(ragService.containerService.containers, id: \.id) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }
                .pickerStyle(.menu)
                if messageContainerOverride != nil {
                    Button {
                        messageContainerOverride = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal)

            // Context / Status Bar (active-container scoped)
            ContextStatusBarView(
                docCount: activeDocCount,
                chunkCount: activeChunkCount,
                usedK: latestRetrievedCount
            )

            Divider()

            if shouldShowFirstQueryHero {
                FirstQueryPromptView(
                    hasDocuments: activeDocCount > 0,
                    prompts: starterPrompts,
                    onPromptSelected: sendSuggestedPrompt
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.md)
            } else {
                MessageListView(messages: $messages)
                    .clipped()
                    .padding(.bottom, DSSpacing.md)
            }

            // Streaming row (verbose but clean)
            if isProcessing && !streamingText.isEmpty {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    AvatarView(kind: .assistant)
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(streamingText)
                            .font(DSTypography.body)
                            .foregroundColor(DSColors.primaryText)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.sm)
                            .background(DSColors.surface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DSCorners.bubble, style: .continuous)
                            )
                            .bubbleShadow()
                        HStack(spacing: DSSpacing.xs) {
                            TokenCadenceView(
                                tokensApprox: tokensApprox, tokensPerSecond: tokensPerSecondApprox)
                            TypingIndicator()
                        }
                    }
                    Spacer(minLength: 48)
                }
                .padding(.horizontal, DSSpacing.md)
                .transition(.opacity.combined(with: .scale))
            }

            // Stage indicator + execution badge (stacked, not overlay)
            StageProgressBar(
                stage: stage,
                execution: execution,
                ttft: ttft,
                embeddingElapsed: embeddingElapsedDisplay,
                searchingElapsed: searchingElapsedDisplay,
                generatingElapsed: generatingElapsedDisplay
            )

            // Live telemetry strip during generation (stacked, not overlay)
            if isProcessing {
                LiveCountersStrip(
                    ttft: ttft,
                    tokensApprox: tokensApprox,
                    tokensPerSecondApprox: tokensPerSecondApprox,
                    retrievedCount: latestRetrievedCount
                )
            }

            Divider()

            // Composer (will evolve with Writing Tools and actions)
            ChatComposer(
                isProcessing: isProcessing,
                onSend: sendMessage
            )
        }
        .navigationTitle(ragService.currentModelName)
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
            await recalcActiveCounts()
        }
        // Recalculate when documents list changes (objectWillChange is a coarse signal)
        .onReceive(ragService.objectWillChange) { _ in
            Task { await recalcActiveCounts() }
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
            .presentationDetents([.medium, .large])
#endif
        }
    }

    // MARK: - Active-container counts

    private func recalcActiveCounts() async {
        let activeId = await MainActor.run { ragService.containerService.activeContainerId }
        let defaultId = await MainActor.run { ragService.containerService.containers.first?.id }
        let docsSnapshot = await MainActor.run { ragService.documents }
        // Match Visualizations/Documents parity for legacy docs
        let docsForActive = docsSnapshot.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        let chunksForActive = await ragService.allChunksForActiveContainer()
        await MainActor.run {
            self.activeDocCount = docsForActive.count
            self.activeChunkCount = chunksForActive.count
        }
    }

    // MARK: - Derived counters
    private var latestRetrievedCount: Int {
        messages.last(where: { $0.role == .assistant })?.retrievedChunks?.count ?? 0
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

    // MARK: - Execution Context mapping
    private var executionContext: ExecutionContext {
        switch executionContextRaw {
        case "automatic": return .automatic
        case "onDeviceOnly": return .onDeviceOnly
        case "preferCloud": return .preferCloud
        case "cloudOnly": return .cloudOnly
        default: return .automatic
        }
    }

    // MARK: - Send Message
    private var shouldShowFirstQueryHero: Bool {
        messages.isEmpty && !onboardingStore.hasAskedFirstQuery
    }

    private var starterPrompts: [String] {
        [
            "Summarize the pricing brief in three customer-ready bullets.",
            "What architecture choices keep the retrieval engine private?",
            "Give me launch talking points for the Starter plan.",
            "List risks reviewers should know before monetization."
        ]
    }

    private func newChat() {
        print("🔄 [ChatScreen] New chat initiated")
        
        // Cancel any in-flight processing
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
        toasts.removeAll()
        showRetrievedDetails = false
    }

    private func clearChat() {
        print("🗑️ [ChatScreen] Clear chat initiated")
        
        // Cancel any in-flight processing
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
        toasts.removeAll()
        showRetrievedDetails = false
    }

    private func sendMessage(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        // Prevent concurrent queries
        guard !isProcessing else {
            print("⚠️ [ChatScreen] Query already in progress, ignoring new request")
            return
        }
        
        onboardingStore.markAskedFirstQuery()

        // Append user message with selected container (override or active)
        var userMessage = ChatMessage(role: .user, content: query)
        let usedContainerId =
            messageContainerOverride ?? ragService.containerService.activeContainerId
        userMessage.containerId = usedContainerId
        messages.append(userMessage)
        // Reset override after one use
        self.messageContainerOverride = nil

        // Reset and start processing
        isProcessing = true
        stage = .embedding
        execution = .unknown
        ttft = nil

        // Capture values for async task (query may be clarified asynchronously)
        let capturedTopK = retrievalTopK
        let capturedMaxTokens = maxTokens
        let capturedTemperature = temperature
        let capturedExecutionContext = executionContext
        let capturedAllowPCC = allowPrivateCloudCompute
        let capturedService = ragService
        let capturedUsedContainerId = usedContainerId
        resetStreamingState()

        Task(priority: .userInitiated) {
            // Guarantee cleanup even on cancellation or error
            defer {
                Task { @MainActor in
                    self.isProcessing = false
                    if self.stage == .generating || self.stage == .searching || self.stage == .embedding {
                        self.stage = .idle
                    }
                }
            }
            
            do {
                // Clarify the user's query using Writing Tools if available (improves retrieval quality)
                var capturedQuery = query
                if let clarified = try? await WritingToolsService().clarifyQuery(query) {
                    capturedQuery = clarified
                }

                // Stage 1: Embedding
                await MainActor.run {
                    self.stage = .embedding
                    self.embeddingStart = Date()
                    self.embeddingElapsedFinal = nil
                    self.searchingStart = nil
                    self.searchingElapsedFinal = nil
                    self.generatingStartTS = nil
                    self.generatingElapsedFinal = nil
                    self.pushToast(
                        "Embedding started", icon: "brain.head.profile", tint: DSColors.accent)
                }
                try? await Task.sleep(nanoseconds: 250_000_000)

                // Stage 2: Searching
                await MainActor.run {
                    self.stage = .searching
                    self.searchingStart = Date()
                    if let embStart = self.embeddingStart {
                        self.embeddingElapsedFinal = Date().timeIntervalSince(embStart)
                    }
                    self.pushToast(
                        "Searching top \(capturedTopK)", icon: "magnifyingglass", tint: .green)
                }

                let config = InferenceConfig(
                    maxTokens: capturedMaxTokens,
                    temperature: Float(capturedTemperature),
                    topP: 0.9,
                    topK: 40,
                    useKVCache: true,
                    executionContext: capturedExecutionContext,
                    allowPrivateCloudCompute: capturedAllowPCC
                )

                // Stage 3: Generating
                await MainActor.run {
                    self.stage = .generating
                    self.generationStart = Date()
                    self.generatingStartTS = self.generationStart
                    if let searchStart = self.searchingStart, let genStart = self.generationStart {
                        self.searchingElapsedFinal = genStart.timeIntervalSince(searchStart)
                    }
                    self.pushToast("Generating…", icon: "sparkles", tint: DSColors.accent)
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
                    self.pushToast(
                        "Found \(response.retrievedChunks.count) source\(response.retrievedChunks.count == 1 ? "" : "s")",
                        icon: "doc.text.magnifyingglass", tint: .green)
                }

                // Update execution badge based on TTFT heuristic
                if let first = response.metadata.timeToFirstToken {
                    await MainActor.run {
                        self.ttft = first
                        self.execution = first < 1.0 ? .onDevice : .privateCloudCompute
                        let ttftString =
                            first < 1.0
                            ? String(format: "%.0f ms", first * 1000)
                            : String(format: "%.2f s", first)
                        self.pushToast("TTFT \(ttftString)", icon: "timer", tint: DSColors.accent)
                    }
                }

                var assistant = ChatMessage(
                    role: .assistant,
                    content: response.generatedResponse,
                    metadata: response.metadata,
                    retrievedChunks: response.retrievedChunks
                )
                assistant.containerId = capturedUsedContainerId

                await MainActor.run {
                    // flushStreamingBufferToVisibleText already handled cleanup when isFinal arrived
                    // No need to reset again here - would race with final flush
                    self.messages.append(assistant)
                    self.stage = .complete
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
                print("❌ [ChatScreen] Query failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.stage = .idle
                    self.resetStreamingState()
                    
                    // Add error message to chat
                    let errorMsg = ChatMessage(
                        role: .assistant,
                        content: "Sorry, I encountered an error: \(error.localizedDescription)\n\nPlease try again."
                    )
                    self.messages.append(errorMsg)
                }
            }
        }
    }

    private func sendSuggestedPrompt(_ prompt: String) {
        DSHaptics.selection()
        sendMessage(prompt)
    }

    // MARK: - Toasts

    private func pushToast(_ title: String, icon: String, tint: Color) {
        // Toast UI disabled for layout stabilization
        // Intentionally no-op to avoid any overlay/stack interference
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
            print("🚰 [Streaming] Starting pump (buffer=\(streamingBuffer.count) chars)")
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
        defer {
            print("🚰 [Streaming] Pump stopped (remaining buffer=\(streamingBuffer.count) chars)")
            streamingPumpTask = nil
        }
        var pumpedCount = 0
        while !Task.isCancelled {
            guard !streamingBuffer.isEmpty else { return }
            let takeCount = min(chunkSize, streamingBuffer.count)
            let nextChunk = String(streamingBuffer.prefix(takeCount))
            streamingBuffer.removeFirst(takeCount)
            pumpedCount += 1
            
            // Force immediate UI update with explicit animation
            withAnimation(.linear(duration: 0.04)) {
                streamingText.append(nextChunk)
            }
            
            if pumpedCount % 5 == 0 {
                print("🚰 [Streaming] Pumped \(pumpedCount) chunks (\(streamingText.count) visible chars, \(streamingBuffer.count) buffered)")
            }
            
            do {
                try await Task.sleep(nanoseconds: cadence)
            } catch {
                return
            }
        }
    }

    /// Cleans streamed chunks before they reach the UI, stripping stray control characters and the recurring "null -" artifact reported in the stream gutter.
    private func sanitizeStreamChunk(_ chunk: String, isFirstChunk: Bool) -> String? {
        guard !chunk.isEmpty else { return nil }

        // Remove null scalars and non-printable control characters while preserving whitespace/newlines for Markdown layout.
        var cleaned = chunk.replacingOccurrences(of: "\u{0000}", with: "")
        let disallowedControls = CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines)
        if cleaned.rangeOfCharacter(from: disallowedControls) != nil {
            cleaned = cleaned.components(separatedBy: disallowedControls).joined()
        }

        guard !cleaned.isEmpty else { return nil }

        if isFirstChunk,
            let range = cleaned.range(
                of: #"^\s*(?:null|\(null\))\s*[-–—]\s*"#,
                options: [.regularExpression, .caseInsensitive]
            )
        {
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

        return cleaned.isEmpty ? nil : cleaned
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

//
//  ChatScreen.swift
//  OpenIntelligence
//
//  Created by Cline on 10/28/25.
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

/// Data container for unified metrics bar (shown during streaming AND after completion)
struct ConsolidatedMetrics {
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
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openURL) var openURL
    @EnvironmentObject var onboardingStore: OnboardingStateStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var entitlementStore: EntitlementStore
    @ObservedObject var ragService: RAGService

    init(ragService: RAGService) {
        self.ragService = ragService
    }

    @AppStorage("retrievalTopK") var retrievalTopK: Int = 3
    @State private var showScrollToBottom: Bool = false
    @State var showThreadSidebar: Bool = false
    @State var messages: [ChatMessage] = []
    @State var didSeedScreenshotDemo: Bool = false
    #if DEBUG
        /// The listing's page scene: a cited passage open on its PDF page (5.7).
        @State var storeScenePage: StoreScenePage? = nil
    #endif
    @State var streamingText: String = ""
    /// Text another part of the system handed over to ask about, put in the composer unsent (5.7).
    @State var composerDraft: ComposerDraft? = nil
    /// The library's documents for a cited passage's page; one object, so the environment is stable.
    @State var documentLookup = LibraryDocumentLookup()
    /// A source chip's passage, open in its document (5.8).
    @State var openedSourceChunk: OpenedRetrievedChunk?
    @State var streamingBuffer: String = ""
    @State var streamingPumpTask: Task<Void, Never>? = nil
    @State var currentQueryTask: Task<Void, Never>? = nil  // Track current query for cancellation
    @State var currentQuerySessionId: UUID? = nil
    /// The library the answer in progress belongs to, which is not always the active one: an
    /// answer keeps running after the person switches library.
    @State var currentQueryContainerId: UUID? = nil
    /// A question sent while the previous answer was being checked. It goes once that answer lands;
    /// only one waits at a time.
    @State var questionAfterCheck: String? = nil
    @State var queryStart: Date? = nil
    @State var hasReceivedStreamToken: Bool = false
    @State var generationStart: Date? = nil
    // Per-stage timing
    @State var embeddingStart: Date? = nil
    @State var searchingStart: Date? = nil
    @State var generatingStartTS: Date? = nil
    @State var embeddingElapsedFinal: TimeInterval? = nil
    @State var searchingElapsedFinal: TimeInterval? = nil
    @State var generatingElapsedFinal: TimeInterval? = nil
    @State var isStreamFinished: Bool = false
    // Live clock tick to drive elapsed UI — only connected during processing to save battery
    @State var nowTick: Date = Date()
    @State var processingClock = Timer.publish(every: 0.2, on: .main, in: .common)
    /// Handle for the connection above, so it can actually be cancelled.
    ///
    /// Without this there is nothing to call `cancel()` on: `connect()` returns the
    /// cancellable and the old code discarded it with `_ =`, so every query started a new
    /// 5 Hz timer and none of them ever stopped. After N queries the run loop was waking
    /// 5N times a second for the life of the session, under a comment claiming the timer
    /// was stopped to save battery.
    @State var processingClockConnection: Cancellable?
    // Ephemeral UI and retrieval
    @StateObject var toastManager = ToastManager()
    @State var currentRetrievedChunks: [RetrievedChunk] = []
    @State var currentMetadata: ResponseMetadata? = nil
    @State var currentStructuredAnswer: StructuredAnswer? = nil
    @State var showRetrievedDetails: Bool = false
    @State var thinkingEvents: [ThinkingEvent] = []
    @State var requestedExecutionContext: ExecutionContext = .automatic

    // Processing State
    @State var isProcessing: Bool = false
    @State var stage: ChatProcessingStage = .idle
    @State var execution: ChatExecutionLocation = .unknown
    @State var ttft: TimeInterval?

    // Active-container scoped counts for status bar
    @State var activeDocCount: Int = 0
    @State var activeChunkCount: Int = 0

    // One-off per-message container override
    @State var messageContainerOverride: UUID? = nil

    // Cloud consent prompt state
    @State var activeCloudConsent: CloudTransmissionRecord? = nil

    // Translation overlay
    @State var translationText: String = ""
    @State var showTranslation: Bool = false

    // WritingTools overlay
    @State var writingToolsResult: String = ""
    @State var writingToolsTitle: String = ""
    @State var showWritingToolsResult: Bool = false
    /// The file a conversation export wrote, while its share sheet is up.
    @State var conversationExport: ConversationExportFile? = nil
    @State var writingToolsProcessing: Bool = false

    // Vision Capture overlay
    @State var showVisionCapture: Bool = false
    /// Apple's document scanner, for "Scan a Document" (5.7). Not the app's own camera, which
    /// stays in Debug builds (`visionCaptureAction`).
    @State var showDocumentScanner: Bool = false

    /// Opens the live camera screen, or nil on a platform that has no camera screen.
    ///
    /// Computed here rather than written inline into the `ChatComposerV2` argument list, because
    /// `CameraVisionOverlayView` lives inside `#if os(iOS)` and a conditional-compilation block in
    /// an argument position is more fragile than a property that resolves before the call.
    ///
    /// `AttachmentPicker` guards its button on `if let onVisionCapture`, so nil here removes the
    /// menu item rather than showing one that does nothing. Passing nil is what "disabled" meant
    /// for this feature from v1 until 2026-09-11.
    ///
    /// **Debug builds only, decided 2026-09-13.** The owner's words: the camera work is
    /// experimental and "should probably wait". Shipping it in 5.3 would put a live camera feature
    /// in front of strangers having never run outside one person's hands on one phone, and its
    /// riskiest property is one nobody has observed: `CameraVisionOverlayView` pairs `.onAppear`
    /// with `.onDisappear { cameraManager.stopSession() }`, which is correct code, but a dismissal
    /// path where `.onDisappear` does not fire leaves the capture session running. On a stranger's
    /// phone that is a lit camera indicator and a flat battery, reported through a review rather
    /// than to us.
    ///
    /// A compile-time gate rather than a setting, because a setting still ships the screen and
    /// leaves it one tap from anyone who goes looking. `#if DEBUG` keeps it on the owner's own
    /// device builds, which is where the remaining testing has to happen anyway.
    ///
    /// Measured on a Release build rather than assumed: `CameraVisionOverlayView`'s own
    /// `Vision Capture` string is absent from the Release binary, because nothing can set
    /// `showVisionCapture` true and the optimiser strips the presenter. `AttachmentPicker`'s
    /// `Look at Something` label does survive, since that file compiles unconditionally, so the
    /// menu item is **unreachable rather than absent**. It cannot render: its `if let
    /// onVisionCapture` guard is handed nil.
    ///
    /// **Removing the `#if DEBUG` is what releasing this feature means.** Do not remove it to
    /// silence a diff or to make a screenshot; the notes in `CHANGELOG.md` and `Docs/ai/STATE.md`
    /// describe what would have to be true first.
    var visionCaptureAction: (() -> Void)? {
        #if os(iOS) && DEBUG
            return { showVisionCapture = true }
        #else
            return nil
        #endif
    }
    @State var showPlanSheet: Bool = false
    @State var planEntryPoint: PlanUpgradeEntryPoint = .maximumModeLimit
    @State var showMaximumModeLimitDialog: Bool = false
    @State var maximumModeLimitDialogMessage: String = ""

    // Hardware telemetry for Motherboard HUD visibility
    private var hardwareTelemetry = HardwareTelemetryState.shared

    // Dynamic suggested questions
    @State var dynamicSuggestedQuestions: [String] = []
    @State var dynamicQuestionDetails: [String: SuggestedQuestionsService.SuggestedQuestion] = [:]
    @State var suggestedQuestionsTask: Task<Void, Never>? = nil
    @State var isRefreshingSuggestions = false
    let suggestedQuestionsService = SuggestedQuestionsService.shared
    @State var lastProcessedContainerId: UUID? = nil
    @State var lastLoadedChatContainerId: UUID? = nil
    @State var lastProcessedDocuments: [Document]? = nil
    @State var isAppeared = false

    // The development journal's launch markers (5.8): when the chat first showed in this process and how many answers
    // it has written, for `launch.chatUsable`, `answer.start` and `answer.done`.
    static var chatFirstShownAt: Date?
    static var answersThisLaunch = 0

    /// Windows or scenes in front, for `chat.appear` (5.8): with `engines`, whether two windows share one engine.
    var visibleWindowCount: Int {
        #if os(macOS)
            return NSApplication.shared.windows.filter { $0.isVisible && $0.canBecomeMain }.count
        #else
            return UIApplication.shared.connectedScenes.filter { $0.activationState != .background }.count
        #endif
    }

    /// The open library's passage count as the library list has it, for the large-library rows (5.8).
    var activeLibraryPassages: Int {
        ragService.containerService.activeContainer?.totalChunks ?? 0
    }
    @State var needsSuggestedQuestionsRefresh = false

    // Smart Reply follow-up suggestions (shown after AI response)
    @State var followUpSuggestions: [SmartReply] = []
    @State var followUpSuggestionsTask: Task<Void, Never>? = nil
    @State var showFeedbackEmailPrompt = false

    // Speed history for sparkline graph
    @State var speedHistory: [Double] = []
    @State var lastSpeedSampleTokens: Int = 0
    @State var lastSpeedSampleTime: Date = .init()
    @State var lastSemanticQuery: String? = nil
    @StateObject var continuedQueryCoordinator = ContinuedQueryCoordinator()

    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    // Settings (synchronized with SettingsView via @AppStorage)
    @AppStorage("llmTemperature") var temperature: Double = 0.7
    @AppStorage("llmMaxTokens") var maxTokens: Int = 512
    @AppStorage("llmTopP") var topP: Double = 0.9
    // Defaults to "topK" so an upgrading user keeps the previous behaviour: the old
    // inference path in LLMService always resolved to .random(top: 40) for chat.
    @AppStorage("llmSamplingStrategy") var samplingStrategyRaw: String = SamplingStrategy.topK.rawValue
    /// Sampling shortlist size. Distinct from the retrieval top-K passed to `query(_:topK:)`.
    @AppStorage("llmTopK") var samplingTopK: Int = 40
    @AppStorage("llmSamplingSeed") var seedStorage: Int = -1
    @AppStorage("llmFrequencyPenalty") var frequencyPenalty: Double = 0.0
    @AppStorage("llmPresencePenalty") var presencePenalty: Double = 0.0
    @AppStorage("llmRepetitionPenalty") var repetitionPenalty: Double = 1.0
    @AppStorage("llmSystemPrompt") var systemPrompt: String = "You are a helpful assistant."
    @AppStorage("llmContextLength") var contextLength: Int = 2048

    /// Context tokens actually used (from audit) or estimated
    /// Uses real values from RAGService when available for accuracy
    var actualContextTokensUsed: Int {
        // Prefer real audit data when available
        if let audit = ragService.lastAuditSnapshot {
            // Convert chars to tokens (audit has contextChars)
            return max(1, audit.contextChars / 3)  // ~3 chars per token conservative
        }
        return estimatedContextTokens
    }

    /// Max context tokens - use audit's availableContextTokens when available
    /// This reflects the ACTUAL budget RAGService computed, not a hardcoded value
    var maxContextTokensForUI: Int {
        if let audit = ragService.lastAuditSnapshot {
            // Show available context budget (what was actually allocated)
            return audit.availableContextTokens > 0 ? audit.availableContextTokens : audit.baseWindowTokens
        }

        // Before the first answer, the window this device reports (5.7; this was a fixed 4096, under the 8,192 a
        // Mac on macOS 27 reported). A device that reports none keeps 4096.
        return FoundationModelTokenBudget.reportedOnDeviceContextSize ?? FoundationModelTokenBudget.baseContextLength
    }

}

// MARK: - Header

struct ChatHeader: View {
    let onNewChat: () -> Void
    let onClearChat: () -> Void
    var body: some View {
        HStack {
            HStack(spacing: DSSpacing.sm) {
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
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Context / Status Bar

struct ContextStatusBarView: View {
    let docCount: Int
    let chunkCount: Int
    let usedK: Int

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "doc.text.fill")
                .font(.caption2)
                .foregroundStyle(.green)

            Text("\(docCount) document\(docCount == 1 ? "" : "s")")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)

            Text("•")
                .font(.caption2)
                .foregroundStyle(DSColors.secondaryText)

            Text("\(chunkCount) chunks")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)

            Spacer()

            Text("k used: \(usedK)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
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

    /// The bottom row's two pills. Both are fixed size (5.7), so the row wraps instead of squeezing one
    /// (`WrappingRowLayout`): the pills and the counts on one line when everything fits, the counts on a line of their
    /// own when it does not (on a 402-point iPhone a library of 100 passages or more no longer fits beside the pills),
    /// and the pills on lines of their own when they are wider than the screen together.
    @ViewBuilder
    private var bottomRowPills: some View {
        // Always show quality mode picker - Deep Think is useful for all users
        QualityModeQuickPicker(
            selectedMode: $settings.ragQualityMode, onMaximumModeBlocked: onMaximumModeBlocked
        ) { _, _ in
            Tour.used(.modePicker)
            // Reset stale Deep Think/Maximum metrics when mode changes
            ragService.resetDeepThinkLiveMetrics()
        }
        .tour(.modePicker, in: Tour.chat)

        // Model indicator (compact)
        ModelStatusIndicator()
    }

    /// Stats for active container
    private var bottomRowCounts: some View {
        HStack(spacing: DSSpacing.sm) {
            StatChip(icon: "doc.fill", value: "\(docCount)", color: .blue)
            // The passages are the search's units, not the person's: shown with the technical view (5.7).
            if settings.showTechnicalDetails {
                StatChip(icon: "square.grid.3x3.fill", value: "\(chunkCount)", color: .purple)
            }
        }
    }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            // Top row: Library picker strip (scrollable)
            libraryPickerStrip

            // Bottom row: Quality mode picker + Model status + Stats, on as few lines as fit (see `bottomRowPills`)
            WrappingRowLayout(spacing: DSSpacing.sm, lineSpacing: DSSpacing.sm, lastAtTrailingEdge: true) {
                bottomRowPills
                bottomRowCounts
            }
            // Stacked, the row is only as wide as its widest pill, and the header's stack would center it.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.md)
        }
        .padding(.vertical, DSSpacing.sm)
        .onAppear {
            deviceCapabilities = RAGService.checkDeviceCapabilities()
        }
    }

    // MARK: - Library Picker Strip

    private var libraryPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        libraryPillList
                    }
                    .padding(.horizontal, DSSpacing.md)
                }
            } else {
                HStack(spacing: DSSpacing.sm) {
                    libraryPillList
                }
                .padding(.horizontal, DSSpacing.md)
            }
        }
    }

    @ViewBuilder
    private var libraryPillList: some View {
        // The libraries a Focus filter allows while its Focus is on, otherwise all (5.7).
        ForEach(containerService.pickableContainers) { container in
            ContainerPill(
                container: container,
                isSelected: containerService.activeContainerId == container.id,
                canDelete: false,
                badgeText: documentCountText(for: container),
                badgeStyle: .count
            ) {
                Tour.used(.libraryPills)
                withAnimation(DSAnimations.snappySpring) {
                    containerService.setActive(container.id)
                }
                SiriDonations.libraryUsed(container)
            }
            .fixedSize(horizontal: true, vertical: false)
            .tour(.libraryPills, in: Tour.chat, when: containerService.activeContainerId != container.id
                && container.id == containerService.pickableContainers.first(where: { $0.id != containerService.activeContainerId })?.id)
        }
    }

    private func documentCountText(for container: KnowledgeContainer) -> String? {
        let count = containerService.documentCount(for: container.id)
        return count > 0 ? "\(count)" : nil
    }
}


/// Reliability-first indicator (shown when advanced tuning is disabled).
struct AccuracyModeBadge: View {
    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "checkmark.seal.fill")
                .scaledFont(size: 10, weight: .semibold)
            Text("Reliability First")
                .scaledFont(size: 11, weight: .semibold)
        }
        .foregroundStyle(Color.green)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
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
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            // The count in the label color, the color in the icon and the tint (5.7): colored digits on the tinted
            // capsule measured 4.1 to 1.
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
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
            VStack(spacing: DSSpacing.lg) {
                Spacer(minLength: DSSpacing.lg)

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
                        .scaledFont(size: 48)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: DSSpacing.sm) {
                    Text("New Chat UI (V2)")
                        .font(.title3)

                    Text(
                        "A modern, modular interface is being enabled behind a feature flag. This is the initial scaffold."
                    )
                    .font(.subheadline)
                    .foregroundStyle(DSColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DSSpacing.xl)
                }

                VStack(alignment: .leading, spacing: DSSpacing.md) {
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
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.sm)

                Spacer(minLength: DSSpacing.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.md)
        }
    }
}


struct ChatV2FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DSColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
    }
}

// MARK: - Composer Placeholder (legacy stub, not used in flow)

struct ComposerStub: View {
    @State private var text: String = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.md) {
            TextField("Message AI...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
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
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                }
            }
            .disabled(true)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.md)
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

//
//  UnifiedMetricsBar.swift
//  OpenIntelligence
//
//  Single source of truth for all processing metrics and intelligence in chat.
//  Combines execution location, context usage, generation stats, source quality,
//  and real-time system state into one cohesive, expandable component.
//

import SwiftUI

// MARK: - RAG Pipeline Mode

/// Indicates the retrieval strategy being used for the current query
enum RetrievalMode: String, Sendable {
    case hybrid = "Hybrid" // Vector + BM25 with RRF fusion
    case vectorOnly = "Vector" // Pure semantic search
    case lexicalBoosted = "BM25+" // Lexical-heavy for keyword queries

    var icon: String {
        switch self {
        case .hybrid: return "arrow.triangle.merge"
        case .vectorOnly: return "brain"
        case .lexicalBoosted: return "text.magnifyingglass"
        }
    }

    var color: Color {
        switch self {
        case .hybrid: return .purple
        case .vectorOnly: return .blue
        case .lexicalBoosted: return .orange
        }
    }
}

// MARK: - Main Unified Component

/// The ONE metrics bar to rule them all.
/// Shows everything: execution location, context window, generation speed,
/// sources, quality mode, system state—with expandable detail panel for transparency.
struct UnifiedMetricsBar: View {
    // Processing state
    let stage: ChatProcessingStage
    let execution: ChatExecutionLocation
    let isProcessing: Bool
    let qualityMode: RAGQualityMode

    /// Whether the LLM is actively generating tokens right now.
    /// This comes from Apple's `session.isResponding` and provides more accurate
    /// real-time feedback than the app's manual `isProcessing` state.
    /// When `true`, shows a pulsing indicator to signal active generation.
    var isLLMActivelyGenerating: Bool = false

    // Context metrics
    let contextTokens: Int
    let maxContextTokens: Int

    // Generation metrics (live during streaming, final after completion)
    let tokensGenerated: Int
    let tokensPerSecond: Double
    let characterCount: Int
    let elapsedTime: TimeInterval
    let speedHistory: [Double]
    let ttft: TimeInterval?

    // Source metrics
    let sourceCount: Int
    let averageSourceScore: Float?
    let totalDocuments: Int
    let totalChunks: Int
    let coveredDocuments: Int
    let toolCallCount: Int

    // Model info
    let modelName: String?
    let requestedExecutionContext: ExecutionContext

    // RAG Pipeline Intelligence (optional - shows when available)
    var retrievalMode: RetrievalMode = .hybrid
    var mmrDiversity: Double = 0.6
    var semanticChunksUsed: Bool = true
    var vectorWeight: Double = 0.4  // Default matches RetrievalConfig.default
    var lexicalWeight: Double = 0.6 // Slightly favor BM25 for keyword queries

    // NEW: Real-time query understanding (set from RAGService thinking events)
    var originalQuery: String = ""
    var rewrittenQuery: String = ""
    var extractedKeywords: [String] = []
    var queryIntent: String = ""
    var hydeEnabled: Bool = false
    var expansionCount: Int = 0
    var topMatchScore: Float = 0.0
    var topMatchSource: String = ""

    // NEW: Advanced RAG features (FullBlownUpgrade)
    var hierarchicalChunkingActive: Bool = false // Parent-child indexing enabled
    var parentChunksUsed: Int = 0 // Number of parent-expanded chunks
    var siblingChunksAdded: Int = 0 // Siblings merged during expansion
    var graphExpansionActive: Bool = false // GraphRAG-lite 2-hop search
    var graphEntitiesExtracted: Int = 0 // Entities found for graph traversal
    var intentAwareWeightsActive: Bool = true // Dynamic weight adjustment

    /// When true, shows total tokens across calls instead of percentage (for recursive/agentic RAG)
    /// Recursive RAG bypasses single-call limits by making multiple small calls
    var isRecursiveRAG: Bool = false
    /// Number of LLM calls made in recursive mode
    var recursiveCallCount: Int = 0

    // MARK: - Full Transparency Dashboard Data (from RAGAuditSnapshot)
    // These provide the "watching the gears turn" granular view users want

    // Pipeline Journey: Chunk Selection Funnel
    var totalStoredChunks: Int = 0      // Total chunks in vector DB
    var candidatesCount: Int = 0        // Initial retrieval candidates
    var rerankedCount: Int = 0          // After reranking
    var filteredCount: Int = 0          // After similarity filtering
    var droppedCount: Int = 0           // Chunks dropped (low quality)
    var mmrSelectedCount: Int = 0       // After MMR diversity selection
    var uniqueDocCount: Int = 0         // Unique documents in final set

    // Token Budget Allocation
    var baseWindowTokens: Int = 0       // Model's base context window
    var safetyTokens: Int = 0           // Safety margin reserved
    var promptOverheadTokens: Int = 0   // System prompt + framing
    var questionTokens: Int = 0         // User query tokens
    var reservedOutputTokens: Int = 0   // Reserved for response
    var availableContextTokens: Int = 0 // What's left for RAG context

    // Confidence & Quality Metrics
    var lenientRetrieval: Bool = false  // Using relaxed thresholds
    var dynamicMinThreshold: Float = 0  // Computed minimum similarity
    var topSimilarity: Float = 0        // Best match score
    var secondSimilarity: Float = 0     // Second-best score
    var avgTop5Similarity: Float = 0    // Average of top 5
    var acceptanceOverride: Bool = false // Forced acceptance

    // Library Context
    var containerName: String = ""      // Active library name
    var embeddingDim: Int = 512         // Embedding dimensions
    var vectorDBKind: String = ""       // Vector DB type (HNSW, JSON, etc.)
    var chunkingTargetWords: Int = 0    // Target words per chunk
    var chunkingOverlapWords: Int = 0   // Overlap between chunks
    var contextStrategy: String = ""    // Chunking strategy used

    // Per-Stage Timing
    var embeddingElapsed: TimeInterval = 0
    var searchElapsed: TimeInterval = 0
    var generationElapsed: TimeInterval = 0

    // Maximum Mode: Live confidence meter (0-1, shows progress toward 98% threshold)
    var liveConfidence: Float = 0
    var isMaximumMode: Bool = false
    var maximumModeSessionCount: Int = 0
    var liveReasoningTitle: String = ""
    var liveReasoningDetail: String = ""
    var liveReasoningKind: ThinkingEvent.Kind? = nil
    var thinkingEvents: [ThinkingEvent] = []

    // Callbacks
    var onTapDetails: (() -> Void)?

    // State
    @State private var showExpandedDetails = false
    @State private var pulsePhase: CGFloat = 0
    
    // Smooth Drag State
    @State private var autoHeight: CGFloat = 0
    @State private var baseHeight: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    // System state (live monitoring)
    @ObservedObject private var systemMonitor = SystemStateMonitor.shared

    // Computed
    private var contextUsageRatio: Double {
        guard maxContextTokens > 0 else { return 0 }
        return min(1.0, Double(contextTokens) / Double(maxContextTokens))
    }

    private var contextColor: Color {
        if contextUsageRatio > 0.85 { return .red }
        if contextUsageRatio > 0.65 { return .orange }
        return .green
    }

    /// Descriptive label for context showing optimization status
    private var contextDetailLabel: String {
        if hierarchicalChunkingActive && parentChunksUsed > 0 {
            return "\(sourceCount) chunks • \(parentChunksUsed) expanded"
        } else if sourceCount > 0 {
            return "\(contextTokens) tokens • \(sourceCount) chunks"
        } else {
            return "\(contextTokens) of \(maxContextTokens) tokens"
        }
    }

    private var speedColor: Color {
        if tokensPerSecond > 30 { return .green }
        if tokensPerSecond > 15 { return .blue }
        if tokensPerSecond > 5 { return .orange }
        return .red
    }

    private var isReasoningQualityMode: Bool {
        isRecursiveRAG || isMaximumMode
    }

    private var liveTokenMetricColor: Color {
        isReasoningQualityMode ? qualityModeColor : speedColor
    }

    private var tokenCounterColor: Color {
        if isReasoningQualityMode {
            return qualityModeColor
        }
        return tokensGenerated > 0 ? .green : .secondary
    }

    private var tokenCounterIcon: String {
        if isMaximumMode {
            return "flame.fill"
        }
        if isRecursiveRAG {
            return "brain.head.profile"
        }
        return "text.bubble.fill"
    }

    private var wantsCloud: Bool {
        requestedExecutionContext == .preferCloud || requestedExecutionContext == .cloudOnly
    }

    private var cloudFallbackActive: Bool {
        execution == .onDevice && wantsCloud
    }

    private var pccActive: Bool {
        execution == .privateCloudCompute
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main compact strip
            Button {
                withAnimation(DSAnimations.snappySpring) {
                    showExpandedDetails.toggle()
                }
                DSHaptics.selection()
            } label: {
                mainCompactStrip
            }
            .buttonStyle(.plain)

            // Expanded detail panel
            if showExpandedDetails {
                expandedDetailsPanel
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .animation(DSAnimations.snappySpring, value: showExpandedDetails)
        .animation(DSAnimations.fastEase, value: execution)
        .animation(DSAnimations.fastEase, value: stage)
    }

    // MARK: - Main Compact Strip (Premium Two-Row Layout)

    /// Three distinct visual treatments based on quality mode:
    /// - **Standard**: Blue theme, shows "Match" score (retrieval quality), single-pass indicator
    /// - **Deep Think**: Purple/cyan theme, shows "Confidence" building (3 sessions → 85% target)
    /// - **Maximum**: Gold/orange theme, shows "Confidence" meter (unlimited → 98% target)

    private var mainCompactStrip: some View {
        VStack(spacing: DSSpacing.xs) {
            // Row 1: Primary metrics - adapts per mode. The mode's badges at the leading edge and the answer's figures
            // with the chevron at the trailing edge, each group going onto further lines when it does not fit: across
            // one line, up to eight fixed-size badges ran past the screen at the larger text sizes (5.7).
            WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs, lastAtTrailingEdge: true) {
                WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                    // 1. QUALITY MODE BADGE - Distinct per mode
                    premiumQualityBadge

                    // 2. SCORE INDICATOR - Different meaning per mode
                    if sourceCount > 0 || isProcessing {
                        modeAdaptiveScoreBadge
                    }

                    // 3. SESSIONS/PROGRESS - Only for Deep Think/Maximum
                    if isRecursiveRAG || isMaximumMode {
                        modeProgressIndicator
                    }

                    // 4. CONTEXT - Input tokens (only for Standard mode)
                    // Deep Think/Maximum use contextTokens for total agentic tokens, which is redundant
                    // with tokensGenerated - so we hide this badge for those modes
                    if contextTokens > 0 && !isRecursiveRAG && !isMaximumMode {
                        premiumContextBadge
                    }
                }

                WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                    // 5. GENERATION STATS - Speed + output
                    if tokensGenerated > 0 || isProcessing {
                        premiumGenerationBadge
                    }

                    // 6. TIME
                    if elapsedTime > 0 || isProcessing {
                        premiumTimeBadge
                    }

                    // Thermal warning
                    let currentThermal = systemMonitor.currentState.thermalState
                    if currentThermal == .serious || currentThermal == .critical {
                        systemStateBadge
                    }

                    // Expand chevron
                    Image(systemName: showExpandedDetails ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Row 2: Mode-specific detail row
            modeSpecificDetailRow
        }
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                // Mode-colored gradient border
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [qualityModeColor.opacity(0.4), .clear, qualityModeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .contentShape(Rectangle())
    }

    // MARK: - Mode-Specific Detail Row (Row 2)

    @ViewBuilder
    private var modeSpecificDetailRow: some View {
        if shouldShowLiveReasoning {
            liveReasoningDetailRow
        } else if isMaximumMode {
            // MAXIMUM: Show confidence progress bar toward 98% + session count
            maximumModeDetailRow
        } else if isRecursiveRAG {
            // DEEP THINK: Show reasoning chain progress + sparkline
            deepThinkDetailRow
        } else if speedHistory.count > 1 && (isProcessing || tokensGenerated > 0) {
            // STANDARD: Simple sparkline + sources
            standardModeDetailRow
        }
    }

    private var shouldShowLiveReasoning: Bool {
        isProcessing && (!liveReasoningTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !liveReasoningDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var liveReasoningSummary: String {
        let parts = [liveReasoningTitle, liveReasoningDetail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " • ")
    }

    private var liveReasoningAccent: Color {
        switch liveReasoningKind?.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "teal": return .teal
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "pink": return .pink
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return qualityModeColor
        }
    }

    private var liveReasoningDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: liveReasoningKind?.systemIconName ?? qualityMode.icon)
                    .font(.caption2.weight(.semibold))

                Text(isMaximumMode ? "Thinking" : isRecursiveRAG ? "Reasoning" : "Working")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DSColors.primaryText)
            }
            .foregroundStyle(DSColors.readable(liveReasoningAccent))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(liveReasoningAccent.opacity(0.12))
            )

            Text(liveReasoningSummary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DSColors.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 0)

            if isMaximumMode || isRecursiveRAG {
                modeProgressIndicator
            } else if sourceCount > 0 {
                premiumSourcesBadge
            }
        }
    }

    private var standardModeDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            if sourceCount > 0 {
                premiumSourcesBadge
            }

            MiniSparkline(values: speedHistory, color: speedColor)
                .frame(height: 20)

            if toolCallCount > 0 {
                premiumToolsBadge
            }
        }
    }

    private var deepThinkDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            // Sources badge
            if sourceCount > 0 {
                premiumSourcesBadge
            }

            // Speed sparkline (purple for Deep Think)
            if speedHistory.count > 1 {
                MiniSparkline(values: speedHistory, color: .purple)
                    .frame(height: 20)
            }

            Spacer()

            if toolCallCount > 0 {
                premiumToolsBadge
            }
        }
    }

    private var maximumModeDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            // Confidence progress bar toward 98%
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                            .frame(height: 6)

                        // Target marker at 98%
                        Capsule()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: geo.size.width * 0.98, height: 6)

                        // Current progress
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(liveConfidence)), height: 6)
                            .animation(DSAnimations.fastEase, value: liveConfidence)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: 100)

            Spacer()

            if speedHistory.count > 1 {
                MiniSparkline(values: speedHistory, color: .orange)
                    .frame(width: 50, height: 18)
            }

            if sourceCount > 0 {
                premiumSourcesBadge
            }
        }
    }

    // MARK: - Premium Badge: Quality Mode (The Brain)

    private var premiumQualityBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            // Animated brain icon
            ZStack {
                if isProcessing {
                    Circle()
                        .fill(qualityModeColor.opacity(0.2))
                        .frame(width: 18, height: 18)
                        .scaleEffect(1.0 + sin(pulsePhase) * 0.15)
                        .animation(DSAnimations.stagePulse, value: pulsePhase)
                        .onAppear { pulsePhase = .pi * 2 }
                }
                Image(systemName: qualityMode.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DSColors.readable(qualityModeColor))
            }

            Text(qualityModeLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(DSColors.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(
            Capsule()
                .fill(qualityModeColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(qualityModeColor.opacity(0.25), lineWidth: 0.5)
                )
        )
        .fixedSize()
    }

    // MARK: - Premium Badge: Retrieval Quality (Match Score)

    /// Mode-adaptive score badge:
    /// - Standard: "Match" - shows retrieval similarity (how well docs matched query)
    /// - Deep Think: "Confidence" - shows live reasoning confidence building to 85%
    /// - Maximum: "Confidence" - shows live agentic confidence building to 98%
    @ViewBuilder
    private var modeAdaptiveScoreBadge: some View {
        if isMaximumMode {
            // Maximum: Live confidence meter (orange/gold theme)
            maximumConfidenceBadge
        } else if isRecursiveRAG {
            // Deep Think: Live confidence (cyan theme)
            deepThinkConfidenceBadge
        } else {
            // Standard: Retrieval match quality (blue/green theme)
            standardMatchBadge
        }
    }

    private var standardMatchBadge: some View {
        let matchScore = computedMatchScore
        let matchPct = Int(matchScore * 100)
        let matchColor = matchScoreColor(matchScore)

        return HStack(spacing: DSSpacing.xxs) {
            // Circular match indicator
            ZStack {
                Circle()
                    .stroke(matchColor.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(matchScore))
                    .stroke(matchColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
            }

            Text("\(matchPct)%")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(matchColor.opacity(0.1))
        )
        .fixedSize()
    }

    private var deepThinkConfidenceBadge: some View {
        let confidence = liveConfidence > 0 ? liveConfidence : 0.10
        let pct = Int(confidence * 100)
        // The confidence Deep Think aims for on this device (5.7): 0.85 on an A17 Pro up to 0.95 on M-series
        // (`optimizedAgenticConfig`). A fixed 0.85 showed the target reached while a Mac's run kept going.
        let target = DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold
        let targetReached = confidence >= target
        let color: Color = targetReached ? .green : .purple

        return HStack(spacing: DSSpacing.xxs) {
            // Circular confidence indicator
            ZStack {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(min(confidence / target, 1.0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
                    .animation(DSAnimations.fastEase, value: confidence)
            }

            Text("\(pct)%")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            if targetReached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(DSColors.readable(.green))
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
        .fixedSize()
    }

    private var maximumConfidenceBadge: some View {
        let confidence = liveConfidence
        let pct = Int(confidence * 100)
        let targetReached = confidence >= 0.98
        let color: Color = targetReached ? .green : .orange

        return HStack(spacing: DSSpacing.xxs) {
            // Circular confidence indicator
            ZStack {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(min(confidence / 0.98, 1.0)))
                    .stroke(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
                    .animation(DSAnimations.fastEase, value: confidence)
            }

            Text("\(pct)%")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            if targetReached {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(DSColors.readable(.yellow))
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
        .fixedSize()
    }

    // MARK: - Mode Progress Indicator (Sessions/Depth)

    @ViewBuilder
    private var modeProgressIndicator: some View {
        if isMaximumMode {
            // Maximum: Unlimited sessions indicator
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "infinity")
                    .font(.caption2.weight(.bold))
                if maximumModeSessionCount > 0 {
                    Text("×\(maximumModeSessionCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }
            }
            .foregroundStyle(DSColors.readable(.orange))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.12))
            )
            .fixedSize()
        } else if isRecursiveRAG {
            // Deep Think: session count (no max - it goes until confident)
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "brain.head.profile")
                    .font(.caption2.weight(.semibold))
                Text("×\(recursiveCallCount)")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
            }
            .foregroundStyle(DSColors.readable(.purple))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.12))
            )
            .fixedSize()
        }
    }

    /// Computed match score from retrieval similarity, rescaled for user comprehension.
    /// The cross-encoder reranker normalizes scores to 0.10-0.90 range (MS-MARCO model).
    /// A score of 0.90 means "perfect match" but shows as 90% which confuses users.
    /// We rescale: (score - 0.10) / 0.80 → maps 0.10→0%, 0.50→50%, 0.90→100%
    private var computedMatchScore: Float {
        // Use actual retrieval quality metrics
        if topSimilarity > 0 {
            // Rescale reranker scores from [0.10, 0.90] to [0, 1] for intuitive display
            // This makes 0.90 (max reranker score) show as 100%
            let rescaled = max(0, (topSimilarity - 0.10) / 0.80)
            return min(1.0, rescaled)  // Cap at 100%
        } else if let avg = averageSourceScore, avg > 0 {
            // Also rescale averages from reranker
            let rescaled = max(0, (avg - 0.10) / 0.80)
            return min(1.0, rescaled)
        } else if sourceCount > 0 {
            return 0.5  // Default if we have sources but no score
        }
        return 0
    }

    private func matchScoreColor(_ score: Float) -> Color {
        if score >= 0.75 { return .green }
        if score >= 0.55 { return .blue }
        if score >= 0.35 { return .orange }
        return .red
    }

    // MARK: - Premium Badge: Sessions (Reasoning Depth)

    private var premiumSessionsBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "brain.head.profile")
                .font(.caption2.weight(.semibold))
            Text("×\(recursiveCallCount)")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(.purple))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 0.5)
                )
        )
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Premium Badge: Context (Input Tokens)

    private var premiumContextBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.caption2.weight(.semibold))
            Text(formatTokenCount(contextTokens))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(contextColor))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(contextColor.opacity(0.1))
        )
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Premium Badge: Generation (Speed + Output + Words)

    private var premiumGenerationBadge: some View {
        HStack(spacing: DSSpacing.xs) {
            // Speed metric
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.bold))
                Text(String(format: "%.0f", tokensPerSecond))
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
                Text("t/s")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DSColors.primaryText)
                    .opacity(0.7)
            }
            .foregroundStyle(DSColors.readable(liveTokenMetricColor))
            .lineLimit(1)
            .fixedSize()

            // Divider + Output tokens
            if tokensGenerated > 0 || isProcessing {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 10)

                // Output token count
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: tokenCounterIcon)
                        .font(.caption2.weight(.semibold))
                    Text(formatTokenCount(tokensGenerated))
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }
                .foregroundStyle(DSColors.readable(tokenCounterColor))
                .lineLimit(1)
                .fixedSize()
            }

            // Cumulative word count (the big number!)
            if characterCount > 0 {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 10)

                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.caption2.weight(.semibold))
                    Text(formatLargeCount(characterCount))
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }
                .foregroundStyle(DSColors.readable(.purple))
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(liveTokenMetricColor.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(liveTokenMetricColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Premium Badge: Time

    private var premiumTimeBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: isProcessing ? "hourglass" : "checkmark.circle.fill")
                .font(.caption2.weight(.medium))
                .symbolEffect(.pulse, isActive: isProcessing)
            Text(formatElapsed(elapsedTime))
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(isProcessing ? .orange : .green))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill((isProcessing ? Color.orange : Color.green).opacity(0.1))
        )
        .fixedSize()
    }

    // MARK: - Premium Badge: Sources (Row 2)

    private var premiumSourcesBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption2.weight(.semibold))
            Text("\(sourceCount)")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(sourceQualityColor))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(sourceQualityColor.opacity(0.1))
        )
        .fixedSize()
    }

    // MARK: - Premium Badge: Tools (Row 2)

    private var premiumToolsBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption2.weight(.semibold))
            Text("\(toolCallCount)")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(.purple))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.12))
        )
    }

    // MARK: - Legacy Badges (kept for expanded view compatibility)

    private var qualityBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: qualityMode.icon)
                .font(.caption2.weight(.semibold))
            Text(qualityModeLabel)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(qualityModeColor)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(qualityModeColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var qualityModeLabel: String {
        switch qualityMode.canonical {
        case .standard: return "Standard"
        case .deepThink: return "Deep Think"
        case .maximum: return "Maximum"
        default: return "Standard"
        }
    }

    // MARK: - Descriptive Advanced RAG Badge

    private var advancedRAGBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.semibold))
            Text(advancedRAGLabelDescriptive)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.yellow.opacity(0.12))
        .clipShape(Capsule())
    }

    private var advancedRAGLabelDescriptive: String {
        var parts: [String] = []
        if hierarchicalChunkingActive { parts.append("Hierarchical") }
        if graphExpansionActive { parts.append("Graph") }
        if parts.isEmpty { return "Enhanced" }
        return parts.joined(separator: " + ")
    }

    // MARK: - Elapsed Time Badge

    private var elapsedTimeBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: isProcessing ? "timer" : "checkmark.circle.fill")
                .font(.caption2.weight(.medium))
            Text(formatElapsed(elapsedTime))
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .monospacedDigit()
            if !isProcessing {
                Text("done")
                    .font(.caption2.weight(.medium))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(isProcessing ? .orange : .green)
    }

    // MARK: - Descriptive Context Gauge

    private var contextGaugeDescriptive: some View {
        // For Deep Think: Context window is IRRELEVANT - we chain multiple sessions
        if isRecursiveRAG {
            return AnyView(
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "arrow.trianglehead.branch")
                        .font(.caption2.weight(.semibold))
                    if recursiveCallCount > 0 {
                        Text("\(recursiveCallCount) sessions")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    if contextTokens > 0 {
                        Text("• \(formatTokenCount(contextTokens)) tokens")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.purple.opacity(0.12))
                .clipShape(Capsule())
            )
        }

        // Standard mode: show context with label
        return AnyView(
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "doc.viewfinder")
                    .font(.caption2.weight(.semibold))
                Text("Context:")
                    .font(.caption2.weight(.medium))
                    .opacity(0.7)
                Text(formatTokenCount(contextTokens))
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .monospacedDigit()
                Text("tokens")
                    .font(.caption2.weight(.medium))
                    .opacity(0.6)
            }
            .foregroundStyle(contextColor)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(contextColor.opacity(0.1))
            .clipShape(Capsule())
        )
    }

    // MARK: - Descriptive Speed Badge

    private var speedBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "gauge.with.needle.fill")
                .font(.caption2.weight(.semibold))
            Text("Speed:")
                .font(.caption2.weight(.medium))
                .opacity(0.7)
            Text(String(format: "%.0f", tokensPerSecond))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
            Text("t/s")
                .font(.caption2.weight(.medium))
                .opacity(0.6)
        }
        .foregroundStyle(speedColor)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(speedColor.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Descriptive Output Tokens Badge

    private var outputTokensBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "text.bubble.fill")
                .font(.caption2.weight(.semibold))
            Text("Output:")
                .font(.caption2.weight(.medium))
                .opacity(0.7)
            Text(formatTokenCount(tokensGenerated))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
            Text("tokens")
                .font(.caption2.weight(.medium))
                .opacity(0.6)
        }
        .foregroundStyle(.green)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Descriptive Sources Badge

    private var sourcesBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "doc.text.fill")
                .font(.caption2.weight(.semibold))
            Text("\(sourceCount)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
            Text(sourceCount == 1 ? "source" : "sources")
                .font(.caption2.weight(.medium))
                .opacity(0.7)
            // Show quality indicator
            if let score = averageSourceScore {
                Text("•")
                    .font(.caption2)
                    .opacity(0.5)
                Text(sourceQualityLabel(score))
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(sourceQualityColor)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(sourceQualityColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private func sourceQualityLabel(_ score: Float) -> String {
        if score > 0.7 { return "excellent" }
        if score > 0.5 { return "good" }
        if score > 0.3 { return "fair" }
        return "weak"
    }

    // MARK: - Descriptive Tool Call Badge

    private var toolCallBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "function")
                .font(.caption2.weight(.semibold))
            Text("\(toolCallCount)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
            Text(toolCallCount == 1 ? "tool call" : "tool calls")
                .font(.caption2.weight(.medium))
                .opacity(0.7)
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.purple.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Output Tokens Badge (LLM response size)

    private var outputTokensBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "text.bubble.fill")
                .font(.caption2.weight(.semibold))
            Text(formatTokenCount(tokensGenerated))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(.green)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Character Count Badge

    private var characterCountBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "textformat.size")
                .font(.caption2.weight(.semibold))
            Text(formatCount(characterCount))
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(DSColors.secondaryText)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Badges

    /// Clean execution badge showing Neural Engine or PCC with real chip specs
    private var executionBadge: some View {
        let device = DeviceCapabilityService.shared

        return HStack(spacing: DSSpacing.xs) {
            ZStack {
                // Pulse animation during generation
                if isProcessing && stage == .generating {
                    Circle()
                        .fill(executionBadgeColor.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .scaleEffect(pulsePhase)
                        .opacity(Double(1.0 - pulsePhase * 0.5))
                        .onAppear {
                            withAnimation(DSAnimations.stagePulse) {
                                pulsePhase = 1.5
                            }
                        }
                }

                Image(systemName: executionBadgeIcon)
                    .font(.caption2.weight(.semibold))
            }

            // Clean label: "Neural Engine" for on-device, "PCC" for cloud
            Text(executionBadgeLabel)
                .font(.caption2.weight(.semibold))

            // Chip specs for on-device (e.g., "A18 Pro • 38T")
            if execution == .onDevice || (execution == .unknown && !isProcessing) {
                Text("•")
                    .font(.caption2)
                    .opacity(0.4)
                Text("\(device.chipName)")
                    .font(.caption2.weight(.medium))
                    .opacity(0.8)
                Text("\(Int(device.memoryGB))GB")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .opacity(0.7)
                // Show Neural Engine TOPS for visual confirmation
                Text("\(device.npuTops)T")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .opacity(0.6)
            }

            // TTFT when available (only during processing)
            if isProcessing, let t = ttft {
                Text("•")
                    .font(.caption2)
                    .opacity(0.5)
                Text(formatDuration(t))
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(executionBadgeColor)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(executionBadgeColor.opacity(0.12))
        .clipShape(Capsule())
        .onChange(of: isProcessing) { _, newValue in
            if !newValue {
                pulsePhase = 0
            }
        }
    }

    private var executionBadgeIcon: String {
        switch execution {
        case .onDevice, .unknown: return "cpu"  // Neural Engine icon
        case .privateCloudCompute: return "cloud.fill"
        }
    }

    private var executionBadgeLabel: String {
        switch execution {
        case .onDevice, .unknown: return "NE"
        case .privateCloudCompute: return "PC"
        }
    }

    private var executionBadgeColor: Color {
        switch execution {
        case .onDevice, .unknown: return .green  // On-device is always green (private)
        case .privateCloudCompute: return .blue
        }
    }

    private var stageBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            // Pulsing dot when LLM is actively generating (from session.isResponding)
            if isLLMActivelyGenerating, stage == .generating {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulsePhase == 1 ? 1.3 : 0.8)
                    .opacity(pulsePhase == 1 ? 1.0 : 0.6)
                    .animation(
                        DSAnimations.stagePulse,
                        value: pulsePhase
                    )
                    .onAppear { pulsePhase = 1 }
            }

            Image(systemName: stage.icon)
                .font(.caption2.weight(.medium))
            Text(stage.description)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(stageColor)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(stageColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var stageColor: Color {
        switch stage {
        case .idle, .complete: return .secondary
        case .embedding: return .purple
        case .searching: return .blue
        case .generating: return .green
        }
    }

    private var contextGauge: some View {
        // For Deep Think: Context window is IRRELEVANT - we chain multiple sessions
        // Just show total tokens used across all sessions
        if isRecursiveRAG {
            return AnyView(
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "arrow.trianglehead.branch")
                        .font(.caption2.weight(.semibold))

                    // Show sessions count (this is what matters)
                    if recursiveCallCount > 0 {
                        Text("\(recursiveCallCount)×")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                    }

                    // Total tokens (summed across all sessions)
                    if contextTokens > 0 {
                        Text(formatTokenCount(contextTokens))
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                    } else {
                        Text("...")
                            .font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.purple.opacity(0.12))
                .clipShape(Capsule())
            )
        }

        // Standard mode: show token count with context-appropriate icon
        // Using doc.viewfinder to represent "retrieved context"
        return AnyView(
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "doc.viewfinder")
                    .font(.caption2.weight(.semibold))
                if contextTokens > 0 {
                    Text(formatTokenCount(contextTokens))
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.caption2.weight(.medium))
                }
            }
            .foregroundStyle(contextColor)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(contextColor.opacity(0.1))
            .clipShape(Capsule())
        )
    }

    /// Format token count with K suffix for large numbers
    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 10000 {
            return String(format: "%.1fK", Double(tokens) / 1000.0)
        } else if tokens >= 1000 {
            return "\(tokens / 1000).\((tokens % 1000) / 100)K"
        }
        return "\(tokens)"
    }

    /// Format large counts (characters/words) with K suffix - shows big numbers like 40.2K
    private func formatLargeCount(_ count: Int) -> String {
        if count >= 100000 {
            return String(format: "%.0fK", Double(count) / 1000.0)
        } else if count >= 10000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private var speedBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "gauge.with.needle.fill")
                .font(.caption2.weight(.semibold))
            Text(String(format: "%.0f", tokensPerSecond))
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .monospacedDigit()
            Text("t/s")
                .font(.caption2.weight(.medium))
                .opacity(0.7)
        }
        .foregroundStyle(speedColor)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(speedColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var sourcesBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "doc.text.fill")
                .font(.caption2.weight(.semibold))
            Text("\(sourceCount)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(sourceQualityColor)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(sourceQualityColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var coverageBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption2.weight(.semibold))
            Text("\(coveredDocuments)/\(totalDocuments)")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.blue.opacity(0.12))
        .clipShape(Capsule())
    }

    // pccActiveBadge removed - executionBadge already shows "PCC" when active

    private var cloudFallbackBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "cloud.slash")
                .font(.caption2.weight(.semibold))
            Text("Local Fallback")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Advanced RAG Badge (compact indicator for enhanced features)

    private var advancedRAGBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.semibold))
            Text(advancedRAGLabel)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.yellow.opacity(0.12))
        .clipShape(Capsule())
    }

    private var advancedRAGLabel: String {
        var parts: [String] = []
        if hierarchicalChunkingActive { parts.append("H") }
        if graphExpansionActive { parts.append("G") }
        if !queryIntent.isEmpty { parts.append(queryIntent.prefix(3).uppercased()) }
        return parts.isEmpty ? "RAG+" : parts.joined(separator: "·")
    }

    // MARK: - RAG Mode Badge

    private var ragModeBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: retrievalMode.icon)
                .font(.caption2.weight(.semibold))
            Text(retrievalMode.rawValue)
                .font(.caption2.weight(.semibold))
            if semanticChunksUsed {
                Text("•")
                    .font(.caption2)
                    .opacity(0.5)
                Image(systemName: "brain")
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(retrievalMode.color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(retrievalMode.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var sourceQualityColor: Color {
        guard let score = averageSourceScore else { return .purple }
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }

    private var qualityBadge: some View {
        // Show quality mode icon with appropriate color
        Image(systemName: qualityMode.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(qualityModeColor.opacity(0.8))
            .padding(DSSpacing.xxs)
            .background(qualityModeColor.opacity(0.08))
            .clipShape(Circle())
    }

    /// Mode-specific theme colors:
    /// - Standard: Blue (fast, efficient, single-pass)
    /// - Deep Think: Purple (analytical, multi-session reasoning)
    /// - Maximum: Orange/Gold (premium, unlimited, thorough)
    private var qualityModeColor: Color {
        switch qualityMode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .blue
        }
    }

    // MARK: - Universal Confidence Badge (All Modes)

    /// Computed confidence based on quality mode:
    /// - Standard: NOT USED - we show "match score" instead (retrieval quality)
    /// - Deep Think: Live confidence from reasoning chain (builds toward 85%)
    /// - Maximum: Live agentic confidence (builds toward 98%)
    private var computedConfidence: Float {
        if isMaximumMode {
            // Maximum mode: Use live confidence from agentic orchestrator
            return liveConfidence
        } else if isRecursiveRAG {
            // Deep Think: ALWAYS use live confidence from reasoning chain
            // This ensures header matches chat log (23% → 31% → etc.)
            // Start at 10% before first session completes (matches reasoning chain initial value)
            return liveConfidence > 0 ? liveConfidence : 0.10
        } else {
            // Standard mode: Return raw retrieval similarity
            // This is used by the legacy confidence badge (universalConfidenceBadge)
            // The new premiumRetrievalBadge uses computedMatchScore instead
            return topSimilarity > 0 ? topSimilarity : 0.5
        }
    }

    /// Universal confidence badge that adapts to quality mode
    private var universalConfidenceBadge: some View {
        let confidence = computedConfidence
        let confidencePercent = Int(confidence * 100)
        let badgeColor = confidenceColorFor(confidence)

        // Different thresholds per mode
        let targetReached: Bool = {
            if isMaximumMode { return confidence >= 0.98 }
            if isRecursiveRAG { return confidence >= 0.85 }
            return confidence >= 0.70  // Standard: 70%+ is solid
        }()

        return HStack(spacing: DSSpacing.xxs) {
            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(badgeColor.opacity(0.2), lineWidth: 2)
                    .frame(width: 14, height: 14)

                Circle()
                    .trim(from: 0, to: CGFloat(confidence))
                    .stroke(
                        badgeColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(-90))
                    .animation(DSAnimations.fastEase, value: confidence)
            }

            // Confidence label + percentage
            Text("Confidence:")
                .font(.caption2.weight(.medium))
                .opacity(0.7)
            Text("\(confidencePercent)%")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(badgeColor)

            // Target indicator (mode-appropriate)
            if targetReached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(badgeColor.opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    /// Color for confidence based on value (mode-agnostic)
    private func confidenceColorFor(_ confidence: Float) -> Color {
        if confidence >= 0.85 { return .green }
        if confidence >= 0.65 { return .yellow }
        if confidence >= 0.40 { return .orange }
        return .red
    }

    // MARK: - System State Badge

    /// Compact system state indicator showing thermal/battery/memory status
    @ViewBuilder
    private var systemStateBadge: some View {
        let state = systemMonitor.currentState
        let thermalColor = systemStateThermalColor(state.thermalState)

        // Always show thermal indicator (it's useful info about device state)
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: SystemStateMonitor.thermalIcon(for: state.thermalState))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(DSColors.readable(thermalColor))
        .padding(DSSpacing.xs)
        .background(thermalColor.opacity(0.1))
        .clipShape(Circle())
    }

    private func systemStateThermalColor(_ thermal: ProcessInfo.ThermalState) -> Color {
        switch thermal {
        case .nominal: return .green
        case .fair: return .blue
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private var toolCallBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "function")
                .font(.caption2.weight(.semibold))
            Text("\(toolCallCount)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.purple.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Micro Metric

    private func microMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DSColors.secondaryText)
            Text(value)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
            if !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(DSColors.secondaryText.opacity(0.7))
            }
        }
    }

// MARK: - Expanded Panel (Streamlined for This Query)

    private var expandedDetailsPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Section 1: Library Context (what knowledge base)
                    if !containerName.isEmpty {
                        libraryContextSection
                    }

                    // Section 2: Query Understanding (how we interpreted the question)
                    if !originalQuery.isEmpty || stage == .embedding || stage == .searching {
                        queryUnderstandingSection
                    }

                    // Section 3: Mode-Specific Reasoning (what THIS mode did)
                    modeSpecificReasoningSection

                    // Section 4: Pipeline Journey (the actual funnel for THIS query)
                    if candidatesCount > 0 || totalStoredChunks > 0 {
                        pipelineJourneySection
                    }

                    // Section 5: Quality Signals (how good was the retrieval)
                    if topSimilarity > 0 || averageSourceScore != nil {
                        qualitySignalsSection
                    }

                    // Section 6: Token Budget (how context was allocated)
                    if baseWindowTokens > 0 {
                        tokenBudgetSection
                    }

                    // Section 7: Where It Ran (only post-generation)
                    if !isProcessing {
                        whereRunningSection
                    }

                    // Section 8: Agentic Tools (only if tools were used - this IS dynamic per query)
                    if !isProcessing {
                        agenticToolsSection
                    }
                }
            }
            
            // Native Resizable Drawer Handle
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                Spacer()
            }
            .frame(height: 21)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { val in
                        if !isDragging {
                            isDragging = true
                            // Capture the exact height instantly only if we haven't already
                            if baseHeight == 0 {
                                baseHeight = autoHeight
                            }
                        }
                        dragOffset = val.translation.height
                    }
                    .onEnded { val in
                        baseHeight = max(150, baseHeight + val.translation.height)
                        dragOffset = 0
                        isDragging = false
                    }
            )
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.height) { _, newHeight in
                        // Constantly track intrinsic height when not being manually forced
                        if baseHeight == 0 {
                            autoHeight = newHeight
                        }
                    }
                    .onAppear {
                        if baseHeight == 0 {
                            autoHeight = geo.size.height
                        }
                    }
            }
        )
        .frame(height: baseHeight > 0 ? max(150, baseHeight + dragOffset) : nil)
        // Auto-reset manual height when system finishes processing so it can auto-size the new tools section
        .onChange(of: isProcessing) {
            baseHeight = 0
            isDragging = false
        }
        #if os(iOS)
        .frame(maxHeight: 1000) // Massive expansion limit for demos without triggering UIScreen deprecation warnings
        #else
        .frame(maxHeight: 650)
        #endif
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .padding(.top, DSSpacing.xs)
    }

    // MARK: - Section: Library Context (NEW)

    private var libraryContextSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "books.vertical.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
                Text("Knowledge Base")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                // Library name
                HStack(spacing: DSSpacing.sm) {
                    Text(containerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColors.primaryText)

                    Spacer()

                    // Chunk stats
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                        Text("\(totalStoredChunks) chunks")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                // Technical specs row
                HStack(spacing: DSSpacing.md) {
                    if embeddingDim > 0 {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "cube.fill")
                                .font(.caption2)
                            Text("\(embeddingDim)-dim")
                                .font(.system(.caption2, design: .monospaced).weight(.medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(DSColors.secondaryText)
                    }

                    if !vectorDBKind.isEmpty {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "cylinder.fill")
                                .font(.caption2)
                            Text(vectorDBKind)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(DSColors.secondaryText)
                    }

                    if chunkingTargetWords > 0 {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "text.justify.left")
                                .font(.caption2)
                            Text("~\(chunkingTargetWords)w/chunk")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .background(Color.teal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    // MARK: - Section: Pipeline Journey (NEW - Chunk Funnel)

    private var pipelineJourneySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "arrow.down.right.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text("Pipeline Journey")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("chunk selection funnel")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Visual funnel
            VStack(spacing: DSSpacing.xs) {
                pipelineFunnelRow(
                    label: "Vector Store",
                    count: totalStoredChunks,
                    icon: "cylinder.fill",
                    color: .gray,
                    widthRatio: 1.0
                )

                if candidatesCount > 0 {
                    pipelineFunnelRow(
                        label: "Retrieved",
                        count: candidatesCount,
                        icon: "magnifyingglass",
                        color: .blue,
                        widthRatio: min(1.0, Double(candidatesCount) / max(1, Double(totalStoredChunks)) * 20)
                    )
                }

                if rerankedCount > 0 && rerankedCount != candidatesCount {
                    pipelineFunnelRow(
                        label: "Reranked",
                        count: rerankedCount,
                        icon: "arrow.up.arrow.down",
                        color: .purple,
                        widthRatio: candidatesCount > 0 ? Double(rerankedCount) / Double(candidatesCount) : 0.8
                    )
                }

                if filteredCount > 0 {
                    pipelineFunnelRow(
                        label: "Quality Filtered",
                        count: filteredCount,
                        icon: "line.3.horizontal.decrease",
                        color: .orange,
                        widthRatio: candidatesCount > 0 ? Double(filteredCount) / Double(candidatesCount) : 0.6
                    )
                }

                if mmrSelectedCount > 0 {
                    pipelineFunnelRow(
                        label: "MMR Diversified",
                        count: mmrSelectedCount,
                        icon: "shuffle",
                        color: .green,
                        widthRatio: candidatesCount > 0 ? Double(mmrSelectedCount) / Double(candidatesCount) : 0.4
                    )
                }

                // Final usage
                pipelineFunnelRow(
                    label: "Used in Prompt",
                    count: sourceCount,
                    icon: "checkmark.circle.fill",
                    color: .green,
                    widthRatio: candidatesCount > 0 ? Double(sourceCount) / Double(candidatesCount) : 0.3,
                    isHighlighted: true
                )

                if droppedCount > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.6))
                        Text("\(droppedCount) dropped (low similarity)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .padding(.top, DSSpacing.xs)
                }

                if uniqueDocCount > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                        Text("from \(uniqueDocCount) unique documents")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    .padding(.top, DSSpacing.xxs)
                }
            }
            .padding(DSSpacing.sm)
            .background(Color.cyan.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    private func pipelineFunnelRow(
        label: String,
        count: Int,
        icon: String,
        color: Color,
        widthRatio: Double,
        isHighlighted: Bool = false
    ) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
                .frame(width: 14)

            Text(label)
                .font(.caption2.weight(isHighlighted ? .semibold : .regular))
                .foregroundStyle(isHighlighted ? DSColors.primaryText : DSColors.secondaryText)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(isHighlighted ? 1.0 : 0.6))
                    .frame(width: max(4, geo.size.width * min(1.0, max(0.1, widthRatio))))
            }
            .frame(height: 6)

            Text("\(count)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - Section: Token Budget (NEW)

    private var tokenBudgetSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "chart.pie.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)
                Text("Token Budget")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("\(baseWindowTokens) window")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: DSSpacing.xs) {
                tokenBudgetRow(label: "Base Window", value: baseWindowTokens, color: .gray, isTotal: true)
                tokenBudgetRow(label: "− Safety Margin", value: -safetyTokens, color: .red)
                tokenBudgetRow(label: "− Prompt Overhead", value: -promptOverheadTokens, color: .orange)
                tokenBudgetRow(label: "− Question Tokens", value: -questionTokens, color: .purple)
                tokenBudgetRow(label: "− Reserved Output", value: -reservedOutputTokens, color: .blue)

                Divider()

                tokenBudgetRow(label: "= Available for Context", value: availableContextTokens, color: .green, isResult: true)
                tokenBudgetRow(label: "  Actually Used", value: contextTokens, color: .teal, isHighlighted: true)
            }
            .padding(DSSpacing.sm)
            .background(Color.mint.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    private func tokenBudgetRow(
        label: String,
        value: Int,
        color: Color,
        isTotal: Bool = false,
        isResult: Bool = false,
        isHighlighted: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption2.weight(isResult || isHighlighted ? .semibold : .regular))
                .foregroundStyle(isResult || isHighlighted ? DSColors.primaryText : DSColors.secondaryText)

            Spacer()

            Text(value >= 0 ? "\(value)" : "\(abs(value))")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: - Section: Confidence Metrics (NEW)

    private var confidenceMetricsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                Text("Confidence & Quality")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                if lenientRetrieval {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.caption2)
                        Text("Lenient")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            VStack(spacing: DSSpacing.sm) {
                // Similarity scores
                HStack(spacing: DSSpacing.lg) {
                    VStack(alignment: .center, spacing: DSSpacing.xxs) {
                        Text(String(format: "%.1f%%", topSimilarity * 100))
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(similarityColor(topSimilarity))
                        Text("Top Match")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)

                    if secondSimilarity > 0 {
                        VStack(alignment: .center, spacing: DSSpacing.xxs) {
                            Text(String(format: "%.1f%%", secondSimilarity * 100))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(similarityColor(secondSimilarity))
                            Text("2nd Best")
                                .font(.caption2)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if avgTop5Similarity > 0 {
                        VStack(alignment: .center, spacing: DSSpacing.xxs) {
                            Text(String(format: "%.1f%%", avgTop5Similarity * 100))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(similarityColor(avgTop5Similarity))
                            Text("Avg Top 5")
                                .font(.caption2)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Threshold info
                if dynamicMinThreshold > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "line.horizontal.3.decrease")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                        Text("Dynamic threshold: \(String(format: "%.1f%%", dynamicMinThreshold * 100))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)

                        if acceptanceOverride {
                            Text("• Override active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(DSSpacing.sm)
            .background(Color.yellow.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    private func similarityColor(_ similarity: Float) -> Color {
        if similarity >= 0.8 { return .green }
        if similarity >= 0.6 { return .blue }
        if similarity >= 0.4 { return .orange }
        return .red
    }

    // MARK: - Section: Timing Breakdown (NEW)

    private var timingBreakdownSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                Text("Timing Breakdown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                let totalTime = embeddingElapsed + searchElapsed + max(generationElapsed, elapsedTime)
                if totalTime > 0 {
                    Text(String(format: "%.1fs total", totalTime))
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: DSSpacing.xs) {
                // Visual timeline
                let total = embeddingElapsed + searchElapsed + max(generationElapsed, elapsedTime)
                if total > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            if embeddingElapsed > 0 {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.blue)
                                    .frame(width: geo.size.width * CGFloat(embeddingElapsed / total))
                            }
                            if searchElapsed > 0 {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.purple)
                                    .frame(width: geo.size.width * CGFloat(searchElapsed / total))
                            }
                            let genTime = max(generationElapsed, elapsedTime)
                            if genTime > 0 {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * CGFloat(genTime / total))
                            }
                        }
                    }
                    .frame(height: 8)
                    .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                }

                // Legend
                HStack(spacing: DSSpacing.lg) {
                    if embeddingElapsed > 0 {
                        HStack(spacing: DSSpacing.xs) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("Embed: \(formatDuration(embeddingElapsed))")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    if searchElapsed > 0 {
                        HStack(spacing: DSSpacing.xs) {
                            Circle().fill(Color.purple).frame(width: 8, height: 8)
                            Text("Search: \(formatDuration(searchElapsed))")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    let genTime = max(generationElapsed, elapsedTime)
                    if genTime > 0 {
                        HStack(spacing: DSSpacing.xs) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("Generate: \(formatDuration(genTime))")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }

                // TTFT if available
                if let ttft = ttft, ttft > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("Time to first token: \(formatDuration(ttft))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .background(Color.pink.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    // MARK: - Section: Mode-Specific Reasoning

    @ViewBuilder
    private var modeSpecificReasoningSection: some View {
        if isMaximumMode {
            maximumModeReasoningSection
        } else if isRecursiveRAG {
            deepThinkReasoningSection
        } else {
            standardModeReasoningSection
        }
    }

    private var standardModeReasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("Standard Retrieval")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("single-pass")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }

            // What techniques were used
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // Hybrid search weights
                HStack(spacing: DSSpacing.lg) {
                    HStack(spacing: DSSpacing.xs) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("Semantic: \(Int(vectorWeight * 100))%")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    HStack(spacing: DSSpacing.xs) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Keyword: \(Int(lexicalWeight * 100))%")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(DSColors.secondaryText)

                // Active techniques
                HStack(spacing: DSSpacing.sm) {
                    if hydeEnabled {
                        techniquePill(icon: "wand.and.stars", text: "HyDE", color: .purple)
                    }
                    if hierarchicalChunkingActive {
                        techniquePill(icon: "doc.on.doc", text: "Parent Expansion", color: .teal)
                    }
                    if siblingChunksAdded > 0 {
                        techniquePill(icon: "arrow.left.arrow.right", text: "+\(siblingChunksAdded) siblings", color: .cyan)
                    }
                    if lenientRetrieval {
                        techniquePill(icon: "hand.thumbsup", text: "Lenient", color: .orange)
                    }
                }
            }

            ThinkingStreamView(events: thinkingEvents, qualityMode: qualityMode)
        }
        .padding(DSSpacing.md)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var deepThinkReasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("Deep Think Reasoning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("multi-session")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Session info
            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("\(recursiveCallCount)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.purple)
                    Text("reasoning sessions")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                }

                if liveConfidence > 0 || !isProcessing {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(Int(liveConfidence * 100))%")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(liveConfidence >= 0.85 ? .green : .purple)
                        Text("final confidence")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                if contextTokens > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(formatTokenCount(contextTokens))
                            .font(.system(.headline, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.purple)
                        Text("total tokens")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Techniques used
            HStack(spacing: DSSpacing.sm) {
                techniquePill(icon: "arrow.triangle.branch", text: "Multi-Query", color: .purple)
                if graphExpansionActive {
                    techniquePill(icon: "point.3.connected.trianglepath.dotted", text: "Graph Expansion", color: .indigo)
                }
                if graphEntitiesExtracted > 0 {
                    techniquePill(icon: "tag.fill", text: "\(graphEntitiesExtracted) entities", color: .teal)
                }
            }

            ThinkingStreamView(events: thinkingEvents, qualityMode: qualityMode)
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var maximumModeReasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Maximum Reasoning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                // Was "unlimited": Maximum stops at 50 sessions, fewer when few passages match (5.7).
                Text("up to 50")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Session info - bigger numbers for Maximum
            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("\(maximumModeSessionCount)")
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Text("reasoning sessions")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                }

                // Confidence with progress to 98%
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xs) {
                        Text("\(Int(liveConfidence * 100))%")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(liveConfidence >= 0.98 ? .green : .orange)
                        Text("/ 98%")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    Text(liveConfidence >= 0.98 ? "target reached!" : "confidence target")
                        .font(.caption2)
                        .foregroundStyle(liveConfidence >= 0.98 ? .green : DSColors.secondaryText)
                }

                Spacer()

                if contextTokens > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(formatTokenCount(contextTokens))
                            .font(.system(.headline, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                        Text("total tokens")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Maximum mode techniques
            HStack(spacing: DSSpacing.sm) {
                techniquePill(icon: "arrow.triangle.branch", text: "Multi-Query", color: .orange)
                techniquePill(icon: "repeat", text: "Iterative Refinement", color: .yellow)
                if graphExpansionActive {
                    techniquePill(icon: "point.3.connected.trianglepath.dotted", text: "Graph", color: .indigo)
                }
            }

            ThinkingStreamView(events: thinkingEvents, qualityMode: qualityMode)
        }
        .padding(DSSpacing.md)
        .background(
            LinearGradient(colors: [.orange.opacity(0.08), .yellow.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func techniquePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Section: Quality Signals

    private var qualitySignalsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Confidence & Quality")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            HStack(spacing: DSSpacing.lg) {
                // Top match score
                if topSimilarity > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xs) {
                            Text("\(Int(topSimilarity * 100))%")
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(matchScoreColor(topSimilarity))
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text("best match")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                // Second best (gap indicates confidence)
                if secondSimilarity > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(Int(secondSimilarity * 100))%")
                            .font(.callout.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(matchScoreColor(secondSimilarity))
                        Text("2nd best")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                // Average of top results
                if avgTop5Similarity > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(Int(avgTop5Similarity * 100))%")
                            .font(.callout.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(matchScoreColor(avgTop5Similarity))
                        Text("avg top 5")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                // MMR diversity used
                if mmrDiversity > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text("λ=\(String(format: "%.1f", mmrDiversity))")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.teal)
                        Text("diversity")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else {
            return String(format: "%.1fs", seconds)
        }
    }

    // MARK: - Section: Query Understanding

    private var queryUnderstandingSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "text.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Text("Query Understanding")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                if hydeEnabled {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption2)
                        Text("HyDE Active")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Original query (full, not truncated)
            if !originalQuery.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("You asked:")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DSColors.secondaryText)
                    Text(originalQuery)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true) // Full text, never truncate
                }
            }

            // Rewritten/clarified query (if different)
            if !rewrittenQuery.isEmpty && rewrittenQuery != originalQuery {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Clarified to:")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    Text(rewrittenQuery)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpacing.sm)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
            }

            // Extracted keywords & intent
            HStack(spacing: DSSpacing.md) {
                // Keywords
                if !extractedKeywords.isEmpty {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Key terms extracted:")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DSColors.secondaryText)
                        FlowLayout(spacing: DSSpacing.xxs) {
                            ForEach(extractedKeywords.prefix(8), id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, DSSpacing.sm)
                                    .padding(.vertical, DSSpacing.xxs)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                // Query expansions
                if expansionCount > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text("\(expansionCount)")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.purple)
                        Text("query variations")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Intent classification
            if !queryIntent.isEmpty {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Detected intent: \(queryIntent)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DSColors.primaryText)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: Search Results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("Search Results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Best match info (if available)
            if topMatchScore > 0 {
                HStack(spacing: DSSpacing.md) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text("Best Match")
                                .font(.caption.weight(.semibold))
                        }
                        if !topMatchSource.isEmpty {
                            Text(topMatchSource)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DSColors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("\(Int(topMatchScore * 100))% vector similarity")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(matchScoreColor(topMatchScore))
                            Text("Database match vs. LLM confidence")
                                .font(.caption2)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    Spacer()

                    // Relevance gauge
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(topMatchScore))
                            .stroke(matchScoreColor(topMatchScore), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(topMatchScore * 100))")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(matchScoreColor(topMatchScore))
                    }
                    .frame(width: 40, height: 40)
                }
                .padding(DSSpacing.sm)
                .background(matchScoreColor(topMatchScore).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
            }

            // Stats grid
            HStack(spacing: DSSpacing.lg) {
                if sourceCount > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(sourceCount)")
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(sourceQualityColor)
                            Text("sources")
                                .font(.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if let avg = averageSourceScore {
                            Text("\(Int(avg * 100))% avg vector distance")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(sourceQualityColor)
                        }
                    }
                }

                if totalDocuments > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(coveredDocuments)")
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                            Text("of \(totalDocuments) docs")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if totalChunks > 0 {
                            Text("\(totalChunks) passages scanned")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }

                Spacer()

                if toolCallCount > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.subheadline)
                            Text("\(toolCallCount)")
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.purple)
                        Text("agentic tools invoked")
                            .font(.caption)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: Search Strategy

    private var searchStrategySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("Search Strategy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                // Retrieval mode badge
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: retrievalMode.icon)
                        .font(.caption2)
                    Text(retrievalMode.rawValue)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(retrievalMode.color)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(retrievalMode.color.opacity(0.12))
                .clipShape(Capsule())
            }

            // Visual weight comparison
            HStack(spacing: DSSpacing.md) {
                // Semantic search
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                        Text("Semantic Search")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Finds content with similar meaning, even if different words are used")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DSSpacing.sm) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * vectorWeight)
                        }
                        .frame(height: 8)
                        .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                        Text("\(Int(vectorWeight * 100))%")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)

                // Keyword search
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                        Text("Keyword Search")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Matches exact words and phrases using BM25 scoring algorithm")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DSSpacing.sm) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * lexicalWeight)
                        }
                        .frame(height: 8)
                        .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                        Text("\(Int(lexicalWeight * 100))%")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Additional strategy details
            HStack(spacing: DSSpacing.md) {
                if semanticChunksUsed {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Smart chunking preserves topic boundaries")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "shuffle")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                    Text("Diversity: \(diversityDescriptionFull)")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }

            // NEW: Advanced RAG Features (FullBlownUpgrade)
            advancedRAGFeaturesSection
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Advanced RAG Features (FullBlownUpgrade)

    @ViewBuilder
    private var advancedRAGFeaturesSection: some View {
        let hasAdvancedFeatures = hierarchicalChunkingActive || graphExpansionActive || intentAwareWeightsActive

        if hasAdvancedFeatures {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Divider()
                    .padding(.vertical, DSSpacing.xxs)

                // Header for advanced features
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                    Text("Advanced RAG")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                }

                // Feature badges in a flow layout
                FlowLayout(spacing: DSSpacing.xs) {
                    // Hierarchical Chunking badge
                    if hierarchicalChunkingActive {
                        advancedFeatureBadge(
                            icon: "rectangle.3.group",
                            title: "Hierarchical",
                            detail: parentChunksUsed > 0 ? "\(parentChunksUsed) parent" : nil,
                            color: .cyan,
                            tooltip: "Parent-child indexing: precise embedding + rich context"
                        )
                    }

                    // Parent expansion stats
                    if siblingChunksAdded > 0 {
                        advancedFeatureBadge(
                            icon: "plus.rectangle.on.rectangle",
                            title: "+\(siblingChunksAdded) siblings",
                            detail: nil,
                            color: .teal,
                            tooltip: "Adjacent chunks merged for complete context"
                        )
                    }

                    // Intent-Aware Weights
                    if intentAwareWeightsActive && !queryIntent.isEmpty {
                        advancedFeatureBadge(
                            icon: "brain",
                            title: "Intent: \(queryIntent)",
                            detail: nil,
                            color: .purple,
                            tooltip: "Dynamic weights adjusted for query type"
                        )
                    }

                    // GraphRAG-lite expansion
                    if graphExpansionActive {
                        advancedFeatureBadge(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "Graph 2-hop",
                            detail: graphEntitiesExtracted > 0 ? "\(graphEntitiesExtracted) entities" : nil,
                            color: .orange,
                            tooltip: "Entity extraction + relationship search"
                        )
                    }
                }
            }
        }
    }

    private func advancedFeatureBadge(
        icon: String,
        title: String,
        detail: String?,
        color: Color,
        tooltip: String
    ) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
            if let detail {
                Text("•")
                    .font(.caption2)
                    .opacity(0.6)
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .help(tooltip)
    }

    private var diversityDescriptionFull: String {
        if mmrDiversity >= 0.8 { return "High – pulls from varied sources to give broader perspective" }
        if mmrDiversity >= 0.5 { return "Balanced – mix of relevance and source variety" }
        return "Low – focuses on most relevant matches only"
    }

    // MARK: - Section: Where It's Running

    private var whereRunningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: execution.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(execution.color)
                Text("Processing Location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            HStack(spacing: DSSpacing.md) {
                // Main execution info
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(executionExplanationFull)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true) // Never truncate

                    if let modelName, !modelName.isEmpty {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "brain")
                                .font(.caption2)
                                .foregroundStyle(DSColors.secondaryText)
                            Text(modelName)
                                .font(.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    // Privacy assurance
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: execution == .privateCloudCompute ? "lock.shield.fill" : "iphone")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(privacyExplanation)
                            .font(.caption)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                // Context usage (visual + text) - BUT NOT for Deep Think/Maximum which uses tokens
                if isRecursiveRAG {
                    // Deep Think / Maximum mode: Show tokens and sessions instead
                    // Use mode-appropriate color (purple for Deep Think, orange for Maximum)
                    let modeColor: Color = isMaximumMode ? .orange : .purple
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: "arrow.trianglehead.branch")
                                    .font(.caption2)
                                    .foregroundStyle(modeColor)
                                Text("Multi-Session")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DSColors.secondaryText)
                            }

                            HStack(spacing: DSSpacing.xs) {
                                // Sessions count
                                if recursiveCallCount > 0 {
                                    HStack(spacing: DSSpacing.xxs) {
                                        Text("\(recursiveCallCount)")
                                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(modeColor)
                                        Text("sessions")
                                            .font(.caption2)
                                            .foregroundStyle(DSColors.secondaryText)
                                    }
                                }
                            }

                            // Total tokens
                            if contextTokens > 0 {
                                HStack(spacing: DSSpacing.xxs) {
                                    Text(formatTokenCount(contextTokens))
                                        .font(.system(.caption, design: .monospaced).weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(modeColor)
                                    Text("tokens")
                                        .font(.caption2)
                                        .foregroundStyle(DSColors.secondaryText)
                                }
                            }
                        }

                        // Response time
                        if let t = ttft {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                Text("First token in \(formatDuration(t))")
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(t < 0.5 ? .green : (t < 1.5 ? .blue : .orange))
                        }
                    }
                } else {
                    // Standard mode: Show context window usage
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        // Context bar with smart label
                        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                            HStack(spacing: DSSpacing.xxs) {
                                if hierarchicalChunkingActive {
                                    Image(systemName: "rectangle.3.group")
                                        .font(.caption2)
                                        .foregroundStyle(.cyan)
                                }
                                Text(hierarchicalChunkingActive ? "Smart Context" : "Context Window")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DSColors.secondaryText)
                            }

                            HStack(spacing: DSSpacing.xs) {
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 70, height: 8)
                                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                        .fill(contextColor)
                                        .frame(width: 70 * contextUsageRatio, height: 8)
                                }

                                Text("\(Int(contextUsageRatio * 100))%")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(contextColor)
                            }

                            Text(contextDetailLabel)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }

                        // Response time
                        if let t = ttft {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                Text("First token in \(formatDuration(t))")
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(t < 0.5 ? .green : (t < 1.5 ? .blue : .orange))
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(execution.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var executionExplanationFull: String {
        let device = DeviceCapabilityService.shared
        switch execution {
        // Apple's 2024 research article on its on-device model says its key-value cache updates run on "our neural
        // engines" (machinelearning.apple.com/research/introducing-apple-foundation-models, read 2026-10-19), so the
        // Neural Engine is named. A 2026-10-18 change took it out after reading only the Foundation Models pages,
        // which name no chip, and was reverted the next day.
        case .onDevice:
            return "\(device.chipName) Neural Engine • \(device.npuTops) TOPS"
        case .privateCloudCompute:
            return "Private Cloud Compute • Encrypted"
        case .unknown:
            return "\(device.chipName)"
        }
    }

    private var privacyExplanation: String {
        switch execution {
        case .onDevice:
            return "On-device only"
        case .privateCloudCompute:
            return "End-to-end encrypted"
        case .unknown:
            return "Private"
        }
    }

    // MARK: - Section: Agentic Tools Used

    private var agenticToolsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("Agentic Tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("\(toolCallCount) invoked")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.purple)
            }

            let toolEvents = thinkingEvents.filter { $0.kind == .toolCall || $0.kind == .agentic }
            if !toolEvents.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    ForEach(toolEvents) { event in
                        HStack(alignment: .top, spacing: DSSpacing.xs) {
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.purple.opacity(0.6))
                                .padding(.top, DSSpacing.xxs)
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(event.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(DSColors.primaryText)
                                if let detail = event.detail {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(DSColors.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(.top, DSSpacing.xxs)
            } else if toolCallCount > 0 {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple.opacity(0.6))
                            .padding(.top, DSSpacing.xxs)
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("Vector Search Engine")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DSColors.primaryText)
                            Text("The AI autonomously searched your documents and retrieved additional context.")
                                .font(.caption2)
                                .foregroundStyle(DSColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, DSSpacing.xxs)
            } else {
                Text("No additional tools were required to answer this query.")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: How Smart It's Being

    private var howSmartSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("Search Intelligence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Two-column layout for search methods
            HStack(spacing: DSSpacing.md) {
                // Meaning-based search
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("Meaning")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Finds similar ideas")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)

                    // Visual bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                    }
                    .frame(height: 6)
                    .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                    Text("\(Int(vectorWeight * 100))% weight")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)

                // Keyword-based search
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Keywords")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Matches exact words")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)

                    // Visual bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                    .frame(height: 6)
                    .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                    Text("\(Int(lexicalWeight * 100))% weight")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
            }

            // Bottom row: diversity setting
            HStack(spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "shuffle")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                    Text("Diversity: \(diversityDescription)")
                        .font(.caption)
                }

                if semanticChunksUsed {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Smart chunking enabled")
                            .font(.caption)
                    }
                }

                Spacer()
            }
            .foregroundStyle(DSColors.secondaryText)
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var diversityDescription: String {
        if mmrDiversity >= 0.8 { return "High (varied sources)" }
        if mmrDiversity >= 0.5 { return "Balanced" }
        return "Low (focused)"
    }

    // MARK: - Section: What It Found

    private var whatFoundSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("Search Results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Stats in readable format
            HStack(spacing: DSSpacing.lg) {
                if sourceCount > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(sourceCount)")
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(sourceQualityColor)
                            Text("sources used")
                                .font(.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if let avg = averageSourceScore {
                            Text("\(sourceQualityLabel(avg)) relevance")
                                .font(.caption)
                                .foregroundStyle(sourceQualityColor)
                        }
                    }
                }

                if totalDocuments > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(coveredDocuments)/\(totalDocuments)")
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                            Text("docs searched")
                                .font(.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if totalChunks > 0 {
                            Text("\(totalChunks) passages scanned")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }

                Spacer()

                if toolCallCount > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption)
                            Text("\(toolCallCount)")
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.purple)
                        Text("tools used")
                            .font(.caption)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: Device Health

    private var deviceHealthSection: some View {
        let state = systemMonitor.currentState
        let device = DeviceCapabilityService.shared

        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header with live indicator
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Device Status")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            // Horizontal scroll of status pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    // Chip
                    statusPill(
                        icon: "cpu",
                        title: device.chipName,
                        subtitle: "\(device.npuTops)T neural",
                        color: .purple
                    )

                    // Thermal
                    statusPill(
                        icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                        title: state.thermalStateName,
                        subtitle: thermalSubtitle(state.thermalState),
                        color: systemStateThermalColor(state.thermalState)
                    )

                    // Memory
                    statusPill(
                        icon: state.memoryPressure.icon,
                        title: formatMemory(state.availableMemoryMB),
                        subtitle: memorySubtitle(state.memoryPressure),
                        color: memoryColor(pressure: state.memoryPressure)
                    )

                    // Battery
                    if state.batteryLevel >= 0 {
                        statusPill(
                            icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                            title: "\(state.batteryPercent)%",
                            subtitle: state.isCharging ? "Charging" : "Battery",
                            color: batteryColor(level: state.batteryLevel, isCharging: state.isCharging)
                        )
                    }
                }
            }

            // Warnings (only if constrained - removed cloud status chips as they're not useful)
            if state.isConstrained {
                HStack(spacing: DSSpacing.sm) {
                    warningChip(
                        icon: "exclamationmark.triangle.fill",
                        text: "Performance reduced: \(constraintReason(state))",
                        color: .orange
                    )
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func thermalSubtitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Running cool"
        case .fair: return "Slightly warm"
        case .serious: return "Getting hot"
        case .critical: return "Throttling"
        @unknown default: return ""
        }
    }

    private func memorySubtitle(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .nominal: return "Plenty free"
        case .warning: return "Getting low"
        case .critical: return "Very low"
        }
    }

    private func statusPill(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    private func warningChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Legacy Compact Row: Execution + Context (kept for reference)

    private var executionContextRow: some View {
        HStack(spacing: DSSpacing.md) {
            // Execution
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: execution.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(execution.color)
                Text(execution.displayName)
                    .font(.caption.weight(.semibold))
                if let modelName, !modelName.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                    Text(modelName)
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Context gauge inline
            HStack(spacing: DSSpacing.xxs) {
                Text("Context:")
                    .font(.caption2)
                    .foregroundStyle(DSColors.secondaryText)
                Text("\(contextTokens)/\(maxContextTokens)")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(contextColor)

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(contextColor)
                            .frame(width: geo.size.width * contextUsageRatio)
                    }
                }
                .frame(width: 40, height: 4)
            }

            // TTFT if available
            if let t = ttft {
                Text(String(format: "%.0fms", t * 1000))
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(t < 0.5 ? .green : .blue)
            }
        }
    }

    // MARK: - Compact Row: System Vitals

    private var systemVitalsRow: some View {
        let state = systemMonitor.currentState
        let device = DeviceCapabilityService.shared

        return HStack(spacing: DSSpacing.sm) {
            // Chip
            compactMetric(icon: "cpu", value: device.chipName, color: .purple)

            // Thermal
            compactMetric(
                icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                value: state.thermalStateName,
                color: systemStateThermalColor(state.thermalState)
            )

            // Memory
            compactMetric(
                icon: state.memoryPressure.icon,
                value: formatMemory(state.availableMemoryMB),
                color: memoryColor(pressure: state.memoryPressure)
            )

            // Battery
            if state.batteryLevel >= 0 {
                compactMetric(
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    value: "\(state.batteryPercent)%",
                    color: batteryColor(level: state.batteryLevel, isCharging: state.isCharging)
                )
            }

            // NPU
            compactMetric(
                icon: "brain.head.profile",
                value: "\(device.npuTops)T",
                color: .blue
            )

            Spacer()

            // Live indicator
            HStack(spacing: DSSpacing.xxs) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text("Live")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, DSSpacing.xxs)
        .padding(.horizontal, DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

    // MARK: - Compact Row: RAG Pipeline

    private var ragPipelineRow: some View {
        HStack(spacing: DSSpacing.sm) {
            // Mode
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: retrievalMode.icon)
                    .font(.caption2)
                Text(retrievalMode.rawValue)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(retrievalMode.color)

            // Semantic/Lexical split bar
            HStack(spacing: DSSpacing.xxs) {
                Text("V:\(Int(vectorWeight * 100))")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.blue)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                        Rectangle().fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                }
                .frame(width: 50, height: 4)
                .clipShape(Capsule())

                Text("L:\(Int(lexicalWeight * 100))")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }

            // Chunking
            if semanticChunksUsed {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Semantic")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.purple)
            }

            // MMR
            Text("MMR:\(String(format: "%.1f", mmrDiversity))")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.cyan)

            Spacer()

            // Silicon badge
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption2)
                Text("vDSP")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.cyan)
        }
        .padding(.vertical, DSSpacing.xxs)
        .padding(.horizontal, DSSpacing.sm)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

    // MARK: - Compact Row: Coverage

    private var coverageRow: some View {
        HStack(spacing: DSSpacing.md) {
            if sourceCount > 0 {
                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(sourceQualityColor)
                        .frame(width: 5, height: 5)
                    Text("\(sourceCount) sources")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                    if let avg = averageSourceScore {
                        Text("(\(String(format: "%.0f%%", avg * 100)) avg)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            if totalDocuments > 0 {
                Text("\(coveredDocuments)/\(totalDocuments) docs")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }

            if totalChunks > 0 {
                Text("\(totalChunks) chunks")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.secondaryText)
            }

            if toolCallCount > 0 {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption2)
                    Text("\(toolCallCount)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(.purple)
            }

            Spacer()
        }
    }

    // MARK: - Compact Row: Warnings

    private var statusWarningsRow: some View {
        HStack(spacing: DSSpacing.sm) {
            if pccActive {
                miniWarning(icon: "cloud.fill", text: "PCC Active", color: .blue)
            }
            if cloudFallbackActive {
                miniWarning(icon: "iphone", text: "Local Fallback", color: .orange)
            }
            if systemMonitor.currentState.isConstrained {
                miniWarning(
                    icon: "exclamationmark.triangle.fill",
                    text: "Throttled: \(constraintReason(systemMonitor.currentState))",
                    color: .orange
                )
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func compactMetric(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
    }

    @ViewBuilder
    private func miniWarning(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - System State Detail Card (Legacy - kept for reference)

    private var systemStateDetailCard: some View {
        let state = systemMonitor.currentState
        let deviceService = DeviceCapabilityService.shared

        return VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("System State")
                    .font(.footnote.weight(.semibold))
                Spacer()
                // Live indicator
                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            // 2-column grid for better readability
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DSSpacing.sm),
                GridItem(.flexible(), spacing: DSSpacing.sm),
            ], spacing: DSSpacing.sm) {
                // Thermal - Apple's exact terminology
                systemMetricCell(
                    icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                    label: "Thermal State",
                    value: state.thermalStateName,
                    detail: thermalDetail(state.thermalState),
                    color: systemStateThermalColor(state.thermalState)
                )

                // Battery
                systemMetricCell(
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    label: "Battery Level",
                    value: state.batteryDisplayString,
                    detail: batteryDetail(state),
                    color: batteryColor(level: state.batteryLevel, isCharging: state.isCharging)
                )

                // Memory
                systemMetricCell(
                    icon: state.memoryPressure.icon,
                    label: "Available RAM",
                    value: formatMemory(state.availableMemoryMB),
                    detail: state.memoryPressure.rawValue,
                    color: memoryColor(pressure: state.memoryPressure)
                )

                // Pipeline Mode
                systemMetricCell(
                    icon: "slider.horizontal.3",
                    label: "Pipeline Mode",
                    value: state.optimizationLevel.displayName,
                    detail: pipelineDetail(state.optimizationLevel),
                    color: pipelineColor(level: state.optimizationLevel)
                )

                // Chip
                systemMetricCell(
                    icon: "cpu",
                    label: "Processor",
                    value: deviceService.chipName,
                    detail: "\(state.activeProcessorCount)/\(state.processorCount) cores",
                    color: .purple
                )

                // NPU
                systemMetricCell(
                    icon: "brain.head.profile",
                    label: "Neural Engine",
                    value: "\(deviceService.npuTops) TOPS",
                    detail: deviceService.tier.displayName,
                    color: .blue
                )
            }

            // Status indicators row
            HStack(spacing: DSSpacing.md) {
                if state.isLowPowerModeEnabled {
                    statusPill(icon: "leaf.fill", text: "Low Power Mode", color: .orange)
                }

                if deviceService.hasThermalHeadroom && !state.isConstrained {
                    statusPill(icon: "thermometer.snowflake", text: "Thermal Headroom", color: .green)
                }

                if state.isCharging {
                    statusPill(icon: "bolt.fill", text: "Charging", color: .green)
                }

                Spacer()
            }

            // Constrained state warning
            if state.isConstrained {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Pipeline Adjusted")
                            .font(.caption.weight(.semibold))
                        Text(constraintReason(state))
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                .foregroundStyle(.orange)
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - RAG Intelligence Card

    private var ragIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("RAG Pipeline")
                    .font(.footnote.weight(.semibold))
                Spacer()
                // Silicon badge
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.caption2)
                    Text(DeviceCapabilityService.shared.chipName)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())
            }

            // 2-column grid for RAG metrics
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DSSpacing.sm),
                GridItem(.flexible(), spacing: DSSpacing.sm),
            ], spacing: DSSpacing.sm) {
                // Retrieval Mode
                ragMetricCell(
                    icon: retrievalMode.icon,
                    label: "Retrieval Mode",
                    value: retrievalMode.rawValue,
                    detail: retrievalModeDetail,
                    color: retrievalMode.color
                )

                // Semantic Chunking
                ragMetricCell(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Chunking",
                    value: semanticChunksUsed ? "Semantic" : "Fixed",
                    detail: semanticChunksUsed ? "Topic boundaries" : "Word windows",
                    color: semanticChunksUsed ? .purple : .gray
                )

                // Vector Weight
                ragMetricCell(
                    icon: "brain",
                    label: "Semantic",
                    value: "\(Int(vectorWeight * 100))%",
                    detail: "Embedding similarity",
                    color: .blue
                )

                // Lexical Weight
                ragMetricCell(
                    icon: "text.magnifyingglass",
                    label: "Keyword",
                    value: "\(Int(lexicalWeight * 100))%",
                    detail: "BM25 scoring",
                    color: .orange
                )
            }

            // Fusion visualization
            HStack(spacing: DSSpacing.sm) {
                // Vector bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())

                Text("RRF")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple)
            }

            // Feature pills
            HStack(spacing: DSSpacing.sm) {
                ragFeaturePill(icon: "function", label: "vDSP Math")
                ragFeaturePill(icon: "arrow.triangle.branch", label: "MMR \(String(format: "%.2f", mmrDiversity))")
                if totalChunks > 0 {
                    ragFeaturePill(icon: "square.stack.3d.up", label: "\(totalChunks) chunks")
                }
                Spacer()
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var retrievalModeDetail: String {
        switch retrievalMode {
        case .hybrid: return "Vector + BM25 fusion"
        case .vectorOnly: return "Pure semantic search"
        case .lexicalBoosted: return "Keyword-heavy search"
        }
    }

    @ViewBuilder
    private func ragMetricCell(icon: String, label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(value)
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            Text(detail)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DSColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    @ViewBuilder
    private func ragFeaturePill(icon: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.cyan.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func systemMetricCell(icon: String, label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Label row
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Value - prominent
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            // Detail - subtle
            Text(detail)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    @ViewBuilder
    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func thermalDetail(_ thermal: ProcessInfo.ThermalState) -> String {
        switch thermal {
        case .nominal: return "Optimal performance"
        case .fair: return "Slightly elevated"
        case .serious: return "Throttling active"
        case .critical: return "Maximum throttling"
        @unknown default: return "Unknown"
        }
    }

    private func batteryDetail(_ state: SystemStateSnapshot) -> String {
        if state.isFullyCharged { return "Fully charged" }
        if state.isCharging { return "Charging" }
        if state.batteryLevel < 0.10 { return "Low battery" }
        if state.batteryLevel < 0.20 { return "Battery saver" }
        return "On battery"
    }

    private func formatMemory(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    private func pipelineDetail(_ level: PipelineOptimizationLevel) -> String {
        switch level {
        case .full: return "All features enabled"
        case .balanced: return "Smart optimization"
        case .efficient: return "Power saving"
        case .minimal: return "Essential only"
        }
    }

    private func batteryColor(level: Float, isCharging: Bool) -> Color {
        if isCharging { return .green }
        if level < 0 { return .gray }
        if level < 0.10 { return .red }
        if level < 0.25 { return .orange }
        return .green
    }

    private func memoryColor(pressure: MemoryPressureLevel) -> Color {
        switch pressure {
        case .nominal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func pipelineColor(level: PipelineOptimizationLevel) -> Color {
        switch level {
        case .full: return .green
        case .balanced: return .blue
        case .efficient: return .orange
        case .minimal: return .red
        }
    }

    private func constraintReason(_ state: SystemStateSnapshot) -> String {
        var reasons: [String] = []
        if state.thermalState == .serious || state.thermalState == .critical {
            reasons.append("thermal")
        }
        if state.memoryPressure != .nominal {
            reasons.append("memory")
        }
        if state.batteryLevel >= 0 && state.batteryLevel < 0.20 && !state.isCharging {
            reasons.append("battery")
        }
        if state.isLowPowerModeEnabled {
            reasons.append("low power mode")
        }
        return reasons.isEmpty ? "device constraints" : reasons.joined(separator: ", ")
    }

    private var executionDetailCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: execution.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(execution.color)
                Text("Execution")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(execution.displayName)
                .font(.subheadline.weight(.medium))

            if let modelName, !modelName.isEmpty {
                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(1)
            }

            Text(executionExplanationFull)
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let t = ttft {
                HStack(spacing: DSSpacing.xxs) {
                    Text("TTFT:")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DSColors.secondaryText)
                    Text(String(format: "%.2fs", t))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(t < 1.0 ? .green : .blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // executionExplanation defined earlier in file

    private var cloudStatusBanner: some View {
        let (icon, text, tint): (String, String, Color) = {
            if pccActive {
                return ("cloud.fill", "Private Cloud Compute active", .blue)
            }
            return ("iphone", "Processing on-device", .green)
        }()

        return HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(tint)
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    private var coverageDetailCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("Coverage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(
                totalDocuments > 0
                    ? "\(coveredDocuments) / \(totalDocuments) docs"
                    : "\(coveredDocuments) docs"
            )
            .font(.subheadline.weight(.medium))
            .monospacedDigit()

            Text(
                totalChunks > 0
                    ? "\(sourceCount) / \(totalChunks) chunks"
                    : "\(sourceCount) chunks"
            )
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .monospacedDigit()
            .foregroundStyle(DSColors.secondaryText)

            if let avg = averageSourceScore {
                Text(String(format: "Avg score: %.2f", avg))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var routingDetailCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("Routing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(routingTitle)
                .font(.subheadline.weight(.medium))

            Text(routingExplanation)
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var routingTitle: String {
        switch execution {
        case .unknown:
            return "Apple Intelligence"
        case .onDevice:
            return "On-Device"
        case .privateCloudCompute:
            return "Private Cloud Compute"
        }
    }

    private var routingExplanation: String {
        switch execution {
        case .unknown:
            return "Processing with Apple Intelligence."
        case .onDevice:
            return "Running locally on Neural Engine. No network required."
        case .privateCloudCompute:
            return "Encrypted processing on Apple's attested servers."
        }
    }

    private var contextDetailCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(contextColor)
                Text("Context")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text("\(formatTokenLimit(contextTokens)) / \(formatTokenLimit(maxContextTokens)) tokens")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(contextColor)
                        .frame(width: geo.size.width * CGFloat(contextUsageRatio))
                }
            }
            .frame(height: 6)

            Text(contextExplanation)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var contextExplanation: String {
        // The limit is this answer's own (`maxContextTokens`, the window the model reported), as the bar's
        // ratio already used: 8,192 on the owner's Mac (2026-10-05). These lines named 4,096 until 5.7.
        let limit = formatTokenLimit(maxContextTokens)
        if contextUsageRatio > 0.85 {
            return "Near the session limit (\(limit) tokens)."
        } else if contextUsageRatio > 0.65 {
            return "Good context usage. Session limit \(limit) tokens."
        } else {
            return "Plenty of headroom. Session limit \(limit) tokens."
        }
    }

    private var architectureNote: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Apple Intelligence")
                    .font(.caption.weight(.medium))
            }
            Text(execution == .privateCloudCompute
                ? "Routed to Private Cloud Compute servers."
                : DeviceCapabilities.pccRoutingCompiledIn
                    ? "On-device model. With your permission, a large answer or a multi-document Deep Think or Maximum answer can be written on Private Cloud Compute, and every answer when it is picked in the model picker."
                    : "On-device model. Nothing leaves this device in this version.")
                .font(.caption2)
                .foregroundStyle(DSColors.secondaryText)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    // MARK: - Helpers

    private func formatCount(_ n: Int) -> String {
        if n > 1000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private func formatTokenLimit(_ n: Int) -> String {
        Self.tokenFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        if t < 60 {
            return String(format: "%.1fs", t)
        }
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Mini Sparkline

/// Compact sparkline chart for speed history
private struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(values.max() ?? 1, 1)
            let minVal = max(values.min() ?? 0, 0)
            let range = max(maxVal - minVal, 1)

            Path { path in
                guard values.count > 1 else { return }

                let stepX = geo.size.width / CGFloat(values.count - 1)
                let points = values.enumerated().map { i, val -> CGPoint in
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - (CGFloat((val - minVal) / range) * geo.size.height)
                    return CGPoint(x: x, y: y)
                }

                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Current value dot
            if let lastVal = values.last {
                let x = geo.size.width
                let y = geo.size.height - (CGFloat((lastVal - minVal) / range) * geo.size.height)
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Generating") {
    UnifiedMetricsBar(
        stage: .generating,
        execution: .onDevice,
        isProcessing: true,
        qualityMode: .standard,
        contextTokens: 2100,
        maxContextTokens: 4096,
        tokensGenerated: 47,
        tokensPerSecond: 23.5,
        characterCount: 312,
        elapsedTime: 2.1,
        speedHistory: [12.0, 18.5, 22.0, 25.3, 23.5],
        ttft: 0.23,
        sourceCount: 5,
        averageSourceScore: 0.72,
        totalDocuments: 24,
        totalChunks: 180,
        coveredDocuments: 6,
        toolCallCount: 2,
        modelName: "Apple Intelligence",
        requestedExecutionContext: .preferCloud,
        thinkingEvents: []
    )
    .padding()
}

#Preview("Complete") {
    UnifiedMetricsBar(
        stage: .complete,
        execution: .privateCloudCompute,
        isProcessing: false,
        qualityMode: .standard,
        contextTokens: 3800,
        maxContextTokens: 4096,
        tokensGenerated: 156,
        tokensPerSecond: 18.2,
        characterCount: 1024,
        elapsedTime: 8.5,
        speedHistory: [],
        ttft: 2.4,
        sourceCount: 12,
        averageSourceScore: 0.85,
        totalDocuments: 120,
        totalChunks: 2400,
        coveredDocuments: 18,
        toolCallCount: 0,
        modelName: "Apple Intelligence",
        requestedExecutionContext: .preferCloud,
        thinkingEvents: []
    )
    .padding()
}

#Preview("Searching") {
    UnifiedMetricsBar(
        stage: .searching,
        execution: .unknown,
        isProcessing: true,
        qualityMode: .standard,
        contextTokens: 800,
        maxContextTokens: 4096,
        tokensGenerated: 0,
        tokensPerSecond: 0,
        characterCount: 0,
        elapsedTime: 0.3,
        speedHistory: [],
        ttft: nil,
        sourceCount: 0,
        averageSourceScore: nil,
        totalDocuments: 0,
        totalChunks: 0,
        coveredDocuments: 0,
        toolCallCount: 0,
        modelName: nil,
        requestedExecutionContext: .automatic,
        thinkingEvents: []
    )
    .padding()
}
#endif

// FlowLayout is defined in DocumentDetailsView.swift - reusing it from Shared scope
struct PanelHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

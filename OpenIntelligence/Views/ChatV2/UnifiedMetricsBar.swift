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
    var mmrDiversity: Double = 0.7
    var semanticChunksUsed: Bool = true
    var vectorWeight: Double = 0.65
    var lexicalWeight: Double = 0.35

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

    // Callbacks
    var onTapDetails: (() -> Void)?

    // State
    @State private var showExpandedDetails = false
    @State private var pulsePhase: CGFloat = 0

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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showExpandedDetails)
        .animation(.easeInOut(duration: 0.3), value: execution)
        .animation(.easeInOut(duration: 0.2), value: stage)
    }

    // MARK: - Main Compact Strip

    private var mainCompactStrip: some View {
        VStack(spacing: 6) {
            // Top row: Key badges with horizontal scroll for overflow
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Execution location (with model name if available)
                    executionBadge

                    qualityBadge

                    // Advanced RAG indicator (when enhanced features active)
                    if hierarchicalChunkingActive || graphExpansionActive {
                        advancedRAGBadge
                    }

                    // Stage indicator (when actively processing)
                    if isProcessing, stage != .idle, stage != .complete {
                        stageBadge
                    }

                    // System state indicator (thermal/battery/memory warning)
                    systemStateBadge

                    Spacer(minLength: 8)

                    // Right-aligned metrics
                    HStack(spacing: 6) { 
                        // Context gauge (always visible)
                        contextGauge

                        // Speed (during generation or after completion)
                        if tokensGenerated > 0 || isProcessing {
                            speedBadge
                        }

                        // Sources (when we have them)
                        if sourceCount > 0 {
                            sourcesBadge
                        }

                        // Expand chevron
                        Image(systemName: showExpandedDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 2)
            }

            // Bottom row: Live generation stats (only during/after generation)
            if tokensGenerated > 0 {
                HStack(spacing: 8) {
                    // Token count
                    microMetric(icon: "number", value: "\(tokensGenerated)", label: "tokens")

                    // Character count
                    microMetric(icon: "text.alignleft", value: formatCount(characterCount), label: "chars")

                    // Elapsed time with status icon
                    microMetric(
                        icon: isProcessing ? "clock" : "checkmark.circle.fill",
                        value: formatElapsed(elapsedTime),
                        label: ""
                    )

                    // Sparkline (only during active streaming with history)
                    if isProcessing && speedHistory.count > 2 {
                        MiniSparkline(values: speedHistory, color: speedColor)
                            .frame(width: 44, height: 14)
                    }

                    Spacer()

                    // Tool calls (if any)
                    if toolCallCount > 0 {
                        toolCallBadge
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Badges

    private var executionBadge: some View {
        HStack(spacing: 4) {
            ZStack {
                // Pulse animation during generation
                if isProcessing && stage == .generating {
                    Circle()
                        .fill(execution.color.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .scaleEffect(pulsePhase)
                        .opacity(Double(1.0 - pulsePhase * 0.5))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                                pulsePhase = 1.5
                            }
                        }
                }

                Image(systemName: execution.icon)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(executionLabel)
                .font(.system(size: 10, weight: .semibold))

            // TTFT when available
            if let t = ttft {
                Text("•")
                    .font(.system(size: 5))
                    .opacity(0.5)
                Text(String(format: "%.0fms", t * 1000))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
        }
        .foregroundStyle(execution.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(execution.color.opacity(0.12))
        .clipShape(Capsule())
        .onChange(of: isProcessing) { _, newValue in
            if !newValue {
                pulsePhase = 0
            }
        }
    }

    private var executionLabel: String {
        switch execution {
        case .onDevice: return "Device"
        case .privateCloudCompute: return "PCC"
        case .mlxLocal: return "MLX"
        case .unknown:
            if let t = ttft, t < 0.5 { return "Device" }
            return "..."
        }
    }

    private var stageBadge: some View {
        HStack(spacing: 3) {
            // Pulsing dot when LLM is actively generating (from session.isResponding)
            if isLLMActivelyGenerating, stage == .generating {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulsePhase == 1 ? 1.3 : 0.8)
                    .opacity(pulsePhase == 1 ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: pulsePhase
                    )
                    .onAppear { pulsePhase = 1 }
            }

            Image(systemName: stage.icon)
                .font(.system(size: 9, weight: .medium))
            Text(stage.description)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(stageColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
        // For recursive RAG (Deep Think), show multi-window indicator
        if isRecursiveRAG {
            return AnyView(
                HStack(spacing: 3) {
                    // Show stacked windows icon to indicate multiple context windows
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 10, weight: .semibold))
                    if contextTokens > 0 {
                        Text(formatTokenCount(contextTokens))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    if recursiveCallCount > 0 {
                        Text("•")
                            .font(.system(size: 4))
                            .opacity(0.5)
                        Text(recursiveCallCount == 0 ? "thinking..." : "\(recursiveCallCount)× 4K")
                            .font(.system(size: 8, weight: .medium))
                    }
                }
                .foregroundStyle(.cyan)
            )
        }

        // Standard mode: show percentage gauge
        return AnyView(
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: contextUsageRatio)
                        .stroke(contextColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)

                Text("\(Int(contextUsageRatio * 100))%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(contextColor)
            }
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

    private var speedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(String(format: "%.1f", tokensPerSecond))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
            Text("t/s")
                .font(.system(size: 7, weight: .medium))
                .opacity(0.7)
        }
        .foregroundStyle(speedColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(speedColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var sourcesBadge: some View {
        HStack(spacing: 3) {
            // Quality indicator dot
            Circle()
                .fill(sourceQualityColor)
                .frame(width: 5, height: 5)

            Image(systemName: "doc.text.fill")
                .font(.system(size: 8, weight: .semibold))

            Text("\(sourceCount)")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(sourceQualityColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(sourceQualityColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var coverageBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 8, weight: .semibold))
            Text("\(coveredDocuments)/\(totalDocuments)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.12))
        .clipShape(Capsule())
    }

    // pccActiveBadge removed - executionBadge already shows "PCC" when active

    private var cloudFallbackBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 8, weight: .semibold))
            Text("Local Fallback")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Advanced RAG Badge (compact indicator for enhanced features)

    private var advancedRAGBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .semibold))
            Text(advancedRAGLabel)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
        HStack(spacing: 3) {
            Image(systemName: retrievalMode.icon)
                .font(.system(size: 8, weight: .semibold))
            Text(retrievalMode.rawValue)
                .font(.system(size: 8, weight: .semibold))
            if semanticChunksUsed {
                Text("•")
                    .font(.system(size: 4))
                    .opacity(0.5)
                Image(systemName: "brain")
                    .font(.system(size: 7, weight: .medium))
            }
        }
        .foregroundStyle(retrievalMode.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
            .font(.system(size: 9, weight: .semibold))
.foregroundStyle(qualityModeColor.opacity(0.8))
            .padding(4)
.background(qualityModeColor.opacity(0.08))
            .clipShape(Circle())
    }

    private var qualityModeColor: Color {
        switch qualityMode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        default: return .blue
        }
    }

    // MARK: - System State Badge

    /// Compact system state indicator showing thermal/battery/memory status
    @ViewBuilder
    private var systemStateBadge: some View {
        let state = systemMonitor.currentState
        let thermalColor = systemStateThermalColor(state.thermalState)

        // Only show if there's something notable (not all nominal)
        if state.hasWarning || state.hasCritical || showExpandedDetails {
            HStack(spacing: 3) {
                // Thermal icon
                Image(systemName: SystemStateMonitor.thermalIcon(for: state.thermalState))
                    .font(.system(size: 8, weight: .semibold))

                // Show battery if low or charging
                if state.isCharging || state.batteryLevel < 0.25 {
                    Text("•")
                        .font(.system(size: 4))
                        .opacity(0.5)
                    Image(systemName: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging))
                        .font(.system(size: 8, weight: .semibold))
                }

                // Show optimization level if not full
                if state.optimizationLevel != .full {
                    Text(state.optimizationLevel.displayName.prefix(3))
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .foregroundStyle(thermalColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(thermalColor.opacity(0.12))
            .clipShape(Capsule())
        }
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
        HStack(spacing: 3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 8, weight: .semibold))
            Text("\(toolCallCount)")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.purple.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Micro Metric

    private func microMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DSColors.primaryText)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
    }

// MARK: - Expanded Panel (Redesigned for Clarity)

    private var expandedDetailsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) { 
                // Section 1: Query Understanding (NEW - most important for user insight)
                if !originalQuery.isEmpty || stage == .embedding || stage == .searching {
                    queryUnderstandingSection
                }

                // Section 2: Where It's Running
                whereRunningSection

                // Section 3: Search Results & Quality
                if sourceCount > 0 || totalDocuments > 0 {
                    searchResultsSection
                }

                // Section 4: How Smart It's Being (retrieval strategy)
                if sourceCount > 0 || stage == .searching || stage == .embedding {
                    searchStrategySection
                }

                // Section 5: Device Health (compact, only notable states)
                deviceHealthSection
            }
        }
        .frame(maxHeight: 400) // Allow scrolling for rich content
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 4)
    }

    // MARK: - Section: Query Understanding (NEW)

    private var queryUnderstandingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("Query Understanding")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if hydeEnabled {
                    HStack(spacing: 3) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9))
                        Text("HyDE Active")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Original query (full, not truncated)
            if !originalQuery.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You asked:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(originalQuery)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true) // Full text, never truncate
                }
            }

            // Rewritten/clarified query (if different)
            if !rewrittenQuery.isEmpty && rewrittenQuery != originalQuery {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Clarified to:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(rewrittenQuery)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Extracted keywords & intent
            HStack(spacing: 16) {
                // Keywords
                if !extractedKeywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Key terms extracted:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 4) {
                            ForEach(extractedKeywords.prefix(8), id: \.self) { keyword in
                                Text(keyword)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expansionCount)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.purple)
                        Text("query variations")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Intent classification
            if !queryIntent.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("Detected intent: \(queryIntent)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(12)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Section: Search Results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Search Results")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Best match info (if available)
            if topMatchScore > 0 {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text("Best Match")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        if !topMatchSource.isEmpty {
                            Text(topMatchSource)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(Int(topMatchScore * 100))% relevance score")
                            .font(.system(size: 11))
                            .foregroundStyle(matchScoreColor(topMatchScore))
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(matchScoreColor(topMatchScore))
                    }
                    .frame(width: 40, height: 40)
                }
                .padding(10)
                .background(matchScoreColor(topMatchScore).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Stats grid
            HStack(spacing: 20) {
                if sourceCount > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(sourceCount)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(sourceQualityColor)
                            Text("sources")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if let avg = averageSourceScore {
                            Text("\(Int(avg * 100))% average relevance")
                                .font(.system(size: 11))
                                .foregroundStyle(sourceQualityColor)
                        }
                    }
                }

                if totalDocuments > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(coveredDocuments)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                            Text("of \(totalDocuments) docs")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if totalChunks > 0 {
                            Text("\(totalChunks) passages scanned")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if toolCallCount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 14))
                            Text("\(toolCallCount)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.purple)
                        Text("agentic tools invoked")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func matchScoreColor(_ score: Float) -> Color {
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }

    // MARK: - Section: Search Strategy

    private var searchStrategySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Search Strategy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                // Retrieval mode badge
                HStack(spacing: 3) {
                    Image(systemName: retrievalMode.icon)
                        .font(.system(size: 9))
                    Text(retrievalMode.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(retrievalMode.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(retrievalMode.color.opacity(0.12))
                .clipShape(Capsule())
            }

            // Visual weight comparison
            HStack(spacing: 16) {
                // Semantic search
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                        Text("Semantic Search")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Finds content with similar meaning, even if different words are used")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * vectorWeight)
                        }
                        .frame(height: 8)
                        .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))

                        Text("\(Int(vectorWeight * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)

                // Keyword search
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                        Text("Keyword Search")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Matches exact words and phrases using BM25 scoring algorithm")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * lexicalWeight)
                        }
                        .frame(height: 8)
                        .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))

                        Text("\(Int(lexicalWeight * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Additional strategy details
            HStack(spacing: 12) {
                if semanticChunksUsed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Smart chunking preserves topic boundaries")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    Text("Diversity: \(diversityDescriptionFull)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // NEW: Advanced RAG Features (FullBlownUpgrade)
            advancedRAGFeaturesSection
        }
        .padding(12)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Advanced RAG Features (FullBlownUpgrade)

    @ViewBuilder
    private var advancedRAGFeaturesSection: some View {
        let hasAdvancedFeatures = hierarchicalChunkingActive || graphExpansionActive || intentAwareWeightsActive

        if hasAdvancedFeatures {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .padding(.vertical, 4)

                // Header for advanced features
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.yellow)
                    Text("Advanced RAG")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.yellow)
                }

                // Feature badges in a flow layout
                FlowLayout(spacing: 6) {
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
            if let detail {
                Text("•")
                    .font(.system(size: 5))
                    .opacity(0.6)
                Text(detail)
                    .font(.system(size: 8, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: execution.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(execution.color)
                Text("Processing Location")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                // Main execution info
                VStack(alignment: .leading, spacing: 4) {
                    Text(executionExplanationFull)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
.fixedSize(horizontal: false, vertical: true) // Never truncate

                    if let modelName, !modelName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(modelName)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Privacy assurance
                    HStack(spacing: 4) {
                        Image(systemName: execution == .privateCloudCompute ? "lock.shield.fill" : "iphone")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(privacyExplanation)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Context usage (visual + text)
                VStack(alignment: .trailing, spacing: 6) {
                    // Context bar with smart label
                    VStack(alignment: .trailing, spacing: 4) { 
                        HStack(spacing: 4) {
                            if hierarchicalChunkingActive {
                                Image(systemName: "rectangle.3.group")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.cyan)
                            }
                            Text(hierarchicalChunkingActive ? "Smart Context" : "Context Window")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            ZStack(alignment: .leading) { 
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.2))
.frame(width: 70, height: 8)
RoundedRectangle(cornerRadius: 4)
    .fill(contextColor)
.frame(width: 70 * contextUsageRatio, height: 8)
                            }

                            Text("\(Int(contextUsageRatio * 100))%")
.font(.system(size: 12, weight: .bold, design: .monospaced))
    .foregroundStyle(contextColor)
                        }

                        Text(contextDetailLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // Response time
                    if let t = ttft {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text("First token in \(String(format: "%.0fms", t * 1000))")
                                .font(.system(size: 11, weight: .medium))
                        }
.foregroundStyle(t < 0.5 ? .green : (t < 1.5 ? .blue : .orange))
                    }
                }
            }
        }
        .padding(12)
        .background(execution.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var executionExplanationFull: String { 
        switch execution {
        case .onDevice:
            return "Running privately on your device's Neural Engine – no data leaves your phone"
        case .privateCloudCompute:
            return "Using Apple's Private Cloud Compute – encrypted processing on attested Apple Silicon servers"
        case .mlxLocal:
            return "Running locally with MLX acceleration on Apple Silicon for fast on-device inference"
        case .unknown:
            return "Determining optimal processing location..."
        }
    }

    private var privacyExplanation: String {
        switch execution {
        case .onDevice:
            return "Your data never leaves this device"
        case .privateCloudCompute:
            return "End-to-end encrypted, Apple cannot access your data"
        case .mlxLocal:
            return "Fully private, local processing only"
        case .unknown:
            return "Privacy-first processing"
        }
    }

    // MARK: - Section: How Smart It's Being

    private var howSmartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Search Intelligence")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Two-column layout for search methods
            HStack(spacing: 16) {
                // Meaning-based search
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("Meaning")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Finds similar ideas")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Visual bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                    }
                    .frame(height: 6)
                    .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))

                    Text("\(Int(vectorWeight * 100))% weight")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)

                // Keyword-based search
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Keywords")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Matches exact words")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Visual bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                    .frame(height: 6)
                    .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))

                    Text("\(Int(lexicalWeight * 100))% weight")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
            }

            // Bottom row: diversity setting
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    Text("Diversity: \(diversityDescription)")
                        .font(.system(size: 11))
                }

                if semanticChunksUsed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Smart chunking enabled")
                            .font(.system(size: 11))
                    }
                }

                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var diversityDescription: String {
        if mmrDiversity >= 0.8 { return "High (varied sources)" }
        if mmrDiversity >= 0.5 { return "Balanced" }
        return "Low (focused)"
    }

    // MARK: - Section: What It Found

    private var whatFoundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Search Results")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Stats in readable format
            HStack(spacing: 20) {
                if sourceCount > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(sourceCount)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(sourceQualityColor)
                            Text("sources used")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if let avg = averageSourceScore {
                            Text("\(sourceQualityLabel(avg)) relevance")
                                .font(.system(size: 11))
                                .foregroundStyle(sourceQualityColor)
                        }
                    }
                }

                if totalDocuments > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(coveredDocuments)/\(totalDocuments)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                            Text("docs searched")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if totalChunks > 0 {
                            Text("\(totalChunks) passages scanned")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if toolCallCount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 12))
                            Text("\(toolCallCount)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.purple)
                        Text("tools used")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sourceQualityLabel(_ score: Float) -> String {
        if score > 0.7 { return "Excellent" }
        if score > 0.5 { return "Good" }
        if score > 0.3 { return "Fair" }
        return "Low"
    }

    // MARK: - Section: Device Health

    private var deviceHealthSection: some View {
        let state = systemMonitor.currentState
        let device = DeviceCapabilityService.shared

        return VStack(alignment: .leading, spacing: 8) {
            // Header with live indicator
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Device Status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            // Horizontal scroll of status pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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

            // Warnings (if any)
            if pccActive || cloudFallbackActive || state.isConstrained {
                HStack(spacing: 8) {
                    if pccActive {
                        warningChip(icon: "cloud.fill", text: "Using Apple's secure cloud", color: .blue)
                    }
                    if cloudFallbackActive {
                        warningChip(icon: "iphone", text: "Cloud unavailable, using device", color: .orange)
                    }
                    if state.isConstrained {
                        warningChip(
                            icon: "exclamationmark.triangle.fill",
                            text: "Performance reduced: \(constraintReason(state))",
                            color: .orange
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func warningChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Legacy Compact Row: Execution + Context (kept for reference)

    private var executionContextRow: some View {
        HStack(spacing: 12) { 
            // Execution
            HStack(spacing: 4) {
                Image(systemName: execution.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(execution.color)
                Text(execution.displayName)
                    .font(.system(size: 11, weight: .semibold))
                if let modelName, !modelName.isEmpty {
                    Text("•")
                        .font(.system(size: 6))
                        .foregroundStyle(.secondary)
                    Text(modelName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Context gauge inline
            HStack(spacing: 4) {
                Text("Context:")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("\(contextTokens)/\(maxContextTokens)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(contextColor)

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextColor)
                            .frame(width: geo.size.width * contextUsageRatio)
                    }
                }
                .frame(width: 40, height: 4)
            }

            // TTFT if available
            if let t = ttft {
                Text(String(format: "%.0fms", t * 1000))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(t < 0.5 ? .green : .blue)
            }
        }
    }

    // MARK: - Compact Row: System Vitals

    private var systemVitalsRow: some View {
        let state = systemMonitor.currentState
        let device = DeviceCapabilityService.shared

        return HStack(spacing: 10) {
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
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text("Live")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Compact Row: RAG Pipeline

    private var ragPipelineRow: some View {
        HStack(spacing: 10) {
            // Mode
            HStack(spacing: 3) {
                Image(systemName: retrievalMode.icon)
                    .font(.system(size: 9))
                Text(retrievalMode.rawValue)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(retrievalMode.color)

            // Semantic/Lexical split bar
            HStack(spacing: 4) {
                Text("V:\(Int(vectorWeight * 100))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
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
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            // Chunking
            if semanticChunksUsed {
                HStack(spacing: 2) {
                    Image(systemName: "brain")
                        .font(.system(size: 8))
                    Text("Semantic")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.purple)
            }

            // MMR
            Text("MMR:\(String(format: "%.1f", mmrDiversity))")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.cyan)

            Spacer()

            // Silicon badge
            HStack(spacing: 2) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 7))
                Text("vDSP")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(.cyan)
        }
        .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Compact Row: Coverage

    private var coverageRow: some View {
        HStack(spacing: 12) { 
            if sourceCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(sourceQualityColor)
                        .frame(width: 5, height: 5)
                    Text("\(sourceCount) sources")
                        .font(.system(size: 10, weight: .medium))
                    if let avg = averageSourceScore {
                        Text("(\(String(format: "%.0f%%", avg * 100)) avg)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if totalDocuments > 0 {
                Text("\(coveredDocuments)/\(totalDocuments) docs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
            }

            if totalChunks > 0 {
                Text("\(totalChunks) chunks")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if toolCallCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 8))
                    Text("\(toolCallCount)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.purple)
            }

            Spacer()
        }
    }

    // MARK: - Compact Row: Warnings

    private var statusWarningsRow: some View {
        HStack(spacing: 8) {
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
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func miniWarning(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
.foregroundStyle(color)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(color.opacity(0.12))
    .clipShape(Capsule())
    }

    // MARK: - System State Detail Card (Legacy - kept for reference)

    private var systemStateDetailCard: some View {
        let state = systemMonitor.currentState
        let deviceService = DeviceCapabilityService.shared

        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("System State")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // Live indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            // 2-column grid for better readability
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
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
            HStack(spacing: 12) {
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
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pipeline Adjusted")
                            .font(.system(size: 11, weight: .semibold))
                        Text(constraintReason(state))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - RAG Intelligence Card

    private var ragIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("RAG Pipeline")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // Silicon badge
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 8))
                    Text(DeviceCapabilityService.shared.chipName)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())
            }

            // 2-column grid for RAG metrics
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
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
            HStack(spacing: 8) {
                // Vector bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())

                Text("RRF")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            // Feature pills
            HStack(spacing: 8) {
                ragFeaturePill(icon: "function", label: "vDSP Math")
                ragFeaturePill(icon: "arrow.triangle.branch", label: "MMR \(String(format: "%.2f", mmrDiversity))")
                if totalChunks > 0 {
                    ragFeaturePill(icon: "square.stack.3d.up", label: "\(totalChunks) chunks")
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func ragFeaturePill(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(label)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.cyan.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func systemMetricCell(icon: String, label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label row
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Value - prominent
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Detail - subtle
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: execution.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(execution.color)
                Text("Execution")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(execution.displayName)
                .font(.system(size: 14, weight: .medium))

            if let modelName, !modelName.isEmpty {
                Text(modelName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(executionExplanationFull)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
.fixedSize(horizontal: false, vertical: true)

            if let t = ttft {
                HStack(spacing: 4) {
                    Text("TTFT:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fs", t))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(t < 1.0 ? .green : .blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // executionExplanation defined earlier in file

    private var cloudStatusBanner: some View {
        let (icon, text, tint): (String, String, Color) = {
            if pccActive {
                return ("cloud.fill", "Private Cloud Compute active", .blue)
            }
            return ("iphone", "Processing on-device", .green)
        }()

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(tint)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var coverageDetailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Coverage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(
                totalDocuments > 0
                    ? "\(coveredDocuments) / \(totalDocuments) docs"
                    : "\(coveredDocuments) docs"
            )
                .font(.system(size: 14, weight: .medium))

            Text(
                totalChunks > 0
                    ? "\(sourceCount) / \(totalChunks) chunks"
                    : "\(sourceCount) chunks"
            )
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            if let avg = averageSourceScore {
                Text(String(format: "Avg score: %.2f", avg))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var routingDetailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Routing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(routingTitle)
                .font(.system(size: 14, weight: .medium))

            Text(routingExplanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var routingTitle: String {
        switch execution {
        case .unknown:
            return wantsCloud ? "Requesting PCC..." : "Selecting route..."
        case .onDevice:
            return "On-Device (3B model)"
        case .privateCloudCompute:
            return "Private Cloud Compute"
        case .mlxLocal:
            return "Local MLX"
        }
    }

    private var routingExplanation: String {
        switch execution {
        case .unknown:
            return wantsCloud
                ? "Connecting to Private Cloud Compute...":
                    "Determining optimal processing location."
        case .onDevice:
            return "Running locally on Neural Engine. No network required."
        case .privateCloudCompute:
            return "Encrypted processing on Apple's attested servers."
        case .mlxLocal:
            return "Local MLX model processing."
        }
    }

    private var contextDetailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(contextColor)
                Text("Context")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(formatTokenLimit(contextTokens)) / \(formatTokenLimit(maxContextTokens)) tokens")
                .font(.system(size: 14, weight: .medium))

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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var contextExplanation: String {
        // Session context limit is 4,096 tokens regardless of PCC routing
        // PCC extends input capacity but session accumulation is still limited
        if contextUsageRatio > 0.85 {
            return "Near session limit (4,096 tokens)."
        } else if contextUsageRatio > 0.65 {
            return "Good context usage. Session limit 4K."
        } else {
            return "Plenty of headroom. Session limit 4K."
        }
    }

    private var architectureNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
.font(.system(size: 11))
    .foregroundStyle(.purple)
                Text("Apple Intelligence")
                    .font(.system(size: 11, weight: .medium))
            }
            Text(execution == .privateCloudCompute
                ? "Routed to Private Cloud Compute servers."
                : "On-device 3B model. Complex queries may route to PCC.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    struct UnifiedMetricsBar_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                // Active generation on device - Adaptive mode
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
                    requestedExecutionContext: .preferCloud
                )

                // Completed on PCC - Adaptive mode
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
                    requestedExecutionContext: .preferCloud
                )

                // Searching stage - Adaptive mode
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
                    requestedExecutionContext: .automatic
                )
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
        }
    }
#endif

// FlowLayout is defined in DocumentDetailsView.swift - reusing it from Shared scope

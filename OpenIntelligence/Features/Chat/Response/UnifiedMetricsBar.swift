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
    @State var showExpandedDetails = false
    @State var pulsePhase: CGFloat = 0
    
    // Smooth Drag State
    @State var autoHeight: CGFloat = 0
    @State var baseHeight: CGFloat = 0
    @State var dragOffset: CGFloat = 0
    @State var isDragging: Bool = false

    // System state (live monitoring)
    @ObservedObject var systemMonitor = SystemStateMonitor.shared

    // Computed
    var contextUsageRatio: Double {
        guard maxContextTokens > 0 else { return 0 }
        return min(1.0, Double(contextTokens) / Double(maxContextTokens))
    }

    var contextColor: Color {
        if contextUsageRatio > 0.85 { return .red }
        if contextUsageRatio > 0.65 { return .orange }
        return .green
    }

    /// Descriptive label for context showing optimization status
    var contextDetailLabel: String {
        if hierarchicalChunkingActive && parentChunksUsed > 0 {
            return "\(sourceCount) chunks • \(parentChunksUsed) expanded"
        } else if sourceCount > 0 {
            return "\(contextTokens) tokens • \(sourceCount) chunks"
        } else {
            return "\(contextTokens) of \(maxContextTokens) tokens"
        }
    }

    var speedColor: Color {
        if tokensPerSecond > 30 { return .green }
        if tokensPerSecond > 15 { return .blue }
        if tokensPerSecond > 5 { return .orange }
        return .red
    }

    private var isReasoningQualityMode: Bool {
        isRecursiveRAG || isMaximumMode
    }

    var liveTokenMetricColor: Color {
        isReasoningQualityMode ? qualityModeColor : speedColor
    }

    var tokenCounterColor: Color {
        if isReasoningQualityMode {
            return qualityModeColor
        }
        return tokensGenerated > 0 ? .green : .secondary
    }

    var tokenCounterIcon: String {
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

    var cloudFallbackActive: Bool {
        execution == .onDevice && wantsCloud
    }

    var pccActive: Bool {
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

    // MARK: - Helpers

    func formatCount(_ n: Int) -> String {
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

    func formatTokenLimit(_ n: Int) -> String {
        Self.tokenFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    func formatElapsed(_ t: TimeInterval) -> String {
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
struct MiniSparkline: View {
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

//
//  UnifiedMetricsBar.swift
//  OpenIntelligence
//
//  Single source of truth for all processing metrics and intelligence in chat.
//  Combines execution location, context usage, generation stats, and source quality
//  into one cohesive, expandable component.
//

import SwiftUI

// MARK: - Main Unified Component

/// The ONE metrics bar to rule them all.
/// Shows everything: execution location, context window, generation speed,
/// sources, quality mode—with expandable detail panel for transparency.
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

    // Callbacks
    var onTapDetails: (() -> Void)?

    // State
    @State private var showExpandedDetails = false
    @State private var pulsePhase: CGFloat = 0

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
            // Top row: Execution + Stage + Context + Speed + Sources
            HStack(spacing: 6) {
                // Execution location (with model name if available)
                executionBadge

                qualityBadge

                // Stage indicator (when actively processing)
                if isProcessing && stage != .idle && stage != .complete {
                    stageBadge
                }

                // Note: executionBadge already shows "PCC" when pccActive
                // Don't add duplicate pccActiveBadge

                if cloudFallbackActive {
                    cloudFallbackBadge
                }

                Spacer(minLength: 4)

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

                if totalDocuments > 0, coveredDocuments > 0 {
                    coverageBadge
                }

                // Expand chevron
                Image(systemName: showExpandedDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
            }

            // Bottom row: Live generation stats (only during/after generation)
            if tokensGenerated > 0 {
                HStack(spacing: 8) {
                    // Token count
                    microMetric(icon: "number", value: "\(tokensGenerated)", label: "tok")

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

    private var sourceQualityColor: Color {
        guard let score = averageSourceScore else { return .purple }
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }

    private var qualityBadge: some View {
        Image(systemName: qualityMode.icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(qualityModeColor.opacity(0.8))
            .padding(4)
            .background(qualityModeColor.opacity(0.08))
            .clipShape(Circle())
    }

    private var qualityModeColor: Color {
        switch qualityMode {
        case .fast: return .orange
        case .balanced: return .blue
        case .thorough: return .green
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

    // MARK: - Expanded Panel

    private var expandedDetailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                executionDetailCard
                contextDetailCard
            }

            if pccActive || cloudFallbackActive {
                cloudStatusBanner
            }

            HStack(spacing: 12) {
                coverageDetailCard
                routingDetailCard
            }

            architectureNote
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 4)
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

            Text(executionExplanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)

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

    private var executionExplanation: String {
        switch execution {
        case .unknown:
            return "Determining optimal processing location..."
        case .onDevice:
            return "Running on Neural Engine. 4,096-token context, no network needed."
        case .privateCloudCompute:
            return "Using attested PCC nodes for long-context reasoning. Zero data retention."
        case .mlxLocal:
            return "Local MLX model processing."
        }
    }

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
                // Active generation on device
                UnifiedMetricsBar(
                    stage: .generating,
                    execution: .onDevice,
                    isProcessing: true,
                    qualityMode: .balanced,
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

                // Completed on PCC
                UnifiedMetricsBar(
                    stage: .complete,
                    execution: .privateCloudCompute,
                    isProcessing: false,
                    qualityMode: .thorough,
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

                // Searching stage (no generation yet)
                UnifiedMetricsBar(
                    stage: .searching,
                    execution: .unknown,
                    isProcessing: true,
                    qualityMode: .fast,
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

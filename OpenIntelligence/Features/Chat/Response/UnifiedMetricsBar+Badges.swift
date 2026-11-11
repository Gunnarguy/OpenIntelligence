//
//  UnifiedMetricsBar+Badges.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - Legacy Badges (kept for expanded view compatibility)

    private var qualityBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: qualityMode.icon)
                .scaledFont(size: 10, weight: .semibold)
            Text(qualityModeLabel)
                .scaledFont(size: 10, weight: .semibold)
        }
        .foregroundStyle(qualityModeColor)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(qualityModeColor.opacity(0.12))
        .clipShape(Capsule())
    }

    var qualityModeLabel: String {
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
                .scaledFont(size: 9, weight: .semibold)
            Text(advancedRAGLabelDescriptive)
                .scaledFont(size: 9, weight: .semibold)
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
                .scaledFont(size: 9, weight: .medium)
            Text(formatElapsed(elapsedTime))
                .scaledFont(size: 10, weight: .medium, design: .monospaced)
                .monospacedDigit()
            if !isProcessing {
                Text("done")
                    .scaledFont(size: 8, weight: .medium)
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
                        .scaledFont(size: 9, weight: .semibold)
                    if recursiveCallCount > 0 {
                        Text("\(recursiveCallCount) sessions")
                            .scaledFont(size: 10, weight: .semibold)
                            .monospacedDigit()
                    }
                    if contextTokens > 0 {
                        Text("• \(formatTokenCount(contextTokens)) tokens")
                            .scaledFont(size: 9, weight: .medium)
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
                    .scaledFont(size: 9, weight: .semibold)
                Text("Context:")
                    .scaledFont(size: 9, weight: .medium)
                    .opacity(0.7)
                Text(formatTokenCount(contextTokens))
                    .scaledFont(size: 10, weight: .bold, design: .monospaced)
                    .monospacedDigit()
                Text("tokens")
                    .scaledFont(size: 8, weight: .medium)
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
                .scaledFont(size: 9, weight: .semibold)
            Text("Speed:")
                .scaledFont(size: 9, weight: .medium)
                .opacity(0.7)
            Text(tokensPerSecond >= 1 ? String(format: "%.0f", tokensPerSecond) : "–")  // no "0 t/s" before the first token (5.8)
                .scaledFont(size: 10, weight: .bold, design: .monospaced)
                .monospacedDigit()
            Text("t/s")
                .scaledFont(size: 8, weight: .medium)
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
                .scaledFont(size: 9, weight: .semibold)
            Text("Output:")
                .scaledFont(size: 9, weight: .medium)
                .opacity(0.7)
            Text(formatTokenCount(tokensGenerated))
                .scaledFont(size: 10, weight: .bold, design: .monospaced)
                .monospacedDigit()
            Text("tokens")
                .scaledFont(size: 8, weight: .medium)
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
                .scaledFont(size: 9, weight: .semibold)
            Text("\(sourceCount)")
                .scaledFont(size: 10, weight: .bold)
                .monospacedDigit()
            Text(sourceCount == 1 ? "source" : "sources")
                .scaledFont(size: 9, weight: .medium)
                .opacity(0.7)
            // Show quality indicator
            if let score = averageSourceScore {
                Text("•")
                    .scaledFont(size: 5)
                    .opacity(0.5)
                Text(sourceQualityLabel(score))
                    .scaledFont(size: 8, weight: .semibold)
            }
        }
        .foregroundStyle(sourceQualityColor)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(sourceQualityColor.opacity(0.12))
        .clipShape(Capsule())
    }

    func sourceQualityLabel(_ score: Float) -> String {
        if score > 0.7 { return "excellent" }
        if score > 0.5 { return "good" }
        if score > 0.3 { return "fair" }
        return "weak"
    }

    // MARK: - Descriptive Tool Call Badge

    private var toolCallBadgeDescriptive: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "function")
                .scaledFont(size: 9, weight: .semibold)
            Text("\(toolCallCount)")
                .scaledFont(size: 10, weight: .bold)
                .monospacedDigit()
            Text(toolCallCount == 1 ? "tool call" : "tool calls")
                .scaledFont(size: 9, weight: .medium)
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
                .scaledFont(size: 7, weight: .semibold)
            Text(formatTokenCount(tokensGenerated))
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
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
                .scaledFont(size: 8, weight: .semibold)
            Text(formatCount(characterCount))
                .scaledFont(size: 10, weight: .medium, design: .monospaced)
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
                    .scaledFont(size: 10, weight: .semibold)
            }

            // Clean label: "Neural Engine" for on-device, "PCC" for cloud
            Text(executionBadgeLabel)
                .scaledFont(size: 10, weight: .semibold)

            // Chip specs for on-device (e.g., "A18 Pro • 38T")
            if execution == .onDevice || (execution == .unknown && !isProcessing) {
                Text("•")
                    .scaledFont(size: 5)
                    .opacity(0.4)
                Text("\(device.chipDisplayName)")
                    .scaledFont(size: 9, weight: .medium)
                    .opacity(0.8)
                Text(device.memoryDescription.replacingOccurrences(of: " ", with: ""))
                    .scaledFont(size: 8, weight: .semibold, design: .monospaced)
                    .monospacedDigit()
                    .opacity(0.7)
            }

            // TTFT when available (only during processing)
            if isProcessing, let t = ttft {
                Text("•")
                    .scaledFont(size: 5)
                    .opacity(0.5)
                Text(formatDuration(t))
                    .scaledFont(size: 9, weight: .medium, design: .monospaced)
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
                .scaledFont(size: 9, weight: .medium)
            Text(stage.description)
                .scaledFont(size: 9, weight: .medium)
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
                        .scaledFont(size: 7, weight: .semibold)

                    // Show sessions count (this is what matters)
                    if recursiveCallCount > 0 {
                        Text("\(recursiveCallCount)×")
                            .scaledFont(size: 8, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                    }

                    // Total tokens (summed across all sessions)
                    if contextTokens > 0 {
                        Text(formatTokenCount(contextTokens))
                            .scaledFont(size: 8, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                    } else {
                        Text("...")
                            .scaledFont(size: 7, weight: .medium)
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
                    .scaledFont(size: 7, weight: .semibold)
                if contextTokens > 0 {
                    Text(formatTokenCount(contextTokens))
                        .scaledFont(size: 8, weight: .bold, design: .monospaced)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .scaledFont(size: 7, weight: .medium)
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
    func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 10000 {
            return String(format: "%.1fK", Double(tokens) / 1000.0)
        } else if tokens >= 1000 {
            return "\(tokens / 1000).\((tokens % 1000) / 100)K"
        }
        return "\(tokens)"
    }

    /// Format large counts (characters/words) with K suffix - shows big numbers like 40.2K
    func formatLargeCount(_ count: Int) -> String {
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
                .scaledFont(size: 6, weight: .semibold)
            Text(tokensPerSecond >= 1 ? String(format: "%.0f", tokensPerSecond) : "–")  // no "0 t/s" before the first token (5.8)
                .scaledFont(size: 8, weight: .semibold, design: .monospaced)
                .monospacedDigit()
            Text("t/s")
                .scaledFont(size: 6, weight: .medium)
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
                .scaledFont(size: 6, weight: .semibold)
            Text("\(sourceCount)")
                .scaledFont(size: 8, weight: .bold)
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
                .scaledFont(size: 8, weight: .semibold)
            Text("\(coveredDocuments)/\(totalDocuments)")
                .scaledFont(size: 9, weight: .semibold, design: .monospaced)
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
                .scaledFont(size: 8, weight: .semibold)
            Text("Local Fallback")
                .scaledFont(size: 8, weight: .semibold)
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
                .scaledFont(size: 6, weight: .semibold)
            Text(advancedRAGLabel)
                .scaledFont(size: 7, weight: .semibold)
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
                .scaledFont(size: 8, weight: .semibold)
            Text(retrievalMode.rawValue)
                .scaledFont(size: 8, weight: .semibold)
            if semanticChunksUsed {
                Text("•")
                    .scaledFont(size: 4)
                    .opacity(0.5)
                Image(systemName: "brain")
                    .scaledFont(size: 7, weight: .medium)
            }
        }
        .foregroundStyle(retrievalMode.color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(retrievalMode.color.opacity(0.12))
        .clipShape(Capsule())
    }

    var sourceQualityColor: Color {
        guard let score = averageSourceScore else { return .purple }
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }

    private var qualityBadge: some View {
        // Show quality mode icon with appropriate color
        Image(systemName: qualityMode.icon)
            .scaledFont(size: 8, weight: .semibold)
            .foregroundStyle(qualityModeColor.opacity(0.8))
            .padding(DSSpacing.xxs)
            .background(qualityModeColor.opacity(0.08))
            .clipShape(Circle())
    }

    /// Mode-specific theme colors:
    /// - Standard: Blue (fast, efficient, single-pass)
    /// - Deep Think: Purple (analytical, multi-session reasoning)
    /// - Maximum: Orange/Gold (premium, unlimited, thorough)
    var qualityModeColor: Color {
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
                .scaledFont(size: 9, weight: .medium)
                .opacity(0.7)
            Text("\(confidencePercent)%")
                .scaledFont(size: 10, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(badgeColor)

            // Target indicator (mode-appropriate)
            if targetReached {
                Image(systemName: "checkmark.circle.fill")
                    .scaledFont(size: 9)
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
    var systemStateBadge: some View {
        let state = systemMonitor.currentState
        let thermalColor = systemStateThermalColor(state.thermalState)

        // Always show thermal indicator (it's useful info about device state)
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: SystemStateMonitor.thermalIcon(for: state.thermalState))
                .scaledFont(size: 9, weight: .semibold)
        }
        .foregroundStyle(DSColors.readable(thermalColor))
        .padding(DSSpacing.xs)
        .background(thermalColor.opacity(0.1))
        .clipShape(Circle())
    }

    func systemStateThermalColor(_ thermal: ProcessInfo.ThermalState) -> Color {
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
                .scaledFont(size: 6, weight: .semibold)
            Text("\(toolCallCount)")
                .scaledFont(size: 8, weight: .semibold)
                .monospacedDigit()
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.purple.opacity(0.12))
        .clipShape(Capsule())
    }

}

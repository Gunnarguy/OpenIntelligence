//
//  UnifiedMetricsBar+IntelligenceCard.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - RAG Intelligence Card

    private var ragIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.purple)
                Text("RAG Pipeline")
                    .scaledFont(size: 13, weight: .semibold)
                Spacer()
                // Silicon badge
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "bolt.horizontal.fill")
                        .scaledFont(size: 8)
                    Text(DeviceCapabilityService.shared.chipName)
                        .scaledFont(size: 9, weight: .medium)
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
                    .scaledFont(size: 9, weight: .semibold)
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
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(color)
                Text(label)
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(value)
                .scaledFont(size: 13, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            Text(detail)
                .scaledFont(size: 8, weight: .medium)
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
                .scaledFont(size: 8, weight: .semibold)
            Text(label)
                .scaledFont(size: 8, weight: .medium)
                .monospacedDigit()
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.cyan.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    func systemMetricCell(icon: String, label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Label row
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(color)
                Text(label)
                    .scaledFont(size: 10, weight: .medium)
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Value - prominent
            Text(value)
                .scaledFont(size: 14, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            // Detail - subtle
            Text(detail)
                .scaledFont(size: 9, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    @ViewBuilder
    func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 9, weight: .semibold)
            Text(text)
                .scaledFont(size: 9, weight: .medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    func thermalDetail(_ thermal: ProcessInfo.ThermalState) -> String {
        switch thermal {
        // Apple's descriptions of ProcessInfo.ThermalState (5.8 review: the app does not throttle at .serious).
        case .nominal: return "Within normal limits"
        case .fair: return "Slightly elevated"
        case .serious: return "High"
        case .critical: return "Hurting performance"
        @unknown default: return "Unknown"
        }
    }

    func batteryDetail(_ state: SystemStateSnapshot) -> String {
        if state.isFullyCharged { return "Fully charged" }
        if state.isCharging { return "Charging" }
        if state.batteryLevel < 0.10 { return "Low battery" }
        if state.batteryLevel < 0.20 { return "Battery saver" }
        return "On battery"
    }

    func formatMemory(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    func pipelineDetail(_ level: PipelineOptimizationLevel) -> String {
        switch level {
        case .full: return "All features enabled"
        case .balanced: return "Smart optimization"
        case .efficient: return "Power saving"
        case .minimal: return "Essential only"
        }
    }

    func batteryColor(level: Float, isCharging: Bool) -> Color {
        if isCharging { return .green }
        if level < 0 { return .gray }
        if level < 0.10 { return .red }
        if level < 0.25 { return .orange }
        return .green
    }

    func memoryColor(pressure: MemoryPressureLevel) -> Color {
        switch pressure {
        case .nominal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    func pipelineColor(level: PipelineOptimizationLevel) -> Color {
        switch level {
        case .full: return .green
        case .balanced: return .blue
        case .efficient: return .orange
        case .minimal: return .red
        }
    }

    func constraintReason(_ state: SystemStateSnapshot) -> String {
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
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(execution.color)
                Text("Execution")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(execution.displayName)
                .scaledFont(size: 14, weight: .medium)

            if let modelName, !modelName.isEmpty {
                Text(modelName)
                    .scaledFont(size: 11)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(1)
            }

            Text(executionExplanationFull)
                .scaledFont(size: 11)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let t = ttft {
                HStack(spacing: DSSpacing.xxs) {
                    Text("TTFT:")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(DSColors.secondaryText)
                    Text(String(format: "%.2fs", t))
                        .scaledFont(size: 10, weight: .semibold, design: .monospaced)
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
                .scaledFont(size: 12, weight: .semibold)
            Text(text)
                .scaledFont(size: 11)
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
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.blue)
                Text("Coverage")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(
                totalDocuments > 0
                    ? "\(coveredDocuments) / \(totalDocuments) docs"
                    : "\(coveredDocuments) docs"
            )
            .scaledFont(size: 14, weight: .medium)
            .monospacedDigit()

            Text(
                totalChunks > 0
                    ? "\(sourceCount) / \(totalChunks) chunks"
                    : "\(sourceCount) chunks"
            )
            .scaledFont(size: 11, weight: .medium, design: .monospaced)
            .monospacedDigit()
            .foregroundStyle(DSColors.secondaryText)

            if let avg = averageSourceScore {
                Text(String(format: "Avg score: %.2f", avg))
                    .scaledFont(size: 11)
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
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.blue)
                Text("Routing")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text(routingTitle)
                .scaledFont(size: 14, weight: .medium)

            Text(routingExplanation)
                .scaledFont(size: 11)
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
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(contextColor)
                Text("Context")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Text("\(formatTokenLimit(contextTokens)) / \(formatTokenLimit(maxContextTokens)) tokens")
                .scaledFont(size: 14, weight: .medium)
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
                .scaledFont(size: 11)
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
                    .scaledFont(size: 11)
                    .foregroundStyle(.purple)
                Text("Apple Intelligence")
                    .scaledFont(size: 11, weight: .medium)
            }
            Text(execution == .privateCloudCompute
                ? "Routed to Private Cloud Compute servers."
                : DeviceCapabilities.pccRoutingCompiledIn
                    ? "On-device model. With your permission, a large answer or a multi-document Deep Think or Maximum answer can be written on Private Cloud Compute, and every answer when it is picked in the model picker."
                    : "On-device model. Nothing leaves this device in this version.")
                .scaledFont(size: 10)
                .foregroundStyle(DSColors.secondaryText)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

}

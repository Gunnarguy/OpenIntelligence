//
//  ResponseDetailsView.swift
//  OpenIntelligence
//
//  Modernized response details view with granular metrics and sleek visualization
//

import SwiftUI

struct ChatResponseDetailsView: View {
    let metadata: ResponseMetadata
    let retrievedChunks: [RetrievedChunk]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DetailsTab = .overview
    @State private var showPerformanceBreakdown = false
    @Namespace private var animation

    enum DetailsTab: String, CaseIterable {
        case overview = "Overview"
        case sources = "Sources"
        case performance = "Performance"

        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .sources: return "doc.text.magnifyingglass"
            case .performance: return "gauge.with.dots.needle.67percent"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                tabSelector
                    .padding(.top, DSSpacing.xs)

                // Content
                ScrollView { 
                    VStack(spacing: DSSpacing.md) {
                        switch selectedTab {
                        case .overview:
                            overviewContent
                        case .sources:
                            sourcesContent
                        case .performance:
                            performanceContent
                        }
                    }
                    .padding(.vertical, DSSpacing.md)
                }
            }
            .background(DSColors.background)
            .navigationTitle("Response Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(DetailsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(DSAnimations.snappySpring) {
                        selectedTab = tab
                    }
                    DSHaptics.selection()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "tab", in: animation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DSSpacing.xxs)
        .background(DSColors.surface)
        .clipShape(Capsule())
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Overview Content

    private var overviewContent: some View {
        VStack(spacing: DSSpacing.md) {
            // Hero Card with model + execution
            heroCard

            // Quick stats grid
            statsGrid

            // Quick insights
            insightsCard
        }
        .padding(.horizontal, DSSpacing.md)
    }

    private var heroCard: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                // Execution badge (prominent)
                ModernExecutionBadge(
                    modelName: metadata.modelUsed,
                    ttft: metadata.timeToFirstToken,
                    retrievalConfigSummary: metadata.retrievalConfigSummary
                )

                Spacer()

                // Tool calls if any
                if let toolCalls = metadata.toolCallsMade, toolCalls > 0 {
                    toolCallBadge(count: toolCalls)
                }

                // Speed indicator
                if let tps = metadata.tokensPerSecond {
                    speedBadge(tps: tps)
                }
            }

            // Model name subtitle
            if !metadata.modelUsed.isEmpty {
                Text(metadata.modelUsed)
                    .font(DSTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DSSpacing.md)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: DSSpacing.sm) {
            ModernStatCell(
                value: metadata.timeToFirstToken != nil
                    ? String(format: "%.0f", metadata.timeToFirstToken! * 1000)
                    : "—",
                unit: "ms",
                label: "TTFT",
                icon: "bolt.fill",
                color: ttftColor
            )

            ModernStatCell(
                value: "\(metadata.tokensGenerated)", 
                unit: "tok",
                label: "Generated",
                icon: "number",
                color: .blue
            )

            ModernStatCell(
                value: String(format: "%.1f", metadata.totalGenerationTime),
                unit: "s",
                label: "Duration",
                icon: "clock.fill",
                color: .purple
            )

            ModernStatCell(
                value: "\(retrievedChunks.count)", 
                unit: "",
                label: "Sources",
                icon: "doc.text.fill",
                color: sourceQualityColor
            )
        }
    }

    private var ttftColor: Color {
        guard let ttft = metadata.timeToFirstToken else { return .secondary }
        if ttft < 0.5 { return .green }
        if ttft < 1.0 { return .blue }
        return .orange
    }

    private var sourceQualityColor: Color {
        guard !retrievedChunks.isEmpty else { return .secondary }
        let avg = retrievedChunks.map(\.similarityScore).reduce(0, +) / Float(retrievedChunks.count)
        if avg > 0.7 { return .green }
        if avg > 0.5 { return .blue }
        if avg > 0.3 { return .orange }
        return .red
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Insights", systemImage: "lightbulb.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: DSSpacing.xs) {
                if let ttft = metadata.timeToFirstToken, ttft > 0 {
                    ModernInsightRow(
                        icon: ttft < 0.5 ? "bolt.fill" : "clock",
                        text: ttft < 0.5
                            ? "Fast first token (\(String(format: "%.0fms", ttft * 1000)))"
                            : "First token in \(String(format: "%.1fs", ttft))",
                        color: ttft < 0.5 ? .green : (ttft < 1.0 ? .blue : .orange)
                    )
                }

                if let tps = metadata.tokensPerSecond, tps > 0 {
                    ModernInsightRow(
                        icon: tps > 30 ? "flame.fill" : "speedometer",
                        text: tps > 30
                            ? "Excellent speed (\(String(format: "%.0f", tps)) t/s)"
                            : "Generation at \(String(format: "%.0f", tps)) t/s",
                        color: tps > 30 ? .green : (tps > 15 ? .blue : .orange)
                    )
                }

                if let provider = metadata.embeddingProvider {
                    let isContextual = provider.contains("contextual")
                    ModernInsightRow(
                        icon: isContextual ? "sparkles" : "bolt.badge.a",
                        text: isContextual ? "Contextual Embeddings (+15-25% accuracy)" : "Standard Embeddings",
                        color: isContextual ? .purple : .blue
                    )
                }

                if let decision = metadata.gatingDecision {
                    let info = gatingInfo(for: decision)
                    ModernInsightRow(icon: info.0, text: info.1, color: info.2)
                }
            }
        }
        .padding(DSSpacing.md)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Sources Content

    private var sourcesContent: some View {
        VStack(spacing: DSSpacing.md) { 
            if retrievedChunks.isEmpty {
                emptySourcesState
            } else {
                // Quality overview header
                ModernSourcesQualityHeader(chunks: retrievedChunks)

                // Source cards
                ForEach(Array(retrievedChunks.enumerated()), id: \.offset) { index, chunk in
                    ModernSourceCard(chunk: chunk, rank: index + 1)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
    }

    private var emptySourcesState: some View {
        VStack(spacing: DSSpacing.md) {
            ZStack {
                Circle()
                    .fill(DSColors.surface)
                    .frame(width: 80, height: 80)
                Image(systemName: "doc.text.magnifyingglass")
.font(.system(size: 32, weight: .light))
    .foregroundStyle(.secondary.opacity(0.5))
            }

            VStack(spacing: DSSpacing.xxs) { 
                Text("No Sources Retrieved")
.font(.system(size: 16, weight: .semibold))
    .foregroundStyle(.secondary)
Text("This response was generated without document context")
.font(DSTypography.caption)
    .foregroundStyle(.tertiary)
    .multilineTextAlignment(.center)
            }
        }
.frame(maxWidth: .infinity)
.padding(.vertical, DSSpacing.xl)
    }

    // MARK: - Performance Content

    private var performanceContent: some View {
        VStack(spacing: DSSpacing.md) {
            // Timing breakdown card
            if metadata.retrievalTime > 0 || metadata.totalGenerationTime > 0 {
                timingCard
            }

            // Detailed metrics
            detailedMetricsCard

            // Architecture info
            architectureCard
        }
.padding(.horizontal, DSSpacing.md)
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Timing Breakdown", systemImage: "clock.arrow.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ModernTimingBar(
                embedding: metadata.retrievalTime * 0.3,
                searching: metadata.retrievalTime * 0.7, 
                generating: metadata.totalGenerationTime
            )
        }
.padding(DSSpacing.md)
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var detailedMetricsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Detailed Metrics", systemImage: "chart.bar.doc.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: DSSpacing.xs) {
                MetricRow(label: "Total Generation Time", value: String(format: "%.3fs", metadata.totalGenerationTime))
                MetricRow(label: "Retrieval Time", value: String(format: "%.3fs", metadata.retrievalTime))
                MetricRow(label: "Tokens Generated", value: "\(metadata.tokensGenerated)")

                if let tps = metadata.tokensPerSecond {
                    MetricRow(label: "Tokens/Second", value: String(format: "%.1f", tps))
                }
                if let ttft = metadata.timeToFirstToken {
                    MetricRow(label: "Time to First Token", value: String(format: "%.0fms", ttft * 1000))
                }

                if !retrievedChunks.isEmpty {
                    let avgScore = retrievedChunks.map(\.similarityScore).reduce(0, +) / Float(retrievedChunks.count)
                    MetricRow(label: "Avg Source Score", value: String(format: "%.1f%%", avgScore * 100))
                }
            }
        }
.padding(DSSpacing.md)
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Architecture", systemImage: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: DSSpacing.xs) {
                MetricRow(label: "Model", value: metadata.modelUsed.isEmpty ? "Unknown" : metadata.modelUsed)
                MetricRow(label: "Quality Mode", value: metadata.retrievalConfigSummary)

                if let provider = metadata.embeddingProvider {
                    MetricRow(label: "Embedding Provider", value: provider)
                }
                if let decision = metadata.gatingDecision {
                    MetricRow(label: "Gating Decision", value: decision)
                }
            }
        }
.padding(DSSpacing.md)
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helper Badges

    private func toolCallBadge(count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 9, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 5)
        .background(DSColors.chipBackground(for: .purple))
        .clipShape(Capsule())
    }

    private func speedBadge(tps: Float) -> some View {
        let color: Color = {
            if tps > 30 { return .green }
            if tps > 15 { return .blue }
            if tps > 5 { return .orange }
            return .red
        }()

        return HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(String(format: "%.0f", tps))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Text("t/s")
                .font(.system(size: 8, weight: .medium))
                .opacity(0.7)
        }
        .foregroundStyle(color)
.padding(.horizontal, DSSpacing.xs)
    .padding(.vertical, 5)
    .background(DSColors.chipBackground(for: color))
    .clipShape(Capsule())
    }

    private func gatingInfo(for decision: String) -> (String, String, Color) {
        switch decision {
        case "acceptance_override": return ("checkmark.seal.fill", "Acceptance Override", .green)
        case "lenient": return ("hand.thumbsup.fill", "Lenient Mode", .blue)
        case "strict_blocked": return ("exclamationmark.triangle.fill", "Strict Gate", .red)
        case "fallback_ondevice_low_confidence": return ("bolt.horizontal.circle.fill", "On-Device Fallback", .orange)
        default: return ("questionmark.circle.fill", decision, .gray)
        }
    }
}

// MARK: - Modern Stat Cell

private struct ModernStatCell: View { 
    let value: String
    let unit: String
    let label: String
    let icon: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: DSSpacing.xxs) {
            // Icon in colored circle
            ZStack {
                Circle()
                    .fill(DSColors.chipBackground(for: color))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }

            // Value + unit
            HStack(spacing: 1) {
                Text(value)
.font(.system(size: 18, weight: .bold, design: .rounded))
    .foregroundStyle(DSColors.primaryText)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Label
            Text(label)
.font(.system(size: 10, weight: .medium))
    .foregroundStyle(.secondary)
        }
.frame(maxWidth: .infinity)
    .padding(.vertical, DSSpacing.sm)
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }
}

// MARK: - Modern Execution Badge

private struct ModernExecutionBadge: View {
    let modelName: String
    let ttft: TimeInterval?
    let retrievalConfigSummary: String

    private var executionInfo: (icon: String, label: String, color: Color) {
        if retrievalConfigSummary == "High Accuracy" {
            return ("slider.horizontal.3", "High Accuracy", .purple)
        }
        if modelName.contains("GGUF") {
            return ("doc.badge.gearshape", "On-Device GGUF", .blue)
        } else if modelName.contains("Core ML") {
            return ("cpu", "Neural Engine", .purple)
        } else if modelName.contains("Apple Intelligence") || modelName.contains("Foundation") {
            if modelName.localizedCaseInsensitiveContains("private cloud")
                || modelName.localizedCaseInsensitiveContains("pcc")
                || modelName.localizedCaseInsensitiveContains("cloud compute")
            {
                return ("cloud.fill", "Private Cloud Compute", .blue)
            }
            if modelName.localizedCaseInsensitiveContains("on-device")
                || modelName.localizedCaseInsensitiveContains("on device")
            {
                return ("iphone", "On-Device", .green)
            }
            if let ttft = ttft {
                if ttft < 1.0 {
                    return ("iphone", "On-Device", .green)
                } else {
                    return ("cloud.fill", "Private Cloud", .blue)
                }
            }
            return ("sparkles", "Apple Intelligence", .indigo)
        } else if modelName.contains("On-Device Analysis") {
            return ("doc.text.magnifyingglass", "Extractive QA", .gray)
        }
        return ("questionmark.circle", "Unknown", .secondary)
    }

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            // Icon with subtle glow
            ZStack {
                Circle()
                    .fill(executionInfo.color.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: executionInfo.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(executionInfo.color)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(executionInfo.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(executionInfo.color)

                if let t = ttft {
                    Text(String(format: "%.0fms TTFT", t * 1000))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
.padding(.horizontal, DSSpacing.sm)
    .padding(.vertical, DSSpacing.xs)
    .background(
        RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
            .fill(DSColors.chipBackground(for: executionInfo.color))
    )
    .overlay(
        RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
            .strokeBorder(executionInfo.color.opacity(0.2), lineWidth: 0.5)
    )
    }
}

// MARK: - Modern Insight Row

private struct ModernInsightRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            // Small colored dot indicator
            Circle()
.fill(color)
.frame(width: 6, height: 6)
        }
.padding(.vertical, DSSpacing.xxs)
    }
}

// MARK: - Modern Sources Quality Header

private struct ModernSourcesQualityHeader: View { 
    let chunks: [RetrievedChunk]

    private var stats: (best: Float, worst: Float, avg: Float) {
        guard !chunks.isEmpty else { return (0, 0, 0) }
        let scores = chunks.map(\.similarityScore)
        return (scores.max() ?? 0, scores.min() ?? 0, scores.reduce(0, +) / Float(scores.count))
    }

    private var uniqueSources: Int {
        Set(chunks.map(\.sourceDocument)).count
    }

    private var qualityTier: (label: String, description: String, color: Color, icon: String) {
        let avg = stats.avg
        if avg > 0.7 {
            return ("Excellent Match", "High confidence context", .green, "checkmark.seal.fill")
        } else if avg > 0.5 {
            return ("Good Match", "Reliable context", .blue, "hand.thumbsup.fill")
        } else if avg > 0.3 {
            return ("Partial Match", "Some relevant context", .orange, "exclamationmark.triangle")
        } else {
            return ("Weak Match", "Limited context", .red, "xmark.circle")
        }
    }

    var body: some View { 
        VStack(spacing: DSSpacing.sm) { 
            // Quality tier header
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(DSColors.chipBackground(for: qualityTier.color))
                        .frame(width: 44, height: 44)
                    Image(systemName: qualityTier.icon)
.font(.system(size: 20, weight: .semibold))
    .foregroundStyle(qualityTier.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(qualityTier.label)
.font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                    Text(qualityTier.description)
.font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Big percentage
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f", stats.avg * 100))
.font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(qualityTier.color)
                    Text("avg %")
.font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Modern score range visualization
            if chunks.count > 1 { 
                ModernScoreRange(best: stats.best, worst: stats.worst, avg: stats.avg)
            }

            // Stats chips
            HStack(spacing: DSSpacing.xs) {
                StatChip(icon: "doc.text", value: "\(chunks.count)", label: chunks.count == 1 ? "chunk" : "chunks")
                StatChip(icon: "folder", value: "\(uniqueSources)", label: uniqueSources == 1 ? "source" : "sources")
                StatChip(icon: "arrow.up", value: String(format: "%.0f%%", stats.best * 100), label: "best", color: .green)
                if chunks.count > 1 { 
                    StatChip(icon: "arrow.down", value: String(format: "%.0f%%", stats.worst * 100), label: "lowest", color: stats.worst < 0.3 ? .red : .orange)
                }
            }
        }
        .padding(DSSpacing.md)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

private struct StatChip: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) { 
                Image(systemName: icon)
.font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
.font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DSColors.primaryText)
            }
            Text(label)
.font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ModernScoreRange: View { 
    let best: Float
    let worst: Float
    let avg: Float

    private func scoreColor(_ score: Float) -> Color {
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: DSSpacing.xxs) { 
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))

                    // Range bar
                    let worstX = geo.size.width * CGFloat(worst)
                    let bestX = geo.size.width * CGFloat(best)
                    let rangeWidth = bestX - worstX

                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [scoreColor(worst), scoreColor(best)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
.frame(width: max(rangeWidth, 8))
                        .offset(x: worstX)

                    // Average marker
                    let avgX = geo.size.width * CGFloat(avg)
                    ZStack { 
                        Circle()
                            .fill(.white)
.frame(width: 12, height: 12)
    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
Circle()
    .fill(scoreColor(avg))
.frame(width: 8, height: 8)
                    }
                    .offset(x: avgX - 6)
                }
            }
.frame(height: 12)

            // Labels
            HStack {
                Text("0%")
.font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Score Range")
.font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("100%")
.font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Modern Source Card

private struct ModernSourceCard: View { 
    let chunk: RetrievedChunk
    let rank: Int

    @State private var isExpanded = true

    private var similarityScore: Double {
        Double(chunk.similarityScore)
    }

    private var similarityColor: Color {
        if similarityScore >= 0.7 { return .green }
        if similarityScore >= 0.5 { return .blue }
        if similarityScore >= 0.3 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header row
            HStack(spacing: DSSpacing.xs) {
                // Rank badge with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [similarityColor, similarityColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Text("#\(rank)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Source name
                VStack(alignment: .leading, spacing: 1) { 
                    Text(chunk.sourceDocument.isEmpty ? "Document" : chunk.sourceDocument)
.font(.system(size: 13, weight: .semibold))
    .foregroundStyle(DSColors.primaryText)
    .lineLimit(1)

                    // Word/char count
                    Text("\(chunk.chunk.content.split(separator: " ").count) words")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Similarity percentage pill
                Text(String(format: "%.0f%%", similarityScore * 100))
.font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(similarityColor)
.padding(.horizontal, DSSpacing.xs)
    .padding(.vertical, 4)
    .background(DSColors.chipBackground(for: similarityColor))
    .clipShape(Capsule())

                // Expand toggle
                Button {
                    withAnimation(DSAnimations.snappySpring) { 
                        isExpanded.toggle()
                    }
                    DSHaptics.selection()
                } label: { 
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }

            // Similarity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [similarityColor.opacity(0.8), similarityColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * similarityScore)
                }
            }
.frame(height: 6)

            // Expandable content
            if isExpanded { 
                VStack(alignment: .leading, spacing: DSSpacing.xs) { 
                    Text(chunk.chunk.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
.textSelection(.enabled)

                    // Metadata chips
                    HStack(spacing: DSSpacing.xs) {
                        SourceMetaChip(icon: "text.alignleft", text: "\(chunk.chunk.content.count) chars")
                        SourceMetaChip(icon: "textformat", text: "\(chunk.chunk.content.split(separator: " ").count) words")
                    }
                }
                .padding(.top, DSSpacing.xxs)
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
            }
        }
.padding(DSSpacing.md)
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

private struct SourceMetaChip: View { 
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) { 
            Image(systemName: icon)
.font(.system(size: 9, weight: .medium))
            Text(text)
.font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.tertiary)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 3)
            .background(DSColors.surfaceElevated)
            .clipShape(Capsule())
    }
}

// MARK: - Modern Timing Bar

private struct ModernTimingBar: View {
    let embedding: TimeInterval
    let searching: TimeInterval
    let generating: TimeInterval

    private var total: TimeInterval {
        embedding + searching + generating
    }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if embedding > 0 {
                        timingSegment(
                            width: geo.size.width * CGFloat(embedding / total),
                            color: .purple,
                            label: "Embed"
                        )
                    }
                    if searching > 0 {
                        timingSegment(
                            width: geo.size.width * CGFloat(searching / total),
                            color: .blue,
                            label: "Search"
                        )
                    }
                    if generating > 0 {
                        timingSegment(
                            width: geo.size.width * CGFloat(generating / total),
                            color: .green,
                            label: "Generate"
                        )
                    }
                }
            }
            .frame(height: 24)

            // Legend
            HStack(spacing: DSSpacing.md) {
                timingLegendItem(color: .purple, label: "Embed", value: embedding)
                timingLegendItem(color: .blue, label: "Search", value: searching)
                timingLegendItem(color: .green, label: "Generate", value: generating)
                Spacer()
                Text(String(format: "Total: %.2fs", total))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timingSegment(width: CGFloat, color: Color, label: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: max(width, 4))
            .overlay(
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(width > 40 ? 1 : 0))
            )
    }

    private func timingLegendItem(color: Color, label: String, value: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label): \(String(format: "%.2fs", value))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DSColors.primaryText)
        }
.padding(.vertical, DSSpacing.xxs)
    }
}

// MARK: - Legacy Support (for external references)

struct ResponseDetailMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(DSColors.secondaryText)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DSColors.primaryText)
        }
    }
}

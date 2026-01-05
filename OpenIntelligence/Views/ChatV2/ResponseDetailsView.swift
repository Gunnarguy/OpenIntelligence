//
//  ResponseDetailsView.swift
//  OpenIntelligence
//
//  Centralized chat response details view for ChatV2 with granular metrics
//

import SwiftUI

struct ChatResponseDetailsView: View {
    let metadata: ResponseMetadata
    let retrievedChunks: [RetrievedChunk]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // Hero section: Model + Key Stats
                    heroSection

                    // Sources section (most important - shown first)
                    sourcesSection

                    // Performance details (collapsed by default)
                    performanceSection
                }
                .padding(.vertical)
            }
            .background(DSColors.background)
            .navigationTitle("Response Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero Section (Model + Stats at a glance)

    private var heroSection: some View {
        VStack(spacing: 12) {
            // Model and execution
            HStack(spacing: 8) {
                ModelExecutionBadge(
                    modelName: metadata.modelUsed,
                    ttft: metadata.timeToFirstToken,
                    retrievalConfigSummary: metadata.retrievalConfigSummary
                )

                if let toolCalls = metadata.toolCallsMade, toolCalls > 0 {
                    ToolCallBadge(count: toolCalls)
                }

                Spacer()

                // Speed indicator
                if let tps = metadata.tokensPerSecond {
                    SpeedBadge(tokensPerSecond: tps)
                }
            }
            .padding(.horizontal)

            // Quick stats row
            HStack(spacing: 16) {
                QuickStat(
                    value: metadata.timeToFirstToken != nil ?
                        String(format: "%.0fms", metadata.timeToFirstToken! * 1000) : "—",
                    label: "First Token"
                )

                Divider().frame(height: 24)

                QuickStat(
                    value: "\(metadata.tokensGenerated)",
                    label: "Tokens"
                )

                Divider().frame(height: 24)

                QuickStat(
                    value: String(format: "%.1fs", metadata.totalGenerationTime),
                    label: "Total Time"
                )

                if !retrievedChunks.isEmpty {
                    Divider().frame(height: 24)

                    QuickStat(
                        value: "\(retrievedChunks.count)",
                        label: "Sources"
                    )
                }
            }
            .padding(.horizontal)
.padding(.vertical, 12)
    .background(Color(uiColor: .secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding(.horizontal)
        }
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack { 
                Label("Retrieved Sources", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal)

            if retrievedChunks.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No Sources Retrieved")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("This response was generated without document context")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
.frame(maxWidth: .infinity)
    .padding(.vertical, 32)
    .padding(.horizontal)
            } else {
                // Quality Overview Card
                SourcesQualityOverview(chunks: retrievedChunks)
                    .padding(.horizontal)

                // Individual source cards
                VStack(spacing: 10) {
                    ForEach(Array(retrievedChunks.enumerated()), id: \.offset) { index, chunk in
                        SourceCard(chunk: chunk, rank: index + 1)
                    }
                }
.padding(.horizontal)
            }
        }
    }

    // MARK: - Performance Section (Collapsible)

    private var performanceSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                // Timing breakdown
                if metadata.retrievalTime > 0 || metadata.totalGenerationTime > 0 {
                    TimingBreakdownView(
                        embedding: metadata.retrievalTime * 0.3,
                        searching: metadata.retrievalTime * 0.7,
                        generating: metadata.totalGenerationTime,
                        total: metadata.totalGenerationTime + metadata.retrievalTime
                    )
                }

                // Performance insights
                performanceInsights

                // Embedding provider info
                if let provider = metadata.embeddingProvider {
                    embeddingProviderRow(provider: provider)
                }

                // Gating decision if present
                if let decision = metadata.gatingDecision {
                    gatingRow(decision: decision)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Performance Details", systemImage: "gauge.with.dots.needle.67percent")
                .font(.system(size: 15, weight: .semibold))
        }
        .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
    }

    private var performanceInsights: some View { 
        let ttft = metadata.timeToFirstToken ?? 0
        let tps = metadata.tokensPerSecond ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            if ttft > 0 {
                InsightRow(
                    icon: ttft < 0.5 ? "bolt.fill" : "clock",
                    text: ttft < 0.5 ? "Fast first token (\(String(format: "%.0fms", ttft * 1000)))" :
                        "First token in \(String(format: "%.1fs", ttft))",
                    color: ttft < 0.5 ? .green : (ttft < 1.0 ? .blue : .orange)
                )
            }

            if tps > 0 {
                InsightRow(
                    icon: tps > 30 ? "flame.fill" : "speedometer",
                    text: tps > 30 ? "Excellent speed (\(String(format: "%.0f", tps)) t/s)" :
                        "Generation at \(String(format: "%.0f", tps)) t/s",
                    color: tps > 30 ? .green : (tps > 15 ? .blue : .orange)
                )
            }
        }
    }

    private func embeddingProviderRow(provider: String) -> some View {
        let isContextual = provider.contains("contextual")
        return HStack(spacing: 8) {
            Image(systemName: isContextual ? "sparkles" : "bolt.badge.a")
                .foregroundStyle(isContextual ? .purple : .blue)
            Text(isContextual ? "Contextual Embeddings" : "Standard Embeddings")
                .font(.system(size: 13))
            Spacer()
            if isContextual {
                Text("+15-25% accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private func gatingRow(decision: String) -> some View {
        let (icon, label, color) = gatingInfo(for: decision)
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13))
            Spacer()
        }
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

// MARK: - Quick Stat

private struct QuickStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DSColors.primaryText)
            Text(label)
                .font(.system(size: 10))
.foregroundStyle(.secondary)
        }
    }
}

// MARK: - Speed Badge

private struct SpeedBadge: View {
    let tokensPerSecond: Float

    private var color: Color {
        if tokensPerSecond > 30 { return .green }
        if tokensPerSecond > 15 { return .blue }
        if tokensPerSecond > 5 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
            Text(String(format: "%.0f t/s", tokensPerSecond))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Quality Summary Badge

private struct QualitySummaryBadge: View {
    let chunks: [RetrievedChunk]

    private var averageScore: Float {
        guard !chunks.isEmpty else { return 0 }
        let total = chunks.reduce(0.0) { $0 + Double($1.similarityScore) }
        return Float(total / Double(chunks.count))
    }

    private var qualityInfo: (label: String, color: Color) {
        if averageScore > 0.7 { return ("Excellent", .green) }
        if averageScore > 0.5 { return ("Good", .blue) }
        if averageScore > 0.3 { return ("Fair", .orange) }
        return ("Weak", .red)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(qualityInfo.color)
                .frame(width: 6, height: 6)
            Text(qualityInfo.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(qualityInfo.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(qualityInfo.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Sources Quality Overview (replaces confusing bar chart)

private struct SourcesQualityOverview: View {
    let chunks: [RetrievedChunk]

    private var stats: (best: Float, worst: Float, avg: Float, spread: Float) {
        guard !chunks.isEmpty else { return (0, 0, 0, 0) }
        let scores = chunks.map(\.similarityScore)
        let best = scores.max() ?? 0
        let worst = scores.min() ?? 0
        let avg = scores.reduce(0, +) / Float(scores.count)
        let spread = best - worst
        return (best, worst, avg, spread)
    }

    private var uniqueSources: Int {
        Set(chunks.map(\.sourceDocument)).count
    }

    private var qualityTier: (label: String, description: String, color: Color, icon: String) {
        let avg = stats.avg
        if avg > 0.7 {
            return ("Excellent Match", "High confidence in retrieved context", .green, "checkmark.seal.fill")
        } else if avg > 0.5 {
            return ("Good Match", "Reliable context retrieved", .blue, "hand.thumbsup.fill")
        } else if avg > 0.3 {
            return ("Partial Match", "Some relevant context found", .orange, "exclamationmark.triangle")
        } else {
            return ("Weak Match", "Limited relevant context", .red, "xmark.circle")
        }
    }

    var body: some View { 
        VStack(spacing: 12) {
            // Quality tier header
            HStack(spacing: 10) {
                Image(systemName: qualityTier.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(qualityTier.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(qualityTier.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                    Text(qualityTier.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Average score (big number)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f", stats.avg * 100))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(qualityTier.color)
                    Text("avg %")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Stats grid
            HStack(spacing: 0) {
                StatCell(
                    value: "\(chunks.count)",
                    label: chunks.count == 1 ? "chunk" : "chunks",
                    icon: "doc.text"
                )

                Divider().frame(height: 30)

                StatCell(
                    value: "\(uniqueSources)",
                    label: uniqueSources == 1 ? "source" : "sources",
                    icon: "folder"
                )

                Divider().frame(height: 30)

                StatCell(
                    value: String(format: "%.0f%%", stats.best * 100),
                    label: "best",
                    icon: "arrow.up",
                    color: .green
                )

                if chunks.count > 1 {
                    Divider().frame(height: 30)

                    StatCell(
                        value: String(format: "%.0f%%", stats.worst * 100),
                        label: "lowest",
                        icon: "arrow.down",
                        color: stats.worst < 0.3 ? .red : .orange
                    )
                }
            }

            // Score range visualization
            if chunks.count > 1 {
                ScoreRangeBar(best: stats.best, worst: stats.worst, avg: stats.avg)
            }
        }
        .padding(14)
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatCell: View { 
    let value: String
    let label: String
    let icon: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) { 
                Image(systemName: icon)
.font(.system(size: 10))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DSColors.primaryText)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScoreRangeBar: View {
    let best: Float
    let worst: Float
    let avg: Float

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Full bar background (0-100%)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))

                    // Range indicator (worst to best)
                    let worstX = geo.size.width * CGFloat(worst)
                    let bestX = geo.size.width * CGFloat(best)
                    let rangeWidth = bestX - worstX

                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [scoreColor(worst), scoreColor(best)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(rangeWidth, 4))
                        .offset(x: worstX)

                    // Average marker
                    let avgX = geo.size.width * CGFloat(avg)
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: avgX - 4)
                }
            }
.frame(height: 8)

            // Labels
            HStack {
                Text("0%")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Score Range")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("100%")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func scoreColor(_ score: Float) -> Color {
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }
}

// MARK: - Source Card (Always Expanded)

private struct SourceCard: View { 
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
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                // Rank badge
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(similarityColor)
                    .clipShape(Capsule())

                // Source name
                Text(chunk.sourceDocument.isEmpty ? "Document" : chunk.sourceDocument)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DSColors.primaryText)
                    .lineLimit(1)

                Spacer()

                // Similarity percentage
                Text(String(format: "%.0f%%", similarityScore * 100))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(similarityColor)

                // Expand/collapse toggle
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: { 
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Similarity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(similarityColor)
                        .frame(width: geo.size.width * similarityScore)
                }
            }
            .frame(height: 4)

            // Content (expandable)
            if isExpanded { 
                Text(chunk.chunk.content)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
.padding(.top, 4)

                HStack(spacing: 12) {
                    Label("\(chunk.chunk.content.count) chars", systemImage: "text.alignleft")
                    Label("\(chunk.chunk.content.split(separator: " ").count) words", systemImage: "textformat")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Insight Row

private struct InsightRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Metric Row (Legacy Support)

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

// MARK: - Model Execution Badge

/// Compact badge showing model and execution location
private struct ModelExecutionBadge: View {
    let modelName: String
    let ttft: TimeInterval?
    let retrievalConfigSummary: String

    private var executionInfo: (icon: String, label: String, color: Color) {
        // High accuracy mode takes priority for visual emphasis
        if retrievalConfigSummary == "High Accuracy" {
            return ("slider.horizontal.3", "High Accuracy", .purple)
        }

        // Determine execution location based on model name and TTFT
        if modelName.contains("GGUF") {
            return ("doc.badge.gearshape", "On-Device GGUF", .blue)
        } else if modelName.contains("Core ML") {
            return ("cpu", "Neural Engine", .purple)
        } else if modelName.contains("Apple Intelligence") || modelName.contains("Foundation") {
            // Prefer explicit execution location when available in the model name.
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

            // Fall back to TTFT heuristic only when we don't have explicit labeling.
            if let ttft = ttft {
                if ttft < 1.0 {
                    return ("iphone", "On-Device (inferred)", .green)
                } else {
                    return ("cloud.fill", "Private Cloud (inferred)", .blue)
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
            Image(systemName: executionInfo.icon)
                .font(.system(size: 10, weight: .semibold))

            Text(executionInfo.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(executionInfo.color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(DSColors.chipBackground(for: executionInfo.color))
        )
        .overlay(
            Capsule()
                .strokeBorder(executionInfo.color.opacity(0.2), lineWidth: 0.5)
        )
    }
}

//
//  ResponseDetailsView.swift
//  OpenIntelligence
//
//  User-friendly response details - single scrollable view
//

import SwiftUI

struct ChatResponseDetailsView: View {
    let metadata: ResponseMetadata
    let retrievedChunks: [RetrievedChunk]
    let structuredAnswer: StructuredAnswer?

    @Environment(\.dismiss) private var dismiss
    @State private var showPerformance = false

    init(
        metadata: ResponseMetadata,
        retrievedChunks: [RetrievedChunk],
        structuredAnswer: StructuredAnswer? = nil
    ) {
        self.metadata = metadata
        self.retrievedChunks = retrievedChunks
        self.structuredAnswer = structuredAnswer
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // 1. Verification Hero
                    verificationHero

                    // 2. How this answer was made
                    answerSummaryCard

                    // 3. Structured summary
                    structuredSummarySection

                    // 4. Sources used
                    sourcesSection

                    // 5. Performance (collapsible)
                    performanceSection
                }
                .padding(.vertical, DSSpacing.md)
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

    // MARK: - Verification Hero

    private var verificationStatus: VerificationInfo {
        guard let decision = metadata.gatingDecision else {
            return VerificationInfo(
                title: "Verified Response",
                subtitle: "Answer passed all quality checks",
                icon: "checkmark.shield.fill",
                color: .green,
                level: .verified
            )
        }
        return VerificationInfo.from(gatingDecision: decision)
    }

    private var verificationHero: some View {
        let info = verificationStatus

        return VStack(spacing: DSSpacing.sm) {
            ZStack {
                Circle()
                    .fill(info.color.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: info.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(info.color)
            }

            Text(info.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DSColors.primaryText)

            Text(info.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Answer Summary Card

    private var executionLabel: String {
        let model = metadata.modelUsed
        if model.localizedCaseInsensitiveContains("private cloud") || model.localizedCaseInsensitiveContains("pcc") || model.localizedCaseInsensitiveContains("cloud compute") {
            return "Private Cloud Compute"
        }
        if model.localizedCaseInsensitiveContains("on-device") || model.localizedCaseInsensitiveContains("on device") {
            return "On-Device"
        }
        if model.contains("Apple") || model.contains("Foundation") {
            if let ttft = metadata.timeToFirstToken, ttft < 1.0 {
                return "On-Device"
            }
            return "Apple Intelligence"
        }
        if model.contains("GGUF") { return "On-Device (GGUF)" }
        if model.contains("Agentic") { return "Multi-Session Reasoning" }
        return "AI-Generated"
    }

    private var executionIcon: String {
        let label = executionLabel
        if label.contains("Cloud") { return "cloud.fill" }
        if label.contains("On-Device") { return "iphone" }
        if label.contains("Multi-Session") { return "brain.head.profile" }
        return "sparkles"
    }

    private var executionColor: Color {
        let label = executionLabel
        if label.contains("Cloud") { return .blue }
        if label.contains("On-Device") { return .green }
        if label.contains("Multi-Session") { return .purple }
        return .indigo
    }

    private var answerSummaryCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("How this answer was made", systemImage: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            // Execution method
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(executionColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: executionIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(executionColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(executionLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)

                    if let mode = metadata.qualityModeName {
                        Text(mode)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Time
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1fs", metadata.totalGenerationTime))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DSColors.primaryText)
                    Text("total time")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Quick stats row
            HStack(spacing: 0) {
                summaryStatItem(
                    value: "\(retrievedChunks.count)",
                    label: retrievedChunks.count == 1 ? "source" : "sources",
                    icon: "doc.text.fill",
                    color: .blue
                )

                summaryStatItem(
                    value: "\(metadata.tokensGenerated)",
                    label: "tokens",
                    icon: "text.word.spacing",
                    color: .purple
                )

                if let tps = metadata.tokensPerSecond, tps > 0 {
                    summaryStatItem(
                        value: String(format: "%.0f/s", tps),
                        label: "speed",
                        icon: "bolt.fill",
                        color: tps > 30 ? .green : (tps > 15 ? .blue : .orange)
                    )
                }

                if let tools = metadata.toolCallsMade, tools > 0 {
                    summaryStatItem(
                        value: "\(tools)",
                        label: tools == 1 ? "tool call" : "tool calls",
                        icon: "wrench.fill",
                        color: .orange
                    )
                }
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }

    private func summaryStatItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DSColors.primaryText)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var structuredSummarySection: some View {
        Group {
            if let structuredAnswer {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Label("Structured Answer", systemImage: "list.bullet.rectangle.portrait")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(structuredAnswer.answerType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DSColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DSColors.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 0) {
                        summaryStatItem(value: "\(structuredAnswer.claims.count)", label: "claims", icon: "text.quote", color: .indigo)
                        summaryStatItem(value: "\(structuredAnswer.evidence.count)", label: "evidence", icon: "doc.on.doc.fill", color: .blue)
                        summaryStatItem(value: "\(structuredAnswer.missing.count)", label: "gaps", icon: "questionmark.circle.fill", color: structuredAnswer.missing.isEmpty ? .green : .orange)
                    }

                    if !structuredAnswer.claims.isEmpty {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            ForEach(Array(structuredAnswer.claims.prefix(3).enumerated()), id: \.offset) { index, claim in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Claim \(index + 1)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    Text(claim.claim)
                                        .font(.system(size: 13))
                                        .foregroundStyle(DSColors.primaryText)
                                    HStack(spacing: 6) {
                                        if let verdict = claim.verificationVerdict {
                                            Text(claimVerificationTitle(verdict))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(claimVerificationColor(verdict))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(claimVerificationColor(verdict).opacity(0.12))
                                                .clipShape(Capsule())
                                        }

                                        Text("Evidence: \(claim.evidenceIds.count) • Confidence: \(Int(claim.confidence * 100))%")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let details = claim.verificationDetails,
                                       let verdict = claim.verificationVerdict,
                                       verdict != .supported
                                    {
                                        Text(details)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !structuredAnswer.missing.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Gaps")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            ForEach(Array(structuredAnswer.missing.prefix(2).enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(DSSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.surface)
                )
                .padding(.horizontal, DSSpacing.md)
            }
        }
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack {
                Label("Sources", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !retrievedChunks.isEmpty {
                    let avg = retrievedChunks.map(\.similarityScore).reduce(0, +) / Float(retrievedChunks.count)
                    MatchQualityPill(score: avg)
                }
            }
            .padding(.horizontal, DSSpacing.md)

            if retrievedChunks.isEmpty {
                noSourcesCard
            } else {
                ForEach(Array(retrievedChunks.enumerated()), id: \.offset) { index, chunk in
                    SourceCard(chunk: chunk, rank: index + 1)
                }
            }
        }
    }

    private var noSourcesCard: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))

            Text("No document sources used")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text("This response was generated from general knowledge")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Performance Section (Collapsible)

    private var performanceSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(DSAnimations.snappySpring) {
                    showPerformance.toggle()
                }
                DSHaptics.selection()
            } label: {
                HStack {
                    Label("Performance Details", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: showPerformance ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(DSSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.surface)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DSSpacing.md)

            if showPerformance {
                VStack(spacing: DSSpacing.sm) {
                    // Timing breakdown
                    if metadata.retrievalTime > 0 || metadata.totalGenerationTime > 0 {
                        timingBreakdown
                    }

                    // All metrics
                    metricsGrid
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
        }
    }

    private var timingBreakdown: some View {
        let retrievalTime = metadata.retrievalTime
        let genTime = metadata.totalGenerationTime
        let total = retrievalTime + genTime

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Timing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)

            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if retrievalTime > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: max(geo.size.width * CGFloat(retrievalTime / total), 4))
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: max(geo.size.width * CGFloat(genTime / total), 4))
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: DSSpacing.md) {
                HStack(spacing: 4) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text("Search: \(String(format: "%.2fs", retrievalTime))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Generate: \(String(format: "%.2fs", genTime))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("All Metrics")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)

            VStack(spacing: 0) {
                PerfMetricRow(label: "Model", value: metadata.modelUsed.isEmpty ? "Unknown" : metadata.modelUsed)
                PerfMetricRow(label: "Quality Mode", value: metadata.qualityModeName ?? metadata.retrievalConfigSummary)
                PerfMetricRow(label: "Total Time", value: String(format: "%.3fs", metadata.totalGenerationTime))
                PerfMetricRow(label: "Retrieval Time", value: String(format: "%.3fs", metadata.retrievalTime))
                PerfMetricRow(label: "Tokens Generated", value: "\(metadata.tokensGenerated)")

                if let tps = metadata.tokensPerSecond {
                    PerfMetricRow(label: "Tokens/Second", value: String(format: "%.1f", tps))
                }
                if let ttft = metadata.timeToFirstToken {
                    PerfMetricRow(label: "First Token", value: String(format: "%.0fms", ttft * 1000))
                }
                if let provider = metadata.embeddingProvider {
                    PerfMetricRow(label: "Embeddings", value: provider)
                }
                if let decision = metadata.gatingDecision {
                    PerfMetricRow(label: "Verification", value: VerificationInfo.from(gatingDecision: decision).title)
                }
                if metadata.usedAgenticMode {
                    PerfMetricRow(label: "Reasoning", value: "Multi-Session Agentic")
                }
                if !retrievedChunks.isEmpty {
                    let avgScore = retrievedChunks.map(\.similarityScore).reduce(0, +) / Float(retrievedChunks.count)
                    PerfMetricRow(label: "Avg Source Match", value: String(format: "%.1f%%", avgScore * 100))
                }
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    private func claimVerificationTitle(_ verdict: StructuredAnswer.Claim.VerificationVerdict) -> String {
        switch verdict {
        case .supported:
            return "Supported"
        case .partial:
            return "Partial"
        case .unsupported:
            return "Unsupported"
        }
    }

    private func claimVerificationColor(_ verdict: StructuredAnswer.Claim.VerificationVerdict) -> Color {
        switch verdict {
        case .supported:
            return .green
        case .partial:
            return .orange
        case .unsupported:
            return .red
        }
    }
}

// MARK: - Verification Info Model

private struct VerificationInfo {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let level: VerificationLevel

    enum VerificationLevel {
        case verified, partial, lowConfidence, unverified, noSources
    }

    static func from(gatingDecision: String) -> VerificationInfo {
        let lower = gatingDecision.lowercased()

        if lower.contains("no_sources") || lower.contains("no_documents") || lower.contains("context_empty") {
            return VerificationInfo(
                title: "No Sources Available",
                subtitle: "No matching documents were found for this question. The response may use general knowledge.",
                icon: "questionmark.circle.fill",
                color: .secondary,
                level: .noSources
            )
        }

        if lower.contains("verification_gates_failed") || lower.contains("missing_citations") {
            return VerificationInfo(
                title: "Could Not Verify",
                subtitle: "The response couldn't be fully verified against your documents. Take it with a grain of salt.",
                icon: "xmark.shield.fill",
                color: .red,
                level: .unverified
            )
        }

        if lower.contains("low_confidence") || lower.contains("rerank_empty") || lower.contains("mmr_empty") || lower.contains("relevance_gate_failed") {
            return VerificationInfo(
                title: "Low Confidence",
                subtitle: "The source documents had limited relevance. The answer may be incomplete or approximate.",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                level: .lowConfidence
            )
        }

        if lower.contains("reliability_fallback") || lower.contains("high_accuracy_blocked") {
            return VerificationInfo(
                title: "Partially Verified",
                subtitle: "Some parts of this answer are well-supported by your documents, but not all claims could be verified.",
                icon: "shield.lefthalf.filled",
                color: .yellow,
                level: .partial
            )
        }

        // Default: verified
        return VerificationInfo(
            title: "Verified Response",
            subtitle: "This answer is well-supported by your documents and passed quality verification.",
            icon: "checkmark.shield.fill",
            color: .green,
            level: .verified
        )
    }
}

// MARK: - Match Quality Pill

private struct MatchQualityPill: View {
    let score: Float

    private var label: String {
        if score > 0.7 { return "Excellent" }
        if score > 0.5 { return "Good" }
        if score > 0.3 { return "Fair" }
        return "Weak"
    }

    private var color: Color {
        if score > 0.7 { return .green }
        if score > 0.5 { return .blue }
        if score > 0.3 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DSColors.chipBackground(for: color))
        .clipShape(Capsule())
    }
}

// MARK: - Source Card

private struct SourceCard: View {
    let chunk: RetrievedChunk
    let rank: Int

    @State private var isExpanded = false

    private var filename: String {
        if chunk.sourceDocument.isEmpty { return "Document" }
        return URL(fileURLWithPath: chunk.sourceDocument).lastPathComponent
    }

    private var score: Double {
        Double(chunk.similarityScore)
    }

    private var scoreColor: Color {
        if score >= 0.7 { return .green }
        if score >= 0.5 { return .blue }
        if score >= 0.3 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header
            HStack(spacing: DSSpacing.xs) {
                // Rank indicator
                ZStack {
                    Circle()
                        .fill(scoreColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("\(rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                }

                // File info
                VStack(alignment: .leading, spacing: 1) {
                    Text(filename)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack(spacing: 4) {
                        if let page = chunk.pageNumber {
                            Text("Page \(page)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(chunk.chunk.content.split(separator: " ").count) words")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Match score
                Text(String(format: "%.0f%%", score * 100))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor.opacity(0.7))
                        .frame(width: geo.size.width * score)
                }
            }
            .frame(height: 4)

            // Expandable content
            Button {
                withAnimation(DSAnimations.snappySpring) {
                    isExpanded.toggle()
                }
                DSHaptics.selection()
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Hide excerpt" : "Show excerpt")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    Text(chunk.chunk.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 250)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }
}

// MARK: - Performance Metric Row

private struct PerfMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSColors.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.vertical, 6)
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

#Preview {
    NavigationStack {
        ChatResponseDetailsView(
            metadata: ResponseMetadata(
                totalGenerationTime: 2.3,
                tokensGenerated: 156,
                tokensPerSecond: 28.5,
                modelUsed: "Apple FM",
                retrievalTime: 0.45,
                retrievalConfigSummary: "Balanced",
                qualityModeName: "Standard"
            ),
            retrievedChunks: []
        )
    }
}

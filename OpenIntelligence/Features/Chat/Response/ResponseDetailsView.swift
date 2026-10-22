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
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // 1. Verification Hero
                    verificationHero

                    // Source Fidelity Status Card
                    SourceFidelityStatus(
                        level: fidelityLevel,
                        score: averageFidelityScore > 0 ? averageFidelityScore : nil
                    )
                    .padding(.horizontal, DSSpacing.md)

                    // Execution Route Trace
                    if let route = metadata.executionRoute {
                        routeTraceSection(route)
                    }

                    // Token Budget Allocation
                    if let budget = metadata.tokenBudget {
                        tokenBudgetSection(budget)
                    }

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
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 24)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 24)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                #endif
            }
        }
    }

    private func routeTraceSection(_ route: ResponseMetadata.ExecutionRoute) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("Execution Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(DSColors.secondaryText)

            HStack(spacing: DSSpacing.sm) {
                Text(route.emoji)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(route.path)
                        .scaledFont(size: 15, weight: .bold)
                        .foregroundStyle(DSColors.primaryText)
                    
                    if let policy = route.policyApplied {
                        Text("Policy: \(policy)")
                            .scaledFont(size: 11, weight: .medium)
                            .foregroundStyle(DSColors.readable(DSColors.accent))
                    }
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(DSSpacing.sm)
            .background(DSColors.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Decision Logic")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
                    .textCase(.uppercase)
                
                Text(route.reason)
                    .scaledFont(size: 13)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(nil)
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }

    private func tokenBudgetSection(_ budget: ResponseMetadata.TokenBudget) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("Token Capacity Allocation", systemImage: "gauge.medium")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(DSColors.secondaryText)

            VStack(spacing: DSSpacing.sm) {
                // Allocation bar
                GeometryReader { geo in
                    HStack(spacing: DSSpacing.xxs) {
                        tokenBarSegment(width: geo.size.width * CGFloat(Double(budget.systemPrompt) / Double(budget.totalLimit)), color: .blue, label: "System")
                        tokenBarSegment(width: geo.size.width * CGFloat(Double(budget.retrievedContext) / Double(budget.totalLimit)), color: .purple, label: "Context")
                        tokenBarSegment(width: geo.size.width * CGFloat(Double(budget.generation) / Double(budget.totalLimit)), color: .green, label: "Gen")
                        tokenBarSegment(width: geo.size.width * CGFloat(Double(budget.remaining) / Double(budget.totalLimit)), color: Color.secondary.opacity(0.1), label: "Free")
                    }
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                HStack {
                    Text("0")
                    Spacer()
                    Text("\(budget.totalLimit) tokens")
                        .scaledFont(size: 11, weight: .bold, design: .rounded)
                        .monospacedDigit()
                    Spacer()
                    Text("Max")
                }
                .scaledFont(size: 10)
                .foregroundStyle(DSColors.secondaryText)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                tokenBudgetStat(label: "System", value: budget.systemPrompt, color: .blue)
                tokenBudgetStat(label: "Context", value: budget.retrievedContext, color: .purple)
                tokenBudgetStat(label: "Generation", value: budget.generation, color: .green)
                tokenBudgetStat(label: "Available", value: budget.remaining, color: .secondary)
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }

    private func tokenBarSegment(width: CGFloat, color: Color, label: String) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0))
            .overlay(
                // Drawn inside its segment at a compact size so it stays inside the 24-point bar; the grid under the bar
                // names each part with its count, in text that grows (5.7).
                Text(label)
                    .scaledFont(size: 8, weight: .bold)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .foregroundStyle(.white)
                    .opacity(width > 30 ? 1 : 0)
            )
    }

    private func tokenBudgetStat(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: DSSpacing.sm) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 24)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
                Text("\(value)")
                    .scaledFont(size: 14, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var averageFidelityScore: Float {
        guard !retrievedChunks.isEmpty else { return 0 }
        return retrievedChunks.map(\.similarityScore).reduce(0, +) / Float(retrievedChunks.count)
    }

    private var fidelityLevel: SourceFidelityStatus.FidelityLevel {
        guard let decision = metadata.gatingDecision else {
            return .sourceLocked
        }
        let lower = decision.lowercased()
        if lower.contains("failed") || lower.contains("missing_citations") || lower.contains("abstain") {
            return .insufficientEvidence
        }
        if lower.contains("low_confidence") || lower.contains("fallback") {
            return .partiallySupported
        }
        return .sourceLocked
    }


    // MARK: - Verification Hero

    private var verificationStatus: VerificationInfo {
        VerificationInfo.from(gatingDecision: metadata.gatingDecision, claims: structuredAnswer?.claims ?? [])
    }

    private var verificationHero: some View {
        let info = verificationStatus

        return VStack(spacing: DSSpacing.sm) {
            ZStack {
                Circle()
                    .fill(info.color.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: info.icon)
                    .scaledFont(size: 28, weight: .semibold)
                    .foregroundStyle(info.color)
            }

            Text(info.title)
                .scaledFont(size: 18, weight: .bold)
                .foregroundStyle(DSColors.primaryText)

            Text(info.subtitle)
                .scaledFont(size: 14)
                .foregroundStyle(DSColors.secondaryText)
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
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(DSColors.secondaryText)

            // Execution method
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(executionColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: executionIcon)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(executionColor)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(executionLabel)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)

                    if let mode = metadata.qualityModeName {
                        Text(mode)
                            .scaledFont(size: 12)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                // Time
                VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                    Text(String(format: "%.1fs", metadata.totalGenerationTime))
                        .scaledFont(size: 16, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                    Text("total time")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
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
        VStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(color)
            Text(value)
                .scaledFont(size: 15, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
            Text(label)
                .scaledFont(size: 10)
                .foregroundStyle(DSColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var structuredSummarySection: some View {
        Group {
            if let structuredAnswer {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Label("Structured Answer", systemImage: "list.bullet.rectangle.portrait")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(DSColors.secondaryText)
                        Spacer()
                        Text(structuredAnswer.answerType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .scaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(DSColors.primaryText)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
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
                                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                    Text("Claim \(index + 1)")
                                        .scaledFont(size: 11, weight: .semibold)
                                        .foregroundStyle(DSColors.secondaryText)
                                    Text(GroundedAnswerView.inlineMarkdown(claim.claim))
                                        .scaledFont(size: 13)
                                        .foregroundStyle(DSColors.primaryText)
                                    HStack(spacing: DSSpacing.xs) {
                                        if let verdict = claim.verificationVerdict {
                                            Text(claimVerificationTitle(verdict))
                                                .scaledFont(size: 10, weight: .semibold)
                                                .foregroundStyle(DSColors.primaryText)
                                                .padding(.horizontal, DSSpacing.xs)
                                                .padding(.vertical, DSSpacing.xxs)
                                                .background(claimVerificationColor(verdict).opacity(0.12))
                                                .clipShape(Capsule())
                                        }

                                        Text("Evidence: \(claim.evidenceIds.count) • Confidence: \(Int(claim.confidence * 100))%")
                                            .scaledFont(size: 11)
                                            .monospacedDigit()
                                            .foregroundStyle(DSColors.secondaryText)
                                    }

                                    if let details = claim.verificationDetails,
                                       let verdict = claim.verificationVerdict,
                                       verdict != .supported
                                    {
                                        Text(details)
                                            .scaledFont(size: 11)
                                            .foregroundStyle(DSColors.secondaryText)
                                    }
                                }
                            }
                        }
                    }

                    if !structuredAnswer.missing.isEmpty {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text("Open Gaps")
                                .scaledFont(size: 11, weight: .semibold)
                                .foregroundStyle(DSColors.secondaryText)
                            ForEach(Array(structuredAnswer.missing.prefix(2).enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .scaledFont(size: 12)
                                    .foregroundStyle(DSColors.secondaryText)
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
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

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
                .scaledFont(size: 28, weight: .light)
                .foregroundStyle(DSColors.secondaryText)

            Text("No document sources used")
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(DSColors.secondaryText)

            Text("This response was generated from general knowledge")
                .scaledFont(size: 12)
                .foregroundStyle(DSColors.secondaryText)
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
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(DSColors.secondaryText)

                    Spacer()

                    Image(systemName: showPerformance ? "chevron.up" : "chevron.down")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(DSColors.secondaryText)
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
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(DSColors.secondaryText)

            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: DSSpacing.xxs) {
                        if retrievalTime > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.blue)
                                .frame(width: max(geo.size.width * CGFloat(retrievalTime / total), 4))
                        }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.green)
                            .frame(width: max(geo.size.width * CGFloat(genTime / total), 4))
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.xs) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text("Search: \(String(format: "%.2fs", retrievalTime))")
                        .scaledFont(size: 11)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.secondaryText)
                }
                HStack(spacing: DSSpacing.xs) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Generate: \(String(format: "%.2fs", genTime))")
                        .scaledFont(size: 11)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.secondaryText)
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
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(DSColors.secondaryText)

            VStack(spacing: 0) {
                PerfMetricRow(label: "Model", value: metadata.modelUsed.isEmpty ? "Unknown" : metadata.modelUsed)
                PerfMetricRow(label: "Quality Mode", value: metadata.qualityModeName ?? metadata.retrievalConfigSummary)
                PerfMetricRow(label: "Total Time", value: String(format: "%.3fs", metadata.totalGenerationTime))
                PerfMetricRow(label: "Retrieval Time", value: String(format: "%.3fs", metadata.retrievalTime))
                PerfMetricRow(label: "Tokens Generated", value: "\(metadata.tokensGenerated)")
                if let usage = metadata.appleUsage {
                    // Apple's own count for the whole answer, every model call added up (5.7).
                    PerfMetricRow(label: "Apple's Count", value: Self.appleUsageText(usage))
                }

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
                    PerfMetricRow(label: "Verification", value: VerificationInfo.from(gatingDecision: decision, claims: structuredAnswer?.claims ?? []).title)
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

    /// Apple's count for an answer in a line: tokens in (with how many came from the model's cache), tokens out,
    /// and reasoning tokens when there were any, which only Private Cloud Compute spends.
    nonisolated static func appleUsageText(_ usage: GenerationUsage) -> String {
        var text = "\(usage.inputTokens.formatted()) in (\(usage.cachedInputTokens.formatted()) cached), "
            + "\(usage.outputTokens.formatted()) out"
        if usage.reasoningTokens > 0 {
            text += ", \(usage.reasoningTokens.formatted()) reasoning"
        }
        return text
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
        case verified, partial, lowConfidence, unverified, noSources, notChecked
    }

    /// One reading of the gating string for the bubble and this sheet (`VerificationOutcome`).
    /// Before 5.6 a missing string read "Verified Response: Answer passed all quality checks", and
    /// so did `unverified:<gates>` and `verification_skipped`.
    static func from(gatingDecision: String?, claims: [StructuredAnswer.Claim] = []) -> VerificationInfo {
        switch VerificationOutcome.from(gatingDecision: gatingDecision, claims: claims) {
        case .noSources:
            return VerificationInfo(
                title: "No Sources Available",
                subtitle: "No matching documents were found for this question. The response may use general knowledge.",
                icon: "questionmark.circle.fill",
                color: .secondary,
                level: .noSources
            )
        case .notSupported:
            return VerificationInfo(
                title: "Could Not Verify",
                subtitle: "The response couldn't be fully verified against your documents. Take it with a grain of salt.",
                icon: "xmark.shield.fill",
                color: .red,
                level: .unverified
            )
        case .lowConfidence:
            return VerificationInfo(
                title: "Low Confidence",
                subtitle: "The source documents had limited relevance. The answer may be incomplete or approximate.",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                level: .lowConfidence
            )
        case .partial:
            return VerificationInfo(
                title: "Partially Verified",
                subtitle: "Some parts of this answer are well-supported by your documents, but not all claims could be verified.",
                icon: "shield.lefthalf.filled",
                color: .yellow,
                level: .partial
            )
        case .supported:
            return VerificationInfo(
                title: "Verified Response",
                subtitle: "This answer is well-supported by your documents and passed quality verification.",
                icon: "checkmark.shield.fill",
                color: .green,
                level: .verified
            )
        case .notChecked:
            return VerificationInfo(
                title: "Not Checked",
                subtitle: "No verification check ran on this answer. Open the sources below to check it against your documents.",
                icon: "shield.slash",
                color: .secondary,
                level: .notChecked
            )
        }
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
        // The word in the label color, the color in the dot and the tint (5.7): green on its own tint measured 2.01
        // to 1.
        HStack(spacing: DSSpacing.xxs) {
            Circle()
                .fill(DSColors.readable(color))
                .frame(width: 6, height: 6)
            Text(label)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColors.chipBackground(for: color))
        .clipShape(Capsule())
    }
}

// MARK: - Source Card

private struct SourceCard: View {
    let chunk: RetrievedChunk
    let rank: Int

    @State private var isExpanded = false
    @State private var shownPage: SourcePageTarget?
    @Environment(\.libraryDocumentLookup) private var libraryDocumentLookup

    /// The library's document and the page to show, when the source is a PDF on this device (5.7).
    private var pageTarget: (document: Document, page: Int)? {
        guard let document = libraryDocumentLookup?.document(chunk.chunk.documentId),
            let page = CitationSourceDocument.page(of: chunk, in: document)
        else { return nil }
        return (document, page)
    }

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
                    // The rank and the score in the label color, the score's color in the circle's tint and the
                    // bar (5.7): green numbers measured 1.79 to 1 on the tint and 1.99 on the card.
                    Text("\(rank)")
                        .scaledFont(size: 12, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }

                // File info
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(filename)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack(spacing: DSSpacing.xs) {
                        if let page = chunk.pageNumber {
                            Text("Page \(page)")
                                .scaledFont(size: 11)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        Text("\(chunk.chunk.content.split(separator: " ").count) words")
                            .scaledFont(size: 11)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                // Match score
                Text(String(format: "%.0f%%", score * 100))
                    .scaledFont(size: 14, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(scoreColor.opacity(0.7))
                        .frame(width: geo.size.width * score)
                }
            }
            .frame(height: 4)

            // Expandable content, and the page itself when the source is a PDF on this device (5.7), side by side
            // while they fit.
            WrappingRowLayout(spacing: DSSpacing.lg, lineSpacing: 0) {
                Button {
                    withAnimation(DSAnimations.snappySpring) {
                        isExpanded.toggle()
                    }
                    DSHaptics.selection()
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Text(isExpanded ? "Hide excerpt" : "Show excerpt")
                            .scaledFont(size: 12, weight: .medium)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .scaledFont(size: 10, weight: .semibold)
                    }
                    .foregroundStyle(DSColors.secondaryText)
                    // 44 points to tap on iPhone and iPad; the audit found the line's own 14 too small (5.7).
                    .frame(minHeight: DSSpacing.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let target = pageTarget {
                    Button {
                        shownPage = SourcePageTarget(document: target.document, page: target.page)
                    } label: {
                        Label("Page \(target.page)", systemImage: "doc.text.magnifyingglass")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(DSColors.readable(DSColors.accent))
                            .frame(minHeight: DSSpacing.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show page \(target.page)")
                }
            }

            if isExpanded {
                ScrollView {
                    Text(chunk.chunk.content)
                        .scaledFont(size: 13)
                        .foregroundStyle(DSColors.secondaryText)
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
        // Outside the `if` that draws the Page button, so a redraw that finds no page cannot close an open one (5.7).
        .sheet(item: $shownPage) { shown in
            SourcePageView(
                document: shown.document, pageNumber: shown.page, passage: chunk.chunk.content, chunk: chunk,
                lookup: libraryDocumentLookup)
        }
    }
}

// MARK: - Performance Metric Row

private struct PerfMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .scaledFont(size: 13)
                .foregroundStyle(DSColors.secondaryText)
            Spacer()
            Text(value)
                .scaledFont(size: 13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.vertical, DSSpacing.xs)
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
                .foregroundStyle(color)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)

            Spacer()

            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
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

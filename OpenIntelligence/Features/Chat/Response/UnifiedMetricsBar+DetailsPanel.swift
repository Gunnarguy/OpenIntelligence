//
//  UnifiedMetricsBar+DetailsPanel.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - Micro Metric

    private func microMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 8, weight: .medium)
                .foregroundStyle(DSColors.secondaryText)
            Text(value)
                .scaledFont(size: 10, weight: .medium, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
            if !label.isEmpty {
                Text(label)
                    .scaledFont(size: 8)
                    .foregroundStyle(DSColors.secondaryText.opacity(0.7))
            }
        }
    }

// MARK: - Expanded Panel (Streamlined for This Query)

    var expandedDetailsPanel: some View {
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
            // High priority, so the chat's scroll view does not take the same drag and move the screen with it.
            .highPriorityGesture(
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
                        baseHeight = Self.clampedPanelHeight(baseHeight + val.translation.height)
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
        // A dragged panel is exactly the height dragged to, and the card around it follows. Until 5.8 the card sat in a
        // frame that grew to all the space Chat offered: dragging up shrank the panel inside a card that kept its size,
        // so the panel slid to the card's middle with a blank band above it, and dragging down pushed the screen
        // (the owner's iPhone, 2026-11-10). Before any drag it sizes itself, up to the same limit as before.
        .frame(height: baseHeight > 0 ? Self.clampedPanelHeight(baseHeight + dragOffset) : nil, alignment: .top)
        .frame(maxHeight: baseHeight > 0 ? nil : Self.panelHeightLimit, alignment: .top)
        // The bar's springs do not run while the finger moves the panel, so it tracks the finger with no lag.
        .transaction { transaction in
            if isDragging { transaction.animation = nil }
        }
        // Auto-reset manual height when system finishes processing so it can auto-size the new tools section
        .onChange(of: isProcessing) {
            baseHeight = 0
            isDragging = false
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .padding(.top, DSSpacing.xs)
    }

    #if os(iOS)
        static let panelHeightLimit: CGFloat = 1000
    #else
        static let panelHeightLimit: CGFloat = 650
    #endif

    /// A dragged height kept between 150 points and the limit the panel had before any drag.
    static func clampedPanelHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return 150 }
        return min(panelHeightLimit, max(150, height))
    }

    // MARK: - Section: Library Context (NEW)

    private var libraryContextSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "books.vertical.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.teal)
                Text("Knowledge Base")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                // Library name
                HStack(spacing: DSSpacing.sm) {
                    Text(containerName)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)

                    Spacer()

                    // Chunk stats
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .scaledFont(size: 10)
                            .foregroundStyle(.teal)
                        Text("\(totalStoredChunks) chunks")
                            .scaledFont(size: 11, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                // Technical specs row
                HStack(spacing: DSSpacing.md) {
                    if embeddingDim > 0 {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "cube.fill")
                                .scaledFont(size: 9)
                            Text("\(embeddingDim)-dim")
                                .scaledFont(size: 10, weight: .medium, design: .monospaced)
                                .monospacedDigit()
                        }
                        .foregroundStyle(DSColors.secondaryText)
                    }

                    if !vectorDBKind.isEmpty {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "cylinder.fill")
                                .scaledFont(size: 9)
                            Text(vectorDBKind)
                                .scaledFont(size: 10, weight: .medium)
                        }
                        .foregroundStyle(DSColors.secondaryText)
                    }

                    if chunkingTargetWords > 0 {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "text.justify.left")
                                .scaledFont(size: 9)
                            Text("~\(chunkingTargetWords)w/chunk")
                                .scaledFont(size: 10, weight: .medium)
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
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.cyan)
                Text("Pipeline Journey")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("chunk selection funnel")
                    .scaledFont(size: 9)
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
                            .scaledFont(size: 9)
                            .foregroundStyle(.red.opacity(0.6))
                        Text("\(droppedCount) dropped (low similarity)")
                            .scaledFont(size: 9)
                            .monospacedDigit()
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .padding(.top, DSSpacing.xs)
                }

                if uniqueDocCount > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "doc.on.doc.fill")
                            .scaledFont(size: 9)
                            .foregroundStyle(DSColors.secondaryText)
                        Text("from \(uniqueDocCount) unique documents")
                            .scaledFont(size: 9)
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
                .scaledFont(size: 10, weight: .medium)
                .foregroundStyle(color)
                .frame(width: 14)

            Text(label)
                .scaledFont(size: 10, weight: isHighlighted ? .semibold : .regular)
                .foregroundStyle(isHighlighted ? DSColors.primaryText : DSColors.secondaryText)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(isHighlighted ? 1.0 : 0.6))
                    .frame(width: max(4, geo.size.width * min(1.0, max(0.1, widthRatio))))
            }
            .frame(height: 6)

            Text("\(count)")
                .scaledFont(size: 11, weight: .bold, design: .monospaced)
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
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.mint)
                Text("Token Budget")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("\(baseWindowTokens) window")
                    .scaledFont(size: 9, weight: .medium, design: .monospaced)
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
                .scaledFont(size: 10, weight: isResult || isHighlighted ? .semibold : .regular)
                .foregroundStyle(isResult || isHighlighted ? DSColors.primaryText : DSColors.secondaryText)

            Spacer()

            Text(value >= 0 ? "\(value)" : "\(abs(value))")
                .scaledFont(size: 11, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: - Section: Confidence Metrics (NEW)

    private var confidenceMetricsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.yellow)
                Text("Confidence & Quality")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                if lenientRetrieval {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "hand.thumbsup.fill")
                            .scaledFont(size: 9)
                        Text("Lenient")
                            .scaledFont(size: 9, weight: .medium)
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
                            .scaledFont(size: 18, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(similarityColor(topSimilarity))
                        Text("Top Match")
                            .scaledFont(size: 9)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)

                    if secondSimilarity > 0 {
                        VStack(alignment: .center, spacing: DSSpacing.xxs) {
                            Text(String(format: "%.1f%%", secondSimilarity * 100))
                                .scaledFont(size: 14, weight: .semibold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(similarityColor(secondSimilarity))
                            Text("2nd Best")
                                .scaledFont(size: 9)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if avgTop5Similarity > 0 {
                        VStack(alignment: .center, spacing: DSSpacing.xxs) {
                            Text(String(format: "%.1f%%", avgTop5Similarity * 100))
                                .scaledFont(size: 14, weight: .semibold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(similarityColor(avgTop5Similarity))
                            Text("Avg Top 5")
                                .scaledFont(size: 9)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Threshold info
                if dynamicMinThreshold > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "line.horizontal.3.decrease")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                        Text("Dynamic threshold: \(String(format: "%.1f%%", dynamicMinThreshold * 100))")
                            .scaledFont(size: 10)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)

                        if acceptanceOverride {
                            Text("• Override active")
                                .scaledFont(size: 10, weight: .medium)
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
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.pink)
                Text("Timing Breakdown")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                let totalTime = embeddingElapsed + searchElapsed + max(generationElapsed, elapsedTime)
                if totalTime > 0 {
                    Text(String(format: "%.1fs total", totalTime))
                        .scaledFont(size: 9, weight: .medium, design: .monospaced)
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
                                .scaledFont(size: 10, weight: .medium)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    if searchElapsed > 0 {
                        HStack(spacing: DSSpacing.xs) {
                            Circle().fill(Color.purple).frame(width: 8, height: 8)
                            Text("Search: \(formatDuration(searchElapsed))")
                                .scaledFont(size: 10, weight: .medium)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    let genTime = max(generationElapsed, elapsedTime)
                    if genTime > 0 {
                        HStack(spacing: DSSpacing.xs) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("Generate: \(formatDuration(genTime))")
                                .scaledFont(size: 10, weight: .medium)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }

                // TTFT if available
                if let ttft = ttft, ttft > 0 {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "bolt.fill")
                            .scaledFont(size: 9)
                            .foregroundStyle(.yellow)
                        Text("Time to first token: \(formatDuration(ttft))")
                            .scaledFont(size: 10)
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

}

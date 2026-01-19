import SwiftUI

struct IngestionQueueOverlay: View {
    let items: [IngestionItem]

    private var sortedItems: [IngestionItem] {
        items.sorted { lhs, rhs in
            sortOrder(for: lhs) < sortOrder(for: rhs)
        }
    }

    private func sortOrder(for item: IngestionItem) -> Int {
        switch item.stage {
        case .queued: return 1
        case .loading, .transcribing, .extracting, .chunking, .analyzing, .embedding, .storing,
             .adapting, .reindexing, .indexing: return 0
        case .complete, .failed: return 2
        }
    }

    private var activeCount: Int {
        items.filter { !$0.stage.isTerminal }.count
    }

    private var completedCount: Int {
        items.filter { $0.stage == .complete }.count
    }

    private var failedCount: Int {
        items.filter { $0.stage == .failed }.count
    }

    // MARK: - Aggregated Totals

    private var totalMetrics: AggregatedMetrics {
        var agg = AggregatedMetrics()
        for item in items {
            let m = item.metrics
            agg.totalFiles += 1
            agg.totalChunks += m.chunkCount
            agg.totalVectors += m.embeddingsGenerated
            agg.totalWords += m.totalWords
            agg.totalCharacters += m.totalCharacters
            agg.totalPages += m.pageCount
            agg.totalOCRPages += m.ocrPagesCount
            agg.totalFileSizeMB += m.fileSizeMB
            agg.totalTimeMs += m.totalTimeMs

            if m.chunkCount > 0 {
                agg.chunkWordSamples.append(m.avgChunkWords)
            }
            if m.embeddingDimension > 0 {
                agg.embeddingDimension = m.embeddingDimension
            }
            if !m.embeddingProvider.isEmpty {
                agg.embeddingProvider = m.embeddingProvider
            }
        }
        return agg
    }

    var body: some View {
        guard !items.isEmpty else { return AnyView(EmptyView()) }

        let visibleItems = Array(sortedItems.prefix(5))
        let hiddenCount = max(0, items.count - visibleItems.count)

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                headerView

                // Totals summary card (only show when we have metrics data)
                if totalMetrics.hasData {
                    TotalsSummaryCard(
                        metrics: totalMetrics,
                        completedCount: completedCount,
                        totalCount: items.count
                    )
                }

                VStack(spacing: 10) {
                    ForEach(visibleItems) { item in
                        IngestionQueueRow(item: item)
                    }
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more in queue")
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DSColors.accent.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: items.count)
        )
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(DSColors.accent)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(activeCount > 0 ? "Processing uploads" : "Upload complete")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DSColors.primaryText)

                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Spacer()
        }
    }

    private var statusLine: String {
        let total = items.count
        let completed = completedCount
        if failedCount > 0 {
            return "\(completed)/\(total) complete • \(failedCount) failed"
        }
        return "\(completed)/\(total) complete"
    }
}

private struct IngestionQueueRow: View {
    let item: IngestionItem
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: stageIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(stageColor)

                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(DSColors.primaryText)

                Spacer()

                Text(item.stage.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(stageColor.opacity(0.12))
                    .foregroundStyle(stageColor)
                    .clipShape(Capsule())
            }

            IngestionPipelineSteps(item: item)

            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
            }

            if let progress = item.progress, !item.stage.isTerminal {
                ProgressView(value: progress)
                    .tint(DSColors.accent)
            }

            // Show live metrics when processing
            if !item.stage.isTerminal, hasMetrics {
                liveMetricsView
            }

            // Expandable details for completed/in-progress items
            if hasMetrics {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(showDetails ? "Hide Pipeline Details" : "Show Pipeline Details")
                            .font(.caption2)
                    }
                    .foregroundStyle(DSColors.accent)
                }
                .buttonStyle(.plain)

                if showDetails {
                    pipelineDetailsView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let errorMessage = item.errorMessage, item.stage == .failed {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(DSColors.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hasMetrics: Bool {
        item.metrics.chunkCount > 0 || item.metrics.totalWords > 0 || item.metrics.embeddingsGenerated > 0
    }

    @ViewBuilder
    private var liveMetricsView: some View {
        let m = item.metrics
        HStack(spacing: 12) {
            if m.chunkCount > 0 {
                metricPill(icon: "square.split.2x2", value: "\(m.chunkCount)", label: "chunks")
            }
            if m.avgChunkWords > 0 {
                metricPill(icon: "textformat.size", value: "\(m.avgChunkWords)", label: "avg w")
            }
            if m.embeddingsGenerated > 0 {
                metricPill(icon: "brain.head.profile", value: "\(m.embeddingsGenerated)", label: "vectors")
            }
            if m.embeddingDimension > 0 {
                metricPill(icon: "arrow.up.right.and.arrow.down.left", value: "\(m.embeddingDimension)D", label: nil)
            }
        }
        .font(.system(size: 10))
    }

    @ViewBuilder
    private func metricPill(icon: String, value: String, label: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value)
                .fontWeight(.medium)
            if let label {
                Text(label)
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(DSColors.surface)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var pipelineDetailsView: some View {
        let m = item.metrics
        VStack(alignment: .leading, spacing: 8) {
            // Document Stats
            if m.totalWords > 0 || m.fileSizeMB > 0 {
                detailSection(title: "Document") {
                    HStack(spacing: 16) {
                        if m.fileSizeMB > 0 {
                            detailItem(label: "Size", value: String(format: "%.2f MB", m.fileSizeMB))
                        }
                        if m.totalWords > 0 {
                            detailItem(label: "Words", value: formatNumber(m.totalWords))
                        }
                        if m.totalCharacters > 0 {
                            detailItem(label: "Chars", value: formatNumber(m.totalCharacters))
                        }
                        if m.pageCount > 0 {
                            detailItem(label: "Pages", value: "\(m.pageCount)")
                        }
                    }
                    if m.ocrPagesCount > 0 {
                        Text("OCR applied to \(m.ocrPagesCount) page(s)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Chunking Stats
            if m.chunkCount > 0 {
                detailSection(title: "Chunking") {
                    HStack(spacing: 16) {
                        detailItem(label: "Chunks", value: "\(m.chunkCount)")
                        detailItem(label: "Avg", value: "\(m.avgChunkWords)w")
                        detailItem(label: "Range", value: "\(m.minChunkWords)-\(m.maxChunkWords)w")
                    }
                    if !m.chunkingStrategy.isEmpty {
                        HStack(spacing: 8) {
                            Text("Strategy: \(m.chunkingStrategy.capitalized)")
                            if m.targetWordWindow > 0 {
                                Text("• \(m.targetWordWindow)w window")
                            }
                            if m.overlapWords > 0 {
                                Text("• \(m.overlapWords)w overlap")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Analysis Results (Auto-Adaptive)
            if m.isAutoAdaptive && m.vocabularyRichness > 0 {
                detailSection(title: "Corpus Analysis") {
                    HStack(spacing: 16) {
                        detailItem(label: "Vocab", value: String(format: "%.0f%%", m.vocabularyRichness * 100))
                        detailItem(label: "Technical", value: String(format: "%.0f%%", m.technicalDensity * 100))
                        detailItem(label: "Complexity", value: String(format: "%.1f", m.semanticComplexity))
                    }
                    HStack(spacing: 8) {
                        if m.hasCode {
                            codeBadge("Code")
                        }
                        if m.hasMath {
                            codeBadge("Math")
                        }
                        if !m.detectedLanguages.isEmpty {
                            Text("Languages: \(m.detectedLanguages.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                    if m.configWasAdapted && !m.adaptationReason.isEmpty {
                        Text("✨ \(m.adaptationReason)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            // Embedding Stats
            if m.embeddingsGenerated > 0 {
                detailSection(title: "Embeddings") {
                    HStack(spacing: 16) {
                        detailItem(label: "Vectors", value: "\(m.embeddingsGenerated)")
                        detailItem(label: "Dimensions", value: "\(m.embeddingDimension)")
                        if !m.embeddingProvider.isEmpty {
                            detailItem(label: "Provider", value: m.embeddingProvider)
                        }
                    }
                }
            }

            // Timing Stats
            if m.totalTimeMs > 0 || m.extractionTimeMs > 0 {
                detailSection(title: "Timing") {
                    HStack(spacing: 16) {
                        if m.extractionTimeMs > 0 {
                            detailItem(label: "Extract", value: formatMs(m.extractionTimeMs))
                        }
                        if m.chunkingTimeMs > 0 {
                            detailItem(label: "Chunk", value: formatMs(m.chunkingTimeMs))
                        }
                        if m.analysisTimeMs > 0 {
                            detailItem(label: "Analyze", value: formatMs(m.analysisTimeMs))
                        }
                        if m.embeddingTimeMs > 0 {
                            detailItem(label: "Embed", value: formatMs(m.embeddingTimeMs))
                        }
                    }
                    if m.totalTimeMs > 0 {
                        Text("Total pipeline: \(formatMs(m.totalTimeMs))")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(DSColors.accent)
                    }
                }
            }

            // Rebuild Info
            if m.isRebuild && !m.rebuildReason.isEmpty {
                Text("🔄 Rebuild: \(m.rebuildReason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .background(DSColors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func detailSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DSColors.secondaryText)
            content()
        }
    }

    @ViewBuilder
    private func detailItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func codeBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.2))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }

    private func formatMs(_ ms: Int) -> String {
        if ms >= 1000 {
            return String(format: "%.1fs", Double(ms) / 1000)
        }
        return "\(ms)ms"
    }

    private var stageIcon: String {
        switch item.stage {
        case .queued: return "clock"
        case .loading: return "arrow.down.circle"
        case .transcribing: return "waveform"
        case .extracting: return "doc.text.magnifyingglass"
        case .chunking: return "square.split.2x2"
        case .analyzing: return "brain"
        case .adapting: return "wand.and.stars"
        case .reindexing: return "arrow.triangle.2.circlepath"
        case .embedding: return "brain.head.profile"
        case .indexing: return "magnifyingglass"
        case .storing: return "tray.and.arrow.down"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var stageColor: Color {
        switch item.stage {
        case .failed: return .red
        case .complete: return .green
        case .queued: return .gray
        default: return DSColors.accent
        }
    }
}

private struct IngestionPipelineSteps: View {
    let item: IngestionItem

    private let steps = IngestionStage.pipelineStages

    var body: some View {
        let activeIndex = item.stage == .complete
            ? steps.count - 1
            : (item.stage.pipelineIndex ?? -1)

        return HStack(spacing: 3) { 
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(stepColor(for: index, activeIndex: activeIndex))
.frame(height: 3)
            }
        }
    }

    private func stepColor(for index: Int, activeIndex: Int) -> Color {
        if item.stage == .failed { return .red.opacity(0.7) }
        if activeIndex == -1 { return Color.gray.opacity(0.2) }
        if index < activeIndex { return Color.green.opacity(0.8) }
        if index == activeIndex { return DSColors.accent }
        return Color.gray.opacity(0.2)
    }
}

// MARK: - Aggregated Metrics

private struct AggregatedMetrics {
    var totalFiles: Int = 0
    var totalChunks: Int = 0
    var totalVectors: Int = 0
    var totalWords: Int = 0
    var totalCharacters: Int = 0
    var totalPages: Int = 0
    var totalOCRPages: Int = 0
    var totalFileSizeMB: Double = 0
    var totalTimeMs: Int = 0
    var chunkWordSamples: [Int] = []
    var embeddingDimension: Int = 0
    var embeddingProvider: String = ""

    var avgChunkWords: Int {
        guard !chunkWordSamples.isEmpty else { return 0 }
        return chunkWordSamples.reduce(0, +) / chunkWordSamples.count
    }

    var hasData: Bool {
        totalChunks > 0 || totalVectors > 0 || totalWords > 0
    }
}

// MARK: - Totals Summary Card

private struct TotalsSummaryCard: View {
    let metrics: AggregatedMetrics
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColors.accent)
                Text("BATCH TOTALS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(DSColors.secondaryText)
                Spacer()
                if metrics.totalFileSizeMB > 0 {
                    Text(String(format: "%.1f MB", metrics.totalFileSizeMB))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DSColors.secondaryText)
                }
            }

            // Primary stats row
            HStack(spacing: 0) {
                totalStatCell(
                    icon: "doc.fill",
                    value: "\(completedCount)/\(totalCount)",
                    label: "Files",
                    color: .blue
                )
                Divider().frame(height: 32)
                totalStatCell(
                    icon: "square.split.2x2.fill",
                    value: formatNumber(metrics.totalChunks),
                    label: "Chunks",
                    color: .purple
                )
                Divider().frame(height: 32)
                totalStatCell(
                    icon: "brain.head.profile.fill",
                    value: formatNumber(metrics.totalVectors),
                    label: "Vectors",
                    color: .green
                )
                Divider().frame(height: 32)
                totalStatCell(
                    icon: "textformat",
                    value: formatNumber(metrics.totalWords),
                    label: "Words",
                    color: .orange
                )
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DSColors.surface.opacity(0.6))
            )

            // Secondary stats row
            HStack(spacing: 12) {
                if metrics.avgChunkWords > 0 {
                    miniStat(icon: "textformat.size", value: "\(metrics.avgChunkWords)w", label: "Avg Chunk")
                }
                if metrics.totalPages > 0 {
                    miniStat(icon: "doc.text", value: "\(metrics.totalPages)", label: "Pages")
                }
                if metrics.embeddingDimension > 0 {
                    miniStat(
                        icon: "arrow.up.right.and.arrow.down.left",
                        value: "\(metrics.embeddingDimension)D",
                        label: metrics.embeddingProvider.isEmpty ? "Dims" : metrics.embeddingProvider
                    )
                }
                if metrics.totalTimeMs > 0 {
                    miniStat(icon: "clock", value: formatTime(metrics.totalTimeMs), label: "Total")
                }
            }
            .font(.system(size: 10))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DSColors.accent.opacity(0.08), DSColors.surface.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DSColors.accent.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func totalStatCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DSColors.primaryText)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DSColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func miniStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(DSColors.accent)
            Text(value)
                .fontWeight(.medium)
            Text(label)
                .foregroundStyle(DSColors.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DSColors.surface.opacity(0.8))
        .clipShape(Capsule())
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }

    private func formatTime(_ ms: Int) -> String {
        if ms >= 60000 {
            return String(format: "%.1fm", Double(ms) / 60000)
        }
        if ms >= 1000 {
            return String(format: "%.1fs", Double(ms) / 1000)
        }
        return "\(ms)ms"
    }
}

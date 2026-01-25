import SwiftUI

// MARK: - Display Shorthand Helpers

/// Shorthand display names for embedding providers.
/// Maintains technical accuracy while fitting in compact pill UI.
private func shortProviderDisplay(_ provider: String) -> String {
    let lower = provider.lowercased()
    // Handle already-short names from RAGService
    if lower == "coreml" || lower == "nl" || lower == "fm" || lower == "openai" || lower == "nlctx" {
        return provider
    }
    // Handle legacy long names that may still be in metrics
    switch lower {
    case "coreml sentence embedding", "coreml_sentence_embedding":
        return "CoreML"
    case "nl embedding", "nl_embedding", "nlembedding":
        return "NL"
    case "apple foundation", "apple_foundation", "foundation models":
        return "FM"
    case "openai embedding", "openai_embedding":
        return "OpenAI"
    case "nl contextual", "nl_contextual", "contextual":
        return "NLCtx"
    default:
        // Truncate long names to 8 chars max
        if provider.count > 8 {
            return String(provider.prefix(7)) + "…"
        }
        return provider
    }
}

/// Shorthand for chunking strategies. Uses SWE-standard abbreviations.
private func shortChunkStrategy(_ strategy: String) -> String {
    switch strategy.lowercased() {
    case "semantic", "semantic_chunking":
        return "Semantic"
    case "sentence", "sentence_based":
        return "Sent"
    case "paragraph", "paragraph_based":
        return "Para"
    case "fixed", "fixed_size", "fixed_window":
        return "Fixed"
    case "sliding", "sliding_window":
        return "Slide"
    case "recursive", "recursive_split":
        return "Recur"
    case "hybrid":
        return "Hybrid"
    default:
        // Capitalize first word, truncate if long
        let word = strategy.split(separator: "_").first.map(String.init) ?? strategy
        return word.count > 7 ? String(word.prefix(6)) + "…" : word.capitalized
    }
}

struct IngestionQueueOverlay: View {
    let items: [IngestionItem]
    @State private var isMinimized = false
    @State private var isDismissed = false
    @State private var gpuLevel: Double = DeviceCapabilityService.shared.gpuAccelerationLevel

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
        guard !items.isEmpty, !isDismissed else { return AnyView(EmptyView()) }

        let visibleItems = Array(sortedItems.prefix(5))
        let hiddenCount = max(0, items.count - visibleItems.count)

        // Reset dismissed state when items clear (so next batch shows)
        if items.isEmpty, isDismissed {
            // Will reset on next appear
        }

        return AnyView(
            VStack(alignment: .leading, spacing: isMinimized ? 0 : 12) {
                headerView

                if !isMinimized {
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
            }
            .padding(14)
.frame(maxWidth: isMinimized ? nil : 360, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DSColors.accent.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: items.count)
.animation(.spring(response: 0.25), value: isMinimized)
    .onChange(of: items.isEmpty) { _, isEmpty in
        if isEmpty {
            // Reset for next batch
            isDismissed = false
            isMinimized = false
        }
    }
        )
    }

    // GPU boost level for display (uses @State for reactivity)
    private var gpuBoostActive: Bool {
        gpuLevel > 0.7
    }

    private var currentConcurrency: Int {
        DeviceCapabilityService.shared.visionParsingConcurrency
    }

    // Mode label based on GPU level
    private var processingModeLabel: String {
        if gpuLevel > 0.7 {
            return "⚡ Turbo"
        } else if gpuLevel >= 0.3 {
            return "🔋 Balanced"
        } else {
            return "🌱 Eco"
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(DSColors.accent)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(activeCount > 0 ? "Processing uploads" : "Upload complete")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)

                    // Always show processing mode during active uploads
                    if activeCount > 0 {
                        HStack(spacing: 4) {
                            Text(processingModeLabel)
                            Text("\(currentConcurrency)x")
                                .fontWeight(.bold)
                        }
                        .font(.caption2)
                        .foregroundColor(gpuBoostActive ? .orange : DSColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(gpuBoostActive ? Color.orange.opacity(0.2) : DSColors.secondaryText.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                if !isMinimized {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }

            Spacer()

            // GPU Turbo toggle (only show during active processing)
            if activeCount > 0 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        // Cycle through modes: Eco (0.1) → Balanced (0.5) → Turbo (0.9) → Eco
                        if gpuLevel > 0.7 {
                            gpuLevel = 0.1  // Back to Eco
                        } else if gpuLevel >= 0.3 {
                            gpuLevel = 0.9  // Boost to Turbo
                        } else {
                            gpuLevel = 0.5  // Up to Balanced
                        }
                        DeviceCapabilityService.shared.gpuAccelerationLevel = gpuLevel
                    }
                } label: {
                    Image(systemName: gpuBoostActive ? "bolt.fill" : "bolt")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(gpuBoostActive ? .orange : DSColors.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(gpuBoostActive ? Color.orange.opacity(0.2) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(gpuBoostActive ? "Turbo Mode - Tap to cycle" : "Tap to cycle GPU modes")
            }

            // Minimize/expand button
            Button {
                withAnimation { isMinimized.toggle() }
            } label: {
                Image(systemName: isMinimized ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColors.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            // Dismiss button
            Button {
                withAnimation { isDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DSColors.secondaryText)
                    .frame(width: 20, height: 20)
                    .background(DSColors.secondaryText.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
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
        // Show metrics if we have any counts OR if Vision parsing is active (live updates during extraction)
        item.metrics.chunkCount > 0 ||
        item.metrics.totalWords > 0 ||
        item.metrics.embeddingsGenerated > 0 ||
        item.metrics.tablesExtracted > 0 ||
        item.metrics.listsExtracted > 0 ||
        item.metrics.titlesDetected > 0 ||
        item.metrics.usedStructuredParsing ||
        item.metrics.pageCount > 0
    }

    @ViewBuilder
    private var liveMetricsView: some View {
        let m = item.metrics
        VStack(alignment: .leading, spacing: 6) {
            // Row 0: Structured parsing status (Vision iOS 26+) - shows LIVE during extraction
            if m.usedStructuredParsing || m.tablesExtracted > 0 || m.listsExtracted > 0 || m.titlesDetected > 0 {
                HStack(spacing: 6) {
                    // Vision badge with optional page count
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 7))
                        Text("Vision")
                            .font(.system(size: 8, weight: .semibold))
                        if m.pageCount > 0 && item.stage == .extracting {
                            Text("•")
                                .font(.system(size: 6))
                            Text("\(m.pageCount) pg")
                                .font(.system(size: 8))
                        }
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())

                    if m.tablesExtracted > 0 {
                        metricPill(icon: "tablecells", value: "\(m.tablesExtracted)", label: "tbl")
                    }
                    if m.listsExtracted > 0 {
                        metricPill(icon: "list.bullet", value: "\(m.listsExtracted)", label: "lst")
                    }
                    if m.titlesDetected > 0 {
                        metricPill(icon: "textformat.size.larger", value: "\(m.titlesDetected)", label: "hdr")
                    }
                }
            }

            // Row 1: Core counts
            HStack(spacing: 8) {
                if m.chunkCount > 0 {
                    metricPill(icon: "square.split.2x2", value: "\(m.chunkCount)", label: "chk")
                }
                if m.avgChunkWords > 0 {
                    metricPill(icon: "textformat.size", value: "\(m.avgChunkWords)", label: "avg")
                }
                if m.embeddingsGenerated > 0 {
                    metricPill(icon: "brain.head.profile", value: "\(m.embeddingsGenerated)", label: "vec")
                }
                if m.embeddingDimension > 0 {
                    metricPill(icon: "cpu", value: "\(m.embeddingDimension)D", label: nil)
                }
            }

            // Row 2: Semantic boundaries (the nerdy stuff)
            if m.sectionsDetected > 0 || m.topicBoundaries > 0 || m.embeddingBoundaries > 0 {
                HStack(spacing: 8) {
                    if m.sectionsDetected > 0 {
                        metricPill(icon: "list.bullet.indent", value: "\(m.sectionsDetected)", label: "sec")
                    }
                    if m.topicBoundaries > 0 {
                        metricPill(icon: "arrow.triangle.branch", value: "\(m.topicBoundaries)", label: "topic")
                    }
                    if m.embeddingBoundaries > 0 {
                        metricPill(icon: "waveform.path.ecg", value: "\(m.embeddingBoundaries)", label: "∇sim")
                    }
                }
            }

            // Row 3: Entity extraction
            if m.entitiesExtracted > 0 {
                HStack(spacing: 8) {
                    metricPill(icon: "tag", value: "\(m.entitiesExtracted)", label: "ent")
                    if !m.topEntities.isEmpty {
                        Text(m.topEntities.prefix(3).joined(separator: ", "))
                            .font(.system(size: 9))
                            .foregroundStyle(DSColors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            // Row 4: Analysis scores (when available)
            if m.vocabularyRichness > 0 || m.technicalDensity > 0 {
                HStack(spacing: 8) {
                    if m.vocabularyRichness > 0 {
                        metricPill(icon: "textformat.abc", value: String(format: "%.0f%%", m.vocabularyRichness * 100), label: "voc")
                    }
                    if m.technicalDensity > 0 {
                        metricPill(icon: "gearshape.2", value: String(format: "%.0f%%", m.technicalDensity * 100), label: "tech")
                    }
                    if m.hasCode {
                        codeBadgeMini("{ }")
                    }
                    if m.hasMath {
                        codeBadgeMini("∑")
                    }
                }
            }
        }
        .font(.system(size: 10))
    }

    @ViewBuilder
    private func codeBadgeMini(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(RoundedRectangle(cornerRadius: 3))
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
        VStack(alignment: .leading, spacing: 10) {
            extractionSection(m)
            visionLayoutSection(m)
            chunkingSection(m)
            corpusIntelligenceSection(m)
            embeddingSection(m)
            timingSection(m)
            rebuildSection(m)
        }
        .padding(10)
        .background(DSColors.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Pipeline Detail Sections (broken up for compiler)

    @ViewBuilder
    private func extractionSection(_ m: PipelineMetrics) -> some View {
        if m.totalWords > 0 || m.fileSizeMB > 0 {
            detailSection(title: "📄 Document Extraction", icon: "doc.text.magnifyingglass") {
                HStack(spacing: 12) {
                    if m.fileSizeMB > 0 {
                        statBox(value: String(format: "%.2f", m.fileSizeMB), unit: "MB", label: "Size")
                    }
                    if m.totalWords > 0 {
                        statBox(value: formatNumber(m.totalWords), unit: "", label: "Words")
                    }
                    if m.totalCharacters > 0 {
                        statBox(value: formatNumber(m.totalCharacters), unit: "", label: "Chars")
                    }
                    if m.pageCount > 0 {
                        statBox(value: "\(m.pageCount)", unit: "", label: "Pages")
                    }
                }
                if m.ocrPagesCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.trianglebadge.exclamationmark")
                            .font(.system(size: 9))
                        Text("OCR: \(m.ocrPagesCount) page\(m.ocrPagesCount > 1 ? "s" : "") scanned")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
                if m.extractionTimeMs > 0 {
                    timingBadge(label: "Extraction", ms: m.extractionTimeMs, throughput: m.totalWords > 0 ? Double(m.totalWords) / (Double(m.extractionTimeMs) / 1000.0) : nil, unit: "w/s")
                }
            }
        }
    }

    @ViewBuilder
    private func visionLayoutSection(_ m: PipelineMetrics) -> some View {
        if m.usedStructuredParsing || m.tablesExtracted > 0 || m.listsExtracted > 0 {
            detailSection(title: "👁 Vision Layout", icon: "doc.viewfinder") {
                visionStatusBadge(m)
                visionStatsRow(m)
                visionTableDetails(m)
                visionExtras(m)
            }
        }
    }

    @ViewBuilder
    private func visionStatusBadge(_ m: PipelineMetrics) -> some View {
        HStack(spacing: 6) {
            Image(systemName: m.usedStructuredParsing ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(m.usedStructuredParsing ? .green : .orange)
            Text(m.usedStructuredParsing ? "RecognizeDocumentsRequest" : "PDFKit Fallback")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(m.usedStructuredParsing ? .green : .orange)
            if m.structuredParsingQuality > 0 {
                Text("(\(Int(m.structuredParsingQuality * 100))% quality)")
                    .font(.system(size: 8))
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((m.usedStructuredParsing ? Color.green : Color.orange).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func visionStatsRow(_ m: PipelineMetrics) -> some View {
        if m.tablesExtracted > 0 || m.listsExtracted > 0 || m.titlesDetected > 0 {
            HStack(spacing: 10) {
                if m.tablesExtracted > 0 { visionStatItem(icon: "tablecells", count: m.tablesExtracted, label: "Tables", color: .cyan) }
                if m.listsExtracted > 0 { visionStatItem(icon: "list.bullet", count: m.listsExtracted, label: "Lists", color: .purple) }
                if m.titlesDetected > 0 { visionStatItem(icon: "textformat.size.larger", count: m.titlesDetected, label: "Headers", color: .blue) }
                if m.figureReferences > 0 { visionStatItem(icon: "photo", count: m.figureReferences, label: "Figures", color: .orange) }
            }
        }
    }

    @ViewBuilder
    private func visionStatItem(icon: String, count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 9))
                Text("\(count)").font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(color)
            Text(label).font(.system(size: 8)).foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func visionTableDetails(_ m: PipelineMetrics) -> some View {
        if m.tablesExtracted > 0 && (m.tableRowsTotal > 0 || m.tableColumnsMax > 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TABLE STRUCTURE").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.cyan.opacity(0.8))
                HStack(spacing: 8) {
                    if m.tableRowsTotal > 0 { HStack(spacing: 2) { Text("\(m.tableRowsTotal)").font(.system(size: 10, weight: .semibold)); Text("rows").font(.system(size: 8)).foregroundStyle(DSColors.secondaryText) } }
                    if m.tableColumnsMax > 0 { HStack(spacing: 2) { Text("\(m.tableColumnsMax)").font(.system(size: 10, weight: .semibold)); Text("max cols").font(.system(size: 8)).foregroundStyle(DSColors.secondaryText) } }
                    if m.atomicTableChunks > 0 { HStack(spacing: 2) { Image(systemName: "lock.fill").font(.system(size: 7)); Text("\(m.atomicTableChunks) atomic").font(.system(size: 8)) }.foregroundStyle(.green) }
                }
            }
            .padding(6)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func visionExtras(_ m: PipelineMetrics) -> some View {
        if m.visionEntitiesDetected > 0 {
            HStack(spacing: 4) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 9))
                Text("\(m.visionEntitiesDetected) auto-detected").font(.system(size: 9))
                Text("(emails, phones, dates)").font(.system(size: 8)).foregroundStyle(DSColors.secondaryText)
            }
            .foregroundStyle(.mint)
        }
        if m.sectionPathDepth > 1 {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.indent").font(.system(size: 9))
                Text("\(m.sectionPathDepth)-level hierarchy").font(.system(size: 9))
            }
            .foregroundStyle(.indigo)
        }
        if m.structuredParsingTimeMs > 0 {
            timingBadge(label: "Vision Parse", ms: m.structuredParsingTimeMs, throughput: m.pageCount > 0 ? Double(m.pageCount) / (Double(m.structuredParsingTimeMs) / 1000.0) : nil, unit: "pg/s")
        }
    }

    @ViewBuilder
    private func chunkingSection(_ m: PipelineMetrics) -> some View {
        if m.chunkCount > 0 {
            detailSection(title: "🧩 Chunking", icon: "square.split.2x2") {
                HStack(spacing: 12) {
                    statBox(value: "\(m.chunkCount)", unit: "", label: "Chunks")
                    statBox(value: "\(m.avgChunkWords)", unit: "w", label: "Avg")
                    statBox(value: "\(m.minChunkWords)", unit: "w", label: "Min")
                    statBox(value: "\(m.maxChunkWords)", unit: "w", label: "Max")
                }
                chunkingAtomicInfo(m)
                chunkingBoundaries(m)
                if m.chunkingTimeMs > 0 {
                    timingBadge(label: "Chunking", ms: m.chunkingTimeMs, throughput: Double(m.chunkCount) / (Double(m.chunkingTimeMs) / 1000.0), unit: "chk/s")
                }
            }
        }
    }

    @ViewBuilder
    private func chunkingAtomicInfo(_ m: PipelineMetrics) -> some View {
        if m.atomicTableChunks > 0 || m.atomicListChunks > 0 {
            HStack(spacing: 8) {
                Image(systemName: "lock.rectangle.stack").font(.system(size: 9))
                if m.atomicTableChunks > 0 { Text("\(m.atomicTableChunks) table\(m.atomicTableChunks > 1 ? "s" : "")") }
                if m.atomicListChunks > 0 { Text("\(m.atomicListChunks) list\(m.atomicListChunks > 1 ? "s" : "")") }
                Text("kept atomic").foregroundStyle(DSColors.secondaryText)
            }
            .font(.system(size: 9))
            .foregroundStyle(.green)
        }
        if !m.chunkingStrategy.isEmpty || m.targetWordWindow > 0 {
            HStack(spacing: 8) {
                if !m.chunkingStrategy.isEmpty { strategyPill(shortChunkStrategy(m.chunkingStrategy)) }
                if m.targetWordWindow > 0 { paramPill("window", "\(m.targetWordWindow)w") }
                if m.overlapWords > 0 { paramPill("overlap", "\(m.overlapWords)w") }
            }
        }
    }

    @ViewBuilder
    private func chunkingBoundaries(_ m: PipelineMetrics) -> some View {
        if m.sectionsDetected > 0 || m.topicBoundaries > 0 || m.embeddingBoundaries > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOUNDARIES").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(DSColors.accent.opacity(0.7))
                HStack(spacing: 10) {
                    if m.sectionsDetected > 0 { boundaryItem(icon: "list.bullet.indent", value: m.sectionsDetected, label: "Sections", desc: "Heading") }
                    if m.topicBoundaries > 0 { boundaryItem(icon: "arrow.triangle.branch", value: m.topicBoundaries, label: "Topics", desc: "TF-IDF") }
                    if m.embeddingBoundaries > 0 { boundaryItem(icon: "waveform.path.ecg", value: m.embeddingBoundaries, label: "∇Sim", desc: "Cosine") }
                }
            }
            .padding(6)
            .background(DSColors.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func corpusIntelligenceSection(_ m: PipelineMetrics) -> some View {
        if m.isAutoAdaptive || m.vocabularyRichness > 0 || m.entitiesExtracted > 0 {
            detailSection(title: "🧠 Corpus Intel", icon: "brain") {
                corpusMetrics(m)
                corpusEntities(m)
                if m.analysisTimeMs > 0 { timingBadge(label: "Analysis", ms: m.analysisTimeMs, throughput: nil, unit: nil) }
            }
        }
    }

    @ViewBuilder
    private func corpusMetrics(_ m: PipelineMetrics) -> some View {
        if m.vocabularyRichness > 0 {
            HStack(spacing: 12) {
                metricGauge(label: "Vocab", value: m.vocabularyRichness, color: .blue)
                metricGauge(label: "Tech", value: m.technicalDensity, color: .purple)
            }
        }
        if m.hasCode || m.hasMath {
            HStack(spacing: 6) {
                if m.hasCode { contentBadge(icon: "chevron.left.forwardslash.chevron.right", text: "Code", color: .orange) }
                if m.hasMath { contentBadge(icon: "function", text: "Math", color: .pink) }
            }
        }
    }

    @ViewBuilder
    private func corpusEntities(_ m: PipelineMetrics) -> some View {
        if m.entitiesExtracted > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "tag.fill").font(.system(size: 9)).foregroundStyle(.cyan)
                    Text("\(m.entitiesExtracted) ENTITIES").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                }
                if !m.topEntities.isEmpty {
                    Text(m.topEntities.prefix(5).joined(separator: " • ")).font(.system(size: 9)).foregroundStyle(DSColors.secondaryText).lineLimit(2)
                }
            }
            .padding(6)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func embeddingSection(_ m: PipelineMetrics) -> some View {
        if m.embeddingsGenerated > 0 {
            detailSection(title: "⚡ Embedding", icon: "brain.head.profile") {
                HStack(spacing: 12) {
                    statBox(value: "\(m.embeddingsGenerated)", unit: "", label: "Vectors")
                    statBox(value: "\(m.embeddingDimension)", unit: "D", label: "Dims")
                    if !m.embeddingProvider.isEmpty {
                        VStack(spacing: 2) {
                            Text(shortProviderDisplay(m.embeddingProvider)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(DSColors.accent)
                            Text("Encoder").font(.system(size: 8)).foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }
                if m.embeddingTimeMs > 0 {
                    let rate = Double(m.embeddingsGenerated) / (Double(m.embeddingTimeMs) / 1000.0)
                    timingBadge(label: "Embedding", ms: m.embeddingTimeMs, throughput: rate, unit: "vec/s")
                }
            }
        }
    }

    @ViewBuilder
    private func timingSection(_ m: PipelineMetrics) -> some View {
        if m.totalTimeMs > 0 {
            detailSection(title: "⏱ Timing", icon: "clock.badge.checkmark") {
                VStack(alignment: .leading, spacing: 4) {
                    if m.extractionTimeMs > 0 { timingBar(label: "Extract", ms: m.extractionTimeMs, total: m.totalTimeMs, color: .blue) }
                    if m.chunkingTimeMs > 0 { timingBar(label: "Chunk", ms: m.chunkingTimeMs, total: m.totalTimeMs, color: .purple) }
                    if m.analysisTimeMs > 0 { timingBar(label: "Analyze", ms: m.analysisTimeMs, total: m.totalTimeMs, color: .green) }
                    if m.embeddingTimeMs > 0 { timingBar(label: "Embed", ms: m.embeddingTimeMs, total: m.totalTimeMs, color: .orange) }
                }
                HStack {
                    Text("TOTAL").font(.system(size: 9, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(formatMs(m.totalTimeMs)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(DSColors.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func rebuildSection(_ m: PipelineMetrics) -> some View {
        if m.isRebuild && !m.rebuildReason.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                Text("REBUILD: \(m.rebuildReason)").font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Granular Detail Components

    @ViewBuilder
    private func detailSection(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(DSColors.accent)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(DSColors.secondaryText)
            }
            content()
        }
    }

    @ViewBuilder
    private func statBox(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func strategyPill(_ strategy: String) -> some View {
        Text(strategy)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DSColors.accent.opacity(0.15))
            .foregroundStyle(DSColors.accent)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func paramPill(_ param: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(param)
                .foregroundStyle(DSColors.secondaryText)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 8))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(DSColors.surface)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func boundaryItem(icon: String, value: Int, label: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text("\(value)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text(label)
                    .font(.system(size: 8, weight: .medium))
            }
            Text(desc)
                .font(.system(size: 7))
                .foregroundStyle(DSColors.secondaryText.opacity(0.7))
        }
    }

    @ViewBuilder
    private func metricGauge(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.2))
                    .frame(width: 40, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 40 * min(1, value), height: 4)
            }
            Text("\(Int(value * 100))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func contentBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func timingBadge(label: String, ms: Int, throughput: Double?, unit: String?) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 8))
                Text(formatMs(ms))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(DSColors.secondaryText)

            if let throughput, let unit, throughput > 0 {
                Text("⚡ \(formatNumber(Int(throughput))) \(unit)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DSColors.accent)
            }
        }
    }

    @ViewBuilder
    private func timingBar(label: String, ms: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Double(ms) / Double(total) : 0
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .frame(width: 45, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 6)

            Text(formatMs(ms))
                .font(.system(size: 8, design: .monospaced))
                .frame(width: 35, alignment: .trailing)
        }
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
                    miniStat(icon: "textformat.size", value: "\(metrics.avgChunkWords)w", label: "Avg")
                }
                if metrics.totalPages > 0 {
                    miniStat(icon: "doc.text", value: "\(metrics.totalPages)", label: "Pgs")
                }
                if metrics.embeddingDimension > 0 {
                    miniStat(
                        icon: "cpu",
                        value: "\(metrics.embeddingDimension)D",
                        label: metrics.embeddingProvider.isEmpty ? "" : shortProviderDisplay(metrics.embeddingProvider)
                    )
                }
                if metrics.totalTimeMs > 0 {
                    miniStat(icon: "clock", value: formatTime(metrics.totalTimeMs), label: "")
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

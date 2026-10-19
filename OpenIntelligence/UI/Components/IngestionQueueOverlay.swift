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

// MARK: - Console Log View

struct IngestionConsoleView: View {
    let events: [IngestionEvent]
    let isTerminal: Bool
    
    @State private var isExpanded = true
    @State private var isFullHeight = false
    @State private var hasAutoExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header to expand/collapse
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                // In the label color: gray on this gray bar measured 3.82 to 1 (5.7).
                HStack {
                    Text("Processing Log")
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(DSColors.primaryText)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .scaledFont(size: 8, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(events) { event in
                                    IngestionConsoleLogRow(event: event, isLatest: event == events.last && !isTerminal)
                                        .id(event.id)
                                }
                            }
                        }
                        .frame(maxHeight: isFullHeight ? 250 : 120)
                        .onChange(of: events.count) { _, _ in
                            if let latest = events.last {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(latest.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    if events.count > 6 {
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                isFullHeight.toggle()
                            }
                        }) {
                            Text(isFullHeight ? "Compact" : "Full Log (\(events.count))")
                                .scaledFont(size: 8, weight: .medium, design: .monospaced)
                                .foregroundStyle(DSColors.readable(.blue))
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.03))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                // A console in both appearances (5.7): a solid near-black box whose colors resolve as dark mode's.
                // Black at 60% over the panel was a mid gray in light mode, under the log's colored words.
                .environment(\.colorScheme, .dark)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: 0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .onChange(of: events.count) { _, newCount in
            if newCount >= 1 && !hasAutoExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded = true
                    hasAutoExpanded = true
                }
            }
        }
        .onChange(of: events.isEmpty) { _, isEmpty in
            if isEmpty {
                hasAutoExpanded = false
            }
        }
        .onChange(of: isTerminal) { _, terminal in
            if terminal && isExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded = false
                }
            }
        }
    }
}

private let consoleEventTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "mm:ss"
    return formatter
}()

struct IngestionConsoleLogRow: View {
    let event: IngestionEvent
    let isLatest: Bool
    // The time and stage columns grow with the text (5.7).
    @ScaledMetric(relativeTo: .body) private var timeColumn: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var stageColumn: CGFloat = 44
    
    private var timestamp: String {
        return consoleEventTimeFormatter.string(from: event.timestamp)
    }
    
    private var stageColor: Color {
        switch event.stage {
        case .queued: return .gray
        case .paused: return .orange
        case .loading: return .blue
        case .transcribing: return .purple
        case .extracting: return .orange
        case .chunking: return .green
        case .analyzing: return .teal
        case .adapting: return .yellow
        case .reindexing: return .pink
        case .embedding: return .indigo
        case .indexing: return .mint
        case .storing: return .cyan
        case .complete: return .green
        case .cancelled: return .orange
        case .failed: return .red
        }
    }
    
    private var shortStageLabel: String {
        switch event.stage {
        case .transcribing: return "AUDIO"
        case .extracting: return "EXTRACT"
        case .chunking: return "CHUNK"
        case .analyzing: return "ANALYZE"
        case .adapting: return "ADAPT"
        case .reindexing: return "REINDEX"
        case .embedding: return "EMBED"
        case .indexing: return "INDEX"
        case .storing: return "STORE"
        case .queued: return "QUEUE"
        case .paused: return "PAUSE"
        case .loading: return "LOAD"
        case .complete: return "DONE"
        case .cancelled: return "CANCEL"
        case .failed: return "FAIL"
        }
    }
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // One line, and at accessibility sizes the time, the stage and the words on lines of their own, with the
        // words wrapping: across one line the two scaled columns left the words a few letters (5.7).
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let rowLayout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1)) : AnyLayout(HStackLayout(alignment: .center, spacing: 4))
        return rowLayout {
            Text(timestamp)
                .scaledFont(size: 8, weight: .medium, design: .monospaced)
                .foregroundStyle(Color(white: 0.72))
                .frame(width: timeColumn, alignment: .leading)
                
            Text(shortStageLabel)
                .scaledFont(size: 7, weight: .bold, design: .monospaced)
                .foregroundStyle(DSColors.readable(stageColor))
                .frame(width: stageColumn, alignment: .leading)
                
            // The step and what it did side by side, and one under the other at accessibility sizes, where side by side
            // each wrapped in half the width (5.7).
            let textLayout = isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1)) : AnyLayout(HStackLayout(spacing: 2))
            textLayout {
                Text(event.title)
                    .scaledFont(size: 8, weight: .medium, design: .monospaced)
                    .foregroundStyle(isLatest ? Color.white : Color.white.opacity(0.8))
                    .lineLimit(isAccessibilitySize ? nil : 1)
                
                if let detail = event.detail, !detail.isEmpty {
                    if !isAccessibilitySize {
                        Image(systemName: "arrow.right")
                            .scaledFont(size: 6, weight: .semibold)
                            .foregroundStyle(Color(white: 0.6))
                            .accessibilityHidden(true)
                    }
                    Text(detail)
                        .scaledFont(size: 8, weight: .regular, design: .monospaced)
                        .foregroundStyle(DSColors.readable(stageColor))
                        .lineLimit(isAccessibilitySize ? nil : 1)
                }
            }
            if !isAccessibilitySize {
                Spacer(minLength: 0)
            }

            if isLatest && !isAccessibilitySize {
                Circle()
                    .fill(stageColor)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isLatest ? stageColor.opacity(0.1) : Color.clear)
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

struct IngestionQueueOverlay: View {
    let items: [IngestionItem]
    var onCancelItem: ((UUID) -> Void)? = nil
    var onCancelAll: (() -> Void)? = nil
    var onContinuePaused: (() -> Void)? = nil
    var onDiscardPaused: (() -> Void)? = nil
    var onStopAndDismiss: (() -> Void)? = nil
    /// Pauses the queue (5.7). The button shows while an import runs.
    var onPause: (() -> Void)? = nil
    /// Whether the paused queue was paused by the person rather than stopped by a restart.
    var pausedByPerson: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isMinimized = false
    /// The height of everything under the header, so its scroll view is no taller than that (5.7).
    @State private var panelBodyHeight: CGFloat = 560
    private static let resumeDecisionID = "resumeDecision"
    @State private var isDismissed = false
    /// The GPU profile Settings shows, read from its own key so this button and Settings agree (5.7). Until 5.7 the
    /// button wrote `gpuAccelerationLevel`, which `DeviceCapabilityService` reads only when no profile is stored, and
    /// one is stored at every launch (`migrateGPUExecutionProfile`), so the button changed its own label and nothing
    /// else; its three states also called Maximum "Performance".
    @AppStorage(DeviceCapabilityService.gpuProfileDefaultsKey) private var gpuProfileRaw: String = GPUExecutionProfile.balanced.rawValue

    private var sortedItems: [IngestionItem] {
        items.sorted { lhs, rhs in
            sortOrder(for: lhs) < sortOrder(for: rhs)
        }
    }

    private func sortOrder(for item: IngestionItem) -> Int {
        switch item.stage {
        case .paused: return 0
        case .queued: return 1
        case .loading, .transcribing, .extracting, .chunking, .analyzing, .embedding, .storing,
             .adapting, .reindexing, .indexing: return 0
        case .complete, .cancelled, .failed: return 2
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

    private var cancelledCount: Int {
        items.filter { $0.stage == .cancelled }.count
    }

    private var hasCancelableItems: Bool {
        items.contains { !$0.stage.isTerminal }
    }

    private var pausedItems: [IngestionItem] {
        items.filter { $0.stage == .paused }
    }

    private var hasPausedItems: Bool {
        !pausedItems.isEmpty
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

    private var overlayMaxWidth: CGFloat {
#if canImport(UIKit)
        let connectedScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let screenWidth = (connectedScenes.first { $0.activationState == .foregroundActive } ?? connectedScenes.first)?
            .screen
            .bounds
            .width ?? 460
        let horizontalInset: CGFloat = horizontalSizeClass == .compact ? 32 : 56
        let widthCap: CGFloat = horizontalSizeClass == .compact ? 380 : 460
        return min(widthCap, max(260, screenWidth - horizontalInset))
#else
        return 460
#endif
    }

    private var overlayAccentColor: Color {
        if hasPausedItems {
            return .orange
        }
        if activeCount == 0 {
            if failedCount > 0 {
                return .red
            }
            if cancelledCount > 0 {
                return .orange
            }
            return DSColors.accent
        }
        return gpuBoostActive ? .orange : DSColors.accent
    }

    private var overlayTint: Color {
        overlayAccentColor.opacity(activeCount > 0 ? 0.16 : 0.08)
    }

    /// The panel itself, drawn only while it is visible (`body`).
    private var panel: some View {
        let visibleItems = Array(sortedItems.prefix(5))
        let hiddenCount = max(0, items.count - visibleItems.count)

        return VStack(alignment: .leading, spacing: isMinimized ? 0 : 16) {
            headerView

            if !isMinimized {
                // Everything under the header scrolls as one, at the height it needs up to 560 points, and less when
                // the screen has less (5.7). Only the files scrolled before, under a decision panel and a totals card
                // that at the largest text sizes filled the screen on their own, so the files were out of reach.
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            if hasPausedItems {
                                resumeDecisionPanel
                                    .id(Self.resumeDecisionID)
                            }

                            // Totals summary card (only show when we have metrics data)
                            if totalMetrics.hasData {
                                TotalsSummaryCard(
                                    metrics: totalMetrics,
                                    completedCount: completedCount,
                                    totalCount: items.count
                                )
                            }

                            VStack(spacing: 12) {
                                ForEach(visibleItems) { item in
                                    IngestionQueueRow(
                                        item: item,
                                        onCancel: item.stage.isTerminal ? nil : { onCancelItem?(item.id) }
                                    )
                                }
                            }

                            if hiddenCount > 0 {
                                Text("+\(hiddenCount) more files in queue")
                                    .scaledFont(size: 11, weight: .medium)
                                    .foregroundStyle(DSColors.secondaryText)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.trailing, 4)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { panelBodyHeight = $0 }
                    }
                    .frame(maxHeight: min(panelBodyHeight, 560))
                    // Continue and Discard sit at the top. Paused from the header with the files scrolled into view, at
                    // the largest sizes they would be out of sight (5.7).
                    .onChange(of: hasPausedItems) { _, paused in
                        guard paused else { return }
                        Task { @MainActor in
                            withAnimation { proxy.scrollTo(Self.resumeDecisionID, anchor: .top) }
                        }
                    }
                }
            }
        }
        .padding(14)
        // The same width minimized (5.7): 260 points left the title a few letters beside Pause and the panel's two
        // buttons, which are 44 points to tap on iPhone and iPad.
        .frame(maxWidth: overlayMaxWidth, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(overlayAccentColor.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .glassCardEffectHelper(cornerRadius: 20, isSelected: false, interactive: false)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: items.count)
        .animation(.spring(response: 0.25), value: isMinimized)
    }

    var body: some View {
        let isVisible = !items.isEmpty && !isDismissed

        // Drawn only while there is something to show (5.7). The panel used to stay in the view at opacity 0 with hit
        // testing off, so on an empty library's Chat and Documents Apple's accessibility audit, and anything else
        // reading the accessibility tree, still found "Upload complete" and "0/0 complete" (2026-10-15); an
        // `accessibilityHidden` on it did not take it out of the audit either (2026-10-16). The same spring brings it
        // in and out as a transition.
        return ZStack {
            if isVisible {
                panel
                    .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: 40)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isVisible)
        .onChange(of: items.isEmpty) { _, isEmpty in
            if isEmpty {
                isDismissed = false
                isMinimized = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.openintelligence.showIngestionQueue"))) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isDismissed = false
                isMinimized = false
            }
        }
    }

    private var gpuProfile: GPUExecutionProfile {
        GPUExecutionProfile(rawValue: gpuProfileRaw) ?? DeviceCapabilityService.shared.gpuExecutionProfile
    }

    /// Performance and Maximum let searching and large searches use the GPU as well.
    private var gpuBoostActive: Bool {
        gpuProfile == .performance || gpuProfile == .maximum
    }

    private var processingModeLabel: String {
        gpuProfile.displayName
    }

    private var processingModeIcon: String {
        switch gpuProfile {
        case .efficiency: return "leaf.fill"
        case .balanced: return "dial.medium.fill"
        case .performance: return "bolt.fill"
        case .maximum: return "gauge.with.dots.needle.100percent"
        }
    }

    /// The colors Settings gives the profiles (`SettingsView.gpuModeColor(for:)`).
    private var processingModeColor: Color {
        switch gpuProfile {
        case .efficiency: return .blue
        case .balanced: return .green
        case .performance: return .orange
        case .maximum: return .red
        }
    }

    /// The activity icon, the title and status, the import's own controls (the processing mode and pause) and the
    /// panel's (hide and close).
    ///
    /// With 44-point buttons the controls took 237 of the 342 points the header has on a 402-point iPhone, and the
    /// title was cut to "Pr..." (5.7). The title and the import's controls share a `WrappingRowLayout`: side by side
    /// when they fit, as on the Mac, and otherwise the controls go under the title. The labels stay on one line and
    /// shrink a little before they are cut, because with no line limit and less width than their longest word
    /// SwiftUI broke inside the word ("Process / ing / uploads" on a 6.3" device). At accessibility sizes the icon
    /// steps aside and the labels wrap, which leaves room across for the words.
    private var headerView: some View {
        HStack(alignment: .top, spacing: 8) {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    Circle()
                        .fill(overlayAccentColor.opacity(0.12))
                    Image(systemName: headerIcon)
                        .foregroundStyle(DSColors.readable(overlayAccentColor))
                        .scaledFont(size: 13, weight: .bold)
                }
                .frame(width: 32, height: 32)
                .frame(minHeight: DSSpacing.tapTarget)
                .accessibilityHidden(true)
            }

            WrappingRowLayout(spacing: 8, lineSpacing: 4, lastAtTrailingEdge: true) {
                headerLabels
                if showsImportControls {
                    importControls
                }
            }

            panelControls
        }
    }

    private var headerLabels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headerTitle)
                .scaledFont(size: 14, weight: .bold)
                .foregroundStyle(DSColors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)

            if !isMinimized {
                Text(statusLine)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
            }
        }
        .frame(minHeight: DSSpacing.tapTarget, alignment: .leading)
    }

    /// The header shows the import's own controls while files are importing (5.7): Pause, and the processing mode while
    /// the panel is open. Paused, the panel under the header has Continue and Discard in words, which the header
    /// repeated as two unlabeled circles.
    private var showsImportControls: Bool {
        activeCount > 0 && !hasPausedItems
    }

    private var importControls: some View {
        HStack(spacing: 4) {
            if !isMinimized {
                processingModeButton
            }

            if let onPause {
                Button {
                    DSHaptics.tick()
                    onPause()
                } label: {
                    Image(systemName: "pause.fill")
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(DSColors.readable(.orange))
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.14))
                        .clipShape(Circle())
                        .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause importing")
                .accessibilityHint("Stops the import until you continue it. A large file goes on from where it stopped.")
            }
        }
    }

    private var processingModeButton: some View {
        Button {
            DSHaptics.tick()
            // The next profile up, Maximum back to Efficiency, through the setter Settings uses, which stores the
            // profile and its level; `gpuProfileRaw` follows the stored profile.
            let ladder: [GPUExecutionProfile] = [.efficiency, .balanced, .performance, .maximum]
            let next = ladder[((ladder.firstIndex(of: gpuProfile) ?? 1) + 1) % ladder.count]
            withAnimation(.spring(response: 0.3)) {
                DeviceCapabilityService.shared.gpuExecutionProfile = next
                gpuProfileRaw = next.rawValue
            }
        } label: {
            // The word in the label color, the mode's color in the icon and the tint (5.7).
            HStack(spacing: 4) {
                Image(systemName: processingModeIcon)
                    .foregroundStyle(DSColors.readable(processingModeColor))
                Text(processingModeLabel)
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(DSColors.primaryText)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(processingModeColor.opacity(gpuBoostActive ? 0.18 : 0.10))
            .clipShape(Capsule())
            .frame(minHeight: DSSpacing.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Processing mode")
        .accessibilityValue(processingModeLabel)
        .accessibilityHint("Switches to the next GPU profile, the same setting as in Settings, Device & Performance.")
    }

    private var panelControls: some View {
        HStack(spacing: 4) {
            Button {
                DSHaptics.light()
                withAnimation { isMinimized.toggle() }
            } label: {
                Image(systemName: isMinimized ? "chevron.up" : "chevron.down")
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(DSColors.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(DSColors.secondaryText.opacity(0.08))
                    .clipShape(Circle())
                    .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMinimized ? "Show import details" : "Hide import details")

            // Not while uploads are paused, as before (5.7): Discard is the way to drop them. Stop and dismiss would
            // delete their checkpoints with no question.
            if !hasPausedItems {
                Button {
                    DSHaptics.medium()
                    onStopAndDismiss?()
                    withAnimation { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(size: 10, weight: .heavy)
                        .foregroundStyle(DSColors.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(DSColors.secondaryText.opacity(0.12))
                        .clipShape(Circle())
                        .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)
                        .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasCancelableItems ? "Stop and dismiss ingestion" : "Dismiss ingestion summary")
            .accessibilityHint(hasCancelableItems ? "Stops the current queue and prevents automatic restoration of these items." : "Closes the completed ingestion summary.")
            }
        }
    }

    private var resumeDecisionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(DSColors.readable(.orange))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        pausedByPerson
                            ? (pausedItems.count == 1 ? "Upload paused" : "\(pausedItems.count) uploads paused")
                            : (pausedItems.count == 1 ? "Interrupted upload paused" : "\(pausedItems.count) interrupted uploads paused"))
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        pausedByPerson
                            ? "Continue picks up where it stopped. A file that isn't saved in pieces starts over."
                            : "Continue processing or discard the saved queue.")
                        .scaledFont(size: 11, weight: .medium)
                        // The label color on the orange tint, where gray measured 4.48 to 1 (5.7).
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Side by side, and stacked at accessibility sizes, where they were cut to "Conti..." and "Disc..." (5.7).
            // The words in the label color, the color in the icon and the tint.
            let buttonLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            buttonLayout {
                Button {
                    DSHaptics.tick()
                    onContinuePaused?()
                } label: {
                    Label {
                        Text("Continue")
                    } icon: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(DSColors.readable(.green))
                    }
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(DSColors.primaryText)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
                    .background(Color.green.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    DSHaptics.medium()
                    onDiscardPaused?()
                } label: {
                    Label {
                        Text("Discard")
                    } icon: {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(DSColors.readable(.red))
                    }
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(DSColors.primaryText)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
                    .background(Color.red.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusLine: String {
        if hasPausedItems {
            let count = pausedItems.count
            return count == 1 ? "1 upload waiting for a decision" : "\(count) uploads waiting for a decision"
        }

        let total = items.count
        let completed = completedCount
        var segments = ["\(completed)/\(total) complete"]
        if cancelledCount > 0 {
            segments.append("\(cancelledCount) cancelled")
        }
        if failedCount > 0 {
            segments.append("\(failedCount) failed")
        }
        return segments.joined(separator: " • ")
    }

    private var headerTitle: String {
        if hasPausedItems {
            return pausedByPerson ? "Uploads paused" : "Resume interrupted upload?"
        }

        if activeCount > 0 {
            return "Processing uploads"
        }
        if failedCount > 0 {
            return "Upload failed"
        }
        if cancelledCount > 0 {
            return "Upload cancelled"
        }
        return "Upload complete"
    }

    private var headerIcon: String {
        if hasPausedItems {
            return "pause.circle.fill"
        }

        if activeCount > 0 {
            return "tray.and.arrow.down.fill"
        }
        if failedCount > 0 {
            return "xmark.octagon.fill"
        }
        if cancelledCount > 0 {
            return "slash.circle.fill"
        }
        return "checkmark.circle.fill"
    }
}

private struct IngestionQueueRow: View {
    let item: IngestionItem
    var onCancel: (() -> Void)? = nil
    @State private var showDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The dot between the stage, what it is doing and the time: drawn, so it is not text that VoiceOver cannot reach,
    /// which Apple's element check reports when a "•" is hidden from it (5.7).
    @ScaledMetric(relativeTo: .body) private var separatorSize: CGFloat = 3
    private var separatorDot: some View {
        Circle()
            .fill(DSColors.secondaryText)
            .frame(width: separatorSize, height: separatorSize)
    }

    /// The timing bars' columns grow with their text (5.7).
    @ScaledMetric(relativeTo: .body) private var timingLabelColumn: CGFloat = 45
    @ScaledMetric(relativeTo: .body) private var timingValueColumn: CGFloat = 35

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        // The stage, what it is doing and the time on one line, and at accessibility sizes on lines of their own:
        // squeezed across one line, "Paused" broke into "Pause / d" (5.7).
        let stageLineLayout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 4))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Leading Icon. The stage's word says what it shows.
                ZStack {
                    Circle()
                        .fill(stageColor.opacity(0.12))
                    Image(systemName: stageIcon)
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(DSColors.readable(stageColor))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .scaledFont(size: 13, weight: .semibold)
                        .lineLimit(isAccessibilitySize ? 3 : 1)
                        .truncationMode(.middle)
                        .foregroundStyle(DSColors.primaryText)

                    stageLineLayout {
                        // The word in the label color, the stage's color in the icon (5.7).
                        Text(item.stage.displayName)
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(DSColors.primaryText)
                            .fixedSize(horizontal: !isAccessibilitySize, vertical: false)

                        if !item.detail.isEmpty {
                            if !isAccessibilitySize {
                                separatorDot
                            }
                            Text(item.detail)
                                .scaledFont(size: 10)
                                .foregroundStyle(DSColors.secondaryText)
                                .lineLimit(isAccessibilitySize ? nil : 1)
                        }

                        if let startedAt = item.startedAt, !item.stage.isTerminal {
                            if !isAccessibilitySize {
                                separatorDot
                            }
                            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                                .scaledFont(size: 10, design: .monospaced)
                                .foregroundStyle(DSColors.secondaryText)
                        }

                        if item.stage == .complete {
                            let durationSec: Double = {
                                if let startedAt = item.startedAt, let finishedAt = item.finishedAt {
                                    return finishedAt.timeIntervalSince(startedAt)
                                } else {
                                    return Double(item.metrics.totalTimeMs) / 1000.0
                                }
                            }()
                            if durationSec > 0 {
                                if !isAccessibilitySize {
                                    separatorDot
                                }
                                // Gray like the running time: green measured under 4.5 to 1 even in Apple's
                                // high-contrast green (5.7).
                                Text(String(format: "%.1fs", durationSec))
                                    .scaledFont(size: 10, design: .monospaced)
                                    .foregroundStyle(DSColors.secondaryText)
                            }
                        }
                    }
                }

                Spacer()

                if let onCancel, !item.stage.isTerminal {
                    Button(action: {
                        DSHaptics.soft()
                        onCancel()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 16)
                            .foregroundStyle(DSColors.secondaryText)
                            .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel this file's import")
                } else if item.stage == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(size: 16)
                        .foregroundStyle(DSColors.readable(.green))
                }
            }

            if let progress = item.progress, !item.stage.isTerminal {
                CustomProgressBar(value: progress, color: stageColor)
                    .frame(height: 4)
            }

            if !item.events.isEmpty {
                IngestionConsoleView(events: item.events, isTerminal: item.stage.isTerminal)
                    .padding(.top, 2)
            }

            // Show live metrics when processing in a clean, consolidated line
            if hasMetrics {
                HStack(spacing: 8) {
                    compactMetricsRow
                    
                    Spacer()
                    
                    Button {
                        DSHaptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showDetails.toggle()
                        }
                    } label: {
                        Image(systemName: showDetails ? "info.circle.fill" : "info.circle")
                            .scaledFont(size: 12)
                            .foregroundStyle(showDetails ? DSColors.accent : DSColors.secondaryText)
                            .frame(minWidth: DSSpacing.tapTarget, minHeight: DSSpacing.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showDetails ? "Hide this file's details" : "Show this file's details")
                }
                .padding(.top, 2)
            }

            if showDetails && hasMetrics {
                // A diagnostics panel of figures in columns: it grows with the text size up to the largest size
                // below the accessibility sizes (5.7).
                pipelineDetailsView
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let errorMessage = item.errorMessage, item.stage == .failed {
                Text(errorMessage)
                    .scaledFont(size: 10)
                    .foregroundStyle(DSColors.readable(.red))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        // The elevated surface, nearly opaque (white in light), so the row's gray text reads at 4.5 to 1 over the glass
        // panel: on the plain surface at 40% it measured 4.24 to 4.43 in light (5.7).
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DSColors.surfaceElevated.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(stageColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var compactMetricsRow: some View {
        let m = item.metrics
        return HStack(spacing: 6) {
            if m.chunkCount > 0 {
                metricLabel(icon: "square.split.2x2", value: "\(m.chunkCount)")
            }
            if m.embeddingsGenerated > 0 {
                metricLabel(icon: "brain.head.profile", value: "\(m.embeddingsGenerated)")
            }
            if m.fileSizeMB > 0 {
                metricLabel(icon: "doc", value: String(format: "%.1fMB", m.fileSizeMB))
            }
            if m.usedStructuredParsing {
                Image(systemName: "eye.fill")
                    .scaledFont(size: 8)
                    .foregroundStyle(DSColors.readable(.green))
            }
        }
    }

    @ViewBuilder
    private func metricLabel(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .scaledFont(size: 8)
            Text(value)
                .scaledFont(size: 9, weight: .bold, design: .monospaced)
        }
        .foregroundStyle(DSColors.secondaryText)
    }

    private var hasMetrics: Bool {
        // Simplified metrics check
        item.metrics.chunkCount > 0 || 
        item.metrics.embeddingsGenerated > 0 ||
        item.metrics.fileSizeMB > 0
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                            .scaledFont(size: 9)
                        Text("OCR: \(m.ocrPagesCount) page\(m.ocrPagesCount > 1 ? "s" : "") scanned")
                    }
                    .font(.caption2)
                    .foregroundStyle(DSColors.readable(.orange))
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
                .scaledFont(size: 10)
                .foregroundStyle(DSColors.readable(m.usedStructuredParsing ? .green : .orange))
            Text(m.usedStructuredParsing ? "RecognizeDocumentsRequest" : "PDFKit Fallback")
                .scaledFont(size: 9, weight: .medium, design: .monospaced)
                .foregroundStyle(DSColors.primaryText)
            if m.structuredParsingQuality > 0 {
                Text("(\(Int(m.structuredParsingQuality * 100))% quality)")
                    .scaledFont(size: 8)
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((m.usedStructuredParsing ? Color.green : Color.orange).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                Image(systemName: icon).scaledFont(size: 9).foregroundStyle(DSColors.readable(color))
                Text("\(count)").scaledFont(size: 11, weight: .bold, design: .monospaced)
                    .foregroundStyle(DSColors.primaryText)
            }
            Text(label).scaledFont(size: 8).foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func visionTableDetails(_ m: PipelineMetrics) -> some View {
        if m.tablesExtracted > 0 && (m.tableRowsTotal > 0 || m.tableColumnsMax > 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TABLE STRUCTURE").scaledFont(size: 8, weight: .bold, design: .monospaced).foregroundStyle(DSColors.readable(.cyan))
                HStack(spacing: 8) {
                    if m.tableRowsTotal > 0 { HStack(spacing: 2) { Text("\(m.tableRowsTotal)").scaledFont(size: 10, weight: .semibold); Text("rows").scaledFont(size: 8).foregroundStyle(DSColors.secondaryText) } }
                    if m.tableColumnsMax > 0 { HStack(spacing: 2) { Text("\(m.tableColumnsMax)").scaledFont(size: 10, weight: .semibold); Text("max cols").scaledFont(size: 8).foregroundStyle(DSColors.secondaryText) } }
                    if m.atomicTableChunks > 0 { HStack(spacing: 2) { Image(systemName: "lock.fill").scaledFont(size: 7); Text("\(m.atomicTableChunks) atomic").scaledFont(size: 8) }.foregroundStyle(DSColors.readable(.green)) }
                }
            }
            .padding(6)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private func visionExtras(_ m: PipelineMetrics) -> some View {
        if m.visionEntitiesDetected > 0 {
            HStack(spacing: 4) {
                Image(systemName: "sparkle.magnifyingglass").scaledFont(size: 9)
                Text("\(m.visionEntitiesDetected) auto-detected").scaledFont(size: 9)
                Text("(emails, phones, dates)").scaledFont(size: 8).foregroundStyle(DSColors.secondaryText)
            }
            .foregroundStyle(DSColors.readable(.mint))
        }
        if m.sectionPathDepth > 1 {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.indent").scaledFont(size: 9)
                Text("\(m.sectionPathDepth)-level hierarchy").scaledFont(size: 9)
            }
            .foregroundStyle(DSColors.readable(.indigo))
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
                Image(systemName: "lock.rectangle.stack").scaledFont(size: 9)
                if m.atomicTableChunks > 0 { Text("\(m.atomicTableChunks) table\(m.atomicTableChunks > 1 ? "s" : "")") }
                if m.atomicListChunks > 0 { Text("\(m.atomicListChunks) list\(m.atomicListChunks > 1 ? "s" : "")") }
                Text("kept atomic").foregroundStyle(DSColors.secondaryText)
            }
            .scaledFont(size: 9)
            .foregroundStyle(DSColors.primaryText)
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
                Text("BOUNDARIES").scaledFont(size: 8, weight: .bold, design: .monospaced).foregroundStyle(DSColors.readable(DSColors.accent))
                HStack(spacing: 10) {
                    if m.sectionsDetected > 0 { boundaryItem(icon: "list.bullet.indent", value: m.sectionsDetected, label: "Sections", desc: "Heading") }
                    if m.topicBoundaries > 0 { boundaryItem(icon: "arrow.triangle.branch", value: m.topicBoundaries, label: "Topics", desc: "TF-IDF") }
                    if m.embeddingBoundaries > 0 { boundaryItem(icon: "waveform.path.ecg", value: m.embeddingBoundaries, label: "∇Sim", desc: "Cosine") }
                }
            }
            .padding(6)
            .background(DSColors.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        // Document content profile — shows what the document actually IS
        if !m.documentDomain.isEmpty || !m.contentDescriptor.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !m.documentDomain.isEmpty {
                    HStack(spacing: 6) {
                        domainChip(m.documentDomain)
                        if !m.documentLanguage.isEmpty {
                            Text(m.documentLanguage)
                                .scaledFont(size: 9, design: .monospaced)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }
                if !m.contentDescriptor.isEmpty {
                    Text(m.contentDescriptor)
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.primaryText)
                        .lineLimit(2)
                }
            }
            .padding(6)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }

        // Content categories as topic chips
        if !m.contentCategories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(m.contentCategories.prefix(6), id: \.self) { category in
                        Text(category)
                            .scaledFont(size: 9, weight: .medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DSColors.accent.opacity(0.12))
                            .foregroundStyle(DSColors.primaryText)
                            .clipShape(Capsule())
                    }
                }
            }
        }

        // Content type badges
        if m.hasCode || m.hasMath {
            HStack(spacing: 6) {
                if m.hasCode { contentBadge(icon: "chevron.left.forwardslash.chevron.right", text: "Code", color: .orange) }
                if m.hasMath { contentBadge(icon: "function", text: "Math", color: .pink) }
            }
        }

        // Extraction coverage bar (how much of the document was successfully extracted)
        if m.extractionCoverage > 0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("EXTRACTION").scaledFont(size: 7, weight: .bold, design: .monospaced).foregroundStyle(DSColors.secondaryText)
                    Spacer()
                    Text(String(format: "%.0f%%", m.extractionCoverage * 100))
                        .scaledFont(size: 9, weight: .bold, design: .monospaced)
                        .foregroundStyle(DSColors.primaryText)
                }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(m.extractionCoverage > 0.9 ? .green : m.extractionCoverage > 0.7 ? .yellow : .red)
                        .frame(width: max(4, 80 * min(1, m.extractionCoverage)), height: 3)
                }
            }
        }
    }

    /// Chip displaying the auto-classified document domain
    @ViewBuilder
    private func domainChip(_ domain: String) -> some View {
        let (icon, color) = domainIconAndColor(domain)
        HStack(spacing: 3) {
            Image(systemName: icon)
                .scaledFont(size: 8)
                .foregroundStyle(DSColors.readable(color))
            Text(domain)
                .scaledFont(size: 9, weight: .semibold)
                .foregroundStyle(DSColors.primaryText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func domainIconAndColor(_ domain: String) -> (String, Color) {
        let d = domain.lowercased()
        if d.contains("vehicle") || d.contains("automotive") || d.contains("car") { return ("car.fill", .blue) }
        if d.contains("medical") || d.contains("health") { return ("cross.case.fill", .red) }
        if d.contains("legal") || d.contains("law") || d.contains("contract") { return ("building.columns.fill", .indigo) }
        if d.contains("financial") || d.contains("finance") { return ("chart.line.uptrend.xyaxis", .green) }
        if d.contains("academic") || d.contains("research") || d.contains("scientific") { return ("graduationcap.fill", .purple) }
        if d.contains("technical") || d.contains("engineering") { return ("wrench.and.screwdriver.fill", .orange) }
        if d.contains("manual") || d.contains("guide") || d.contains("instruction") { return ("book.fill", .cyan) }
        if d.contains("report") { return ("doc.text.fill", .teal) }
        if d.contains("policy") || d.contains("compliance") { return ("shield.fill", .mint) }
        return ("doc.fill", .secondary)
    }

    @ViewBuilder
    private func corpusEntities(_ m: PipelineMetrics) -> some View {
        if m.entitiesExtracted > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "tag.fill").scaledFont(size: 9).foregroundStyle(DSColors.readable(.cyan))
                    Text("\(m.entitiesExtracted) ENTITIES").scaledFont(size: 8, weight: .bold, design: .monospaced).foregroundStyle(DSColors.readable(.cyan))
                }
                if !m.topEntities.isEmpty {
                    Text(m.topEntities.prefix(5).joined(separator: " • ")).scaledFont(size: 9).foregroundStyle(DSColors.secondaryText).lineLimit(2)
                }
            }
            .padding(6)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                            Text(shortProviderDisplay(m.embeddingProvider)).scaledFont(size: 11, weight: .bold, design: .monospaced).foregroundStyle(DSColors.accent)
                            Text("Encoder").scaledFont(size: 8).foregroundStyle(DSColors.secondaryText)
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
                    Text("TOTAL").scaledFont(size: 9, weight: .bold, design: .monospaced)
                    Spacer()
                    Text(formatMs(m.totalTimeMs)).scaledFont(size: 12, weight: .bold, design: .monospaced).foregroundStyle(DSColors.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func rebuildSection(_ m: PipelineMetrics) -> some View {
        if m.isRebuild && !m.rebuildReason.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").scaledFont(size: 10)
                    .foregroundStyle(DSColors.readable(.orange))
                Text("REBUILD: \(m.rebuildReason)").scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(DSColors.primaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: - Granular Detail Components

    @ViewBuilder
    private func detailSection(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .scaledFont(size: 10)
                    .foregroundStyle(DSColors.accent)
                Text(title)
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(DSColors.primaryText)
                
                Spacer()
                
                Rectangle()
                    .fill(DSColors.separator)
                    .frame(height: 1)
            }
            content()
        }
        .padding(10)
        .background(DSColors.surface.opacity(0.4))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func statBox(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .scaledFont(size: 8, weight: .medium)
                .foregroundStyle(DSColors.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .scaledFont(size: 13, weight: .bold, design: .monospaced)
                    .foregroundStyle(DSColors.primaryText)
                if !unit.isEmpty {
                    Text(unit)
                        .scaledFont(size: 9, weight: .semibold)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func strategyPill(_ strategy: String) -> some View {
        Text(strategy)
            .scaledFont(size: 9, weight: .semibold, design: .monospaced)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DSColors.accent.opacity(0.15))
            .foregroundStyle(DSColors.primaryText)
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
        .scaledFont(size: 8)
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
                    .scaledFont(size: 8)
                Text("\(value)")
                    .scaledFont(size: 10, weight: .bold, design: .monospaced)
                Text(label)
                    .scaledFont(size: 8, weight: .medium)
            }
            Text(desc)
                .scaledFont(size: 7)
                .foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func metricGauge(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.2))
                    .frame(width: 40, height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 40 * min(1, value), height: 4)
            }
            Text("\(Int(value * 100))%")
                .scaledFont(size: 9, weight: .bold, design: .monospaced)
            Text(label)
                .scaledFont(size: 7)
                .foregroundStyle(DSColors.secondaryText)
        }
    }

    @ViewBuilder
    private func contentBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .scaledFont(size: 8)
                .foregroundStyle(DSColors.readable(color))
            Text(text)
                .scaledFont(size: 9, weight: .semibold)
                .foregroundStyle(DSColors.primaryText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func timingBadge(label: String, ms: Int, throughput: Double?, unit: String?) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .scaledFont(size: 8)
                Text(label)
                    .scaledFont(size: 8)
                Text(formatMs(ms))
                    .scaledFont(size: 9, weight: .bold, design: .monospaced)
            }
            .foregroundStyle(DSColors.secondaryText)

            if let throughput, let unit, throughput > 0 {
                Text("⚡ \(formatNumber(Int(throughput))) \(unit)")
                    .scaledFont(size: 8, weight: .medium, design: .monospaced)
                    .foregroundStyle(DSColors.readable(DSColors.accent))
            }
        }
    }

    @ViewBuilder
    private func timingBar(label: String, ms: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Double(ms) / Double(total) : 0
        HStack(spacing: 6) {
            Text(label)
                .scaledFont(size: 8, weight: .medium)
                .frame(width: timingLabelColumn, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 6)

            Text(formatMs(ms))
                .scaledFont(size: 8, design: .monospaced)
                .frame(width: timingValueColumn, alignment: .trailing)
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
        case .paused: return "pause.circle.fill"
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
        case .cancelled: return "slash.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var stageColor: Color {
        switch item.stage {
        case .failed: return .red
        case .complete: return .green
        case .cancelled: return .orange
        case .paused: return .orange
        case .queued: return .gray
        default: return DSColors.accent
        }
    }
}

private struct CustomProgressBar: View {
    let value: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.1))
                
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(value))
            }
        }
    }
}

private struct TotalsSummaryCard: View {
    let metrics: AggregatedMetrics
    let completedCount: Int
    let totalCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(DSColors.accent)
                // In the label color: gray on the card's tint measured 3.99 and 4.52 to 1 (5.7).
                Text("BATCH TOTALS")
                    .scaledFont(size: 9, weight: .bold, design: .rounded)
                    .foregroundStyle(DSColors.primaryText)
                Spacer()
                if metrics.totalFileSizeMB > 0 {
                    Text(String(format: "%.1f MB", metrics.totalFileSizeMB))
                        .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                        .foregroundStyle(DSColors.primaryText)
                }
            }

            // Primary stats row - more integrated and less "heavy"
            // Across, and stacked at accessibility sizes, where a quarter of the row broke "42" into "4 / 2" (5.7).
            let statLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
            statLayout {
                totalStatItem(
                    icon: "doc.fill", value: "\(completedCount)/\(totalCount)", color: .blue,
                    spoken: "\(completedCount) of \(totalCount) files done")
                totalStatItem(
                    icon: "square.split.2x2.fill", value: formatNumber(metrics.totalChunks), color: .purple,
                    spoken: "\(formatNumber(metrics.totalChunks)) passages")
                totalStatItem(
                    icon: "brain.head.profile.fill", value: formatNumber(metrics.totalVectors), color: .green,
                    spoken: "\(formatNumber(metrics.totalVectors)) vectors")
                totalStatItem(
                    icon: "textformat", value: formatNumber(metrics.totalWords), color: .orange,
                    spoken: "\(formatNumber(metrics.totalWords)) words")
            }
            .padding(10)
            .background(DSColors.surface.opacity(0.3))
            .cornerRadius(12)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DSColors.accent.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DSColors.accent.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func totalStatItem(icon: String, value: String, color: Color, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .scaledFont(size: 8)
                    .foregroundStyle(DSColors.readable(color))
                Text(value)
                    .scaledFont(size: 12, weight: .bold, design: .monospaced)
                    .foregroundStyle(DSColors.primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // VoiceOver read the symbol's name and a bare number (5.7).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
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

#Preview {
    IngestionQueueOverlay(items: [
        IngestionItem(
            url: URL(fileURLWithPath: "/tmp/report.pdf"),
            stage: .embedding,
            detail: "Embedding chunks...",
            progress: 0.65
        ),
        IngestionItem(
            url: URL(fileURLWithPath: "/tmp/notes.txt"),
            stage: .queued,
            detail: "Queued"
        )
    ])
}

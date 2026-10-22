import SwiftUI

/// Raw console-style view showing exactly what the RAG pipeline is doing.
/// No abstractions - just the literal log of operations as they happen.
struct ThinkingStreamView: View {
    let events: [ThinkingEvent]
    var qualityMode: RAGQualityMode? = nil

    @State private var isExpanded = true  // Default expanded to show the action
    @State private var isFullHeight = false  // Secondary expand for full history view
    @State private var hasAutoExpanded = false
    @AppStorage("thinkingViewAutoCollapse") private var autoCollapse = true

    enum ViewMode {
        case console
        case visualGates
    }
    @State private var viewMode: ViewMode = .visualGates

    private var latestEvent: ThinkingEvent? {
        events.last
    }

    /// Elapsed time since first event
    private var pipelineElapsed: TimeInterval? {
        guard let first = events.first, let last = events.last else { return nil }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - shows latest action, tappable to expand/collapse
            Button(action: { withAnimation(DSAnimations.snappySpring) { isExpanded.toggle() } }) {
                headerView
            }
            .buttonStyle(.plain)

            // Expanded: Full console log of all events or visual gates
            if isExpanded {
                VStack(spacing: DSSpacing.sm) {
                    // Mode Picker
                    Picker("View Mode", selection: $viewMode) {
                        Text("Gates").tag(ViewMode.visualGates)
                        Text("Console").tag(ViewMode.console)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.top, DSSpacing.sm)
                    
                    if viewMode == .visualGates {
                        VerificationGatesOverlayView(events: events, qualityMode: qualityMode)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.bottom, DSSpacing.sm)
                    } else {
                        consoleLogView
                    }
                }
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(DSAnimations.snappySpring, value: isExpanded)
        .animation(DSAnimations.fastEase, value: events.count)
        // Auto-expand when events start coming in
        .onChange(of: events.count) { _, newCount in
            if newCount >= 1 && !hasAutoExpanded {
                withAnimation(DSAnimations.snappySpring) {
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
    }

    // MARK: - Header (compact summary when collapsed)

    private var headerView: some View {
        HStack(spacing: DSSpacing.xs) {
            // Pulsing dot when active
            ThinkingPulse()

            // Latest operation (what's happening RIGHT NOW)
            if let latest = latestEvent {
                Text(latest.title)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(colorFor(latest.kind))
                    .lineLimit(1)

                if let detail = latest.detail, !detail.isEmpty {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText.opacity(0.5))
                    Text(detail)
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(DSColors.secondaryText.opacity(0.8))
                        .lineLimit(1)
                }
            } else {
                Text("Initializing...")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Spacer(minLength: DSSpacing.xs)

            // Event count + elapsed
            if events.count > 0 {
                HStack(spacing: DSSpacing.xxs) {
                    Text("\(events.count)")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.accent)

                    if let elapsed = pipelineElapsed, elapsed > 0.1 {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText.opacity(0.4))
                        Text(formatElapsed(elapsed))
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText.opacity(0.7))
                    }
                }
            }

            // Expand/collapse
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DSColors.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColors.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

    // MARK: - Console Log View (the raw pipeline output)

    private var consoleLogView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Each event as a log line
                        ForEach(events) { event in
                            ConsoleLogRow(event: event, isLatest: event.id == latestEvent?.id)
                                .id(event.id)
                        }
                    }
                }
                .frame(maxHeight: isFullHeight ? 350 : 120)  // Compact by default, expandable
                .onChange(of: events.count) { _, _ in
                    // Auto-scroll to latest event
                    if let latest = latestEvent {
                        withAnimation(DSAnimations.fastEase) {
                            proxy.scrollTo(latest.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Expand/collapse button for full history
            if events.count > 8 {
                Button(action: {
                    withAnimation(DSAnimations.snappySpring) {
                        isFullHeight.toggle()
                    }
                }) {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: isFullHeight ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                            .font(.caption2.weight(.medium))
                        Text(isFullHeight ? "Compact" : "Full History (\(events.count))")
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DSColors.accent.opacity(0.7))
                    .padding(.vertical, DSSpacing.xxs)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.03))
                    // The label stays small, and the whole row takes the tap (5.7): a tap on the 10-point-tall
                    // label alone missed it in a demo take.
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DSSpacing.xxs)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(Color.black.opacity(0.85))  // Console-like dark background
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .stroke(DSColors.accent.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.top, DSSpacing.xxs)
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        if elapsed < 1 {
            return String(format: "%.0fms", elapsed * 1000)
        } else if elapsed < 60 {
            return String(format: "%.1fs", elapsed)
        } else {
            let mins = Int(elapsed) / 60
            let secs = Int(elapsed) % 60
            return "\(mins)m\(secs)s"
        }
    }

    private func colorFor(_ kind: ThinkingEvent.Kind) -> Color {
        switch kind.color {
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "teal": return .teal
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "pink": return .pink
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return DSColors.secondaryText
        }
    }
}

// MARK: - Console Log Row (single line in the log)

private struct ConsoleLogRow: View {
    let event: ThinkingEvent
    let isLatest: Bool

    private var tint: Color {
        switch event.kind.color {
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "teal": return .teal
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "pink": return .pink
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .gray
        }
    }

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"  // Just minutes:seconds
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: DSSpacing.xs) {
            // Timestamp (compact)
            Text(timestamp)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.gray.opacity(0.5))
                .frame(width: 36, alignment: .leading)

            // Kind indicator (short colored tag)
            Text(shortKindLabel)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 52, alignment: .leading)

            // Title (the main message)
            Text(event.title)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(isLatest ? Color.white : Color.white.opacity(0.8))
                .lineLimit(1)

            // Detail (additional info)
            if let detail = event.detail, !detail.isEmpty {
                Text("→")
                    .font(.caption2)
                    .foregroundStyle(Color.gray.opacity(0.4))
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            // Latest indicator (tiny dot)
            if isLatest {
                Circle()
                    .fill(tint)
                    .frame(width: 3, height: 3)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.vertical, DSSpacing.xxs)
        .padding(.horizontal, DSSpacing.xxs)
        .background(isLatest ? tint.opacity(0.08) : Color.clear)
    }

    /// Short label for the kind (saves horizontal space)
    private var shortKindLabel: String {
        switch event.kind {
        case .planning: return "PLAN"
        case .embedding: return "EMBED"
        case .retrieval: return "RETRIEV"
        case .rerank: return "RERANK"
        case .gating: return "GATE"
        case .context: return "CONTXT"
        case .generation: return "GENER8"
        case .fallback: return "FALLBACK"
        case .warning: return "WARN"
        case .hyde: return "HYDE"
        case .queryRewrite: return "QRYRWR"
        case .bm25: return "BM25"
        case .vectorSearch: return "VECTOR"
        case .rrf: return "RRF"
        case .mmr: return "MMR"
        case .parentDoc: return "PARENT"
        case .compression: return "COMPRESS"
        case .lostInMiddle: return "REORDR"
        case .grounding: return "GROUND"
        case .selfRag: return "SELF-RAG"
        case .iterative: return "ITERATE"
        case .agentic: return "AGENTIC"
        case .toolCall: return "TOOL"
        case .factBank: return "FACTS"
        case .verification: return "VERIFY"
        case .graphPack: return "GRAPH"
        case .extractive: return "EXTRACT"
        case .intentRoute: return "INTENT"
        case .confidence: return "CONFID"
        case .imagePlayground: return "IMAGIN"
        case .reasoning: return "THINK"
        }
    }
}

// MARK: - Thinking Pulse (animated dot)

private struct ThinkingPulse: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(DSColors.accent)
            .frame(width: 5, height: 5)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(DSAnimations.stagePulse, value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#Preview("Console Log") {
    let sample: [ThinkingEvent] = [
        ThinkingEvent(kind: .planning, title: "Analyzing query intent", detail: "factual • technical"),
        ThinkingEvent(kind: .hyde, title: "Generating hypothetical document", detail: "128 tokens"),
        ThinkingEvent(kind: .embedding, title: "Encoding query + HyDE", detail: "384D in 28ms"),
        ThinkingEvent(kind: .bm25, title: "BM25 keyword search", detail: "42 matches in 847 chunks"),
        ThinkingEvent(kind: .vectorSearch, title: "Vector similarity search", detail: "top 20 candidates"),
        ThinkingEvent(kind: .rrf, title: "Reciprocal Rank Fusion", detail: "merged 62 → 25 chunks"),
        ThinkingEvent(kind: .rerank, title: "Cross-encoder reranking", detail: "TinyBERT scoring 25 pairs"),
        ThinkingEvent(kind: .mmr, title: "MMR diversity selection", detail: "λ=0.6 selecting 8 diverse"),
        ThinkingEvent(kind: .parentDoc, title: "Parent document expansion", detail: "+4 sibling chunks"),
        ThinkingEvent(kind: .compression, title: "Context compression", detail: "1,247 → 680 tokens"),
        ThinkingEvent(kind: .lostInMiddle, title: "Attention reordering", detail: "best at edges"),
        ThinkingEvent(kind: .gating, title: "Confidence gating", detail: "min=0.52 top=0.78 PASS"),
        ThinkingEvent(kind: .generation, title: "Streaming response", detail: "38 t/s • Neural Engine"),
    ]
    return VStack {
        ThinkingStreamView(events: sample)
    }
    .padding()
    .background(DSColors.background)
}

import SwiftUI

/// Raw console-style view showing exactly what the RAG pipeline is doing.
/// No abstractions - just the literal log of operations as they happen.
struct ThinkingStreamView: View {
    let events: [ThinkingEvent]

    @State private var isExpanded = true  // Default expanded to show the action
    @State private var hasAutoExpanded = false
    @AppStorage("thinkingViewAutoCollapse") private var autoCollapse = true

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
            Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                headerView
            }
            .buttonStyle(.plain)

            // Expanded: Full console log of all events
            if isExpanded {
                consoleLogView
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: events.count)
        // Auto-expand when events start coming in
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
    }

    // MARK: - Header (compact summary when collapsed)

    private var headerView: some View {
        HStack(spacing: 6) {
            // Pulsing dot when active
            ThinkingPulse()

            // Latest operation (what's happening RIGHT NOW)
            if let latest = latestEvent {
                Text(latest.title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colorFor(latest.kind))
                    .lineLimit(1)

                if let detail = latest.detail, !detail.isEmpty {
                    Text("·")
                        .font(.system(size: 8))
                        .foregroundStyle(DSColors.secondaryText.opacity(0.5))
                    Text(detail)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DSColors.secondaryText.opacity(0.8))
                        .lineLimit(1)
                }
            } else {
                Text("Initializing...")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DSColors.secondaryText)
            }

            Spacer(minLength: 4)

            // Event count + elapsed
            if events.count > 0 {
                HStack(spacing: 3) {
                    Text("\(events.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DSColors.accent)

                    if let elapsed = pipelineElapsed, elapsed > 0.1 {
                        Text("·")
                            .font(.system(size: 6))
                            .foregroundStyle(DSColors.secondaryText.opacity(0.4))
                        Text(formatElapsed(elapsed))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(DSColors.secondaryText.opacity(0.7))
                    }
                }
            }

            // Expand/collapse
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DSColors.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DSColors.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Console Log View (the raw pipeline output)

    private var consoleLogView: some View {
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
            .frame(maxHeight: 120)  // Fixed max height - scrollable within
            .onChange(of: events.count) { _, _ in
                // Auto-scroll to latest event
                if let latest = latestEvent {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(latest.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.85))  // Console-like dark background
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DSColors.accent.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.top, 2)
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
        default: return .gray
        }
    }

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"  // Just minutes:seconds
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // Timestamp (compact)
            Text(timestamp)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.gray.opacity(0.5))
                .frame(width: 28, alignment: .leading)

            // Kind indicator (short colored tag)
            Text(shortKindLabel)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: 36, alignment: .leading)

            // Title (the main message)
            Text(event.title)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(isLatest ? Color.white : Color.white.opacity(0.8))
                .lineLimit(1)

            // Detail (additional info)
            if let detail = event.detail, !detail.isEmpty {
                Text("→")
                    .font(.system(size: 6))
                    .foregroundStyle(Color.gray.opacity(0.4))
                Text(detail)
                    .font(.system(size: 7, weight: .regular, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Latest indicator (tiny dot)
            if isLatest {
                Circle()
                    .fill(tint)
                    .frame(width: 3, height: 3)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(isLatest ? tint.opacity(0.08) : Color.clear)
    }

    /// Short label for the kind (saves horizontal space)
    private var shortKindLabel: String {
        switch event.kind {
        case .planning: return "PLAN"
        case .embedding: return "EMBED"
        case .retrieval: return "RETRIV"
        case .rerank: return "RERANK"
        case .gating: return "GATE"
        case .context: return "CONTXT"
        case .generation: return "GENER"
        case .fallback: return "FALLBK"
        case .warning: return "WARN"
        case .hyde: return "HYDE"
        case .queryRewrite: return "QREWR"
        case .bm25: return "BM25"
        case .vectorSearch: return "VECTOR"
        case .rrf: return "RRF"
        case .mmr: return "MMR"
        case .parentDoc: return "PARENT"
        case .compression: return "COMPR"
        case .lostInMiddle: return "REORDR"
        case .grounding: return "GROUND"
        case .selfRag: return "SELFRAG"
        case .iterative: return "ITERAT"
        case .agentic: return "AGENTIC"
        case .toolCall: return "TOOL"
        case .factBank: return "FACTS"
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
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
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

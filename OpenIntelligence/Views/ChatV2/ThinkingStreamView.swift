import SwiftUI

struct ThinkingStreamView: View {
    let events: [ThinkingEvent]
    
    @State private var isExpanded = false
    @AppStorage("thinkingViewAutoCollapse") private var autoCollapse = true

    private var recentEvents: [ThinkingEvent] {
        Array(events.suffix(5))
    }
    
    private var latestEvent: ThinkingEvent? {
        events.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header - always visible, tappable to expand
            Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    // Animated thinking indicator
                    ThinkingPulse()
                    
                    Text("Thinking")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DSColors.secondaryText)
                    
                    // Show latest step inline when collapsed
                    if !isExpanded, let latest = latestEvent {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(DSColors.secondaryText.opacity(0.6))
                        Text(latest.title)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(DSColors.secondaryText.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DSColors.secondaryText.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DSColors.surface.opacity(0.8))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Expanded detail view
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recentEvents) { event in
                        CompactThinkingRow(event: event)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(DSColors.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 4)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: recentEvents)
    }
}

// Animated pulsing dot to indicate active thinking
private struct ThinkingPulse: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(DSColors.accent)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// Ultra-compact row for expanded view
private struct CompactThinkingRow: View {
    let event: ThinkingEvent

    private var tint: Color {
        switch event.kind {
        case .planning: return DSColors.secondaryText
        case .embedding: return .purple
        case .retrieval: return .green
        case .rerank: return .blue
        case .gating: return .teal
        case .context: return DSColors.accent
        case .generation: return .orange
        case .fallback: return .pink
        case .warning: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 4, height: 4)
            
            Text(event.title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(DSColors.primaryText)
            
            if let detail = event.detail, !detail.isEmpty {
                Text("–")
                    .font(.system(size: 9))
                    .foregroundStyle(DSColors.secondaryText.opacity(0.6))
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DSColors.secondaryText.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

#Preview("Collapsed") {
    let sample: [ThinkingEvent] = [
        ThinkingEvent(kind: .planning, title: "Scoping query", detail: "Top 3 • Research"),
        ThinkingEvent(kind: .embedding, title: "Embedding", detail: "32ms"),
        ThinkingEvent(kind: .retrieval, title: "Searching", detail: "6 chunks"),
    ]
    return ThinkingStreamView(events: sample)
        .padding()
        .background(DSColors.background)
}

#Preview("Expanded") {
    let sample: [ThinkingEvent] = [
        ThinkingEvent(kind: .planning, title: "Scoping query", detail: "Top 3 • Research Library"),
        ThinkingEvent(kind: .embedding, title: "Embedding ready", detail: "1024D in 32 ms"),
        ThinkingEvent(kind: .retrieval, title: "Hybrid retrieval", detail: "6 candidates • Roadmap.pdf"),
        ThinkingEvent(kind: .gating, title: "Confidence gate", detail: "min 0.52 • top 0.67"),
        ThinkingEvent(kind: .generation, title: "Answer composed", detail: "428 tokens in 2.1s")
    ]
    return VStack {
        ThinkingStreamView(events: sample)
    }
    .padding()
    .background(DSColors.background)
}

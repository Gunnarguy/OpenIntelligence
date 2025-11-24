import SwiftUI

struct ThinkingStreamView: View {
    let events: [ThinkingEvent]

    private var recentEvents: [ThinkingEvent] {
        Array(events.suffix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundStyle(DSColors.accent)
                Text("Thinking trail")
                    .font(DSTypography.meta)
                    .foregroundStyle(DSColors.secondaryText)
            }
            .padding(.bottom, DSSpacing.xxs)

            ForEach(recentEvents) { event in
                ThinkingEventRow(event: event)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: recentEvents)
    }
}

private struct ThinkingEventRow: View {
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
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: event.kind.systemIconName)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(DSTypography.meta)
                    .foregroundStyle(DSColors.primaryText)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
            Spacer(minLength: DSSpacing.sm)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DSSpacing.xs)
        .background(DSColors.surfaceElevated.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

#Preview {
    let sample: [ThinkingEvent] = [
        ThinkingEvent(kind: .planning, title: "Scoping query", detail: "Top 3 • Research Library"),
        ThinkingEvent(kind: .embedding, title: "Embedding ready", detail: "1024D in 32 ms"),
        ThinkingEvent(kind: .retrieval, title: "Hybrid retrieval", detail: "6 candidates • Roadmap.pdf"),
        ThinkingEvent(kind: .gating, title: "Confidence gate", detail: "min 0.52 • top 0.67"),
        ThinkingEvent(kind: .generation, title: "Answer composed", detail: "428 tokens in 2.1s")
    ]
    return ThinkingStreamView(events: sample)
        .padding()
        .background(DSColors.background)
}

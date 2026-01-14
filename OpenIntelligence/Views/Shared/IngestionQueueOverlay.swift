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
        case .loading, .transcribing, .extracting, .chunking, .analyzing, .embedding, .storing: return 0
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

    var body: some View {
        guard !items.isEmpty else { return AnyView(EmptyView()) }

        let visibleItems = Array(sortedItems.prefix(5))
        let hiddenCount = max(0, items.count - visibleItems.count)

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                headerView

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

    private var stageIcon: String {
        switch item.stage {
        case .queued: return "clock"
        case .loading: return "arrow.down.circle"
        case .transcribing: return "waveform"
        case .extracting: return "doc.text.magnifyingglass"
        case .chunking: return "square.split.2x2"
        case .analyzing: return "brain"
        case .embedding: return "brain.head.profile"
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

        return HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(stepColor(for: index, activeIndex: activeIndex))
                    .frame(height: 4)
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

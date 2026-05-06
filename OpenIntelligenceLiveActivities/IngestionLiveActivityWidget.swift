import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct IngestionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IngestionLiveActivityAttributes.self) { context in
            IngestionLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(lockScreenTint(for: context.state.processingMode))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(OpenIntelligenceDeepLink.ingestionQueueURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedHeader(context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    expandedStats(context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    expandedQueue(context)
                }
            } compactLeading: {
                compactLeading(context)
            } compactTrailing: {
                compactTrailing(context)
            } minimal: {
                minimalView(context)
            }
            .contentMargins(.all, 16, for: .expanded)
            .contentMargins(.trailing, 10, for: .expanded)
            .keylineTint(keylineTint(for: context.state.processingMode))
        }
        .supplementalActivityFamilies([.small, .medium])
    }

    private func lockScreenTint(for mode: IngestionLiveActivityProcessingMode) -> Color {
        switch mode {
        case .eco: return Color.green.opacity(0.22)
        case .balanced: return Color.cyan.opacity(0.24)
        case .turbo: return Color.orange.opacity(0.24)
        }
    }

    private func keylineTint(for mode: IngestionLiveActivityProcessingMode) -> Color {
        switch mode {
        case .eco: return .green
        case .balanced: return .cyan
        case .turbo: return .orange
        }
    }

    private func expandedHeader(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Import Queue", systemImage: "tray.and.arrow.down.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(context.attributes.containerName)
                .font(.headline)
                .lineLimit(1)

            Text(context.state.currentFilename)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .accessibilityLabel("Current document \(context.state.currentFilename)")
        }
    }

    private func expandedStats(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(context.state.currentStage)
                .font(.headline)

            Text("\(context.state.processedCount)/\(context.state.totalCount)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())

            Text(context.state.deviceSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func expandedQueue(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: context.state.progress, total: 1.0)
                .tint(keylineTint(for: context.state.processingMode))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.performanceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if context.state.thermalBucket == .serious || context.state.thermalBucket == .critical {
                        Label("Thermal state: \(context.state.thermalBucket.displayName)", systemImage: "thermometer.medium")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((context.state.progress * 100).rounded()))%")
                        .font(.headline.monospacedDigit())
                    Text("\(context.state.activeCount) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !context.state.remainingDocuments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Queue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(context.state.remainingDocuments, id: \.self) { title in
                        Text("• \(title)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func compactLeading(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        ZStack {
            Circle()
                .fill(keylineTint(for: context.state.processingMode).opacity(0.18))
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(keylineTint(for: context.state.processingMode))
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("Document ingestion in progress")
    }

    private func compactTrailing(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Int((context.state.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text("\(context.state.activeCount)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(Int((context.state.progress * 100).rounded())) percent complete with \(context.state.activeCount) active documents")
    }

    private func minimalView(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        ZStack {
            Circle()
                .fill(keylineTint(for: context.state.processingMode).opacity(0.18))
            Text("\(max(1, context.state.activeCount))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .accessibilityLabel("\(context.state.activeCount) active document imports")
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct IngestionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<IngestionLiveActivityAttributes>

    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isActivityFullscreen) private var isActivityFullscreen
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var tint: Color {
        switch context.state.processingMode {
        case .eco: return .green
        case .balanced: return .cyan
        case .turbo: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isActivityFullscreen ? 14 : 10) {
            ViewThatFits(in: .horizontal) {
                horizontalHeader
                stackedHeader
            }

            ProgressView(value: context.state.progress, total: 1.0)
                .tint(tint)

            ViewThatFits(in: .horizontal) {
                horizontalStatus
                stackedStatus
            }

            if !context.state.remainingDocuments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(context.state.remainingDocuments, id: \.self) { document in
                        Text("• \(document)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            if context.state.thermalBucket == .serious || context.state.thermalBucket == .critical {
                Label("Thermal management active", systemImage: "thermometer.medium")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, isActivityFullscreen ? 8 : 0)
    }

    private var horizontalHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.containerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(context.state.currentFilename)
                    .font(isActivityFullscreen ? .title3.weight(.semibold) : .headline)
                    .lineLimit(isActivityFullscreen ? 2 : 1)
            }

            Spacer(minLength: 12)

            headerMeta
        }
    }

    private var stackedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.containerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(context.state.currentFilename)
                    .font(isActivityFullscreen ? .title3.weight(.semibold) : .headline)
                    .lineLimit(2)
            }

            headerMeta
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerMeta: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(context.state.currentStage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(isLuminanceReduced ? 0.16 : 0.22), in: Capsule())

            Text("\(context.state.processedCount) of \(context.state.totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var horizontalStatus: some View {
        HStack(alignment: .top) {
            statusCopy

            Spacer(minLength: 12)

            progressPercent
        }
    }

    private var stackedStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusCopy

            progressPercent
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var statusCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.state.performanceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(context.state.deviceSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var progressPercent: some View {
        Text("\(Int((context.state.progress * 100).rounded()))%")
            .font(.system(isActivityFullscreen ? .title2 : .title3, design: .rounded).weight(.bold))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

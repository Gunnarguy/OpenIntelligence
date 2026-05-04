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
            Text("\(liveActivityProgressPercent(context))%")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(context.state.currentStage)
                .font(.caption.weight(.semibold))

            Text(liveActivityQueueSummary(context))
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
                    Text(liveActivityQueueSummary(context))
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
                    Text("\(liveActivityProgressPercent(context))%")
                        .font(.headline.monospacedDigit())
                    Text(liveActivityCompactStageLabel(context.state.currentStage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func compactLeading(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        LiveActivityAppIconView(
            tint: keylineTint(for: context.state.processingMode),
            size: 24,
            cornerRadius: 6
        )
        .accessibilityLabel("Document ingestion in progress")
    }

    private func compactTrailing(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(liveActivityProgressPercent(context))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(liveActivityCompactStageLabel(context.state.currentStage))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel("\(liveActivityProgressPercent(context)) percent complete during \(context.state.currentStage)")
    }

    private func minimalView(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> some View {
        LiveActivityAppIconView(
            tint: keylineTint(for: context.state.processingMode),
            size: 28,
            cornerRadius: 8
        )
        .accessibilityLabel("\(context.state.currentStage) in progress")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                LiveActivityAppIconView(tint: tint, size: isActivityFullscreen ? 42 : 34, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.containerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(context.state.currentFilename)
                        .font(isActivityFullscreen ? .title3.weight(.semibold) : .headline)
                        .lineLimit(isActivityFullscreen ? 2 : 1)

                    Text(context.state.currentStage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(liveActivityProgressPercent(context))%")
                        .font(.system(isActivityFullscreen ? .title2 : .title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(lockScreenProgressSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            ProgressView(value: context.state.progress, total: 1.0)
                .tint(tint)

            Text(lockScreenStatusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if context.state.thermalBucket == .serious || context.state.thermalBucket == .critical {
                Label("Thermal management active", systemImage: "thermometer.medium")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, isActivityFullscreen ? 6 : 0)
    }

    private var lockScreenProgressSummary: String {
        if context.state.totalCount == 1 {
            return "1 document"
        }
        return "\(context.state.processedCount) of \(context.state.totalCount) complete"
    }

    private var lockScreenStatusLine: String {
        if !context.state.remainingDocuments.isEmpty {
            return "\(liveActivityQueueSummary(context)) • Next: \(context.state.remainingDocuments[0])"
        }
        return liveActivityQueueSummary(context)
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct LiveActivityAppIconView: View {
    let tint: Color
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.16))

            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)

            Image("OpenIntelligenceActivityIcon")
                .resizable()
                .scaledToFill()
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

@available(iOSApplicationExtension 17.0, *)
private func liveActivityProgressPercent(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> Int {
    Int((context.state.progress * 100).rounded())
}

@available(iOSApplicationExtension 17.0, *)
private func liveActivityCompactStageLabel(_ stage: String) -> String {
    switch stage.lowercased() {
    case "loading": return "Load"
    case "transcribing": return "Audio"
    case "extracting": return "Text"
    case "chunking": return "Chunk"
    case "analyzing": return "Analyze"
    case "adapting": return "Tune"
    case "re-indexing": return "Reindex"
    case "embedding": return "Embed"
    case "indexing": return "Index"
    case "storing": return "Store"
    case "complete": return "Done"
    case "failed": return "Issue"
    default: return stage
    }
}

@available(iOSApplicationExtension 17.0, *)
private func liveActivityQueueSummary(_ context: ActivityViewContext<IngestionLiveActivityAttributes>) -> String {
    let queuedCount = max(0, context.state.totalCount - context.state.processedCount - context.state.activeCount)
    var parts: [String] = []

    if context.state.activeCount > 0 {
        parts.append("\(context.state.activeCount) active")
    }
    if queuedCount > 0 {
        parts.append("\(queuedCount) queued")
    }
    if context.state.processedCount > 0 {
        parts.append("\(context.state.processedCount) complete")
    }

    if parts.isEmpty {
        return liveActivityCompactStageLabel(context.state.currentStage)
    }

    return parts.joined(separator: " • ")
}

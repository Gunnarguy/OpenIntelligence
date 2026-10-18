import ActivityKit
import AppIntents
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
            .widgetURL(OpenIntelligenceDeepLink.ingestionQueueURL)
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
        switch activityFamily {
        case .small:
            watchOSCompactView
        default:
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
            .padding(.horizontal, 16)
            .padding(.vertical, isActivityFullscreen ? 12 : 8)
        }
    }

    private var watchOSCompactView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 3.5)
                Circle()
                    .trim(from: 0.0, to: CGFloat(context.state.progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(context.state.currentFilename)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(context.state.currentStage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int((context.state.progress * 100).rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

// MARK: - A long answer (5.7)

/// A question that is still being answered after about ten seconds: Deep Think and Maximum, or a
/// long Standard answer. It shows the step the answer is on and ends when the answer does
/// (`QueryLiveActivityService` in the app). Its views live in this file, which the extension
/// already compiles, so the project file did not change.
@available(iOSApplicationExtension 17.0, *)
struct QueryLiveActivityWidget: Widget {
    private static let chatURL = URL(string: "openintelligence://chat")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QueryLiveActivityAttributes.self) { context in
            QueryLiveActivityLockScreenView(state: context.state, sessionID: context.attributes.sessionID)
                .activityBackgroundTint(Color.purple.opacity(0.22))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.chatURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Answering", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int((context.state.progress * 100).rounded()))%")
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 10) {
                            ProgressView(value: context.state.progress, total: 1.0)
                                .tint(.purple)
                            if context.state.finished != true {
                                // Stops the answer and keeps what is written (5.7).
                                Button(intent: StopLongAnswerIntent(sessionID: context.attributes.sessionID)) {
                                    Label("Stop", systemImage: "stop.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .tint(.purple)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Text("\(Int((context.state.progress * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
            }
            .keylineTint(.purple)
            .widgetURL(Self.chatURL)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct QueryLiveActivityLockScreenView: View {
    let state: QueryLiveActivityAttributes.ContentState
    let sessionID: UUID

    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("OpenIntelligence", systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((state.progress * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(state.title)
                .font(.headline)
                .lineLimit(1)
            Text(state.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 12) {
                ProgressView(value: state.progress, total: 1.0)
                    .tint(.purple)
                // Stops the answer and keeps what is written (5.7). Not in the watch's small
                // layout, which has no room for it.
                if state.finished != true, activityFamily != .small {
                    Button(intent: StopLongAnswerIntent(sessionID: sessionID)) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(.purple)
                }
            }
        }
        .padding()
    }
}

// MARK: - Controls (5.7)

/// Buttons for Control Center, the Lock Screen and the Action button. Each opens one of the app's
/// own links with the system's `OpenURLIntent`, so the action needs no code in this extension and
/// no project change; the app routes the link (`AppLink`) as it routes any other.
@available(iOSApplicationExtension 18.0, *)
struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.openintelligence.control.ask") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "openintelligence://chat")!)) {
                Label("Ask OpenIntelligence", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .displayName("Ask")
        .description("Opens the chat to ask your documents a question.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct AddDocumentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.openintelligence.control.add") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "openintelligence://documents/add")!)) {
                Label("Add Document", systemImage: "doc.badge.plus")
            }
        }
        .displayName("Add Document")
        .description("Opens the file picker to add a document to the open library.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ScanDocumentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.openintelligence.control.scan") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "openintelligence://chat/scan")!)) {
                Label("Scan Document", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Scan Document")
        .description("Opens the document scanner and adds the scan to the open library.")
    }
}

/// Scan a page into the open library from the Lock Screen without unlocking (5.7). It opens OpenIntelligence's own
/// capture extension through `ScanIntoLibraryIntent`, where "Scan Document" above opens the app's scanner after
/// unlocking.
@available(iOSApplicationExtension 18.0, *)
struct ScanIntoLibraryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.openintelligence.control.lockedscan") {
            ControlWidgetButton(action: ScanIntoLibraryIntent()) {
                Label("Scan into Library", systemImage: "camera.viewfinder")
            }
        }
        .displayName("Scan into Library")
        .description("Takes a photo of a page without unlocking. It's added to the library you have open when you open the app.")
    }
}

// MARK: - Home Screen and Lock Screen widget (5.7)

/// Ask, Add Document and Scan Document on the Home Screen and the Lock Screen. Each opens one of the
/// app's own links, as the controls above do, so the widget needs no data from the app and no app
/// group. "Your Library" below shows the document count and the last question, which the app writes
/// to an app group the two share.
@available(iOSApplicationExtension 17.0, *)
struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.openintelligence.widget.quickactions", provider: QuickActionsTimeline()) { _ in
            QuickActionsWidgetView()
        }
        .configurationDisplayName("Ask OpenIntelligence")
        .description("Ask your documents a question, add a document or scan one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

/// One entry that never changes: the widget shows the same three links whatever the app holds.
struct QuickActionsTimeline: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry { QuickActionsEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionsEntry(date: .now)], policy: .never))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct QuickActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private static let ask = URL(string: "openintelligence://chat")!
    private static let add = URL(string: "openintelligence://documents/add")!
    private static let scan = URL(string: "openintelligence://chat/scan")!
    private static let askSymbol = "bubble.left.and.text.bubble.right"

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: Self.askSymbol)
                .font(.title3)
                .widgetURL(Self.ask)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            Label("Ask your documents", systemImage: Self.askSymbol)
                .font(.headline)
                .widgetURL(Self.ask)
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            HStack(spacing: 10) {
                action("Ask", symbol: Self.askSymbol, url: Self.ask)
                action("Add", symbol: "doc.badge.plus", url: Self.add)
                action("Scan", symbol: "doc.viewfinder", url: Self.scan)
            }
            .containerBackground(for: .widget) { Color(.systemBackground) }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: Self.askSymbol)
                    .font(.title2)
                    .foregroundStyle(.purple)
                Spacer(minLength: 0)
                Text("Ask your documents")
                    .font(.headline)
                    .lineLimit(2)
                Text("OpenIntelligence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(Self.ask)
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }

    private func action(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.purple)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - "Your Library" widget (5.7)

/// What the app writes for this widget, read from the app group's container: the fields of the app's
/// `WidgetSnapshot` (OpenIntelligence/App/WidgetSnapshot.swift) that the widget shows. The app keeps the
/// answer to the open library's own, so the widget shows what it finds.
struct LibraryWidgetSnapshot: Codable, Equatable {
    var libraryName: String
    var documentCount: Int
    var question: String?
    var answerPreview: String?
    var answeredAt: Date?

    static let appGroup = "group.Gunndamental.OpenIntelligence"
    static let fileName = "widget_snapshot.json"

    static func read() -> LibraryWidgetSnapshot? {
        guard
            let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent(fileName),
            let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibraryWidgetSnapshot.self, from: data)
    }

    /// What the widget gallery shows before the app has written anything.
    static let example = LibraryWidgetSnapshot(
        libraryName: "Home", documentCount: 12, question: "When is the rent due?",
        answerPreview: "Rent is due on the first of each month, with a grace period of five days.",
        answeredAt: nil)
}

/// "Your Library" (5.7): the open library and its document count on the Home Screen and the Lock
/// Screen, and on the Home Screen the last question in that library with the start of its answer.
/// The answer is marked `privacySensitive`: WidgetKit hides it on a locked device when the person has
/// chosen to hide private widget data (developer.apple.com, "Creating a widget extension", read
/// 2026-10-15). The app redraws the widget when either changes (`WidgetSnapshot.write`). With no app
/// group, or before the app has written anything, it asks to open the app.
///
/// Not in `OpenIntelligenceLiveActivitiesBundle` yet: until the App ID carries the app group, a device
/// build has no container, and the widget could only ask to open the app. It goes into the bundle in
/// the same commit as the App Group entitlement. Seen working in the iOS 27 Simulator with the group
/// on 2026-10-15.
@available(iOSApplicationExtension 17.0, *)
struct LibraryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.openintelligence.widget.library", provider: LibraryTimeline()) { entry in
            LibraryWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Library")
        .description("The library you have open, how many documents it holds, and your last question.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct LibraryEntry: TimelineEntry {
    let date: Date
    let snapshot: LibraryWidgetSnapshot?
}

/// One entry, read when the system asks: the app asks for a redraw whenever it writes a new snapshot.
struct LibraryTimeline: TimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry {
        LibraryEntry(date: .now, snapshot: .example)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        let snapshot = LibraryWidgetSnapshot.read() ?? (context.isPreview ? .example : nil)
        completion(LibraryEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        completion(Timeline(entries: [LibraryEntry(date: .now, snapshot: LibraryWidgetSnapshot.read())], policy: .never))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct LibraryWidgetView: View {
    let entry: LibraryEntry
    @Environment(\.widgetFamily) private var family

    private static let chat = URL(string: "openintelligence://chat")!
    private static let documents = URL(string: "openintelligence://documents")!

    var body: some View {
        content
            .widgetURL(entry.snapshot == nil ? Self.documents : Self.chat)
            .containerBackground(for: .widget) {
                if family == .accessoryRectangular { Color.clear } else { Color(.systemBackground) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(snapshot.libraryName, systemImage: "books.vertical")
                        .font(.headline)
                        .lineLimit(1)
                    Text(Self.count(snapshot.documentCount))
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    library(snapshot)
                        .frame(maxWidth: 110, maxHeight: .infinity, alignment: .topLeading)
                    lastAnswer(snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            default:
                library(snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "books.vertical")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Spacer(minLength: 0)
                Text("Open OpenIntelligence to show your library here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func library(_ snapshot: LibraryWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(.purple)
            Spacer(minLength: 0)
            Text(snapshot.libraryName)
                .font(.headline)
                .lineLimit(2)
            Text(Self.count(snapshot.documentCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private func lastAnswer(_ snapshot: LibraryWidgetSnapshot) -> some View {
        if let answer = snapshot.answerPreview {
            VStack(alignment: .leading, spacing: 4) {
                if let question = snapshot.question {
                    Text(question)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                Text(answer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .privacySensitive()
        } else {
            Text("Your last answer shows here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func count(_ n: Int) -> String {
        n == 1 ? "1 document" : "\(n) documents"
    }
}

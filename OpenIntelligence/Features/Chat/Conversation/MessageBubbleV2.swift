//
//  MessageBubbleV2.swift
//  OpenIntelligence
//
//  Modern message bubble with refined typography, actions, and metrics
//

import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

struct MessageBubbleV2: View {
    @Binding var message: ChatMessage
    let showMetadata: Bool
    let onRegenerate: (() -> Void)?

    /// Called when user wants deeper analysis (re-query with agentic mode)
    let onGoDeeper: (() -> Void)?

    // iOS 26+: Apple Intelligence feedback callbacks
    let onThumbsUp: (() -> Void)?
    let onThumbsDown: (() -> Void)?

    /// Called when user taps Translate on a response
    let onTranslate: ((String) -> Void)?
    /// Called when user taps Illustrate on a response
    let onIllustrate: ((String) -> Void)?

    @State private var showActions = false
    @State private var showDetails = false
    @State private var showFullMetrics = false
    @State private var showReportSheet = false
    @State private var sharePayload: SharePayload? = nil
    @State private var showReasoningTrace = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Supplies the library's index state for the shared trace. Optional on purpose.
    ///
    /// This was an `@EnvironmentObject` for RAGService and it crashed the app on 2026-08-19.
    /// `ChatScreen` takes its `ragService` through `init` as an `@ObservedObject`, so the object is
    /// not in this view tree's environment and never has been. `@EnvironmentObject` traps when the
    /// object is absent rather than returning nil, which turns a missing section into a crash.
    /// Passed explicitly and defaulted to nil so a host that does not supply it simply produces a
    /// trace without a LIBRARY STATE section.
    var libraryStateProvider: ((UUID) async -> String)?

    /// Responsive spacer: compact (iPhone) gets more content width, regular (iPad/Mac) keeps roomy margins
    private var bubbleSpacerMinLength: CGFloat {
        horizontalSizeClass == .compact ? 24 : 60
    }

    init(
        message: Binding<ChatMessage>,
        showMetadata: Bool = true,
        onRegenerate: (() -> Void)? = nil,
        onGoDeeper: (() -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil,
        onTranslate: ((String) -> Void)? = nil,
        onIllustrate: ((String) -> Void)? = nil,
        libraryStateProvider: ((UUID) async -> String)? = nil
    ) {
        _message = message
        self.showMetadata = showMetadata
        self.onRegenerate = onRegenerate
        self.onGoDeeper = onGoDeeper
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.onTranslate = onTranslate
        self.onIllustrate = onIllustrate
        self.libraryStateProvider = libraryStateProvider
    }

    private var isUser: Bool { message.role == .user }

    private var responseRouteBadge: ResponseRouteBadgeDescriptor? {
        guard !isUser, let metadata = message.metadata else { return nil }
        return ResponseRouteBadgeDescriptor(metadata: metadata)
    }

    private var displayedReasoningTrace: [String] {
        if let trace = message.metadata?.reasoningTrace, !trace.isEmpty {
            return trace
        }

        if let thinkingEvents = message.thinkingEvents, !thinkingEvents.isEmpty {
            return thinkingEvents.compactReasoningTrace()
        }

        return []
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // Main bubble with tap-to-reveal actions
            HStack(alignment: .bottom, spacing: 0) {
                if isUser { Spacer(minLength: bubbleSpacerMinLength) }

                VStack(alignment: .leading, spacing: 0) {
                    if !isUser, message.isHidden {
                        hiddenMessageView
                    } else if let structuredAnswer = message.structuredAnswer, !isUser {
                        GroundedAnswerView(
                            answer: structuredAnswer,
                            retrievedChunks: message.retrievedChunks ?? [],
                            modeName: message.metadata?.qualityModeName
                        )
                    } else {
                        // Message content
                        MarkdownText(
                            message.content,
                            font: .system(size: 14, weight: .regular),
                            foregroundColor: isUser ? .white : DSColors.primaryText
                        )

                        // Visual Evidence (if any)
                        if let visualEvidence = message.visualEvidence {
                            VisualEvidenceCard(
                                metadata: visualEvidence.metadata,
                                ocrText: visualEvidence.ocrText
                            )
                            .padding(.vertical, 8)
                        }

                        // Reasoning trace (expandable "show your work" section)
                        if !displayedReasoningTrace.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showReasoningTrace.toggle()
                                    if showReasoningTrace {
                                        DSHaptics.expand()
                                    } else {
                                        DSHaptics.collapse()
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showReasoningTrace ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .medium))
                                    
                                    let modeIcon: String = {
                                        let mode = message.metadata?.qualityModeName?.lowercased() ?? ""
                                        if mode.contains("max") { return "flame.fill" }
                                        if mode.contains("deep") { return "brain.head.profile" }
                                        return "sparkles"
                                    }()
                                    
                                    Image(systemName: modeIcon)
                                        .font(.system(size: 10))
                                    
                                    Text("Reasoning Process")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("(\(displayedReasoningTrace.count) steps)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .foregroundStyle(DSColors.accent)
                            }
                            .buttonStyle(.plain)

                            if showReasoningTrace {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(displayedReasoningTrace.enumerated()), id: \.offset) { idx, step in
                                        ReasoningStepView(
                                            step: step,
                                            index: idx,
                                            modeName: message.metadata?.qualityModeName
                                        )
                                    }
                                }
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isUser: isUser))
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        showActions.toggle()
                        DSHaptics.soft()
                    }
                }

                if !isUser { Spacer(minLength: bubbleSpacerMinLength) }
            }

            // Action bar (appears on tap)
            if showActions {
                MessageActionsBar(
                    message: message,
                    onCopy: {
                        // Already handled in bar
                    },
                    onRegenerate: isUser ? nil : onRegenerate,
                    onShowDetails: message.metadata != nil ? { showDetails = true } : nil,
                    onShare: { shareMessage() },
                    onToggleHidden: (!isUser ? { toggleHidden() } : nil),
                    onReport: (!isUser ? { showReportSheet = true } : nil),
                    onExportTrace: (!isUser ? { exportPipelineTrace() } : nil),
                    onGoDeeper: isUser ? nil : onGoDeeper,
                    onTranslate: (!isUser && onTranslate != nil) ? { onTranslate?(message.content) } : nil,
                    onIllustrate: (!isUser && onIllustrate != nil) ? { onIllustrate?(message.content) } : nil,
                    onThumbsUp: onThumbsUp,
                    onThumbsDown: onThumbsDown
                )
                // User bubbles only show Copy + Share — shrink bar to fit content
                // and let the parent VStack's .trailing alignment push it right.
                // Without this, the ScrollView inside MessageActionsBar stretches
                // full-width, pinning the buttons to the left edge.
                .fixedSize(horizontal: isUser, vertical: false)
                .transition(.scale.combined(with: .opacity))
            }

            // Timestamp and mode indicator - detailed metrics shown in header area
            if showMetadata, !showActions {
                HStack(spacing: 6) {
                    if let descriptor = responseRouteBadge {
                        Button {
                            showDetails = true
                        } label: {
                            ResponseRouteBadge(descriptor: descriptor)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(relativeTime(message.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.6))

                    // Mode indicator for assistant messages
                    if !isUser, let meta = message.metadata {
                        if meta.usedAgenticMode {
                            let isMaximum = meta.qualityModeName == "Maximum"
                            HStack(spacing: 2) {
                                Image(systemName: isMaximum ? "flame.fill" : "brain")
                                    .font(.system(size: 8, weight: .medium))
                                Text(isMaximum ? "Max" : "Deep")
                                    .font(.system(size: 9, weight: .medium))
                            }
.foregroundStyle(isMaximum ? .orange.opacity(0.8) : .purple.opacity(0.7))
                        } else if meta.canGoDeeper {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt")
                                    .font(.system(size: 8, weight: .medium))
                                Text("Standard")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(.blue.opacity(0.6))
                        }

                        // Verification gate inline badge
                        if let decision = meta.gatingDecision {
                            VerificationBadge(gatingDecision: decision)
                        }

                        // Tool call count badge
                        if let toolCalls = meta.toolCallsMade, toolCalls > 0 {
                            MicroToolCallBadge(count: toolCalls)
                        }
                    }
                }
.padding(.horizontal, isUser ? 0 : 4)
            }

            // Detailed metrics accessible via tap on message
            // (Model, speed, sources, quality all shown in header area)

            // Expandable metrics panel (assistant only)
            if !isUser && showFullMetrics, let meta = message.metadata {
                MessageMetadataPanel(
                    metadata: meta,
                    chunks: message.retrievedChunks
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showDetails) {
            if let meta = message.metadata {
                ChatResponseDetailsView(
                    metadata: meta,
                    retrievedChunks: message.retrievedChunks ?? [],
                    structuredAnswer: message.structuredAnswer
                )
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportMessageSheet(
                message: message,
                onSubmit: { reason, notes, shouldHide, includeDebugContext in
                    submitReport(reason: reason, notes: notes, shouldHide: shouldHide, includeDebugContext: includeDebugContext)
                }
            )
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: payload.items)
        }
    }

    @ViewBuilder
    private var hiddenMessageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text("Message hidden")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Tap to view actions")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        }
        .foregroundStyle(DSColors.primaryText)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [DSColors.accent, DSColors.accent.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            DSColors.surface
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func shareMessage() {
        sharePayload = SharePayload(items: [message.content])
    }

    private func exportPipelineTrace() {
        // Read the library state at share time rather than capturing it with the message. The
        // interesting state belongs to the vector store, not to the answer, and a store that was
        // healthy when the question was asked and empty afterwards is exactly the case worth
        // seeing. Async because the chunk count is a real read of the store.
        Task { @MainActor in
            var libraryState: String? = nil
            if let containerId = message.containerId, let libraryStateProvider {
                libraryState = await libraryStateProvider(containerId)
            }

            if let fileURL = PipelineTraceExporter.exportToFile(
                message: message,
                pipelineTrace: message.pipelineTrace ?? [],
                libraryState: libraryState
            ) {
                sharePayload = SharePayload(items: [fileURL])
            } else {
                // Fallback: copy trace text to clipboard
                let traceText = PipelineTraceExporter.buildTrace(
                    message: message,
                    pipelineTrace: message.pipelineTrace ?? [],
                    libraryState: libraryState
                )
                #if canImport(UIKit)
                    UIPasteboard.general.string = traceText
                #endif
                DSHaptics.success()
            }
        }
    }

    private func toggleHidden() {
        message.isHidden.toggle()
        DSHaptics.selection()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            showActions = false
        }
    }

    private func submitReport(
        reason: ReportReason,
        notes: String,
        shouldHide: Bool,
        includeDebugContext: Bool
    ) {
        // Persist minimal local state.
        message.userReportedAt = Date()
        message.userReportReason = reason.rawValue
        message.userReportNotes = notes.isEmpty ? nil : notes
        if shouldHide {
            message.isHidden = true
        }

        // Emit local telemetry (no network transmission).
        TelemetryCenter.emit(
            .system,
            severity: .warning,
            title: "User reported assistant message",
            metadata: [
                "messageId": message.id.uuidString,
                "reason": reason.rawValue,
                "hasNotes": notes.isEmpty ? "false" : "true",
            ]
        )

        // Prepare a shareable payload so the user can send it to support.
        let reportText = ReportMessageSheet.buildReportText(
            message: message,
            reason: reason,
            notes: notes,
            includeDebugContext: includeDebugContext
        )

        #if canImport(UIKit)
            UIPasteboard.general.string = reportText
        #endif

        DSHaptics.success()
        sharePayload = SharePayload(items: [reportText])

        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            showActions = false
        }
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }
}

enum ResponseRouteBadgeKind: Equatable {
    case onDevice
    case privateCloudCompute
    case onDeviceFallback
}

struct ResponseRouteBadgeDescriptor: Equatable {
    let kind: ResponseRouteBadgeKind

    init?(metadata: ResponseMetadata) {
        if let receipt = metadata.executionReceipt {
            if receipt.completedTarget == .onDevice,
               (receipt.intendedTarget == .privateCloudCompute
                || receipt.attempts.contains(where: { $0.target == .privateCloudCompute })) {
                kind = .onDeviceFallback
                return
            }

            switch receipt.completedTarget {
            case .privateCloudCompute:
                kind = .privateCloudCompute
            case .onDevice, .deterministic:
                kind = .onDevice
            case .abstain:
                return nil
            }
            return
        }

        if let route = metadata.executionRoute {
            let path = route.path.lowercased()
            let reason = route.reason.lowercased()
            if path.contains("on-device"), reason.contains("intended"), reason.contains("privatecloudcompute") {
                kind = .onDeviceFallback
            } else if path.contains("private cloud") || path.contains("pcc") {
                kind = .privateCloudCompute
            } else if path.contains("on-device") || path.contains("local") {
                kind = .onDevice
            } else {
                return nil
            }
            return
        }

        let modelName = metadata.modelUsed.lowercased()
        if modelName.contains("private cloud") || modelName.contains("pcc") {
            kind = .privateCloudCompute
        } else if modelName.contains("on-device")
                    || modelName.contains("apple intelligence")
                    || modelName.contains("foundation model") {
            kind = .onDevice
        } else {
            return nil
        }
    }

    var title: String {
        switch kind {
        case .onDevice: return "On-device"
        case .privateCloudCompute: return "PCC"
        case .onDeviceFallback: return "On-device fallback"
        }
    }

    var systemImage: String {
        switch kind {
        case .onDevice: return "iphone.gen3"
        case .privateCloudCompute: return "cloud.fill"
        case .onDeviceFallback: return "arrow.uturn.backward.circle.fill"
        }
    }
}

private struct ResponseRouteBadge: View {
    let descriptor: ResponseRouteBadgeDescriptor

    private var color: Color {
        switch descriptor.kind {
        case .onDevice: return .green
        case .privateCloudCompute: return .blue
        case .onDeviceFallback: return .orange
        }
    }

    var body: some View {
        Label(descriptor.title, systemImage: descriptor.systemImage)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
            .accessibilityLabel("Answer generated by \(descriptor.title)")
            .accessibilityHint("Opens routing details")
    }
}

// MARK: - Bubble Shape

// Custom bubble shape with tail
private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6

        var path = Path()

        if isUser {
            path.addRoundedRect(
                in: CGRect(x: 0, y: 0, width: rect.width - tailSize / 2, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        } else {
            path.addRoundedRect(
                in: CGRect(x: tailSize / 2, y: 0, width: rect.width - tailSize / 2, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        }

        return path
    }
}

// MARK: - Reasoning Step View

/// Displays a single step from the AI's reasoning process
private struct ReasoningStepView: View {
    let step: String
    let index: Int
    let modeName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(stepColor.opacity(0.2))
                    .frame(width: 8, height: 8)
                
                Rectangle()
                    .fill(stepColor.opacity(0.1))
                    .frame(width: 2)
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                let parts = step.components(separatedBy: ": ")
                let label = parts.first ?? "Step \(index + 1)"
                let content = parts.count > 1 ? parts.dropFirst().joined(separator: ": ") : step

                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(stepColor)
                    .textCase(.uppercase)

                Text(content)
                    .font(.system(size: 13))
                    .foregroundStyle(DSColors.primaryText.opacity(0.8))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)
        }
    }

    private var stepColor: Color {
        if let mode = modeName?.lowercased() {
            if mode.contains("max") { return .orange }
            if mode.contains("deep") { return .purple }
        }
        
        switch index {
        case 0: return .blue      // Analyzing
        case 1: return .purple    // Patterns
        default: return .green    // Synthesis/Other
        }
    }
}

// MARK: - Verification Gate Badge

/// Compact inline badge showing verification gate status parsed from gatingDecision string
private struct VerificationBadge: View {
    let gatingDecision: String

    private var status: VerificationStatus {
        VerificationStatus.from(gatingDecision: gatingDecision)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.system(size: 8, weight: .bold))
            Text(status.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(status.color.opacity(0.12))
        )
        .contentShape(Capsule())
    }

    enum VerificationStatus {
        case verified
        case partiallyVerified
        case lowConfidence
        case unverified
        case noSources

        var icon: String {
            switch self {
            case .verified: return "checkmark.shield.fill"
            case .partiallyVerified: return "shield.lefthalf.filled"
            case .lowConfidence: return "exclamationmark.triangle.fill"
            case .unverified: return "xmark.shield.fill"
            case .noSources: return "questionmark.circle"
            }
        }

        var label: String {
            switch self {
            case .verified: return "Verified"
            case .partiallyVerified: return "Partially Verified"
            case .lowConfidence: return "Low Confidence"
            case .unverified: return "Unverified"
            case .noSources: return "No Sources"
            }
        }

        var color: Color {
            switch self {
            case .verified: return .green
            case .partiallyVerified: return .yellow
            case .lowConfidence: return .orange
            case .unverified: return .red
            case .noSources: return .secondary
            }
        }

        static func from(gatingDecision: String) -> VerificationStatus {
            let lower = gatingDecision.lowercased()
            if lower.contains("no_sources") || lower.contains("no_documents") || lower.contains("context_empty") {
                return .noSources
            }
            if lower.contains("verification_gates_failed") || lower.contains("missing_citations") {
                return .unverified
            }
            if lower.contains("low_confidence") || lower.contains("rerank_empty") || lower.contains("mmr_empty") || lower.contains("relevance_gate_failed") {
                return .lowConfidence
            }
            if lower.contains("reliability_fallback") || lower.contains("high_accuracy_blocked") {
                return .partiallyVerified
            }
            return .verified
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubbleV2(message: .constant(ChatMessage(role: .user, content: "What's in my documents about machine learning?")))
        MessageBubbleV2(message: .constant(ChatMessage(role: .assistant, content: "Based on your documents, I found several references to machine learning concepts including neural networks, gradient descent, and backpropagation.")))
    }
    .padding()
    .background(DSColors.background)
}

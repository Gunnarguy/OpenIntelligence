//
//  MessageListV2.swift
//  OpenIntelligence
//
//  Redesigned message list with modern styling and smooth animations
//

import SwiftUI

struct MessageListV2: View {
    @Binding var messages: [ChatMessage]
    @Binding var thinkingEvents: [ThinkingEvent]
    let streamingText: String
    let isStreaming: Bool
    let qualityMode: RAGQualityMode
    let generationStart: Date?
    var onRegenerate: ((ChatMessage) -> Void)?

    /// Called when user taps "Go Deeper" to re-query with agentic mode
    var onGoDeeper: (() -> Void)?

    // iOS 26+: Apple Intelligence feedback callbacks
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?

    /// Called when user taps Translate on a message
    var onTranslate: ((String) -> Void)?
    /// Called when user taps Illustrate on a message
    var onIllustrate: ((String) -> Void)?

    @State private var scrollProxy: ScrollViewProxy?

    private var streamingBubbleIdentity: String {
        let phase = streamingText.isEmpty ? "typing" : "text"
        if streamingText.isEmpty {
            let latestEventID = thinkingEvents.last?.id.uuidString ?? "empty"
            return "streaming-\(phase)-\(latestEventID)"
        }
        return "streaming-\(phase)"
    }

    init(
        messages: Binding<[ChatMessage]>,
        thinkingEvents: Binding<[ThinkingEvent]>,
        streamingText: String,
        isStreaming: Bool,
        qualityMode: RAGQualityMode,
        generationStart: Date? = nil,
        onRegenerate: ((ChatMessage) -> Void)? = nil,
        onGoDeeper: (() -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil,
        onTranslate: ((String) -> Void)? = nil,
        onIllustrate: ((String) -> Void)? = nil
    ) {
        _messages = messages
        _thinkingEvents = thinkingEvents
        self.streamingText = streamingText
        self.isStreaming = isStreaming
        self.qualityMode = qualityMode
        self.generationStart = generationStart
        self.onRegenerate = onRegenerate
        self.onGoDeeper = onGoDeeper
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.onTranslate = onTranslate
        self.onIllustrate = onIllustrate
    }

    var body: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if messages.isEmpty {
                            EmptyStateV2()
                                .id("empty")
                                .padding(.top, 100)
                        } else {
                            ForEach($messages) { $message in
                                let snapshot = $message.wrappedValue
                                MessageBubbleV2(
                                    message: $message,
                                    onRegenerate: snapshot.role == .assistant ? { onRegenerate?(snapshot) } : nil,
                                    onGoDeeper: snapshot.role == .assistant ? onGoDeeper : nil,
                                    onThumbsUp: snapshot.role == .assistant ? onThumbsUp : nil,
                                    onThumbsDown: snapshot.role == .assistant ? onThumbsDown : nil,
                                    onTranslate: snapshot.role == .assistant ? onTranslate : nil,
                                    onIllustrate: snapshot.role == .assistant ? onIllustrate : nil
                                )
                                .id(snapshot.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                            }

                            // Streaming message with live metrics (or placeholder while waiting on first token)
                            if isStreaming {
                                if streamingText.isEmpty {
                                    TypingBubbleV2(
                                        events: thinkingEvents,
                                        mode: qualityMode
                                    )
                                    .id(streamingBubbleIdentity)
                                        .transition(.opacity)
                                } else {
                                    StreamingBubbleV2(
                                        text: streamingText
                                    )
                                    .id(streamingBubbleIdentity)
                                        .transition(.opacity)
                                }
                            }

                            // Bottom anchor
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                                .background(BottomAnchorGeometry())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .coordinateSpace(name: "MessageListV2Scroll")
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    scrollProxy = proxy
                    // Jump to the newest message on first open only, and afterwards only if the
                    // reader was already at the bottom when they left.
                    //
                    // This was unconditional, and `.onAppear` fires on every return to the Chat
                    // tab, so scrolling up to re-read an older answer and glancing at another tab
                    // threw the position away — with a visible jump, because `animated: false`
                    // still routes through a 0.12s `withAnimation`. `isPinnedToBottom` is already
                    // maintained from the bottom-anchor preference for exactly this decision and
                    // was simply not consulted here.
                    //
                    // Streaming auto-follow is untouched: the three `onChange` handlers below do
                    // that work and already gate on `isPinnedToBottom`.
                    if !hasPerformedInitialScroll || isPinnedToBottom {
                        scrollToBottom(proxy: proxy, animated: false)
                        hasPerformedInitialScroll = true
                    }
                }
                .onChange(of: messages.count) { _, _ in
                    guard isPinnedToBottom else { return }
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: streamingText) { _, newText in
                    // Scroll smoothly during streaming - every ~80 chars for smooth following
                    if isStreaming, isPinnedToBottom {
                        // Use character count modulo to throttle without losing smoothness
                        let shouldScroll = newText.count % 80 < 20
                        if shouldScroll {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }
                .onChange(of: thinkingEvents.count) { _, _ in
                    guard isPinnedToBottom, streamingText.isEmpty else { return }
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onPreferenceChange(BottomAnchorYPreferenceKey.self) { bottomMinY in
                    // In the scroll view's coordinate space, the visible region is roughly 0...outerGeo.size.height.
                    // When the bottom anchor drifts below the visible region, the user has scrolled up.
                    let threshold: CGFloat = 80
                    isPinnedToBottom = bottomMinY <= outerGeo.size.height + threshold
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            // Smooth micro-animation for streaming - keeps text visible without jarring
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @State private var hasPerformedInitialScroll = false
    @State private var isPinnedToBottom: Bool = true
}

// Empty state
private struct EmptyStateV2: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Local-First")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(DSColors.accent.opacity(0.12))
                )

            ZStack {
                Circle()
                    .fill(DSColors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(DSColors.accent.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("Grounded chat over your library")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DSColors.primaryText)

                Text("Grounded answers over your files, with strong support for PDFs, modern Office files, text, scans, images, code, and transcriptable media.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Streaming Bubble V2 with Live Metrics

private struct StreamingBubbleV2: View {
    let text: String

    @State private var cursorVisible = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var spacerMinLength: CGFloat {
        horizontalSizeClass == .compact ? 24 : 60
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // Message content with cursor
                HStack(alignment: .bottom, spacing: 2) {
                    // Plain `Text` while the answer is still arriving, markdown once it stops.
                    //
                    // This view is handed the whole accumulated `streamingText` on every pump
                    // tick, and `MarkdownText.body` calls `MarkdownParser.parse` as its first
                    // statement — 14 whole-string ICU substitutions, roughly two regex
                    // evaluations per line, and an `AttributedString(markdown:)` per paragraph.
                    // The pump runs at 80ms and tightens to 20ms under backlog, so that is
                    // 12.5-50Hz of O(length) parsing on the main actor, during the one
                    // interaction the user watches most closely, and every intermediate result
                    // is discarded a few milliseconds later.
                    //
                    // No functionality is lost: the identical `MarkdownText` renders the moment
                    // the stream closes and the message becomes a normal history row, so the
                    // final answer is formatted exactly as before. What changes is that partial
                    // markdown is no longer rendered mid-stream — which also removes the flicker
                    // of half-open ** and ``` sequences resolving as tokens arrive.
                    //
                    // The per-parse cost is unmeasured; the log this came from carries no
                    // timings. Confirm with the SwiftUI instrument's Long View Body Updates lane
                    // on a Release device build before assuming a magnitude.
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(DSColors.primaryText)
                        .textSelection(.enabled)

                    // Blinking cursor
                    Rectangle()
                        .fill(DSColors.accent)
                        .frame(width: 2, height: 16)
                        .opacity(cursorVisible ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

            Spacer(minLength: spacerMinLength)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }
}

// MARK: - Typing Placeholder

private struct TypingBubbleV2: View {
    let events: [ThinkingEvent]
    let mode: RAGQualityMode

    @State private var pulse = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var latestEvent: ThinkingEvent? {
        events.last
    }

    private var modeColor: Color {
        switch mode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return DSColors.accent
        }
    }

    private var progress: Double {
        guard let latest = latestEvent else { return 0.05 }
        switch latest.kind {
        case .planning: return 0.1
        case .embedding: return 0.2
        case .queryRewrite: return 0.3
        case .retrieval, .vectorSearch, .bm25: return 0.5
        case .rerank, .rrf, .mmr: return 0.7
        case .gating, .grounding, .verification: return 0.85
        case .context: return 0.9
        case .generation: return 0.95
        default: return 0.5
        }
    }

    private var spacerMinLength: CGFloat {
        horizontalSizeClass == .compact ? 24 : 60
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Stage + Progress
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(modeColor.opacity(0.1), lineWidth: 1.5)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(modeColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        if let latest = latestEvent {
                            Image(systemName: latest.kind.systemIconName)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(modeColor)
                                .transition(.scale.combined(with: .opacity))
                                .id("icon-\(latest.id)")
                        } else {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.5)
                        }
                    }
                    .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(latestEvent?.title ?? "Initializing \(mode.displayName)...")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DSColors.primaryText)

                        Text(mode.displayName.uppercased())
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(modeColor.opacity(0.8))
                            .tracking(0.5)
                    }
                }

                // Live Pipeline Activity (The "Streaming Console" energy)
                if !events.isEmpty {
                    LivePipelinePreview(events: events, tint: modeColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    DSColors.surface

                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, modeColor.opacity(0.05), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: pulse ? geo.size.width : -geo.size.width)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: events.count)

            Spacer(minLength: spacerMinLength)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse.toggle()
            }
        }
    }
}

private struct LivePipelinePreview: View {
    let events: [ThinkingEvent]
    let tint: Color

    private var recentEvents: [ThinkingEvent] {
        Array(events.suffix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(recentEvents.enumerated()), id: \.element.id) { index, event in
                let isLatest = index == recentEvents.count - 1

                HStack(alignment: .top, spacing: 8) {
                    Text(event.kind.displayName.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(isLatest ? tint : tint.opacity(0.75))
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        // Titles are short and generated by us, so one line is enough.
                        // Details are not: they carry retrieved snippets and model
                        // reasoning, and at one line they cut mid-word
                        // ("[Document Analysis Results] — Document […"), hiding the
                        // part that says what the step actually did.
                        Text(event.title)
                            .font(.system(size: 11, weight: isLatest ? .semibold : .medium))
                            .foregroundStyle(DSColors.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        if let detail = event.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(DSColors.secondaryText)
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .opacity(isLatest ? 1 : 0.78)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Bottom Anchor Visibility

private struct BottomAnchorYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BottomAnchorGeometry: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: BottomAnchorYPreferenceKey.self,
                    value: geo.frame(in: .named("MessageListV2Scroll")).minY
                )
        }
    }
}

#Preview {
    let messages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What's machine learning?"),
        ChatMessage(role: .assistant, content: "Machine learning is a branch of artificial intelligence that enables computers to learn from data and improve their performance over time without being explicitly programmed."),
    ]
    return MessageListV2(
        messages: .constant(messages),
        thinkingEvents: .constant([]),
        streamingText: "This is a streaming response that shows live metrics while generating...",
        isStreaming: true,
        qualityMode: .standard,
        generationStart: Date().addingTimeInterval(-2)
    )
    .background(DSColors.background)
}

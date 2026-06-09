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
                                    .id("streaming")
                                        .transition(.opacity)
                                } else {
                                    StreamingBubbleV2(
                                        text: streamingText,
                                        events: thinkingEvents,
                                        mode: qualityMode,
                                        startTime: generationStart
                                    )
                                    .id("streaming")
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
                    scrollToBottom(proxy: proxy, animated: false)
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
    let events: [ThinkingEvent]
    let mode: RAGQualityMode
    let startTime: Date?

    @State private var cursorVisible = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var latestEvent: ThinkingEvent? {
        events.last
    }

    private var spacerMinLength: CGFloat {
        horizontalSizeClass == .compact ? 24 : 60
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Latest thinking event if any (e.g. tool call during generation)
                    if let latest = latestEvent, latest.kind != .generation {
                        HStack(spacing: 8) {
                            Image(systemName: latest.kind.systemIconName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DSColors.accent)
                            
                            Text(latest.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DSColors.accent.opacity(0.08))
                        .cornerRadius(6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    if let start = startTime {
                        TimelineView(.periodic(from: .now, by: 0.1)) { context in
                            let elapsed = context.date.timeIntervalSince(start)
                            Text(String(format: "%.1fs", elapsed))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(DSColors.secondaryText.opacity(0.5))
                        }
                    }
                }

                // Inline thinking console for agentic modes
                if !events.isEmpty {
                    ThinkingStreamView(events: events)
                        .padding(.vertical, 4)
                }

                // Message content with cursor
                HStack(alignment: .bottom, spacing: 2) {
                    MarkdownText(
                        text,
                        font: .system(size: 15),
                        foregroundColor: DSColors.primaryText
                    )

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
                    ThinkingStreamView(events: events)
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

//
//  MessageListV2.swift
//  OpenIntelligence
//
//  Redesigned message list with modern styling and smooth animations
//

import SwiftUI

struct MessageListV2: View {
    @Binding var messages: [ChatMessage]
    let streamingText: String
    let isStreaming: Bool
    let generationStart: Date?
    var onRegenerate: ((ChatMessage) -> Void)?

    // iOS 26+: Apple Intelligence feedback callbacks
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?

    @State private var scrollProxy: ScrollViewProxy?

    init(
        messages: Binding<[ChatMessage]>,
        streamingText: String,
        isStreaming: Bool,
        generationStart: Date? = nil,
        onRegenerate: ((ChatMessage) -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil
    ) {
        _messages = messages
        self.streamingText = streamingText
        self.isStreaming = isStreaming
        self.generationStart = generationStart
        self.onRegenerate = onRegenerate
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
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
                                    onThumbsUp: snapshot.role == .assistant ? onThumbsUp : nil,
                                    onThumbsDown: snapshot.role == .assistant ? onThumbsDown : nil
                                )
                                .id(snapshot.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                            }

                            // Streaming message with live metrics
                            if isStreaming, !streamingText.isEmpty {
                                StreamingBubbleV2(
                                    text: streamingText
                                )
                                .id("streaming")
                                    .transition(.opacity)
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
            ZStack {
                Circle()
                    .fill(DSColors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(DSColors.accent.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DSColors.primaryText)

                Text("Ask questions about your documents\nor chat with AI")
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
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
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
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
        streamingText: "This is a streaming response that shows live metrics while generating...",
        isStreaming: true,
        generationStart: Date().addingTimeInterval(-2)
    )
    .background(DSColors.background)
}

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
                        if isStreaming && !streamingText.isEmpty {
                            StreamingBubbleV2(
                                text: streamingText,
                                generationStart: generationStart
                            )
                            .id("streaming")
                            .transition(.opacity)
                        }

                        // Bottom anchor
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: streamingText) { _, _ in
                if isStreaming {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
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
    let generationStart: Date?

    @State private var cursorVisible = true
    @State private var speedHistory: [Double] = []
    @State private var lastTokenCount: Int = 0
    @State private var lastSpeedUpdate: Date = .init()

    private var tokensApprox: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var elapsedTime: TimeInterval {
        guard let start = generationStart else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private var tokensPerSecond: Double {
        guard elapsedTime > 0.1 else { return 0 }
        return Double(tokensApprox) / elapsedTime
    }

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

                // Live streaming metrics bar
                LiveStreamingMetrics(
                    tokensApprox: tokensApprox,
                    tokensPerSecond: tokensPerSecond,
                    characterCount: text.count,
                    elapsedTime: elapsedTime,
                    speedHistory: speedHistory
                )
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
        .onChange(of: tokensApprox) { _, newCount in
            // Update speed history every ~10 tokens
            if newCount - lastTokenCount >= 5 {
                let now = Date()
                let interval = now.timeIntervalSince(lastSpeedUpdate)
                if interval > 0.1 {
                    let recentSpeed = Double(newCount - lastTokenCount) / interval
                    speedHistory.append(recentSpeed)
                    // Keep last 20 samples
                    if speedHistory.count > 20 {
                        speedHistory.removeFirst()
                    }
                    lastTokenCount = newCount
                    lastSpeedUpdate = now
                }
            }
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

//
//  MessageList.swift
//  OpenIntelligence
//
//  ChatV2 message list + row/bubble primitives (scaffold)
//  Created by Cline on 10/28/25.
//

import SwiftUI

// MARK: - Message List (scaffold)

struct MessageListView: View {
    @Binding var messages: [ChatMessage]
    @State private var shouldAutoScroll = true
    @State private var showScrollToBottom = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.lg) {
                        if messages.isEmpty {
                            EmptyListPlaceholder()
                                .id("empty")
                        } else {
                            ForEach(messages.indices, id: \.self) { index in
                                let message = messages[index]
                                let isNewDay = index == 0 || !Calendar.current.isDate(messages[index - 1].timestamp, inSameDayAs: message.timestamp)
                                if isNewDay {
                                    DayDivider(date: message.timestamp)
                                }
                                MessageRowView(message: message)
                                    .id(message.id)
                            }
                            // Anchor to bottom
                            Color.clear.frame(height: 1).id("bottom-anchor")
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.md)
                }
                .onChange(of: messages.count) { _, _ in
                    if shouldAutoScroll {
                        withAnimation(DSAnimations.fastEase) {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll once on appear if there are messages
                    if !messages.isEmpty {
                        DispatchQueue.main.async {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }
                }
                // TODO: In a subsequent pass, wire a scroll offset preference to toggle this intelligently.
                .onTapGesture {
                    // Dismiss keyboard in parent if needed; leave as noop for now
                }

                if showScrollToBottom {
                    ScrollToBottomButton {
                        withAnimation(DSAnimations.fastEase) {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                        shouldAutoScroll = true
                        showScrollToBottom = false
                    }
                    .padding(.trailing, DSSpacing.md)
                    .padding(.bottom, DSSpacing.md)
                }
            }
        }
    }

    private func isNewDayBoundary(prev: Date?, current: Date) -> Bool {
        guard let prev else { return true }
        return !Calendar.current.isDate(prev, inSameDayAs: current)
    }
}

// MARK: - Row

struct MessageRowView: View {
    let message: ChatMessage
    @State private var showDetails = false

    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            if message.role == .user { Spacer(minLength: 48) }

            if message.role == .assistant {
                AvatarView(kind: .assistant)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: DSSpacing.xs) {
                MessageBubbleView(message: message)

                // Meta row (timestamp; execution badge hook in later pass)
                MessageMetaView(date: message.timestamp, metadata: message.metadata)

                // Sources chips (assistant only)
                if message.role == .assistant, let chunks = message.retrievedChunks, !chunks.isEmpty {
                    SourceChipsView(chunks: chunks) {
                        showDetails = true
                    }
                }
            }
            .sheet(isPresented: $showDetails) {
                if let meta = message.metadata {
                    ChatResponseDetailsView(
                        metadata: meta,
                        retrievedChunks: message.retrievedChunks ?? []
                    )
                } else {
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text("Retrieved Sources")
                            .font(DSTypography.title)
                        Text("Details unavailable for this message.")
                            .font(DSTypography.body)
                            .foregroundColor(DSColors.secondaryText)
                    }
                    .padding()
                }
            }

            if message.role == .user {
                AvatarView(kind: .user)
            } else {
                Spacer(minLength: 48)
            }
        }
    }
}

// MARK: - Bubble

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Render content as markdown with safe fallback
            MarkdownText(message.content, font: DSTypography.body, foregroundColor: message.role == .user ? .white : DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.sm)
        .background(
            BubbleBackground(isUser: message.role == .user)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: DSCorners.bubble, style: .continuous)
        )
        .bubbleShadow()
    }
}

// MARK: - Meta

struct MessageMetaView: View {
    let date: Date
    let metadata: ResponseMetadata?

    private var executionBadge: (emoji: String, label: String)? {
        guard let meta = metadata else { return nil }
        let model = meta.modelUsed
        if model.localizedCaseInsensitiveContains("On-Device") {
            return ("📱", "On‑Device")
        }
        if model.localizedCaseInsensitiveContains("Private Cloud Compute") ||
           model.localizedCaseInsensitiveContains("PCC") {
            return ("☁️", "PCC")
        }
        if model.localizedCaseInsensitiveContains("OpenAI") {
            return ("🔑", "OpenAI")
        }
        if model.localizedCaseInsensitiveContains("MLX") {
            return ("🖥️", "MLX")
        }
        // Fallback: infer from TTFT if available
        if let ttft = meta.timeToFirstToken {
            return ttft < 1.0 ? ("📱", "On‑Device") : ("☁️", "PCC")
        }
        return nil
    }

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundColor(DSColors.secondaryText)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(DSTypography.meta)
                .foregroundColor(DSColors.secondaryText)

            if let badgeTuple: (emoji: String, label: String) = executionBadge {
                let badgeText = "\(badgeTuple.emoji) \(badgeTuple.label)"
                Text(badgeText)
                    .font(DSTypography.meta)
                    .foregroundColor(DSColors.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DSColors.surface)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, DSSpacing.xs)
    }
}

// MARK: - Day Divider

struct DayDivider: View {
    let date: Date

    var body: some View {
        HStack {
            Divider().overlay(Color.gray.opacity(0.3))
            Text(date.formatted(.dateTime.year().month().day()))
                .font(DSTypography.meta)
                .foregroundColor(DSColors.secondaryText)
                .padding(.horizontal, DSSpacing.xs)
                .chipStyle(tint: .secondary)
            Divider().overlay(Color.gray.opacity(0.3))
        }
    }
}

// MARK: - Avatar

enum AvatarKind { case user, assistant }

struct AvatarView: View {
    let kind: AvatarKind
    var body: some View {
        Group {
            switch kind {
            case .assistant:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.white)
                    )
            case .user:
                Circle()
                    .fill(DSColors.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// MARK: - Typing Indicator (scaffold)

struct TypingIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DSColors.accent.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(1.0 + 0.4 * CGFloat(sin(phase + Double(i) * 0.5)))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Skeleton (scaffold)

struct SkeletonMessageRow: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            AvatarView(kind: .assistant)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 160, height: 10)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 220, height: 10)
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - Scroll To Bottom FAB (scaffold)

struct ScrollToBottomButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(DSColors.accent)
                .clipShape(Circle())
                .fabShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to latest message")
    }
}

// MARK: - Empty Placeholder (when no messages yet)

struct EmptyListPlaceholder: View {
    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.18), .blue.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 6) {
                Text("Ready to Chat")
                    .font(.title3).fontWeight(.bold)
                Text("Type a message below to get started.")
                    .font(.subheadline)
                    .foregroundColor(DSColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.lg)
    }
}

// MARK: - Preview

#Preview {
    let sample: [ChatMessage] = [
        ChatMessage(role: .assistant, content: "Hello! How can I help you today?"),
        ChatMessage(role: .user, content: "Show me a markdown example with `code` and a list:\n- one\n- two\n- three"),
        ChatMessage(role: .assistant, content: "Sure! Here's a quick example:\n\n```swift\nprint(\"Hello, world!\")\n```")
    ]
    return NavigationView {
        MessageListView(messages: .constant(sample))
            .navigationTitle("Preview")
    }
    #if os(iOS)
    .navigationViewStyle(.stack)
    #endif
}

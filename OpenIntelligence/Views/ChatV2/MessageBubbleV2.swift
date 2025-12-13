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
    let message: ChatMessage
    let showMetadata: Bool
    let onRegenerate: (() -> Void)?
    
    @State private var showActions = false
    @State private var showDetails = false
    @State private var showFullMetrics = false
    
    init(message: ChatMessage, showMetadata: Bool = true, onRegenerate: (() -> Void)? = nil) {
        self.message = message
        self.showMetadata = showMetadata
        self.onRegenerate = onRegenerate
    }
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // Main bubble with tap-to-reveal actions
            HStack(alignment: .bottom, spacing: 0) {
                if isUser { Spacer(minLength: 60) }
                
                VStack(alignment: .leading, spacing: 0) {
                    // Message content
                    MarkdownText(
                        message.content,
                        font: .system(size: 15, weight: .regular),
                        foregroundColor: isUser ? .white : DSColors.primaryText
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isUser: isUser))
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        showActions.toggle()
                    }
                }
                
                if !isUser { Spacer(minLength: 60) }
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
                    onShare: { shareMessage() }
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            // Metadata row (compact badges)
            if showMetadata && !showActions {
                HStack(spacing: 6) {
                    if !isUser {
                        // Model/execution badge for assistant
                        if let meta = message.metadata {
                            CompactExecutionBadge(
                                modelName: meta.modelUsed,
                                ttft: meta.timeToFirstToken
                            )
                            
                            // Tokens per second badge
                            if let tps = meta.tokensPerSecond, tps > 0 {
                                TokenSpeedBadge(tokensPerSecond: tps)
                            }
                            
                            if let tools = meta.toolCallsMade, tools > 0 {
                                CompactToolBadge(count: tools)
                            }
                        }
                    }
                    
                    // Relative timestamp
                    Text(relativeTime(message.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .padding(.horizontal, isUser ? 0 : 4)
            }
            
            // Source chips with quality indicator
            if !isUser, let chunks = message.retrievedChunks, !chunks.isEmpty {
                HStack(spacing: 6) {
                    CompactSourceChips(chunks: chunks) {
                        showDetails = true
                    }
                    
                    CompactQualityIndicator(chunks: chunks)
                }
            }
            
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
                    retrievedChunks: message.retrievedChunks ?? []
                )
            }
        }
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
            Color(uiColor: .secondarySystemBackground)
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
        #if canImport(UIKit)
        let text = message.content
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }
}

// MARK: - Token Speed Badge

private struct TokenSpeedBadge: View {
    let tokensPerSecond: Float
    
    private var speedInfo: (label: String, color: Color) {
        if tokensPerSecond > 40 { return ("Fast", .green) }
        if tokensPerSecond > 20 { return ("Good", .blue) }
        if tokensPerSecond > 10 { return ("OK", .orange) }
        return ("Slow", .red)
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(String(format: "%.0f", tokensPerSecond))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Text("t/s")
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(speedInfo.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(speedInfo.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// Custom bubble shape with tail
private struct BubbleShape: Shape {
    let isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6
        
        var path = Path()
        
        if isUser {
            path.addRoundedRect(
                in: CGRect(x: 0, y: 0, width: rect.width - tailSize/2, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        } else {
            path.addRoundedRect(
                in: CGRect(x: tailSize/2, y: 0, width: rect.width - tailSize/2, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        }
        
        return path
    }
}

// Compact execution badge
private struct CompactExecutionBadge: View {
    let modelName: String
    let ttft: TimeInterval?
    
    private var info: (icon: String, label: String, color: Color) {
        if modelName.contains("On-Device") || (ttft ?? 1.0) < 0.3 {
            return ("iphone", "Device", .blue)
        } else if modelName.contains("PCC") || modelName.contains("Cloud") || (ttft ?? 0) > 0.5 {
            return ("cloud", "PCC", .green)
        } else if modelName.contains("OpenAI") || modelName.contains("GPT") {
            return ("globe", "Cloud", .orange)
        }
        return ("sparkles", "AI", .purple)
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: info.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(info.label)
                .font(.system(size: 10, weight: .medium))
            if let ttft = ttft {
                Text("•")
                    .font(.system(size: 6))
                    .opacity(0.5)
                Text(formatTTFT(ttft))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
        }
        .foregroundStyle(info.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(info.color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private func formatTTFT(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0fms", t * 1000)
        }
        return String(format: "%.1fs", t)
    }
}

// Compact tool call badge
private struct CompactToolBadge: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 9, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.12))
        .clipShape(Capsule())
    }
}

// Compact source chips
private struct CompactSourceChips: View {
    let chunks: [RetrievedChunk]
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                Text("\(chunks.count) source\(chunks.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(DSColors.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DSColors.accent.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubbleV2(message: ChatMessage(role: .user, content: "What's in my documents about machine learning?"))
        MessageBubbleV2(message: ChatMessage(role: .assistant, content: "Based on your documents, I found several references to machine learning concepts including neural networks, gradient descent, and backpropagation."))
    }
    .padding()
    .background(DSColors.background)
}

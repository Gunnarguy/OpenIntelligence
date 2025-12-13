//
//  MessageActionsBar.swift
//  OpenIntelligence
//
//  Contextual action buttons for chat messages - copy, regenerate, share, details
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Floating action bar that appears on message tap/hover
struct MessageActionsBar: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?
    let onShowDetails: (() -> Void)?
    let onShare: (() -> Void)?
    
    @State private var copiedFeedback = false
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(spacing: 2) {
            // Copy button
            ActionButton(
                icon: copiedFeedback ? "checkmark" : "doc.on.doc",
                label: copiedFeedback ? "Copied" : "Copy",
                color: copiedFeedback ? .green : .secondary
            ) {
                copyToClipboard()
            }
            
            // Regenerate (assistant only)
            if !isUser, let onRegenerate {
                ActionButton(icon: "arrow.clockwise", label: "Retry", color: .orange) {
                    onRegenerate()
                }
            }
            
            // Details (assistant only, if has metadata)
            if !isUser, message.metadata != nil, let onShowDetails {
                ActionButton(icon: "info.circle", label: "Details", color: .blue) {
                    onShowDetails()
                }
            }
            
            // Share
            if let onShare {
                ActionButton(icon: "square.and.arrow.up", label: "Share", color: .purple) {
                    onShare()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = message.content
        #endif
        
        copiedFeedback = true
        DSHaptics.success()
        onCopy()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedFeedback = false
        }
    }
}

/// Individual action button
private struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            DSHaptics.selection()
            action()
        }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(color)
            .frame(width: 50, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionButtonStyle())
    }
}

private struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Expandable per-message metadata panel
struct MessageMetadataPanel: View {
    let metadata: ResponseMetadata
    let chunks: [RetrievedChunk]?
    
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row - always visible
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DSColors.accent)
                    
                    Text("Response Metrics")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DSColors.accent.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if expanded {
                VStack(spacing: 0) {
                    MetricRow(label: "Model", value: metadata.modelUsed, icon: "cpu")
                    Divider().padding(.horizontal, 12)
                    MetricRow(label: "TTFT", value: formatTTFT(metadata.timeToFirstToken), icon: "bolt")
                    Divider().padding(.horizontal, 12)
                    MetricRow(label: "Total Time", value: String(format: "%.2fs", metadata.totalGenerationTime), icon: "clock")
                    Divider().padding(.horizontal, 12)
                    MetricRow(label: "Tokens", value: "\(metadata.tokensGenerated)", icon: "textformat.123")
                    if let tps = metadata.tokensPerSecond {
                        Divider().padding(.horizontal, 12)
                        MetricRow(label: "Speed", value: String(format: "%.1f tok/s", tps), icon: "speedometer")
                    }
                    Divider().padding(.horizontal, 12)
                    MetricRow(label: "Retrieval", value: String(format: "%.0fms", metadata.retrievalTime * 1000), icon: "magnifyingglass")
                    if let chunks = chunks, !chunks.isEmpty {
                        Divider().padding(.horizontal, 12)
                        MetricRow(label: "Sources", value: "\(chunks.count) chunks", icon: "doc.text")
                    }
                    if metadata.strictModeEnabled {
                        Divider().padding(.horizontal, 12)
                        MetricRow(label: "Strict Mode", value: "Enabled", icon: "shield.checkered", valueColor: .orange)
                    }
                    if let tools = metadata.toolCallsMade, tools > 0 {
                        Divider().padding(.horizontal, 12)
                        MetricRow(label: "Tool Calls", value: "\(tools)", icon: "wrench.and.screwdriver")
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func formatTTFT(_ ttft: TimeInterval?) -> String {
        guard let ttft = ttft else { return "—" }
        if ttft < 1.0 {
            return String(format: "%.0fms", ttft * 1000)
        }
        return String(format: "%.2fs", ttft)
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = DSColors.primaryText
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview("Actions Bar") {
    VStack(spacing: 30) {
        MessageActionsBar(
            message: ChatMessage(role: .assistant, content: "This is a test message"),
            onCopy: {},
            onRegenerate: {},
            onShowDetails: {},
            onShare: {}
        )
        
        MessageActionsBar(
            message: ChatMessage(role: .user, content: "User message"),
            onCopy: {},
            onRegenerate: nil,
            onShowDetails: nil,
            onShare: {}
        )
    }
    .padding()
    .background(DSColors.background)
}

#Preview("Metadata Panel") {
    MessageMetadataPanel(
        metadata: ResponseMetadata(
            timeToFirstToken: 0.234,
            totalGenerationTime: 3.45,
            tokensGenerated: 156,
            tokensPerSecond: 45.2,
            modelUsed: "Apple Foundation Model (PCC)",
            retrievalTime: 0.089,
            strictModeEnabled: true,
            toolCallsMade: 2
        ),
        chunks: []
    )
    .padding()
    .background(DSColors.background)
}

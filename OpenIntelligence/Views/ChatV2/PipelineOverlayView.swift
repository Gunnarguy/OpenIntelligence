//
//  PipelineOverlayView.swift
//  OpenIntelligence
//
//  Animated, non-interactive pipeline visualization that runs "behind" chat.
//  Shows flow from Embedding → Searching → Generating with stage pulses and a flowing line.
//

import SwiftUI

struct PipelineOverlayView: View {
    let stage: ChatProcessingStage
    let retrievedCount: Int
    let isGenerating: Bool
    
    // Animation clock
    @State private var flowPhase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Connector path with animated gradient "flow"
                connector(in: geo.size)
                    .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .fill(flowGradient)
                    .mask(
                        connector(in: geo.size)
                            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    )
                    .opacity(0.5)
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: flowPhase)
                
                // Stage nodes
                stageNode(icon: "brain.head.profile",
                          label: "Embedding",
                          active: stage == .embedding || stage == .searching || stage == .generating)
                .position(positions(in: geo.size).embedding)
                
                stageNode(icon: "magnifyingglass",
                          label: "Searching",
                          active: stage == .searching || stage == .generating)
                .position(positions(in: geo.size).searching)
                
                stageNode(icon: "sparkles",
                          label: "Generating",
                          active: stage == .generating)
                .position(positions(in: geo.size).generating)
                
                // Retrieval waterfall indicator near Searching node
                if stage == .searching || stage == .generating {
                    retrievalWaterfall(count: retrievedCount)
                        .position(x: positions(in: geo.size).searching.x,
                                  y: positions(in: geo.size).searching.y + 28)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .onAppear {
                // Kick the flow animation
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    flowPhase = 1
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    // MARK: - Geometry
    
    private func positions(in size: CGSize) -> (embedding: CGPoint, searching: CGPoint, generating: CGPoint) {
        let centerY = size.height * 0.35
        let leftX = size.width * 0.16
        let midX = size.width * 0.5
        let rightX = size.width * 0.84
        return (CGPoint(x: leftX, y: centerY),
                CGPoint(x: midX, y: centerY),
                CGPoint(x: rightX, y: centerY))
    }
    
    private func connector(in size: CGSize) -> Path {
        var path = Path()
        let pos = positions(in: size)
        path.move(to: pos.embedding)
        path.addLine(to: pos.searching)
        path.addLine(to: pos.generating)
        return path
    }
    
    // MARK: - Stages
    
    private func stageNode(icon: String, label: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(active ? DSColors.chipBackground(for: DSColors.accent) : DSColors.surface)
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(active ? DSColors.accent : DSColors.secondaryText)
            }
            Text(label)
                .font(DSTypography.meta)
                .foregroundColor(active ? DSColors.accent : DSColors.secondaryText)
        }
        .scaleEffect(active ? 1.05 : 1.0)
        .animation(DSAnimations.fastEase, value: active)
    }
    
    // MARK: - Retrieval Waterfall
    
    private func retrievalWaterfall(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption2)
                .foregroundColor(.green)
            Text(count > 0 ? "\(count) chunks" : "searching…")
                .font(DSTypography.meta)
                .foregroundColor(DSColors.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DSColors.surface)
        .cornerRadius(DSCorners.chip)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .opacity(0.9)
    }
    
    // MARK: - Flow gradient
    
    private var flowGradient: LinearGradient {
        let colors: [Color] = [
            DSColors.accent.opacity(0.05),
            DSColors.accent.opacity(0.6),
            DSColors.accent.opacity(0.05)
        ]
        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

//
//  LiveStreamingMetrics.swift
//  OpenIntelligence
//
//  Real-time streaming metrics display showing token rate, character count,
//  and a mini sparkline of generation speed over time.
//

import SwiftUI

/// Compact live metrics strip shown during generation
struct LiveStreamingMetrics: View {
    let tokensApprox: Int
    let tokensPerSecond: Double
    let characterCount: Int
    let elapsedTime: TimeInterval
    let speedHistory: [Double]  // Last N tok/s readings for sparkline
    
    var body: some View {
        // Use a flexible flow layout that wraps on smaller widths
        FlowLayout(spacing: 6) {
            // Speed (primary metric)
            CompactMetricPill(
                icon: "bolt.fill",
                value: String(format: "%.1f", tokensPerSecond),
                unit: "t/s",
                color: speedColor
            )
            
            // Sparkline (if we have data)
            if speedHistory.count > 2 {
                MiniSparkline(values: speedHistory, color: speedColor)
                    .frame(width: 36, height: 14)
                    .padding(.horizontal, 4)
            }
            
            // Token count
            CompactMetricPill(
                icon: "number",
                value: "\(tokensApprox)",
                unit: "tok",
                color: .blue
            )
            
            // Character count
            CompactMetricPill(
                icon: "text.alignleft",
                value: formatCount(characterCount),
                unit: "",
                color: .purple
            )
            
            // Elapsed time
            CompactMetricPill(
                icon: "clock",
                value: formatElapsed(elapsedTime),
                unit: "",
                color: .secondary
            )
        }
    }
    
    private var speedColor: Color {
        if tokensPerSecond > 30 { return .green }
        if tokensPerSecond > 15 { return .blue }
        if tokensPerSecond > 5 { return .orange }
        return .red
    }
    
    private func formatCount(_ n: Int) -> String {
        if n > 1000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }
    
    private func formatElapsed(_ t: TimeInterval) -> String {
        if t < 60 {
            return String(format: "%.1fs", t)
        }
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Compact Metric Pill

/// Ultra-compact metric display
private struct CompactMetricPill: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DSColors.primaryText)
            
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Flow Layout

/// A flexible layout that wraps items to new lines when needed
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }
        
        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

/// Mini sparkline chart for speed history
private struct MiniSparkline: View {
    let values: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let maxVal = max(values.max() ?? 1, 1)
            let minVal = max(values.min() ?? 0, 0)
            let range = max(maxVal - minVal, 1)
            
            Path { path in
                guard values.count > 1 else { return }
                
                let stepX = geo.size.width / CGFloat(values.count - 1)
                let points = values.enumerated().map { (i, val) -> CGPoint in
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - (CGFloat((val - minVal) / range) * geo.size.height)
                    return CGPoint(x: x, y: y)
                }
                
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            
            // Current value dot
            if let lastVal = values.last {
                let x = geo.size.width
                let y = geo.size.height - (CGFloat((lastVal - minVal) / range) * geo.size.height)
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LiveStreamingMetrics(
            tokensApprox: 47,
            tokensPerSecond: 23.5,
            characterCount: 312,
            elapsedTime: 2.1,
            speedHistory: [12.0, 18.5, 22.0, 25.3, 23.5]
        )
        
        LiveStreamingMetrics(
            tokensApprox: 156,
            tokensPerSecond: 45.2,
            characterCount: 1024,
            elapsedTime: 3.45,
            speedHistory: [30.0, 35.5, 40.0, 42.3, 45.2]
        )
        
        LiveStreamingMetrics(
            tokensApprox: 8,
            tokensPerSecond: 3.2,
            characterCount: 52,
            elapsedTime: 2.5,
            speedHistory: [2.0, 3.5, 3.0, 3.2]
        )
    }
    .padding()
    .background(DSColors.background)
}

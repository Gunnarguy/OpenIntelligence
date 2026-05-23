//
//  ContextUsageIndicator.swift
//  OpenIntelligence
//
//  Shows context window usage as a visual gauge - how much of the
//  model's context is being utilized by retrieved chunks + history.
//

import SwiftUI

/// Visual gauge showing context window utilization
struct ContextUsageIndicator: View {
    let usedTokens: Int
    let maxTokens: Int
    let retrievedChunksTokens: Int
    let historyTokens: Int
    let systemPromptTokens: Int
    
    private var usageRatio: Double {
        guard maxTokens > 0 else { return 0 }
        return Double(usedTokens) / Double(maxTokens)
    }
    
    private var usageColor: Color {
        if usageRatio > 0.9 { return .red }
        if usageRatio > 0.75 { return .orange }
        if usageRatio > 0.5 { return .yellow }
        return .green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with usage percentage
            HStack {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(usageColor)
                
                Text("Context Window")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                Text("\(usedTokens) / \(formatNumber(maxTokens))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(usageColor)
                
                Text(String(format: "(%.0f%%)", usageRatio * 100))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            
            // Segmented bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    // System prompt segment
                    if systemPromptTokens > 0 {
                        ContextSegment(
                            width: segmentWidth(systemPromptTokens, in: geo.size.width),
                            color: .gray
                        )
                    }
                    
                    // History segment
                    if historyTokens > 0 {
                        ContextSegment(
                            width: segmentWidth(historyTokens, in: geo.size.width),
                            color: .blue
                        )
                    }
                    
                    // Retrieved chunks segment
                    if retrievedChunksTokens > 0 {
                        ContextSegment(
                            width: segmentWidth(retrievedChunksTokens, in: geo.size.width),
                            color: .purple
                        )
                    }
                    
                    // Remaining space
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            
            // Legend
            HStack(spacing: 12) {
                LegendItem(color: .gray, label: "System", tokens: systemPromptTokens)
                LegendItem(color: .blue, label: "History", tokens: historyTokens)
                LegendItem(color: .purple, label: "Context", tokens: retrievedChunksTokens)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DSColors.surfaceElevated)
        )
    }
    
    private func segmentWidth(_ tokens: Int, in totalWidth: CGFloat) -> CGFloat {
        guard maxTokens > 0 else { return 0 }
        return totalWidth * CGFloat(tokens) / CGFloat(maxTokens)
    }
    
    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.0fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }
}

private struct ContextSegment: View {
    let width: CGFloat
    let color: Color
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 2))
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let tokens: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.secondary)
            
            Text("\(tokens)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// Compact inline context indicator
struct CompactContextIndicator: View {
    let usedTokens: Int
    let maxTokens: Int
    
    private var usageRatio: Double {
        guard maxTokens > 0 else { return 0 }
        return Double(usedTokens) / Double(maxTokens)
    }
    
    private var usageColor: Color {
        if usageRatio > 0.9 { return .red }
        if usageRatio > 0.75 { return .orange }
        if usageRatio > 0.5 { return .yellow }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Mini bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(usageColor.opacity(0.2))
                    
                    Capsule()
                        .fill(usageColor)
                        .frame(width: geo.size.width * usageRatio)
                }
            }
            .frame(width: 30, height: 6)
            
            Text(String(format: "%.0f%%", usageRatio * 100))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(usageColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(usageColor.opacity(0.1))
        )
    }
}

/// Circular context gauge
struct CircularContextGauge: View {
    let usedTokens: Int
    let maxTokens: Int
    
    private var usageRatio: Double {
        guard maxTokens > 0 else { return 0 }
        return min(Double(usedTokens) / Double(maxTokens), 1.0)
    }
    
    private var usageColor: Color {
        if usageRatio > 0.9 { return .red }
        if usageRatio > 0.75 { return .orange }
        if usageRatio > 0.5 { return .yellow }
        return .green
    }
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(usageColor.opacity(0.2), lineWidth: 4)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: usageRatio)
                .stroke(usageColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            // Center text
            VStack(spacing: 0) {
                Text(String(format: "%.0f", usageRatio * 100))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(usageColor)
                Text("%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: 44, height: 44)
    }
}

#Preview {
    VStack(spacing: 20) {
        ContextUsageIndicator(
            usedTokens: 1850,
            maxTokens: 4096,
            retrievedChunksTokens: 1200,
            historyTokens: 450,
            systemPromptTokens: 200
        )
        
        ContextUsageIndicator(
            usedTokens: 3800,
            maxTokens: 4096,
            retrievedChunksTokens: 2500,
            historyTokens: 1100,
            systemPromptTokens: 200
        )
        
        HStack(spacing: 16) {
            CompactContextIndicator(usedTokens: 1850, maxTokens: 4096)
            CompactContextIndicator(usedTokens: 3800, maxTokens: 4096)
            CompactContextIndicator(usedTokens: 4000, maxTokens: 4096)
        }
        
        HStack(spacing: 20) {
            CircularContextGauge(usedTokens: 1000, maxTokens: 4096)
            CircularContextGauge(usedTokens: 3000, maxTokens: 4096)
            CircularContextGauge(usedTokens: 3900, maxTokens: 4096)
        }
    }
    .padding()
    .background(DSColors.background)
}

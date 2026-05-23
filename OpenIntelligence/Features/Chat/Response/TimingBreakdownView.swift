//
//  TimingBreakdownView.swift
//  OpenIntelligence
//
//  Detailed timing breakdown showing each pipeline stage with
//  waterfall visualization and percentage contributions.
//

import SwiftUI

/// Full timing breakdown with waterfall chart
struct TimingBreakdownView: View {
    let embedding: TimeInterval?
    let searching: TimeInterval?
    let generating: TimeInterval?
    let total: TimeInterval
    
    @State private var expanded = false
    
    private var stages: [(name: String, duration: TimeInterval, color: Color, icon: String)] {
        var result: [(String, TimeInterval, Color, String)] = []
        if let e = embedding { result.append(("Embedding", e, .purple, "brain.head.profile")) }
        if let s = searching { result.append(("Searching", s, .blue, "magnifyingglass")) }
        if let g = generating { result.append(("Generating", g, DSColors.accent, "sparkles")) }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Mini waterfall bars
                    HStack(spacing: 2) {
                        ForEach(stages, id: \.name) { stage in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(stage.color)
                                .frame(width: barWidth(for: stage.duration), height: 8)
                        }
                    }
                    .frame(width: 60, alignment: .leading)
                    
                    Text(formatDuration(total))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DSColors.primaryText)
                    
                    Text("total")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    
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
                        .fill(DSColors.surfaceElevated)
                )
            }
            .buttonStyle(.plain)
            
            // Expanded breakdown
            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        if index > 0 {
                            Divider().padding(.horizontal, 12)
                        }
                        
                        TimingRow(
                            icon: stage.icon,
                            name: stage.name,
                            duration: stage.duration,
                            percentage: percentage(for: stage.duration),
                            color: stage.color
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DSColors.surface)
                )
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func barWidth(for duration: TimeInterval) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(duration / total) * 60
    }
    
    private func percentage(for duration: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return (duration / total) * 100
    }
    
    private func formatDuration(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0fms", t * 1000)
        }
        return String(format: "%.2fs", t)
    }
}

private struct TimingRow: View {
    let icon: String
    let name: String
    let duration: TimeInterval
    let percentage: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            
            // Name
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DSColors.primaryText)
            
            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(percentage / 100))
                }
            }
            .frame(height: 6)
            
            // Duration
            Text(formatDuration(duration))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 55, alignment: .trailing)
            
            // Percentage
            Text(String(format: "%.0f%%", percentage))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private func formatDuration(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0fms", t * 1000)
        }
        return String(format: "%.2fs", t)
    }
}

/// Inline timing chips (compact alternative)
struct TimingChipsRow: View {
    let embedding: TimeInterval?
    let searching: TimeInterval?
    let generating: TimeInterval?
    
    var body: some View {
        HStack(spacing: 6) {
            if let e = embedding {
                TimingChip(icon: "brain.head.profile", duration: e, color: .purple)
            }
            if let s = searching {
                TimingChip(icon: "magnifyingglass", duration: s, color: .blue)
            }
            if let g = generating {
                TimingChip(icon: "sparkles", duration: g, color: DSColors.accent)
            }
        }
    }
}

private struct TimingChip: View {
    let icon: String
    let duration: TimeInterval
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            
            Text(formatDuration(duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
    
    private func formatDuration(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0fms", t * 1000)
        }
        return String(format: "%.1fs", t)
    }
}

#Preview {
    VStack(spacing: 20) {
        TimingBreakdownView(
            embedding: 0.032,
            searching: 0.145,
            generating: 2.34,
            total: 2.517
        )
        
        TimingChipsRow(
            embedding: 0.032,
            searching: 0.145,
            generating: 2.34
        )
        
        TimingBreakdownView(
            embedding: 0.089,
            searching: 0.234,
            generating: 5.67,
            total: 5.993
        )
    }
    .padding()
    .background(DSColors.background)
}

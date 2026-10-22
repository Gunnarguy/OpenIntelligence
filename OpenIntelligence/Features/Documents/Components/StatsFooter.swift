//
//  StatsFooter.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct StatsFooter: View {
    let totalDocuments: Int
    let totalChunks: Int
    var autoIntelligenceEnabled: Bool = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Side by side, and one under the other at accessibility sizes; in the readable gray, where gray at 80% measured
        // 3.48 to 3.53 to 1 (5.7).
        let countsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DSSpacing.xs)) : AnyLayout(HStackLayout(spacing: DSSpacing.lg))
        return VStack(spacing: DSSpacing.md) {
            countsLayout {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("\(totalDocuments) Documents")
                }
                
                // Drawn, so it is not text that VoiceOver cannot reach, which Apple's element check reports when a "•"
                // is hidden from it (5.7).
                if !dynamicTypeSize.isAccessibilitySize {
                    Circle()
                        .fill(DSColors.secondaryText)
                        .frame(width: 3, height: 3)
                }
                
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "cube.box.fill")
                    Text("\(totalChunks) Chunks")
                }
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(DSColors.secondaryText)

            // Auto Intelligence status indicator
            AutoIntelligenceBadge(isEnabled: autoIntelligenceEnabled)
        }
        .padding(.vertical, DSSpacing.xl)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

/// Compact badge showing Auto Intelligence status
struct AutoIntelligenceBadge: View {
    let isEnabled: Bool

    var body: some View {
        // White on the readable purple and blue, where on the plain ones it measured 3.59 to 1; the label color on the
        // gray tint when it is off (5.7).
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: isEnabled ? "wand.and.stars" : "slider.horizontal.3")
                .font(.caption2.weight(.semibold))
            Text(isEnabled ? "Auto Intelligence Active" : "Manual Pipeline Mode")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isEnabled ? Color.white : DSColors.primaryText)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(
            ZStack {
                if isEnabled {
                    LinearGradient(
                        colors: [DSColors.readable(.accentColor), DSColors.readable(.accentColor)], startPoint: .leading,
                        endPoint: .trailing)
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
        )
        .clipShape(Capsule())
        .shadow(color: isEnabled ? Color.accentColor.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
    }
}

#Preview {
    VStack(spacing: 20) {
        StatsFooter(totalDocuments: 12, totalChunks: 347)
        AutoIntelligenceBadge(isEnabled: true)
        AutoIntelligenceBadge(isEnabled: false)
    }
    .padding()
}

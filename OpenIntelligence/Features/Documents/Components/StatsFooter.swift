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
            ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 16))
        return VStack(spacing: 12) {
            countsLayout {
                HStack(spacing: 4) {
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
                
                HStack(spacing: 4) {
                    Image(systemName: "cube.box.fill")
                    Text("\(totalChunks) Chunks")
                }
            }
            .scaledFont(size: 11, weight: .semibold)
            .foregroundStyle(DSColors.secondaryText)

            // Auto Intelligence status indicator
            AutoIntelligenceBadge(isEnabled: autoIntelligenceEnabled)
        }
        .padding(.vertical, 24)
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
        HStack(spacing: 6) {
            Image(systemName: isEnabled ? "wand.and.stars" : "slider.horizontal.3")
                .scaledFont(size: 10, weight: .bold)
            Text(isEnabled ? "Auto Intelligence Active" : "Manual Pipeline Mode")
                .scaledFont(size: 10, weight: .bold, design: .rounded)
        }
        .foregroundStyle(isEnabled ? Color.white : DSColors.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                if isEnabled {
                    LinearGradient(
                        colors: [DSColors.readable(.purple), DSColors.readable(.blue)], startPoint: .leading,
                        endPoint: .trailing)
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
        )
        .clipShape(Capsule())
        .shadow(color: isEnabled ? .purple.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
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

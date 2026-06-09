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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("\(totalDocuments) Documents")
                }
                
                Text("•")
                    .foregroundColor(.secondary.opacity(0.3))
                
                HStack(spacing: 4) {
                    Image(systemName: "cube.box.fill")
                    Text("\(totalChunks) Chunks")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.8))

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
        HStack(spacing: 6) {
            Image(systemName: isEnabled ? "wand.and.stars" : "slider.horizontal.3")
                .font(.system(size: 10, weight: .bold))
            Text(isEnabled ? "Auto Intelligence Active" : "Manual Pipeline Mode")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(isEnabled ? .white : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                if isEnabled {
                    LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
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

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
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Label("\(totalDocuments) Documents", systemImage: "doc.on.doc")
                Divider()
                    .frame(height: 12)
                Label("\(totalChunks) Chunks", systemImage: "cube.box")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Auto Intelligence status indicator
            AutoIntelligenceBadge(isEnabled: autoIntelligenceEnabled)
        }
        .padding(.vertical, 20)
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
                .font(.caption2)
            Text(isEnabled ? "Auto Intelligence" : "Manual Mode")
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(isEnabled ? .white : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isEnabled
                    ? LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.secondary.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                )
        )
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

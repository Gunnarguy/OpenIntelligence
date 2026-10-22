//
//  FeatureRow.swift
//  OpenIntelligence
//
//  Created by GitHub Copilot on 10/24/25.
//

import SwiftUI

/// Shared row used inside the About screen to highlight key features.
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DSColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }
}

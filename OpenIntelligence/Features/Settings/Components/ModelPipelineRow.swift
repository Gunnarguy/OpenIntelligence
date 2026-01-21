//
//  ModelPipelineRow.swift
//  OpenIntelligence
//
//  Created by GitHub Copilot on 10/24/25.
//

import SwiftUI

/// Visualises a single stage in the model fallback pipeline.
struct ModelPipelineRow: View {
    let stage: ModelPipelineStage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stage.icon)
                    .font(.title3)
                    .foregroundColor(color(for: stage.status))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(stage.name)
                            .font(.headline)
                        roleBadge
                    }

                    Text(stage.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    statusLabel
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var roleBadge: some View {
        Text(stage.role.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stage.role.tint.opacity(0.15))
            .foregroundColor(stage.role.tint)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch stage.status {
        case .active:
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .available:
            Label("Ready", systemImage: "bolt.circle")
                .font(.caption)
                .foregroundColor(.blue)
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        case .requiresConfiguration(let message):
            Label(message, systemImage: "key.fill")
                .font(.caption)
                .foregroundColor(.orange)
        case .disabled:
            Label("Disabled in Settings", systemImage: "slash.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func color(for status: ModelPipelineStage.Status) -> Color {
        switch status {
        case .active:
            return .green
        case .available:
            return .blue
        case .unavailable:
            return .orange
        case .requiresConfiguration:
            return .orange
        case .disabled:
            return .secondary
        }
    }
}

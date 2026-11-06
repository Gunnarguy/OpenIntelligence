//
//  PipelineTimelineView.swift
//  OpenIntelligence
//
//  Moved from VisualizationsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

struct PipelineTimelineView: View {
    @StateObject private var telemetry = TelemetryCenter.shared

    private struct Stage: Identifiable {
        let id: String
        let name: String
        let detail: String
        let icon: String
        let category: TelemetryCategory
    }

    private var stages: [Stage] {
        [
            Stage(id: "ingest", name: "Ingestion", detail: "Parse PDFs and text into raw payloads", icon: "doc.text.fill", category: .ingestion),
            Stage(id: "chunk", name: "Chunking", detail: "Split content into 280-350 word windows (~17% overlap)", icon: "square.split.2x2", category: .ingestion),
            Stage(id: "embed", name: "Embedding", detail: "Map chunks into the 512-dim vector space", icon: "function", category: .embedding),
            Stage(id: "store", name: "Storage", detail: "Persist vectors + BM25 payloads per container", icon: "externaldrive.fill", category: .storage),
            Stage(id: "query", name: "Query", detail: "Embed the question and expand with heuristics", icon: "magnifyingglass", category: .retrieval),
            Stage(id: "retrieve", name: "Retrieval", detail: "Run hybrid search + MMR diversification", icon: "arrow.down.circle.fill", category: .retrieval),
            Stage(id: "assemble", name: "Assembly", detail: "Build grounded context + metadata bundle", icon: "square.stack.3d.up.fill", category: .retrieval),
            Stage(id: "generate", name: "Generation", detail: "Stream the answer with citations + tools", icon: "sparkles", category: .generation),
            Stage(id: "billing", name: "Billing & Entitlements", detail: "StoreKit purchases, restores, and quota updates", icon: "creditcard.fill", category: .billing),
        ]
    }

    private var recentEvents: [TelemetryEvent] {
        Array(telemetry.events.suffix(3).reversed())
    }

    var body: some View {
        DashboardSectionCard(
            icon: "flowchart.fill",
            title: "Pipeline Timeline",
            subtitle: "Track where the current request is spending time"
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(stages) { stage in
                        StageChip(stage: stage, isActive: isStageActive(stage.category), color: color(for: stage.category))
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }

            if !recentEvents.isEmpty {
                Divider()
                    .padding(.vertical, DSSpacing.sm)

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Recent activity")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(recentEvents, id: \.id) { event in
                        ActivityRow(event: event, accent: color(for: event.category))
                    }
                }
            }

            VisualizationInfoSection(title: "Stage reference") {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(stages) { stage in
                        HStack(alignment: .top, spacing: DSSpacing.sm) {
                            Image(systemName: stage.icon)
                                .font(.caption)
                                .foregroundStyle(color(for: stage.category))
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(stage.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(stage.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, DSSpacing.xxs)
                    }
                }
            }
        }
    }

    private func isStageActive(_ category: TelemetryCategory) -> Bool {
        let window = telemetry.events.suffix(12)
        return window.contains { event in
            event.category == category && Date().timeIntervalSince(event.timestamp) < 6
        }
    }

    func color(for category: TelemetryCategory) -> Color {
        switch category {
        case .ingestion: return .orange
        case .embedding: return DSColors.accent
        case .retrieval: return DSColors.accent
        case .generation: return .green
        case .storage: return DSColors.accent
        case .system: return .secondary
        case .billing: return .green
        case .error: return .red
        }
    }

    private struct StageChip: View {
        let stage: Stage
        let isActive: Bool
        let color: Color

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: stage.icon)
                        .font(.subheadline)
                        .foregroundStyle(isActive ? .white : color)
                        .padding(DSSpacing.sm)
                        .background(
                            Circle().fill(isActive ? color : color.opacity(0.12))
                        )

                    Text(stage.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }

                Text(stage.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(DSSpacing.md)
            .frame(width: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(isActive ? color.opacity(0.12) : DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }

    private struct ActivityRow: View {
        let event: TelemetryEvent
        let accent: Color

        var body: some View {
            HStack(spacing: DSSpacing.md) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(event.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let duration = event.duration {
                    Text(String(format: "%.0f ms", duration * 1000))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface)
            )
        }
    }
}

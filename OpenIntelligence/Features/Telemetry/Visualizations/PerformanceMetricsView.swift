//
//  PerformanceMetricsView.swift
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

// MARK: - Performance Metrics View

struct PerformanceMetricsView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject private var telemetry = TelemetryCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text("Performance Metrics")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, DSSpacing.lg)

            // Pipeline stage breakdown
            PipelineStagesCard()
                .padding(.horizontal, DSSpacing.lg)

            // System metrics
            SystemMetricsGrid()
                .padding(.horizontal, DSSpacing.lg)
        }
    }
}

struct PipelineStagesCard: View {
    @ObservedObject private var telemetry = TelemetryCenter.shared

    var stageMetrics: [(stage: String, avgTime: Double, color: Color)] {
        [
            ("Embedding", avgDuration(for: .embedding), DSColors.accent),
            ("Retrieval", avgDuration(for: .retrieval), DSColors.accent),
            ("Generation", avgDuration(for: .generation), .green),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Pipeline Stages")
                .font(.headline)

            ForEach(stageMetrics, id: \.stage) { metric in
                StageMetricRow(
                    stage: metric.stage,
                    avgTime: metric.avgTime,
                    color: metric.color
                )
            }
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func avgDuration(for category: TelemetryCategory) -> Double {
        let events = telemetry.events.filter { $0.category == category }
        guard !events.isEmpty else { return 0 }
        let totalTime = events.compactMap { $0.duration }.reduce(0, +)
        return totalTime / Double(events.count)
    }
}

struct StageMetricRow: View {
    let stage: String
    let avgTime: Double
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(stage)
                .font(.subheadline)

            Spacer()

            Text(String(format: "%.2fs", avgTime))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

struct SystemMetricsGrid: View {
    var body: some View {
        #if canImport(UIKit)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                StatCard(
                    icon: "memorychip",
                    label: "Device",
                    value: UIDevice.current.model,
                    color: DSColors.accent
                )

                StatCard(
                    icon: "cpu",
                    label: "iOS",
                    value: UIDevice.current.systemVersion,
                    color: .green
                )
            }
        #else
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                StatCard(
                    icon: "desktopcomputer",
                    label: "Device",
                    value: "Mac",
                    color: DSColors.accent
                )

                StatCard(
                    icon: "cpu",
                    label: "OS",
                    value: ProcessInfo.processInfo.operatingSystemVersionString,
                    color: .green
                )
            }
        #endif
    }
}

// MARK: - Reusable Components

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)

                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
            }

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

//
//  VisualizationCards.swift
//  OpenIntelligence
//
//  Moved unchanged from AdaptiveVisualizationsView.swift on 2026-11-05 (5.8 split).
//

import Charts
import SceneKit
import SwiftUI
import TipKit

// MARK: - Supporting Views

struct QuickMetric: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

struct InsightCard: View {
    let insight: VisualizationInsight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(insight.color.opacity(0.15))
                        .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)

                    Image(systemName: insight.icon)
                        .scaledFont(size: 18)
                        .foregroundStyle(insight.color)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(insight.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if !insight.metrics.isEmpty {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        if let first = insight.metrics.first {
                            Text(first.value)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(DSColors.readable(insight.color))
                            Text(first.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RecommendedViewCard: View {
    let view: LibraryVisualizationEngine.RecommendedView
    let isExpanded: Bool
    let onTap: () -> Void

    private var viewIcon: String {
        switch view.type {
        case .topicCloud: return "cloud.fill"
        case .embedding3D: return "cube.fill"
        case .retrievalFlow: return "arrow.triangle.branch"
        case .timelineView: return "calendar"
        case .contentBreakdown: return "chart.pie.fill"
        }
    }

    private var viewColor: Color {
        switch view.type {
        case .topicCloud: return DSColors.accent
        case .embedding3D: return DSColors.accent
        case .retrievalFlow: return .orange
        case .timelineView: return .green
        case .contentBreakdown: return .secondary
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Image(systemName: viewIcon)
                        .font(.title3)
                        .foregroundStyle(viewColor)

                    Spacer()

                    if isExpanded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text(view.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(view.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Relevance bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(viewColor.opacity(0.2))
                            .frame(height: 4)

                        Capsule()
                            .fill(viewColor)
                            .frame(width: geo.size.width * CGFloat(view.relevanceScore), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(isExpanded ? viewColor.opacity(0.1) : DSColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                            .stroke(isExpanded ? viewColor.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }
}
// MARK: - Atlas Components

struct AtlasStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .scaledFont(size: 9)
                .foregroundStyle(color)

            Text(value)
                .scaledFont(size: 10, weight: .bold, design: .rounded)
                .foregroundStyle(.white)

            Text(label)
                .scaledFont(size: 8)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            Capsule()
                .fill(color.opacity(0.3))
        )
        .fixedSize() // Prevent wrapping
    }
}

struct AtlasToggleChip: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(DSAnimations.snappySpring) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .scaledFont(size: 10)
                Text(label)
                    .font(.caption2)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.1))
            )
            .foregroundStyle(isOn ? .white : .white.opacity(0.6))
        }
    }
}

struct CompactInsightCard: View {
    let insight: VisualizationInsight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: insight.icon)
                        .scaledFont(size: 16)
                        .foregroundStyle(insight.color)

                    Text(insight.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(insight.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let metric = insight.metrics.first {
                    HStack(spacing: DSSpacing.xs) {
                        Text(metric.value)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(DSColors.readable(insight.color))
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 160)
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                            .stroke(insight.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

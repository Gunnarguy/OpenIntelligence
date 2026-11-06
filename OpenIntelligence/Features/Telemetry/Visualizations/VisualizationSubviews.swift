//
//  VisualizationSubviews.swift
//  OpenIntelligence
//
//  Moved from AdaptiveVisualizationsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SceneKit
import SwiftUI
import TipKit

// MARK: - Visualization Subviews

struct TopicCloudView: View {
    let topics: [TopicCluster]
    let profile: LibraryProfile

    /// A topic's passages in the library (5.8): counted when the analysis read the whole library, estimated from its
    /// share of the sample otherwise, so the numbers here add up to the header's passages, not the sample's.
    private func passageText(_ topic: TopicCluster) -> String {
        guard profile.isSampled else { return "\(topic.chunkCount.formatted()) passages" }
        let estimate = Int((Double(topic.percentage) * Double(profile.libraryPassageCount)).rounded())
        return "about \(estimate.formatted()) passages"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ForEach(topics) { topic in
                HStack(spacing: DSSpacing.md) {
                    Circle()
                        .fill(topic.color)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack {
                            Text(topic.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text(passageText(topic))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Keyword tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DSSpacing.xs) {
                                ForEach(topic.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption2)
                                        .padding(.horizontal, DSSpacing.sm)
                                        .padding(.vertical, DSSpacing.xs)
                                        .background(topic.color.opacity(0.15))
                                        .foregroundStyle(DSColors.readable(topic.color))
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(topic.color.opacity(0.2))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(topic.color)
                                    .frame(width: geo.size.width * CGFloat(topic.percentage), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(DSSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.background)
                )
            }
        }
    }
}

struct ContentBreakdownView: View {
    let contentMix: [ContentCategory: Float]
    let chunkCount: Int

    var sortedCategories: [(ContentCategory, Float)] {
        contentMix.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            // Pie chart representation
            Chart {
                ForEach(sortedCategories, id: \.0) { category, percentage in
                    SectorMark(
                        angle: .value("Percentage", percentage),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(category.color)
                    .annotation(position: .overlay) {
                        if percentage > 0.1 {
                            Text(String(format: "%.0f%%", percentage * 100))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(height: 200)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                ForEach(sortedCategories.filter { $0.1 > 0.05 }, id: \.0) { category, percentage in
                    HStack(spacing: DSSpacing.sm) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 10, height: 10)

                        Image(systemName: category.icon)
                            .font(.caption)
                            .foregroundStyle(category.color)

                        Text(category.rawValue)
                            .font(.caption)

                        Spacer()

                        Text(String(format: "%.0f%%", percentage * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct RetrievalFlowView: View {
    let hotChunks: [HotChunk]
    let coldZones: Int
    let totalChunks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // Hot chunks list
            ForEach(hotChunks) { chunk in
                HStack(spacing: DSSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Text("\(chunk.retrievalCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(DSColors.readable(.orange))
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(chunk.documentName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(chunk.snippet)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(String(format: "%.2f", chunk.avgSimilarity))
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("avg sim")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DSSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.background)
                )
            }

            // Coverage summary
            HStack(spacing: DSSpacing.xl) {
                VStack(spacing: DSSpacing.xs) {
                    Text("\(hotChunks.reduce(0) { $0 + $1.retrievalCount })")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(DSColors.readable(.orange))
                    Text("Total Hits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: DSSpacing.xs) {
                    Text("\(totalChunks - coldZones)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(DSColors.readable(.green))
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: DSSpacing.xs) {
                    Text("\(coldZones)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text("Untouched")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.background)
            )
        }
    }
}

struct LibraryTimelineView: View {
    let additions: [RecentAddition]
    let libraryAge: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // Age summary
            HStack {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Library Age")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatAge(libraryAge))
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                    Text("Recent Additions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(additions.count)")
                        .font(.headline)
                        .foregroundStyle(DSColors.readable(.green))
                }
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.background)
            )

            // Recent additions list
            if !additions.isEmpty {
                ForEach(additions) { addition in
                    HStack(spacing: DSSpacing.md) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(addition.documentName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(addition.addedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                            Text(String(format: "%.0f%%", addition.integrationScore * 100))
                                .font(.caption)
                                .foregroundStyle(DSColors.readable(addition.integrationScore > 0.6 ? .green : .orange))
                            Text("fit")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                            .fill(DSColors.background)
                    )
                }
            } else {
                Text("No recent additions in the last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(DSSpacing.lg)
            }
        }
    }

    private func formatAge(_ interval: TimeInterval) -> String {
        let days = Int(interval / (24 * 60 * 60))
        if days < 1 {
            return "New"
        } else if days < 30 {
            return "\(days) days"
        } else if days < 365 {
            return "\(days / 30) months"
        } else {
            return "\(days / 365) years"
        }
    }
}

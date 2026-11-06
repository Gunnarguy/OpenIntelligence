//
//  QueryAnalyticsView.swift
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

// MARK: - Query Analytics View

struct QueryAnalyticsView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject private var telemetry = TelemetryCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text("Query Analytics")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, DSSpacing.lg)

            // Recent queries from telemetry
            if telemetry.events.isEmpty {
                EmptyAnalyticsView()
                    .padding(DSSpacing.lg)
            } else {
                QueryStatsGrid()
                    .padding(.horizontal, DSSpacing.lg)

                RecentQueriesList(telemetry: telemetry)
                    .padding(.horizontal, DSSpacing.lg)
            }
        }
    }
}

struct EmptyAnalyticsView: View {
    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .scaledFont(size: 50)
                .foregroundStyle(.secondary)

            Text("No query data yet")
                .font(.headline)

            Text("Run some queries to see analytics")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

struct QueryStatsGrid: View {
    @ObservedObject private var telemetry = TelemetryCenter.shared

    var queryCount: Int {
        telemetry.events.filter { $0.category == .generation && $0.title.contains("Query") }.count
    }

    var avgResponseTime: Double {
        let queryEvents = telemetry.events.filter { $0.category == .generation }
        guard !queryEvents.isEmpty else { return 0 }
        let totalTime = queryEvents.compactMap { $0.duration }.reduce(0, +)
        return totalTime / Double(queryEvents.count)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
            StatCard(
                icon: "bubble.left.and.bubble.right",
                label: "Queries",
                value: "\(queryCount)",
                color: DSColors.accent
            )

            StatCard(
                icon: "clock",
                label: "Avg Time",
                value: String(format: "%.1fs", avgResponseTime),
                color: .green
            )
        }
    }
}

struct RecentQueriesList: View {
    @ObservedObject var telemetry: TelemetryCenter

    var recentQueries: [TelemetryEvent] {
        telemetry.events
            .filter { $0.category == .generation && $0.title.contains("Query") }
            .prefix(5)
            .reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Recent Queries")
                .font(.headline)

            ForEach(Array(recentQueries.enumerated()), id: \.element.id) { index, event in
                QueryEventCard(event: event, index: index + 1)
            }
        }
    }
}

struct QueryEventCard: View {
    let event: TelemetryEvent
    let index: Int

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            ZStack {
                Circle()
                    .fill(DSColors.accent.opacity(0.16))
                    .frame(width: 32, height: 32)

                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(DSColors.accent)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(event.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let duration = event.duration {
                    Text(String(format: "%.2f s", duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }
}

struct RetrievalPatternsView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    let totalChunkCount: Int
    let activeDocuments: [Document]

    private var activeContainerId: UUID { containerService.activeContainerId }

    private var history: [RetrievalLogEntry] {
        ragService.retrievalHistory.filter { $0.containerId == activeContainerId }
    }

    private var documentLookup: [UUID: String] {
        Dictionary(uniqueKeysWithValues: activeDocuments.map { ($0.id, $0.filename) })
    }

    var body: some View {
        let docLookup = documentLookup
        let chunkStats = buildChunkStats(docLookup: docLookup)
        let documentStats = buildDocumentStats(from: chunkStats)
        let totalRetrievals = history.reduce(0) { $0 + $1.chunks.count }
        let coverage = coveragePercentage(uniqueChunkCount: chunkStats.count)
        let coverageLabel = formattedCoverage(coverage)
        let topDocumentName = documentStats.first?.name ?? "—"

        return DashboardSectionCard(
            icon: "target",
            title: "Retrieval Patterns",
            subtitle: "See which chunks ground your answers most often"
        ) {
            if history.isEmpty {
                Text("Run a few queries to populate retrieval analytics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                statsGrid(
                    totalRetrievals: totalRetrievals,
                    uniqueChunks: chunkStats.count,
                    coverageLabel: coverageLabel,
                    topDocument: topDocumentName
                )

                if !chunkStats.isEmpty {
                    chunkChart(chunkStats.prefix(8))
                        .padding(.top, DSSpacing.sm)
                }

                if !documentStats.isEmpty {
                    documentChart(documentStats.prefix(6))
                        .padding(.top, DSSpacing.md)
                }

                if !chunkStats.isEmpty {
                    chunkDetailSection(chunkStats.prefix(3))
                        .padding(.top, DSSpacing.md)
                }

                VisualizationInfoSection(title: "🔍 Atlas-inspired cross filtering") {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("Apple's Embedding Atlas advocates linking projection, clustering, and metadata views so you can spot the sources that actually ground responses.")
                            .font(.caption2)
                        Text("These retrieval metrics are computed directly from your live history, making it easy to compare hit coverage against chunking strategy or embedding quality.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, DSSpacing.md)
            }
        }
    }

    private func statsGrid(
        totalRetrievals: Int,
        uniqueChunks: Int,
        coverageLabel: String,
        topDocument: String
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
            StatCard(
                icon: "arrow.2.squarepath",
                label: "Retrievals",
                value: "\(totalRetrievals)",
                color: DSColors.accent
            )

            StatCard(
                icon: "number",
                label: "Unique Chunks",
                value: "\(uniqueChunks)",
                color: DSColors.accent
            )

            StatCard(
                icon: "percent",
                label: "Coverage",
                value: coverageLabel,
                color: .orange
            )

            StatCard(
                icon: "doc.richtext",
                label: "Top Document",
                value: topDocument,
                color: .green
            )
        }
    }

    @ViewBuilder
    private func chunkChart(_ stats: ArraySlice<ChunkHitStat>) -> some View {
        let entries = Array(stats)

        Chart {
            ForEach(entries) { stat in
                BarMark(
                    x: .value("Hits", stat.hits),
                    y: .value("Chunk", chunkLabel(for: stat))
                )
                .foregroundStyle(color(for: stat.docId))
                .annotation(position: .trailing) {
                    Text("\(stat.hits) hits\navg \(String(format: "%.2f", stat.averageSimilarity))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(height: CGFloat(entries.count) * 32 + 20)
    }

    @ViewBuilder
    private func documentChart(_ stats: ArraySlice<DocumentHitStat>) -> some View {
        let entries = Array(stats)

        Chart {
            ForEach(entries) { stat in
                BarMark(
                    x: .value("Retrievals", stat.hits),
                    y: .value("Document", stat.name)
                )
                .foregroundStyle(color(for: stat.id))
                .annotation(position: .trailing) {
                    Text("\(stat.uniqueChunks) chunks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .annotation(position: .trailing) {
                    Text("\(stat.hits)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: CGFloat(entries.count) * 28 + 20)
    }

    private func chunkDetailSection(_ stats: ArraySlice<ChunkHitStat>) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Most-retrieved chunks")
                .font(.headline)

            ForEach(Array(stats)) { stat in
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                        Circle()
                            .fill(color(for: stat.docId))
                            .frame(width: 10, height: 10)

                        Text(chunkLabel(for: stat))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Text(String(format: "%.2f", stat.averageSimilarity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(DSColors.accent.opacity(0.12), in: Capsule())
                    }

                    if let section = stat.sectionTitle, !section.isEmpty {
                        Text(section)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(stat.snippet)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: DSSpacing.md) {
                        if let page = stat.pageNumber {
                            Label("Page \(page)", systemImage: "doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Label("\(stat.hits) hits", systemImage: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Label(relativeTime(for: stat.lastRetrieved), systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DSSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.background)
                )
            }
        }
    }

    private func buildChunkStats(docLookup: [UUID: String]) -> [ChunkHitStat] {
        struct MutableAccumulator {
            // Track per-chunk retrieval aggregation to stay aligned with live telemetry
            var chunk: DocumentChunk
            var docName: String
            var hits: Int
            var similaritySum: Double
            var lastRetrieved: Date
        }

        var accumulator: [UUID: MutableAccumulator] = [:]
        for entry in history {
            for retrieved in entry.chunks {
                let chunk = retrieved.chunk
                let chunkId = chunk.id
                let docId = chunk.documentId
                let docName = docLookup[docId] ?? retrieved.sourceDocument
                let similarity = Double(retrieved.similarityScore)
                if accumulator[chunkId] == nil {
                    accumulator[chunkId] = MutableAccumulator(
                        chunk: chunk,
                        docName: docName,
                        hits: 0,
                        similaritySum: 0,
                        lastRetrieved: entry.timestamp
                    )
                }
                accumulator[chunkId]?.hits += 1
                accumulator[chunkId]?.similaritySum += similarity
                if let current = accumulator[chunkId], entry.timestamp > current.lastRetrieved {
                    accumulator[chunkId]?.lastRetrieved = entry.timestamp
                }
            }
        }

        return accumulator.values.map { value in
            let chunk = value.chunk
            return ChunkHitStat(
                id: chunk.id,
                docId: chunk.documentId,
                docName: value.docName,
                chunkIndex: chunk.metadata.chunkIndex,
                hits: value.hits,
                averageSimilarity: value.hits > 0 ? value.similaritySum / Double(value.hits) : 0,
                lastRetrieved: value.lastRetrieved,
                pageNumber: chunk.metadata.pageNumber,
                sectionTitle: chunk.metadata.sectionTitle,
                snippet: snippet(for: chunk.content)
            )
        }
        .sorted { lhs, rhs in
            if lhs.hits == rhs.hits {
                return lhs.lastRetrieved > rhs.lastRetrieved
            }
            return lhs.hits > rhs.hits
        }
    }

    private func buildDocumentStats(from chunkStats: [ChunkHitStat]) -> [DocumentHitStat] {
        var accumulator: [UUID: DocumentHitStat] = [:]
        for stat in chunkStats {
            var entry = accumulator[stat.docId] ?? DocumentHitStat(
                id: stat.docId,
                name: stat.docName,
                hits: 0,
                uniqueChunks: 0
            )
            entry.hits += stat.hits
            entry.uniqueChunks += 1
            accumulator[stat.docId] = entry
        }
        return accumulator.values.sorted { lhs, rhs in
            if lhs.hits == rhs.hits {
                return lhs.uniqueChunks > rhs.uniqueChunks
            }
            return lhs.hits > rhs.hits
        }
    }

    private func coveragePercentage(uniqueChunkCount: Int) -> Double {
        guard totalChunkCount > 0 else { return 0 }
        return (Double(uniqueChunkCount) / Double(totalChunkCount)) * 100
    }

    private func formattedCoverage(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        return String(format: "%.0f%%", value)
    }

    func color(for docId: UUID) -> Color {
        let hash = abs(docId.uuidString.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.65, brightness: 0.9)
    }

    private func chunkLabel(for stat: ChunkHitStat) -> String {
        "\(stat.docName) • #\(stat.chunkIndex + 1)"
    }

    private func relativeTime(for date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    func snippet(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return String(trimmed.prefix(180)) + "…"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private struct ChunkHitStat: Identifiable {
        let id: UUID
        let docId: UUID
        let docName: String
        let chunkIndex: Int
        let hits: Int
        let averageSimilarity: Double
        let lastRetrieved: Date
        let pageNumber: Int?
        let sectionTitle: String?
        let snippet: String
    }

    private struct DocumentHitStat: Identifiable {
        let id: UUID
        let name: String
        var hits: Int
        var uniqueChunks: Int
    }
}

struct DashboardSectionCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    private let content: Content

    init(icon: String, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(DSColors.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            content
        }
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal, DSSpacing.lg)
    }
}

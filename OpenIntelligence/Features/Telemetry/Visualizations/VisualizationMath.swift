//
//  VisualizationMath.swift
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

// MARK: - Math & Sampling Helpers

enum VisualizationMath {
    /// Compute the L2 norm of an embedding vector while guarding against overflow.
    static func vectorNorm(_ vector: [Float]) -> Float {
        guard !vector.isEmpty else { return 0 }
        let sum = vector.reduce(Float.zero) { partial, value in
            partial + (value * value)
        }
        return sqrt(sum)
    }
}

enum VisualizationChunkSampler {
    static func seed(for containerId: UUID) -> UInt64 {
        let uuid = containerId.uuid
        let high =
            (UInt64(uuid.0) << 56) |
            (UInt64(uuid.1) << 48) |
            (UInt64(uuid.2) << 40) |
            (UInt64(uuid.3) << 32) |
            (UInt64(uuid.4) << 24) |
            (UInt64(uuid.5) << 16) |
            (UInt64(uuid.6) << 8) |
            UInt64(uuid.7)
        let low =
            (UInt64(uuid.8) << 56) |
            (UInt64(uuid.9) << 48) |
            (UInt64(uuid.10) << 40) |
            (UInt64(uuid.11) << 32) |
            (UInt64(uuid.12) << 24) |
            (UInt64(uuid.13) << 16) |
            (UInt64(uuid.14) << 8) |
            UInt64(uuid.15)
        let combined = high ^ low
        return combined == 0 ? 0x9E37_79B9_7F4A_7C15 : combined
    }

    static func sampleChunks(
        _ chunks: [DocumentChunk],
        limit: Int,
        seed: UInt64
    ) -> [DocumentChunk] {
        guard limit > 0, !chunks.isEmpty else { return [] }
        guard chunks.count > limit else { return chunks }
        var generator = SplitMix64(seed: seed)
        var selection = Array(chunks.shuffled(using: &generator).prefix(limit))
        selection.sort(by: VisualizationChunkSampler.chunkOrdering)
        return selection
    }

    private nonisolated static func chunkOrdering(lhs: DocumentChunk, rhs: DocumentChunk) -> Bool {
        if lhs.documentId == rhs.documentId {
            return lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
        return lhs.documentId.uuidString < rhs.documentId.uuidString
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

// MARK: - FTS5 Storage Visualization

/// Comprehensive SQLite FTS5 full-text search statistics and visualization
struct FTS5StorageView: View {
    let containerId: UUID

    @State private var stats: SQLiteFullTextService.FTS5Statistics?
    @State private var indexInfo: SQLiteFullTextService.FTS5IndexInfo?
    @State private var documentStats: [SQLiteFullTextService.DocumentStat] = []
    @State private var isLoading = true
    @State private var showDocumentList = false

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            // Header with status
            headerSection

            if isLoading {
                ProgressView("Loading FTS5 statistics...")
                    .padding(DSSpacing.lg)
            } else if let stats = stats {
                // Main stats grid
                mainStatsGrid(stats)

                // Index health card
                if let indexInfo = indexInfo {
                    indexHealthCard(indexInfo, stats: stats)
                }

                // Container breakdown
                if !stats.containerStats.isEmpty {
                    containerBreakdownCard(stats)
                }

                // Document size distribution
                if !documentStats.isEmpty {
                    documentSizeChart
                }

                // Actions
                actionsSection
            } else {
                emptyState
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .task {
            await loadStatistics()
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundStyle(DSColors.accent)
                    Text("SQLite FTS5 Storage")
                        .font(.headline)
                }
                Text("Full-text search with inverted index")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let stats = stats {
                StatusBadge(
                    status: stats.indexStatus,
                    color: stats.totalDocuments > 0 ? .green : .orange
                )
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func mainStatsGrid(_ stats: SQLiteFullTextService.FTS5Statistics) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: DSSpacing.md) {
            FTS5StatCard(
                icon: "doc.text.fill",
                title: "Documents",
                value: "\(stats.totalDocuments)",
                subtitle: "Indexed",
                color: DSColors.accent
            )

            FTS5StatCard(
                icon: "textformat.size",
                title: "Characters",
                value: formatNumber(stats.totalCharacters),
                subtitle: "Total stored",
                color: DSColors.accent
            )

            FTS5StatCard(
                icon: "text.word.spacing",
                title: "Words",
                value: formatNumber(stats.totalWords),
                subtitle: "Searchable",
                color: .green
            )

            FTS5StatCard(
                icon: "externaldrive.fill",
                title: "Database Size",
                value: formatBytes(stats.databaseSizeBytes),
                subtitle: "On disk",
                color: .orange
            )

            FTS5StatCard(
                icon: "arrow.up.arrow.down",
                title: "Avg Doc Size",
                value: formatNumber(stats.averageDocumentSize),
                subtitle: "characters",
                color: DSColors.accent
            )

            FTS5StatCard(
                icon: "folder.fill",
                title: "Containers",
                value: "\(stats.containerStats.count)",
                subtitle: "Active",
                color: DSColors.accent
            )
        }
    }

    private func indexHealthCard(_ indexInfo: SQLiteFullTextService.FTS5IndexInfo, stats: SQLiteFullTextService.FTS5Statistics) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(DSColors.accent)
                Text("Index Health")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Unique Terms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatNumber(indexInfo.uniqueTerms))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Total Occurrences")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatNumber(indexInfo.totalTerms))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Avg Frequency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", indexInfo.averageTermFrequency))
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }

            // Compression ratio bar
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("Storage Efficiency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", min(100, indexInfo.compressionRatio * 100)))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(compressionColor(indexInfo.compressionRatio))
                            .frame(width: geo.size.width * min(1, CGFloat(indexInfo.compressionRatio)))
                    }
                }
                .frame(height: 8)

                Text(compressionDescription(indexInfo.compressionRatio))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func containerBreakdownCard(_ stats: SQLiteFullTextService.FTS5Statistics) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(DSColors.accent)
                Text("Container Breakdown")
                    .font(.headline)
                Spacer()
            }

            ForEach(stats.containerStats) { container in
                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(container.containerId.uuidString.prefix(8) + "...")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("\(container.documentCount) docs • \(formatNumber(container.totalWords)) words")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(formatNumber(container.totalCharacters))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("chars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DSSpacing.xs)

                if container.id != stats.containerStats.last?.id {
                    Divider()
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private var documentSizeChart: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.green)
                Text("Document Size Distribution")
                    .font(.headline)
                Spacer()

                Button {
                    showDocumentList.toggle()
                } label: {
                    Image(systemName: showDocumentList ? "list.bullet" : "chart.bar")
                        .foregroundStyle(DSColors.accent)
                }
            }

            if showDocumentList {
                documentListView
            } else {
                documentBarChart
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var documentBarChart: some View {
        VStack(spacing: DSSpacing.sm) {
            ForEach(documentStats.prefix(10)) { doc in
                HStack(spacing: DSSpacing.sm) {
                    Text(doc.documentId.uuidString.prefix(8) + "...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        let maxChars = documentStats.map(\.characterCount).max() ?? 1
                        let width = geo.size.width * CGFloat(doc.characterCount) / CGFloat(maxChars)

                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(DSColors.accent.gradient)
                            .frame(width: max(4, width))
                    }
                    .frame(height: 12)

                    Text(formatNumber(doc.characterCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }

            if documentStats.count > 10 {
                Text("+ \(documentStats.count - 10) more documents")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, DSSpacing.xs)
            }
        }
    }

    private var documentListView: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack {
                Text("Document ID")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Words")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 60)
            }
            .padding(.bottom, DSSpacing.xs)

            ForEach(documentStats.prefix(15)) { doc in
                HStack {
                    Text(doc.documentId.uuidString.prefix(12) + "...")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formatNumber(doc.characterCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatNumber(doc.wordCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            if documentStats.count > 15 {
                Text("+ \(documentStats.count - 15) more documents")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, DSSpacing.xs)
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: DSSpacing.md) {
            Button {
                Task { await loadStatistics() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColors.accent.opacity(0.15))
                    .foregroundStyle(DSColors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let stats = stats, let lastMod = stats.lastModified {
                Spacer()
                Text("Last updated: \(lastMod, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, DSSpacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "cylinder")
                .scaledFont(size: 48)
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No FTS5 Data")
                .font(.headline)

            Text("Add documents to populate the full-text search index")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(DSSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helpers

    private func loadStatistics() async {
        isLoading = true
        let service = SQLiteFullTextService.shared
        stats = await service.getStatistics()
        indexInfo = await service.getIndexInfo()
        documentStats = await service.getDocumentStats(containerId: containerId)
        isLoading = false
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func compressionColor(_ ratio: Double) -> Color {
        if ratio < 0.3 {
            return .green
        } else if ratio < 0.6 {
            return DSColors.accent
        } else if ratio < 0.9 {
            return .orange
        } else {
            return .red
        }
    }

    private func compressionDescription(_ ratio: Double) -> String {
        if ratio < 0.3 {
            return "Excellent: Index is highly compressed"
        } else if ratio < 0.6 {
            return "Good: Index has efficient storage"
        } else if ratio < 0.9 {
            return "Fair: Moderate compression achieved"
        } else {
            return "Index size similar to raw text (normal for small datasets)"
        }
    }
}

/// Individual stat card for FTS5 metrics
private struct FTS5StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

/// Status badge for index state
private struct StatusBadge: View {
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(DSColors.readable(color))
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        VisualizationsView()
            .environmentObject(RAGService())
            .environmentObject(ContainerService())
    }
}

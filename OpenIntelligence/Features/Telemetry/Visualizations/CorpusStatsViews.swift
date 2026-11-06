//
//  CorpusStatsViews.swift
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

// MARK: - Chunk Distribution View

struct ChunkDistributionView: View {
    let documents: [Document]
    let chunkCount: Int

    var chunkSizeData: [(document: String, avgSize: Double)] {
        documents.map { doc in
            let avgSize = doc.processingMetadata?.chunkStats.averageChars ?? 0
            return (doc.filename, Double(avgSize))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text("Chunk Distribution")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, DSSpacing.lg)

            // Chart
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(chunkSizeData, id: \.document) { item in
                        BarMark(
                            x: .value("Size", item.avgSize),
                            y: .value("Document", item.document)
                        )
                        .foregroundStyle(DSColors.accent.gradient)
                    }
                }
                .frame(height: CGFloat(documents.count * 50))
                .padding(DSSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                )
                .padding(.horizontal, DSSpacing.lg)
            }

            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                StatCard(
                    icon: "doc.text",
                    label: "Total Docs",
                    value: "\(documents.count)",
                    color: DSColors.accent
                )

                StatCard(
                    icon: "cube.box",
                    label: "Total Chunks",
                    value: "\(chunkCount)",
                    color: .green
                )

                StatCard(
                    icon: "chart.bar",
                    label: "Avg per Doc",
                    value: "\(documents.isEmpty ? 0 : chunkCount / documents.count)",
                    color: DSColors.accent
                )

                StatCard(
                    icon: "waveform",
                    label: "Avg Size",
                    value: "\(averageChunkSize) chars",
                    color: .orange
                )
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }

    private var averageChunkSize: Int {
        let totalSize = documents.compactMap { $0.processingMetadata?.chunkStats.averageChars }.reduce(0, +)
        return documents.isEmpty ? 0 : totalSize / documents.count
    }
}

// MARK: - Advanced Corpus Stats View

struct AdvancedCorpusStatsView: View {
    let documents: [Document]
    let chunkCount: Int

    @State private var showNerdStats = false

    private var totalCharacters: Int {
        // Calculate from average chars × chunk count per document
        documents.compactMap { doc -> Int? in
            guard let avgChars = doc.processingMetadata?.chunkStats.averageChars else { return nil }
            return avgChars * doc.totalChunks
        }.reduce(0, +)
    }

    private var totalWords: Int {
        // Estimate words as chars / 5 (avg word length)
        totalCharacters / 5
    }

    private var chunksPerDocStats: (min: Int, max: Int, avg: Double, stdDev: Double) {
        let counts = documents.map { $0.totalChunks }
        guard !counts.isEmpty else { return (0, 0, 0, 0) }

        let minVal = counts.min() ?? 0
        let maxVal = counts.max() ?? 0
        let avg = Double(counts.reduce(0, +)) / Double(counts.count)

        let variance = counts.map { pow(Double($0) - avg, 2) }.reduce(0, +) / Double(counts.count)
        let stdDev = sqrt(variance)

        return (minVal, maxVal, avg, stdDev)
    }

    private var chunkSizeStats: (min: Int, max: Int, avg: Int, median: Int) {
        let sizes = documents.compactMap { $0.processingMetadata?.chunkStats.averageChars }
        guard !sizes.isEmpty else { return (0, 0, 0, 0) }

        let sorted = sizes.sorted()
        let median = sorted[sorted.count / 2]

        return (sorted.first ?? 0, sorted.last ?? 0, sizes.reduce(0, +) / sizes.count, median)
    }

    private var documentTypeBreakdown: [(type: String, count: Int)] {
        let grouped = Dictionary(grouping: documents) { doc -> String in
            let ext = (doc.filename as NSString).pathExtension.lowercased()
            if ext.isEmpty { return "Text" }
            return ext.uppercased()
        }
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
    }

    private var ingestionTimeStats: (oldest: Date?, newest: Date?, avgAge: TimeInterval?) {
        let dates = documents.map { $0.addedAt }
        guard !dates.isEmpty else { return (nil, nil, nil) }

        let oldest = dates.min()
        let newest = dates.max()
        let avgTimestamp = dates.map { $0.timeIntervalSince1970 }.reduce(0, +) / Double(dates.count)
        let avgAge = Date().timeIntervalSince1970 - avgTimestamp

        return (oldest, newest, avgAge)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack {
                Text("Corpus Analytics")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    withAnimation(DSAnimations.snappySpring) {
                        showNerdStats.toggle()
                    }
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: showNerdStats ? "chevron.up" : "chevron.down")
                        Text(showNerdStats ? "Hide Details" : "🤓 Nerd Mode")
                    }
                    .font(.caption)
                    .foregroundStyle(DSColors.accent)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(DSColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DSSpacing.lg)

            // Quick stats row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    CorpusQuickStat(icon: "character", label: "Characters", value: formatLargeNumber(totalCharacters), color: DSColors.accent)
                    CorpusQuickStat(icon: "text.word.spacing", label: "Est. Words", value: formatLargeNumber(totalWords), color: .green)
                    CorpusQuickStat(icon: "doc.on.doc", label: "Avg Chunks/Doc", value: String(format: "%.1f", chunksPerDocStats.avg), color: DSColors.accent)
                    CorpusQuickStat(icon: "ruler", label: "Median Chunk", value: "\(chunkSizeStats.median) chars", color: .orange)
                }
                .padding(.horizontal, DSSpacing.lg)
            }

            if showNerdStats {
                VStack(spacing: DSSpacing.lg) {
                    // Document type breakdown
                    documentTypeSection

                    // Chunk statistics deep dive
                    chunkStatsSection

                    // Temporal analysis
                    temporalAnalysisSection

                    // Data quality indicators
                    dataQualitySection
                }
                .padding(.horizontal, DSSpacing.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var documentTypeSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: "doc.badge.gearshape")
                    .foregroundStyle(DSColors.accent)
                Text("Document Types")
                    .font(.headline)
            }

            HStack(spacing: DSSpacing.sm) {
                ForEach(documentTypeBreakdown, id: \.type) { item in
                    VStack(spacing: DSSpacing.xs) {
                        Text("\(item.count)")
                            .font(.title3.bold())
                        Text(item.type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.md)
                    .background(typeColor(item.type).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var chunkStatsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(DSColors.accent)
                Text("Chunk Statistics")
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                NerdStatRow(label: "Min chunks/doc", value: "\(chunksPerDocStats.min)")
                NerdStatRow(label: "Max chunks/doc", value: "\(chunksPerDocStats.max)")
                NerdStatRow(label: "Std deviation", value: String(format: "%.2f", chunksPerDocStats.stdDev))
                NerdStatRow(label: "Coefficient of var", value: String(format: "%.2f", chunksPerDocStats.stdDev / max(chunksPerDocStats.avg, 0.01)))
                NerdStatRow(label: "Min chunk size", value: "\(chunkSizeStats.min) chars")
                NerdStatRow(label: "Max chunk size", value: "\(chunkSizeStats.max) chars")
                NerdStatRow(label: "Size range", value: "\(chunkSizeStats.max - chunkSizeStats.min) chars")
                NerdStatRow(label: "Tokens (est.)", value: formatLargeNumber(totalCharacters / 4))
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var temporalAnalysisSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(DSColors.accent)
                Text("Temporal Analysis")
                    .font(.headline)
            }

            let timeStats = ingestionTimeStats
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                if let oldest = timeStats.oldest {
                    HStack {
                        Text("Oldest document:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(oldest, style: .date)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let newest = timeStats.newest {
                    HStack {
                        Text("Newest document:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(newest, style: .date)
                            .font(.caption.monospacedDigit())
                    }
                }
                if let avgAge = timeStats.avgAge {
                    HStack {
                        Text("Average age:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTimeInterval(avgAge))
                            .font(.caption.monospacedDigit())
                    }
                }
                if let oldest = timeStats.oldest, let newest = timeStats.newest {
                    HStack {
                        Text("Corpus span:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTimeInterval(newest.timeIntervalSince(oldest)))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var dataQualitySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.green)
                Text("Data Quality Indicators")
                    .font(.headline)
            }

            let uniformityScore = calculateUniformityScore()
            let coverageScore = calculateCoverageScore()
            let freshnessScore = calculateFreshnessScore()

            VStack(spacing: DSSpacing.sm) {
                QualityIndicatorRow(label: "Chunk Uniformity", score: uniformityScore, description: uniformityDescription(uniformityScore))
                QualityIndicatorRow(label: "Content Coverage", score: coverageScore, description: coverageDescription(coverageScore))
                QualityIndicatorRow(label: "Data Freshness", score: freshnessScore, description: freshnessDescription(freshnessScore))
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86400)
        if days > 365 {
            return "\(days / 365)y \(days % 365)d"
        } else if days > 30 {
            return "\(days / 30)mo \(days % 30)d"
        } else if days > 0 {
            return "\(days)d"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "pdf": return .red
        case "txt", "text": return DSColors.accent
        case "md", "markdown": return DSColors.accent
        case "csv": return .green
        case "json": return .orange
        case "html": return DSColors.accent
        default: return .secondary
        }
    }

    private func calculateUniformityScore() -> Double {
        let sizes = documents.map { $0.totalChunks }
        guard sizes.count > 1, let maxSize = sizes.max(), maxSize > 0 else { return 1.0 }

        let avg = Double(sizes.reduce(0, +)) / Double(sizes.count)
        let variance = sizes.map { pow(Double($0) - avg, 2) }.reduce(0, +) / Double(sizes.count)
        let cv = sqrt(variance) / avg // coefficient of variation

        return max(0, min(1, 1 - cv))
    }

    private func calculateCoverageScore() -> Double {
        guard !documents.isEmpty, chunkCount > 0 else { return 0 }

        // Check if all docs have chunks
        let docsWithChunks = documents.filter { $0.totalChunks > 0 }.count
        let docCoverage = Double(docsWithChunks) / Double(documents.count)

        // Check chunk distribution
        let avgChunks = Double(chunkCount) / Double(documents.count)
        let hasGoodDistribution = avgChunks >= 2 ? 1.0 : avgChunks / 2.0

        return (docCoverage + hasGoodDistribution) / 2
    }

    private func calculateFreshnessScore() -> Double {
        let dates = documents.map { $0.addedAt }
        guard !dates.isEmpty else { return 0 }

        let now = Date()
        let ages = dates.map { now.timeIntervalSince($0) }
        let avgAge = ages.reduce(0, +) / Double(ages.count)

        // Score based on average age (newer = higher)
        // 1 day = 1.0, 30 days = 0.5, 365 days = 0.1
        let dayAge = avgAge / 86400
        if dayAge < 1 { return 1.0 }
        if dayAge < 7 { return 0.9 }
        if dayAge < 30 { return 0.7 }
        if dayAge < 90 { return 0.5 }
        if dayAge < 365 { return 0.3 }
        return 0.1
    }

    private func uniformityDescription(_ score: Double) -> String {
        if score > 0.8 { return "Excellent: Chunks are uniformly distributed" }
        if score > 0.5 { return "Good: Some variation in chunk counts" }
        return "Consider: High variation between documents"
    }

    private func coverageDescription(_ score: Double) -> String {
        if score > 0.8 { return "Excellent: All documents well indexed" }
        if score > 0.5 { return "Good: Most documents have chunks" }
        return "Some documents may need reprocessing"
    }

    private func freshnessDescription(_ score: Double) -> String {
        if score > 0.8 { return "Fresh: Recently ingested content" }
        if score > 0.5 { return "Current: Reasonably up-to-date" }
        return "Consider refreshing older documents"
    }
}

// MARK: - Advanced Stats Helper Views

private struct CorpusQuickStat: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.monospacedDigit())
                .fontWeight(.semibold)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.md)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

private struct NerdStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColors.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

private struct QualityIndicatorRow: View {
    let label: String
    let score: Double
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f%%", score * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSColors.readable(scoreColor))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(scoreColor)
                        .frame(width: geo.size.width * CGFloat(score))
                }
            }
            .frame(height: 6)

            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var scoreColor: Color {
        if score > 0.8 { return .green }
        if score > 0.5 { return .orange }
        return .orange
    }
}

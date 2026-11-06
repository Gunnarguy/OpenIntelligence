//
//  SimilarityHeatmapView.swift
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

// MARK: - New Advanced Visualizations

struct SimilarityHeatmapView: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @State private var sampleChunks: [DocumentChunk] = []
    @State private var chunkDescriptors: [UUID: HeatmapChunkDescriptor] = [:]
    @State private var isLoading = false
    @State private var lastUpdated: Date? = nil
    @State private var refreshNonce: UInt64 = 0

    private let maxSampleCount = 12
    private let cellSize: CGFloat = 56
    private let rowLabelWidth: CGFloat = 140

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            headerSection
            heatmapSection
            statsSection
        }
        .task { await refreshSample() }
        .task(id: containerService.activeContainerId) {
            await MainActor.run { refreshNonce = 0 }
            await refreshSample()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(DSColors.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("Similarity Heatmap")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Pairwise cosine similarity across sampled chunks from the active library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let stamp = formattedLastUpdated() {
                    Text("Updated \(stamp)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    guard !isLoading else { return }
                    refreshNonce &+= 1
                    Task(priority: .userInitiated) {
                        await refreshSample()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            VisualizationInfoSection(title: "💡 Why cosine similarity?") {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Embeddings are high-dimensional vectors. Cosine similarity measures the angle between them, giving a scale from 0 (unrelated) to 1 (identical).")
                        .font(.caption2)
                    Text("Cells along the diagonal are always 1.0 because a chunk is perfectly similar to itself.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.background)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8)
        .padding(.horizontal, DSSpacing.lg)
    }

    @ViewBuilder
    private var heatmapSection: some View {
        if isLoading {
            ProgressView("Computing similarities…")
                .padding(DSSpacing.lg)
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(DSColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                .padding(.horizontal, DSSpacing.lg)
        } else if sampleChunks.isEmpty {
            Text("Add documents or run a query to populate similarity data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(DSSpacing.lg)
                .frame(maxWidth: .infinity)
                .background(DSColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                .padding(.horizontal, DSSpacing.lg)
        } else {
            heatmapGrid
        }
    }

    private var heatmapGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xxs) {
                    Color.clear.frame(width: rowLabelWidth, height: cellSize)
                    ForEach(sampleChunks) { chunk in
                        headerLabel(for: chunk)
                    }
                }
                ForEach(sampleChunks) { rowChunk in
                    HStack(spacing: DSSpacing.xxs) {
                        sideLabel(for: rowChunk)
                        ForEach(sampleChunks) { columnChunk in
                            heatmapCell(rowChunk, columnChunk)
                        }
                    }
                }
            }
            .padding(DSSpacing.lg)
        }
        .frame(maxHeight: 420)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .padding(.horizontal, DSSpacing.lg)
    }

    private var statsSection: some View {
        HStack(spacing: DSSpacing.md) {
            StatCard(
                icon: "number",
                label: "Chunks",
                value: "\(sampleChunks.count)",
                color: DSColors.accent
            )
            StatCard(
                icon: "doc.text.fill",
                label: "Documents",
                value: "\(uniqueDocumentCount)",
                color: DSColors.accent
            )
            StatCard(
                icon: "waveform.path.ecg",
                label: "Avg Similarity",
                value: String(format: "%.2f", averagePairSimilarity),
                color: .secondary
            )
            StatCard(
                icon: "arrow.up",
                label: "Max Similarity",
                value: String(format: "%.2f", maximumPairSimilarity),
                color: .orange
            )
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func refreshSample() async {
        await MainActor.run { isLoading = true }
        let allChunks = await ragService.allChunksForActiveContainer()
        if Task.isCancelled { return }
        guard !allChunks.isEmpty else {
            await MainActor.run {
                sampleChunks = []
                chunkDescriptors = [:]
                lastUpdated = Date()
                isLoading = false
            }
            return
        }

        let docNames = await MainActor.run {
            Dictionary(uniqueKeysWithValues: ragService.documents.map { ($0.id, $0.filename) })
        }
        let seed = VisualizationChunkSampler.seed(for: containerService.activeContainerId) ^ refreshNonce
        let sample = VisualizationChunkSampler.sampleChunks(
            allChunks,
            limit: maxSampleCount,
            seed: seed
        )
        let descriptors = buildDescriptors(for: sample, docNames: docNames)

        await MainActor.run {
            sampleChunks = sample
            chunkDescriptors = descriptors
            lastUpdated = Date()
            isLoading = false
        }
    }

    private func buildDescriptors(
        for chunks: [DocumentChunk],
        docNames: [UUID: String]
    ) -> [UUID: HeatmapChunkDescriptor] {
        var result: [UUID: HeatmapChunkDescriptor] = [:]
        result.reserveCapacity(chunks.count)
        for chunk in chunks {
            let docName = docNames[chunk.documentId] ?? "Unknown"
            let descriptor = HeatmapChunkDescriptor(
                docName: docName,
                sectionTitle: chunk.metadata.sectionTitle,
                chunkIndex: chunk.metadata.chunkIndex,
                page: chunk.metadata.pageNumber,
                norm: VisualizationMath.vectorNorm(chunk.embedding),
                snippet: String(chunk.content.prefix(120))
            )
            result[chunk.id] = descriptor
        }
        return result
    }

    private func headerLabel(for chunk: DocumentChunk) -> some View {
        Text(label(for: chunk))
            .font(.caption2.weight(.medium))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(width: cellSize, height: cellSize)
    }

    private func sideLabel(for chunk: DocumentChunk) -> some View {
        Text(label(for: chunk))
            .font(.caption2)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(width: rowLabelWidth, height: cellSize, alignment: .leading)
    }

    private func heatmapCell(_ row: DocumentChunk, _ column: DocumentChunk) -> some View {
        let similarity = cosineSimilarity(row, column)
        let color = heatColor(for: similarity)
        let textColor = heatTextColor(for: similarity)
        let value = String(format: "%.2f", similarity)
        return Rectangle()
            .fill(color)
            .frame(width: cellSize, height: cellSize)
            .overlay(
                Text(value)
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(textColor)
            )
            .accessibilityLabel(
                Text("Similarity between \(label(for: row)) and \(label(for: column)) is \(value)")
            )
    }

    func label(for chunk: DocumentChunk) -> String {
        guard let descriptor = chunkDescriptors[chunk.id] else {
            return "Chunk \(chunk.metadata.chunkIndex + 1)"
        }
        var parts: [String] = [descriptor.docName]
        if let page = descriptor.page {
            parts.append("p.\(page)")
        }
        parts.append("#\(descriptor.chunkIndex + 1)")
        return parts.joined(separator: " • ")
    }

    private func cosineSimilarity(_ lhs: DocumentChunk, _ rhs: DocumentChunk) -> Float {
        guard lhs.embedding.count == rhs.embedding.count else { return 0 }
        let dot = zip(lhs.embedding, rhs.embedding).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let leftNorm = chunkDescriptors[lhs.id]?.norm ?? VisualizationMath.vectorNorm(lhs.embedding)
        let rightNorm = chunkDescriptors[rhs.id]?.norm ?? VisualizationMath.vectorNorm(rhs.embedding)
        let denom = max(leftNorm * rightNorm, 1e-6)
        return max(0, min(1, dot / denom))
    }

    private func heatColor(for similarity: Float) -> Color {
        let clamped = max(0, min(1, similarity))
        let hue = 0.58 - (Double(clamped) * 0.45)
        return Color(hue: hue, saturation: 0.85, brightness: 0.95)
    }

    private func heatTextColor(for similarity: Float) -> Color {
        similarity > 0.6 ? .white : .black.opacity(0.8)
    }

    func formattedLastUpdated() -> String? {
        guard let date = lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var uniqueDocumentCount: Int {
        Set(sampleChunks.map { $0.documentId }).count
    }

    private var averagePairSimilarity: Double {
        guard sampleChunks.count > 1 else { return 1.0 }
        var sum: Double = 0
        var count = 0
        for (idx, chunk) in sampleChunks.enumerated() {
            for jdx in idx + 1 ..< sampleChunks.count {
                sum += Double(cosineSimilarity(chunk, sampleChunks[jdx]))
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 1.0
    }

    private var maximumPairSimilarity: Double {
        guard sampleChunks.count > 1 else { return 1.0 }
        var maxValue: Double = 0
        for chunk in sampleChunks {
            for other in sampleChunks where chunk.id != other.id {
                maxValue = max(maxValue, Double(cosineSimilarity(chunk, other)))
            }
        }
        return maxValue
    }

    private struct HeatmapChunkDescriptor {
        let docName: String
        let sectionTitle: String?
        let chunkIndex: Int
        let page: Int?
        let norm: Float
        let snippet: String
    }
}

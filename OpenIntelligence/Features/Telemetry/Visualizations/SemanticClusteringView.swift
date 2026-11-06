//
//  SemanticClusteringView.swift
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

struct SemanticClusteringView: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedK: Int = 3
    @State private var sampleChunks: [DocumentChunk] = []
    @State private var docNames: [UUID: String] = [:]
    @State private var chunkNorms: [UUID: Float] = [:]
    @State private var clusters: [[DocumentChunk]] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var lastUpdated: Date?
    @State private var refreshNonce: UInt64 = 0
    @State private var showClusterTopics = true

    private let maxSampleCount = 180
    private let maxIterations = 12

    var body: some View {
        DashboardSectionCard(
            icon: "circle.hexagongrid.fill",
            title: "Semantic Clustering",
            subtitle: "Sample embeddings to discover the highest-signal topics"
        ) {
            VStack(spacing: DSSpacing.lg) {
                clusterControls

                if let error = lastError {
                    errorCard(error)
                } else if isLoading {
                    loadingCard
                } else if sampleChunks.isEmpty {
                    emptyStateCard
                } else {
                    clusterSummarySection
                    clusterDistributionSection
                    clusterPreviewSection
                    ClusteringInfoCard()
                }
            }
        }
        .task {
            await refreshSample()
        }
        .task(id: containerService.activeContainerId) {
            refreshNonce = 0
            await refreshSample()
        }
        .onChange(of: selectedK) { oldValue, newValue in
            guard newValue != oldValue else { return }
            recomputeClusters()
        }
    }

    private var clusterControls: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Cluster granularity")
                        .font(.headline)

                    Text("Tighter clusters surface more niche themes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("K = \(selectedK)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DSColors.accent)
            }

            Slider(value: Binding(
                get: { Double(selectedK) },
                set: { selectedK = Int($0) }
            ), in: 2 ... 10, step: 1)
                .tint(DSColors.accent)
                .accessibilityLabel("Cluster granularity")
                .accessibilityValue("K = \(selectedK)")

            HStack(spacing: DSSpacing.md) {
                Button {
                    guard !isLoading else { return }
                    refreshNonce &+= 1
                    Task { await refreshSample() }
                } label: {
                    Label(isLoading ? "Refreshing…" : "Refresh sample", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if let stamp = formattedLastUpdated {
                    Label("Updated \(stamp)", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Label("\(sampleChunks.count) chunks", systemImage: "square.stack.3d.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(DSColors.readable(.red))
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var loadingCard: some View {
        ProgressView("Clustering embeddings…")
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var emptyStateCard: some View {
        Text("Import documents or run queries to generate chunk embeddings for clustering.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var clusterDistributionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Cluster Distribution")
                .font(.headline)
            Chart {
                ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                    BarMark(
                        x: .value("Count", cluster.count),
                        y: .value("Cluster", "Topic \(index + 1)")
                    )
                    .foregroundStyle(clusterColor(index))
                    .annotation(position: .trailing) {
                        Text("\(cluster.count) chunks")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: CGFloat(max(clusters.count, 1) * 48))
            .padding(.horizontal, DSSpacing.xs)
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.background)
        )
    }

    private var clusterSummarySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.md) {
                MetricPill(icon: "number", label: "Clusters", value: "\(clusters.count)")
                MetricPill(icon: "doc.on.doc", label: "Unique docs", value: "\(uniqueDocumentCount)")
                MetricPill(icon: "chart.bar", label: "Avg size", value: averageClusterSize)
                MetricPill(icon: "chart.pie", label: "Largest", value: "\(maxClusterSize)")
                MetricPill(icon: "link", label: "Avg sim", value: String(format: "%.2f", averagePairSimilarity))
            }
            .padding(.vertical, DSSpacing.xs)
        }
    }

    private var clusterPreviewSection: some View {
        DisclosureGroup(isExpanded: $showClusterTopics) {
            VStack(spacing: DSSpacing.md) {
                ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                    ClusterPreviewCard(
                        index: index,
                        cluster: cluster,
                        color: clusterColor(index),
                        docNameProvider: docName(for:)
                    )
                }
            }
            .padding(.top, DSSpacing.sm)
        } label: {
            HStack {
                Text("Topic highlights")
                    .font(.headline)
                Spacer()
                Text("Tap to \(showClusterTopics ? "collapse" : "expand")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct MetricPill: View {
        let icon: String
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(DSColors.accent)
                    Text(label.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.background)
            )
        }
    }

    private func refreshSample() async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        let allChunks = await ragService.allChunksForActiveContainer()
        if Task.isCancelled { return }

        let seedBase = VisualizationChunkSampler.seed(for: containerService.activeContainerId) ^ refreshNonce

        if allChunks.isEmpty {
            await MainActor.run {
                sampleChunks = []
                docNames = [:]
                chunkNorms = [:]
                clusters = []
                lastUpdated = Date()
                isLoading = false
            }
            return
        }

        let sampled = VisualizationChunkSampler.sampleChunks(
            allChunks,
            limit: maxSampleCount,
            seed: seedBase
        )

        let norms = Dictionary(uniqueKeysWithValues: sampled.map { ($0.id, VisualizationMath.vectorNorm($0.embedding)) })

        let names = await MainActor.run {
            Dictionary(uniqueKeysWithValues: ragService.documents.map { ($0.id, $0.filename) })
        }

        await MainActor.run {
            docNames = names
            sampleChunks = sampled
            chunkNorms = norms
            recomputeClusters(seed: seedBase &+ UInt64(selectedK))
            lastUpdated = Date()
            isLoading = false
        }
    }

    @MainActor
    private func recomputeClusters(seed: UInt64? = nil) {
        guard !sampleChunks.isEmpty else {
            clusters = []
            return
        }
        let baseSeed = seed ?? (VisualizationChunkSampler.seed(for: containerService.activeContainerId) ^ refreshNonce)
        let rawClusters = performKMeansClustering(chunks: sampleChunks, k: selectedK, seed: baseSeed)
        clusters = sanitizeClusters(rawClusters)
    }

    private var formattedLastUpdated: String? {
        guard let date = lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var uniqueDocumentCount: Int {
        Set(sampleChunks.map { $0.documentId }).count
    }

    private var maxClusterSize: Int {
        clusters.map(\.count).max() ?? 0
    }

    private var averageClusterSize: String {
        guard !clusters.isEmpty else { return "0.0" }
        return String(format: "%.1f", Double(sampleChunks.count) / Double(max(clusters.count, 1)))
    }

    private var averagePairSimilarity: Double {
        var total: Double = 0
        var pairCount = 0

        for cluster in clusters where cluster.count > 1 {
            for lhsIndex in 0 ..< (cluster.count - 1) {
                let lhs = cluster[lhsIndex]
                for rhs in cluster[(lhsIndex + 1) ..< cluster.count] {
                    total += cosineSimilarity(lhs, rhs)
                    pairCount += 1
                }
            }
        }

        guard pairCount > 0 else { return 0 }
        return total / Double(pairCount)
    }

    @MainActor
    private func docName(for chunk: DocumentChunk) -> String {
        if let cached = docNames[chunk.documentId] {
            return cached
        }
        return ragService.getDocumentName(for: chunk.documentId)
    }

    private func cosineSimilarity(_ lhs: DocumentChunk, _ rhs: DocumentChunk) -> Double {
        let embeddingA = lhs.embedding
        let embeddingB = rhs.embedding
        guard embeddingA.count == embeddingB.count, !embeddingA.isEmpty else { return 0 }

        var dot: Double = 0
        for (valueA, valueB) in zip(embeddingA, embeddingB) {
            dot += Double(valueA * valueB)
        }

        let normA = Double(chunkNorms[lhs.id] ?? VisualizationMath.vectorNorm(embeddingA))
        let normB = Double(chunkNorms[rhs.id] ?? VisualizationMath.vectorNorm(embeddingB))
        let denominator = max(normA * normB, 1e-6)
        let similarity = dot / denominator
        return max(0, min(1, similarity))
    }

    private func performKMeansClustering(chunks: [DocumentChunk], k: Int, seed: UInt64) -> [[DocumentChunk]] {
        guard !chunks.isEmpty, k > 0 else { return [] }

        var generator = SplitMix64(seed: seed == 0 ? 0xCAFE_BABE_DEAD_BEEF : seed)
        var centroids: [[Float]] = []
        centroids.reserveCapacity(k)
        for _ in 0 ..< k {
            if let embedding = chunks.randomElement(using: &generator)?.embedding {
                centroids.append(embedding)
            } else {
                centroids.append(chunks[0].embedding)
            }
        }

        var clusters = Array(repeating: [DocumentChunk](), count: k)

        for _ in 0 ..< maxIterations {
            clusters = Array(repeating: [], count: k)
            for chunk in chunks {
                let distances = centroids.enumerated().map { index, centroid -> (Int, Float) in
                    (index, euclideanDistance(chunk.embedding, centroid))
                }
                if let nearest = distances.min(by: { $0.1 < $1.1 })?.0 {
                    clusters[nearest].append(chunk)
                }
            }

            for index in 0 ..< k where !clusters[index].isEmpty {
                centroids[index] = averageEmbedding(clusters[index].map { $0.embedding })
            }
        }

        return clusters.filter { !$0.isEmpty }
    }

    private func sanitizeClusters(_ raw: [[DocumentChunk]]) -> [[DocumentChunk]] {
        guard !raw.isEmpty else { return [] }
        let normalized = raw.compactMap { cluster -> (ClusterSignature, [DocumentChunk])? in
            let ordered = cluster.sorted(by: chunkOrdering)
            guard !ordered.isEmpty else { return nil }
            // Use a deterministic signature so "Topic 1" consistently tracks the same cluster weight.
            return (clusterSignature(for: ordered), ordered)
        }
        return normalized.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private func chunkOrdering(lhs: DocumentChunk, rhs: DocumentChunk) -> Bool {
        if lhs.documentId == rhs.documentId {
            return lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
        return lhs.documentId.uuidString < rhs.documentId.uuidString
    }

    private func clusterSignature(for cluster: [DocumentChunk]) -> ClusterSignature {
        var docAccumulator: UInt64 = 0
        var leading = cluster.first
        for chunk in cluster {
            let hash = UInt64(bitPattern: Int64(chunk.documentId.hashValue))
            docAccumulator ^= hash
            if let current = leading, chunkOrdering(lhs: current, rhs: chunk) {
                continue
            }
            leading = chunk
        }
        return ClusterSignature(
            size: cluster.count,
            docHash: docAccumulator,
            leadChunkId: leading?.id ?? UUID()
        )
    }

    private struct ClusterSignature: Comparable {
        let size: Int
        let docHash: UInt64
        let leadChunkId: UUID

        static func < (lhs: ClusterSignature, rhs: ClusterSignature) -> Bool {
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            if lhs.docHash != rhs.docHash { return lhs.docHash < rhs.docHash }
            return lhs.leadChunkId.uuidString < rhs.leadChunkId.uuidString
        }
    }

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.infinity }
        var sum: Float = 0
        for (lhs, rhs) in zip(a, b) {
            let diff = lhs - rhs
            sum += diff * diff
        }
        return sqrt(sum)
    }

    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        var accumulator = Array(repeating: Float.zero, count: first.count)
        for embedding in embeddings {
            for (index, value) in embedding.enumerated() {
                accumulator[index] += value
            }
        }
        let count = Float(embeddings.count)
        return accumulator.map { $0 / count }
    }

    private func clusterColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .red, .cyan, .indigo, .mint, .teal]
        return colors[index % colors.count]
    }
}

// MARK: - Helper Views

struct ClusteringInfoCard: View {
    var body: some View {
        VisualizationInfoSection(title: "🧠 What is K-means Clustering?") {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Automatically groups similar chunks together:")
                    .font(.caption)
                    .fontWeight(.medium)

                Text("1. Picks K random cluster centers in embedding space")
                    .font(.caption2)
                Text("2. Assigns each chunk to nearest center")
                    .font(.caption2)
                Text("3. Recalculates centers based on assignments")
                    .font(.caption2)
                Text("4. Repeats until clusters stabilize")
                    .font(.caption2)

                Divider()

                Text("Use this to discover main topics in your knowledge base without manual tagging!")
                    .font(.caption2)
                    .foregroundStyle(DSColors.accent)
                    .fontWeight(.medium)
            }
        }
    }
}

@MainActor
struct ClusterPreviewCard: View {
    let index: Int
    let cluster: [DocumentChunk]
    let color: Color
    let docNameProvider: @MainActor (DocumentChunk) -> String

    private var representativeDocName: String? {
        guard let chunk = cluster.first else { return nil }
        return docNameProvider(chunk)
    }

    private var snippet: String {
        guard let chunk = cluster.first else { return "" }
        let trimmed = chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 180 {
            return String(trimmed.prefix(180)) + "…"
        }
        return trimmed
    }

    private var docCounts: [(String, Int)] {
        Dictionary(grouping: cluster, by: { docNameProvider($0) })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)

                Text("Topic \(index + 1)")
                    .font(.headline)

                Spacer()

                Text("\(cluster.count) chunks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let docName = representativeDocName {
                Text(docName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !docCounts.isEmpty {
                Divider()
                    .padding(.vertical, DSSpacing.xs)

                HStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(Array(docCounts.prefix(3)), id: \.0) { item in
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(item.0)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .lineLimit(2)
                            Text("\(item.1) chunks")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

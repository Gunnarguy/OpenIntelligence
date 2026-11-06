//
//  EmbeddingSpaceRenderer+Stats.swift
//  OpenIntelligence
//
//  Part of EmbeddingSpaceRenderer, moved from Embedding3DView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI
import Charts
import Spatial
#if canImport(SceneKit)
import SceneKit
import QuartzCore

extension EmbeddingSpaceRenderer {
    // MARK: - Embedding Space Stats Helpers

    struct EmbeddingStatMini: View {
        let label: String
        let value: String
        let icon: String
        var color: Color = DSColors.accent

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: icon)
                        .scaledFont(size: 10)
                        .foregroundStyle(color)
                    Text(label)
                        .scaledFont(size: 9, weight: .medium)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .scaledFont(size: 13, weight: .bold, design: .monospaced)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                    .fill(color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
    }

    struct ProjectionDetailRow: View {
        let label: String
        let value: String
        var valueColor: Color = .primary

        var body: some View {
            HStack {
                Text(label)
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .scaledFont(size: 11, weight: .medium, design: .monospaced)
                    .foregroundStyle(valueColor)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(DSColors.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    private struct DistributionBar: View {
        let values: [Double]
        let maxValue: Double
        let color: Color

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let height = maxValue > 0 ? (value / maxValue) * geometry.size.height : 0
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(color.opacity(0.3 + 0.7 * (value / max(maxValue, 1))))
                            .frame(width: max(2, geometry.size.width / CGFloat(values.count) - 1), height: height)
                            .offset(y: geometry.size.height - height)
                    }
                }
            }
        }
    }

    private struct VectorSpaceIndicator: View {
        let coverage: Double // 0-1
        let sparsity: Double // 0-1

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Vector Space Health")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: DSSpacing.md) {
                    // Coverage meter
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Coverage")
                            .scaledFont(size: 9)
                            .foregroundStyle(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                    .fill(Color.secondary.opacity(0.2))
                                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                    .fill(coverageColor)
                                    .frame(width: geo.size.width * coverage)
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.1f%%", coverage * 100))
                            .scaledFont(size: 9, design: .monospaced)
                    }

                    // Density meter
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Density")
                            .scaledFont(size: 9)
                            .foregroundStyle(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                    .fill(Color.secondary.opacity(0.2))
                                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                    .fill(densityColor)
                                    .frame(width: geo.size.width * (1 - sparsity))
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.1f%%", (1 - sparsity) * 100))
                            .scaledFont(size: 9, design: .monospaced)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .background(DSColors.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }

        private var coverageColor: Color {
            if coverage > 0.8 { return .green }
            if coverage > 0.5 { return .orange }
            return .orange
        }

        private var densityColor: Color {
            let density = 1 - sparsity
            if density > 0.7 { return .green }
            if density > 0.4 { return DSColors.accent }
            return .secondary
        }
    }

    @ViewBuilder
    var legendSection: some View {
        if !legendItems.isEmpty {
            HStack {
                LegendChipsView(
                    items: legendItems,
                    selectedDocFilters: $selectedDocFilters,
                    totalPoints: totalPoints
                )
                InfoButtonView(
                    title: "Document Legend",
                    explanation: "Each color represents a different document in the active library. The numbers show how many points from that document are included in the current sample, and the percentage of the total points they represent. Tap a document to toggle it on or off in the 3D view."
                )
                .padding(.trailing, DSSpacing.lg)
            }
        }
    }

    // Extracted legend chips to reduce type-checking complexity
    struct LegendChipsView: View {
        let items: [VizLegendItem]
        @Binding var selectedDocFilters: Set<UUID>
        let totalPoints: Int

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(items, id: \.id) { item in
                        LegendChip(
                            item: item,
                            selected: selectedDocFilters.isEmpty || selectedDocFilters.contains(item.docId),
                            totalPoints: totalPoints
                        )
                        .onTapGesture {
                            toggle(item.docId)
                        }
                    }
                }
                .padding(.leading, DSSpacing.lg)
            }
        }

        private func toggle(_ id: UUID) {
            if selectedDocFilters.isEmpty {
                selectedDocFilters = Set(items.map { $0.docId })
            }
            if selectedDocFilters.contains(id) {
                selectedDocFilters.remove(id)
            } else {
                selectedDocFilters.insert(id)
            }
            if selectedDocFilters.isEmpty {
                // keep empty to mean "all"
            }
        }
    }

    struct LegendChip: View {
        let item: VizLegendItem
        let selected: Bool
        let totalPoints: Int

        private var pctStr: String {
            totalPoints > 0
                ? String(format: "%.0f%%", (Double(item.count) / Double(totalPoints)) * 100.0)
                : "0%"
        }

        var body: some View {
            HStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text("\(item.name) • \(item.count) • \(pctStr)")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.vertical, DSSpacing.xs)
            .padding(.horizontal, DSSpacing.sm)
            .background(DSColors.surface.opacity(selected ? 0.9 : 0.4))
            .overlay(
                Capsule()
                    .stroke(selected ? DSColors.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
    }

    struct AnnotationPopoverLayer: View {
        let labels: [PointAnnotationLabel]
        let focusMode: Bool

        var body: some View {
            GeometryReader { proxy in
                ForEach(labels) { label in
                    AnnotationBubble(label: label)
                        .position(
                            x: proxy.size.width * label.normalizedX,
                            y: proxy.size.height * (1 - label.normalizedY)
                        )
                        .scaleEffect(depthScale(label.depthHint))
                        .opacity(depthOpacity(label.depthHint, score: label.score))
                        .animation(DSAnimations.gentleSpring, value: label.id)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(Double(label.depthHint))
                }
            }
            .allowsHitTesting(false)
        }

        private func depthScale(_ depth: CGFloat) -> CGFloat {
            // Subtle depth parallax: closer = slightly larger
            let base = focusMode ? 1.0 : 0.98
            return base + (depth * 0.08)
        }

        private func depthOpacity(_ depth: CGFloat, score: Double) -> Double {
            // Keep labels readable - minimum 0.8 opacity
            let depthFade = 0.85 + (depth * 0.15)
            let scoreFade = 0.85 + (score * 0.15)
            return min(depthFade, scoreFade)
        }
    }

    struct AnnotationBubble: View {
        let label: PointAnnotationLabel

        private var keywordTag: String? {
            label.keywords.first
        }

        var body: some View {
            HStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(label.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: label.accent.opacity(0.5), radius: 2, x: 0, y: 0)

                Text(label.title)
                    .scaledFont(size: 11, weight: .semibold, design: .rounded)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let keyword = keywordTag {
                    Text("·")
                        .scaledFont(size: 9, weight: .medium)
                        .foregroundStyle(.secondary)
                    Text(keyword)
                        .scaledFont(size: 10, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(label.accent.opacity(0.4), lineWidth: 0.5)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
    }

    struct InsightCard: View {
        let insight: EmbeddingInsight

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: insight.icon)
                        .foregroundStyle(insight.accent)
                    Text(insight.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Text(insight.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpacing.md)
            .background(DSColors.background)
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(insight.accent.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
    }

// MARK: - Filtering

    func filteredArrays() -> ([SCNVector3], [PlatformColor]) {
        guard !points.isEmpty else { return ([], []) }
        // If no explicit filters, return all
        if selectedDocFilters.isEmpty {
            return (points, pointColorsUI)
        }
        var fp: [SCNVector3] = []
        var fc: [PlatformColor] = []
        fp.reserveCapacity(points.count)
        fc.reserveCapacity(pointColorsUI.count)
        for i in 0..<points.count {
            if i < allDocIdsForPoints.count, selectedDocFilters.contains(allDocIdsForPoints[i]) {
                fp.append(points[i])
                fc.append(pointColorsUI[i])
            }
        }
        return (fp, fc)
    }

    /// Translate the current sample into approachable "Atlas-style" insights.
    func buildInsights(
        sampledPoints: Int,
        chunkCount: Int,
        docCounts: [UUID: Int],
        docNames: [UUID: String]
    ) -> [EmbeddingInsight] {
        var cards: [EmbeddingInsight] = []
        let safeTotal = max(sampledPoints, 1)

        if chunkCount > 0 {
            let ratio = Double(sampledPoints) / Double(max(chunkCount, 1))
            let pct = String(format: "%.0f%%", ratio * 100)
            if ratio < 0.2 {
                cards.append(
                    EmbeddingInsight(
                        icon: "gauge.low",
                        title: "Light sample",
                        detail: "Only \(pct) of the library is visible—raise the point cap for broader context.",
                        accent: .orange
                    )
                )
            } else if ratio > 0.6 {
                cards.append(
                    EmbeddingInsight(
                        icon: "sparkles",
                        title: "Rich coverage",
                        detail: "Most of the library is represented. Try t-SNE or UMAP to stress-test cluster separation.",
                        accent: .green
                    )
                )
            }
        }

        if let dominant = docCounts.max(by: { $0.value < $1.value }), dominant.value > 0 {
            let docName = docNames[dominant.key] ?? "Document"
            let pct = String(format: "%.0f%%", (Double(dominant.value) / Double(safeTotal)) * 100)
            cards.append(
                EmbeddingInsight(
                    icon: "doc.text.magnifyingglass",
                    title: "\(docName) dominates",
                    detail: "\(pct) of sampled points come from this source—toggle legend chips to verify balance.",
                    accent: .purple
                )
            )
        }

        if documentCount > 0 {
            let docRatio = Double(docCounts.count) / Double(max(documentCount, 1))
            let pct = String(format: "%.0f%%", docRatio * 100)
            if docRatio < 0.5 {
                cards.append(
                    EmbeddingInsight(
                        icon: "rectangle.3.offgrid",
                        title: "Limited document mix",
                        detail: "Only \(pct) of docs appear in this sample. Consider refreshing or increasing the cap.",
                        accent: .pink
                    )
                )
            } else {
                cards.append(
                    EmbeddingInsight(
                        icon: "link.circle",
                        title: "Healthy coverage",
                        detail: "\(pct) of docs are represented—use filters to focus on a storyline.",
                        accent: .blue
                    )
                )
            }
        }

        cards.append(
            EmbeddingInsight(
                icon: "cube.transparent",
                title: "\(projectionMethod.rawValue) focus",
                detail: projectionExplainer,
                accent: Color.accentColor
            )
        )

        return Array(cards.prefix(4))
    }

    /// Result must match `Array.min()`/`Array.max()` semantics exactly: comparisons
    /// use strict `<`/`>` seeded from the first element, so a NaN at index 0 propagates
    /// for that lane and a NaN at any later index is ignored. `count` is clamped to
    /// `coords.count`; returns nil when no elements are in range.
    /// nonisolated is safe: pure function over Sendable value types with no shared state.
    nonisolated static func normalizationBounds(
        coords: [SIMD3<Float>],
        count: Int
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        let limit = min(count, coords.count)
        guard limit > 0 else { return nil }
        var minBound = coords[0]
        var maxBound = coords[0]
        for index in 1..<limit {
            let coord = coords[index]
            if coord.x < minBound.x {
                minBound.x = coord.x
            } else if coord.x > maxBound.x {
                maxBound.x = coord.x
            }
            if coord.y < minBound.y {
                minBound.y = coord.y
            } else if coord.y > maxBound.y {
                maxBound.y = coord.y
            }
            if coord.z < minBound.z {
                minBound.z = coord.z
            } else if coord.z > maxBound.z {
                maxBound.z = coord.z
            }
        }
        return (min: minBound, max: maxBound)
    }

    func buildAnnotationLabels(
        chunks: [DocumentChunk],
        coords: [SIMD3<Float>],
        docIds: [UUID],
        docNames: [UUID: String],
        colorByDoc: [UUID: PlatformColor],
        limit: Int
    ) -> [PointAnnotationLabel] {
        guard limit > 0 else { return [] }
        let count = min(chunks.count, coords.count, docIds.count)
        guard count > 0 else { return [] }

        guard let bounds = Self.normalizationBounds(coords: coords, count: count) else { return [] }
        let minX = bounds.min.x
        let maxX = bounds.max.x
        let minY = bounds.min.y
        let maxY = bounds.max.y
        let minZ = bounds.min.z
        let maxZ = bounds.max.z
        let spanX = max(maxX - minX, 0.001)
        let spanY = max(maxY - minY, 0.001)
        let spanZ = max(maxZ - minZ, 0.001)

        struct AnnotationCandidate {
            let docId: UUID
            let pointIndex: Int
            let title: String
            let detail: String
            let keywords: [String]
            let normalizedX: CGFloat
            let normalizedY: CGFloat
            let depthHint: CGFloat
            let accent: Color
            let score: Double
        }

        var candidates: [AnnotationCandidate] = []
        candidates.reserveCapacity(count)

        for index in 0..<count {
            let chunk = chunks[index]
            let coord = coords[index]
            let docId = docIds[index]
            let docName = docNames[docId] ?? "Document"
            let sectionTitle = chunk.metadata.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (sectionTitle?.isEmpty == false) ? sectionTitle! : docName
            let rawDetail = chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let keywords = chunk.metadata.keywords
            let detail: String
            if keywords.isEmpty {
                detail = rawDetail.isEmpty ? docName : String(rawDetail.prefix(64))
            } else {
                detail = keywords.prefix(3).joined(separator: " • ")
            }
            let densityScore = Double(chunk.metadata.semanticDensity ?? 0.45)
            let lengthScore = Double(min(chunk.metadata.wordCount, 420)) / 420.0
            let keywordScore = Double(min(keywords.count, 4)) * 0.08
            let numericBonus = chunk.metadata.hasNumericData ? 0.08 : 0
            let score = densityScore + lengthScore + keywordScore + numericBonus
            let baseX = Double(coord.x - minX) / Double(spanX)
            let baseY = Double(coord.y - minY) / Double(spanY)
            let jitterSeed = Double(abs(chunk.id.hashValue % 1000)) / 1000.0
            let jitterX = (jitterSeed - 0.5) * 0.08
            let jitterY = (0.5 - jitterSeed) * 0.06
            let normalizedX = CGFloat(min(max(baseX + jitterX, 0.08), 0.92))
            let normalizedY = CGFloat(min(max(baseY + jitterY, 0.08), 0.92))
            let depthBase = Double(coord.z - minZ) / Double(spanZ)
            let depthHint = CGFloat(min(max(depthBase, 0), 1))
            let accentColor: Color
            if let platformColor = colorByDoc[docId] {
                accentColor = Color(platformColor)
            } else {
                accentColor = .accentColor
            }
            let candidate = AnnotationCandidate(
                docId: docId,
                pointIndex: index,
                title: title,
                detail: detail,
                keywords: keywords,
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                depthHint: depthHint,
                accent: accentColor,
                score: max(score, 0.05)
            )
            candidates.append(candidate)
        }

        guard !candidates.isEmpty else { return [] }

        candidates.sort { $0.score > $1.score }
        var selected: [AnnotationCandidate] = []
        selected.reserveCapacity(limit)
        var usedDocs: Set<UUID> = []

        for candidate in candidates where selected.count < limit {
            if !usedDocs.contains(candidate.docId) {
                selected.append(candidate)
                usedDocs.insert(candidate.docId)
            }
        }
        if selected.count < limit {
            for candidate in candidates where selected.count < limit {
                if !selected.contains(where: { $0.pointIndex == candidate.pointIndex }) {
                    selected.append(candidate)
                }
            }
        }

        let maxScore = selected.map { $0.score }.max() ?? 1
        let safeMax = max(maxScore, 0.01)

        return selected.map { candidate in
            let normalizedScore = candidate.score / safeMax
            let safeScore = min(max(normalizedScore, 0), 1)
            return PointAnnotationLabel(
                pointIndex: candidate.pointIndex,
                docId: candidate.docId,
                title: candidate.title,
                detail: candidate.detail,
                keywords: candidate.keywords,
                normalizedX: candidate.normalizedX,
                normalizedY: candidate.normalizedY,
                depthHint: candidate.depthHint,
                accent: candidate.accent,
                score: safeScore
            )
        }
    }

}
#endif

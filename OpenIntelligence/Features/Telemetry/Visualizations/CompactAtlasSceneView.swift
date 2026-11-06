//
//  CompactAtlasSceneView.swift
//  OpenIntelligence
//
//  Moved unchanged from AdaptiveVisualizationsView.swift on 2026-11-05 (5.8 split).
//

import Charts
import SceneKit
import SwiftUI
import TipKit

// MARK: - Compact Atlas Scene View

/// A streamlined 3D embedding view designed for embedded use.
/// Shows topic-colored dots with cluster labels and full settings control.
struct CompactAtlasSceneView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    let profile: LibraryProfile
    let height: CGFloat

    // Settings passed from parent
    let projectionMethod: ProjectionMethodKind
    let autoRotate: Bool
    let depthCue: Bool
    let backgroundStyle: EmbeddingSceneBackgroundStyle
    /// Scene or chart (`AtlasDrawingStyle`, 5.7), and the scene's own two settings.
    let style: AtlasDrawingStyle
    let pointScale: Double
    let showLabels: Bool

    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var colors: [PlatformColor] = []
    @State private var sceneReloadToken = UUID()
    /// The chart's angle (5.7), held here so it outlasts the chart while the card reloads.
    @State private var pose: Chart3DPose = .default
    /// The library the points on screen are from, so another library's load clears them rather than drawing under
    /// its name.
    @State private var drawnLibrary: UUID?
    /// What the card last loaded (`AtlasContentKey`).
    @State private var loadedKey: AtlasContentKey?

    // Dynamic axis labels derived from content analysis
    @State private var dynamicAxisLabels: Embedding3DSceneView.AxisLabels = .placeholder
    /// The scene's cluster names in the map, and the box of cluster names over its corner (the Scene style).
    @State private var annotations: [Embedding3DSceneView.AnnotationData] = []
    @State private var legendItems: [TopicColorItem] = []
    // Where the scene is and where the cluster box and hint over it start, for its axis labels (`cardLabelInsets`).
    @State private var cardSceneFrame: CGRect = .zero
    @State private var cardChromeFrame: CGRect = .zero

    // A guard only: the passages arrive sampled to `RAGService.visualizationPassageLimit` (6,000) since 5.7.
    private let sampleLimit = 50000

    // The 3D chart draws its own points (`AtlasChart3D`); point size applies to the SceneKit scene only.
    private var sceneOptions: Embedding3DSceneView.SceneOptions {
        Embedding3DSceneView.SceneOptions(
            pointScale: style == .scene ? CGFloat(pointScale * AtlasSceneLabels.pointScale(for: points.count)) : 1,
            autoRotate: autoRotate,
            showAxes: true, // Always show axes for spatial reference
            showLines: true,
            depthCue: depthCue,
            backgroundStyle: backgroundStyle,
            projectionMethod: projectionMethod,
            axisLabels: dynamicAxisLabels
        )
    }

    var body: some View {
        ZStack {
            // The chart stays on screen while it reloads (5.7), so it keeps the angle it was turned to.
            if isLoading && points.isEmpty {
                loadingPlaceholder
            } else if points.isEmpty {
                emptyPlaceholder
            } else {
                sceneContent
                    .overlay(alignment: .topTrailing) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .padding(10)
                        }
                    }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        // One task keyed by the open library, the number of documents in every library once no import runs, and the
        // projection (`AtlasContentKey`, 5.7). Through 5.6 there were two, one per key, so both loaded when the card
        // appeared, and an import that ended with the card on screen never showed in it. The key is recorded when a
        // load finishes, and an interrupted load is done again.
        .task(id: contentKey) {
            let key = contentKey
            guard !(key.onlyStartsAnImport(after: loadedKey) && !isLoading) else { return }
            if key.settlesFirst(after: loadedKey) {
                try? await Task.sleep(for: AtlasContentKey.settleDelay)
                guard !Task.isCancelled else { return }
            }
            await loadAndProject()
            if !Task.isCancelled { loadedKey = key }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.7))

            Text("Mapping semantic space…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "cube.transparent")
                .scaledFont(size: 36)
                .foregroundStyle(.white.opacity(0.4))

            Text("Add documents to visualize")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
    }

    /// The scene with its labels, the box of cluster names and the hint over its lower corner, as through 5.6; or the
    /// chart and under it what its axes run between (5.7), with the chips under the card naming the clusters.
    @ViewBuilder
    private var sceneContent: some View {
        if style == .scene {
            ZStack(alignment: .bottomLeading) {
                Embedding3DSceneView(
                    points: points,
                    colors: colors,
                    options: sceneOptions,
                    reloadToken: sceneReloadToken,
                    annotations: showLabels ? annotations : [],
                    drawsScene: true,
                    labelInsets: cardLabelInsets
                )
                .onGeometryChange(for: CGRect.self, of: { Fullscreen3DAtlasView.fullFrame($0) }) { cardSceneFrame = $0 }

                VStack(alignment: .leading, spacing: 0) {
                    topicLegendOverlay
                    sceneHintOverlay
                }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { cardChromeFrame = $0 }
            }
        } else {
            chartContent
        }
    }

    /// The box the cluster names and the hint take at the card's lower left, which its axis labels keep clear of (5.7).
    /// From 5.8 only where a label would cover it: through 5.7 it was a band across the whole bottom, which held a label
    /// at the middle of the card, nowhere near the box, above the box's top (the owner, 2026-11-03).
    private var cardLabelInsets: AxisLabelInsets {
        Self.cardLabelInsets(scene: cardSceneFrame, chrome: cardChromeFrame)
    }

    /// `chrome`, in the same coordinates as `scene`, as a box in the scene's view units: -1 to 1 across and up.
    nonisolated static func cardLabelInsets(scene: CGRect, chrome: CGRect) -> AxisLabelInsets {
        guard scene.width > 0, scene.height > 0, chrome.width > 0, chrome.height > 0 else { return .zero }
        let box = scene.intersection(chrome)
        guard !box.isNull, box.width > 0, box.height > 0 else { return .zero }
        let left = -1 + 2 * (box.minX - scene.minX) / scene.width
        let right = -1 + 2 * (box.maxX - scene.minX) / scene.width
        let top = 1 - 2 * (box.minY - scene.minY) / scene.height
        let bottom = 1 - 2 * (box.maxY - scene.minY) / scene.height
        return AxisLabelInsets(boxes: [
            AxisLabelPlacement(
                center: SIMD2(Float(left + right) / 2, Float(top + bottom) / 2),
                halfSize: SIMD2(Float(right - left) / 2, Float(top - bottom) / 2))
        ])
    }

    /// Shows what each color represents (Atlas canvas overlay keeps fixed sizes so it fits inside the compact 3D scene)
    private var topicLegendOverlay: some View {
        Group {
            if !legendItems.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    ForEach(legendItems.prefix(5), id: \.name) { item in
                        HStack(spacing: DSSpacing.xs) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)

                            Text(item.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(DSSpacing.xs)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
            }
        }
    }

    private struct TopicColorItem: Hashable {
        let name: String
        let color: Color
        let count: Int
    }

    /// Small overlay explaining what the user is looking at (Atlas canvas overlay keeps fixed sizes)
    private var sceneHintOverlay: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "hand.draw")
                .font(.system(size: 8))
            Text("Drag to rotate • Pinch to zoom")
                .font(.system(size: 8))
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(DSSpacing.xs)
    }

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Embedding3DSceneView(
                points: points,
                colors: colors,
                options: sceneOptions,
                reloadToken: sceneReloadToken,
                annotations: [],
                pose: $pose
            )
            AtlasAxisKey(labels: dynamicAxisLabels, lineLimit: 1)
                .padding(.horizontal, DSSpacing.sm)
            // A 3D chart turns with a drag and does not zoom with a pinch (probe, iOS 27 Simulator, 2026-10-19).
            Label("Drag to turn", systemImage: "hand.draw")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xs)
        }
    }

    // MARK: - Data Loading

    /// The open library, the number of documents in every library once no import runs, and the projection
    /// (`AtlasContentKey`).
    private var contentKey: AtlasContentKey {
        AtlasContentKey(
            containerId: containerService.activeContainerId, documentCount: ragService.documents.count,
            importing: ragService.isProcessing, variant: projectionMethod.rawValue)
    }

    private func loadAndProject() async {
        // Through 5.6 this also read the corpus terms and phrases, which nothing on the card showed (5.7).
        let activeId = containerService.activeContainerId
        await MainActor.run {
            isLoading = true
            // Another library (5.7): the old map would sit under the new library's name until this one is drawn.
            if drawnLibrary != activeId {
                points = []
                colors = []
                annotations = []
                legendItems = []
            }
        }

        let allChunks = await ragService.allChunksForActiveContainer()

        guard !allChunks.isEmpty else {
            // Not when another load has taken this one's place (5.7): it draws, and these writes would leave its view
            // empty, or skip its reload during an import.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = []
                colors = []
                isLoading = false
            }
            return
        }

        // Sample chunks (stratified by document)
        let sampledChunks = sampleChunks(allChunks)
        let embeddings = sampledChunks.map { $0.embedding }

        guard !embeddings.isEmpty else {
            // Not when another load has taken this one's place (5.7): it draws, and these writes would leave its view
            // empty, or skip its reload during an import.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = []
                colors = []
                isLoading = false
            }
            return
        }

        // Project to 3D — use deterministic seed (not .hashValue which is randomized per launch)
        let seed = deterministicSeed(from: containerService.activeContainerId.uuidString)
        // Off the main actor: UMAP and t-SNE take seconds on a few thousand passages (`ProjectionService`).
        let method = projectionMethod
        let coords3D = await Task.detached(priority: .userInitiated) {
            ProjectionService.shared.project3D(embeddings: embeddings, method: method, seed: seed)
        }.value

        // === CLUSTER MEMBERSHIP & NAMING ===
        // Cluster membership derives deterministically from embeddings via k-means.
        // Cluster names derive solely from the words of the passages in the cluster.
        let texts = sampledChunks.map { $0.content }
        // Splitting 6,000 passages into words and clustering their vectors is seconds of work on
        // a phone, so it is done off the main actor; only the results come back to it.
        // The axes' words are read here too (5.7): they were six passes over the sample on the main actor.
        // What each passage belongs to (5.7): its document and its section heading, so an axis end or a cluster is named
        // for the part of the library it is (`AtlasLabeling.PassageSources`).
        let documentNames = await MainActor.run {
            Dictionary(
                ragService.documents.map { ($0.id, AtlasLabeling.shortDocumentName($0.filename)) },
                uniquingKeysWith: { first, _ in first })
        }
        let sources = AtlasLabeling.PassageSources(
            groups: sampledChunks.map { documentNames[$0.documentId] },
            sections: sampledChunks.map(\.metadata.sectionTitle))
        let (clusterIndices, clusterNames, axisEnds) = await Task.detached(priority: .userInitiated) {
            // The word classes of the passages' languages first (5.7), so an adverb names nothing in them.
            await AtlasLabeling.loadWordClasses(for: texts)
            let terms = texts.map { AtlasLabeling.terms(in: $0) }
            let indices = AtlasLabeling.kMeans(embeddings: embeddings)
            let names = AtlasLabeling.clusterNames(
                texts: texts,
                clusterMembership: indices,
                precomputedTerms: terms,
                sources: sources
            )
            return (
                indices, names,
                AtlasLabeling.axisLabels(coords: coords3D, texts: texts, passageTerms: terms, sources: sources)
            )
        }.value
        AtlasLabeling.recordLabels(
            view: "card", scope: "library", library: activeId, passages: texts.count,
            clusterNames: clusterNames, axisEnds: axisEnds)

        let palette: [PlatformColor] = [
            PlatformColor(.blue),
            PlatformColor(.purple),
            PlatformColor(.green),
            PlatformColor(.orange),
            PlatformColor(.pink),
            PlatformColor(.teal)
        ]

        var mappedColors: [PlatformColor] = []
        mappedColors.reserveCapacity(sampledChunks.count)

        for i in sampledChunks.indices {
            let c = (i < clusterIndices.count && clusterIndices[i] >= 0 && clusterIndices[i] < clusterNames.count) ? clusterIndices[i] : 0
            mappedColors.append(palette[c % palette.count])
        }

        // Use ACTUAL PCA/UMAP coordinates - scale them properly for viewing
        // This preserves natural clustering and semantic structure!
        let scaledPoints = scalePointsForViewing(coords3D)

        // The scene's cluster names in the map and its box of names (the Scene style). The chart shows neither: the
        // chips under the card name the clusters (`atlasTopicLegend`).
        let clusterAnnotations = AtlasSceneLabels.annotations(
            coords: coords3D, groups: clusterIndices, names: clusterNames, colors: palette,
            detailLevel: { $0 > 50 ? 2 : ($0 > 20 ? 1 : 0) })
        var clusterCounts = Array(repeating: 0, count: clusterNames.count)
        for c in clusterIndices where c >= 0 && c < clusterCounts.count { clusterCounts[c] += 1 }
        let clusterLegend: [TopicColorItem] = clusterNames.indices.compactMap { c in
            clusterCounts[c] > 0
                ? TopicColorItem(name: clusterNames[c], color: Color(palette[c % palette.count]), count: clusterCounts[c])
                : nil
        }

        // Each end of each axis named by the words of the passages there (5.7).
        let axisLabels = Embedding3DSceneView.AxisLabels(ends: axisEnds)

        // A load for another method or library started while this one worked: that one draws, not this.
        // `.task(id: contentKey)` cancels this one when its key changes.
        guard !Task.isCancelled, activeId == containerService.activeContainerId else { return }

        await MainActor.run {
            points = scaledPoints
            colors = mappedColors
            annotations = clusterAnnotations
            legendItems = clusterLegend
            dynamicAxisLabels = axisLabels
            drawnLibrary = activeId
            sceneReloadToken = UUID()
            isLoading = false
        }
    }

    /// Scales actual PCA/UMAP coordinates for proper 3D viewing
    /// Preserves natural clustering and semantic structure (like Apple Embedding Atlas)
    private func scalePointsForViewing(_ coords: [SIMD3<Float>]) -> [SCNVector3] {
        guard !coords.isEmpty else { return [] }

        // Find bounds
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

        for c in coords {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
            minZ = min(minZ, c.z); maxZ = max(maxZ, c.z)
        }

        // Calculate center and span
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2

        let spanX = max(maxX - minX, 0.0001)
        let spanY = max(maxY - minY, 0.0001)
        let spanZ = max(maxZ - minZ, 0.0001)
        let maxSpan = max(spanX, max(spanY, spanZ))

        // Target viewing size - fills scene nicely with room for labels
        let targetSize: Float = 4.5
        let scale = targetSize / maxSpan

        var result: [SCNVector3] = []
        result.reserveCapacity(coords.count)

        for c in coords {
            // Center at origin and scale uniformly to preserve shape
            let x = (c.x - centerX) * scale
            let y = (c.y - centerY) * scale
            let z = (c.z - centerZ) * scale

            // Small jitter to prevent exact overlaps (rare edge case)
            let seed = UInt32(result.count)
            let jitterX = (Float((seed &* 1_103_515_245 &+ 12345) % 10000) / 20000.0 - 0.025) * 0.02
            let jitterY = (Float((seed &* 1_664_525 &+ 1_013_904_223) % 10000) / 20000.0 - 0.025) * 0.02
            let jitterZ = (Float((seed &* 22_695_477 &+ 1) % 10000) / 20000.0 - 0.025) * 0.02

            result.append(SCNVector3(x + jitterX, y + jitterY, z + jitterZ))
        }

        return result
    }





    // MARK: - Sampling

    private func sampleChunks(_ chunks: [DocumentChunk]) -> [DocumentChunk] {
        guard chunks.count > sampleLimit else { return chunks }

        var byDoc: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks {
            byDoc[chunk.documentId, default: []].append(chunk)
        }

        let docCount = byDoc.count
        let perDocQuota = max(1, sampleLimit / max(docCount, 1))

        var sampled: [DocumentChunk] = []
        sampled.reserveCapacity(sampleLimit)

        let seed = deterministicSeed(from: containerService.activeContainerId.uuidString)
        var prng = VizLCG(seed: seed)

        let sortedDocIds = byDoc.keys.sorted { $0.uuidString < $1.uuidString }
        for docId in sortedDocIds {
            guard let docChunks = byDoc[docId] else { continue }
            if docChunks.count > perDocQuota {
                var indices = Array(0 ..< docChunks.count)
                for i in stride(from: indices.count - 1, through: 1, by: -1) {
                    let j = Int(prng.next() % UInt64(i + 1))
                    if i != j { indices.swapAt(i, j) }
                }
                for idx in indices.prefix(perDocQuota) {
                    sampled.append(docChunks[idx])
                }
            } else {
                sampled.append(contentsOf: docChunks)
            }
        }

        if sampled.count > sampleLimit {
            var order = Array(0 ..< sampled.count)
            for i in stride(from: order.count - 1, through: 1, by: -1) {
                let j = Int(prng.next() % UInt64(i + 1))
                if i != j { order.swapAt(i, j) }
            }
            sampled = order.prefix(sampleLimit).map { sampled[$0] }
        }

        return sampled
    }
}

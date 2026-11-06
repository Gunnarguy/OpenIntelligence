//
//  EmbeddingSpaceRenderer+Data.swift
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
    // MARK: - Data + Projection

    func loadAndProject() async {
        // Cancel any ongoing load
        loadTask?.cancel()
        loadTask = Task {
            await MainActor.run {
                isLoading = true
                errorText = nil
                annotationLabels = []
            }
            // Much higher limit for rich annotations - we need these for keyword/section extraction
            let annotationLimit = await MainActor.run { focusMode ? 50 : 30 }

            // === LOAD FTS5 CORPUS INTELLIGENCE ===
            // Get real terms and phrases from the SQLite FTS5 index for this container
            let activeId = containerService.activeContainerId
            async let topTermsTask = SQLiteFullTextService.shared.getTopTermsForContainer(containerId: activeId, limit: 100)
            async let keyPhrasesTask = SQLiteFullTextService.shared.getKeyPhrasesForContainer(containerId: activeId, limit: 30)

            let (topTermsResult, keyPhrasesResult) = await (topTermsTask, keyPhrasesTask)

            // Store FTS5 terms for use in labels (on main actor)
            await MainActor.run {
                self.fts5TopTerms = topTermsResult.map { $0.term }
                self.fts5KeyPhrases = keyPhrasesResult
            }

            // Snapshot documents to resolve names and filter by active container
            let docsSnapshot = await MainActor.run { ragService.documents }
            let defaultId = containerService.containers.first?.id
            let activeDocs = docsSnapshot.filter { doc in
                if let cid = doc.containerId {
                    return cid == activeId
                } else {
                    // Legacy docs (no containerId) belong to the default container (first in list)
                    return activeId == defaultId
                }
            }
            let activeDocIdsSet = Set(activeDocs.map { $0.id })
            let nameById: [UUID: String] = Dictionary(uniqueKeysWithValues: activeDocs.map { ($0.id, $0.filename) })

            // Pull chunks from the active container's vector DB
            let allChunks = await ragService.allChunksForActiveContainer()
            if Task.isCancelled { return }
            guard !allChunks.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                    self.insights = []
                    self.annotationLabels = []
                }
                return
            }
            // Filter chunks to documents visible in current container snapshot (defensive)
            let filtered = allChunks.filter { activeDocIdsSet.contains($0.documentId) }
            if Task.isCancelled { return }
            guard !filtered.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                    self.insights = []
                    self.annotationLabels = []
                }
                return
            }

            // Group by document for stratified downsampling
            var chunksByDoc: [UUID: [DocumentChunk]] = [:]
            for c in filtered {
                chunksByDoc[c.documentId, default: []].append(c)
            }

            // Allocate fair share of sampleLimit across docs
            let docIds = Array(chunksByDoc.keys)
            let perDocQuota = max(1, sampleLimit / max(docIds.count, 1))
            var sampledEmbeddings: [[Float]] = []
            var sampledDocIds: [UUID] = []
            var sampledChunks: [DocumentChunk] = []
            let capacity = min(sampleLimit, filtered.count)
            sampledEmbeddings.reserveCapacity(capacity)
            sampledDocIds.reserveCapacity(capacity)
            sampledChunks.reserveCapacity(capacity)

            // Deterministic sampling per containerId
            // Use deterministic seed (not .hashValue which is randomized per process launch)
            let rngSeed = deterministicSeed(from: activeId.uuidString)
            var prng = VizLCG(seed: rngSeed)

            for did in docIds {
                let arr = chunksByDoc[did] ?? []
                if arr.count > perDocQuota {
                    var indices = Array(0..<arr.count)
                    // shuffle deterministically
                    for i in stride(from: indices.count - 1, through: 1, by: -1) {
                        let j = Int(prng.next() % UInt64(i + 1))
                        if i != j { indices.swapAt(i, j) }
                    }
                    for idx in indices.prefix(perDocQuota) {
                        let chunk = arr[idx]
                        sampledEmbeddings.append(chunk.embedding)
                        sampledDocIds.append(did)
                        sampledChunks.append(chunk)
                    }
                } else {
                    for c in arr {
                        sampledEmbeddings.append(c.embedding)
                        sampledDocIds.append(did)
                        sampledChunks.append(c)
                    }
                }
            }
            // Global cap if above sampleLimit
            if sampledEmbeddings.count > sampleLimit {
                var order = Array(0..<sampledEmbeddings.count)
                for i in stride(from: order.count - 1, through: 1, by: -1) {
                    let j = Int(prng.next() % UInt64(i + 1))
                    if i != j { order.swapAt(i, j) }
                }
                order = Array(order.prefix(sampleLimit))
                var newEmb: [[Float]] = []
                var newIds: [UUID] = []
                var newChunks: [DocumentChunk] = []
                newEmb.reserveCapacity(order.count)
                newIds.reserveCapacity(order.count)
                newChunks.reserveCapacity(order.count)
                for idx in order {
                    newEmb.append(sampledEmbeddings[idx])
                    newIds.append(sampledDocIds[idx])
                    newChunks.append(sampledChunks[idx])
                }
                sampledEmbeddings = newEmb
                sampledDocIds = newIds
                sampledChunks = newChunks
            }

            // Validate dims while keeping identifiers aligned
            var filteredEmbeddings: [[Float]] = []
            var filteredDocIds: [UUID] = []
            var filteredChunks: [DocumentChunk] = []
            filteredEmbeddings.reserveCapacity(sampledEmbeddings.count)
            filteredDocIds.reserveCapacity(sampledDocIds.count)
            filteredChunks.reserveCapacity(sampledChunks.count)
            for index in 0..<sampledEmbeddings.count {
                guard index < sampledDocIds.count, index < sampledChunks.count else { continue }
                let embedding = sampledEmbeddings[index]
                guard !embedding.isEmpty else { continue }
                filteredEmbeddings.append(embedding)
                filteredDocIds.append(sampledDocIds[index])
                filteredChunks.append(sampledChunks[index])
            }
            sampledEmbeddings = filteredEmbeddings
            sampledDocIds = filteredDocIds
            sampledChunks = filteredChunks
            if Task.isCancelled { return }
            guard !sampledEmbeddings.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                    self.insights = []
                    self.annotationLabels = []
                }
                return
            }

            // Projection & caching
            let methodKind: ProjectionMethodKind
            switch projectionMethod {
            case .pca:
                methodKind = .pca
            case .tsne:
                methodKind = .tsne
            case .umap:
                methodKind = .umap
            }
            let cacheKey = ProjectionCacheKey(
                containerId: activeId,
                method: methodKind.rawValue,
                sampleLimit: sampleLimit,
                seed: rngSeed
            )

            var coords3D: [SIMD3<Float>]
            if let cached = ProjectionCache.shared.get(cacheKey),
               cached.coords.count == sampledEmbeddings.count {
                coords3D = cached.coords
            } else {
                // Off the main actor: UMAP and t-SNE take seconds on a few thousand passages (`ProjectionService`).
                let toProject = sampledEmbeddings
                let method = methodKind
                let seed = rngSeed
                coords3D = await Task.detached(priority: .userInitiated) {
                    ProjectionService.shared.project3D(embeddings: toProject, method: method, seed: seed)
                }.value
                // Build counts per doc for legend and cache
                var perDocCounts: [UUID: Int] = [:]
                for did in sampledDocIds {
                    perDocCounts[did, default: 0] += 1
                }
                let entry = ProjectionCacheEntry(
                    coords: coords3D,
                    docIds: sampledDocIds,
                    totalPoints: coords3D.count,
                    perDocCounts: perDocCounts,
                    timestamp: Date()
                )
                ProjectionCache.shared.set(entry, for: cacheKey)
            }
            if Task.isCancelled { return }

            // Color mapping per document (deterministic by sorted doc ids)
            let palette = EmbeddingColorPalette.makePalette(count: docIds.count)
            var colorByDoc: [UUID: PlatformColor] = [:]
            let sortedDocIds = docIds.sorted { $0.uuidString < $1.uuidString }
            for (i, did) in sortedDocIds.enumerated() {
                let pcol = palette[i % palette.count]
                colorByDoc[did] = pcol
            }

            // Legend build with counts
            var counts: [UUID: Int] = [:]
            for did in sampledDocIds { counts[did, default: 0] += 1 }
            var legend: [VizLegendItem] = []
            for did in sortedDocIds {
                let uiColor = colorByDoc[did] ?? EmbeddingColorPalette.fallback
                let swiftUIColor = Color(uiColor)
                let name = nameById[did] ?? "Unknown"
                let cnt = counts[did] ?? 0
                legend.append(VizLegendItem(docId: did, name: name, color: swiftUIColor, count: cnt))
            }

            // Build SceneKit vectors and color list aligned
            // Normalize to viewing cube (±1.0) and add jitter to reduce overlap
            let scnPoints: [SCNVector3] = normalizeToViewingCube(coords3D, jitterAmount: 0.08)
            let uiColors: [PlatformColor] = sampledDocIds.map { colorByDoc[$0] ?? EmbeddingColorPalette.fallback }
            let generatedInsights = buildInsights(
                sampledPoints: scnPoints.count,
                chunkCount: chunkCount,
                docCounts: counts,
                docNames: nameById
            )
            let annotationSet = buildAnnotationLabels(
                chunks: sampledChunks,
                coords: coords3D,
                docIds: sampledDocIds,
                docNames: nameById,
                colorByDoc: colorByDoc,
                limit: annotationLimit
            )

            // Extract chunk texts and doc names for tap-to-inspect feature
            let chunkTextList = sampledChunks.map { $0.text }
            let chunkDocNameList = sampledDocIds.map { nameById[$0] ?? "Unknown" }

            // The same axis words as the Knowledge Atlas (5.7), read off the main actor.
            let axisTexts = sampledChunks.map(\.content)
            let axisCoords = coords3D
            let axisEnds = await Task.detached(priority: .userInitiated) {
                await AtlasLabeling.loadWordClasses(for: axisTexts)
                return AtlasLabeling.axisLabels(coords: axisCoords, texts: axisTexts)
            }.value
            let axisLabels = Embedding3DSceneView.AxisLabels(ends: axisEnds)

            await MainActor.run {
                self.points = scnPoints
                self.pointColorsUI = uiColors
                self.legendItems = legend
                self.allDocIdsForPoints = sampledDocIds
                self.totalPoints = scnPoints.count
                // Default: if no filters yet, treat as "all" selected by keeping set empty
                self.isLoading = false
                self.insights = generatedInsights
                self.annotationLabels = annotationSet
                // Store chunk data for tap-to-inspect and search
                self.chunkTexts = chunkTextList
                self.chunkDocNames = chunkDocNameList
                // Store content-derived axis labels
                self.dynamicAxisLabels = axisLabels
                // Auto-scale point size based on final count
                self.autoScalePointSize()
            }
        }
    }

    // MARK: - SampleLimit persistence

    func saveSampleLimit(_ value: Int) {
        let key = "viz.sampleLimit.\(containerService.activeContainerId.uuidString)"
        UserDefaults.standard.setValue(value, forKey: key)
    }

    func loadSampleLimitForActive() {
        let key = "viz.sampleLimit.\(containerService.activeContainerId.uuidString)"
        if let v = UserDefaults.standard.value(forKey: key) as? Int, sampleOptions.contains(v) {
            sampleLimit = v
        } else if let v = UserDefaults.standard.value(forKey: key) as? Int, v > 2000 {
            // 5,000 or "All" from before 5.7: the most the map draws now.
            sampleLimit = RAGService.visualizationPassageLimit
        } else {
            sampleLimit = 2000 // Higher default for full visibility
        }
    }
}
#endif

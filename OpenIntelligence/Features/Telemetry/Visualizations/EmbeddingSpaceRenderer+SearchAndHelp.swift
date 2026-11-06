//
//  EmbeddingSpaceRenderer+SearchAndHelp.swift
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
    // MARK: - Search & Help UI

    var helpButton: some View {
        Button {
            if showHelpTip {
                showHelpTip = false
            } else {
                showHelpTip = true
                // Auto-dismiss after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { showHelpTip = false }
                }
            }
        } label: {
            Image(systemName: showHelpTip ? "xmark.circle.fill" : "questionmark.circle")
                .scaledFont(size: 18, weight: .medium)
                .foregroundStyle(.white.opacity(0.7))
                .padding(DSSpacing.md)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial.opacity(showHelpTip ? 0.9 : 0.5))
                )
        }
        .padding(DSSpacing.md)
        .popover(isPresented: $showHelpTip, arrowEdge: .top) {
            gestureHelpContent
        }
    }

    private var gestureHelpContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Navigate Your Knowledge")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                helpRow(icon: "hand.draw", text: "Drag to rotate")
                helpRow(icon: "arrow.up.left.and.arrow.down.right", text: "Pinch to zoom")
                helpRow(icon: "hand.tap", text: "Tap a point for details")
                helpRow(icon: "magnifyingglass", text: "Search to highlight")
            }

            Divider()

            Text("Points close together = similar content")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.lg)
        .frame(width: 220)
    }

    private func helpRow(icon: String, text: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .scaledFont(size: 14)
                .foregroundStyle(DSColors.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    var searchBar: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))

            TextField("Search chunks...", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    highlightedPointIndices = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Button {
                withAnimation(DSAnimations.fastEase) { isSearching = false }
                searchQuery = ""
                highlightedPointIndices = []
            } label: {
                Text("Done")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 60)
        .padding(.top, DSSpacing.md)
    }

    var onboardingTip: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.orange)

            Text("Drag to explore • Pinch to zoom • Close points = similar ideas")
                .font(.caption)
                .foregroundStyle(.white)

            Button {
                withAnimation(DSAnimations.fastEase) {
                    hasSeenOnboarding = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            Capsule()
                .fill(.black.opacity(0.7))
        )
        .padding(.bottom, DSSpacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Detail card shown when a point is tapped
    func tappedPointDetailCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header with close button
            HStack {
                Label("Chunk \(index + 1)", systemImage: "doc.text.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    withAnimation(DSAnimations.fastEase) {
                        showPointDetail = false
                        tappedPointIndex = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(size: 20)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Document name
            if index < chunkDocNames.count {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(DSColors.accent)
                    Text(chunkDocNames[index])
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Chunk text preview
            if index < chunkTexts.count {
                Text(chunkTexts[index])
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Loading chunk data...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(DSSpacing.lg)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        )
    }

    private func performSearch() {
        // Search through chunk texts and highlight matching points
        guard !searchQuery.isEmpty else {
            highlightedPointIndices = []
            return
        }

        let query = searchQuery.lowercased()
        var matches: Set<Int> = []

        for (index, text) in chunkTexts.enumerated() {
            if text.lowercased().contains(query) {
                matches.insert(index)
            }
        }

        highlightedPointIndices = matches
        // Trigger scene reload to apply highlighting
        sceneReloadToken = UUID()
    }

    var tuningCard: some View {
        VStack(spacing: DSSpacing.md) {
            sampleOptionRow
            Divider().opacity(0.08)
            pointSizeRow
        }
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        .padding(.horizontal, DSSpacing.lg)
    }

    /// 500, 2K, 6K.
    private func sampleOptionLabel(_ option: Int) -> String {
        if option >= 1000 { return "\(option/1000)K" }
        return "\(option)"
    }

    private var sampleOptionRow: some View {
        HStack(spacing: DSSpacing.sm) {
            Text("Points")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(sampleOptions, id: \.self) { option in
                Button {
                    guard sampleLimit != option else { return }
                    sampleLimit = option
                    saveSampleLimit(option)
                    // Auto-scale point size based on count
                    autoScalePointSize()
                } label: {
                    Text(sampleOptionLabel(option))
                        .font(.caption2)
                        .fontWeight(sampleLimit == option ? .semibold : .regular)
                        .padding(.vertical, DSSpacing.xs)
                        .padding(.horizontal, DSSpacing.md)
                        .background(sampleLimit == option ? DSColors.accent.opacity(0.16) : DSColors.background)
                        .foregroundStyle(sampleLimit == option ? DSColors.accent : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            InfoButtonView(
                title: "Sampling",
                explanation: "How many passages the map draws, up to 6,000. A library with more is drawn from an even sample across all of it. More points draw smaller and can make turning the map slower."
            )
        }
    }

    /// Automatically scale point size based on point count for performance
    func autoScalePointSize() {
        // Scale inversely with point count: more points = smaller dots
        let targetPoints = min(totalPoints, sampleLimit)
        if targetPoints >= 10000 {
            pointScale = 0.6 // Tiny dots for massive datasets
        } else if targetPoints >= 5000 {
            pointScale = 0.7
        } else if targetPoints >= 2000 {
            pointScale = 0.85
        } else {
            pointScale = 1.0 // Normal size for smaller datasets
        }
    }

    private var pointSizeRow: some View {
        HStack(spacing: DSSpacing.md) {
            Label("Point size", systemImage: "circle.grid.cross")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $pointScale, in: 0.6...1.6, step: 0.1)

            Text(String(format: "%.1fx", pointScale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DSSpacing.tapTarget)
        }
    }

    var sceneOptions: Embedding3DSceneView.SceneOptions {
        // Convert EmbeddingSpaceView.ProjectionMethod to ProjectionMethodKind
        let methodKind: ProjectionMethodKind
        switch projectionMethod {
        case .pca: methodKind = .pca
        case .tsne: methodKind = .tsne
        case .umap: methodKind = .umap
        }
        return Embedding3DSceneView.SceneOptions(
            pointScale: CGFloat(pointScale),
            autoRotate: autoRotate,
            showAxes: showAxes,
            showLines: true,
            depthCue: depthCue,
            backgroundStyle: backgroundStyle,
            projectionMethod: methodKind,
            axisLabels: dynamicAxisLabels
        )
    }

    func buildSceneAnnotations() -> [Embedding3DSceneView.AnnotationData] {
        guard showClusterLabels, !points.isEmpty, !allDocIdsForPoints.isEmpty else { return [] }

        var result: [Embedding3DSceneView.AnnotationData] = []

        // === LAYER 1: Document Cluster Labels ===
        // Group points by document and create main cluster labels

        var docPointsMap: [UUID: [SCNVector3]] = [:]
        var docColorMap: [UUID: PlatformColor] = [:]
        var docPointIndices: [UUID: [Int]] = [:]

        for (index, point) in points.enumerated() {
            guard index < allDocIdsForPoints.count else { continue }
            let docId = allDocIdsForPoints[index]
            docPointsMap[docId, default: []].append(point)
            docPointIndices[docId, default: []].append(index)
            if docColorMap[docId] == nil, index < pointColorsUI.count {
                docColorMap[docId] = pointColorsUI[index]
            }
        }

        // Create main document cluster labels
        for legendItem in legendItems where legendItem.count > 0 {
            guard let clusterPoints = docPointsMap[legendItem.docId], !clusterPoints.isEmpty else { continue }

            // Compute centroid - but use DENSITY-WEIGHTED centroid for better visual accuracy
            // If points are scattered, find the densest region and weight toward it
            let centroid: SCNVector3
            if clusterPoints.count <= 3 {
                // Simple average for tiny clusters
                var sumX: Float = 0, sumY: Float = 0, sumZ: Float = 0
                for pt in clusterPoints {
                    sumX += Float(pt.x); sumY += Float(pt.y); sumZ += Float(pt.z)
                }
                let count = Float(clusterPoints.count)
                centroid = SCNVector3(xFloat: sumX / count, yFloat: sumY / count, zFloat: sumZ / count)
            } else if clusterPoints.count > 100 {
                // OPTIMIZATION: For large clusters, use grid-based density approximation O(n) instead of O(n²)
                let radius: Float = 0.3
                let cellSize = radius // Grid cell size matches neighbor radius

                // Build spatial hash grid
                var grid: [SIMD3<Int32>: [Int]] = [:]
                for (i, pt) in clusterPoints.enumerated() {
                    let cell = SIMD3<Int32>(
                        Int32(floor(Float(pt.x) / cellSize)),
                        Int32(floor(Float(pt.y) / cellSize)),
                        Int32(floor(Float(pt.z) / cellSize))
                    )
                    grid[cell, default: []].append(i)
                }

                // Calculate density by checking only neighboring cells
                var densities: [Float] = Array(repeating: 1, count: clusterPoints.count)
                for (i, pt) in clusterPoints.enumerated() {
                    let ptx = Float(pt.x)
                    let pty = Float(pt.y)
                    let ptz = Float(pt.z)
                    let cellX = Int32(floor(ptx / cellSize))
                    let cellY = Int32(floor(pty / cellSize))
                    let cellZ = Int32(floor(ptz / cellSize))

                    var neighborCount: Float = 0
                    // Check 27 neighboring cells (3x3x3)
                    for dx in Int32(-1)...Int32(1) {
                        for dy in Int32(-1)...Int32(1) {
                            for dz in Int32(-1)...Int32(1) {
                                let neighborCell = SIMD3<Int32>(cellX + dx, cellY + dy, cellZ + dz)
                                if let indices = grid[neighborCell] {
                                    for j in indices where j != i {
                                        let other = clusterPoints[j]
                                        let diffX = ptx - Float(other.x)
                                        let diffY = pty - Float(other.y)
                                        let diffZ = ptz - Float(other.z)
                                        let distSq = diffX*diffX + diffY*diffY + diffZ*diffZ
                                        if distSq < radius * radius {
                                            neighborCount += 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                    densities[i] = neighborCount + 1
                }

                // Weight each point by its density
                let totalWeight = densities.reduce(0, +)
                var weightedX: Float = 0, weightedY: Float = 0, weightedZ: Float = 0
                for (i, pt) in clusterPoints.enumerated() {
                    let w = densities[i]
                    weightedX += Float(pt.x) * w
                    weightedY += Float(pt.y) * w
                    weightedZ += Float(pt.z) * w
                }
                centroid = SCNVector3(
                    xFloat: weightedX / totalWeight,
                    yFloat: weightedY / totalWeight,
                    zFloat: weightedZ / totalWeight
                )
            } else {
                // Density-weighted: points in denser regions get more weight
                // Calculate local density for each point (count of neighbors within radius)
                let radius: Float = 0.3 // Neighborhood radius
                let radiusSq = radius * radius // Avoid sqrt
                var densities: [Float] = []
                densities.reserveCapacity(clusterPoints.count)
                for i in 0..<clusterPoints.count {
                    var neighborCount: Float = 0
                    let pt = clusterPoints[i]
                    let ptx = Float(pt.x)
                    let pty = Float(pt.y)
                    let ptz = Float(pt.z)
                    for j in 0..<clusterPoints.count where i != j {
                        let other = clusterPoints[j]
                        let dx = ptx - Float(other.x)
                        let dy = pty - Float(other.y)
                        let dz = ptz - Float(other.z)
                        let distSq = dx*dx + dy*dy + dz*dz
                        if distSq < radiusSq {
                            neighborCount += 1
                        }
                    }
                    densities.append(neighborCount + 1) // +1 so isolated points still count
                }

                // Weight each point by its density
                let totalWeight = densities.reduce(0, +)
                var weightedX: Float = 0, weightedY: Float = 0, weightedZ: Float = 0
                for (i, pt) in clusterPoints.enumerated() {
                    let w = densities[i]
                    weightedX += Float(pt.x) * w
                    weightedY += Float(pt.y) * w
                    weightedZ += Float(pt.z) * w
                }
                centroid = SCNVector3(
                    xFloat: weightedX / totalWeight,
                    yFloat: weightedY / totalWeight,
                    zFloat: weightedZ / totalWeight
                )
            }

            // === PER-DOCUMENT KEYWORDS + POINT COUNT ===
            // Use chunk metadata keywords specific to THIS document, not global FTS5
            let docNameLower = legendItem.name.lowercased()
            var topKeywords: [String] = []

            // Primary: Extract keywords from chunks belonging to THIS document
            let docKeywords = annotationLabels
                .filter { $0.docId == legendItem.docId }
                .flatMap { $0.keywords }

            var keywordCounts: [String: Int] = [:]
            for kw in docKeywords {
                let kwLower = kw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip keywords that are part of the document name or too short
                guard kwLower.count >= 3,
                      !docNameLower.contains(kwLower),
                      !kwLower.contains(String(docNameLower.prefix(4))) else { continue }
                keywordCounts[kwLower, default: 0] += 1
            }

            // Get top keywords sorted by frequency in this document
            topKeywords = keywordCounts
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key }

            // If still empty, try to extract from chunk content directly
            if topKeywords.isEmpty {
                // Find unique section titles for this document
                let sectionTitles = annotationLabels
                    .filter { $0.docId == legendItem.docId }
                    .compactMap { label -> String? in
                        let title = label.title.lowercased()
                        guard title != docNameLower, title.count >= 3 else { return nil }
                        return label.title
                    }
                let uniqueSections = Array(Set(sectionTitles)).prefix(2)
                topKeywords.append(contentsOf: uniqueSections)
            }

            // Always append point count as last keyword for visibility
            topKeywords.append("\(clusterPoints.count) chunks")

            let detailLevel = clusterPoints.count >= 30 ? 2 : (clusterPoints.count >= 8 ? 1 : 0)

            result.append(Embedding3DSceneView.AnnotationData(
                position: centroid,
                title: legendItem.name,
                keywords: topKeywords,
                color: docColorMap[legendItem.docId] ?? EmbeddingColorPalette.fallback,
                detailLevel: detailLevel,
                clusterSize: clusterPoints.count,
                isDocumentCluster: true
            ))
        }

        // === LAYER 2: Section/Topic Sub-clusters ===
        // Find semantic sub-clusters within each document using section titles

        for legendItem in legendItems where legendItem.count >= 5 {
            guard let indices = docPointIndices[legendItem.docId], indices.count >= 5 else { continue }

            // Group by section title
            var sectionPoints: [String: [SCNVector3]] = [:]
            var sectionKeywords: [String: [String]] = [:]

            for label in annotationLabels where label.docId == legendItem.docId {
                guard label.pointIndex < points.count else { continue }
                let sectionName = label.title
                sectionPoints[sectionName, default: []].append(points[label.pointIndex])
                sectionKeywords[sectionName, default: []].append(contentsOf: label.keywords)
            }

            // Create sub-cluster labels for sections with enough points
            for (section, sectionPts) in sectionPoints where sectionPts.count >= 3 {
                // Skip if section name is same as document name (already labeled)
                if section.lowercased() == legendItem.name.lowercased() { continue }

                // Compute section centroid
                var sx: Float = 0, sy: Float = 0, sz: Float = 0
                for pt in sectionPts {
                    sx += Float(pt.x); sy += Float(pt.y); sz += Float(pt.z)
                }
                let n = Float(sectionPts.count)
                let sectionCentroid = SCNVector3(xFloat: sx / n, yFloat: sy / n, zFloat: sz / n)

                // Get unique keywords for this section
                let uniqueKW = Array(Set(sectionKeywords[section] ?? [])).prefix(2)

                result.append(Embedding3DSceneView.AnnotationData(
                    position: sectionCentroid,
                    title: String(section.prefix(25)),
                    keywords: Array(uniqueKW),
                    color: (docColorMap[legendItem.docId] ?? EmbeddingColorPalette.fallback).withAlphaComponent(0.8),
                    detailLevel: 0, // Smaller label
                    clusterSize: sectionPts.count,
                    isDocumentCluster: false // This is a sub-cluster
                ))
            }
        }

        // === LAYER 3: FTS5-Powered Keyword Hotspots ===
        // Use actual top terms from SQLite FTS5 index for meaningful labels

        if !fts5TopTerms.isEmpty && annotationLabels.count >= 5 {
            // For each top FTS5 term, find where it appears in the embedding space
            let topTermsToShow = fts5TopTerms.prefix(15) // Top 15 terms from the database

            for term in topTermsToShow {
                let termLower = term.lowercased()

                // Find chunks that contain this term
                var termPoints: [SCNVector3] = []
                for label in annotationLabels {
                    guard label.pointIndex < points.count else { continue }
                    // Check if chunk content or keywords contain this term
                    let detailLower = label.detail.lowercased()
                    let keywordsLower = label.keywords.map { $0.lowercased() }

                    if detailLower.contains(termLower) || keywordsLower.contains(termLower) {
                        termPoints.append(points[label.pointIndex])
                    }
                }

                guard termPoints.count >= 3 else { continue } // Need at least 3 occurrences

                // Compute centroid
                var tx: Float = 0, ty: Float = 0, tz: Float = 0
                for pt in termPoints {
                    tx += Float(pt.x); ty += Float(pt.y); tz += Float(pt.z)
                }
                let n = Float(termPoints.count)
                let termCentroid = SCNVector3(xFloat: tx / n, yFloat: ty / n, zFloat: tz / n)

                // Check spatial coherence
                var totalDist: Float = 0
                for pt in termPoints {
                    let dx = Float(pt.x) - Float(termCentroid.x)
                    let dy = Float(pt.y) - Float(termCentroid.y)
                    let dz = Float(pt.z) - Float(termCentroid.z)
                    totalDist += sqrt(dx*dx + dy*dy + dz*dz)
                }
                let avgDist = totalDist / n

                // Only show if clustered (not scattered)
                if avgDist < 1.8 {
                    result.append(Embedding3DSceneView.AnnotationData(
                        position: termCentroid,
                        title: "#\(term)",
                        keywords: [],
                        color: platformColor(0.3, 0.9, 0.95, alpha: 0.9), // Bright cyan for FTS5 terms
                        detailLevel: 0,
                        clusterSize: termPoints.count,
                        isDocumentCluster: false
                    ))
                }
            }
        } else if annotationLabels.count >= 10 {
            // Fallback to chunk metadata keywords if no FTS5 data
            var keywordPositions: [String: [SCNVector3]] = [:]

            for label in annotationLabels {
                guard label.pointIndex < points.count else { continue }
                let pt = points[label.pointIndex]
                for kw in label.keywords {
                    let normalizedKW = kw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard normalizedKW.count >= 3 else { continue }
                    keywordPositions[normalizedKW, default: []].append(pt)
                }
            }

            for (keyword, kwPoints) in keywordPositions where kwPoints.count >= 4 {
                var kx: Float = 0, ky: Float = 0, kz: Float = 0
                for pt in kwPoints {
                    kx += Float(pt.x); ky += Float(pt.y); kz += Float(pt.z)
                }
                let n = Float(kwPoints.count)
                let kwCentroid = SCNVector3(xFloat: kx / n, yFloat: ky / n, zFloat: kz / n)

                var totalDist: Float = 0
                for pt in kwPoints {
                    let dx = Float(pt.x) - Float(kwCentroid.x)
                    let dy = Float(pt.y) - Float(kwCentroid.y)
                    let dz = Float(pt.z) - Float(kwCentroid.z)
                    totalDist += sqrt(dx*dx + dy*dy + dz*dz)
                }
                let avgDist = totalDist / n

                if avgDist < 1.5 {
                    result.append(Embedding3DSceneView.AnnotationData(
                        position: kwCentroid,
                        title: "#\(keyword)",
                        keywords: [],
                        color: platformColor(0.4, 0.8, 1.0, alpha: 0.9),
                        detailLevel: 0,
                        clusterSize: kwPoints.count,
                        isDocumentCluster: false
                    ))
                }
            }
        }

        // Sort: Document clusters first (largest), then sub-clusters, then keywords
        result.sort { lhs, rhs in
            if lhs.isDocumentCluster != rhs.isDocumentCluster {
                return lhs.isDocumentCluster // Document clusters first
            }
            return lhs.clusterSize > rhs.clusterSize
        }

        return result
    }

    private func formattedCount(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var heroHeight: CGFloat { focusMode ? 620 : 460 }
    var heroHorizontalPadding: CGFloat { focusMode ? 4 : 16 }

    var sampleCoverageRatio: Double {
        guard chunkCount > 0 else { return 0 }
        return min(1, Double(totalPoints) / Double(max(chunkCount, 1)))
    }

    private var docCoverageRatio: Double {
        guard documentCount > 0 else { return 0 }
        let represented = legendItems.filter { $0.count > 0 }.count
        return min(1, Double(represented) / Double(max(documentCount, 1)))
    }

    private var sampleCoverageText: String {
        guard chunkCount > 0, totalPoints > 0 else { return "No embeddings sampled yet" }
        let pct = String(format: "%.0f%%", sampleCoverageRatio * 100)
        return "Showing \(formattedCount(totalPoints)) of \(formattedCount(chunkCount)) chunks (\(pct))"
    }

    private var docCoverageText: String {
        guard documentCount > 0, !legendItems.isEmpty else { return "" }
        let pct = String(format: "%.0f%%", docCoverageRatio * 100)
        return "\(legendItems.filter { $0.count > 0 }.count) of \(documentCount) docs (\(pct))"
    }

    var projectionExplainer: String {
        switch projectionMethod {
        case .pca:
            return "PCA keeps the broadest themes intact—use it for a fast sanity check."
        case .tsne:
            return "t-SNE squeezes tiny topic bubbles apart; look for tight clusters."
        case .umap:
            return "UMAP balances global + local structure, great for mixed-format libraries."
        }
    }

    private var controlOverlay: some View {
        VStack(alignment: .trailing, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                ControlToggleButton(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Rotate",
                    isActive: autoRotate,
                    action: { autoRotate.toggle() }
                )

                ControlToggleButton(
                    icon: "chart.xyaxis.line",
                    title: "Axes",
                    isActive: showAxes,
                    action: { showAxes.toggle() }
                )

                ControlToggleButton(
                    icon: "cube.transparent",
                    title: "Depth",
                    isActive: depthCue,
                    action: { depthCue.toggle() }
                )

                ControlToggleButton(
                    icon: "text.justify",
                    title: "HUD",
                    isActive: showHUD,
                    action: {
                        withAnimation(DSAnimations.fastEase) {
                            showHUD.toggle()
                        }
                    }
                )

                ControlToggleButton(
                    icon: "tag.fill",
                    title: "Labels",
                    isActive: showClusterLabels,
                    action: {
                        withAnimation(DSAnimations.fastEase) {
                            showClusterLabels.toggle()
                            sceneReloadToken = UUID() // Force scene rebuild
                        }
                    }
                )

                ControlToggleButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Focus",
                    isActive: focusMode,
                    action: {
                        withAnimation(DSAnimations.gentleSpring) {
                            focusMode.toggle()
                        }
                    }
                )

                Button(action: resetScene) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption2)
                        .padding(.vertical, DSSpacing.xs)
                        .padding(.horizontal, DSSpacing.sm)
                        .background(Color.black.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(EmbeddingSceneBackgroundStyle.allCases) { style in
                    Button {
                        backgroundStyle = style
                    } label: {
                        HStack {
                            Label(style.displayName, systemImage: style.iconName)
                            Spacer()
                            if style == backgroundStyle {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(backgroundStyle.displayName, systemImage: backgroundStyle.iconName)
                    .font(.caption2)
                    .padding(.vertical, DSSpacing.xs)
                    .padding(.horizontal, DSSpacing.md)
                    .background(Color.black.opacity(0.14))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(DSSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
        .padding(DSSpacing.lg)
    }

    /// Inline HUD inspired by Apple's Embedding Atlas to explain what the user is seeing.
    @ViewBuilder
    var sceneHUD: some View {
        if totalPoints > 0 {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                sampleSummaryBadge
                axisHintPanel
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                            .stroke(DSColors.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 6)
            .padding(DSSpacing.md)
        }
    }

    var controlToolbar: some View {
        VStack(spacing: DSSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    // Search button
                    ControlToggleButton(
                        icon: "magnifyingglass",
                        title: "Search",
                        isActive: isSearching,
                        action: {
                            withAnimation(DSAnimations.fastEase) {
                                isSearching.toggle()
                            }
                        }
                    )

                    ControlToggleButton(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Rotate",
                        isActive: autoRotate,
                        action: { autoRotate.toggle() }
                    )

                    ControlToggleButton(
                        icon: "chart.xyaxis.line",
                        title: "Axes",
                        isActive: showAxes,
                        action: { showAxes.toggle() }
                    )

                    ControlToggleButton(
                        icon: "cube.transparent",
                        title: "Depth",
                        isActive: depthCue,
                        action: { depthCue.toggle() }
                    )

                    ControlToggleButton(
                        icon: "text.justify",
                        title: "HUD",
                        isActive: showHUD,
                        action: {
                            withAnimation(DSAnimations.fastEase) {
                                showHUD.toggle()
                            }
                        }
                    )

                    ControlToggleButton(
                        icon: "tag.fill",
                        title: "Labels",
                        isActive: showClusterLabels,
                        action: {
                            withAnimation(DSAnimations.fastEase) {
                                showClusterLabels.toggle()
                                sceneReloadToken = UUID()
                            }
                        }
                    )

                    ControlToggleButton(
                        icon: "arrow.up.left.and.arrow.down.right",
                        title: "Focus",
                        isActive: focusMode,
                        action: {
                            withAnimation(DSAnimations.gentleSpring) {
                                focusMode.toggle()
                            }
                        }
                    )

                    Button(action: resetScene) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption2)
                            .padding(.vertical, DSSpacing.xs)
                            .padding(.horizontal, DSSpacing.sm)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DSSpacing.xs)
            }

            Menu {
                ForEach(EmbeddingSceneBackgroundStyle.allCases) { style in
                    Button {
                        backgroundStyle = style
                    } label: {
                        HStack {
                            Label(style.displayName, systemImage: style.iconName)
                            Spacer()
                            if style == backgroundStyle {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(backgroundStyle.displayName, systemImage: backgroundStyle.iconName)
                    .font(.caption2)
                    .padding(.vertical, DSSpacing.xs)
                    .padding(.horizontal, DSSpacing.md)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                        .stroke(DSColors.border, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal, DSSpacing.lg)
    }

    private var sampleSummaryBadge: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "chart.scatter")
                Text(sampleCoverageText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.primary)

            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "rectangle.3.group")
                Text(docCoverageText.isEmpty ? projectionExplainer : docCoverageText)
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var axisHintPanel: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "chart.xyaxis.line")
                Text("Axis cheat sheet")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            axisHintRow(label: "X axis", detail: "Left ↔ Right splits the strongest topic contrast.", color: .blue)
            axisHintRow(label: "Y axis", detail: "Up ↕ Down separates structure—narrative vs. tabular.", color: .green)
            axisHintRow(label: "Z axis", detail: "Depth stacks subtopics; tilt the view to reveal layers.", color: .purple)
        }
    }

    private func axisHintRow(label: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 8, height: 8)
                .padding(.top, DSSpacing.xs)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var insightHighlights: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Text("Quick insights")
                        .font(.headline)
                    Spacer()
                    Text(projectionExplainer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.md) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                    .padding(.vertical, DSSpacing.xs)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }

    private func resetScene() {
        sceneReloadToken = UUID()
    }

    func backgroundGradient(for style: EmbeddingSceneBackgroundStyle) -> LinearGradient {
        switch style {
        case .aurora:
            return LinearGradient(
                colors: [Color(red: 0.14, green: 0.24, blue: 0.45), Color(red: 0.42, green: 0.62, blue: 0.93)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnight:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.12), Color(red: 0.26, green: 0.28, blue: 0.38)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        case .cosmos:
            return LinearGradient(
                colors: [Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.12, green: 0.08, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .nebula:
            return LinearGradient(
                colors: [Color(red: 0.18, green: 0.08, blue: 0.28), Color(red: 0.35, green: 0.15, blue: 0.45), Color(red: 0.12, green: 0.25, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ocean:
            return LinearGradient(
                colors: [Color(red: 0.02, green: 0.15, blue: 0.30), Color(red: 0.05, green: 0.28, blue: 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .forest:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.12, blue: 0.08), Color(red: 0.12, green: 0.22, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .parchment:
            return LinearGradient(
                colors: [Color(red: 0.96, green: 0.94, blue: 0.89), Color(red: 0.86, green: 0.82, blue: 0.74)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private struct ControlToggleButton: View {
        let icon: String
        let title: String
        let isActive: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                }
                .font(.caption2)
                .padding(.vertical, DSSpacing.xs)
                .padding(.horizontal, DSSpacing.sm)
                .background(isActive ? DSColors.accent : Color.secondary.opacity(0.15))
                .foregroundStyle(isActive ? .white : .primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

}
#endif

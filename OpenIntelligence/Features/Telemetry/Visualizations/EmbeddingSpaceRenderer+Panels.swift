//
//  EmbeddingSpaceRenderer+Panels.swift
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
    // MARK: - Spatial Density Section

    @ViewBuilder
    var spatialDensitySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(DSColors.accent)
                Text("Spatial Density Analysis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !points.isEmpty {
                let stats = computeSpatialStats()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                    SpatialStatMini(
                        label: "Centroid",
                        value: String(format: "(%.2f, %.2f, %.2f)", stats.centroid.x, stats.centroid.y, stats.centroid.z),
                        icon: "scope"
                    )
                    SpatialStatMini(
                        label: "Avg Distance",
                        value: String(format: "%.3f", stats.avgDistanceFromCentroid),
                        icon: "arrow.left.and.right"
                    )
                    SpatialStatMini(
                        label: "Spread (σ)",
                        value: String(format: "%.3f", stats.spreadStdDev),
                        icon: "chart.bar.doc.horizontal"
                    )
                    SpatialStatMini(
                        label: "Bounding Box",
                        value: String(format: "%.2f³", stats.boundingBoxVolume),
                        icon: "cube"
                    )
                    SpatialStatMini(
                        label: "Density",
                        value: String(format: "%.1f pts/unit³", stats.pointDensity),
                        icon: "circle.hexagongrid"
                    )
                    SpatialStatMini(
                        label: "Clustering",
                        value: clusteringQualityLabel(stats.clusteringCoeff),
                        icon: "circle.grid.3x3"
                    )
                }

                // Axis-wise distribution mini-chart
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Axis Distribution")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: DSSpacing.xs) {
                        AxisDistributionBar(label: "X", range: stats.xRange, color: .red)
                        AxisDistributionBar(label: "Y", range: stats.yRange, color: .green)
                        AxisDistributionBar(label: "Z", range: stats.zRange, color: .blue)
                    }
                    .frame(height: 40)
                }
            } else {
                Text("No points to analyze")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Raw Data Inspector

    @ViewBuilder
    var rawDataInspector: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(DSColors.accent)
                Text("Raw Data Inspector")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(points.count) vectors")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !points.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    // Memory usage estimate
                    let memoryBytes = points.count * 3 * MemoryLayout<Float>.size
                    HStack {
                        Text("3D Memory:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatBytes(memoryBytes))
                            .font(.caption2.monospacedDigit())
                            .fontWeight(.medium)
                        Spacer()
                        Text("Float32 × 3")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Original embedding memory estimate
                    let embeddingMemory = points.count * embeddingDimension * MemoryLayout<Float>.size
                    HStack {
                        Text("Original (\(embeddingDimension)D):")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatBytes(embeddingMemory))
                            .font(.caption2.monospacedDigit())
                            .fontWeight(.medium)
                        Spacer()
                        let ratio = Double(memoryBytes) / Double(embeddingMemory)
                        Text(String(format: "%.1f%% of original", ratio * 100))
                            .font(.caption2)
                            .foregroundStyle(DSColors.readable(.green))
                    }
                }

                Divider().opacity(0.2)

                // Sample point coordinates
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Sample Points")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(Array(points.prefix(3).enumerated()), id: \.offset) { idx, point in
                        HStack(spacing: DSSpacing.sm) {
                            Text("[\(idx)]")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(String(format: "x:%.4f", point.x))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DSColors.readable(.red))
                            Text(String(format: "y:%.4f", point.y))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DSColors.readable(.green))
                            Text(String(format: "z:%.4f", point.z))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DSColors.readable(.blue))
                            Spacer()
                        }
                    }

                    if points.count > 3 {
                        Text("... + \(points.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, DSSpacing.xxl)
                    }
                }
            }
        }
    }

    // MARK: - Spatial Stats Computation

    private struct SpatialStats {
        let centroid: SCNVector3
        let avgDistanceFromCentroid: Float
        let spreadStdDev: Float
        let boundingBoxVolume: Float
        let pointDensity: Float
        let clusteringCoeff: Float
        let xRange: ClosedRange<Float>
        let yRange: ClosedRange<Float>
        let zRange: ClosedRange<Float>
    }

    private func computeSpatialStats() -> SpatialStats {
        guard !points.isEmpty else {
            return SpatialStats(
                centroid: SCNVector3Zero,
                avgDistanceFromCentroid: 0,
                spreadStdDev: 0,
                boundingBoxVolume: 0,
                pointDensity: 0,
                clusteringCoeff: 0,
                xRange: 0...0,
                yRange: 0...0,
                zRange: 0...0
            )
        }

        // Compute centroid
        var sumX: Float = 0, sumY: Float = 0, sumZ: Float = 0
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

        for point in points {
            let px = Float(point.x)
            let py = Float(point.y)
            let pz = Float(point.z)
            sumX += px; sumY += py; sumZ += pz
            minX = min(minX, px); maxX = max(maxX, px)
            minY = min(minY, py); maxY = max(maxY, py)
            minZ = min(minZ, pz); maxZ = max(maxZ, pz)
        }

        let count = Float(points.count)
        let centroid = SCNVector3(xFloat: sumX / count, yFloat: sumY / count, zFloat: sumZ / count)

        // Compute distances from centroid
        var distances: [Float] = []
        distances.reserveCapacity(points.count)
        for point in points {
            let dx = Float(point.x) - Float(centroid.x)
            let dy = Float(point.y) - Float(centroid.y)
            let dz = Float(point.z) - Float(centroid.z)
            distances.append(sqrt(dx * dx + dy * dy + dz * dz))
        }

        let avgDistance = distances.reduce(0, +) / Float(distances.count)

        // Standard deviation
        let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Float(distances.count)
        let stdDev = sqrt(variance)

        // Bounding box volume
        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)

        // Point density
        let density = volume > 0.0001 ? Float(points.count) / volume : 0

        // Simplified clustering coefficient (average nearest neighbor distance ratio)
        let clusterCoeff = computeClusteringCoefficient()

        return SpatialStats(
            centroid: centroid,
            avgDistanceFromCentroid: avgDistance,
            spreadStdDev: stdDev,
            boundingBoxVolume: volume,
            pointDensity: density,
            clusteringCoeff: clusterCoeff,
            xRange: minX...maxX,
            yRange: minY...maxY,
            zRange: minZ...maxZ
        )
    }

    private func computeClusteringCoefficient() -> Float {
        // Approximate clustering by looking at nearest neighbor distances
        // Lower values = tighter clusters
        guard points.count > 10 else { return 0 }

        let sampleSize = min(50, points.count)
        let sampleIndices = Array((0..<points.count).shuffled().prefix(sampleSize))

        // OPTIMIZATION: Use spatial grid for O(n) nearest neighbor search instead of O(n²)
        // Build a coarse grid - cell size based on expected nearest neighbor distance
        let gridCellSize: Float = 0.5 // Reasonable for normalized viewing cube
        var grid: [SIMD3<Int32>: [Int]] = [:]
        grid.reserveCapacity(points.count / 4)

        for i in 0..<points.count {
            let pt = points[i]
            let cell = SIMD3<Int32>(
                Int32(floor(Float(pt.x) / gridCellSize)),
                Int32(floor(Float(pt.y) / gridCellSize)),
                Int32(floor(Float(pt.z) / gridCellSize))
            )
            grid[cell, default: []].append(i)
        }

        var nearestDistances: [Float] = []
        nearestDistances.reserveCapacity(sampleSize)

        for i in sampleIndices {
            let pt = points[i]
            let ptx = Float(pt.x)
            let pty = Float(pt.y)
            let ptz = Float(pt.z)
            let cellX = Int32(floor(ptx / gridCellSize))
            let cellY = Int32(floor(pty / gridCellSize))
            let cellZ = Int32(floor(ptz / gridCellSize))

            var minDistSq: Float = .greatestFiniteMagnitude

            // Check neighboring cells (3x3x3 = 27 cells max)
            for dx in Int32(-1)...Int32(1) {
                for dy in Int32(-1)...Int32(1) {
                    for dz in Int32(-1)...Int32(1) {
                        let neighborCell = SIMD3<Int32>(cellX + dx, cellY + dy, cellZ + dz)
                        if let indices = grid[neighborCell] {
                            for j in indices where i != j {
                                let other = points[j]
                                let diffX = ptx - Float(other.x)
                                let diffY = pty - Float(other.y)
                                let diffZ = ptz - Float(other.z)
                                let distSq = diffX*diffX + diffY*diffY + diffZ*diffZ
                                minDistSq = min(minDistSq, distSq)
                            }
                        }
                    }
                }
            }

            // If no neighbor in adjacent cells, expand search (rare case)
            if minDistSq == .greatestFiniteMagnitude {
                for j in 0..<points.count where i != j {
                    let other = points[j]
                    let diffX = ptx - Float(other.x)
                    let diffY = pty - Float(other.y)
                    let diffZ = ptz - Float(other.z)
                    let distSq = diffX*diffX + diffY*diffY + diffZ*diffZ
                    minDistSq = min(minDistSq, distSq)
                }
            }

            if minDistSq < .greatestFiniteMagnitude {
                nearestDistances.append(sqrt(minDistSq))
            }
        }

        guard !nearestDistances.isEmpty else { return 0 }
        let avgNearestDist = nearestDistances.reduce(0, +) / Float(nearestDistances.count)

        // Normalize to 0-1 range (lower = more clustered)
        return min(1, max(0, 1 - avgNearestDist * 2))
    }

    private func clusteringQualityLabel(_ coeff: Float) -> String {
        if coeff > 0.7 { return "Tight" }
        else if coeff > 0.4 { return "Moderate" }
        else { return "Sparse" }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) B"
        }
    }

    // MARK: - Spatial Helper Views

    private struct SpatialStatMini: View {
        let label: String
        let value: String
        let icon: String

        var body: some View {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(label)
                        .scaledFont(size: 9)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .scaledFont(size: 10, weight: .medium, design: .monospaced)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DSSpacing.xs)
            .padding(.horizontal, DSSpacing.sm)
            .background(DSColors.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
    }

    private struct AxisDistributionBar: View {
        let label: String
        let range: ClosedRange<Float>
        let color: Color

        var body: some View {
            VStack(spacing: DSSpacing.xxs) {
                Text(label)
                    .scaledFont(size: 9, weight: .bold)
                    .foregroundStyle(DSColors.readable(color))

                GeometryReader { geo in
                    let width = range.upperBound - range.lowerBound
                    let normalized = min(1, max(0.1, CGFloat(width)))

                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.7)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geo.size.height * normalized)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }

                Text(String(format: "%.2f", range.upperBound - range.lowerBound))
                    .scaledFont(size: 8, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var loadingCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            VStack(spacing: DSSpacing.md) {
                ProgressView("Preparing 3D embedding space…")
                Text("Downsampling and projecting to 3D")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.lg)
        }
        .frame(height: 340)
    }

    var emptyStateCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            VStack(spacing: DSSpacing.sm) {
                Text("No embeddings available for the active container")
                    .font(.subheadline)
                Text("Add documents or switch libraries to see the 3D map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.lg)
        }
        .frame(height: 340)
    }

    var heroScene: some View {
        let (filteredPoints, filteredColors) = filteredArrays()
        return ZStack {
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(backgroundGradient(for: backgroundStyle))

            Embedding3DSceneView(
                points: filteredPoints,
                colors: filteredColors,
                options: sceneOptions,
                reloadToken: sceneReloadToken,
                annotations: buildSceneAnnotations(),
                onPointTapped: { index, position in
                    // Handle tap - show detail for this point
                    tappedPointIndex = index
                    showPointDetail = true
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
        }
        .overlay(alignment: .topLeading) {
            if showHUD { sceneHUD }
        }
        .overlay(alignment: .topTrailing) {
            // Subtle help button
            helpButton
        }
        .overlay(alignment: .top) {
            // Minimal search bar (only when actively searching)
            if isSearching {
                searchBar
            }
        }
        .overlay(alignment: .bottom) {
            // First-time onboarding tip
            if !hasSeenOnboarding && !points.isEmpty {
                onboardingTip
            }
        }
        .overlay(alignment: .center) {
            // Tapped point detail card
            if showPointDetail, let idx = tappedPointIndex {
                tappedPointDetailCard(index: idx)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: heroHeight)
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 12)
        .padding(.horizontal, heroHorizontalPadding)
        .animation(DSAnimations.gentleSpring, value: focusMode)
        .animation(DSAnimations.fastEase, value: showHUD)
        .animation(DSAnimations.fastEase, value: isSearching)
        .animation(DSAnimations.fastEase, value: hasSeenOnboarding)
    }

}
#endif

//  Embedding3DView.swift
//  OpenIntelligence
//
//  Lightweight 3D scatter for document embeddings (Apple-style scaffolding)
//  - Projects 512-d embeddings to 3D using PCA (approx) or RP via ProjectionService
//  - Colors points by source document (per active container)
//  - SceneKit-based viewer with orbit control and default lighting
//  - Deterministic stratified downsampling with caching and per-file filters
//
//  NOTE: This is an integration scaffold. Swap ProjectionService backend with Apple's
//  Embedding Atlas or true UMAP/t-SNE later without changing UI.

import SwiftUI

struct EmbeddingInsight: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let accent: Color
}

/// Lightweight annotation descriptor used to project short contextual blurbs over the scene.
struct PointAnnotationLabel: Identifiable, Equatable {
    let id = UUID()
    let pointIndex: Int
    let docId: UUID
    let title: String
    let detail: String
    let keywords: [String]
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let depthHint: CGFloat
    let accent: Color
    let score: Double
}

#if canImport(SceneKit)
import SceneKit
import QuartzCore

extension SCNVector3 {
    init(xFloat: Float, yFloat: Float, zFloat: Float) {
        #if os(macOS)
        self.init(CGFloat(xFloat), CGFloat(yFloat), CGFloat(zFloat))
        #else
        self.init(xFloat, yFloat, zFloat)
        #endif
    }
}

extension SCNVector4 {
    init(xFloat: Float, yFloat: Float, zFloat: Float, wFloat: Float) {
        #if os(macOS)
        self.init(CGFloat(xFloat), CGFloat(yFloat), CGFloat(zFloat), CGFloat(wFloat))
        #else
        self.init(xFloat, yFloat, zFloat, wFloat)
        #endif
    }
}

#if canImport(UIKit)
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#endif

private func platformColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> PlatformColor {
#if canImport(UIKit)
    return PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
#else
    return PlatformColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
#endif
}

enum EmbeddingSceneBackgroundStyle: String, CaseIterable, Identifiable {
    case aurora
    case midnight
    case cosmos
    case nebula
    case ocean
    case forest
    case parchment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .midnight: return "Midnight"
        case .cosmos: return "Cosmos"
        case .nebula: return "Nebula"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .parchment: return "Parchment"
        }
    }

    var iconName: String {
        switch self {
        case .aurora: return "sun.max"
        case .midnight: return "moon.stars"
        case .cosmos: return "sparkles"
        case .nebula: return "hurricane"
        case .ocean: return "water.waves"
        case .forest: return "leaf"
        case .parchment: return "doc.text"
        }
    }

    var gradientSpec: GradientSpec {
        switch self {
        case .aurora:
            return GradientSpec(
                colors: [platformColor(0.16, 0.29, 0.57),
                         platformColor(0.34, 0.58, 0.84)],
                startPoint: CGPoint(x: 0.1, y: 0.0),
                endPoint: CGPoint(x: 0.9, y: 1.0)
            )
        case .midnight:
            return GradientSpec(
                colors: [platformColor(0.07, 0.07, 0.16),
                         platformColor(0.23, 0.25, 0.36)],
                startPoint: CGPoint(x: 0.5, y: 0.0),
                endPoint: CGPoint(x: 0.5, y: 1.0)
            )
        case .cosmos:
            // Deep space black to dark purple - stars would pop
            return GradientSpec(
                colors: [platformColor(0.02, 0.02, 0.08),
                         platformColor(0.12, 0.08, 0.22),
                         platformColor(0.05, 0.03, 0.12)],
                startPoint: CGPoint(x: 0.0, y: 0.0),
                endPoint: CGPoint(x: 1.0, y: 1.0)
            )
        case .nebula:
            // Purple/pink/teal cosmic cloud
            return GradientSpec(
                colors: [platformColor(0.18, 0.08, 0.28),
                         platformColor(0.35, 0.15, 0.45),
                         platformColor(0.12, 0.25, 0.35)],
                startPoint: CGPoint(x: 0.0, y: 0.3),
                endPoint: CGPoint(x: 1.0, y: 0.7)
            )
        case .ocean:
            // Deep ocean blues
            return GradientSpec(
                colors: [platformColor(0.02, 0.15, 0.30),
                         platformColor(0.05, 0.28, 0.45),
                         platformColor(0.08, 0.18, 0.32)],
                startPoint: CGPoint(x: 0.5, y: 0.0),
                endPoint: CGPoint(x: 0.5, y: 1.0)
            )
        case .forest:
            // Deep forest greens
            return GradientSpec(
                colors: [platformColor(0.05, 0.12, 0.08),
                         platformColor(0.12, 0.22, 0.14),
                         platformColor(0.08, 0.16, 0.10)],
                startPoint: CGPoint(x: 0.2, y: 0.0),
                endPoint: CGPoint(x: 0.8, y: 1.0)
            )
        case .parchment:
            return GradientSpec(
                colors: [platformColor(0.96, 0.94, 0.89),
                         platformColor(0.84, 0.80, 0.72)],
                startPoint: CGPoint(x: 0.0, y: 0.0),
                endPoint: CGPoint(x: 1.0, y: 1.0)
            )
        }
    }

    var fogColor: PlatformColor {
        switch self {
        case .aurora:
            return platformColor(0.10, 0.16, 0.28)
        case .midnight:
            return platformColor(0.04, 0.04, 0.09)
        case .cosmos:
            return platformColor(0.03, 0.02, 0.08)
        case .nebula:
            return platformColor(0.15, 0.08, 0.22)
        case .ocean:
            return platformColor(0.03, 0.12, 0.22)
        case .forest:
            return platformColor(0.04, 0.10, 0.06)
        case .parchment:
            return platformColor(0.92, 0.90, 0.84)
        }
    }

    /// Primary text color for labels - ensures readability on this background
    var labelTextColor: PlatformColor {
        switch self {
        case .aurora, .midnight, .cosmos, .nebula, .ocean, .forest:
            return platformColor(1.0, 1.0, 1.0) // White text on dark
        case .parchment:
            return platformColor(0.15, 0.12, 0.10) // Dark brown on light
        }
    }

    /// Background pill color for labels - semi-transparent contrast layer
    var labelBackgroundColor: PlatformColor {
        switch self {
        case .aurora, .midnight, .cosmos, .nebula, .ocean, .forest:
            return platformColor(0.0, 0.0, 0.0, alpha: 0.75) // Dark pill on dark bg
        case .parchment:
            return platformColor(1.0, 1.0, 1.0, alpha: 0.85) // Light pill on light bg
        }
    }

    /// Whether this is a dark background (for emission glow intensity)
    var isDark: Bool {
        switch self {
        case .aurora, .midnight, .cosmos, .nebula, .ocean, .forest: return true
        case .parchment: return false
        }
    }

    struct GradientSpec {
        let colors: [PlatformColor]
        let startPoint: CGPoint
        let endPoint: CGPoint
    }
}

/// Shared legend item for per-document coloring in embedding visualizations.
/// Used by both EmbeddingSpaceRenderer and Fullscreen3DAtlasView.
struct VizLegendItem: Identifiable {
    let docId: UUID
    let name: String
    let color: Color
    let count: Int
    var id: UUID { docId }
}

struct EmbeddingSpaceRenderer: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService

    let projectionMethod: EmbeddingSpaceView.ProjectionMethod
    let chunkCount: Int
    let documentCount: Int

    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var pointColorsUI: [PlatformColor] = []
    @State private var legendItems: [VizLegendItem] = []
    @State private var errorText: String? = nil

    // Deterministic per-container controls and state
    @State private var sampleLimit: Int = 2000 // Higher default for full visibility
    @State private var allDocIdsForPoints: [UUID] = [] // aligned with points/colors
    @State private var totalPoints: Int = 0
    @State private var selectedDocFilters: Set<UUID> = [] // empty = select all by default
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var pointScale: Double = 1.0 // Slightly smaller for more points
    @State private var autoRotate = false // Off by default — let user explore
    @State private var showAxes = true // On by default — show spatial reference
    @State private var depthCue = false // Off for cleaner look
    @State private var backgroundStyle: EmbeddingSceneBackgroundStyle = .midnight // Dark for better contrast
    @State private var sceneReloadToken = UUID()
    @State private var insights: [EmbeddingInsight] = []
    @State private var focusMode = false
    @State private var showHUD = true
    @State private var showClusterLabels = true // Show floating document cluster labels
    @State private var annotationLabels: [PointAnnotationLabel] = []

    // Search & highlight functionality
    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false
    @State private var highlightedPointIndices: Set<Int> = []

    // Tap-to-inspect: tapped point info
    @State private var tappedPointIndex: Int? = nil
    @State private var showPointDetail: Bool = false

    // Chunk data for tap-to-inspect (loaded once, indexed by point order)
    @State private var chunkTexts: [String] = []
    @State private var chunkDocNames: [String] = []

    // Dynamic axis labels derived from analyzing content at axis extremes
    @State private var dynamicAxisLabels: Embedding3DSceneView.AxisLabels = .placeholder

    // Onboarding / help
    @State private var showHelpTip: Bool = false
    @AppStorage("embedding3d_hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    // FTS5-derived corpus intelligence for richer labels
    @State private var fts5TopTerms: [String] = []  // Top terms from SQLite FTS5 index
    @State private var fts5KeyPhrases: [(phrase: String, count: Int)] = []  // Multi-word phrases

    // Sample options: 500 up to 50K (ALL) for full corpus visibility
    // Higher counts auto-scale point size smaller
    private let sampleOptions = [500, 2000, 5000, 50000] // 50K = "All" for most libraries
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            if let err = errorText {
                errorBanner(err)
            }
            contentBody
        }
        // Reload when container/method/sample changes
        .task(id: containerService.activeContainerId) {
            loadSampleLimitForActive()
            await loadAndProject()
        }
        .task(id: projectionMethod) {
            await loadAndProject()
        }
        .task(id: sampleLimit) {
            await loadAndProject()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

        // MARK: - Subview builders (split to help the type-checker)

    private func errorBanner(_ err: String) -> some View {
        Text(err)
            .font(.caption)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contentBody: some View {
        if isLoading {
            loadingCard
        } else if points.isEmpty {
            emptyStateCard
        } else {
            readyContent
        }
    }

    private var readyContent: some View {
        VStack(spacing: 20) {
            heroScene
            controlToolbar
            tuningCard
            embeddingSpaceStats
            insightHighlights
            legendSection
        }
    }

    /// Detailed nerd stats for the embedding space
    private var embeddingSpaceStats: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.dots.scatter")
                    .foregroundColor(.purple)
                Text("Embedding Space Analytics")
                    .font(.headline)
                Spacer()
                Text("🤓 Nerd Mode")
                    .font(.caption2)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(8)
            }

            // Core metrics grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                EmbeddingStatMini(
                    label: "Points",
                    value: "\(totalPoints)",
                    icon: "circle.fill",
                    color: .blue
                )
                EmbeddingStatMini(
                    label: "Documents",
                    value: "\(legendItems.count)",
                    icon: "doc.fill",
                    color: .green
                )
                EmbeddingStatMini(
                    label: "Dimensions",
                    value: "\(embeddingDimension)",
                    icon: "cube.fill",
                    color: .purple
                )
                EmbeddingStatMini(
                    label: "Method",
                    value: projectionMethod.rawValue,
                    icon: "function",
                    color: .orange
                )
                EmbeddingStatMini(
                    label: "Coverage",
                    value: String(format: "%.0f%%", sampleCoverageRatio * 100),
                    icon: "percent",
                    color: .cyan
                )
                EmbeddingStatMini(
                    label: "Sample Cap",
                    value: "\(sampleLimit)",
                    icon: "slider.horizontal.3",
                    color: .pink
                )
            }

            Divider().opacity(0.3)

            // Distribution insights
            VStack(alignment: .leading, spacing: 10) {
                Text("Distribution Analysis")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                if !legendItems.isEmpty {
                    let sortedItems = legendItems.sorted { $0.count > $1.count }
                    let maxCount = sortedItems.first?.count ?? 1
                    let minCount = sortedItems.last?.count ?? 0
                    let avgCount = totalPoints > 0 ? totalPoints / max(legendItems.count, 1) : 0
                    let variance = calculateVariance(legendItems.map { $0.count })

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max pts/doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(maxCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Min pts/doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(minCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg pts/doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(avgCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Std Dev")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f", sqrt(variance)))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }

                    // Balance indicator
                    let balanceScore = calculateBalanceScore(legendItems.map { $0.count })
                    HStack(spacing: 8) {
                        Text("Balance Score:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.2))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(balanceColor(balanceScore))
                                    .frame(width: geo.size.width * CGFloat(balanceScore))
                            }
                        }
                        .frame(height: 8)
                        Text(String(format: "%.0f%%", balanceScore * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(balanceColor(balanceScore))
                    }
                    .frame(height: 20)

                    Text(balanceDescription(balanceScore))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider().opacity(0.3)

            // Projection details
            VStack(alignment: .leading, spacing: 8) {
                Text("Projection Details")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    ProjectionDetailRow(label: "Algorithm", value: projectionMethodDescription)
                    Spacer()
                }

                Text(projectionExplainer)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.3)

            // Spatial density analysis
            spatialDensitySection

            Divider().opacity(0.3)

            // Raw data inspector
            rawDataInspector
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    private var embeddingDimension: Int {
        // Get from first chunk or default
        384 // MiniLM-L6-v2 dimension
    }

    private var projectionMethodDescription: String {
        switch projectionMethod {
        case .pca: return "Principal Component Analysis"
        case .tsne: return "t-Distributed Stochastic Neighbor Embedding"
        case .umap: return "Uniform Manifold Approximation"
        }
    }

    private func calculateVariance(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let squaredDiffs = values.map { pow(Double($0) - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count)
    }

    private func calculateBalanceScore(_ counts: [Int]) -> Double {
        guard counts.count > 1, let maxCount = counts.max(), maxCount > 0 else { return 1.0 }
        let total = counts.reduce(0, +)
        let idealPerDoc: Double = Double(total) / Double(counts.count)
        let deviations: [Double] = counts.map { count in
            let diff: Double = Double(count) - idealPerDoc
            return Swift.abs(diff) / idealPerDoc
        }
        let avgDeviation: Double = deviations.reduce(0.0, +) / Double(deviations.count)
        return max(0.0, 1.0 - avgDeviation)
    }

    private func balanceColor(_ score: Double) -> Color {
        if score > 0.8 { return .green }
        else if score > 0.5 { return .orange }
        else { return .red }
    }

    private func balanceDescription(_ score: Double) -> String {
        if score > 0.8 { return "Well-balanced: Points are evenly distributed across documents" }
        else if score > 0.5 { return "Moderate imbalance: Some documents dominate the sample" }
        else { return "Highly imbalanced: Consider filtering or adjusting sample cap" }
    }

    // MARK: - Spatial Density Section

    @ViewBuilder
    private var spatialDensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundColor(.cyan)
                Text("Spatial Density Analysis")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if !points.isEmpty {
                let stats = computeSpatialStats()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Axis Distribution")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        AxisDistributionBar(label: "X", range: stats.xRange, color: .red)
                        AxisDistributionBar(label: "Y", range: stats.yRange, color: .green)
                        AxisDistributionBar(label: "Z", range: stats.zRange, color: .blue)
                    }
                    .frame(height: 40)
                }
            } else {
                Text("No points to analyze")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Raw Data Inspector

    @ViewBuilder
    private var rawDataInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tablecells")
                    .foregroundColor(.indigo)
                Text("Raw Data Inspector")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(points.count) vectors")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    // Memory usage estimate
                    let memoryBytes = points.count * 3 * MemoryLayout<Float>.size
                    HStack {
                        Text("3D Memory:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatBytes(memoryBytes))
                            .font(.caption2.monospacedDigit())
                            .fontWeight(.medium)
                        Spacer()
                        Text("Float32 × 3")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    // Original embedding memory estimate
                    let embeddingMemory = points.count * embeddingDimension * MemoryLayout<Float>.size
                    HStack {
                        Text("Original (\(embeddingDimension)D):")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatBytes(embeddingMemory))
                            .font(.caption2.monospacedDigit())
                            .fontWeight(.medium)
                        Spacer()
                        let ratio = Double(memoryBytes) / Double(embeddingMemory)
                        Text(String(format: "%.1f%% of original", ratio * 100))
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                Divider().opacity(0.2)

                // Sample point coordinates
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Points")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)

                    ForEach(Array(points.prefix(3).enumerated()), id: \.offset) { idx, point in
                        HStack(spacing: 8) {
                            Text("[\(idx)]")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(String(format: "x:%.4f", point.x))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.red.opacity(0.8))
                            Text(String(format: "y:%.4f", point.y))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.green.opacity(0.8))
                            Text(String(format: "z:%.4f", point.z))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.blue.opacity(0.8))
                            Spacer()
                        }
                    }

                    if points.count > 3 {
                        Text("... + \(points.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 32)
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.8))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color.cyan.opacity(0.06))
            .cornerRadius(6)
        }
    }

    private struct AxisDistributionBar: View {
        let label: String
        let range: ClosedRange<Float>
        let color: Color

        var body: some View {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)

                GeometryReader { geo in
                    let width = range.upperBound - range.lowerBound
                    let normalized = min(1, max(0.1, CGFloat(width)))

                    RoundedRectangle(cornerRadius: 3)
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
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var loadingCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            VStack(spacing: 12) {
                ProgressView("Preparing 3D embedding space…")
                Text("Downsampling and projecting to 3D")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(height: 340)
    }

    private var emptyStateCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            VStack(spacing: 8) {
                Text("No embeddings available for the active container")
                    .font(.subheadline)
                Text("Add documents or switch libraries to see the 3D map")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(height: 340)
    }

    private var heroScene: some View {
        let (filteredPoints, filteredColors) = filteredArrays()
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: focusMode)
        .animation(.easeInOut(duration: 0.2), value: showHUD)
        .animation(.easeInOut(duration: 0.25), value: isSearching)
        .animation(.easeInOut(duration: 0.3), value: hasSeenOnboarding)
    }

    // MARK: - Search & Help UI

    private var helpButton: some View {
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
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(12)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial.opacity(showHelpTip ? 0.9 : 0.5))
                )
        }
        .padding(12)
        .popover(isPresented: $showHelpTip, arrowEdge: .top) {
            gestureHelpContent
        }
    }

    private var gestureHelpContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Navigate Your Knowledge")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                helpRow(icon: "hand.draw", text: "Drag to rotate")
                helpRow(icon: "arrow.up.left.and.arrow.down.right", text: "Pinch to zoom")
                helpRow(icon: "hand.tap", text: "Tap a point for details")
                helpRow(icon: "magnifyingglass", text: "Search to highlight")
            }

            Divider()

            Text("Points close together = similar content")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 220)
    }

    private func helpRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))

            TextField("Search chunks...", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
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
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Button {
                withAnimation { isSearching = false }
                searchQuery = ""
                highlightedPointIndices = []
            } label: {
                Text("Done")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 60)
        .padding(.top, 12)
    }

    private var onboardingTip: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)

            Text("Drag to explore • Pinch to zoom • Close points = similar ideas")
                .font(.caption)
                .foregroundColor(.white)

            Button {
                withAnimation {
                    hasSeenOnboarding = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.black.opacity(0.7))
        )
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Detail card shown when a point is tapped
    private func tappedPointDetailCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with close button
            HStack {
                Label("Chunk \(index + 1)", systemImage: "doc.text.fill")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showPointDetail = false
                        tappedPointIndex = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Document name
            if index < chunkDocNames.count {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(chunkDocNames[index])
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Chunk text preview
            if index < chunkTexts.count {
                Text(chunkTexts[index])
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Loading chunk data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 16)
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

    private var tuningCard: some View {
        VStack(spacing: 14) {
            sampleOptionRow
            Divider().opacity(0.08)
            pointSizeRow
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(DSColors.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }

    /// Format sample option label - 50K shows as "All"
    private func sampleOptionLabel(_ option: Int) -> String {
        if option >= 50000 { return "All" }
        if option >= 1000 { return "\(option/1000)K" }
        return "\(option)"
    }

    private var sampleOptionRow: some View {
        HStack(spacing: 10) {
            Text("Points")
                .font(.caption)
                .foregroundColor(.secondary)

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
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(sampleLimit == option ? Color.accentColor.opacity(0.16) : DSColors.background)
                        .foregroundColor(sampleLimit == option ? .accentColor : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            InfoButtonView(
                title: "Sampling",
                explanation: "Controls how many embedding points are displayed. 'All' shows up to 50K points (scales point size automatically for performance). Higher limits give complete coverage but may slow rotation."
            )
        }
    }

    /// Automatically scale point size based on point count for performance
    private func autoScalePointSize() {
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
        HStack(spacing: 12) {
            Label("Point size", systemImage: "circle.grid.cross")
                .font(.caption)
                .foregroundColor(.secondary)

            Slider(value: $pointScale, in: 0.6...1.6, step: 0.1)

            Text(String(format: "%.1fx", pointScale))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 44)
        }
    }

    private var sceneOptions: Embedding3DSceneView.SceneOptions {
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

    private func buildSceneAnnotations() -> [Embedding3DSceneView.AnnotationData] {
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

    private var heroHeight: CGFloat { focusMode ? 620 : 460 }
    private var heroHorizontalPadding: CGFloat { focusMode ? 4 : 16 }

    private var sampleCoverageRatio: Double {
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

    private var projectionExplainer: String {
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
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 6) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showHUD.toggle()
                        }
                    }
                )

                ControlToggleButton(
                    icon: "tag.fill",
                    title: "Labels",
                    isActive: showClusterLabels,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            focusMode.toggle()
                        }
                    }
                )

                Button(action: resetScene) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption2)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.12))
                        .foregroundColor(.white)
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
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.14))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(16)
    }

    /// Inline HUD inspired by Apple's Embedding Atlas to explain what the user is seeing.
    @ViewBuilder
    private var sceneHUD: some View {
        if totalPoints > 0 {
            VStack(alignment: .leading, spacing: 12) {
                sampleSummaryBadge
                axisHintPanel
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 6)
            .padding(12)
        }
    }

    private var controlToolbar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Search button
                    ControlToggleButton(
                        icon: "magnifyingglass",
                        title: "Search",
                        isActive: isSearching,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHUD.toggle()
                            }
                        }
                    )

                    ControlToggleButton(
                        icon: "tag.fill",
                        title: "Labels",
                        isActive: showClusterLabels,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
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
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                                focusMode.toggle()
                            }
                        }
                    )

                    Button(action: resetScene) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption2)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.black.opacity(0.08))
                            .foregroundColor(.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
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
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.05))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var sampleSummaryBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.scatter")
                Text(sampleCoverageText)
            }
            .font(.caption)
            .foregroundColor(.primary)

            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group")
                Text(docCoverageText.isEmpty ? projectionExplainer : docCoverageText)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private var axisHintPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var insightHighlights: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Quick insights")
                        .font(.headline)
                    Spacer()
                    Text(projectionExplainer)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)
        }
    }

    private func resetScene() {
        sceneReloadToken = UUID()
    }

    private func backgroundGradient(for style: EmbeddingSceneBackgroundStyle) -> LinearGradient {
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
                HStack(spacing: 4) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                }
                .font(.caption2)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(isActive ? Color.accentColor : Color.black.opacity(0.1))
                .foregroundColor(isActive ? .white : .white.opacity(0.85))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Embedding Space Stats Helpers

    private struct EmbeddingStatMini: View {
        let label: String
        let value: String
        let icon: String
        var color: Color = .purple

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(color.opacity(0.8))
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
    }

    private struct ProjectionDetailRow: View {
        let label: String
        let value: String
        var valueColor: Color = .primary

        var body: some View {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(valueColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(4)
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
                        RoundedRectangle(cornerRadius: 1)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Vector Space Health")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    // Coverage meter
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coverage")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(coverageColor)
                                    .frame(width: geo.size.width * coverage)
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.1f%%", coverage * 100))
                            .font(.system(size: 9, design: .monospaced))
                    }

                    // Density meter
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Density")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(densityColor)
                                    .frame(width: geo.size.width * (1 - sparsity))
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.1f%%", (1 - sparsity) * 100))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
            }
            .padding(10)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(8)
        }

        private var coverageColor: Color {
            if coverage > 0.8 { return .green }
            if coverage > 0.5 { return .yellow }
            return .orange
        }

        private var densityColor: Color {
            let density = 1 - sparsity
            if density > 0.7 { return .green }
            if density > 0.4 { return .blue }
            return .purple
        }
    }

    @ViewBuilder
    private var legendSection: some View {
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
                .padding(.trailing)
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
                HStack(spacing: 10) {
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
                .padding(.leading)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text("\(item.name) • \(item.count) • \(pctStr)")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(DSColors.surface.opacity(selected ? 0.9 : 0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1)
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
                        .animation(.spring(response: 0.4, dampingFraction: 0.92), value: label.id)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(label.accent)
.frame(width: 6, height: 6)
    .shadow(color: label.accent.opacity(0.5), radius: 2, x: 0, y: 0)

                Text(label.title)
.font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
.foregroundColor(.primary)

                if let keyword = keywordTag {
                    Text("·")
.font(.system(size: 9, weight: .medium))
    .foregroundColor(.secondary.opacity(0.7))
                    Text(keyword)
.font(.system(size: 10, weight: .medium, design: .rounded))
    .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
.padding(.horizontal, 8)
    .padding(.vertical, 4)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: insight.icon)
                        .foregroundColor(insight.accent)
                    Text(insight.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Text(insight.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(DSColors.background)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(insight.accent.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(14)
        }
    }

// MARK: - Filtering

    private func filteredArrays() -> ([SCNVector3], [PlatformColor]) {
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
    private func buildInsights(
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

    private func buildAnnotationLabels(
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

    // MARK: - Intelligent Axis Analysis

    /// Analyze what content appears at the extremes of each projection axis
    /// Returns content-derived labels like "Baking ↔ Grilling" based on actual chunk content
    private func analyzeAxisLabels(
        coords: [SIMD3<Float>],
        chunks: [DocumentChunk]
    ) -> Embedding3DSceneView.AxisLabels {
        guard coords.count >= 6, coords.count == chunks.count else {
            return .placeholder
        }

        // For each axis, find the top N chunks at each extreme
        let extremeSampleSize = max(3, min(10, coords.count / 8)) // 3-10 chunks per extreme

        // Create indexed tuples for sorting
        let indexed = coords.enumerated().map { (idx: $0.offset, coord: $0.element) }

        // X-axis extremes
        let sortedByX = indexed.sorted { $0.coord.x < $1.coord.x }
        let xNegIndices = Array(sortedByX.prefix(extremeSampleSize).map { $0.idx })
        let xPosIndices = Array(sortedByX.suffix(extremeSampleSize).map { $0.idx })

        // Y-axis extremes
        let sortedByY = indexed.sorted { $0.coord.y < $1.coord.y }
        let yNegIndices = Array(sortedByY.prefix(extremeSampleSize).map { $0.idx })
        let yPosIndices = Array(sortedByY.suffix(extremeSampleSize).map { $0.idx })

        // Z-axis extremes
        let sortedByZ = indexed.sorted { $0.coord.z < $1.coord.z }
        let zNegIndices = Array(sortedByZ.prefix(extremeSampleSize).map { $0.idx })
        let zPosIndices = Array(sortedByZ.suffix(extremeSampleSize).map { $0.idx })

        // Use FTS5 terms as a reference vocabulary - these are proven meaningful
        let vocabularySet = Set(fts5TopTerms.map { $0.lowercased() })

        // Build corpus-wide word frequencies for TF-IDF contrast scoring
        // Terms appearing uniformly across ALL chunks are noise, not axis-discriminative
        let globalFreqs = buildGlobalWordFrequencies(chunks: chunks)

        // Greedy deduplication: each axis endpoint claims a unique label
        // so the same keyword never appears at multiple axis endpoints
        var usedLabels = Set<String>()

        let xNegLabel = extractExtremeLabel(indices: xNegIndices, chunks: chunks, vocabulary: vocabularySet, excluding: usedLabels, globalFreqs: globalFreqs, totalChunks: chunks.count)
        if !xNegLabel.isEmpty { usedLabels.insert(xNegLabel.lowercased()) }
        let xPosLabel = extractExtremeLabel(indices: xPosIndices, chunks: chunks, vocabulary: vocabularySet, excluding: usedLabels, globalFreqs: globalFreqs, totalChunks: chunks.count)
        if !xPosLabel.isEmpty { usedLabels.insert(xPosLabel.lowercased()) }
        let yNegLabel = extractExtremeLabel(indices: yNegIndices, chunks: chunks, vocabulary: vocabularySet, excluding: usedLabels, globalFreqs: globalFreqs, totalChunks: chunks.count)
        if !yNegLabel.isEmpty { usedLabels.insert(yNegLabel.lowercased()) }
        let yPosLabel = extractExtremeLabel(indices: yPosIndices, chunks: chunks, vocabulary: vocabularySet, excluding: usedLabels, globalFreqs: globalFreqs, totalChunks: chunks.count)
        if !yPosLabel.isEmpty { usedLabels.insert(yPosLabel.lowercased()) }
        let zNegLabel = extractExtremeLabel(indices: zNegIndices, chunks: chunks, vocabulary: vocabularySet, excluding: usedLabels, globalFreqs: globalFreqs, totalChunks: chunks.count)
        if !zNegLabel.isEmpty { usedLabels.insert(zNegLabel.lowercased()) }
        let zPosLabel = extractExtremeLabel(indices: zPosIndices, chunks: chunks, vocabulary: vocabularySet, excluding: usedLabels, globalFreqs: globalFreqs, totalChunks: chunks.count)

        return Embedding3DSceneView.AxisLabels(
            xNeg: xNegLabel, xPos: xPosLabel,
            yNeg: yNegLabel, yPos: yPosLabel,
            zNeg: zNegLabel, zPos: zPosLabel
        )
    }

    /// Build word → chunk-count map across entire corpus for IDF scoring
    private func buildGlobalWordFrequencies(chunks: [DocumentChunk]) -> [String: Int] {
        var docFreq: [String: Int] = [:]
        for chunk in chunks {
            let uniqueWords = Set(
                chunk.text
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .map { $0.lowercased() }
                    .filter { $0.count >= 3 }
            )
            for word in uniqueWords {
                docFreq[word, default: 0] += 1
            }
            for kw in chunk.metadata.keywords {
                let clean = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if clean.count >= 3 { docFreq[clean, default: 0] += 1 }
            }
        }
        return docFreq
    }

    /// Extract the most distinctive keyword from chunks at an axis extreme.
    /// Uses TF-IDF contrast scoring: penalizes terms appearing uniformly across
    /// all chunks (corpus noise). Prefers terms concentrated at this specific extreme.
    private func extractExtremeLabel(indices: [Int], chunks: [DocumentChunk], vocabulary: Set<String>, excluding: Set<String> = [], globalFreqs: [String: Int] = [:], totalChunks: Int = 1) -> String {
        guard !indices.isEmpty else { return "" }
        let extremeCount = Double(indices.count)
        let totalDocs = max(Double(totalChunks), 1.0)

        // First, try to use chunk metadata keywords (already curated)
        var metadataKeywords: [String: Int] = [:]
        for idx in indices {
            guard idx < chunks.count else { continue }
            for keyword in chunks[idx].metadata.keywords {
                let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.count >= 3 {
                    metadataKeywords[clean.lowercased(), default: 0] += 1
                }
            }
        }

        // If we have metadata keywords, prefer those — but REQUIRE FTS5 validation
        // with TF-IDF contrast scoring to filter corpus-wide noise
        if !metadataKeywords.isEmpty {
            let scored = metadataKeywords
                .filter({ vocabulary.contains($0.key) && !excluding.contains($0.key) })
                .map { kw, count -> (String, Double) in
                    let tf = Double(count) / extremeCount
                    let globalCount = Double(globalFreqs[kw] ?? 1)
                    let idf = log(totalDocs / max(globalCount, 1.0)) + 1.0
                    let concentration = Double(count) / max(globalCount, 1.0)
                    return (kw, tf * idf * (1.0 + concentration))
                }
                .sorted(by: { $0.1 > $1.1 })

            if let topKeyword = scored.first?.0 {
                return topKeyword.prefix(1).uppercased() + topKeyword.dropFirst()
            }
        }

        // Fallback: extract from text content
        let extremeTexts = indices.compactMap { idx -> String? in
            guard idx < chunks.count else { return nil }
            return chunks[idx].text
        }

        guard !extremeTexts.isEmpty else { return "" }

        // Common stopwords to exclude
        let stopwords = Set([
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "dare",
            "ought", "used", "to", "of", "in", "for", "on", "with", "at", "by",
            "from", "as", "into", "through", "during", "before", "after", "above",
            "below", "between", "under", "again", "further", "then", "once", "here",
            "there", "when", "where", "why", "how", "all", "each", "few", "more",
            "most", "other", "some", "such", "no", "nor", "not", "only", "own",
            "same", "so", "than", "too", "very", "just", "also", "now", "and",
            "but", "or", "because", "while", "although", "if", "this", "that",
            "these", "those", "it", "its", "they", "their", "them", "we", "our",
            "you", "your", "he", "she", "him", "her", "his", "i", "me", "my",
            "any", "many", "much", "new", "first", "last", "long", "great", "little",
            "old", "right", "big", "high", "different", "small", "large", "next",
            "early", "young", "important", "public", "bad", "good", "like", "make",
            "get", "see", "know", "take", "come", "think", "look", "want", "give",
            "use", "find", "tell", "ask", "work", "seem", "feel", "try", "leave",
            "call", "put", "keep", "let", "begin", "show", "hear", "play", "run",
            "move", "live", "believe", "hold", "bring", "happen", "write", "provide",
            "sit", "stand", "lose", "pay", "meet", "include", "continue", "set",
            "learn", "change", "lead", "understand", "watch", "follow", "stop",
            "create", "speak", "read", "allow", "add", "spend", "grow", "open",
            "walk", "win", "offer", "remember", "love", "consider", "appear", "buy",
            "wait", "serve", "die", "send", "expect", "build", "stay", "fall", "cut",
            "reach", "kill", "remain", "data", "file", "page", "section", "chapter"
        ])

        // Extract words and count frequency
        var wordCounts: [String: Int] = [:]
        var originalCase: [String: String] = [:] // Store original casing

        for text in extremeTexts {
            // Split into words - reduced minimum to 3 chars
            let words = text
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { word in
                    let lower = word.lowercased()
                    return word.count >= 3 && // At least 3 chars (was 4)
                           word.count <= 20 && // Not too long
                           !stopwords.contains(lower) &&
                           !word.allSatisfy({ $0.isNumber }) // Not all numbers
                }

            for word in words {
                let lower = word.lowercased()
                wordCounts[lower, default: 0] += 1
                // Keep the most "proper" looking case (capitalized or original)
                if originalCase[lower] == nil || (word.first?.isUppercase == true && originalCase[lower]?.first?.isUppercase != true) {
                    originalCase[lower] = word
                }
            }
        }

        // FTS5-validated terms with TF-IDF contrast scoring
        var fts5Scored: [(word: String, score: Double)] = []
        var fallbackScored: [(word: String, score: Double)] = []
        for (word, count) in wordCounts where !excluding.contains(word) {
            let tf = Double(count) / extremeCount
            let globalCount = Double(globalFreqs[word] ?? 1)
            let idf = log(totalDocs / max(globalCount, 1.0)) + 1.0
            let concentration = Double(count) / max(globalCount, 1.0)
            let score = tf * idf * (1.0 + concentration)

            if vocabulary.contains(word) {
                fts5Scored.append((word, score * 2.0))
            } else {
                fallbackScored.append((word, score))
            }
        }

        // Prefer FTS5-validated, fall back to unvalidated only if empty
        let scored = fts5Scored.isEmpty ? fallbackScored : fts5Scored

        // Get top scoring word
        guard let topWord = scored.sorted(by: { $0.score > $1.score }).first?.word else {
            return ""
        }

        // Use original casing if available, otherwise capitalize
        if let original = originalCase[topWord] {
            return original
        }
        return topWord.prefix(1).uppercased() + topWord.dropFirst()
    }

    // MARK: - Data + Projection

    private func loadAndProject() async {
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
                coords3D = ProjectionService.shared.project3D(
                    embeddings: sampledEmbeddings,
                    method: methodKind,
                    seed: rngSeed
                )
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

            // Analyze axis extremes to derive content-specific labels
            let axisLabels = self.analyzeAxisLabels(coords: coords3D, chunks: sampledChunks)

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

    private func saveSampleLimit(_ value: Int) {
        let key = "viz.sampleLimit.\(containerService.activeContainerId.uuidString)"
        UserDefaults.standard.setValue(value, forKey: key)
    }

    private func loadSampleLimitForActive() {
        let key = "viz.sampleLimit.\(containerService.activeContainerId.uuidString)"
        if let v = UserDefaults.standard.value(forKey: key) as? Int, sampleOptions.contains(v) {
            sampleLimit = v
        } else {
            sampleLimit = 2000 // Higher default for full visibility
        }
    }
}

// MARK: - SceneKit SwiftUI Wrapper

struct Embedding3DSceneView: View {
    struct SceneOptions {
        let pointScale: CGFloat
        let autoRotate: Bool
        let showAxes: Bool
        let showLines: Bool
        let depthCue: Bool
        let backgroundStyle: EmbeddingSceneBackgroundStyle
        let projectionMethod: ProjectionMethodKind
        // Dynamic axis labels derived from content analysis
        let axisLabels: AxisLabels
    }

    /// Dynamic axis labels derived from analyzing content at extremes of each axis
    struct AxisLabels {
        let xNeg: String  // Label for negative X direction
        let xPos: String  // Label for positive X direction
        let yNeg: String  // Label for negative Y direction
        let yPos: String  // Label for positive Y direction
        let zNeg: String  // Label for negative Z direction
        let zPos: String  // Label for positive Z direction

        static let placeholder = AxisLabels(
            xNeg: "", xPos: "",
            yNeg: "", yPos: "",
            zNeg: "", zPos: ""
        )
    }

    struct AnnotationData: Identifiable {
        let id = UUID()
        let position: SCNVector3       // Cluster centroid position
        let title: String              // Document/cluster name
        let keywords: [String]         // Top keywords for this cluster
        let color: PlatformColor       // Document accent color
        let detailLevel: Int           // 0=minimal, 1=normal, 2=detailed
        let clusterSize: Int           // Number of points in this cluster
        let isDocumentCluster: Bool    // True = per-doc cluster, False = spatial cluster
    }

    /// Info for a tapped point
    struct TappedPointInfo: Identifiable {
        let id = UUID()
        let index: Int
        let position: SCNVector3
    }

    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: SceneOptions
    let reloadToken: UUID
    let annotations: [AnnotationData]
    var onPointTapped: ((Int, SCNVector3) -> Void)?

    var body: some View {
        SceneViewContainer(
            points: points,
            colors: colors,
            options: options,
            reloadToken: reloadToken,
            annotations: annotations,
            onPointTapped: onPointTapped
        )
        .background(DSColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#if canImport(UIKit)
struct SceneViewContainer: UIViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: Embedding3DSceneView.SceneOptions
    let reloadToken: UUID
    let annotations: [Embedding3DSceneView.AnnotationData]

    // Callback for when a point is tapped
    var onPointTapped: ((Int, SCNVector3) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.delegate = context.coordinator
        configure(view)

        // Add tap gesture for point inspection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        context.coordinator.scnView = view
        context.coordinator.onPointTapped = onPointTapped

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        configure(uiView)
        context.coordinator.onPointTapped = onPointTapped
    }

    private func configure(_ view: SCNView) {
        let _ = reloadToken
        view.scene = buildScene(points: points, colors: colors, options: options, annotations: annotations)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.05 // Throttle to 20fps for performance
        weak var scnView: SCNView?
        var onPointTapped: ((Int, SCNVector3) -> Void)?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let location = gesture.location(in: view)

            // Perform hit test
            let hitResults = view.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .boundingBoxOnly: false
            ])

            // Find the first hit that's a point node
            for result in hitResults {
                if let nodeName = result.node.name, nodeName.hasPrefix("point_") {
                    // Extract point index from name "point_123"
                    let indexStr = nodeName.dropFirst(6) // Remove "point_"
                    if let index = Int(indexStr) {
                        let position = result.node.position
                        onPointTapped?(index, position)
                        return
                    }
                }
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Throttle updates for performance
            guard time - lastUpdateTime > updateInterval else { return }
            lastUpdateTime = time

            guard let scene = renderer.scene else { return }
            updateLabelLOD(scene: scene, pointOfView: renderer.pointOfView)
        }

        private func updateLabelLOD(scene: SCNScene, pointOfView: SCNNode?) {
            guard let camera = pointOfView else { return }
            let cameraPos = camera.position

            // Find the labelLayer node
            scene.rootNode.enumerateChildNodes { node, stop in
                guard node.name == "labelLayer" else { return }

                // Update each cluster label based on distance
                node.enumerateChildNodes { labelNode, _ in
                    // Only process our cluster labels
                    guard let nodeName = labelNode.name, nodeName.hasPrefix("clusterLabel_") else { return }

                    let distance = simd_distance(
                        simd_float3(cameraPos.x, cameraPos.y, cameraPos.z),
                        simd_float3(labelNode.position.x, labelNode.position.y, labelNode.position.z)
                    )

                    // Smooth LOD transitions - labels always visible but scale with distance
                    // Closer = smaller scale (more readable), Farther = larger scale (visible from afar)
                    let (opacity, scale): (Float, Float)

                    if distance < 2.5 {
                        // Very close - small, crisp, high opacity
                        opacity = 0.95
                        scale = 0.8
                    } else if distance < 4.0 {
                        // Close - slightly larger
                        opacity = 0.92
                        scale = 1.0
                    } else if distance < 6.0 {
                        // Medium - normal size
                        opacity = 0.88
                        scale = 1.2
                    } else if distance < 9.0 {
                        // Far - larger to stay readable
                        opacity = 0.82
                        scale = 1.5
                    } else {
                        // Very far - largest, slightly faded
                        opacity = 0.7
                        scale = 1.8
                    }

                    labelNode.opacity = CGFloat(opacity)
                    labelNode.scale = SCNVector3(scale, scale, scale)
                }

                stop.pointee = true // Found labelLayer, stop enumeration
            }
        }
    }
}
#else
struct SceneViewContainer: NSViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: Embedding3DSceneView.SceneOptions
    let reloadToken: UUID
    let annotations: [Embedding3DSceneView.AnnotationData]

    // Callback for when a point is tapped (optional for macOS)
    var onPointTapped: ((Int, SCNVector3) -> Void)?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.delegate = context.coordinator
        configure(view)

        // Add click gesture for point inspection
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(clickGesture)
        context.coordinator.scnView = view
        context.coordinator.onPointTapped = onPointTapped

        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        configure(nsView)
        context.coordinator.onPointTapped = onPointTapped
    }

    private func configure(_ view: SCNView) {
        let _ = reloadToken
        view.scene = buildScene(points: points, colors: colors, options: options, annotations: annotations)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.05 // Throttle to 20fps for performance
        weak var scnView: SCNView?
        var onPointTapped: ((Int, SCNVector3) -> Void)?

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = scnView else { return }
            let location = gesture.location(in: view)

            // Perform hit test
            let hitResults = view.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .boundingBoxOnly: false
            ])

            // Find the first hit that's a point node
            for result in hitResults {
                if let nodeName = result.node.name, nodeName.hasPrefix("point_") {
                    let indexStr = nodeName.dropFirst(6)
                    if let index = Int(indexStr) {
                        let position = result.node.position
                        onPointTapped?(index, position)
                        return
                    }
                }
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Throttle updates for performance
            guard time - lastUpdateTime > updateInterval else { return }
            lastUpdateTime = time

            guard let scene = renderer.scene else { return }
            updateLabelLOD(scene: scene, pointOfView: renderer.pointOfView)
        }

        private func updateLabelLOD(scene: SCNScene, pointOfView: SCNNode?) {
            guard let camera = pointOfView else { return }
            let cameraPos = camera.position

            // Find the labelLayer node
            scene.rootNode.enumerateChildNodes { node, stop in
                guard node.name == "labelLayer" else { return }

                // Update each cluster label based on distance
                node.enumerateChildNodes { labelNode, _ in
                    // Only process our cluster labels
                    guard let nodeName = labelNode.name, nodeName.hasPrefix("clusterLabel_") else { return }

                    let distance = simd_distance(
                        simd_float3(Float(cameraPos.x), Float(cameraPos.y), Float(cameraPos.z)),
                        simd_float3(Float(labelNode.position.x), Float(labelNode.position.y), Float(labelNode.position.z))
                    )

                    // Smooth LOD transitions - labels always visible but scale with distance
                    let (opacity, scale): (Float, Float)

                    if distance < 2.5 {
                        opacity = 0.95
                        scale = 0.8
                    } else if distance < 4.0 {
                        opacity = 0.92
                        scale = 1.0
                    } else if distance < 6.0 {
                        opacity = 0.88
                        scale = 1.2
                    } else if distance < 9.0 {
                        opacity = 0.82
                        scale = 1.5
                    } else {
                        opacity = 0.7
                        scale = 1.8
                    }

                    labelNode.opacity = CGFloat(opacity)
                    labelNode.scale = SCNVector3(scale, scale, scale)
                }

                stop.pointee = true
            }
        }
    }
}
#endif

// MARK: - Scene construction

private func buildScene(points: [SCNVector3], colors: [PlatformColor], options: Embedding3DSceneView.SceneOptions, annotations: [Embedding3DSceneView.AnnotationData]) -> SCNScene {
    let scene = SCNScene()
    scene.rootNode.addChildNode(makeCameraNode(depthCue: options.depthCue))

    let contentRoot = SCNNode()
    contentRoot.name = "contentRoot"
    scene.rootNode.addChildNode(contentRoot)

    // Always add a subtle ground plane and grid for spatial reference
    contentRoot.addChildNode(makeGroundPlane())

    // Add intuitive axes with human-readable labels
    if options.showAxes {
        contentRoot.addChildNode(makeIntuiveAxesNode(projectionMethod: options.projectionMethod, axisLabels: options.axisLabels))
    }

    addPointNodes(points, colors, scale: options.pointScale, depthCue: options.depthCue, into: contentRoot)
    addClusterLabels(annotations, backgroundStyle: options.backgroundStyle, into: contentRoot)
    if options.showLines {
        addInterClusterLines(annotations, backgroundStyle: options.backgroundStyle, into: contentRoot)
    }
    addLighting(into: scene.rootNode, depthCue: options.depthCue)
    applyBackground(style: options.backgroundStyle, to: scene)
    applyAutoRotate(options.autoRotate, to: contentRoot)

    if options.depthCue {
        scene.fogStartDistance = 5.0
        scene.fogEndDistance = 12.0
        scene.fogDensityExponent = 1.0
        #if canImport(UIKit)
        scene.fogColor = options.backgroundStyle.fogColor.withAlphaComponent(0.7)
        #else
        scene.fogColor = options.backgroundStyle.fogColor.withAlphaComponent(0.7)
        #endif
    } else {
        scene.fogStartDistance = 0
        scene.fogEndDistance = 0
    }

    return scene
}

// MARK: - Ground Plane (Spatial Reference)

private func makeGroundPlane() -> SCNNode {
    let container = SCNNode()

    // Subtle grid floor - sized to match full axis extent (6.0)
    // OPTIMIZATION: Fewer grid lines for better performance
    let gridSize: Float = 6.0
    let gridLines = 6 // Reduced from 12
    let spacing = gridSize / Float(gridLines)

    // Share geometry for all grid lines
    let lineGeo = SCNCylinder(radius: 0.004, height: CGFloat(gridSize))
    let lineMat = SCNMaterial()
    #if canImport(UIKit)
        lineMat.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
    #else
        lineMat.diffuse.contents = NSColor.white.withAlphaComponent(0.08)
    #endif
    lineMat.lightingModel = .constant
    lineGeo.materials = [lineMat]

    for i in 0 ... gridLines {
        let offset = -gridSize / 2 + Float(i) * spacing

        // X-axis lines (share geometry)
        let xNode = SCNNode(geometry: lineGeo)
        xNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        xNode.position = SCNVector3(0, -3.0, offset)
        container.addChildNode(xNode)

        // Z-axis lines (share geometry)
        let zNode = SCNNode(geometry: lineGeo)
        zNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        zNode.position = SCNVector3(offset, -3.0, 0)
        container.addChildNode(zNode)
    }

    return container
}

// MARK: - Clean Arrow Axes (visible, no text clutter)

private func makeIntuiveAxesNode(projectionMethod: ProjectionMethodKind, axisLabels: Embedding3DSceneView.AxisLabels) -> SCNNode {
    let node = SCNNode()

    // Bright axis colors
    #if canImport(UIKit)
    let xColor = UIColor.systemRed
    let yColor = UIColor.systemGreen
    let zColor = UIColor.systemBlue
    #else
    let xColor = NSColor.systemRed
    let yColor = NSColor.systemGreen
    let zColor = NSColor.systemBlue
    #endif

    // Create arrow axes - 5 units in each direction from origin
    let axisHalfLength: Float = 5.0

    // X axis (red) - horizontal
    node.addChildNode(makeArrowAxis(from: SCNVector3(-axisHalfLength, 0, 0),
                                    to: SCNVector3(axisHalfLength, 0, 0),
                                    color: xColor))

    // Y axis (green) - vertical
    node.addChildNode(makeArrowAxis(from: SCNVector3(0, -axisHalfLength, 0),
                                    to: SCNVector3(0, axisHalfLength, 0),
                                    color: yColor))

    // Z axis (blue) - depth
    node.addChildNode(makeArrowAxis(from: SCNVector3(0, 0, -axisHalfLength),
                                    to: SCNVector3(0, 0, axisHalfLength),
                                    color: zColor))

    // Origin sphere
    node.addChildNode(makeOriginMarker())

    // === DYNAMIC CONTENT-DERIVED AXIS LABELS ===
    // Show content-specific labels at each axis endpoint (e.g., "Baking ↔ Grilling")
    // If labels are empty, fall back to minimal X/Y/Z

    let xPosText = axisLabels.xPos.isEmpty ? "X" : axisLabels.xPos
    let yPosText = axisLabels.yPos.isEmpty ? "Y" : axisLabels.yPos
    let zPosText = axisLabels.zPos.isEmpty ? "Z" : axisLabels.zPos

    // Add text labels at the positive end of each axis
    node.addChildNode(makeAxisLabel(text: xPosText,
                                    position: SCNVector3(axisHalfLength + 0.4, 0, 0),
                                    color: xColor))
    node.addChildNode(makeAxisLabel(text: yPosText,
                                    position: SCNVector3(0, axisHalfLength + 0.4, 0),
                                    color: yColor))
    node.addChildNode(makeAxisLabel(text: zPosText,
                                    position: SCNVector3(0, 0, axisHalfLength + 0.4),
                                    color: zColor))

    // Add labels at the negative end of each axis (if we have content-derived labels)
    if !axisLabels.xNeg.isEmpty {
        node.addChildNode(makeAxisLabel(text: axisLabels.xNeg,
                                        position: SCNVector3(-axisHalfLength - 0.4, 0, 0),
                                        color: xColor))
    }
    if !axisLabels.yNeg.isEmpty {
        node.addChildNode(makeAxisLabel(text: axisLabels.yNeg,
                                        position: SCNVector3(0, -axisHalfLength - 0.4, 0),
                                        color: yColor))
    }
    if !axisLabels.zNeg.isEmpty {
        node.addChildNode(makeAxisLabel(text: axisLabels.zNeg,
                                        position: SCNVector3(0, 0, -axisHalfLength - 0.4),
                                        color: zColor))
    }

    // Add a subtle hint near origin explaining the labels represent content themes
    let hasContentLabels = !axisLabels.xPos.isEmpty || !axisLabels.yPos.isEmpty || !axisLabels.zPos.isEmpty
    if hasContentLabels {
        node.addChildNode(makeAxisHintLabel(text: "← themes from content →",
                                            position: SCNVector3(0, -0.4, 0),
                                            axis: .x))
    } else {
        // Fallback hint based on projection method
        let hintText: String
        switch projectionMethod {
        case .pca, .rp:
            hintText = "← distance matters →"
        case .tsne:
            hintText = "← clusters matter →"
        case .umap:
            hintText = "← structure matters →"
        }
        node.addChildNode(makeAxisHintLabel(text: hintText,
                                            position: SCNVector3(0, -0.4, 0),
                                            axis: .x))
    }

    return node
}

/// Creates a floating label for an axis endpoint
private func makeAxisLabel(text: String, position: SCNVector3, color: PlatformColor) -> SCNNode {
    let textGeo = SCNText(string: text, extrusionDepth: 0.02)

    #if canImport(UIKit)
    textGeo.font = UIFont.systemFont(ofSize: 0.35, weight: .bold)
    #else
    textGeo.font = NSFont.systemFont(ofSize: 0.35, weight: .bold)
    #endif
    textGeo.flatness = 0.02
    textGeo.chamferRadius = 0.01

    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.emission.contents = color
    mat.emission.intensity = 0.9
    mat.lightingModel = .constant
    mat.isDoubleSided = true
    textGeo.materials = [mat]

    let textNode = SCNNode(geometry: textGeo)

    // Center the text
    let (minBound, maxBound) = textGeo.boundingBox
    let textWidth = maxBound.x - minBound.x
    let textHeight = maxBound.y - minBound.y
    textNode.pivot = SCNMatrix4MakeTranslation(
        minBound.x + textWidth / 2,
        minBound.y + textHeight / 2,
        0
    )

    let container = SCNNode()
    container.addChildNode(textNode)
    container.position = position

    // Billboard constraint so it always faces camera
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = [.X, .Y]
    container.constraints = [billboard]

    return container
}

/// Creates a smaller hint label near the origin explaining what the axis represents
private func makeAxisHintLabel(text: String, position: SCNVector3, axis: AxisDirection) -> SCNNode {
    let textGeo = SCNText(string: text, extrusionDepth: 0.01)

    #if canImport(UIKit)
    textGeo.font = UIFont.systemFont(ofSize: 0.18, weight: .medium)
    let textColor = UIColor.white.withAlphaComponent(0.5)
    #else
    textGeo.font = NSFont.systemFont(ofSize: 0.18, weight: .medium)
    let textColor = NSColor.white.withAlphaComponent(0.5)
    #endif
    textGeo.flatness = 0.02

    let mat = SCNMaterial()
    mat.diffuse.contents = textColor
    mat.emission.contents = textColor
    mat.emission.intensity = 0.4
    mat.lightingModel = .constant
    mat.isDoubleSided = true
    textGeo.materials = [mat]

    let textNode = SCNNode(geometry: textGeo)

    // Center the text
    let (minBound, maxBound) = textGeo.boundingBox
    let textWidth = maxBound.x - minBound.x
    let textHeight = maxBound.y - minBound.y
    textNode.pivot = SCNMatrix4MakeTranslation(
        minBound.x + textWidth / 2,
        minBound.y + textHeight / 2,
        0
    )

    let container = SCNNode()
    container.addChildNode(textNode)
    container.position = position

    // Billboard constraint
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = [.X, .Y]
    container.constraints = [billboard]

    return container
}

/// Creates an arrow from start to end with a cone tip
private func makeArrowAxis(from start: SCNVector3, to end: SCNVector3, color: PlatformColor) -> SCNNode {
    let container = SCNNode()

    // Calculate direction and length
    let dx = end.x - start.x
    let dy = end.y - start.y
    let dz = end.z - start.z
    let length = sqrt(dx * dx + dy * dy + dz * dz)

    // Shaft (cylinder) - visible but not too thick
    let shaftLength = length - 0.3 // Leave room for cone tip
    let shaft = SCNCylinder(radius: 0.025, height: CGFloat(shaftLength))
    let shaftMat = SCNMaterial()
    shaftMat.diffuse.contents = color
    shaftMat.emission.contents = color
    shaftMat.emission.intensity = 0.8
    shaftMat.lightingModel = .constant
    shaft.materials = [shaftMat]

    let shaftNode = SCNNode(geometry: shaft)
    // Position at midpoint
    shaftNode.position = SCNVector3((start.x + end.x) / 2 - dx * 0.2 / length,
                                    (start.y + end.y) / 2 - dy * 0.2 / length,
                                    (start.z + end.z) / 2 - dz * 0.2 / length)

    // Rotate to align with axis
    if abs(dy) > abs(dx), abs(dy) > abs(dz) {
        // Y axis - no rotation needed
    } else if abs(dx) > abs(dz) {
        // X axis
        shaftNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
    } else {
        // Z axis
        shaftNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    }

    container.addChildNode(shaftNode)

    // Cone tip at positive end
    let cone = SCNCone(topRadius: 0, bottomRadius: 0.06, height: 0.25)
    let coneMat = SCNMaterial()
    coneMat.diffuse.contents = color
    coneMat.emission.contents = color
    coneMat.emission.intensity = 1.0
    coneMat.lightingModel = .constant
    cone.materials = [coneMat]

    let coneNode = SCNNode(geometry: cone)
    coneNode.position = SCNVector3(end.x - dx * 0.1 / length,
                                   end.y - dy * 0.1 / length,
                                   end.z - dz * 0.1 / length)

    // Rotate cone to point in direction
    if abs(dy) > abs(dx), abs(dy) > abs(dz) {
        if dy < 0 { coneNode.eulerAngles = SCNVector3(Float.pi, 0, 0) }
    } else if abs(dx) > abs(dz) {
        coneNode.eulerAngles = SCNVector3(0, 0, dx > 0 ? -Float.pi / 2 : Float.pi / 2)
    } else {
        coneNode.eulerAngles = SCNVector3(dz > 0 ? Float.pi / 2 : -Float.pi / 2, 0, 0)
    }

    container.addChildNode(coneNode)

    return container
}

/// White sphere at origin
private func makeOriginMarker() -> SCNNode {
    let sphere = SCNSphere(radius: 0.06)
    let mat = SCNMaterial()
    #if canImport(UIKit)
        mat.diffuse.contents = UIColor.white
        mat.emission.contents = UIColor.white
    #else
        mat.diffuse.contents = NSColor.white
        mat.emission.contents = NSColor.white
    #endif
    mat.emission.intensity = 1.0
    mat.lightingModel = .constant
    sphere.materials = [mat]
    return SCNNode(geometry: sphere)
}

private func makeCameraNode(depthCue: Bool) -> SCNNode {
    let node = SCNNode()
    let camera = SCNCamera()
    camera.zNear = 0.01
    camera.zFar = 100
    camera.wantsDepthOfField = depthCue
    if depthCue {
        camera.focusDistance = 5.5
        camera.fStop = 10
    }
    node.camera = camera
    // Camera positioned for optimal viewing of a 4.5-unit data cube with 5-unit axes
    node.position = SCNVector3(3.5, 2.5, 6.0)
    node.look(at: SCNVector3(0, 0, 0))
    return node
}

private func addPointNodes(_ points: [SCNVector3], _ colors: [PlatformColor], scale: CGFloat, depthCue: Bool, into root: SCNNode) {
    let count = min(points.count, colors.count)
    guard count > 0 else { return }

    // Size relative to point count: fewer points = larger, more points = smaller
    // Range: 10 points → 0.12 radius, 500 points → 0.025 radius
    let countFactor = max(0.3, min(1.0, 50.0 / CGFloat(count)))
    let baseRadius: CGFloat = 0.08 * countFactor
    let radius = max(0.02, min(0.12, baseRadius * scale))

    // OPTIMIZATION: Reduce geometry complexity based on point count
    // More points = simpler spheres (8 segments vs 16 for few points)
    let segmentCount: Int
    if count > 1000 {
        segmentCount = 6 // Very simple for large datasets
    } else if count > 500 {
        segmentCount = 8
    } else if count > 100 {
        segmentCount = 10
    } else {
        segmentCount = 12
    }

    // Group points by color for efficient batching
    var colorToIndices: [Int: [Int]] = [:]
    colorToIndices.reserveCapacity(20) // Typical doc count
    for index in 0..<count {
        let colorHash = colors[index].hash
        colorToIndices[colorHash, default: []].append(index)
    }

    // Create one sphere geometry per color (true geometry sharing)
    // Each color group shares the SAME geometry instance
    for (_, indices) in colorToIndices {
        guard let firstIndex = indices.first else { continue }
        let color = colors[firstIndex]

        // Create shared geometry for this color group
        let sharedSphere = SCNSphere(radius: radius)
        sharedSphere.segmentCount = segmentCount

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.emission.contents = color
        material.emission.intensity = 0.85
        material.transparency = 0.92
        sharedSphere.materials = [material]

        // Create nodes sharing this geometry
        for index in indices {
            let node = SCNNode(geometry: sharedSphere)
            node.position = points[index]
            node.name = "point_\(index)"
            root.addChildNode(node)
        }
    }
}

// MARK: - Cluster Labels (Background-Aware with Arrows)

private func addClusterLabels(_ annotations: [Embedding3DSceneView.AnnotationData], backgroundStyle: EmbeddingSceneBackgroundStyle, into root: SCNNode) {
    guard !annotations.isEmpty else { return }

    // Create a dedicated label layer node that renders on top of everything
    let labelLayer = SCNNode()
    labelLayer.name = "labelLayer"
    labelLayer.renderingOrder = 100

    // === PHASE 1: Calculate scene bounds and spread distance ===
    let allPositions = annotations.map { simd_float3(Float($0.position.x), Float($0.position.y), Float($0.position.z)) }
    let centroid = allPositions.reduce(simd_float3.zero, +) / Float(allPositions.count)
    let maxDistFromCenter = allPositions.map { simd_length($0 - centroid) }.max() ?? 1.0

    // Spread labels VERY far out - at least 2.5x the data spread, minimum 3.5 units
    let baseSpreadRadius = max(maxDistFromCenter * 2.8, 3.5)

    // === PHASE 2: Sort annotations by importance (document clusters first, larger clusters prioritized) ===
    let sortedAnnotations = annotations.sorted { a, b in
        if a.isDocumentCluster != b.isDocumentCluster { return a.isDocumentCluster }
        return a.clusterSize > b.clusterSize
    }

    // === PHASE 3: Calculate initial positions using golden angle spiral for maximum spread ===
    var labelPositions: [simd_float3] = []
    let goldenAngle: Float = .pi * (3.0 - sqrt(5.0)) // ~137.5° - optimal distribution

    for (index, annotation) in sortedAnnotations.enumerated() {
        let clusterPos = simd_float3(Float(annotation.position.x), Float(annotation.position.y), Float(annotation.position.z))

        // Calculate direction from scene centroid through cluster point (push labels outward)
        var outwardDir = simd_normalize(clusterPos - centroid)
        if simd_length(outwardDir) < 0.01 {
            // Fallback if cluster is at centroid
            outwardDir = simd_float3(cos(Float(index)), 0.3, sin(Float(index)))
        }

        // Use golden angle spiral for vertical distribution
        let spiralOffset = goldenAngle * Float(index)
        let verticalAngle = Float(index) / Float(max(sortedAnnotations.count, 1)) * Float.pi - Float.pi / 2

        // Add rotation around vertical axis based on spiral
        let rotatedX = outwardDir.x * cos(spiralOffset) - outwardDir.z * sin(spiralOffset)
        let rotatedZ = outwardDir.x * sin(spiralOffset) + outwardDir.z * cos(spiralOffset)
        outwardDir = simd_normalize(simd_float3(rotatedX, outwardDir.y + sin(verticalAngle) * 0.5, rotatedZ))

        // Distance varies by type: document clusters further out
        let distanceMultiplier: Float = annotation.isDocumentCluster ? 1.4 : 1.1
        let spreadDist = baseSpreadRadius * distanceMultiplier

        // Add some index-based variation to prevent exact alignments
        let jitter = Float(index % 3) * 0.2 - 0.2

        let labelPos = clusterPos + outwardDir * (spreadDist + jitter)
        labelPositions.append(labelPos)
    }

    // === PHASE 4: Collision detection and resolution ===
    let minSeparation: Float = 0.8 // Minimum distance between labels
    let iterations = 4 // Number of repulsion passes

    for _ in 0..<iterations {
        for i in 0..<labelPositions.count {
            for j in (i + 1)..<labelPositions.count {
                let delta = labelPositions[j] - labelPositions[i]
                let dist = simd_length(delta)

                if dist < minSeparation && dist > 0.001 {
                    // Push labels apart
                    let overlap = minSeparation - dist
                    let pushDir = simd_normalize(delta)
                    let pushAmount = overlap * 0.6

                    labelPositions[i] -= pushDir * pushAmount
                    labelPositions[j] += pushDir * pushAmount
                }
            }
        }
    }

    // === PHASE 5: Create label nodes with arrows ===
    for (index, annotation) in sortedAnnotations.enumerated() {
        let labelPos = labelPositions[index]
        let clusterPos = annotation.position

        // Create arrow pointing FROM label TO cluster centroid
        let arrowNode = makeArrowToCluster(
            from: SCNVector3(labelPos.x, labelPos.y, labelPos.z),
            to: clusterPos,
            color: annotation.color,
            backgroundStyle: backgroundStyle,
            isDocumentCluster: annotation.isDocumentCluster
        )

        // Create the badge
        let labelNode = makeClusterBadge(
            title: annotation.title,
            clusterSize: annotation.clusterSize,
            detailLevel: annotation.detailLevel,
            keywords: annotation.keywords,
            accentColor: annotation.color,
            backgroundStyle: backgroundStyle,
            priority: index,
            isDocumentCluster: annotation.isDocumentCluster
        )

        labelNode.position = SCNVector3(labelPos.x, labelPos.y, labelPos.z)
        labelLayer.addChildNode(arrowNode)
        labelLayer.addChildNode(labelNode)
    }

    root.addChildNode(labelLayer)
}

// MARK: - Inter-Cluster Relationship Lines

/// Draws faint connection lines between nearby clusters to show semantic relationships.
/// Only connects clusters whose centroids are within a threshold distance — closer means more related.
private func addInterClusterLines(_ annotations: [Embedding3DSceneView.AnnotationData], backgroundStyle: EmbeddingSceneBackgroundStyle, into root: SCNNode) {
    guard annotations.count >= 2 else { return }

    let lineLayer = SCNNode()
    lineLayer.name = "interClusterLines"
    lineLayer.renderingOrder = 5 // Behind cluster labels (100) but above points

    // Calculate median pairwise distance to set adaptive threshold
    var allDists: [Float] = []
    for i in 0..<annotations.count {
        for j in (i + 1)..<annotations.count {
            let pi = simd_float3(Float(annotations[i].position.x), Float(annotations[i].position.y), Float(annotations[i].position.z))
            let pj = simd_float3(Float(annotations[j].position.x), Float(annotations[j].position.y), Float(annotations[j].position.z))
            allDists.append(simd_distance(pi, pj))
        }
    }
    allDists.sort()

    // Connect pairs within the 40th percentile of distances (closest ~40%)
    let threshold: Float
    if allDists.count >= 2 {
        let p40Index = Int(Float(allDists.count) * 0.4)
        threshold = allDists[min(p40Index, allDists.count - 1)]
    } else {
        threshold = 3.0
    }

    // Maximum lines to avoid visual clutter
    let maxLines = min(annotations.count * 2, 15)
    var lineCount = 0

    // Sort pairs by distance (closest first) for priority drawing
    var pairs: [(i: Int, j: Int, dist: Float)] = []
    for i in 0..<annotations.count {
        for j in (i + 1)..<annotations.count {
            let pi = simd_float3(Float(annotations[i].position.x), Float(annotations[i].position.y), Float(annotations[i].position.z))
            let pj = simd_float3(Float(annotations[j].position.x), Float(annotations[j].position.y), Float(annotations[j].position.z))
            let dist = simd_distance(pi, pj)
            if dist <= threshold && dist > 0.1 {
                pairs.append((i, j, dist))
            }
        }
    }
    pairs.sort { $0.dist < $1.dist }

    for pair in pairs {
        guard lineCount < maxLines else { break }

        let a = annotations[pair.i]
        let b = annotations[pair.j]
        let posA = simd_float3(Float(a.position.x), Float(a.position.y), Float(a.position.z))
        let posB = simd_float3(Float(b.position.x), Float(b.position.y), Float(b.position.z))

        // Opacity inversely proportional to distance (closer = slightly more visible)
        let normalizedDist = pair.dist / max(threshold, 0.01)
        let alpha = CGFloat(max(0.04, 0.14 * (1.0 - Double(normalizedDist))))

        // Create hair-thin cylinder between the two cluster centroids
        let midpoint = (posA + posB) * 0.5
        let length = CGFloat(pair.dist)
        let lineGeo = SCNCylinder(radius: 0.004, height: length)

        // Use cluster color at very low opacity — visible on rotation, not distracting
        let lineMat = SCNMaterial()
        #if canImport(UIKit)
        lineMat.diffuse.contents = a.color.withAlphaComponent(alpha)
        lineMat.emission.contents = a.color.withAlphaComponent(alpha * 0.5)
        #else
        lineMat.diffuse.contents = a.color.withAlphaComponent(alpha)
        lineMat.emission.contents = a.color.withAlphaComponent(alpha * 0.5)
        #endif
        lineMat.emission.intensity = 0.3
        lineMat.lightingModel = .constant
        lineMat.isDoubleSided = true
        lineMat.writesToDepthBuffer = false
        lineMat.readsFromDepthBuffer = true
        lineGeo.materials = [lineMat]

        let lineNode = SCNNode(geometry: lineGeo)
        lineNode.position = SCNVector3(midpoint.x, midpoint.y, midpoint.z)

        // Rotate cylinder to align between the two points
        let direction = simd_normalize(posB - posA)
        let up = simd_float3(0, 1, 0)
        let dotProduct = simd_dot(direction, up)

        if abs(dotProduct) > 0.999 {
            // Nearly parallel to Y — minimal rotation needed
            if dotProduct < 0 { lineNode.eulerAngles.z = .pi }
        } else {
            let crossVec = simd_cross(up, direction)
            let angle = acos(min(max(dotProduct, -1), 1))
            lineNode.rotation = SCNVector4(crossVec.x, crossVec.y, crossVec.z, angle)
        }

        lineLayer.addChildNode(lineNode)
        lineCount += 1
    }

    root.addChildNode(lineLayer)
}

/// Creates an arrow line from label position pointing to cluster centroid
private func makeArrowToCluster(
    from labelPos: SCNVector3,
    to clusterPos: SCNVector3,
    color: PlatformColor,
    backgroundStyle: EmbeddingSceneBackgroundStyle,
    isDocumentCluster: Bool
) -> SCNNode {
    let container = SCNNode()

    // Calculate direction and length
    let dx = Float(clusterPos.x) - Float(labelPos.x)
    let dy = Float(clusterPos.y) - Float(labelPos.y)
    let dz = Float(clusterPos.z) - Float(labelPos.z)
    let length = sqrt(dx * dx + dy * dy + dz * dz)

    guard length > 0.1 else { return container } // Skip if too short

    // Shorten the line so it doesn't overlap with label or cluster
    let shortenAmount: Float = isDocumentCluster ? 0.15 : 0.1
    let effectiveLength = max(0.1, length - shortenAmount * 2)

    // Create the line (cylinder) — subtle enough to not clutter, visible enough to trace
    let lineRadius: CGFloat = isDocumentCluster ? 0.005 : 0.003
    let line = SCNCylinder(radius: lineRadius, height: CGFloat(effectiveLength))

    let lineMat = SCNMaterial()
    lineMat.diffuse.contents = color.withAlphaComponent(0.35)
    lineMat.emission.contents = color
    lineMat.emission.intensity = backgroundStyle.isDark ? 0.25 : 0.12
    lineMat.lightingModel = .constant
    lineMat.writesToDepthBuffer = false
    lineMat.readsFromDepthBuffer = false
    line.materials = [lineMat]

    let lineNode = SCNNode(geometry: line)

    // Position at midpoint
    let midX = (Float(labelPos.x) + Float(clusterPos.x)) / 2
    let midY = (Float(labelPos.y) + Float(clusterPos.y)) / 2
    let midZ = (Float(labelPos.z) + Float(clusterPos.z)) / 2
    lineNode.position = SCNVector3(xFloat: midX, yFloat: midY, zFloat: midZ)

    // Rotate to point from label to cluster
    // Default cylinder is along Y axis, we need to rotate it
    let direction = simd_normalize(simd_float3(dx, dy, dz))
    let up = simd_float3(0, 1, 0)

    // Calculate rotation quaternion
    let dot = simd_dot(up, direction)
    if abs(dot) < 0.999 {
        let cross = simd_cross(up, direction)
        let angle = acos(dot)
        lineNode.rotation = SCNVector4(xFloat: cross.x, yFloat: cross.y, zFloat: cross.z, wFloat: angle)
    } else if dot < 0 {
        // Pointing down
        lineNode.eulerAngles = SCNVector3(xFloat: Float.pi, yFloat: 0, zFloat: 0)
    }

    container.addChildNode(lineNode)

    // Create arrowhead (cone) pointing at cluster
    if isDocumentCluster {
        let coneHeight: CGFloat = 0.06
        let coneRadius: CGFloat = 0.025
        let cone = SCNCone(topRadius: 0, bottomRadius: coneRadius, height: coneHeight)

        let coneMat = SCNMaterial()
        coneMat.diffuse.contents = color
        coneMat.emission.contents = color
        coneMat.emission.intensity = 0.5
        coneMat.lightingModel = .constant
        cone.materials = [coneMat]

        let coneNode = SCNNode(geometry: cone)

        // Position near cluster (but not at it)
        let arrowTipDist = shortenAmount + Float(coneHeight) / 2
        let tipX = Float(clusterPos.x) - direction.x * arrowTipDist
        let tipY = Float(clusterPos.y) - direction.y * arrowTipDist
        let tipZ = Float(clusterPos.z) - direction.z * arrowTipDist
        coneNode.position = SCNVector3(xFloat: tipX, yFloat: tipY, zFloat: tipZ)

        // Rotate cone to point at cluster
        if abs(dot) < 0.999 {
            let cross = simd_cross(up, direction)
            let angle = acos(dot)
            coneNode.rotation = SCNVector4(xFloat: cross.x, yFloat: cross.y, zFloat: cross.z, wFloat: angle)
        } else if dot < 0 {
            coneNode.eulerAngles = SCNVector3(xFloat: Float.pi, yFloat: 0, zFloat: 0)
        }

        container.addChildNode(coneNode)
    }

    return container
}

/// Creates a floating cluster label - contrast-aware, with document name, count, and optional keywords
private func makeClusterBadge(
    title: String,
    clusterSize: Int,
    detailLevel: Int,
    keywords: [String],
    accentColor: PlatformColor,
    backgroundStyle: EmbeddingSceneBackgroundStyle,
    priority: Int,
    isDocumentCluster: Bool = true
) -> SCNNode {
    let container = SCNNode()
    container.name = "clusterLabel_\(priority)"
    container.renderingOrder = 101 + priority

    // === DETERMINE LABEL STYLE ===
    let isKeywordLabel = title.hasPrefix("#")
    let isSubCluster = !isDocumentCluster && !isKeywordLabel

    // === BUILD THE LABEL TEXT ===
    var displayText: String
    if isKeywordLabel {
        // Keyword hotspot: just the hashtag
        displayText = title
    } else if isDocumentCluster {
        // Main document cluster: Name (count) + keywords
        let truncatedTitle = String(title.prefix(22)) + (title.count > 22 ? "…" : "")
        displayText = "\(truncatedTitle) (\(clusterSize))"
        if detailLevel >= 1 && !keywords.isEmpty {
            // Filter out keywords that are substrings of the title (avoid "API API" duplication)
            let titleLower = title.lowercased()
            let filteredKeywords = keywords.filter { kw in
                let kwLower = kw.lowercased()
                return !titleLower.contains(kwLower) && !kwLower.contains(titleLower.prefix(4))
            }
            // Deduplicate keywords (case-insensitive)
            var seenKeywords: Set<String> = []
            let uniqueKeywords = filteredKeywords.filter { kw in
                let lower = kw.lowercased()
                if seenKeywords.contains(lower) { return false }
                seenKeywords.insert(lower)
                return true
            }
            if !uniqueKeywords.isEmpty {
                let keywordStr = uniqueKeywords.prefix(3).joined(separator: " • ")
                displayText += "\n\(keywordStr)"
            }
        }
    } else {
        // Sub-cluster: Section name only, smaller
        let truncatedTitle = String(title.prefix(18)) + (title.count > 18 ? "…" : "")
        displayText = "▸ \(truncatedTitle)"
        if !keywords.isEmpty {
            // Filter keywords that match section title
            let titleLower = title.lowercased()
            let filtered = keywords.filter { !titleLower.contains($0.lowercased()) }
            if let firstKw = filtered.first {
                displayText += " • \(firstKw)"
            }
        }
    }

    let textGeo = SCNText(string: displayText, extrusionDepth: isDocumentCluster ? 0.02 : 0.012)

    // === DYNAMIC FONT SIZE (larger for readability) ===
    let baseFontSize: CGFloat
    if isKeywordLabel {
        baseFontSize = 0.18 // Larger for keyword tags
    } else if isDocumentCluster {
        baseFontSize = 0.24 + CGFloat(min(clusterSize, 80)) / 400.0 // Scale with cluster size, bigger base
    } else {
        baseFontSize = 0.16 // Sub-clusters slightly smaller
    }

    #if canImport(UIKit)
        let fontWeight: UIFont.Weight = isDocumentCluster ? .semibold : (isKeywordLabel ? .medium : .regular)
        textGeo.font = UIFont.systemFont(ofSize: baseFontSize, weight: fontWeight)
    #else
        let fontWeight: NSFont.Weight = isDocumentCluster ? .semibold : (isKeywordLabel ? .medium : .regular)
        textGeo.font = NSFont.systemFont(ofSize: baseFontSize, weight: fontWeight)
    #endif
    textGeo.flatness = 0.02 // Much smoother curves (lower = smoother but more geometry)
    textGeo.chamferRadius = 0.005 // Slightly rounded edges

    // === STYLE-SPECIFIC COLORS ===
    let textMat = SCNMaterial()
    if isKeywordLabel {
        // Keyword labels: cyan/teal color scheme
        textMat.diffuse.contents = platformColor(0.2, 0.9, 1.0) // Bright cyan
        textMat.emission.contents = platformColor(0.0, 0.7, 0.9)
        textMat.emission.intensity = 0.8
    } else if isSubCluster {
        // Sub-cluster: slightly muted, matches document color
        textMat.diffuse.contents = backgroundStyle.labelTextColor.withAlphaComponent(0.85)
        textMat.emission.contents = accentColor
        textMat.emission.intensity = backgroundStyle.isDark ? 0.4 : 0.2
    } else {
        // Document cluster: full prominence
        textMat.diffuse.contents = backgroundStyle.labelTextColor
        textMat.emission.contents = accentColor
        textMat.emission.intensity = backgroundStyle.isDark ? 0.6 : 0.3
    }
    textMat.lightingModel = .constant
    textMat.isDoubleSided = true
    textMat.writesToDepthBuffer = false
    textMat.readsFromDepthBuffer = false
    textGeo.materials = [textMat]

    let textNode = SCNNode(geometry: textGeo)

    // Center the text pivot point
    let (minBound, maxBound) = textGeo.boundingBox
    let textWidth = maxBound.x - minBound.x
    let textHeight = maxBound.y - minBound.y
    textNode.pivot = SCNMatrix4MakeTranslation(
        minBound.x + textWidth / 2,
        minBound.y + textHeight / 2,
        0
    )

    // === BACKGROUND PILL (style varies by type) ===
    let paddingH: CGFloat = isDocumentCluster ? 0.08 : 0.05
    let paddingV: CGFloat = isDocumentCluster ? 0.04 : 0.03
    let bgWidth = CGFloat(textWidth) + paddingH * 2
    let bgHeight = CGFloat(textHeight) + paddingV * 2
    let bgPlane = SCNPlane(width: bgWidth, height: bgHeight)
    bgPlane.cornerRadius = min(bgHeight / 2, 0.06)

    let bgMat = SCNMaterial()
    if isKeywordLabel {
        // Keyword: dark teal background
        bgMat.diffuse.contents = platformColor(0.0, 0.15, 0.2, alpha: 0.85)
    } else if isSubCluster {
        // Sub-cluster: slightly transparent version of main background
        bgMat.diffuse.contents = backgroundStyle.labelBackgroundColor.withAlphaComponent(0.6)
    } else {
        bgMat.diffuse.contents = backgroundStyle.labelBackgroundColor
    }
    bgMat.lightingModel = .constant
    bgMat.writesToDepthBuffer = false
    bgMat.readsFromDepthBuffer = false
    bgPlane.materials = [bgMat]

    let bgNode = SCNNode(geometry: bgPlane)
    bgNode.renderingOrder = 100 + priority
    bgNode.position = SCNVector3(0, 0, -0.005)

    // === ASSEMBLE BASE ===
    container.addChildNode(bgNode)
    container.addChildNode(textNode)

    // === ACCENT INDICATOR (only for document clusters) ===
    if isDocumentCluster {
        let indicatorRadius: CGFloat = 0.022
        let indicator = SCNSphere(radius: indicatorRadius)
        let indicatorMat = SCNMaterial()
        indicatorMat.diffuse.contents = accentColor
        indicatorMat.emission.contents = accentColor
        indicatorMat.emission.intensity = 0.6
        indicatorMat.lightingModel = .constant
        indicator.materials = [indicatorMat]

        let indicatorNode = SCNNode(geometry: indicator)
        indicatorNode.position = SCNVector3(
            Float(-bgWidth / 2) - Float(indicatorRadius) - 0.012,
            0,
            0
        )
        container.addChildNode(indicatorNode)
    }

    // Billboard constraint - always face camera
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = [.X, .Y]
    container.constraints = [billboard]

    return container
}

private func addLighting(into root: SCNNode, depthCue: Bool) {
    // Brighter, more even lighting for better visibility
    let keyLight = SCNLight()
    keyLight.type = .omni
    keyLight.intensity = depthCue ? 1400 : 1100
    keyLight.castsShadow = false // Shadows can obscure points
    keyLight.attenuationStartDistance = 2.0
    keyLight.attenuationEndDistance = 15
    let keyNode = SCNNode()
    keyNode.light = keyLight
    keyNode.position = SCNVector3(2.5, 2.5, 3.0)
    root.addChildNode(keyNode)

    let fillLight = SCNLight()
    fillLight.type = .omni
    fillLight.intensity = depthCue ? 700 : 600
    fillLight.attenuationStartDistance = 2.0
    fillLight.attenuationEndDistance = 15
    let fillNode = SCNNode()
    fillNode.light = fillLight
    fillNode.position = SCNVector3(-2.5, -1.5, -3.0)
    root.addChildNode(fillNode)

    // Stronger ambient for base visibility
    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 350
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    root.addChildNode(ambientNode)
}

private func applyAutoRotate(_ isEnabled: Bool, to node: SCNNode) {
    // Always remove any existing animation first
    node.removeAnimation(forKey: "autoRotate")

    // Only add rotation if explicitly enabled
    guard isEnabled else { return }

    let animation = CABasicAnimation(keyPath: "rotation")
    animation.fromValue = SCNVector4(0, 1, 0, 0)
    animation.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
    animation.duration = 30 // Slower rotation
    animation.repeatCount = .greatestFiniteMagnitude
    node.addAnimation(animation, forKey: "autoRotate")
}

private func applyBackground(style: EmbeddingSceneBackgroundStyle, to scene: SCNScene) {
    if let image = gradientImage(for: style) {
        scene.background.contents = image
        scene.lightingEnvironment.contents = image
    } else {
        scene.background.contents = style.gradientSpec.colors.last
    }
}

private func gradientImage(for style: EmbeddingSceneBackgroundStyle) -> PlatformImage? {
    #if canImport(UIKit)
    let size = CGSize(width: 1024, height: 1024)
    let layer = CAGradientLayer()
    layer.frame = CGRect(origin: .zero, size: size)
    layer.colors = style.gradientSpec.colors.map { $0.cgColor }
    layer.startPoint = style.gradientSpec.startPoint
    layer.endPoint = style.gradientSpec.endPoint

    UIGraphicsBeginImageContextWithOptions(size, true, 0)
    guard let ctx = UIGraphicsGetCurrentContext() else {
        UIGraphicsEndImageContext()
        return nil
    }
    layer.render(in: ctx)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
    #else
    let size = CGSize(width: 1024, height: 1024)
    let layer = CAGradientLayer()
    layer.frame = CGRect(origin: .zero, size: size)
    layer.colors = style.gradientSpec.colors.map { $0.cgColor }
    layer.startPoint = style.gradientSpec.startPoint
    layer.endPoint = style.gradientSpec.endPoint

    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return nil
    }
    layer.render(in: ctx)
    image.unlockFocus()
    return image
    #endif
}

private enum AxisDirection { case x, y, z }

#if canImport(UIKit)
private func axisNode(length: CGFloat, color: UIColor, axis: AxisDirection) -> SCNNode {
    // CHUNKY visible axis rods - 0.15 radius
    let cyl = SCNCylinder(radius: 0.15, height: length)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.emission.contents = color
    mat.emission.intensity = 1.0
    mat.lightingModel = .constant
    cyl.materials = [mat]
    let node = SCNNode(geometry: cyl)
    switch axis {
    case .x:
        node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.position = SCNVector3(0, 0, 0)
    case .y:
        node.position = SCNVector3(0, 0, 0)
    case .z:
        node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.position = SCNVector3(0, 0, 0)
    }
    return node
}
#else
private func axisNode(length: CGFloat, color: NSColor, axis: AxisDirection) -> SCNNode {
    // CHUNKY visible axis rods - 0.15 radius
    let cyl = SCNCylinder(radius: 0.15, height: length)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.emission.contents = color
    mat.emission.intensity = 1.0
    mat.lightingModel = .constant
    cyl.materials = [mat]
    let node = SCNNode(geometry: cyl)
    switch axis {
    case .x:
        node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.position = SCNVector3(0, 0, 0)
    case .y:
        node.position = SCNVector3(0, 0, 0)
    case .z:
        node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.position = SCNVector3(0, 0, 0)
    }
    return node
}
#endif

// MARK: - Coordinate Normalization (Apple Embedding Atlas style)

/// Scales coordinates to fit viewing space while preserving natural clustering
/// Unlike forced sphere distribution, this maintains actual embedding relationships
private func normalizeToViewingCube(_ coords: [SIMD3<Float>], jitterAmount: Float = 0.02) -> [SCNVector3] {
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

    // Calculate center and uniform scale
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2
    let centerZ = (minZ + maxZ) / 2

    let spanX = max(maxX - minX, 0.0001)
    let spanY = max(maxY - minY, 0.0001)
    let spanZ = max(maxZ - minZ, 0.0001)
    let maxSpan = max(spanX, max(spanY, spanZ))

    // Target viewing size
    let targetSize: Float = 3.0
    let scale = targetSize / maxSpan

    var result: [SCNVector3] = []
    result.reserveCapacity(coords.count)

    for (index, c) in coords.enumerated() {
        // Center and scale uniformly to preserve shape
        var x = (c.x - centerX) * scale
        var y = (c.y - centerY) * scale
        var z = (c.z - centerZ) * scale

        // Small jitter to prevent exact overlaps
        let seed = UInt32(index)
        x += (Float((seed &* 1_103_515_245 &+ 12345) % 10000) / 20000.0 - 0.025) * jitterAmount
        y += (Float((seed &* 1_664_525 &+ 1_013_904_223) % 10000) / 20000.0 - 0.025) * jitterAmount
        z += (Float((seed &* 22_695_477 &+ 1) % 10000) / 20000.0 - 0.025) * jitterAmount

        result.append(SCNVector3(x, y, z))
    }

    return result
}

// MARK: - Embedding Visualization Color Palette

enum EmbeddingColorPalette {
    static let fallback: PlatformColor = {
        #if canImport(UIKit)
        return UIColor.systemGray
        #else
        return NSColor.systemGray
        #endif
    }()

    /// Hand-picked distinct colors that are visually distinguishable in 3D space
    static func makePalette(count: Int) -> [PlatformColor] {
        // Curated palette of highly distinct colors
        let curated: [(CGFloat, CGFloat, CGFloat)] = [
            (0.95, 0.26, 0.21), // Red
            (0.13, 0.59, 0.95), // Blue
            (0.30, 0.69, 0.31), // Green
            (1.00, 0.60, 0.00), // Orange
            (0.61, 0.15, 0.69), // Purple
            (0.00, 0.74, 0.83), // Cyan
            (1.00, 0.92, 0.23), // Yellow
            (0.91, 0.12, 0.39), // Pink
            (0.47, 0.33, 0.28), // Brown
            (0.00, 0.59, 0.53), // Teal
            (0.98, 0.50, 0.45), // Coral
            (0.40, 0.73, 0.42), // Light Green
            (0.25, 0.32, 0.71), // Indigo
            (1.00, 0.76, 0.03), // Amber
            (0.47, 0.56, 0.61), // Blue Grey
            (0.85, 0.11, 0.38), // Deep Pink
        ]

        var colors: [PlatformColor] = []
        colors.reserveCapacity(max(count, curated.count))

        for i in 0 ..< max(count, curated.count) {
            let (r, g, b) = curated[i % curated.count]
            // Add slight variation for repeated colors
            let variation = CGFloat(i / curated.count) * 0.15
            let adjustedR = min(1.0, r + variation)
            let adjustedG = min(1.0, g + variation * 0.5)
            let adjustedB = min(1.0, b - variation * 0.3)

            #if canImport(UIKit)
            colors.append(UIColor(red: adjustedR, green: adjustedG, blue: adjustedB, alpha: 1.0))
            #else
            colors.append(NSColor(calibratedRed: adjustedR, green: adjustedG, blue: adjustedB, alpha: 1.0))
            #endif
        }
        return colors
    }
}

#else

// Fallback when SceneKit is not available on this platform (e.g., visionOS without SceneKit).
// Provides a graceful placeholder so VisualizationsView compiles across all supported platforms.
struct EmbeddingSpaceRenderer: View {
    let projectionMethod: EmbeddingSpaceView.ProjectionMethod
    let chunkCount: Int
    let documentCount: Int
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(DSColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("3D embedding visualization requires SceneKit")
                        .font(.subheadline)
                    Text("This platform does not support SceneKit. A compatible renderer (RealityKit) can be added.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("Tracking \(chunkCount) chunks across \(documentCount) documents")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    Text(projectionHelper)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Tip: On compatible devices, use Focus mode to stretch the scene, or hide the HUD for a clean canvas.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding()
            }
            .frame(height: 360)

            EmbeddingLegendCard()
        }
    }

    private var projectionHelper: String {
        switch projectionMethod {
        case .pca:
            return "PCA offers a fast overview once SceneKit is available."
        case .tsne:
            return "t-SNE will highlight tiny topic bubbles in the future renderer."
        case .umap:
            return "UMAP balances local and global structure for mixed document sets."
        }
    }
}

#Preview {
    EmbeddingSpaceRenderer(
        projectionMethod: .pca,
        chunkCount: 150,
        documentCount: 5
    )
    .environmentObject(RAGService())
    .environmentObject(ContainerService())
}

#endif

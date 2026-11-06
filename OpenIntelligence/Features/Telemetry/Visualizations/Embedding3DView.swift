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
import Charts
import Spatial

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

func platformColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> PlatformColor {
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

    @State var isLoading = true
    @State var points: [SCNVector3] = []
    @State var pointColorsUI: [PlatformColor] = []
    @State var legendItems: [VizLegendItem] = []
    @State var errorText: String? = nil

    // Deterministic per-container controls and state
    @State var sampleLimit: Int = 2000 // Higher default for full visibility
    @State var allDocIdsForPoints: [UUID] = [] // aligned with points/colors
    @State var totalPoints: Int = 0
    @State var selectedDocFilters: Set<UUID> = [] // empty = select all by default
    @State var loadTask: Task<Void, Never>? = nil
    @State var pointScale: Double = 1.0 // Slightly smaller for more points
    @State var autoRotate = false // Off by default — let user explore
    @State var showAxes = true // On by default — show spatial reference
    @State var depthCue = false // Off for cleaner look
    @State var backgroundStyle: EmbeddingSceneBackgroundStyle = .midnight // Dark for better contrast
    @State var sceneReloadToken = UUID()
    @State var insights: [EmbeddingInsight] = []
    @State var focusMode = false
    @State var showHUD = true
    @State var showClusterLabels = true // Show floating document cluster labels
    @State var annotationLabels: [PointAnnotationLabel] = []

    // Search & highlight functionality
    @State var searchQuery: String = ""
    @State var isSearching: Bool = false
    @State var highlightedPointIndices: Set<Int> = []

    // Tap-to-inspect: tapped point info
    @State var tappedPointIndex: Int? = nil
    @State var showPointDetail: Bool = false

    // Chunk data for tap-to-inspect (loaded once, indexed by point order)
    @State var chunkTexts: [String] = []
    @State var chunkDocNames: [String] = []

    // Dynamic axis labels derived from analyzing content at axis extremes
    @State var dynamicAxisLabels: Embedding3DSceneView.AxisLabels = .placeholder

    // Onboarding / help
    @State var showHelpTip: Bool = false
    @AppStorage("embedding3d_hasSeenOnboarding") var hasSeenOnboarding: Bool = false

    // FTS5-derived corpus intelligence for richer labels
    @State var fts5TopTerms: [String] = []  // Top terms from SQLite FTS5 index
    @State var fts5KeyPhrases: [(phrase: String, count: Int)] = []  // Multi-word phrases

    // How many passages the map draws. The most is what `allChunksForActiveContainer` reads, an even sample of up to
    // `RAGService.visualizationPassageLimit` (6,000) since 5.7; through 5.6 the choices were 5,000 and "All" (50,000).
    // Higher counts auto-scale point size smaller.
    let sampleOptions = [500, 2000, RAGService.visualizationPassageLimit]
    static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        VStack(spacing: DSSpacing.md) {
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
            .foregroundStyle(DSColors.readable(.red))
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
        VStack(spacing: DSSpacing.lg) {
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
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack {
                Image(systemName: "chart.dots.scatter")
                    .foregroundStyle(DSColors.accent)
                Text("Embedding Space Analytics")
                    .font(.headline)
                Spacer()
                Text("🤓 Nerd Mode")
                    .font(.caption2)
                    .foregroundStyle(DSColors.accent)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(DSColors.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
            }

            // Core metrics grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                EmbeddingStatMini(
                    label: "Points",
                    value: "\(totalPoints)",
                    icon: "circle.fill",
                    color: DSColors.accent
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
                    color: DSColors.accent
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
                    color: DSColors.accent
                )
                EmbeddingStatMini(
                    label: "Sample Cap",
                    value: "\(sampleLimit)",
                    icon: "slider.horizontal.3",
                    color: .secondary
                )
            }

            Divider().opacity(0.3)

            // Distribution insights
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Distribution Analysis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if !legendItems.isEmpty {
                    let sortedItems = legendItems.sorted { $0.count > $1.count }
                    let maxCount = sortedItems.first?.count ?? 1
                    let minCount = sortedItems.last?.count ?? 0
                    let avgCount = totalPoints > 0 ? totalPoints / max(legendItems.count, 1) : 0
                    let variance = calculateVariance(legendItems.map { $0.count })

                    HStack(spacing: DSSpacing.lg) {
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("Max pts/doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(maxCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("Min pts/doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(minCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("Avg pts/doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(avgCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("Std Dev")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f", sqrt(variance)))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }

                    // Balance indicator
                    let balanceScore = calculateBalanceScore(legendItems.map { $0.count })
                    HStack(spacing: DSSpacing.sm) {
                        Text("Balance Score:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                    .fill(Color.secondary.opacity(0.2))
                                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                    .fill(balanceColor(balanceScore))
                                    .frame(width: geo.size.width * CGFloat(balanceScore))
                            }
                        }
                        .frame(height: 8)
                        Text(String(format: "%.0f%%", balanceScore * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(DSColors.readable(balanceColor(balanceScore)))
                    }
                    .frame(height: 20)

                    Text(balanceDescription(balanceScore))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.3)

            // Projection details
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Projection Details")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: DSSpacing.lg) {
                    ProjectionDetailRow(label: "Algorithm", value: projectionMethodDescription)
                    Spacer()
                }

                Text(projectionExplainer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.3)

            // Spatial density analysis
            spatialDensitySection

            Divider().opacity(0.3)

            // Raw data inspector
            rawDataInspector
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .padding(.horizontal, DSSpacing.lg)
    }

    var embeddingDimension: Int {
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
        VStack(spacing: DSSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "cube.transparent")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("3D embedding visualization requires SceneKit")
                        .font(.subheadline)
                    Text("This platform does not support SceneKit. A compatible renderer (RealityKit) can be added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.lg)
                    Text("Tracking \(chunkCount) chunks across \(documentCount) documents")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, DSSpacing.xs)
                    Text(projectionHelper)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Tip: On compatible devices, use Focus mode to stretch the scene, or hide the HUD for a clean canvas.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, DSSpacing.xxs)
                }
                .padding(DSSpacing.lg)
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

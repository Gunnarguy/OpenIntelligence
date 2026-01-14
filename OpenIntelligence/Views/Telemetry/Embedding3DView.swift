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
    case parchment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .midnight: return "Midnight"
        case .parchment: return "Parchment"
        }
    }

    var iconName: String {
        switch self {
        case .aurora: return "sun.max"
        case .midnight: return "moon.stars"
        case .parchment: return "rectangle.dashed"
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
        case .parchment:
            return platformColor(0.92, 0.90, 0.84)
        }
    }

    struct GradientSpec {
        let colors: [PlatformColor]
        let startPoint: CGPoint
        let endPoint: CGPoint
    }
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
    struct VizLegendItem: Identifiable {
        let docId: UUID
        let name: String
        let color: Color
        let count: Int
        var id: UUID { docId }
    }
    @State private var legendItems: [VizLegendItem] = []
    @State private var errorText: String? = nil

    // Deterministic per-container controls and state
    @State private var sampleLimit: Int = 500
    @State private var allDocIdsForPoints: [UUID] = [] // aligned with points/colors
    @State private var totalPoints: Int = 0
    @State private var selectedDocFilters: Set<UUID> = [] // empty = select all by default
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var pointScale: Double = 1.2 // Slightly larger points
    @State private var autoRotate = false // Off by default — let user explore
    @State private var showAxes = true // On by default — show spatial reference
    @State private var depthCue = false // Off for cleaner look
    @State private var backgroundStyle: EmbeddingSceneBackgroundStyle = .midnight // Dark for better contrast
    @State private var sceneReloadToken = UUID()
    @State private var insights: [EmbeddingInsight] = []
    @State private var focusMode = false
    @State private var showHUD = true
    @State private var annotationLabels: [PointAnnotationLabel] = []

    // Default: 250/500/1K (lower defaults for cleaner, less cluttered view)
    private let sampleOptions = [250, 500, 1000]
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
            insightHighlights
            legendSection
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
                annotations: buildSceneAnnotations()
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(alignment: .topLeading) {
            if showHUD { sceneHUD }
        }
        .frame(height: heroHeight)
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 12)
        .padding(.horizontal, heroHorizontalPadding)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: focusMode)
        .animation(.easeInOut(duration: 0.2), value: showHUD)
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
                } label: {
                    Text(option >= 1000 ? "\(option/1000)K" : "\(option)")
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
                explanation: "The renderer downsamples embeddings per document to stay interactive. Increase the cap to inspect more of the space; auto-rotate helps validate structure."
            )
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
        Embedding3DSceneView.SceneOptions(
            pointScale: CGFloat(pointScale),
            autoRotate: autoRotate,
            showAxes: showAxes,
            depthCue: depthCue,
            backgroundStyle: backgroundStyle
        )
    }

    private func buildSceneAnnotations() -> [Embedding3DSceneView.AnnotationData] {
        guard showHUD, !annotationLabels.isEmpty, !points.isEmpty else { return [] }

        var result: [Embedding3DSceneView.AnnotationData] = []
        for label in annotationLabels {
            guard label.pointIndex < points.count else { continue }
            let position = points[label.pointIndex]
            let uiColor = pointColorsUI[label.pointIndex]

            // Determine detail level based on spatial clustering
            // In a real implementation, this would check camera distance
            // For now, use score as a proxy
            let detailLevel: Int
            if label.score > 0.8 {
                detailLevel = 2 // Full detail
            } else if label.score > 0.5 {
                detailLevel = 1 // Title only
            } else {
                detailLevel = 0 // Minimal dot
            }

            result.append(Embedding3DSceneView.AnnotationData(
                position: position,
                title: label.title,
                keywords: label.keywords,
                color: uiColor,
                detailLevel: detailLevel
            ))
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
        let items: [EmbeddingSpaceRenderer.VizLegendItem]
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
        let item: EmbeddingSpaceRenderer.VizLegendItem
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

        let xs = coords.prefix(count).map { $0.x }
        let ys = coords.prefix(count).map { $0.y }
        let zs = coords.prefix(count).map { $0.z }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
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
            let annotationLimit = await MainActor.run { focusMode ? 5 : 3 }

            // Snapshot documents to resolve names and filter by active container
            let docsSnapshot = await MainActor.run { ragService.documents }
            let activeId = containerService.activeContainerId
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
            let rngSeed = UInt64(abs(Int64(activeId.uuidString.hashValue)))
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
            sampleLimit = 500 // Lower default for much cleaner initial view
        }
    }
}

// MARK: - SceneKit SwiftUI Wrapper

struct Embedding3DSceneView: View {
    struct SceneOptions {
        let pointScale: CGFloat
        let autoRotate: Bool
        let showAxes: Bool
        let depthCue: Bool
        let backgroundStyle: EmbeddingSceneBackgroundStyle
    }

    struct AnnotationData: Identifiable {
        let id = UUID()
        let position: SCNVector3
        let title: String
        let keywords: [String]
        let color: PlatformColor
        let detailLevel: Int // 0=minimal, 1=normal, 2=detailed
    }

    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: SceneOptions
    let reloadToken: UUID
    let annotations: [AnnotationData]

    var body: some View {
        SceneViewContainer(points: points, colors: colors, options: options, reloadToken: reloadToken, annotations: annotations)
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

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.delegate = context.coordinator
        configure(view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        configure(uiView)
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
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let scene = renderer.scene else { return }
            updateLabelLOD(scene: scene, pointOfView: renderer.pointOfView)
        }

        private func updateLabelLOD(scene: SCNScene, pointOfView: SCNNode?) {
            guard let camera = pointOfView else { return }
            let cameraPos = camera.position

            scene.rootNode.enumerateChildNodes { node, _ in
                guard node.name == "contentRoot" else { return }

                node.enumerateChildNodes { labelNode, _ in
                    guard labelNode.geometry is SCNText || labelNode.childNodes.contains(where: { $0.geometry is SCNText }) else { return }

                    let distance = simd_distance(simd_float3(cameraPos), simd_float3(labelNode.position))

                    // Dynamic LOD based on distance
                    if distance < 2.0 {
                        // Close: show full detail
                        labelNode.opacity = 0.95
                        labelNode.scale = SCNVector3(0.4, 0.4, 0.4)
                    } else if distance < 4.0 {
                        // Medium: normal detail
                        labelNode.opacity = 0.8
                        labelNode.scale = SCNVector3(0.35, 0.35, 0.35)
                    } else if distance < 6.0 {
                        // Far: minimal
                        labelNode.opacity = 0.5
                        labelNode.scale = SCNVector3(0.3, 0.3, 0.3)
                    } else {
                        // Very far: hide
                        labelNode.opacity = 0.2
                        labelNode.scale = SCNVector3(0.25, 0.25, 0.25)
                    }
                }
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

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.delegate = context.coordinator
        configure(view)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        configure(nsView)
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
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let scene = renderer.scene else { return }
            updateLabelLOD(scene: scene, pointOfView: renderer.pointOfView)
        }

        private func updateLabelLOD(scene: SCNScene, pointOfView: SCNNode?) {
            guard let camera = pointOfView else { return }
            let cameraPos = camera.position

            scene.rootNode.enumerateChildNodes { node, _ in
                guard node.name == "labelLayer" else { return }

                node.enumerateChildNodes { labelNode, _ in
                    let distance = simd_distance(simd_float3(cameraPos), simd_float3(labelNode.position))

                    // Scale labels based on distance - keep them readable at ALL distances
                    if distance<3.0 { 
                        labelNode.opacity = 0.95
                        labelNode.scale = SCNVector3(0.12, 0.12, 0.12)
                    } else if distance < 6.0 {
                        labelNode.opacity = 0.9
                        labelNode.scale = SCNVector3(0.15, 0.15, 0.15)
                    } else if distance < 10.0 {
                        labelNode.opacity = 0.8
                        labelNode.scale = SCNVector3(0.18, 0.18, 0.18)
                    } else {
                        labelNode.opacity = 0.7
                        labelNode.scale = SCNVector3(0.22, 0.22, 0.22)
                    }
                }
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
        contentRoot.addChildNode(makeIntuiveAxesNode())
    }

    addPointNodes(points, colors, scale: options.pointScale, depthCue: options.depthCue, into: contentRoot)
    addClusterLabels(annotations, into: contentRoot)
    addLighting(into: scene.rootNode, depthCue: options.depthCue)
    applyBackground(style: options.backgroundStyle, to: scene)
    applyAutoRotate(options.autoRotate, to: contentRoot)

    if options.depthCue {
        scene.fogStartDistance = 4.0
        scene.fogEndDistance = 9.0
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
    let gridSize: Float = 6.0
    let gridLines = 12
    let spacing = gridSize / Float(gridLines)

    for i in 0 ... gridLines {
        let offset = -gridSize / 2 + Float(i) * spacing

        // X-axis lines
        let xLine = SCNCylinder(radius: 0.004, height: CGFloat(gridSize))
        let xMat = SCNMaterial()
        #if canImport(UIKit)
            xMat.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
        #else
            xMat.diffuse.contents = NSColor.white.withAlphaComponent(0.08)
        #endif
        xLine.materials = [xMat]
        let xNode = SCNNode(geometry: xLine)
        xNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        xNode.position = SCNVector3(0, -3.0, offset) // At bottom of Y axis
        container.addChildNode(xNode)

        // Z-axis lines
        let zLine = SCNCylinder(radius: 0.004, height: CGFloat(gridSize))
        zLine.materials = [xMat]
        let zNode = SCNNode(geometry: zLine)
        zNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        zNode.position = SCNVector3(offset, -3.0, 0) // At bottom of Y axis
        container.addChildNode(zNode)
    }

    return container
}

// MARK: - Clean Arrow Axes (visible, no text clutter)

private func makeIntuiveAxesNode() -> SCNNode { 
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

    return node
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
        camera.focusDistance = 6.0
        camera.fStop = 8
    }
    node.camera = camera
    // Close enough to see data clearly, far enough to see axes
    node.position = SCNVector3(4.0, 3.0, 7.0)
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

    for index in 0..<count {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 12 // Fewer segments for better performance

        let material = SCNMaterial()
        material.diffuse.contents = colors[index]

        // Always add glow for visibility - constant lighting for consistent brightness
        material.lightingModel = .constant
        material.emission.contents = colors[index]
        material.emission.intensity = 0.7 // Strong glow for visibility

        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.position = points[index]
        root.addChildNode(node)
    }
}

// MARK: - Cluster Labels (Redesigned)

private func addClusterLabels(_ annotations: [Embedding3DSceneView.AnnotationData], into root: SCNNode) { 
    guard !annotations.isEmpty else { return }

    // Create a dedicated label layer node that renders on top of everything
    let labelLayer = SCNNode()
    labelLayer.name = "labelLayer"
    // Render labels last (on top) by setting rendering order
    labelLayer.renderingOrder = 100

    for annotation in annotations {
        let labelNode = makeClusterBadge(
            title: annotation.title,
            count: annotation.detailLevel,
            color: annotation.color
        )
        // Position label AT the cluster centroid (annotation.position is already scaled correctly)
        // Add Y offset to float above the point cluster
        labelNode.position = SCNVector3(
            annotation.position.x,
            annotation.position.y + 0.5, // Float above the cluster
            annotation.position.z
        )
        labelLayer.addChildNode(labelNode)
    }

    root.addChildNode(labelLayer)
}

/// Creates a floating text label for cluster - BIG, BOLD, ALWAYS VISIBLE
private func makeClusterBadge(title: String, count: Int, color: PlatformColor) -> SCNNode { 
    let container = SCNNode()
    container.renderingOrder = 101 // Render on top of dots

    // Truncate to reasonable length
    let displayText = title.prefix(16) + (title.count > 16 ? "…" : "")
    let textGeo = SCNText(string: String(displayText), extrusionDepth: 0.02)

    // GIANT font - easily readable without zooming. Base 1.2, up to 1.8 for big clusters
    let fontSize: CGFloat = min(1.8, max(1.2, 1.0 + CGFloat(min(count, 50)) * 0.015))
    #if canImport(UIKit)
        textGeo.font = UIFont.systemFont(ofSize: fontSize, weight: .black)
    #else
        textGeo.font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    #endif
    textGeo.flatness = 0.01 // Smoother curves
    textGeo.chamferRadius = 0.01

    // Create contrasting outline/glow effect
    let textMat = SCNMaterial()
    textMat.diffuse.contents = PlatformColor.white // White text for contrast
    textMat.emission.contents = color // Glow in topic color
    textMat.emission.intensity = 0.8
    textMat.lightingModel = .constant // Always fully lit
    textMat.isDoubleSided = true
    textMat.writesToDepthBuffer = false // Don't occlude other labels
    textMat.readsFromDepthBuffer = false // Render on top of everything
    textGeo.materials = [textMat]

    let textNode = SCNNode(geometry: textGeo)

    // Center the text pivot
    let (minBound, maxBound) = textGeo.boundingBox
    let textWidth = maxBound.x - minBound.x
    let textHeight = maxBound.y - minBound.y
    textNode.pivot = SCNMatrix4MakeTranslation(
        minBound.x + textWidth / 2,
        minBound.y + textHeight / 2,
        0
    )

    // Add a dark background pill for contrast
    let bgWidth = CGFloat(textWidth) + 0.15
    let bgHeight = CGFloat(textHeight) + 0.08
    let bgPlane = SCNPlane(width: bgWidth, height: bgHeight)
    bgPlane.cornerRadius = bgHeight / 2
    let bgMat = SCNMaterial()
    bgMat.diffuse.contents = PlatformColor(Color.black.opacity(0.7))
    bgMat.lightingModel = .constant
    bgMat.writesToDepthBuffer = false
    bgMat.readsFromDepthBuffer = false
    bgPlane.materials = [bgMat]

    let bgNode = SCNNode(geometry: bgPlane)
    bgNode.renderingOrder = 100 // Behind text but on top of dots
    bgNode.position = SCNVector3(0, 0, -0.01) // Slightly behind text

    container.addChildNode(bgNode)
    container.addChildNode(textNode)

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

#endif

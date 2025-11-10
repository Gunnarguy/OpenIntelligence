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

// MARK: - Public Renderer (used from VisualizationsView.EmbeddingSpaceView)

struct EmbeddingSpaceRenderer: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    
    let projectionMethod: EmbeddingSpaceView.ProjectionMethod
    
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
    @State private var sampleLimit: Int = 2000
    @State private var allDocIdsForPoints: [UUID] = [] // aligned with points/colors
    @State private var totalPoints: Int = 0
    @State private var selectedDocFilters: Set<UUID> = [] // empty = select all by default
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var pointScale: Double = 1.0
    @State private var autoRotate = true
    @State private var showAxes = false
    @State private var depthCue = true
    @State private var backgroundStyle: EmbeddingSceneBackgroundStyle = .aurora
    @State private var sceneReloadToken = UUID()
    
    // Default: 1K/2K/5K
    private let sampleOptions = [1000, 2000, 5000]
    
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
            tuningCard
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
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(backgroundGradient(for: backgroundStyle))

            Embedding3DSceneView(
                points: filteredPoints,
                colors: filteredColors,
                options: sceneOptions,
                reloadToken: sceneReloadToken
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            controlOverlay
        }
        .frame(height: 440)
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 12)
        .padding(.horizontal)
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

    private var controlOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 10) {
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
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(title)
                }
                .font(.caption2)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isActive ? Color.accentColor : Color.black.opacity(0.12))
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
    
    // MARK: - Data + Projection
    
    private func loadAndProject() async {
        // Cancel any ongoing load
        loadTask?.cancel()
        loadTask = Task {
            await MainActor.run {
                isLoading = true
                errorText = nil
            }
            
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
            sampledEmbeddings.reserveCapacity(min(sampleLimit, filtered.count))
            sampledDocIds.reserveCapacity(min(sampleLimit, filtered.count))
            
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
                        sampledEmbeddings.append(arr[idx].embedding)
                        sampledDocIds.append(did)
                    }
                } else {
                    for c in arr {
                        sampledEmbeddings.append(c.embedding)
                        sampledDocIds.append(did)
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
                newEmb.reserveCapacity(order.count)
                newIds.reserveCapacity(order.count)
                for idx in order {
                    newEmb.append(sampledEmbeddings[idx])
                    newIds.append(sampledDocIds[idx])
                }
                sampledEmbeddings = newEmb
                sampledDocIds = newIds
            }
            
            // Validate dims
            sampledEmbeddings = sampledEmbeddings.filter { !$0.isEmpty }
            if Task.isCancelled { return }
            guard !sampledEmbeddings.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                }
                return
            }
            
            // Projection & caching
            let methodKind: ProjectionMethodKind = (projectionMethod == .pca) ? .pca : .rp
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
            let palette = ColorPalette.makePalette(count: docIds.count)
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
                let uiColor = colorByDoc[did] ?? ColorPalette.fallback
                let swiftUIColor = Color(uiColor)
                let name = nameById[did] ?? "Unknown"
                let cnt = counts[did] ?? 0
                legend.append(VizLegendItem(docId: did, name: name, color: swiftUIColor, count: cnt))
            }
            
            // Build SceneKit vectors and color list aligned
            let scnPoints: [SCNVector3] = coords3D.map { SCNVector3($0.x, $0.y, $0.z) }
            let uiColors: [PlatformColor] = sampledDocIds.map { colorByDoc[$0] ?? ColorPalette.fallback }
            
            await MainActor.run {
                self.points = scnPoints
                self.pointColorsUI = uiColors
                self.legendItems = legend
                self.allDocIdsForPoints = sampledDocIds
                self.totalPoints = scnPoints.count
                // Default: if no filters yet, treat as "all" selected by keeping set empty
                self.isLoading = false
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
            sampleLimit = 2000
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

    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: SceneOptions
    let reloadToken: UUID

    var body: some View {
        SceneViewContainer(points: points, colors: colors, options: options, reloadToken: reloadToken)
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

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: SCNView) {
        let _ = reloadToken
        view.scene = buildScene(points: points, colors: colors, options: options)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
    }
}
#else
struct SceneViewContainer: NSViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: Embedding3DSceneView.SceneOptions
    let reloadToken: UUID

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: SCNView) {
        let _ = reloadToken
        view.scene = buildScene(points: points, colors: colors, options: options)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
    }
}
#endif

// MARK: - Scene construction

private func buildScene(points: [SCNVector3], colors: [PlatformColor], options: Embedding3DSceneView.SceneOptions) -> SCNScene {
    let scene = SCNScene()
    scene.rootNode.addChildNode(makeCameraNode(depthCue: options.depthCue))

    let contentRoot = SCNNode()
    contentRoot.name = "contentRoot"
    scene.rootNode.addChildNode(contentRoot)

    if options.showAxes {
        contentRoot.addChildNode(makeAxesNode())
    }

    addPointNodes(points, colors, scale: options.pointScale, depthCue: options.depthCue, into: contentRoot)
    addLighting(into: scene.rootNode, depthCue: options.depthCue)
    applyBackground(style: options.backgroundStyle, to: scene)
    applyAutoRotate(options.autoRotate, to: contentRoot)

    if options.depthCue {
        scene.fogStartDistance = 3.5
        scene.fogEndDistance = 7.5
        scene.fogDensityExponent = 1.2
        #if canImport(UIKit)
        scene.fogColor = options.backgroundStyle.fogColor.withAlphaComponent(0.85)
        #else
        scene.fogColor = options.backgroundStyle.fogColor.withAlphaComponent(0.85)
        #endif
    } else {
        scene.fogStartDistance = 0
        scene.fogEndDistance = 0
    }

    return scene
}

private func makeCameraNode(depthCue: Bool) -> SCNNode {
    let node = SCNNode()
    let camera = SCNCamera()
    camera.zNear = 0.01
    camera.zFar = 80
    camera.wantsDepthOfField = depthCue
    if depthCue {
        camera.focusDistance = 3.2
        camera.fStop = 8
    }
    node.camera = camera
    node.position = SCNVector3(0, 0, 3.2)
    return node
}

private func makeAxesNode() -> SCNNode {
    let node = SCNNode()
#if canImport(UIKit)
    node.addChildNode(axisNode(length: 1.6, color: .systemRed, axis: .x))
    node.addChildNode(axisNode(length: 1.6, color: .systemGreen, axis: .y))
    node.addChildNode(axisNode(length: 1.6, color: .systemBlue, axis: .z))
#else
    node.addChildNode(axisNode(length: 1.6, color: .systemRed, axis: .x))
    node.addChildNode(axisNode(length: 1.6, color: .systemGreen, axis: .y))
    node.addChildNode(axisNode(length: 1.6, color: .systemBlue, axis: .z))
#endif
    node.opacity = 0.24
    node.addChildNode(axisLabelNode(text: "X", color: .systemRed, axis: .x))
    node.addChildNode(axisLabelNode(text: "Y", color: .systemGreen, axis: .y))
    node.addChildNode(axisLabelNode(text: "Z", color: .systemBlue, axis: .z))
    return node
}

private func axisLabelNode(text: String, color: PlatformColor, axis: AxisDirection) -> SCNNode {
    let label = SCNText(string: text, extrusionDepth: 0.01)
    #if canImport(UIKit)
    label.font = UIFont.systemFont(ofSize: 0.18, weight: .semibold)
    #else
    label.font = NSFont.systemFont(ofSize: 0.18, weight: .semibold)
    #endif
    label.flatness = 0.1
    label.firstMaterial?.diffuse.contents = color
    label.firstMaterial?.emission.contents = color

    let textNode = SCNNode(geometry: label)
    let (min, max) = label.boundingBox
    let width = max.x - min.x
    textNode.pivot = SCNMatrix4MakeTranslation(min.x + width / 2, min.y, 0)
    textNode.scale = SCNVector3(0.4, 0.4, 0.4)

    switch axis {
    case .x:
        textNode.position = SCNVector3(1.0, 0.0, 0.0)
    case .y:
        textNode.position = SCNVector3(0.0, 1.0, 0.0)
    case .z:
        textNode.position = SCNVector3(0.0, 0.0, 1.0)
    }

    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .all
    textNode.constraints = [billboard]
    return textNode
}

private func addPointNodes(_ points: [SCNVector3], _ colors: [PlatformColor], scale: CGFloat, depthCue: Bool, into root: SCNNode) {
    let count = min(points.count, colors.count)
    guard count > 0 else { return }

    let radius = max(0.01, 0.015 * scale)
    for index in 0..<count {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 12
        let material = SCNMaterial()
        material.diffuse.contents = colors[index]
        if depthCue {
            material.lightingModel = .physicallyBased
            material.roughness.contents = NSNumber(value: 0.35)
            material.metalness.contents = NSNumber(value: 0.05)
        } else {
            material.lightingModel = .blinn
            material.emission.contents = colors[index]
        }
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.position = points[index]
        root.addChildNode(node)
    }
}

private func addLighting(into root: SCNNode, depthCue: Bool) {
    let keyLight = SCNLight()
    keyLight.type = .omni
    keyLight.intensity = depthCue ? 1200 : 900
    keyLight.castsShadow = true
    keyLight.attenuationStartDistance = depthCue ? 1.6 : 3.0
    keyLight.attenuationEndDistance = depthCue ? 12 : 18
    let keyNode = SCNNode()
    keyNode.light = keyLight
    keyNode.position = SCNVector3(2.0, 1.8, 2.4)
    root.addChildNode(keyNode)

    let fillLight = SCNLight()
    fillLight.type = .omni
    fillLight.intensity = depthCue ? 520 : 450
    fillLight.attenuationStartDistance = depthCue ? 1.2 : 3.5
    fillLight.attenuationEndDistance = depthCue ? 10 : 18
    let fillNode = SCNNode()
    fillNode.light = fillLight
    fillNode.position = SCNVector3(-2.2, -1.4, -2.6)
    root.addChildNode(fillNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 220
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    root.addChildNode(ambientNode)
}

private func applyAutoRotate(_ isEnabled: Bool, to node: SCNNode) {
    if !isEnabled {
        node.removeAnimation(forKey: "autoRotate")
        return
    }
    let animation = CABasicAnimation(keyPath: "rotation")
    animation.fromValue = SCNVector4(0, 1, 0, 0)
    animation.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
    animation.duration = 26
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
    let cyl = SCNCylinder(radius: 0.0025, height: length)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    cyl.materials = [mat]
    let node = SCNNode(geometry: cyl)
    switch axis {
    case .x:
        node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.position = SCNVector3(length/2, 0, 0)
    case .y:
        node.position = SCNVector3(0, length/2, 0)
    case .z:
        node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.position = SCNVector3(0, 0, length/2)
    }
    return node
}
#else
private func axisNode(length: CGFloat, color: NSColor, axis: AxisDirection) -> SCNNode {
    let cyl = SCNCylinder(radius: 0.0025, height: length)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    cyl.materials = [mat]
    let node = SCNNode(geometry: cyl)
    switch axis {
    case .x:
        node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.position = SCNVector3(length/2, 0, 0)
    case .y:
        node.position = SCNVector3(0, length/2, 0)
    case .z:
        node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.position = SCNVector3(0, 0, length/2)
    }
    return node
}
#endif

// MARK: - Color Palette

enum ColorPalette {
    static let fallback: PlatformColor = {
        #if canImport(UIKit)
        return UIColor.systemGray
        #else
        return NSColor.systemGray
        #endif
    }()
    
    static func makePalette(count: Int) -> [PlatformColor] {
        let base = 12
        let n = max(count, base)
        var colors: [PlatformColor] = []
        colors.reserveCapacity(n)
        for i in 0..<n {
            let hue = CGFloat(i) / CGFloat(n)
            #if canImport(UIKit)
            colors.append(UIColor(hue: hue, saturation: 0.75, brightness: 0.95, alpha: 1.0))
            #else
            colors.append(NSColor(calibratedHue: hue, saturation: 0.75, brightness: 0.95, alpha: 1.0))
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
                }
                .padding()
            }
            .frame(height: 340)
        }
    }
}

#endif

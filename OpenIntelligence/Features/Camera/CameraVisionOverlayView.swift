//
//  CameraVisionOverlayView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  Live camera view with Apple Vision framework overlays for real-time
//  document, text, and table detection with one-tap RAG ingestion.
//

#if os(iOS)
import AVFoundation
import SwiftUI
import Vision

// MARK: - Camera Vision Overlay View

/// Main camera view with live Vision analysis and AR-style overlays
struct CameraVisionOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService

    @StateObject private var cameraManager = CameraManager()
    @State private var detectedRegions: [DetectedRegion] = []
    @State private var liveOCRText: String = ""
    @State private var isCapturing = false
    @State private var captureResult: CaptureResult?
    @State private var showCaptureConfirmation = false
    @State private var selectedRegionType: RegionType = .all
    @State private var flashEnabled = false
    @State private var aestheticsScore: Float?
    @State private var sceneLabels: [String] = []
    @State private var detectedObjects: [String] = []
    @State private var showMetricsHUD = true
    @State private var confidenceThreshold: Float = 0.5
    @State private var frameRate: Double = 0
    @State private var lastFrameTime: Date = Date()
    @State private var regionCounts: [RegionType: Int] = [:]
    @State private var humanPoses: [DetectedPose] = []
    @State private var animalPoses: [DetectedPose] = []

    // Temporal smoothing for document detection (reduces jitter)
    @State private var lastStableDocumentBox: CGRect?
    @State private var documentStabilityCounter: Int = 0
    private let stabilityThreshold: Int = 3  // Frames before accepting new position

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview layer
                CameraPreviewLayer(session: cameraManager.session)
                    .ignoresSafeArea()

                // AR Overlay layer with detected regions
                DetectionOverlayView(
                    regions: filteredRegions,
                    selectedType: selectedRegionType
                )
                .ignoresSafeArea()

                // Pose wireframe overlay
                PoseWireframeOverlay(
                    humanPoses: humanPoses,
                    animalPoses: animalPoses
                )
                .ignoresSafeArea()

                // UI Controls overlay
                VStack(spacing: 0) {
                    // Top bar with filters and flash
                    topControlsBar

                    // Live metrics HUD
                    if showMetricsHUD {
                        metricsHUD
                    }

                    Spacer()

                    // Scene & Object labels
                    if !sceneLabels.isEmpty || !detectedObjects.isEmpty || (regionCounts[.face] ?? 0) > 0 || (regionCounts[.human] ?? 0) > 0 {
                        liveLabelsView
                    }

                    // Live OCR preview (scrollable)
                    if !liveOCRText.isEmpty && (selectedRegionType == .all || selectedRegionType == .text) {
                        liveOCRPreview
                    }

                    // Bottom capture controls
                    bottomCaptureBar
                }
            }
            .navigationTitle("Vision Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showMetricsHUD.toggle()
                    } label: {
                        Image(systemName: showMetricsHUD ? "chart.bar.fill" : "chart.bar")
                    }
                }
            }
            .onAppear {
                cameraManager.startSession()
                cameraManager.onFrameAnalyzed = handleFrameAnalysis
            }
            .onDisappear {
                cameraManager.stopSession()
            }
            .sheet(isPresented: $showCaptureConfirmation) {
                if let result = captureResult {
                    CaptureConfirmationSheet(
                        result: result,
                        ragService: ragService,
                        containerService: containerService,
                        onConfirm: { handleCapture(result) },
                        onDismiss: { captureResult = nil }
                    )
                }
            }
        }
    }

    // MARK: - Filtered Regions

    private var filteredRegions: [DetectedRegion] {
        detectedRegions.filter { region in
            // Apply confidence threshold
            guard region.confidence >= confidenceThreshold else { return false }

            // Apply type filter
            if selectedRegionType != .all && region.type != selectedRegionType {
                return false
            }

            // Additional filtering for noisy detections
            switch region.type {
            case .document:
                // Only show document if it covers significant area (25%+ of screen)
                // and has reasonable aspect ratio (not tiny fragments)
                let area = region.boundingBox.width * region.boundingBox.height
                let aspectRatio = region.boundingBox.width / max(region.boundingBox.height, 0.01)
                return area > 0.25 && aspectRatio > 0.3 && aspectRatio < 3.0
            case .text:
                // Only show text if it has content and reasonable size
                let hasContent = region.preview?.isEmpty == false
                let minSize = region.boundingBox.width > 0.05 && region.boundingBox.height > 0.02
                return hasContent && minSize
            case .scene:
                // Scene labels don't need bounding boxes in overlay
                return false
            case .human, .face:
                // Filter tiny detections
                return region.boundingBox.width * region.boundingBox.height > 0.01
            default:
                return true
            }
        }
    }

    // MARK: - Top Controls

    private var topControlsBar: some View {
        HStack {
            // Flash toggle
            Button {
                flashEnabled.toggle()
                cameraManager.setFlash(flashEnabled)
            } label: {
                Image(systemName: flashEnabled ? "bolt.fill" : "bolt.slash")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            Spacer()

            // Region type filter
            Picker("Filter", selection: $selectedRegionType) {
                ForEach(RegionType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .background(Capsule().fill(Color.black.opacity(0.5)))
        }
        .padding()
    }

    // MARK: - Live Metrics HUD

    private var metricsHUD: some View {
        VStack(spacing: 8) {
            // Top row: FPS, Aesthetics, Confidence
            HStack(spacing: 16) {
                MetricPill(
                    icon: "speedometer",
                    value: String(format: "%.0f", frameRate),
                    label: "FPS",
                    color: frameRate > 8 ? .green : .orange
                )

                if let score = aestheticsScore {
                    MetricPill(
                        icon: "sparkles",
                        value: String(format: "%.0f%%", score * 100),
                        label: "Quality",
                        color: score > 0.6 ? .green : (score > 0.3 ? .orange : .red)
                    )
                }

                MetricPill(
                    icon: "slider.horizontal.3",
                    value: String(format: "%.0f%%", confidenceThreshold * 100),
                    label: "Threshold",
                    color: .blue
                )
            }

            // Second row: Detection counts by type
            HStack(spacing: 12) {
                ForEach(RegionType.allCases.filter { $0 != .all }) { type in
                    let count = regionCounts[type] ?? 0
                    HStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.caption2)
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(count > 0 ? type.color : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                }
            }

            // Third row: Pose detection counts
            if !humanPoses.isEmpty || !animalPoses.isEmpty {
                HStack(spacing: 16) {
                    if !humanPoses.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.caption2)
                            Text("\(humanPoses.count) skeleton\(humanPoses.count == 1 ? "" : "s")")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.cyan.opacity(0.2)))
                    }

                    if !animalPoses.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "pawprint.fill")
                                .font(.caption2)
                            Text("\(animalPoses.count) animal\(animalPoses.count == 1 ? "" : "s")")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                    }
                }
            }

            // Confidence slider
            HStack {
                Text("Min Confidence")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Slider(value: $confidenceThreshold, in: 0.1...0.9, step: 0.1)
                    .tint(.white)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }

    // MARK: - Helper Functions

    /// Get color for detected object based on emoji prefix
    private func colorForDetectedObject(_ label: String) -> Color {
        if label.hasPrefix("🐾") { return .orange }
        if label.hasPrefix("🌿") { return .green }
        if label.hasPrefix("📱") { return .blue }
        if label.hasPrefix("🚗") { return .purple }
        if label.hasPrefix("🍽️") { return .red }
        return .orange
    }

    // MARK: - Live Labels View

    private var liveLabelsView: some View {
        VStack(spacing: 8) {
            // Scene labels
            if !sceneLabels.isEmpty {
                HStack {
                    Image(systemName: "photo")
                        .foregroundColor(.pink)
                    Text("Scene:")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    ForEach(sceneLabels.prefix(3), id: \.self) { label in
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.pink.opacity(0.8)))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }

            // Detected objects - now with emoji prefixes for categories
            if !detectedObjects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundColor(.orange)
                        Text("Detected:")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Spacer()
                    }

                    // Wrap objects in a flowing layout
                    FlowLayout(spacing: 6) {
                        ForEach(detectedObjects.prefix(8), id: \.self) { obj in
                            // Color based on emoji prefix
                            let color = colorForDetectedObject(obj)
                            Text(obj)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(color.opacity(0.85)))
                                .foregroundColor(.white)
                        }
                    }
                }
            }

            // Face and Human detection counts
            let faceCount = regionCounts[.face] ?? 0
            let humanCount = regionCounts[.human] ?? 0
            if faceCount > 0 || humanCount > 0 {
                HStack {
                    if faceCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "face.smiling")
                                .foregroundColor(.cyan)
                            Text("\(faceCount) face\(faceCount == 1 ? "" : "s")")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.cyan.opacity(0.8)))
                                .foregroundColor(.white)
                        }
                    }
                    if humanCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.stand")
                                .foregroundColor(.mint)
                            Text("\(humanCount) person\(humanCount == 1 ? "" : "s")")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.mint.opacity(0.8)))
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }

    // MARK: - Live OCR Preview

    private var liveOCRPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.viewfinder")
                Text("Live Text")
                    .font(.caption.bold())
                Spacer()
                Text("\(liveOCRText.count) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                Text(liveOCRText)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(5)
            }
            .frame(maxHeight: 80)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }

    // MARK: - Bottom Capture Bar

    private var bottomCaptureBar: some View {
        HStack(spacing: 40) {
            // Quick capture (text only)
            Button {
                captureTextOnly()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.title2)
                    Text("Text")
                        .font(.caption2)
                }
                .foregroundColor(.white)
            }

            // Main capture button
            Button {
                performFullCapture()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 70, height: 70)

                    Circle()
                        .fill(isCapturing ? Color.red : Color.white)
                        .frame(width: 58, height: 58)

                    if isCapturing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
            .disabled(isCapturing)

            // Document capture (full structured)
            Button {
                captureDocument()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.richtext")
                        .font(.title2)
                    Text("Document")
                        .font(.caption2)
                }
                .foregroundColor(.white)
            }
        }
        .padding(.vertical, 30)
        .padding(.horizontal)
        .background(
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        )
    }

    // MARK: - Actions

    private func handleFrameAnalysis(_ analysis: FrameAnalysis) {
        // Calculate FPS
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFrameTime)
        if elapsed > 0 {
            frameRate = 1.0 / elapsed
        }
        lastFrameTime = now

        // Count regions by type
        var counts: [RegionType: Int] = [:]
        for region in analysis.regions {
            counts[region.type, default: 0] += 1
        }

        // Apply temporal smoothing to document regions to reduce jitter
        let smoothedRegions = smoothDocumentRegions(analysis.regions)

        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            detectedRegions = smoothedRegions
            liveOCRText = analysis.recognizedText
            aestheticsScore = analysis.aestheticsScore
            sceneLabels = analysis.sceneLabels
            detectedObjects = analysis.detectedObjects
            regionCounts = counts
            humanPoses = analysis.humanPoses
            animalPoses = analysis.animalPoses
        }
    }

    /// Apply temporal smoothing to document detections to reduce visual jitter
    private func smoothDocumentRegions(_ regions: [DetectedRegion]) -> [DetectedRegion] {
        var result: [DetectedRegion] = []

        for region in regions {
            if region.type == .document {
                // Check if the new position is significantly different from last stable
                if let lastStable = lastStableDocumentBox {
                    let deltaX = abs(region.boundingBox.minX - lastStable.minX)
                    let deltaY = abs(region.boundingBox.minY - lastStable.minY)
                    let deltaW = abs(region.boundingBox.width - lastStable.width)
                    let deltaH = abs(region.boundingBox.height - lastStable.height)

                    // Only accept new position if it's significantly different
                    let threshold: CGFloat = 0.03  // 3% movement required
                    if deltaX < threshold && deltaY < threshold &&
                       deltaW < threshold && deltaH < threshold {
                        // Position hasn't changed enough - use stable position
                        documentStabilityCounter = max(0, documentStabilityCounter - 1)
                        result.append(DetectedRegion(
                            type: .document,
                            boundingBox: lastStable,
                            confidence: region.confidence,
                            preview: region.preview
                        ))
                        continue
                    } else {
                        // Position changed significantly
                        documentStabilityCounter += 1
                        if documentStabilityCounter >= stabilityThreshold {
                            // New position is stable, update
                            lastStableDocumentBox = region.boundingBox
                            documentStabilityCounter = 0
                        } else {
                            // Still settling, use interpolated position
                            let smoothed = CGRect(
                                x: lastStable.minX * 0.7 + region.boundingBox.minX * 0.3,
                                y: lastStable.minY * 0.7 + region.boundingBox.minY * 0.3,
                                width: lastStable.width * 0.7 + region.boundingBox.width * 0.3,
                                height: lastStable.height * 0.7 + region.boundingBox.height * 0.3
                            )
                            result.append(DetectedRegion(
                                type: .document,
                                boundingBox: smoothed,
                                confidence: region.confidence,
                                preview: region.preview
                            ))
                            continue
                        }
                    }
                } else {
                    // First document detection
                    lastStableDocumentBox = region.boundingBox
                    documentStabilityCounter = 0
                }
                result.append(region)
            } else {
                result.append(region)
            }
        }

        // Clear stable position if no document detected
        if !regions.contains(where: { $0.type == .document }) {
            lastStableDocumentBox = nil
            documentStabilityCounter = 0
        }

        return result
    }

    private func captureTextOnly() {
        guard !liveOCRText.isEmpty else { return }

        let result = CaptureResult(
            captureType: .textOnly,
            recognizedText: liveOCRText,
            structuredElements: [],
            image: nil,
            timestamp: Date(),
            imageDescription: nil,
            sceneLabels: [],
            detectedObjects: []
        )

        captureResult = result
        showCaptureConfirmation = true
    }

    private func performFullCapture() {
        isCapturing = true

        Task {
            do {
                let result = try await cameraManager.captureFullAnalysis()
                await MainActor.run {
                    isCapturing = false
                    captureResult = result
                    showCaptureConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                }
                Log.error("[CameraVision] Capture failed: \(error.localizedDescription)", category: .ingestion)
            }
        }
    }

    private func captureDocument() {
        isCapturing = true

        Task {
            do {
                let result = try await cameraManager.captureDocumentStructure()
                await MainActor.run {
                    isCapturing = false
                    captureResult = result
                    showCaptureConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                }
                Log.error("[CameraVision] Document capture failed: \(error.localizedDescription)", category: .ingestion)
            }
        }
    }

    private func handleCapture(_ result: CaptureResult) {
        Task {
            do {
                // Use CaptureToRAGBridge to ingest
                try await CaptureToRAGBridge.shared.ingestCapture(
                    result,
                    to: containerService.activeContainerId,
                    ragService: ragService
                )

                await MainActor.run {
                    dismiss()
                }
            } catch {
                Log.error("[CameraVision] Ingestion failed: \(error.localizedDescription)", category: .ingestion)
            }
        }
    }
}

// MARK: - Supporting Types

/// Type of region detected in camera frame
enum RegionType: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case table = "Table"
    case document = "Document"
    case barcode = "Barcode"
    case object = "Object"    // Detected objects/animals
    case scene = "Scene"      // Scene classification
    case face = "Face"        // Face detection
    case human = "Human"      // Human body detection

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .text: return "text.viewfinder"
        case .table: return "tablecells"
        case .document: return "doc.viewfinder"
        case .barcode: return "barcode.viewfinder"
        case .object: return "cube"
        case .scene: return "photo"
        case .face: return "face.smiling"
        case .human: return "figure.stand"
        }
    }

    var color: Color {
        switch self {
        case .all: return .white
        case .text: return .green
        case .table: return .blue
        case .document: return .yellow
        case .barcode: return .purple
        case .object: return .orange
        case .scene: return .pink
        case .face: return .cyan
        case .human: return .mint
        }
    }
}

/// Detected region from Vision analysis
struct DetectedRegion: Identifiable {
    let id = UUID()
    let type: RegionType
    let boundingBox: CGRect  // Normalized 0-1 coordinates
    let confidence: Float
    let preview: String?     // Brief text preview for text regions
}

/// Skeleton joint for pose detection
struct PoseJoint: Identifiable {
    let id = UUID()
    let name: String
    let position: CGPoint  // Normalized 0-1 coordinates
    let confidence: Float
}

/// Connection between two joints for wireframe
struct PoseConnection: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
    let confidence: Float
}

/// Detected pose (human or animal)
struct DetectedPose: Identifiable {
    let id = UUID()
    let isHuman: Bool
    let joints: [PoseJoint]
    let connections: [PoseConnection]
    let boundingBox: CGRect
    let confidence: Float
}

/// Result from frame analysis
struct FrameAnalysis {
    let regions: [DetectedRegion]
    let recognizedText: String
    let aestheticsScore: Float?
    let sceneLabels: [String]       // Top scene classifications
    let detectedObjects: [String]   // Animals, people, etc.
    let humanPoses: [DetectedPose]  // Human skeleton poses
    let animalPoses: [DetectedPose] // Animal skeleton poses
    let lensSmudgeDetected: Bool    // iOS 26 lens smudge detection
}

/// Capture result ready for RAG ingestion
struct CaptureResult {
    enum CaptureType {
        case textOnly
        case fullImage
        case structuredDocument
    }

    let captureType: CaptureType
    let recognizedText: String
    let structuredElements: [StructuredCaptureElement]
    let image: CGImage?
    let timestamp: Date
    let imageDescription: String?   // AI-generated description of the image
    let sceneLabels: [String]       // Scene classifications
    let detectedObjects: [String]   // Detected objects/animals
}

/// Structured element from document capture
struct StructuredCaptureElement {
    enum ElementType {
        case paragraph
        case table(rows: Int, columns: Int)
        case list(items: Int)
        case heading
    }

    let type: ElementType
    let content: String
    let boundingBox: CGRect
}

// MARK: - Camera Preview Layer

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.session = session
    }
}

/// Custom UIView that properly updates the preview layer frame on layout
class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            if let session = session {
                previewLayer.session = session
            }
        }
    }

    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - Detection Overlay View

struct DetectionOverlayView: View {
    let regions: [DetectedRegion]
    let selectedType: RegionType

    private var filteredRegions: [DetectedRegion] {
        if selectedType == .all {
            return regions
        }
        return regions.filter { $0.type == selectedType }
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(filteredRegions) { region in
                // Use silhouettes for humans and faces, bounding box for others
                switch region.type {
                case .human:
                    HumanSilhouetteOverlay(
                        region: region,
                        containerSize: geometry.size
                    )
                case .face:
                    FaceSilhouetteOverlay(
                        region: region,
                        containerSize: geometry.size
                    )
                default:
                    RegionBoundingBox(
                        region: region,
                        containerSize: geometry.size
                    )
                }
            }
        }
    }
}

// MARK: - Face Silhouette Overlay

struct FaceSilhouetteOverlay: View {
    let region: DetectedRegion
    let containerSize: CGSize

    private var frame: CGRect {
        let x = region.boundingBox.minX * containerSize.width
        let y = (1 - region.boundingBox.maxY) * containerSize.height
        let width = region.boundingBox.width * containerSize.width
        let height = region.boundingBox.height * containerSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var body: some View {
        ZStack {
            // Face silhouette with stylized features
            Canvas { context, size in
                let rect = frame
                let faceColor = Color.cyan

                // Face oval
                let faceRect = CGRect(
                    x: rect.minX + rect.width * 0.1,
                    y: rect.minY + rect.height * 0.05,
                    width: rect.width * 0.8,
                    height: rect.height * 0.9
                )
                let facePath = Path(ellipseIn: faceRect)

                // Eyes (two small ovals)
                let eyeY = rect.minY + rect.height * 0.35
                let eyeWidth = rect.width * 0.15
                let eyeHeight = rect.height * 0.08
                let eyeSpacing = rect.width * 0.25

                let leftEyeRect = CGRect(
                    x: rect.midX - eyeSpacing - eyeWidth/2,
                    y: eyeY - eyeHeight/2,
                    width: eyeWidth,
                    height: eyeHeight
                )
                let rightEyeRect = CGRect(
                    x: rect.midX + eyeSpacing - eyeWidth/2,
                    y: eyeY - eyeHeight/2,
                    width: eyeWidth,
                    height: eyeHeight
                )
                let leftEyePath = Path(ellipseIn: leftEyeRect)
                let rightEyePath = Path(ellipseIn: rightEyeRect)

                // Nose (simple line/triangle)
                var nosePath = Path()
                let noseTop = rect.minY + rect.height * 0.42
                let noseBottom = rect.minY + rect.height * 0.58
                let noseWidth = rect.width * 0.08
                nosePath.move(to: CGPoint(x: rect.midX, y: noseTop))
                nosePath.addLine(to: CGPoint(x: rect.midX - noseWidth, y: noseBottom))
                nosePath.addLine(to: CGPoint(x: rect.midX + noseWidth, y: noseBottom))

                // Mouth (curved line)
                var mouthPath = Path()
                let mouthY = rect.minY + rect.height * 0.72
                let mouthWidth = rect.width * 0.25
                mouthPath.move(to: CGPoint(x: rect.midX - mouthWidth, y: mouthY))
                mouthPath.addQuadCurve(
                    to: CGPoint(x: rect.midX + mouthWidth, y: mouthY),
                    control: CGPoint(x: rect.midX, y: mouthY + rect.height * 0.08)
                )

                // Draw glow layer
                context.fill(facePath, with: .color(faceColor.opacity(0.15)))

                // Draw strokes
                context.stroke(facePath, with: .color(faceColor), style: StrokeStyle(lineWidth: 2.5))
                context.fill(leftEyePath, with: .color(faceColor.opacity(0.8)))
                context.fill(rightEyePath, with: .color(faceColor.opacity(0.8)))
                context.stroke(nosePath, with: .color(faceColor.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5))
                context.stroke(mouthPath, with: .color(faceColor.opacity(0.7)), style: StrokeStyle(lineWidth: 2))
            }
            .shadow(color: .cyan.opacity(0.6), radius: 6)

            // Label
            Text("Face")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.cyan.opacity(0.85)))
                .position(x: frame.midX, y: frame.minY - 14)
        }
    }
}

// MARK: - Human Silhouette Overlay

struct HumanSilhouetteOverlay: View {
    let region: DetectedRegion
    let containerSize: CGSize

    private var frame: CGRect {
        let x = region.boundingBox.minX * containerSize.width
        let y = (1 - region.boundingBox.maxY) * containerSize.height
        let width = region.boundingBox.width * containerSize.width
        let height = region.boundingBox.height * containerSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var body: some View {
        ZStack {
            // Silhouette shape - human figure approximation
            Canvas { context, size in
                let rect = frame

                // Head (oval at top)
                let headWidth = rect.width * 0.35
                let headHeight = rect.height * 0.15
                let headRect = CGRect(
                    x: rect.midX - headWidth/2,
                    y: rect.minY,
                    width: headWidth,
                    height: headHeight
                )
                let headPath = Path(ellipseIn: headRect)

                // Body (tapered shape)
                var bodyPath = Path()
                let shoulderY = rect.minY + headHeight
                let shoulderWidth = rect.width * 0.6
                let hipY = rect.minY + rect.height * 0.55
                let hipWidth = rect.width * 0.45
                let waistY = rect.minY + rect.height * 0.4
                let waistWidth = rect.width * 0.35

                bodyPath.move(to: CGPoint(x: rect.midX - shoulderWidth/2, y: shoulderY))
                bodyPath.addQuadCurve(
                    to: CGPoint(x: rect.midX - waistWidth/2, y: waistY),
                    control: CGPoint(x: rect.midX - shoulderWidth/2, y: (shoulderY + waistY) / 2)
                )
                bodyPath.addQuadCurve(
                    to: CGPoint(x: rect.midX - hipWidth/2, y: hipY),
                    control: CGPoint(x: rect.midX - waistWidth/2.5, y: (waistY + hipY) / 2)
                )
                bodyPath.addLine(to: CGPoint(x: rect.midX + hipWidth/2, y: hipY))
                bodyPath.addQuadCurve(
                    to: CGPoint(x: rect.midX + waistWidth/2, y: waistY),
                    control: CGPoint(x: rect.midX + waistWidth/2.5, y: (waistY + hipY) / 2)
                )
                bodyPath.addQuadCurve(
                    to: CGPoint(x: rect.midX + shoulderWidth/2, y: shoulderY),
                    control: CGPoint(x: rect.midX + shoulderWidth/2, y: (shoulderY + waistY) / 2)
                )
                bodyPath.closeSubpath()

                // Legs (two rectangles)
                let legWidth = rect.width * 0.18
                let legSpacing = rect.width * 0.08
                let legTop = hipY - rect.height * 0.02
                let legBottom = rect.maxY

                let leftLeg = Path(roundedRect: CGRect(
                    x: rect.midX - legSpacing - legWidth,
                    y: legTop,
                    width: legWidth,
                    height: legBottom - legTop
                ), cornerRadius: legWidth/3)

                let rightLeg = Path(roundedRect: CGRect(
                    x: rect.midX + legSpacing,
                    y: legTop,
                    width: legWidth,
                    height: legBottom - legTop
                ), cornerRadius: legWidth/3)

                // Draw with glow
                let silhouetteColor = Color.mint

                // Glow layer
                context.fill(headPath, with: .color(silhouetteColor.opacity(0.3)))
                context.fill(bodyPath, with: .color(silhouetteColor.opacity(0.3)))
                context.fill(leftLeg, with: .color(silhouetteColor.opacity(0.3)))
                context.fill(rightLeg, with: .color(silhouetteColor.opacity(0.3)))

                // Stroke layer
                context.stroke(headPath, with: .color(silhouetteColor), style: StrokeStyle(lineWidth: 2))
                context.stroke(bodyPath, with: .color(silhouetteColor), style: StrokeStyle(lineWidth: 2))
                context.stroke(leftLeg, with: .color(silhouetteColor), style: StrokeStyle(lineWidth: 2))
                context.stroke(rightLeg, with: .color(silhouetteColor), style: StrokeStyle(lineWidth: 2))
            }
            .shadow(color: .mint.opacity(0.6), radius: 8)

            // Label
            Text("Person")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.mint.opacity(0.85)))
                .position(x: frame.midX, y: frame.minY - 16)
        }
    }
}

struct RegionBoundingBox: View {
    let region: DetectedRegion
    let containerSize: CGSize

    private var frame: CGRect {
        // Convert normalized coords to screen coords
        // Vision uses bottom-left origin, SwiftUI uses top-left
        let x = region.boundingBox.minX * containerSize.width
        let y = (1 - region.boundingBox.maxY) * containerSize.height
        let width = region.boundingBox.width * containerSize.width
        let height = region.boundingBox.height * containerSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var cornerRadius: CGFloat {
        min(8, min(frame.width, frame.height) * 0.1)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box with animated stroke - smoothed with animation
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    region.type.color,
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: region.type == .document ? [8, 4] : []
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(region.type.color.opacity(0.05))
                )
                .shadow(color: region.type.color.opacity(0.4), radius: 3)
                .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: frame)

            // Type label with confidence
            HStack(spacing: 4) {
                Image(systemName: region.type.icon)
                    .font(.system(size: 10, weight: .bold))

                if let preview = region.preview {
                    Text(preview.prefix(15))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }

                // Confidence indicator
                Text(String(format: "%.0f%%", region.confidence * 100))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(region.type.color.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            )
            .offset(x: 4, y: -24)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
}

// MARK: - Pose Wireframe Overlay

struct PoseWireframeOverlay: View {
    let humanPoses: [DetectedPose]
    let animalPoses: [DetectedPose]

    var body: some View {
        GeometryReader { geometry in
            // Draw human wireframes
            ForEach(humanPoses) { pose in
                HumanWireframe(pose: pose, containerSize: geometry.size)
            }

            // Draw animal wireframes
            ForEach(animalPoses) { pose in
                AnimalWireframe(pose: pose, containerSize: geometry.size)
            }
        }
    }
}

// MARK: - Human Wireframe

/// Anatomically accurate human skeleton visualization
/// Based on COCO 17-keypoint format with proper bone proportions
struct HumanWireframe: View {
    let pose: DetectedPose
    let containerSize: CGSize

    // Anatomical color scheme
    private let boneColor = Color.cyan           // Main skeleton
    private let jointColor = Color.white         // Joint nodes
    private let spineColor = Color.cyan.opacity(0.9)  // Spine emphasis
    private let glowColor = Color.cyan.opacity(0.5)

    var body: some View {
        ZStack {
            // Draw bones with anatomically appropriate thicknesses
            ForEach(pose.connections) { connection in
                let thickness = boneThickness(from: connection)
                WireframeLine(
                    from: convertPoint(connection.from),
                    to: convertPoint(connection.to),
                    color: boneColor,
                    glowColor: glowColor,
                    lineWidth: thickness,
                    confidence: connection.confidence
                )
            }

            // Draw joints with anatomically accurate sizes
            ForEach(pose.joints) { joint in
                WireframeJoint(
                    position: convertPoint(joint.position),
                    color: jointColor,
                    glowColor: boneColor,
                    size: anatomicalJointSize(for: joint.name),
                    confidence: joint.confidence
                )
            }

            // Label above head
            if let headJoint = pose.joints.first(where: { $0.name.contains("nose") }) {
                let pos = convertPoint(headJoint.position)
                Text("Human")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(boneColor.opacity(0.85)))
                    .position(x: pos.x, y: pos.y - 35)
            }
        }
    }

    private func convertPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * containerSize.width,
            y: (1 - point.y) * containerSize.height
        )
    }

    /// Simple joint sizes for clean stick figure
    private func anatomicalJointSize(for name: String) -> CGFloat {
        let nameLower = name.lowercased()

        // Head - largest (top of T)
        if nameLower.contains("nose") {
            return 14
        }
        // Major structural joints
        if nameLower.contains("shoulder") || nameLower.contains("hip") {
            return 10
        }
        // Neck and pelvis center
        if nameLower.contains("neck") || nameLower.contains("root") {
            return 8
        }
        // Elbows and knees
        if nameLower.contains("elbow") || nameLower.contains("knee") {
            return 8
        }
        // Hands (wrists) and feet (ankles)
        if nameLower.contains("wrist") || nameLower.contains("ankle") {
            return 7
        }
        return 6
    }

    /// Clean uniform bone thickness
    private func boneThickness(from connection: PoseConnection) -> CGFloat {
        return 4.0 * CGFloat(max(0.7, connection.confidence))
    }
}

// MARK: - Animal Wireframe

/// Anatomically accurate quadruped skeleton visualization
/// Based on veterinary anatomy with proper bone structure
struct AnimalWireframe: View {
    let pose: DetectedPose
    let containerSize: CGSize

    // Anatomical color scheme for animals
    private let boneColor = Color.orange
    private let jointColor = Color.white
    private let bodyColor = Color.orange.opacity(0.9)
    private let glowColor = Color.orange.opacity(0.5)

    var body: some View {
        ZStack {
            // Draw bones with anatomically appropriate thicknesses
            ForEach(pose.connections) { connection in
                let thickness = animalBoneThickness(from: connection)
                WireframeLine(
                    from: convertPoint(connection.from),
                    to: convertPoint(connection.to),
                    color: boneColor,
                    glowColor: glowColor,
                    lineWidth: thickness,
                    confidence: connection.confidence
                )
            }

            // Draw joints with anatomically accurate sizes
            ForEach(pose.joints) { joint in
                WireframeJoint(
                    position: convertPoint(joint.position),
                    color: jointColor,
                    glowColor: boneColor,
                    size: animalJointSize(for: joint.name),
                    confidence: joint.confidence
                )
            }

            // Label above head
            if let headJoint = pose.joints.first(where: { $0.name.contains("nose") }) {
                let pos = convertPoint(headJoint.position)
                Text("Animal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(boneColor.opacity(0.85)))
                    .position(x: pos.x, y: pos.y - 30)
            }
        }
    }

    private func convertPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * containerSize.width,
            y: (1 - point.y) * containerSize.height
        )
    }

    /// Simple joint sizes for clean stick figure
    private func animalJointSize(for name: String) -> CGFloat {
        let nameLower = name.lowercased()

        // Head
        if nameLower.contains("nose") {
            return 12
        }
        // Neck
        if nameLower.contains("neck") {
            return 8
        }
        // Shoulders and hips (major body joints)
        if nameLower.contains("elbow") && !nameLower.contains("knee") {
            return 10
        }
        // Knees/elbows (leg joints)
        if nameLower.contains("knee") {
            return 8
        }
        // Paws
        if nameLower.contains("paw") {
            return 7
        }
        // Tail
        if nameLower.contains("tail") {
            return 6
        }
        return 6
    }

    /// Clean uniform bone thickness
    private func animalBoneThickness(from connection: PoseConnection) -> CGFloat {
        return 4.0 * CGFloat(max(0.7, connection.confidence))
    }
}

// MARK: - Wireframe Components

struct WireframeLine: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let glowColor: Color
    let lineWidth: CGFloat
    let confidence: Float

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)

            // Glow effect
            context.stroke(
                path,
                with: .color(glowColor),
                style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round)
            )

            // Main line
            context.stroke(
                path,
                with: .color(color.opacity(Double(confidence))),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }
}

struct WireframeJoint: View {
    let position: CGPoint
    let color: Color
    let glowColor: Color
    let size: CGFloat
    let confidence: Float

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(glowColor)
                .frame(width: size + 6, height: size + 6)
                .blur(radius: 4)

            // Inner circle
            Circle()
                .fill(color.opacity(Double(confidence)))
                .frame(width: size, height: size)

            // Highlight
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: size * 0.4, height: size * 0.4)
                .offset(x: -size * 0.15, y: -size * 0.15)
        }
        .position(position)
    }
}

// MARK: - Capture Confirmation Sheet

struct CaptureConfirmationSheet: View {
    let result: CaptureResult
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @State private var customTitle = ""
    @State private var isIngesting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Preview
                if let image = result.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                }

                // Stats
                HStack(spacing: 20) {
                    StatBadge(
                        icon: "character.cursor.ibeam",
                        value: "\(result.recognizedText.count)",
                        label: "Characters"
                    )

                    StatBadge(
                        icon: "doc.text",
                        value: "\(result.recognizedText.split(separator: " ").count)",
                        label: "Words"
                    )

                    if !result.structuredElements.isEmpty {
                        StatBadge(
                            icon: "rectangle.3.group",
                            value: "\(result.structuredElements.count)",
                            label: "Elements"
                        )
                    }
                }

                // Title input
                TextField("Document title (optional)", text: $customTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                // Container selector
                HStack {
                    Text("Add to:")
                        .foregroundColor(.secondary)

                    Text(containerService.activeContainer?.name ?? "Default Library")
                        .fontWeight(.medium)

                    Spacer()
                }
                .padding(.horizontal)

                // Text preview
                GroupBox("Captured Text") {
                    ScrollView {
                        Text(result.recognizedText.prefix(500))
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Confirm Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isIngesting = true
                        onConfirm()
                    } label: {
                        if isIngesting {
                            ProgressView()
                        } else {
                            Text("Add to Library")
                        }
                    }
                    .disabled(isIngesting || result.recognizedText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.headline)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
    }
}

// MARK: - Metric Pill

struct MetricPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.6)))
    }
}

// MARK: - Preview

#Preview {
    CameraVisionOverlayView(
        ragService: RAGService(),
        containerService: ContainerService()
    )
}
#endif


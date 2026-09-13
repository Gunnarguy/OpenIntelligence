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

        /// Carries each detection's identity across frames so the springs in this file can
        /// actually interpolate. See `RegionIdentityTracker`.
        @State private var identityTracker = RegionIdentityTracker()

        /// Same job for skeletons. Without it the pose view is replaced every frame and the stable
        /// joint and bone ids inside it achieve nothing, because their parent did not survive.
        @State private var poseTracker = PoseIdentityTracker()

        /// Pixel size of the frame Vision analysed, reported per frame by `CameraManager`.
        /// `CameraOverlayGeometry` needs it to undo the preview layer's `.resizeAspectFill` crop;
        /// `.zero` makes the geometry return `.zero` rather than divide by it.
        @State private var analysedSourceSize: CGSize = .zero

        @State private var liveOCRText: String = ""
        @State private var isCapturing = false
        @State private var captureResult: CaptureResult?
        @State private var showCaptureConfirmation = false
        @State private var selectedRegionType: RegionType = .all
        @State private var flashEnabled = false
        @State private var aestheticsScore: Float?
        @State private var sceneLabels: [String] = []
        @State private var detectedObjects: [String] = []
        /// The diagnostics panel: FPS, threshold, eight per-type counters and a confidence slider,
        /// inside an `.ultraThinMaterial` card that re-blurs the live video every frame.
        ///
        /// **Off by default as of 2026-09-11.** It was on, and on a phone it covered roughly 40% of
        /// the viewfinder, so the first thing anyone saw when opening the camera was a wall of
        /// instrumentation over the thing they were trying to point at. It is genuinely useful when
        /// tuning detection, which is why it is still one tap away on the chart button, but it is a
        /// developer's view of the screen rather than a user's.
        @State private var showMetricsHUD = false
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
                        selectedType: selectedRegionType,
                        sourceSize: analysedSourceSize
                    )
                    .ignoresSafeArea()

                    // Pose wireframe overlay
                    PoseWireframeOverlay(
                        humanPoses: humanPoses,
                        animalPoses: animalPoses,
                        sourceSize: analysedSourceSize
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
                        if !sceneLabels.isEmpty || !detectedObjects.isEmpty || (regionCounts[.face] ?? 0) > 0
                            || (regionCounts[.human] ?? 0) > 0
                        {
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
                // One slider across every detector, whose confidences are not on comparable
                // scales. Text from `.fast` recognition reports a flat 0.5, face and human
                // rectangles report high values, and image classification reports genuinely low
                // ones: a correct "Refrigerator" often lands near 0.3. Judging all of them against
                // the same 0.5 default would hide object detection completely, which is the
                // failure this exemption exists to prevent, and the reader would conclude the
                // detector found nothing rather than that the slider was mis-scaled for it.
                //
                // Objects are gated instead where they are produced, at a classification
                // confidence of 0.25 in `CameraManager.classify`.
                if region.type != .object {
                    guard region.confidence >= confidenceThreshold else { return false }
                }

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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    // A plain `HStack` here could not fit three long classifications on a phone,
                    // so SwiftUI compressed them into each other: "Computer" rendered on top of
                    // "Consumer Electronics". `FlowLayout` is already used for the detected-object
                    // chips immediately below and wraps instead of overlapping.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .foregroundColor(.pink)
                            Text("Scene:")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                            Spacer()
                        }

                        FlowLayout(spacing: 6) {
                            ForEach(sceneLabels.prefix(3), id: \.self) { label in
                                Text(label)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.pink.opacity(0.8)))
                                    .foregroundColor(.white)
                            }
                        }
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    .fill(
                        LinearGradient(
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

            // Carry identity over from the previous frame. This has to happen AFTER smoothing,
            // because `smoothDocumentRegions` builds fresh `DetectedRegion` values of its own and
            // would otherwise throw away whatever the tracker had just assigned. Without this the
            // spring below animates nothing: every id is new, so SwiftUI replaces every view
            // instead of moving it, and the boxes strobe rather than track.
            let trackedRegions = identityTracker.assigningStableIDs(to: smoothedRegions)

            // The size Vision analysed, needed to undo the preview's aspect-fill crop.
            analysedSourceSize = analysis.sourceSize

            // Carry skeleton identity across frames so the wireframe interpolates between samples
            // instead of being rebuilt at each one. Humans and animals are tracked separately so a
            // person standing over a dog cannot inherit the dog's limbs.
            let trackedHuman = poseTracker.assigningStableIDs(to: analysis.humanPoses)
            let trackedAnimal = poseTracker.assigningStableIDs(to: analysis.animalPoses)

            // Geometry animates. Text does not.
            //
            // The chip rows and the OCR panel used to sit inside this block, and they are
            // `ForEach(id: \.self)` over strings, so a changed array is an insert and a remove
            // rather than a move. Animating that crossfades the old set against the new, and at ten
            // updates a second both are on screen at once: "Appliance" printed over "Machine",
            // "1 person" over "2 skeletons". It read as a layout bug and was a transition.
            //
            // There is nothing to interpolate between two different words anyway, so they are
            // assigned outside the animation and simply replace each other.
            sceneLabels = analysis.sceneLabels
            detectedObjects = analysis.detectedObjects
            liveOCRText = analysis.recognizedText
            regionCounts = counts
            aestheticsScore = analysis.aestheticsScore

            withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                detectedRegions = trackedRegions
                humanPoses = trackedHuman
                animalPoses = trackedAnimal
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
                        if deltaX < threshold && deltaY < threshold && deltaW < threshold && deltaH < threshold {
                            // Position hasn't changed enough - use stable position
                            documentStabilityCounter = max(0, documentStabilityCounter - 1)
                            result.append(
                                DetectedRegion(
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
                                result.append(
                                    DetectedRegion(
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
                    Log.error(
                        "[CameraVision] Document capture failed: \(error.localizedDescription)", category: .ingestion)
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
        case object = "Object"  // Detected objects/animals
        case scene = "Scene"  // Scene classification
        case face = "Face"  // Face detection
        case human = "Human"  // Human body detection

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
        /// Stable across frames for the same physical detection, assigned by `RegionIdentityTracker`.
        ///
        /// This was `let id = UUID()`, which gave every region a fresh identity on every frame. Since
        /// the regions are rebuilt each frame, `ForEach` saw a wholly new identity set each update and
        /// SwiftUI destroyed and recreated every box view. That is why the two `interpolatingSpring`
        /// animations in this file never appeared to do anything: a spring interpolates a surviving
        /// view, and none survived. The boxes strobed rather than tracked.
        ///
        /// The default keeps every existing construction site compiling and means "not yet matched";
        /// the tracker replaces it with the previous frame's id when the two overlap enough to be the
        /// same thing.
        let id: UUID
        let type: RegionType
        let boundingBox: CGRect  // Normalized 0-1 coordinates
        let confidence: Float
        let preview: String?  // Brief text preview for text regions

        init(
            id: UUID = UUID(),
            type: RegionType,
            boundingBox: CGRect,
            confidence: Float,
            preview: String? = nil
        ) {
            self.id = id
            self.type = type
            self.boundingBox = boundingBox
            self.confidence = confidence
            self.preview = preview
        }

        func withID(_ id: UUID) -> DetectedRegion {
            DetectedRegion(
                id: id,
                type: type,
                boundingBox: boundingBox,
                confidence: confidence,
                preview: preview
            )
        }
    }

    /// Skeleton joint for pose detection
    ///
    /// **Identity is the joint's anatomical name, not a fresh UUID.** A left elbow in this frame
    /// and a left elbow in the next are the same elbow, moved. Handing SwiftUI a new `UUID()` each
    /// frame, which is what this did, meant every joint was destroyed and recreated ten times a
    /// second, so no position could ever be interpolated and the skeleton teleported between
    /// samples. Combined with a 4-point blur on each joint that read as motion blur, when it was
    /// really blurred dots jumping.
    struct PoseJoint: Identifiable {
        var id: String { name }
        let name: String
        let position: CGPoint  // Normalized 0-1 coordinates
        let confidence: Float
    }

    /// Connection between two joints for wireframe
    ///
    /// Identified by the pair of joints it spans. `CameraManager` builds these from a fixed
    /// `connectionPairs` topology, so "left shoulder to left elbow" names one bone for the life of
    /// the skeleton and survives from frame to frame.
    struct PoseConnection: Identifiable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let confidence: Float
    }

    /// Detected pose (human or animal)
    ///
    /// The id is assigned by `PoseIdentityTracker` from the previous frame's poses, so one person
    /// keeps one skeleton view as they move. Without it the pose view is rebuilt every frame and
    /// the stable joint ids above buy nothing, because their parent did not survive either.
    struct DetectedPose: Identifiable {
        var id: UUID = UUID()
        let isHuman: Bool
        let joints: [PoseJoint]
        let connections: [PoseConnection]
        let boundingBox: CGRect
        let confidence: Float

        func withID(_ id: UUID) -> DetectedPose {
            var copy = self
            copy.id = id
            return copy
        }
    }

    /// Result from frame analysis
    struct FrameAnalysis {
        let regions: [DetectedRegion]
        let recognizedText: String
        let aestheticsScore: Float?
        let sceneLabels: [String]  // Top scene classifications
        let detectedObjects: [String]  // Animals, people, etc.
        let humanPoses: [DetectedPose]  // Human skeleton poses
        let animalPoses: [DetectedPose]  // Animal skeleton poses
        let lensSmudgeDetected: Bool  // iOS 26 lens smudge detection

        /// Pixel size of the image Vision actually analysed, **after** the capture connection's
        /// rotation was applied.
        ///
        /// Carried rather than inferred. The overlay needs it to undo the preview layer's
        /// `.resizeAspectFill` crop, and the obvious shortcut, deriving it from
        /// `session.sessionPreset`, is wrong twice over: a preset is a request the device may not
        /// honour exactly, and it describes the sensor orientation rather than the rotated buffer,
        /// so it has the axes the wrong way round in portrait. `ciImage.extent` is what arrived.
        ///
        /// Defaulted so the capture-path construction sites, which do not feed the live overlay,
        /// need no change.
        let sourceSize: CGSize

        init(
            regions: [DetectedRegion],
            recognizedText: String,
            aestheticsScore: Float?,
            sceneLabels: [String],
            detectedObjects: [String],
            humanPoses: [DetectedPose],
            animalPoses: [DetectedPose],
            lensSmudgeDetected: Bool,
            sourceSize: CGSize = .zero
        ) {
            self.regions = regions
            self.recognizedText = recognizedText
            self.aestheticsScore = aestheticsScore
            self.sceneLabels = sceneLabels
            self.detectedObjects = detectedObjects
            self.humanPoses = humanPoses
            self.animalPoses = animalPoses
            self.lensSmudgeDetected = lensSmudgeDetected
            self.sourceSize = sourceSize
        }
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
        let imageDescription: String?  // AI-generated description of the image
        let sceneLabels: [String]  // Scene classifications
        let detectedObjects: [String]  // Detected objects/animals
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
        /// Pixel size of the analysed frame, threaded down to the box views.
        let sourceSize: CGSize

        private var filteredRegions: [DetectedRegion] {
            if selectedType == .all {
                return regions
            }
            return regions.filter { $0.type == selectedType }
        }

        var body: some View {
            GeometryReader { geometry in
                ForEach(filteredRegions) { region in
                    // Faces get an oval, everything else a box.
                    //
                    // `.human` used to get `HumanSilhouetteOverlay`, which drew a mannequin from
                    // hardcoded fractions of the bounding box: head ellipse at 35% of its width,
                    // shoulders at 60%, waist at 40% of its height, hips at 55%, legs as
                    // rectangles. None of that was measured, so it drew the same figure every time
                    // stretched to whatever rectangle came back, and it could not match a pose
                    // because it never looked at one.
                    //
                    // What made it read as wrong rather than merely stylised is that the real pose
                    // **is** available and already drawn beside it: `PoseWireframeOverlay` renders
                    // measured joints from `VNDetectHumanBodyPoseRequest`. Two overlays claimed to
                    // describe the same body and disagreed, and the invented one was the louder.
                    // The box says where the person is; the wireframe says what they are doing.
                    switch region.type {
                    case .human:
                        RegionBoundingBox(
                            region: region,
                            containerSize: geometry.size,
                            sourceSize: sourceSize
                        )
                    case .face:
                        FaceSilhouetteOverlay(
                            region: region,
                            containerSize: geometry.size,
                            sourceSize: sourceSize
                        )
                    default:
                        RegionBoundingBox(
                            region: region,
                            containerSize: geometry.size,
                            sourceSize: sourceSize
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
        /// Pixel size of the analysed frame, so the aspect-fill crop can be undone.
        let sourceSize: CGSize

        private var frame: CGRect {
            // Was four lines of hand-rolled arithmetic, repeated identically in five places, that
            // stretched Vision's normalized space onto the view's bounds. The preview layer is
            // `.resizeAspectFill`, so those are different spaces. See `CameraOverlayGeometry`.
            return CameraOverlayGeometry.viewRect(
                normalized: region.boundingBox,
                sourceSize: sourceSize,
                viewSize: containerSize
            )
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

                    // The eyes, nose and mouth that used to be drawn here were invented: fixed
                    // fractions of the bounding box, with no `DetectFaceLandmarksRequest` run
                    // anywhere in the app to place them. They could not line up with a real face
                    // because nothing had measured one, so a detected face wore a smiley doodle
                    // that drifted off it. The oval stays, because the face rectangle IS measured
                    // and inscribing an ellipse in it claims nothing the rectangle does not.

                    // Draw glow layer
                    context.fill(facePath, with: .color(faceColor.opacity(0.15)))

                    // Draw strokes
                    context.stroke(facePath, with: .color(faceColor), style: StrokeStyle(lineWidth: 2.5))
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

    struct RegionBoundingBox: View {
        let region: DetectedRegion
        let containerSize: CGSize
        /// Pixel size of the analysed frame, so the aspect-fill crop can be undone.
        let sourceSize: CGSize

        private var frame: CGRect {
            // Convert normalized coords to screen coords
            // Vision uses bottom-left origin, SwiftUI uses top-left
            // Was four lines of hand-rolled arithmetic, repeated identically in five places, that
            // stretched Vision's normalized space onto the view's bounds. The preview layer is
            // `.resizeAspectFill`, so those are different spaces. See `CameraOverlayGeometry`.
            return CameraOverlayGeometry.viewRect(
                normalized: region.boundingBox,
                sourceSize: sourceSize,
                viewSize: containerSize
            )
        }

        private var cornerRadius: CGFloat {
            min(8, min(frame.width, frame.height) * 0.1)
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                // Bounding box with animated stroke - smoothed with animation
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(region.type.color.opacity(0.05))
                    )
                    .shadow(color: region.type.color.opacity(0.4), radius: 3)
                    .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: frame)

                // Type label.
                //
                // **Text regions get no label.** Every box used to carry one, at a fixed -24pt
                // offset with no collision handling, so a page of printed text produced one capsule
                // per recognised line all stacked on top of each other. A photo of a document
                // showed nine overlapping capsules covering the thing being read. The box itself
                // already says where the line is and the Live Text panel already says what it says,
                // so the capsule was adding occlusion and no information.
                //
                // The label stays for the types that are few and genuinely need naming: a document
                // edge, a recognised animal, a face, a person.
                if region.type != .text {
                    HStack(spacing: 4) {
                        Image(systemName: region.type.icon)
                            .font(.system(size: 10, weight: .bold))

                        if let preview = region.preview {
                            Text(preview.prefix(15))
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }

                        // Confidence, but only where it varies. `VNRecognizeTextRequest` in `.fast`
                        // mode reports 0.5 for essentially every observation, so the old
                        // unconditional percentage rendered a literal "50%" on every capsule on
                        // screen: the same number, repeated, meaning nothing.
                        if region.confidence > 0, region.type != .document {
                            Text(String(format: "%.0f%%", region.confidence * 100))
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(region.type.color.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    )
                    // Kept on screen in both axes.
                    //
                    // The y clamp already moved a label below its box when the box was near the
                    // top. The x offset was a flat 4, which is fine until a box extends past the
                    // left edge, and saliency produces exactly that: a whole television is one
                    // salient object whose rectangle starts off-screen. Its label went with it and
                    // arrived sliced in half.
                    //
                    // Offsets here are relative to the box's own top-left, so pushing the label
                    // right by `-frame.minX` puts it back at the screen edge. `min` against the
                    // container keeps a box that starts off-screen *right* from doing the same
                    // thing in the other direction.
                    .offset(
                        x: min(
                            max(4, 4 - frame.minX),
                            max(4, containerSize.width - frame.minX - 120)
                        ),
                        y: frame.minY < 28 ? 4 : -24
                    )
                }
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    // MARK: - Pose Wireframe Overlay

    struct PoseWireframeOverlay: View {
        let humanPoses: [DetectedPose]
        let animalPoses: [DetectedPose]
        /// Pixel size of the analysed frame, threaded down to the wireframes.
        let sourceSize: CGSize

        var body: some View {
            GeometryReader { geometry in
                // Draw human wireframes
                ForEach(humanPoses) { pose in
                    HumanWireframe(pose: pose, containerSize: geometry.size, sourceSize: sourceSize)
                }

                // Draw animal wireframes
                ForEach(animalPoses) { pose in
                    AnimalWireframe(pose: pose, containerSize: geometry.size, sourceSize: sourceSize)
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
        /// Pixel size of the analysed frame, so the aspect-fill crop can be undone.
        let sourceSize: CGSize

        // Anatomical color scheme
        private let boneColor = Color.cyan  // Main skeleton
        private let jointColor = Color.white  // Joint nodes
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
            CameraOverlayGeometry.viewPoint(
                normalized: point,
                sourceSize: sourceSize,
                viewSize: containerSize
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
        /// Pixel size of the analysed frame, so the aspect-fill crop can be undone.
        let sourceSize: CGSize

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
            CameraOverlayGeometry.viewPoint(
                normalized: point,
                sourceSize: sourceSize,
                viewSize: containerSize
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
            ZStack {
                BoneShape(from: from, to: to)
                    .stroke(
                        // Was drawn at full opacity regardless of confidence, so a 20%-confident
                        // limb kept a solid halo even as its core faded out and read as certain.
                        glowColor.opacity(Double(confidence) * 0.5),
                        style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round)
                    )

                BoneShape(from: from, to: to)
                    .stroke(
                        color.opacity(Double(confidence)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            }
            // Matches the joints exactly, so a bone and the joints at its ends move together
            // rather than arriving at slightly different times, which would make the skeleton
            // appear to stretch.
            .animation(.linear(duration: 0.1), value: from)
            .animation(.linear(duration: 0.1), value: to)
        }
    }

    /// A single bone, as an animatable `Shape`.
    ///
    /// **Why not the `Canvas` this replaced.** A `Canvas` draws imperatively: SwiftUI cannot
    /// interpolate what happens inside the closure, so the line jumped to each new position the
    /// instant a frame arrived, ten times a second, no matter what animation wrapped it. A `Shape`
    /// exposes `animatableData`, so the endpoints themselves interpolate and the limb sweeps.
    ///
    /// It is also far cheaper. Each bone previously allocated a **full-size `Canvas`**, and a human
    /// skeleton has sixteen of them, so one person put sixteen screen-sized drawing surfaces on top
    /// of the preview and two people put thirty-two.
    struct BoneShape: Shape {
        var from: CGPoint
        var to: CGPoint

        /// Both endpoints, so a bone whose ends move different distances interpolates correctly
        /// rather than pivoting about one of them.
        var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
            get {
                AnimatablePair(
                    AnimatablePair(from.x, from.y),
                    AnimatablePair(to.x, to.y)
                )
            }
            set {
                from = CGPoint(x: newValue.first.first, y: newValue.first.second)
                to = CGPoint(x: newValue.second.first, y: newValue.second.second)
            }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            return path
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
                // A crisp ring instead of a 4-point Gaussian blur.
                //
                // The blurred disc is what read as motion blur. It was not motion blur: the joint
                // was a soft smudge, and because every joint got a fresh `UUID()` each frame it
                // teleported rather than moved, so a soft dot appearing in a new place ten times a
                // second looked like something smeared. A stroked ring has a defined edge, which is
                // what makes movement legible at all.
                Circle()
                    .stroke(glowColor.opacity(0.55), lineWidth: 1.5)
                    .frame(width: size + 5, height: size + 5)

                Circle()
                    .fill(color.opacity(Double(confidence)))
                    .frame(width: size, height: size)

                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: size * 0.4, height: size * 0.4)
                    .offset(x: -size * 0.15, y: -size * 0.15)
            }
            .position(position)
            // Linear, and matched to the analysis interval rather than sprung.
            //
            // Vision runs at 10 FPS while the display refreshes at 60 or 120, so nine frames in ten
            // have no new data. Interpolating each joint linearly across exactly that 0.1s gap
            // means the skeleton is drawn continuously between samples and arrives at the next one
            // just as it lands. A spring would be wrong here: samples are evenly spaced, so a
            // spring would overshoot each position and wobble back, adding motion that the body
            // being tracked never made.
            .animation(.linear(duration: 0.1), value: position)
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

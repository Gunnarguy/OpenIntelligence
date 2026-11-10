//
//  CameraVisionOverlayView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  Live camera view with Apple Vision framework overlays for real-time
//  document, text, and table detection with one-tap RAG ingestion.
//

// Debug builds only (5.7): the live camera is experimental and held back (the owner, 2026-09-13: it "should probably
// wait"), so Release builds compile none of it. `ChatScreen.visionCaptureAction` has the reasons.
#if os(iOS) && DEBUG
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

        /// Shows a line of live text only once it has repeated across frames. See
        /// `LiveTextStabilizer`.
        @State private var liveTextStabilizer = LiveTextStabilizer()

        /// The open camera area between the top controls and the bottom panels, in global
        /// coordinates, measured from the `Spacer` that separates them. Boxes, labels and
        /// skeletons are clipped to it so they never sit on Cancel, the title or the buttons.
        @State private var openCameraArea: CGRect = .zero

        /// Whether the bottom card shows its chips and live text, or only its one-line caption.
        @State private var detailsExpanded = true

        var body: some View {
            NavigationStack {
                ZStack {
                    // Camera preview layer. The layer is handed to the camera once it is in a window,
                    // so the analysed frames are rotated exactly like the picture on screen.
                    CameraPreviewLayer(session: cameraManager.session) { previewLayer in
                        cameraManager.attachPreviewLayer(previewLayer)
                    }
                    .ignoresSafeArea()

                    // AR Overlay layer with detected regions
                    DetectionOverlayView(
                        regions: filteredRegions,
                        selectedType: selectedRegionType,
                        sourceSize: analysedSourceSize,
                        openAreaGlobal: openCameraArea
                    )
                    .ignoresSafeArea()

                    // Pose wireframe overlay
                    PoseWireframeOverlay(
                        humanPoses: humanPoses,
                        animalPoses: animalPoses,
                        sourceSize: analysedSourceSize,
                        openAreaGlobal: openCameraArea
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
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .global)
                            } action: { newValue in
                                openCameraArea = newValue
                            }

                        // Chips, live text and the experimental caption, in one compact card.
                        detailsCard

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
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: DSSpacing.xs) {
                            Text("Vision Capture")
                                .font(.headline)
                            experimentalBadge
                        }
                        .accessibilityElement(children: .combine)
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
                // Objects are gated instead where they are produced: `CameraManager.classify` names a box
                // only when Vision's high-precision filter passes (`hasMinimumRecall(0.01, forPrecision: 0.9)`)
                // and the name is not a parent or scene word (`ObjectLabelPolicy`, 5.8).
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
                        .foregroundStyle(.white)
                        .padding(DSSpacing.md)
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
            .padding(DSSpacing.lg)
        }

        // MARK: - Live Metrics HUD

        private var metricsHUD: some View {
            VStack(spacing: DSSpacing.sm) {
                // Top row: FPS, Aesthetics, Confidence
                HStack(spacing: DSSpacing.lg) {
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
                        color: .accentColor
                    )
                }

                // Second row: Detection counts by type
                HStack(spacing: DSSpacing.md) {
                    ForEach(RegionType.allCases.filter { $0 != .all }) { type in
                        let count = regionCounts[type] ?? 0
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: type.icon)
                                .font(.caption2)
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(count > 0 ? type.color : .secondary)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                }

                // Third row: Pose detection counts
                if !humanPoses.isEmpty || !animalPoses.isEmpty {
                    HStack(spacing: DSSpacing.lg) {
                        if !humanPoses.isEmpty {
                            HStack(spacing: DSSpacing.xs) {
                                Image(systemName: "figure.walk")
                                    .font(.caption2)
                                Text("\(humanPoses.count) skeleton\(humanPoses.count == 1 ? "" : "s")")
                                    .font(.caption.monospacedDigit())
                            }
                            .foregroundStyle(DSColors.accent)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(Capsule().fill(DSColors.chipBackground(for: DSColors.accent)))
                        }

                        if !animalPoses.isEmpty {
                            HStack(spacing: DSSpacing.xs) {
                                Image(systemName: "pawprint.fill")
                                    .font(.caption2)
                                Text("\(animalPoses.count) animal\(animalPoses.count == 1 ? "" : "s")")
                                    .font(.caption.monospacedDigit())
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(Capsule().fill(DSColors.chipBackground(for: .orange)))
                        }
                    }
                }

                // Confidence slider
                HStack(spacing: DSSpacing.sm) {
                    Text("Min Confidence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $confidenceThreshold, in: 0.1...0.9, step: 0.1)
                        .tint(.white)
                        .accessibilityLabel("Min Confidence")
                        .accessibilityValue("\(Int((confidenceThreshold * 100).rounded()))%")
                }
                .padding(.horizontal, DSSpacing.lg)
            }
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, DSSpacing.lg)
        }

        // MARK: - Experimental badge

        /// The screen's honesty marker, in the same chip shape the app uses elsewhere.
        private var experimentalBadge: some View {
            Text("Experimental")
                .font(DSTypography.chip)
                .foregroundStyle(DSColors.warning)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xxs)
                .background(Capsule().fill(DSColors.chipBackground(for: DSColors.warning)))
                .accessibilityLabel("Experimental feature")
        }

        // MARK: - Details card

        /// Chips, live text and the caption, in one card.
        ///
        /// **What was wrong before (2026-11-10).** A labels card (two headed chip groups that wrap
        /// onto several lines, plus face and person counts) and a separate Live Text card (five
        /// lines and a character count) stacked above the shutter covered about a third of the
        /// camera view on the owner's iPhone 16 Pro Max. Now every chip group is one line that
        /// scrolls sideways, live text is at most two lines, and the whole card folds down to
        /// its caption with the chevron.
        private var detailsCard: some View {
            let faceCount = regionCounts[.face] ?? 0
            let humanCount = regionCounts[.human] ?? 0
            let showsText = !liveOCRText.isEmpty && (selectedRegionType == .all || selectedRegionType == .text)
            let hasChips = !sceneLabels.isEmpty || !detectedObjects.isEmpty || faceCount > 0 || humanCount > 0

            return VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Button {
                    withAnimation(DSAnimations.snappySpring) { detailsExpanded.toggle() }
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "info.circle")
                        Text("Labels are the device's best guess and may be wrong.")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: DSSpacing.xs)
                        Image(systemName: detailsExpanded ? "chevron.down" : "chevron.up")
                    }
                    .font(DSTypography.meta)
                    .foregroundStyle(.white.opacity(0.85))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Labels are the device's best guess and may be wrong.")
                .accessibilityHint(
                    detailsExpanded ? "Hides the labels and live text" : "Shows the labels and live text")

                if detailsExpanded {
                    if hasChips {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DSSpacing.xs) {
                                ForEach(sceneLabels.prefix(3), id: \.self) { label in
                                    detailChip(label, systemImage: "photo", color: DSColors.accent)
                                }
                                ForEach(detectedObjects.prefix(6), id: \.self) { label in
                                    detailChip(label, systemImage: "cube", color: .orange)
                                }
                                if faceCount > 0 {
                                    detailChip(
                                        "\(faceCount) face\(faceCount == 1 ? "" : "s")",
                                        systemImage: "face.smiling", color: DSColors.accent)
                                }
                                if humanCount > 0 {
                                    detailChip(
                                        "\(humanCount) person\(humanCount == 1 ? "" : "s")",
                                        systemImage: "figure.stand", color: .green)
                                }
                            }
                        }
                    }

                    if showsText {
                        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                            Image(systemName: "text.viewfinder")
                                .font(DSTypography.meta)
                            Text(liveOCRText)
                                .font(DSTypography.code)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.white)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Live text: \(liveOCRText)")
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, DSSpacing.lg)
        }

        /// One chip in the details card. Scene chips describe the whole picture; object chips are
        /// the names of the boxes on screen.
        private func detailChip(_ text: String, systemImage: String, color: Color) -> some View {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: systemImage)
                Text(text)
                    .lineLimit(1)
            }
            .font(DSTypography.meta)
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xxs)
            .background(Capsule().fill(color.opacity(0.85)))
        }

        // MARK: - Bottom Capture Bar

        private var bottomCaptureBar: some View {
            HStack(spacing: DSSpacing.xxl) {
                // Quick capture (text only)
                Button {
                    captureTextOnly()
                } label: {
                    VStack(spacing: DSSpacing.xs) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.title2)
                        Text("Text")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
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
                    VStack(spacing: DSSpacing.xs) {
                        Image(systemName: "doc.richtext")
                            .font(.title2)
                        Text("Document")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(.vertical, DSSpacing.xl)
            .padding(.horizontal, DSSpacing.lg)
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
            // Only lines seen in most of the recent frames. A single frame's reading of blur is
            // what reached this panel, and the Text button, before (2026-11-10).
            liveOCRText = liveTextStabilizer.stableLines(from: analysis.textLines).joined(separator: " ")
            regionCounts = counts
            aestheticsScore = analysis.aestheticsScore

            withAnimation(DSAnimations.snappySpring) {
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
            case .table: return .accentColor
            case .document: return .orange
            case .barcode: return .accentColor
            case .object: return .orange
            case .scene: return .accentColor
            case .face: return .accentColor
            case .human: return .green
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

        /// True when the name came from classifying a crop of a salient region rather than from a
        /// detector that finds that kind of thing (faces, people, cats and dogs). Its confidence
        /// says how sure the classifier is about the crop, not that the box sits on the object, so
        /// the box does not print it.
        let isGuess: Bool

        init(
            id: UUID = UUID(),
            type: RegionType,
            boundingBox: CGRect,
            confidence: Float,
            preview: String? = nil,
            isGuess: Bool = false
        ) {
            self.id = id
            self.type = type
            self.boundingBox = boundingBox
            self.confidence = confidence
            self.preview = preview
            self.isGuess = isGuess
        }

        func withID(_ id: UUID) -> DetectedRegion {
            DetectedRegion(
                id: id,
                type: type,
                boundingBox: boundingBox,
                confidence: confidence,
                preview: preview,
                isGuess: isGuess
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

        /// The recognised lines that passed `LiveTextStabilizer.accepts`, in Vision's order. The
        /// overlay debounces these across frames before showing any of them.
        let textLines: [String]

        init(
            regions: [DetectedRegion],
            recognizedText: String,
            aestheticsScore: Float?,
            sceneLabels: [String],
            detectedObjects: [String],
            humanPoses: [DetectedPose],
            animalPoses: [DetectedPose],
            lensSmudgeDetected: Bool,
            sourceSize: CGSize = .zero,
            textLines: [String] = []
        ) {
            self.textLines = textLines
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

        /// Called once, when the preview layer first lands in a window. See
        /// `CameraManager.attachPreviewLayer`.
        var onLayerInWindow: (AVCaptureVideoPreviewLayer) -> Void = { _ in }

        func makeUIView(context: Context) -> CameraPreviewUIView {
            let view = CameraPreviewUIView()
            view.session = session
            view.onLayerInWindow = onLayerInWindow
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

        var onLayerInWindow: ((AVCaptureVideoPreviewLayer) -> Void)?
        private var reportedLayer = false

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

        /// The rotation coordinator reports 0 degrees for a layer that is not in a view hierarchy,
        /// so the layer is handed over here rather than at creation.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !reportedLayer else { return }
            reportedLayer = true
            onLayerInWindow?(previewLayer)
        }
    }

    // MARK: - Open camera area

    extension View {
        /// Clips an overlay drawn over the whole screen to the open camera area, given in global
        /// coordinates, so nothing it draws can sit on the navigation bar, the top controls or the
        /// bottom card. A zero area (not yet measured) leaves the overlay unclipped.
        func clippedToOpenArea(_ local: CGRect) -> some View {
            mask(alignment: .topLeading) {
                if local.width > 0, local.height > 0 {
                    Rectangle()
                        .frame(width: local.width, height: local.height)
                        .offset(x: local.minX, y: local.minY)
                } else {
                    Rectangle()
                }
            }
        }
    }

    /// The open camera area in an overlay's own coordinates.
    private func openArea(_ global: CGRect, in geometry: GeometryProxy) -> CGRect {
        let origin = geometry.frame(in: .global).origin
        guard global.width > 0, global.height > 0 else {
            return CGRect(origin: .zero, size: geometry.size)
        }
        return global.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: - Detection Overlay View

    struct DetectionOverlayView: View {
        let regions: [DetectedRegion]
        let selectedType: RegionType
        /// Pixel size of the analysed frame, threaded down to the box views.
        let sourceSize: CGSize
        /// The open camera area in global coordinates. See `clippedToOpenArea`.
        var openAreaGlobal: CGRect = .zero

        private var filteredRegions: [DetectedRegion] {
            if selectedType == .all {
                return regions
            }
            return regions.filter { $0.type == selectedType }
        }

        var body: some View {
            GeometryReader { geometry in
                let visible = openArea(openAreaGlobal, in: geometry)
                ZStack(alignment: .topLeading) {
                    ForEach(filteredRegions) { region in
                        // Faces get an oval, everything else a box.
                        //
                        // `.human` used to get `HumanSilhouetteOverlay`, which drew a mannequin from
                        // hardcoded fractions of the bounding box. None of that was measured, and
                        // the real pose is drawn beside it by `PoseWireframeOverlay` from measured
                        // joints. The box says where the person is; the wireframe says what they
                        // are doing.
                        switch region.type {
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
                                sourceSize: sourceSize,
                                visible: visible
                            )
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clippedToOpenArea(visible)
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
                    let faceColor = Color.accentColor

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
                    // anywhere in the app to place them. The oval stays, because the face rectangle
                    // IS measured and inscribing an ellipse in it claims nothing the rectangle does
                    // not.

                    // Draw glow layer
                    context.fill(facePath, with: .color(faceColor.opacity(0.15)))

                    // Draw strokes
                    context.stroke(facePath, with: .color(faceColor), style: StrokeStyle(lineWidth: 2.5))
                }
                .shadow(color: Color.accentColor.opacity(0.6), radius: 6)

                // Label. The overlay's open-area mask keeps it off the navigation bar.
                Text("Face")
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                    .position(x: frame.midX, y: frame.minY - 14)
            }
        }
    }

    // MARK: - Region Bounding Box

    struct RegionBoundingBox: View {
        let region: DetectedRegion
        let containerSize: CGSize
        /// Pixel size of the analysed frame, so the aspect-fill crop can be undone.
        let sourceSize: CGSize
        /// The open camera area in this overlay's coordinates.
        let visible: CGRect

        /// Measured each layout so the label's placement knows its real size.
        @State private var labelSize = CGSize(width: 90, height: 20)

        /// The detection in overlay coordinates. May extend past the screen, which is correct:
        /// the preview crops the picture. See `CameraOverlayGeometry.viewRect`.
        private var fullFrame: CGRect {
            CameraOverlayGeometry.viewRect(
                normalized: region.boundingBox,
                sourceSize: sourceSize,
                viewSize: containerSize
            )
        }

        /// The part of it that is drawn: inside the open camera area, or nothing.
        private var frame: CGRect? {
            CameraOverlayGeometry.clippedRect(fullFrame, to: visible)
        }

        private var cornerRadius: CGFloat {
            DSCorners.chip
        }

        /// A percentage only where it measures the detection: a face, a person, a cat or a dog
        /// found by a detector for that kind of thing. Not on crop guesses (see
        /// `DetectedRegion.isGuess`), not on documents, and not on text, whose fast-mode
        /// confidence is a coarse constant.
        private var showsConfidence: Bool {
            guard region.confidence > 0, !region.isGuess else { return false }
            switch region.type {
            case .face, .human, .object: return true
            default: return false
            }
        }

        var body: some View {
            if let frame {
                ZStack(alignment: .topLeading) {
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
                        .animation(DSAnimations.snappySpring, value: frame)

                    // Type label.
                    //
                    // **Text regions get no label.** A page of printed text produced one capsule
                    // per recognised line, all stacked on each other. The box already says where
                    // the line is and the details card says what it says.
                    if region.type != .text {
                        let offset = CameraOverlayGeometry.labelOffset(
                            box: frame, visible: visible, labelSize: labelSize
                        )
                        boxLabel
                            .fixedSize()
                            .onGeometryChange(for: CGSize.self) { proxy in
                                proxy.size
                            } action: { newValue in
                                labelSize = newValue
                            }
                            .offset(x: offset.x, y: offset.y)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            }
        }

        private var boxLabel: some View {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: region.type.icon)
                    .scaledFont(size: 10, weight: .bold)

                if let preview = region.preview {
                    Text(preview.prefix(18))
                        .scaledFont(size: 10, weight: .medium)
                        .lineLimit(1)
                }

                if showsConfidence {
                    Text(String(format: "%.0f%%", region.confidence * 100))
                        .scaledFont(size: 9, weight: .bold)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule()
                    .fill(region.type.color.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            )
        }
    }

    // MARK: - Pose Wireframe Overlay

    struct PoseWireframeOverlay: View {
        let humanPoses: [DetectedPose]
        let animalPoses: [DetectedPose]
        /// Pixel size of the analysed frame, threaded down to the wireframes.
        let sourceSize: CGSize
        /// The open camera area in global coordinates. See `clippedToOpenArea`.
        var openAreaGlobal: CGRect = .zero

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Draw human wireframes
                    ForEach(humanPoses) { pose in
                        HumanWireframe(pose: pose, containerSize: geometry.size, sourceSize: sourceSize)
                    }

                    // Draw animal wireframes
                    ForEach(animalPoses) { pose in
                        AnimalWireframe(pose: pose, containerSize: geometry.size, sourceSize: sourceSize)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clippedToOpenArea(openArea(openAreaGlobal, in: geometry))
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
        private let boneColor = Color.accentColor  // Main skeleton
        private let jointColor = Color.white  // Joint nodes
        private let spineColor = Color.accentColor.opacity(0.9)  // Spine emphasis
        private let glowColor = Color.accentColor.opacity(0.5)

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
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
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
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
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
                VStack(spacing: DSSpacing.lg) {
                    // Preview
                    if let image = result.image {
                        Image(decorative: image, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                    }

                    // Stats
                    HStack(spacing: DSSpacing.lg) {
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
                        .padding(.horizontal, DSSpacing.lg)

                    // Container selector
                    HStack {
                        Text("Add to:")
                            .foregroundStyle(.secondary)

                        Text(containerService.activeContainer?.name ?? "Default Library")
                            .fontWeight(.medium)

                        Spacer()
                    }
                    .padding(.horizontal, DSSpacing.lg)

                    // Text preview
                    GroupBox("Captured Text") {
                        ScrollView {
                            Text(result.recognizedText.prefix(500))
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding(.horizontal, DSSpacing.lg)

                    Spacer()
                }
                .padding(.top, DSSpacing.lg)
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
            VStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(DSColors.accent)

                Text(value)
                    .font(.headline)
                    .monospacedDigit()

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 0) {
                    Text(value)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                    Text(label)
                        .scaledFont(size: 8)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
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

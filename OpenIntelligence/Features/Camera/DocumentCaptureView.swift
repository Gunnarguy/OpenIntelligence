//
//  DocumentCaptureView.swift
//  OpenIntelligence
//
//  Smart capture using Apple Vision - understands documents AND photos.
//  Philosophy: Simple UI, intelligent analysis behind the scenes.
//

#if os(iOS)
import AVFoundation
import Combine
import SwiftUI
import Vision

// MARK: - Smart Capture View

/// Intelligent capture that understands context - documents, photos, objects, scenes
struct DocumentCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService

    @StateObject private var captureManager = SmartCaptureManager()
    @State private var showConfirmation = false
    @State private var captureResult: SmartCaptureResult?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                CameraPreview(session: captureManager.session)
                    .ignoresSafeArea()

                // Context-aware overlay
                SmartOverlay(
                    captureMode: captureManager.detectedMode,
                    documentBounds: captureManager.documentBounds,
                    isStable: captureManager.isStable
                )
                .ignoresSafeArea()

                // Bottom controls
                VStack {
                    Spacer()

                    // Mode indicator
                    ModeIndicator(mode: captureManager.detectedMode)
                        .padding(.bottom, 12)

                    // Live preview (subtle)
                    if !captureManager.livePreview.isEmpty {
                        LivePreviewBadge(text: captureManager.livePreview)
                    }

                    // Capture button
                    CaptureButton(
                        isReady: captureManager.isStable || captureManager.detectedMode == .photo,
                        isProcessing: isProcessing
                    ) {
                        capture()
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Smart Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                captureManager.start()
            }
            .onDisappear {
                captureManager.stop()
            }
            .sheet(isPresented: $showConfirmation) {
                if let result = captureResult {
                    SmartCaptureConfirmation(
                        result: result,
                        containerName: containerService.activeContainer?.name ?? "Library",
                        onConfirm: { ingest(result) },
                        onRetake: { showConfirmation = false }
                    )
                }
            }
        }
    }

    private func capture() {
        isProcessing = true

        Task {
            do {
                let result = try await captureManager.capture()
                await MainActor.run {
                    captureResult = result
                    isProcessing = false
                    showConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                }
                Log.error("[SmartCapture] Capture failed: \(error)", category: .ingestion)
            }
        }
    }

    private func ingest(_ result: SmartCaptureResult) {
        Task {
            do {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let timestamp = dateFormatter.string(from: result.timestamp)
                let baseName = result.mode == .photo
                    ? (result.sceneLabels.first?.replacingOccurrences(of: " ", with: "_").lowercased() ?? "photo")
                    : result.mode.rawValue.lowercased()

                // Create a rich text document with ALL the AI understanding
                // This is what becomes searchable in RAG
                var documentContent = """
                # \(baseName.capitalized) Capture - \(timestamp)

                ## AI Understanding
                \(result.description)

                """

                if !result.sceneLabels.isEmpty {
                    documentContent += """

                ## Scene Classification
                \(result.sceneLabels.joined(separator: ", "))

                """
                }

                if !result.detectedObjects.isEmpty {
                    documentContent += """

                ## Detected Objects
                \(result.detectedObjects.joined(separator: ", "))

                """
                }

                if !result.extractedText.isEmpty {
                    documentContent += """

                ## Extracted Text
                \(result.extractedText)

                """
                }

                // Add capture metadata
                documentContent += """

                ---
                *Captured: \(result.timestamp.formatted())*
                *Mode: \(result.mode.rawValue)*
                """

                // Save as markdown file (this gets chunked and embedded properly)
                let textFilename = "\(baseName)_\(timestamp).md"
                let textURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(textFilename)
                try documentContent.write(to: textURL, atomically: true, encoding: .utf8)

                // Ingest the rich text document
                _ = await ragService.ingestDocuments(
                    [textURL],
                    context: .userInitiated
                )

                // Also save the image for reference (optional - if you want image in library too)
                if result.mode == .photo || !result.extractedText.isEmpty {
                    let imageFilename = "\(baseName)_\(timestamp).jpg"
                    let imageURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(imageFilename)

                    let uiImage = UIImage(cgImage: result.image)
                    if let data = uiImage.jpegData(compressionQuality: 0.9) {
                        try data.write(to: imageURL)

                        // Ingest image too (will get OCR'd and analyzed by DocumentProcessor)
                        _ = await ragService.ingestDocuments(
                            [imageURL],
                            context: .userInitiated
                        )

                        try? FileManager.default.removeItem(at: imageURL)
                    }
                }

                // Clean up
                try? FileManager.default.removeItem(at: textURL)

                await MainActor.run {
                    dismiss()
                }
            } catch {
                Log.error("[SmartCapture] Ingest failed: \(error)", category: .ingestion)
            }
        }
    }
}

// MARK: - Capture Mode

enum CaptureMode: String {
    case document = "Document"
    case photo = "Photo"
    case text = "Text"
    case product = "Product"

    var icon: String {
        switch self {
        case .document: return "doc.viewfinder"
        case .photo: return "camera.viewfinder"
        case .text: return "text.viewfinder"
        case .product: return "barcode.viewfinder"
        }
    }

    var color: Color {
        switch self {
        case .document: return .blue
        case .photo: return .orange
        case .text: return .green
        case .product: return .purple
        }
    }
}

// MARK: - Smart Capture Result

struct SmartCaptureResult {
    let image: CGImage
    let mode: CaptureMode
    let extractedText: String
    let description: String           // AI-generated description
    let sceneLabels: [String]         // What the image shows
    let detectedObjects: [String]     // Specific objects/animals/products
    let timestamp: Date

    var suggestedFilename: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: self.timestamp)

        switch mode {
        case .document:
            return "document_\(timestamp).jpg"
        case .text:
            return "text_\(timestamp).jpg"
        case .product:
            return "product_\(timestamp).jpg"
        case .photo:
            let primaryLabel = sceneLabels.first?.replacingOccurrences(of: " ", with: "_").lowercased() ?? "photo"
            return "\(primaryLabel)_\(timestamp).jpg"
        }
    }

    /// Rich context for RAG ingestion
    var contextForRAG: String {
        var parts: [String] = []

        // Description
        if !description.isEmpty {
            parts.append(description)
        }

        // Scene context
        if !sceneLabels.isEmpty {
            parts.append("Scene: \(sceneLabels.joined(separator: ", "))")
        }

        // Objects
        if !detectedObjects.isEmpty {
            parts.append("Contains: \(detectedObjects.joined(separator: ", "))")
        }

        // Extracted text
        if !extractedText.isEmpty {
            parts.append("Text content: \(extractedText)")
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Smart Capture Manager

@MainActor
class SmartCaptureManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var detectedMode: CaptureMode = .photo
    @Published var documentBounds: CGRect?
    @Published var isStable = false
    @Published var livePreview: String = ""

    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private let analysisQueue = DispatchQueue(label: "com.openintelligence.smartCapture", qos: .userInteractive)

    // Stability tracking
    private var lastBounds: CGRect?
    private var stabilityFrames = 0
    private let stabilityThreshold = 5

    // Rate limiting
    private var lastAnalysis: Date = .distantPast
    private let analysisInterval: TimeInterval = 0.15  // ~7 FPS

    // Capture continuation
    private var captureContinuation: CheckedContinuation<SmartCaptureResult, Error>?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput

        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        self.photoOutput = photoOutput

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        Task.detached { [session] in
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        Task.detached { [session] in
            session.stopRunning()
        }
    }

    func capture() async throws -> SmartCaptureResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation

            guard let photoOutput = self.photoOutput else {
                continuation.resume(throwing: CaptureError.notReady)
                return
            }

            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Live Analysis

    private func analyzeFrame(_ image: CGImage) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= analysisInterval else { return }
        lastAnalysis = now

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        // Document detection
        let documentRequest = VNDetectDocumentSegmentationRequest()

        // Fast text recognition
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        // Barcode detection (for products)
        let barcodeRequest = VNDetectBarcodesRequest()

        // Limit concurrent Vision requests to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            do {
                try handler.perform([documentRequest, textRequest, barcodeRequest])
            } catch {
                Log.debug("Vision request failed: \(error)", category: .pipeline)
            }
        }

        let docBounds = (documentRequest.results?.first as? VNRectangleObservation)?.boundingBox
        let docConfidence = (documentRequest.results?.first as? VNRectangleObservation)?.confidence ?? 0

        let textResults = textRequest.results ?? []
        let textCount = textResults.count
        let previewText = textResults
            .prefix(3)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .prefix(60)

        let hasBarcodes = !(barcodeRequest.results?.isEmpty ?? true)

        // Determine mode based on what we see
        let mode: CaptureMode
        if hasBarcodes {
            mode = .product
        } else if let bounds = docBounds, docConfidence > 0.7, bounds.width * bounds.height > 0.25 {
            mode = .document
        } else if textCount > 5 {
            mode = .text
        } else {
            mode = .photo
        }

        // Check stability for documents
        let stable = mode == .document ? checkStability(newBounds: docBounds) : true

        DispatchQueue.main.async {
            self.detectedMode = mode
            self.documentBounds = mode == .document ? docBounds : nil
            self.isStable = stable
            self.livePreview = String(previewText)
        }
    }

    private func checkStability(newBounds: CGRect?) -> Bool {
        guard let newBounds = newBounds, let lastBounds = lastBounds else {
            self.lastBounds = newBounds
            stabilityFrames = 0
            return false
        }

        let threshold: CGFloat = 0.02
        let isStable = abs(newBounds.minX - lastBounds.minX) < threshold &&
                       abs(newBounds.minY - lastBounds.minY) < threshold &&
                       abs(newBounds.width - lastBounds.width) < threshold &&
                       abs(newBounds.height - lastBounds.height) < threshold

        if isStable {
            stabilityFrames += 1
        } else {
            stabilityFrames = 0
        }

        self.lastBounds = newBounds
        return stabilityFrames >= stabilityThreshold
    }

    // MARK: - Full Analysis

    private func performFullAnalysis(on image: CGImage, mode: CaptureMode) async -> SmartCaptureResult {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        var extractedText = ""
        var sceneLabels: [String] = []
        var detectedObjects: [String] = []

        // YOLO object detection (80 COCO classes with bounding boxes)
        let yoloObjects = await YOLODetectionService.shared.detectObjects(in: image, confidenceThreshold: 0.4)
        for obj in yoloObjects {
            detectedObjects.append(obj.label)
        }

        // Accurate text recognition
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true

        // Scene classification for context (indoor/outdoor, etc.)
        let classifyRequest = VNClassifyImageRequest()

        // Animal/object recognition with breeds (complements YOLO)
        let animalRequest = VNRecognizeAnimalsRequest()

        // Limit concurrent Vision requests to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            do {
                try handler.perform([textRequest, classifyRequest, animalRequest])
            } catch {
                Log.error("[SmartCapture] Analysis failed: \(error)", category: .ingestion)
            }
        }

        // Extract text
        extractedText = (textRequest.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        // Scene labels (top classifications) - for context like "outdoor", "kitchen", etc.
        let classifications = classifyRequest.results ?? []
        for classification in classifications.prefix(5) where classification.confidence > 0.15 {
            let label = Self.formatLabel(classification.identifier)
            let category = Self.categorize(classification.identifier)

            // Only add scene context, objects come from YOLO
            if category == .scene {
                sceneLabels.append(label)
            } else if !detectedObjects.contains(label) {
                // Add if YOLO didn't already detect it
                detectedObjects.append(label)
            }
        }

        // Animal breeds (more specific than YOLO's generic "dog"/"cat")
        for observation in animalRequest.results ?? [] {
            let labels = observation.labels
                .filter { $0.confidence > 0.3 }
                .prefix(2)
                .map { Self.formatLabel($0.identifier) }

            for label in labels {
                if !detectedObjects.contains(label) {
                    detectedObjects.append(label)
                }
            }
        }

        // Generate natural language description
        let description = generateDescription(
            mode: mode,
            sceneLabels: sceneLabels,
            objects: detectedObjects,
            hasText: !extractedText.isEmpty
        )

        return SmartCaptureResult(
            image: image,
            mode: mode,
            extractedText: extractedText,
            description: description,
            sceneLabels: sceneLabels,
            detectedObjects: detectedObjects,
            timestamp: Date()
        )
    }

    private func generateDescription(
        mode: CaptureMode,
        sceneLabels: [String],
        objects: [String],
        hasText: Bool
    ) -> String {
        var parts: [String] = []

        switch mode {
        case .document:
            parts.append("A scanned document")
            if hasText {
                parts.append("containing text content")
            }

        case .text:
            parts.append("An image with text")

        case .product:
            parts.append("A product")
            if let firstObject = objects.first {
                parts.append("identified as \(firstObject)")
            }

        case .photo:
            if let primary = sceneLabels.first {
                parts.append("A photo of \(primary.lowercased())")
            } else {
                parts.append("A photograph")
            }

            if !objects.isEmpty {
                parts.append("featuring \(objects.joined(separator: ", "))")
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func formatLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private enum Category { case animal, plant, food, electronics, scene }

    private static func categorize(_ identifier: String) -> Category {
        let id = identifier.lowercased()

        // Animals
        let animalKeywords = ["dog", "cat", "bird", "fish", "horse", "cow", "sheep", "lion", "tiger",
                              "bear", "elephant", "monkey", "rabbit", "hamster", "turtle", "snake",
                              "retriever", "shepherd", "terrier", "poodle", "bulldog", "beagle",
                              "siamese", "persian", "tabby", "maine coon"]
        if animalKeywords.contains(where: { id.contains($0) }) { return .animal }

        // Plants
        let plantKeywords = ["flower", "tree", "plant", "rose", "daisy", "tulip", "sunflower",
                             "cactus", "fern", "palm", "oak", "pine", "maple"]
        if plantKeywords.contains(where: { id.contains($0) }) { return .plant }

        // Food
        let foodKeywords = ["food", "pizza", "burger", "sandwich", "salad", "cake", "coffee",
                            "wine", "beer", "fruit", "apple", "banana", "orange"]
        if foodKeywords.contains(where: { id.contains($0) }) { return .food }

        // Electronics
        let electronicsKeywords = ["phone", "laptop", "computer", "screen", "monitor", "keyboard",
                                   "mouse", "tablet", "watch", "camera", "television"]
        if electronicsKeywords.contains(where: { id.contains($0) }) { return .electronics }

        return .scene
    }

    enum CaptureError: Error {
        case notReady
        case photoFailed
    }
}

// MARK: - Delegates

extension SmartCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Create a sendable representation
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return }
        Task { @MainActor in
            self.analyzeFrame(cgImage)
        }
    }
}

extension SmartCaptureManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                captureContinuation?.resume(throwing: error)
                captureContinuation = nil
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                captureContinuation?.resume(throwing: CaptureError.photoFailed)
                captureContinuation = nil
                return
            }

            let currentMode = self.detectedMode
            let result = await performFullAnalysis(on: cgImage, mode: currentMode)

            captureContinuation?.resume(returning: result)
            captureContinuation = nil
        }
    }
}

// MARK: - UI Components

struct SmartOverlay: View {
    let captureMode: CaptureMode
    let documentBounds: CGRect?
    let isStable: Bool

    var body: some View {
        GeometryReader { geometry in
            if captureMode == .document, let bounds = documentBounds {
                // Document bounding box
                let frame = CGRect(
                    x: bounds.minX * geometry.size.width,
                    y: (1 - bounds.maxY) * geometry.size.height,
                    width: bounds.width * geometry.size.width,
                    height: bounds.height * geometry.size.height
                )

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isStable ? Color.green : Color.yellow,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .animation(.easeInOut(duration: 0.15), value: frame)
                    .shadow(color: (isStable ? Color.green : Color.yellow).opacity(0.5), radius: 8)

                // Corner accents
                DocumentCorners(frame: frame, color: isStable ? .green : .yellow)
            } else {
                // Simple center reticle for photos
                Image(systemName: "viewfinder")
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.5))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}

struct ModeIndicator: View {
    let mode: CaptureMode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: mode.icon)
            Text(mode.rawValue)
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(mode.color.opacity(0.8), in: Capsule())
        .animation(.easeInOut, value: mode)
    }
}

struct LivePreviewBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.viewfinder")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    class PreviewView: UIView {
        var session: AVCaptureSession? {
            didSet { previewLayer.session = session }
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

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}

struct DocumentCorners: View {
    let frame: CGRect
    let color: Color

    var body: some View {
        Canvas { context, _ in
            let corners: [(CGPoint, Double)] = [
                (CGPoint(x: frame.minX, y: frame.minY), 0),
                (CGPoint(x: frame.maxX, y: frame.minY), 90),
                (CGPoint(x: frame.maxX, y: frame.maxY), 180),
                (CGPoint(x: frame.minX, y: frame.maxY), 270)
            ]

            for (position, rotation) in corners {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: 20))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 0))

                context.translateBy(x: position.x, y: position.y)
                context.rotate(by: .degrees(rotation))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                context.rotate(by: .degrees(-rotation))
                context.translateBy(x: -position.x, y: -position.y)
            }
        }
    }
}

struct CaptureButton: View {
    let isReady: Bool
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(isProcessing ? Color.gray : (isReady ? Color.white : Color.white.opacity(0.5)))
                    .frame(width: 60, height: 60)

                if isProcessing {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .disabled(isProcessing)
        .scaleEffect(isReady ? 1.0 : 0.95)
        .animation(.spring(response: 0.3), value: isReady)
    }
}

struct SmartCaptureConfirmation: View {
    let result: SmartCaptureResult
    let containerName: String
    let onConfirm: () -> Void
    let onRetake: () -> Void

    @State private var isIngesting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Preview
                    Image(decorative: result.image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 280)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                        .padding(.horizontal)

                    // Mode badge
                    HStack(spacing: 8) {
                        Image(systemName: result.mode.icon)
                        Text(result.mode.rawValue)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(result.mode.color, in: Capsule())

                    // AI Description
                    if !result.description.isEmpty {
                        GroupBox {
                            Text(result.description)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("AI Understanding", systemImage: "sparkles")
                        }
                        .padding(.horizontal)
                    }

                    // Detected content
                    if !result.sceneLabels.isEmpty || !result.detectedObjects.isEmpty {
                        GroupBox {
                            CaptureFlowLayout(spacing: 8) {
                                ForEach(result.detectedObjects + result.sceneLabels, id: \.self) { label in
                                    Text(label)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.secondary.opacity(0.2), in: Capsule())
                                }
                            }
                        } label: {
                            Label("Detected", systemImage: "eye")
                        }
                        .padding(.horizontal)
                    }

                    // Extracted text
                    if !result.extractedText.isEmpty {
                        GroupBox {
                            Text(result.extractedText.prefix(400))
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Text (\(result.extractedText.split(separator: " ").count) words)", systemImage: "doc.text")
                        }
                        .padding(.horizontal)
                    }

                    // Library info
                    HStack {
                        Text("Adding to:")
                            .foregroundColor(.secondary)
                        Text(containerName)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Review Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake") { onRetake() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isIngesting = true
                        onConfirm()
                    } label: {
                        if isIngesting {
                            ProgressView()
                        } else {
                            Text("Add")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isIngesting)
                }
            }
        }
    }
}

// MARK: - Flow Layout (Capture View)

private struct CaptureFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    DocumentCaptureView(
        ragService: RAGService(),
        containerService: ContainerService()
    )
}
#endif

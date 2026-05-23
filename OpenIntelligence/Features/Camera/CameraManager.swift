//
//  CameraManager.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  Manages AVCaptureSession and real-time Vision framework analysis
//  for live camera preview with AR overlays.
//

#if os(iOS)
import AVFoundation
import Combine
import CoreImage
import UIKit
import Vision

// MARK: - Camera Manager

/// Manages camera capture session and real-time Vision analysis
@MainActor
class CameraManager: NSObject, ObservableObject {

    // MARK: - Properties

    let session = AVCaptureSession()

    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private let analysisQueue = DispatchQueue(label: "com.openintelligence.camera.analysis", qos: .userInteractive)
    private let captureQueue = DispatchQueue(label: "com.openintelligence.camera.capture", qos: .userInitiated)

    /// Callback for frame analysis results (runs on main thread)
    var onFrameAnalyzed: ((FrameAnalysis) -> Void)?

    /// Rate limiting for analysis
    private var lastAnalysisTime: Date = .distantPast
    private let analysisInterval: TimeInterval = 0.1 // 10 FPS max for analysis

    /// Pending capture continuation
    private var pendingCaptureContinuation: CheckedContinuation<CaptureResult, Error>?
    private var pendingDocumentContinuation: CheckedContinuation<CaptureResult, Error>?

    // Vision requests (reusable)
    private lazy var textRecognitionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE"]
        return request
    }()

    // MARK: - Initialization

    override init() {
        super.init()
        configureSession()
    }

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
        else {
            Log.error("[CameraManager] Failed to configure video input", category: .ingestion)
            session.commitConfiguration()
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        // Video output for real-time analysis
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput

        // Photo output for high-quality captures
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            // Use the maximum supported dimensions for this device
            // Query supported formats to avoid crash on devices with different max resolutions
            if let maxDimensions = photoOutput.maxPhotoQualityPrioritization == .quality
                ? videoDevice.activeFormat.supportedMaxPhotoDimensions.last
                : videoDevice.activeFormat.supportedMaxPhotoDimensions.first {
                photoOutput.maxPhotoDimensions = maxDimensions
                Log.info("[CameraManager] Photo dimensions set to \(maxDimensions.width)x\(maxDimensions.height)", category: .ingestion)
            }
        }
        self.photoOutput = photoOutput

        session.commitConfiguration()

        Log.info("[CameraManager] Camera session configured", category: .ingestion)
    }

    // MARK: - Session Control

    func startSession() {
        guard !session.isRunning else { return }

        let capturedSession = session
        Task.detached {
            capturedSession.startRunning()
            await MainActor.run {
                Log.info("[CameraManager] Camera session started", category: .ingestion)
            }
        }
    }

    func stopSession() {
        guard session.isRunning else { return }

        let capturedSession = session
        Task.detached {
            capturedSession.stopRunning()
            await MainActor.run {
                Log.info("[CameraManager] Camera session stopped", category: .ingestion)
            }
        }
    }

    func setFlash(_ enabled: Bool) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch
        else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            Log.warning("[CameraManager] Failed to set torch: \(error.localizedDescription)", category: .ingestion)
        }
    }

    // MARK: - Capture Methods

    /// Capture full frame with comprehensive Vision analysis
    func captureFullAnalysis() async throws -> CaptureResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingCaptureContinuation = continuation

            guard let photoOutput = self.photoOutput else {
                continuation.resume(throwing: CameraError.photoOutputNotAvailable)
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Capture with structured document parsing
    func captureDocumentStructure() async throws -> CaptureResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingDocumentContinuation = continuation

            guard let photoOutput = self.photoOutput else {
                continuation.resume(throwing: CameraError.photoOutputNotAvailable)
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Vision Analysis

    /// Perform real-time analysis on a video frame
    private func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        // Rate limiting
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= analysisInterval else { return }
        lastAnalysisTime = now

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        var regions: [DetectedRegion] = []
        var recognizedText = ""
        var aestheticsScore: Float?
        var sceneLabels: [String] = []
        var detectedObjects: [String] = []
        var humanPoses: [DetectedPose] = []
        var animalPoses: [DetectedPose] = []

        // 1. Text Recognition
        let textRequest = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            for observation in observations {
                if let text = observation.topCandidates(1).first?.string {
                    recognizedText += text + " "

                    regions.append(DetectedRegion(
                        type: .text,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        preview: String(text.prefix(30))
                    ))
                }
            }
        }
        textRequest.recognitionLevel = .fast
        textRequest.minimumTextHeight = 0.02

        // 2. Document Detection
        let documentRequest = VNDetectDocumentSegmentationRequest { request, error in
            guard let observation = request.results?.first as? VNRectangleObservation else { return }

            regions.append(DetectedRegion(
                type: .document,
                boundingBox: observation.boundingBox,
                confidence: observation.confidence,
                preview: nil
            ))
        }

        // 3. Barcode Detection
        let barcodeRequest = VNDetectBarcodesRequest { request, error in
            guard let observations = request.results as? [VNBarcodeObservation] else { return }

            for observation in observations {
                regions.append(DetectedRegion(
                    type: .barcode,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: observation.payloadStringValue
                ))
            }
        }

        // 4. Scene Classification - EXTENSIVE taxonomy with 400+ categories
        // Includes: dog breeds, cat breeds, plant species, vehicles, electronics, food, etc.
        let classifyRequest = VNClassifyImageRequest { request, error in
            guard let observations = request.results as? [VNClassificationObservation] else { return }

            // Get top classifications by confidence - more permissive threshold for specifics
            // Apple's taxonomy includes: German Shepherd, Labrador, Rose, Sunflower, etc.
            let topClassifications = observations
                .filter { $0.confidence > 0.15 }  // Lower threshold to catch specific breeds
                .prefix(8)  // Get more categories for detailed info

            for classification in topClassifications {
                // Clean up the identifier for display
                let rawLabel = classification.identifier
                let label = Self.formatClassificationLabel(rawLabel)

                // Categorize the detection for the UI
                let category = Self.categorizeLabel(rawLabel)

                if category == .animal {
                    detectedObjects.append(label)
                } else if category == .plant {
                    detectedObjects.append("🌿 \(label)")
                } else if category == .electronics {
                    detectedObjects.append("📱 \(label)")
                } else if category == .vehicle {
                    detectedObjects.append("🚗 \(label)")
                } else if category == .food {
                    detectedObjects.append("🍽️ \(label)")
                } else {
                    sceneLabels.append(label)
                }

                regions.append(DetectedRegion(
                    type: category == .scene ? .scene : .object,
                    boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                    confidence: classification.confidence,
                    preview: label
                ))
            }
        }

        // 5. Animal/Object Detection with BREED specifics
        // VNRecognizeAnimalsRequest returns dog/cat BREEDS on iOS 17+
        let animalRequest = VNRecognizeAnimalsRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }

            for observation in observations {
                // Get ALL labels - not just the first one!
                // This includes breed info like "Golden Retriever", "Siamese Cat"
                let allLabels = observation.labels
                    .filter { $0.confidence > 0.2 }
                    .prefix(3)
                    .map { Self.formatClassificationLabel($0.identifier) }

                let primaryLabel = allLabels.first ?? "Animal"
                let fullLabel = allLabels.joined(separator: " • ")

                detectedObjects.append("🐾 \(fullLabel)")
                regions.append(DetectedRegion(
                    type: .object,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: primaryLabel
                ))
            }
        }

        // 6. Face Detection
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            guard let observations = request.results as? [VNFaceObservation] else { return }

            for observation in observations {
                regions.append(DetectedRegion(
                    type: .face,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: "Face"
                ))
            }
        }

        // 7. Human Body Detection
        let humanRequest = VNDetectHumanRectanglesRequest { request, error in
            guard let observations = request.results as? [VNHumanObservation] else { return }

            for observation in observations {
                regions.append(DetectedRegion(
                    type: .human,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: "Person"
                ))
            }
        }

        // 8. Human Body Pose Detection
        let humanPoseRequest = VNDetectHumanBodyPoseRequest { request, error in
            guard let observations = request.results as? [VNHumanBodyPoseObservation] else { return }

            for observation in observations {
                if let pose = Self.createHumanPose(from: observation) {
                    humanPoses.append(pose)
                }
            }
        }

        // 9. Animal Body Pose Detection
        let animalPoseRequest = VNDetectAnimalBodyPoseRequest { request, error in
            guard let observations = request.results as? [VNAnimalBodyPoseObservation] else { return }

            for observation in observations {
                if let pose = Self.createAnimalPose(from: observation) {
                    animalPoses.append(pose)
                }
            }
        }

        // 10. Aesthetics Score (iOS 18+)
        if #available(iOS 18.0, *) {
            let aestheticsRequest = VNCalculateImageAestheticsScoresRequest { request, error in
                guard let observation = request.results?.first as? VNImageAestheticsScoresObservation else { return }
                aestheticsScore = observation.overallScore
            }

            // Limit concurrent Vision requests to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([textRequest, documentRequest, barcodeRequest, classifyRequest, animalRequest, faceRequest, humanRequest, humanPoseRequest, animalPoseRequest, aestheticsRequest])
                } catch {
                    Log.debug("[CameraManager] Frame analysis failed: \(error.localizedDescription)", category: .ingestion)
                }
            }
        } else {
            // Limit concurrent Vision requests to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([textRequest, documentRequest, barcodeRequest, classifyRequest, animalRequest, faceRequest, humanRequest, humanPoseRequest, animalPoseRequest])
                } catch {
                    Log.debug("[CameraManager] Frame analysis failed: \(error.localizedDescription)", category: .ingestion)
                }
            }
        }

        // Dispatch results to main thread
        let analysis = FrameAnalysis(
            regions: regions,
            recognizedText: recognizedText.trimmingCharacters(in: .whitespacesAndNewlines),
            aestheticsScore: aestheticsScore,
            sceneLabels: sceneLabels,
            detectedObjects: detectedObjects,
            humanPoses: humanPoses,
            animalPoses: animalPoses,
            lensSmudgeDetected: false // Smudge detection only in full frame analysis
        )

        DispatchQueue.main.async { [weak self] in
            self?.onFrameAnalyzed?(analysis)
        }
    }

    /// Perform comprehensive analysis on a captured image
    private func analyzeCapture(_ image: CGImage, isDocumentCapture: Bool) async -> CaptureResult {
        let ciImage = CIImage(cgImage: image)
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        var recognizedText = ""
        var structuredElements: [StructuredCaptureElement] = []
        var sceneLabels: [String] = []
        var detectedObjects: [String] = []

        // High-quality text recognition
        let textRequest = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            // Sort by reading order
            let sorted = observations.sorted { obs1, obs2 in
                let box1 = obs1.boundingBox
                let box2 = obs2.boundingBox
                let lineThreshold: CGFloat = 0.02

                if abs(box1.midY - box2.midY) > lineThreshold {
                    return box1.midY > box2.midY
                }
                return box1.minX < box2.minX
            }

            recognizedText = sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        textRequest.minimumTextHeight = 0.005

        // Scene/Image Classification - EXTENSIVE with breeds, species, electronics
        let classifyRequest = VNClassifyImageRequest { request, error in
            guard let observations = request.results as? [VNClassificationObservation] else { return }

            // Get top classifications - use lower threshold for specifics like breeds
            let topClassifications = observations
                .filter { $0.confidence > 0.15 }
                .prefix(10)

            for classification in topClassifications {
                let formatted = Self.formatClassificationLabel(classification.identifier)
                let category = Self.categorizeLabel(classification.identifier)

                // Add emoji prefixes based on category
                switch category {
                case .animal:
                    detectedObjects.append("🐾 \(formatted)")
                case .plant:
                    detectedObjects.append("🌿 \(formatted)")
                case .electronics:
                    detectedObjects.append("📱 \(formatted)")
                case .vehicle:
                    detectedObjects.append("🚗 \(formatted)")
                case .food:
                    detectedObjects.append("🍽️ \(formatted)")
                default:
                    sceneLabels.append(formatted)
                }
            }
        }

        // Animal/Object Detection with BREED specifics
        let animalRequest = VNRecognizeAnimalsRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }

            for observation in observations {
                // Get ALL labels including specific breeds
                let labels = observation.labels
                    .filter { $0.confidence > 0.2 }
                    .prefix(3)
                    .map { Self.formatClassificationLabel($0.identifier) }

                if !labels.isEmpty {
                    detectedObjects.append("🐾 \(labels.joined(separator: " • "))")
                }
            }
        }

        // Document structure detection
        if isDocumentCapture {
            let documentRequest = VNDetectDocumentSegmentationRequest { request, error in
                guard let observation = request.results?.first as? VNRectangleObservation else { return }

                // Add document structure element
                structuredElements.append(StructuredCaptureElement(
                    type: .paragraph,
                    content: recognizedText,
                    boundingBox: observation.boundingBox
                ))
            }

            // Limit concurrent Vision requests to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([textRequest, documentRequest, classifyRequest, animalRequest])
                } catch {
                    Log.error("[CameraManager] Capture analysis failed: \(error.localizedDescription)", category: .ingestion)
                }
            }
        } else {
            // Limit concurrent Vision requests to prevent Metal race conditions
            VisionOCRThrottle.performSync {
                do {
                    try requestHandler.perform([textRequest, classifyRequest, animalRequest])
                } catch {
                    Log.error("[CameraManager] Capture analysis failed: \(error.localizedDescription)", category: .ingestion)
                }
            }
        }

        // Generate natural language image description
        let imageDescription = generateImageDescription(
            sceneLabels: sceneLabels,
            detectedObjects: detectedObjects,
            hasText: !recognizedText.isEmpty
        )

        return CaptureResult(
            captureType: isDocumentCapture ? .structuredDocument : .fullImage,
            recognizedText: recognizedText,
            structuredElements: structuredElements,
            image: image,
            timestamp: Date(),
            imageDescription: imageDescription,
            sceneLabels: sceneLabels,
            detectedObjects: detectedObjects
        )
    }

    /// Generate a natural language description of the image
    private func generateImageDescription(
        sceneLabels: [String],
        detectedObjects: [String],
        hasText: Bool
    ) -> String {
        var parts: [String] = []

        // Primary scene
        if let primaryScene = sceneLabels.first {
            parts.append("Image of \(primaryScene.lowercased())")
        }

        // Secondary scenes
        if sceneLabels.count > 1 {
            let secondaryScenes = sceneLabels.dropFirst().prefix(2).map { $0.lowercased() }
            parts.append("showing \(secondaryScenes.joined(separator: " and "))")
        }

        // Detected objects
        if !detectedObjects.isEmpty {
            let objectList = detectedObjects.prefix(3).map { $0.lowercased() }
            if objectList.count == 1 {
                parts.append("containing a \(objectList[0])")
            } else if let lastObject = objectList.last {
                let otherObjects = objectList.dropLast().joined(separator: ", ")
                parts.append("containing \(otherObjects) and \(lastObject)")
            }
        }

        // Note text presence
        if hasText {
            parts.append("with visible text")
        }

        if parts.isEmpty {
            return "Captured image"
        }

        return parts.joined(separator: " ") + "."
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Run analysis on the analysis queue (already on it from delegate)
        Task { @MainActor in
            await MainActor.run {
                // Access self properties safely
            }
        }

        // Perform analysis directly (we're already on analysisQueue)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        performFrameAnalysis(ciImage: ciImage)
    }

    /// Perform frame analysis (called from capture output)
    private nonisolated func performFrameAnalysis(ciImage: CIImage) {
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        var regions: [DetectedRegion] = []
        var recognizedText = ""
        let aestheticsScore: Float? = nil
        var humanPoses: [DetectedPose] = []
        var animalPoses: [DetectedPose] = []

        // Text recognition (fast mode for real-time)
        let textRequest = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            for observation in observations {
                if let text = observation.topCandidates(1).first?.string {
                    recognizedText += text + " "
                    regions.append(DetectedRegion(
                        type: .text,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        preview: String(text.prefix(30))
                    ))
                }
            }
        }
        textRequest.recognitionLevel = .fast

        // Document detection
        let documentRequest = VNDetectDocumentSegmentationRequest { request, error in
            guard let observation = request.results?.first as? VNRectangleObservation else { return }
            regions.append(DetectedRegion(
                type: .document,
                boundingBox: observation.boundingBox,
                confidence: observation.confidence,
                preview: nil
            ))
        }

        // Scene/Image Classification
        let classifyRequest = VNClassifyImageRequest { request, error in
            guard let observations = request.results as? [VNClassificationObservation] else { return }

            // Top 3 classifications with high confidence
            let topClassifications = observations
                .filter { $0.confidence > 0.3 }
                .prefix(3)

            for classification in topClassifications {
                // Create a bounding box that represents the whole image for scene labels
                regions.append(DetectedRegion(
                    type: .scene,
                    boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                    confidence: classification.confidence,
                    preview: classification.identifier.replacingOccurrences(of: "_", with: " ").capitalized
                ))
            }
        }

        // Animal Detection
        let animalRequest = VNRecognizeAnimalsRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }

            for observation in observations {
                let label = observation.labels.first?.identifier ?? "Animal"
                regions.append(DetectedRegion(
                    type: .object,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: label.capitalized
                ))
            }
        }

        // Face Detection
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            guard let observations = request.results as? [VNFaceObservation] else { return }

            for observation in observations {
                regions.append(DetectedRegion(
                    type: .face,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: "Face"
                ))
            }
        }

        // Human Body Detection
        let humanRequest = VNDetectHumanRectanglesRequest { request, error in
            guard let observations = request.results as? [VNHumanObservation] else { return }

            for observation in observations {
                regions.append(DetectedRegion(
                    type: .human,
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    preview: "Person"
                ))
            }
        }

        // Human Body Pose Detection
        let humanPoseRequest = VNDetectHumanBodyPoseRequest { request, error in
            guard let observations = request.results as? [VNHumanBodyPoseObservation] else { return }

            for observation in observations {
                if let pose = Self.createHumanPose(from: observation) {
                    humanPoses.append(pose)
                }
            }
        }

        // Animal Body Pose Detection
        let animalPoseRequest = VNDetectAnimalBodyPoseRequest { request, error in
            guard let observations = request.results as? [VNAnimalBodyPoseObservation] else { return }

            for observation in observations {
                if let pose = Self.createAnimalPose(from: observation) {
                    animalPoses.append(pose)
                }
            }
        }

        // Lens smudge detection placeholder (VNDetectLensSmudgeRequest not yet available)
        let lensSmudgeDetected = false

        // Limit concurrent Vision requests to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            do {
                try requestHandler.perform([textRequest, documentRequest, classifyRequest, animalRequest, faceRequest, humanRequest, humanPoseRequest, animalPoseRequest])
            } catch {
                Log.debug("Frame analysis Vision failed: \(error)", category: .pipeline)
            }
        }

        // Extract scene labels and object names from regions
        let sceneLabels = regions
            .filter { $0.type == .scene }
            .compactMap { $0.preview }

        let detectedObjects = regions
            .filter { $0.type == .object }
            .compactMap { $0.preview }

        let frameAnalysis = FrameAnalysis(
            regions: regions,
            recognizedText: recognizedText.trimmingCharacters(in: .whitespacesAndNewlines),
            aestheticsScore: aestheticsScore,
            sceneLabels: sceneLabels,
            detectedObjects: detectedObjects,
            humanPoses: humanPoses,
            animalPoses: animalPoses,
            lensSmudgeDetected: lensSmudgeDetected
        )

        DispatchQueue.main.async { [weak self] in
            self?.onFrameAnalyzed?(frameAnalysis)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                pendingCaptureContinuation?.resume(throwing: error)
                pendingCaptureContinuation = nil
                pendingDocumentContinuation?.resume(throwing: error)
                pendingDocumentContinuation = nil
                return
            }

            guard let imageData = photo.fileDataRepresentation(),
                  let uiImage = UIImage(data: imageData),
                  let cgImage = uiImage.cgImage
            else {
                let error = CameraError.failedToProcessPhoto
                pendingCaptureContinuation?.resume(throwing: error)
                pendingCaptureContinuation = nil
                pendingDocumentContinuation?.resume(throwing: error)
                pendingDocumentContinuation = nil
                return
            }

            // Determine which continuation to use
            if let continuation = pendingDocumentContinuation {
                pendingDocumentContinuation = nil
                let result = await analyzeCapture(cgImage, isDocumentCapture: true)
                continuation.resume(returning: result)
            } else if let continuation = pendingCaptureContinuation {
                pendingCaptureContinuation = nil
                let result = await analyzeCapture(cgImage, isDocumentCapture: false)
                continuation.resume(returning: result)
            }
        }
    }
}

// MARK: - Pose Detection Helpers

extension CameraManager {
    /// Create a DetectedPose from VNHumanBodyPoseObservation
    /// Anatomically accurate 17-joint human skeleton based on COCO keypoint format
    nonisolated static func createHumanPose(from observation: VNHumanBodyPoseObservation) -> DetectedPose? {
        var joints: [PoseJoint] = []
        var connections: [PoseConnection] = []

        // Simple stick figure joints - only what we need for clean wireframe
        // Head, Neck, Shoulders, Elbows, Hands, Pelvis, Hips, Knees, Ankles
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            // Head (1 point - top of figure)
            .nose,
            // Neck (center of shoulder bar)
            .neck,
            // Shoulders (ends of top T-bar)
            .leftShoulder,
            .rightShoulder,
            // Arms
            .leftElbow,
            .rightElbow,
            .leftWrist,      // Hand
            .rightWrist,     // Hand
            // Pelvis (center of hip bar)
            .root,
            // Hips (ends of bottom T-bar)
            .leftHip,
            .rightHip,
            // Legs
            .leftKnee,
            .rightKnee,
            .leftAnkle,
            .rightAnkle
        ]

        var jointPositions: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

        // Extract all joints with anatomical naming
        for jointName in jointNames {
            if let point = try? observation.recognizedPoint(jointName),
               point.confidence > 0.2 {  // Lower threshold to capture more joints
                joints.append(PoseJoint(
                    name: jointName.rawValue.rawValue,
                    position: point.location,
                    confidence: point.confidence
                ))
                jointPositions[jointName] = point.location
            }
        }

        // Clean stick figure skeleton - simple T-shape with limbs
        // Head → Neck → Shoulders (T-bar) → Spine → Hips (T-bar) → Legs
        let connectionPairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            // HEAD to NECK (vertical spine start)
            (.nose, .neck),

            // SHOULDER BAR (horizontal T across top)
            (.leftShoulder, .rightShoulder),

            // NECK connects to shoulder bar center (implicit via shoulders)
            (.neck, .leftShoulder),
            (.neck, .rightShoulder),

            // SPINE - neck down to pelvis
            (.neck, .root),

            // HIP BAR (horizontal T across bottom)
            (.leftHip, .rightHip),

            // PELVIS connects to hip bar
            (.root, .leftHip),
            (.root, .rightHip),

            // LEFT ARM: shoulder → elbow → wrist (hand)
            (.leftShoulder, .leftElbow),
            (.leftElbow, .leftWrist),

            // RIGHT ARM: shoulder → elbow → wrist (hand)
            (.rightShoulder, .rightElbow),
            (.rightElbow, .rightWrist),

            // LEFT LEG: hip → knee → ankle
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle),

            // RIGHT LEG: hip → knee → ankle
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle)
        ]

        // Create connections
        for (from, to) in connectionPairs {
            if let fromPos = jointPositions[from],
               let toPos = jointPositions[to] {
                let fromPoint = try? observation.recognizedPoint(from)
                let toPoint = try? observation.recognizedPoint(to)
                let confidence = min(fromPoint?.confidence ?? 0, toPoint?.confidence ?? 0)

                connections.append(PoseConnection(
                    from: fromPos,
                    to: toPos,
                    confidence: confidence
                ))
            }
        }

        guard !joints.isEmpty else { return nil }

        // Calculate bounding box from all joints
        let xs = joints.map { $0.position.x }
        let ys = joints.map { $0.position.y }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        return DetectedPose(
            isHuman: true,
            joints: joints,
            connections: connections,
            boundingBox: boundingBox,
            confidence: joints.map { $0.confidence }.reduce(0, +) / Float(joints.count)
        )
    }

    /// Create a DetectedPose from VNAnimalBodyPoseObservation
    /// Anatomically accurate quadruped skeleton (dogs, cats, etc.)
    /// Based on veterinary anatomy: 25 keypoints covering head, spine, limbs, tail
    nonisolated static func createAnimalPose(from observation: VNAnimalBodyPoseObservation) -> DetectedPose? {
        var joints: [PoseJoint] = []
        var connections: [PoseConnection] = []

        // Complete quadruped skeleton (anatomically accurate joint names)
        // HEAD: Facial features and ears (pinnae with 3 points each for ear shape)
        // BODY: Neck (cervical), withers/shoulders, back, hindquarters
        // LIMBS: Each leg has 3 joints matching real anatomy
        //   Front legs: Shoulder → Elbow → Carpus (wrist) → Paw
        //   Back legs: Hip → Stifle (knee) → Hock (ankle) → Paw
        // TAIL: 3 points for tail curvature
        // Simple quadruped stick figure joints
        // Head, Neck, 4 legs with 3 joints each, Tail
        let jointNames: [VNAnimalBodyPoseObservation.JointName] = [
            // Head (just nose as head marker)
            .nose,
            // Neck
            .neck,
            // Front legs (shoulder/elbow/paw)
            .leftFrontElbow,   // Shoulder
            .leftFrontKnee,    // Elbow
            .leftFrontPaw,     // Paw
            .rightFrontElbow,
            .rightFrontKnee,
            .rightFrontPaw,
            // Back legs (hip/knee/paw)
            .leftBackElbow,    // Hip
            .leftBackKnee,     // Knee
            .leftBackPaw,      // Paw
            .rightBackElbow,
            .rightBackKnee,
            .rightBackPaw,
            // Tail
            .tailTop,
            .tailBottom
        ]

        var jointPositions: [VNAnimalBodyPoseObservation.JointName: CGPoint] = [:]

        // Extract all joints with lower threshold for complete skeleton
        for jointName in jointNames {
            if let point = try? observation.recognizedPoint(jointName),
               point.confidence > 0.2 {
                joints.append(PoseJoint(
                    name: jointName.rawValue.rawValue,
                    position: point.location,
                    confidence: point.confidence
                ))
                jointPositions[jointName] = point.location
            }
        }

        // Simple quadruped stick figure connections
        // Head → Neck → Body line → Legs
        let connectionPairs: [(VNAnimalBodyPoseObservation.JointName, VNAnimalBodyPoseObservation.JointName)] = [
            // HEAD to NECK
            (.nose, .neck),

            // BODY - horizontal spine from front shoulders to back hips
            (.neck, .leftFrontElbow),                   // Neck to left front shoulder
            (.neck, .rightFrontElbow),                  // Neck to right front shoulder
            (.leftFrontElbow, .rightFrontElbow),        // Front shoulders bar

            // Connect front to back (body line)
            (.leftFrontElbow, .leftBackElbow),          // Left side body
            (.rightFrontElbow, .rightBackElbow),        // Right side body
            (.leftBackElbow, .rightBackElbow),          // Back hips bar

            // LEFT FRONT LEG: shoulder → elbow → paw
            (.leftFrontElbow, .leftFrontKnee),
            (.leftFrontKnee, .leftFrontPaw),

            // RIGHT FRONT LEG
            (.rightFrontElbow, .rightFrontKnee),
            (.rightFrontKnee, .rightFrontPaw),

            // LEFT BACK LEG: hip → knee → paw
            (.leftBackElbow, .leftBackKnee),
            (.leftBackKnee, .leftBackPaw),

            // RIGHT BACK LEG
            (.rightBackElbow, .rightBackKnee),
            (.rightBackKnee, .rightBackPaw),

            // TAIL
            (.leftBackElbow, .tailTop),
            (.rightBackElbow, .tailTop),
            (.tailTop, .tailBottom)
        ]

        // Create connections
        for (from, to) in connectionPairs {
            if let fromPos = jointPositions[from],
               let toPos = jointPositions[to] {
                let fromPoint = try? observation.recognizedPoint(from)
                let toPoint = try? observation.recognizedPoint(to)
                let confidence = min(fromPoint?.confidence ?? 0, toPoint?.confidence ?? 0)

                connections.append(PoseConnection(
                    from: fromPos,
                    to: toPos,
                    confidence: confidence
                ))
            }
        }

        guard !joints.isEmpty else { return nil }

        // Calculate bounding box from all joints
        let xs = joints.map { $0.position.x }
        let ys = joints.map { $0.position.y }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        return DetectedPose(
            isHuman: false,
            joints: joints,
            connections: connections,
            boundingBox: boundingBox,
            confidence: joints.map { $0.confidence }.reduce(0, +) / Float(joints.count)
        )
    }

    // MARK: - Classification Helpers

    /// Category for classifying detected objects
    enum ClassificationCategory {
        case scene
        case animal
        case plant
        case electronics
        case vehicle
        case food
        case object
    }

    /// Format a raw classification label for display
    /// Example: "golden_retriever" -> "Golden Retriever"
    nonisolated static func formatClassificationLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                // Capitalize first letter of each word
                let str = String(word)
                return str.prefix(1).uppercased() + str.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    /// Categorize a classification label into semantic groups
    /// This uses Apple's Vision taxonomy which includes 400+ categories
    nonisolated static func categorizeLabel(_ identifier: String) -> ClassificationCategory {
        let lowercased = identifier.lowercased()

        // Dog breeds (Apple Vision includes 100+ dog breeds)
        let dogBreeds = [
            "retriever", "shepherd", "terrier", "spaniel", "poodle", "bulldog",
            "beagle", "husky", "corgi", "dachshund", "chihuahua", "boxer",
            "rottweiler", "doberman", "mastiff", "collie", "schnauzer",
            "pomeranian", "maltese", "shih_tzu", "pug", "pit_bull", "great_dane",
            "dalmatian", "saint_bernard", "bernese", "samoyed", "akita", "malamute",
            "whippet", "greyhound", "basset", "bloodhound", "pointer", "setter",
            "weimaraner", "vizsla", "papillon", "havanese", "bichon", "lhasa_apso",
            "pekinese", "chow", "shar_pei", "basenji", "newfoundland", "leonberger",
            "keeshond", "komondor", "briard", "bouvier", "belgian", "australian",
            "border_collie", "old_english_sheepdog", "shetland_sheepdog", "cardigan",
            "pembroke", "affenpinscher", "brussels_griffon", "toy_poodle", "miniature",
            "standard_poodle", "giant_schnauzer", "scottish_deerhound", "irish_wolfhound",
            "borzoi", "afghan_hound", "saluki", "otterhound", "black_and_tan_coonhound",
            "redbone", "bluetick", "english_foxhound", "american_foxhound", "plott",
            "rhodesian_ridgeback", "german_short", "english_setter", "irish_setter",
            "gordon_setter", "clumber_spaniel", "english_springer", "welsh_springer",
            "cocker_spaniel", "sussex_spaniel", "irish_water_spaniel", "kuvasz"
        ]

        // Cat breeds
        let catBreeds = [
            "siamese", "persian", "maine_coon", "ragdoll", "bengal", "abyssinian",
            "sphynx", "british_shorthair", "scottish_fold", "norwegian_forest",
            "birman", "russian_blue", "egyptian_mau", "tabby", "calico", "tuxedo"
        ]

        // Other animals
        let animals = [
            "dog", "cat", "bird", "fish", "rabbit", "hamster", "guinea_pig", "turtle",
            "snake", "lizard", "frog", "horse", "cow", "pig", "sheep", "goat", "chicken",
            "duck", "goose", "owl", "eagle", "hawk", "parrot", "penguin", "flamingo",
            "lion", "tiger", "bear", "wolf", "fox", "deer", "elephant", "giraffe",
            "zebra", "monkey", "gorilla", "chimpanzee", "koala", "kangaroo", "panda"
        ]

        // Plants and flowers
        let plants = [
            "flower", "rose", "tulip", "daisy", "sunflower", "lily", "orchid", "hibiscus",
            "carnation", "chrysanthemum", "lavender", "jasmine", "violet", "peony",
            "plant", "tree", "palm", "fern", "cactus", "succulent", "bonsai", "bamboo",
            "ivy", "moss", "grass", "bush", "shrub", "hedge", "vine", "leaf", "petal",
            "oak", "maple", "pine", "birch", "willow", "cherry_blossom", "magnolia"
        ]

        // Electronics and devices (Vision includes some electronics categories)
        let electronics = [
            "laptop", "computer", "keyboard", "mouse", "monitor", "screen", "display",
            "phone", "cellphone", "smartphone", "tablet", "ipod", "headphone", "earbud",
            "speaker", "microphone", "camera", "television", "tv", "remote", "controller",
            "console", "projector", "printer", "scanner", "router", "modem", "cable",
            "charger", "adapter", "usb", "hdmi", "battery", "power_bank", "electronic"
        ]

        // Vehicles
        let vehicles = [
            "car", "automobile", "truck", "van", "bus", "motorcycle", "bicycle", "bike",
            "scooter", "skateboard", "boat", "ship", "yacht", "airplane", "helicopter",
            "train", "tram", "subway", "taxi", "ambulance", "fire_truck", "police_car",
            "sports_car", "convertible", "suv", "pickup", "limousine", "minivan", "jeep"
        ]

        // Food and drinks
        let food = [
            "food", "pizza", "burger", "sandwich", "taco", "sushi", "pasta", "noodle",
            "rice", "bread", "cake", "cookie", "ice_cream", "fruit", "apple", "banana",
            "orange", "grape", "strawberry", "watermelon", "vegetable", "salad", "soup",
            "coffee", "tea", "juice", "smoothie", "beer", "wine", "cocktail", "soda",
            "chocolate", "candy", "donut", "croissant", "bagel", "muffin", "waffle"
        ]

        // Check categories
        if dogBreeds.contains(where: { lowercased.contains($0) }) {
            return .animal
        }
        if catBreeds.contains(where: { lowercased.contains($0) }) {
            return .animal
        }
        if animals.contains(where: { lowercased.contains($0) }) {
            return .animal
        }
        if plants.contains(where: { lowercased.contains($0) }) {
            return .plant
        }
        if electronics.contains(where: { lowercased.contains($0) }) {
            return .electronics
        }
        if vehicles.contains(where: { lowercased.contains($0) }) {
            return .vehicle
        }
        if food.contains(where: { lowercased.contains($0) }) {
            return .food
        }

        return .scene
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case photoOutputNotAvailable
    case failedToProcessPhoto
    case analysisTimeout

    var errorDescription: String? {
        switch self {
        case .photoOutputNotAvailable:
            return "Camera photo output is not available"
        case .failedToProcessPhoto:
            return "Failed to process captured photo"
        case .analysisTimeout:
            return "Vision analysis timed out"
        }
    }
}
#endif

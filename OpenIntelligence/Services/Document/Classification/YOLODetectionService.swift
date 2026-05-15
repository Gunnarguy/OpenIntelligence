//
//  YOLODetectionService.swift
//  OpenIntelligence
//
//  YOLO-based object detection for intelligent capture.
//  Uses Apple's YOLOv3 CoreML model for 80-class object detection.
//
//  Download model from: https://developer.apple.com/machine-learning/models/
//  File: YOLOv3.mlmodel or YOLOv3Tiny.mlmodel (faster, less accurate)
//

import CoreML
import Foundation
import Vision
import CoreImage

// MARK: - Detected Object

/// A single detected object with bounding box and class
struct DetectedObject: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized 0-1 coordinates

    /// Human-readable description
    var description: String {
        "\(label) (\(Int(confidence * 100))%)"
    }
}

// MARK: - YOLO Detection Service

/// Service for YOLO-based object detection
/// Falls back to Apple Vision if YOLO model not available
actor YOLODetectionService {

    static let shared = YOLODetectionService()

    // MARK: - State

    private var yoloModel: VNCoreMLModel?
    private var yoloBackingModel: MLModel?
    private var isModelLoaded = false
    private var modelLoadError: Error?

    // COCO class labels (80 classes that YOLO detects)
    private let cocoClasses: [String] = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake",
        "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop",
        "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]

    // MARK: - Initialization

    init() {
        Task {
            await loadModel()
        }
    }

    // MARK: - Model Loading

    private func loadModel() async {
        // Try to load YOLOv3Tiny first (faster, 35MB)
        // Then try YOLOv3 (more accurate, 248MB)
        let modelNames = ["YOLOv3Tiny", "YOLOv3", "YOLOv3TinyInt8LUT", "YOLOv3Int8LUT"]

        for modelName in modelNames {
            if let modelURL = OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "mlmodelc") {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .all  // Use Neural Engine if available

                    let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
                    yoloBackingModel = mlModel
                    yoloModel = try VNCoreMLModel(for: mlModel)
                    isModelLoaded = true
                    Log.info("[YOLO] Loaded \(modelName) successfully", category: .ingestion)
                    return
                } catch {
                    modelLoadError = error
                    Log.warning("[YOLO] Failed to load \(modelName): \(error.localizedDescription)", category: .ingestion)
                }
            }
        }

        Log.info("[YOLO] No YOLO model found, will use Apple Vision fallback", category: .ingestion)
    }

    // MARK: - Detection

    /// Detect objects in an image using YOLO (or Vision fallback)
    func detectObjects(in image: CGImage, confidenceThreshold: Float = 0.5) async -> [DetectedObject] {
        if isModelLoaded, let model = yoloModel, let backingModel = yoloBackingModel {
            return await detectWithYOLO(image: image, model: model, backingModel: backingModel, threshold: confidenceThreshold)
        } else {
            return await detectWithVisionFallback(image: image, threshold: confidenceThreshold)
        }
    }

    /// Detect objects in a CIImage
    func detectObjects(in ciImage: CIImage, confidenceThreshold: Float = 0.5) async -> [DetectedObject] {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return []
        }
        return await detectObjects(in: cgImage, confidenceThreshold: confidenceThreshold)
    }

    /// Detect objects in a pixel buffer (for real-time camera frames)
    func detectObjects(in pixelBuffer: CVPixelBuffer, confidenceThreshold: Float = 0.5) async -> [DetectedObject] {
        if isModelLoaded, let model = yoloModel, let backingModel = yoloBackingModel {
            return await detectWithYOLO(pixelBuffer: pixelBuffer, model: model, backingModel: backingModel, threshold: confidenceThreshold)
        } else {
            return await detectWithVisionFallback(pixelBuffer: pixelBuffer, threshold: confidenceThreshold)
        }
    }

    // MARK: - YOLO Detection

    private func detectWithYOLO(image: CGImage, model: VNCoreMLModel, backingModel: MLModel, threshold: Float) async -> [DetectedObject] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        return await performYOLORequest(handler: handler, model: model, backingModel: backingModel, threshold: threshold)
    }

    private func detectWithYOLO(pixelBuffer: CVPixelBuffer, model: VNCoreMLModel, backingModel: MLModel, threshold: Float) async -> [DetectedObject] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        return await performYOLORequest(handler: handler, model: model, backingModel: backingModel, threshold: threshold)
    }

    private func performYOLORequest(handler: VNImageRequestHandler, model: VNCoreMLModel, backingModel: MLModel, threshold: Float) async -> [DetectedObject] {
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let objects = results.compactMap { observation -> DetectedObject? in
                    guard let topLabel = observation.labels.first,
                          topLabel.confidence >= threshold else {
                        return nil
                    }

                    return DetectedObject(
                        label: self.formatLabel(topLabel.identifier),
                        confidence: topLabel.confidence,
                        boundingBox: observation.boundingBox
                    )
                }

                continuation.resume(returning: objects)
            }

            request.imageCropAndScaleOption = .scaleFill

            // Limit concurrent Vision requests to prevent Metal race conditions
            withExtendedLifetime(backingModel) {
                VisionOCRThrottle.performSync {
                    do {
                        try handler.perform([request])
                    } catch {
                        Log.error("[YOLO] Detection failed: \(error.localizedDescription)", category: .ingestion)
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    // MARK: - Vision Fallback

    private func detectWithVisionFallback(image: CGImage, threshold: Float) async -> [DetectedObject] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        return await performVisionFallback(handler: handler, threshold: threshold)
    }

    private func detectWithVisionFallback(pixelBuffer: CVPixelBuffer, threshold: Float) async -> [DetectedObject] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        return await performVisionFallback(handler: handler, threshold: threshold)
    }

    private func performVisionFallback(handler: VNImageRequestHandler, threshold: Float) async -> [DetectedObject] {
        var objects: [DetectedObject] = []

        // Use VNClassifyImageRequest for scene/object labels
        let classifyRequest = VNClassifyImageRequest()

        // Use VNRecognizeAnimalsRequest for animal detection with bounding boxes
        let animalRequest = VNRecognizeAnimalsRequest()

        // Limit concurrent Vision requests to prevent Metal race conditions
        VisionOCRThrottle.performSync {
            do {
                try handler.perform([classifyRequest, animalRequest])

                // Get classifications (no bounding boxes, but good labels)
                if let classifications = classifyRequest.results {
                    for classification in classifications.prefix(5) where classification.confidence >= threshold {
                        objects.append(DetectedObject(
                            label: self.formatLabel(classification.identifier),
                            confidence: classification.confidence,
                            boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)  // Full frame
                        ))
                    }
                }

                // Get animal detections (with bounding boxes)
                if let animals = animalRequest.results {
                    for animal in animals {
                        if let topLabel = animal.labels.first, topLabel.confidence >= threshold {
                            objects.append(DetectedObject(
                                label: self.formatLabel(topLabel.identifier),
                                confidence: topLabel.confidence,
                                boundingBox: animal.boundingBox
                            ))
                        }
                    }
                }
            } catch {
                Log.error("[YOLO Fallback] Detection failed: \(error.localizedDescription)", category: .ingestion)
            }
        }

        return objects
    }

    // MARK: - Helpers

    private func formatLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Check if YOLO model is available
    var isYOLOAvailable: Bool {
        isModelLoaded
    }

    /// Get all COCO classes YOLO can detect
    var availableClasses: [String] {
        cocoClasses
    }
}

// MARK: - Integration with Smart Capture

extension YOLODetectionService {

    /// Get a rich description of detected objects for RAG ingestion
    func describeObjects(_ objects: [DetectedObject]) -> String {
        guard !objects.isEmpty else { return "" }

        // Group by label
        var labelCounts: [String: Int] = [:]
        for obj in objects {
            labelCounts[obj.label, default: 0] += 1
        }

        // Format description
        let descriptions = labelCounts.map { label, count in
            count > 1 ? "\(count) \(label)s" : label
        }

        return descriptions.joined(separator: ", ")
    }

    /// Categorize objects for better organization
    func categorizeObjects(_ objects: [DetectedObject]) -> [String: [DetectedObject]] {
        var categories: [String: [DetectedObject]] = [:]

        for obj in objects {
            let category = categoryFor(label: obj.label.lowercased())
            categories[category, default: []].append(obj)
        }

        return categories
    }

    private func categoryFor(label: String) -> String {
        let animals = ["person", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "teddy bear"]
        let vehicles = ["bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat"]
        let food = ["banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake"]
        let electronics = ["tv", "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "refrigerator"]
        let furniture = ["chair", "couch", "bed", "dining table", "toilet", "potted plant"]
        let sports = ["frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket"]

        if animals.contains(label) { return "Living Things" }
        if vehicles.contains(label) { return "Vehicles" }
        if food.contains(label) { return "Food" }
        if electronics.contains(label) { return "Electronics" }
        if furniture.contains(label) { return "Furniture" }
        if sports.contains(label) { return "Sports" }

        return "Objects"
    }
}

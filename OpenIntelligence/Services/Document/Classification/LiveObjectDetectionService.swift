//
//  LiveObjectDetectionService.swift
//  OpenIntelligence
//
//  Live object detection built on the detectors the OS already ships.
//
//  Replaces YOLODetectionService, which could never run. See the type documentation below.
//

import CoreImage
import CoreML
import Foundation
import Vision

// MARK: - Detected Object

/// A single detected thing, with a normalized bounding box in Vision's coordinate space
/// (origin lower-left, 0-1 on both axes). Consumers flip Y when drawing in SwiftUI.
struct DetectedObject: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect

    /// True when the detector produced a label for the whole frame rather than for a region,
    /// which is the case for scene classification.
    ///
    /// This exists because the previous implementation handed scene labels
    /// `CGRect(x: 0, y: 0, width: 1, height: 1)` so they would satisfy the overlay's
    /// box-drawing code. Had that overlay ever been reachable, the user would have seen up to
    /// five rectangles drawn around the entire frame, one per label, stacked on top of each
    /// other. A caller can now render these as text rather than as geometry.
    let isSceneLevel: Bool

    init(label: String, confidence: Float, boundingBox: CGRect, isSceneLevel: Bool = false) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.isSceneLevel = isSceneLevel
    }

    /// Human-readable description
    var description: String {
        "\(label) (\(Int(confidence * 100))%)"
    }
}

// MARK: - Live Object Detection

/// Detects objects in a frame using the Vision detectors built into iOS and macOS.
///
/// **Why this replaced `YOLODetectionService`.** That service was written against Apple's
/// downloadable YOLOv3 CoreML model. `loadModel()` searched the resource bundle for
/// `YOLOv3Tiny`, `YOLOv3`, `YOLOv3TinyInt8LUT` and `YOLOv3Int8LUT` as `.mlmodelc`. **None of
/// those files exist in this repository and none ever did**, so `isModelLoaded` was permanently
/// false, the 80-entry COCO class list it carried was never read by any code path, and every
/// call fell through to a fallback. The fallback ran `VNClassifyImageRequest`, which returns
/// scene labels carrying no spatial extent, and `VNRecognizeAnimalsRequest`. So the feature
/// described as "object detection with bounding boxes" could, at absolute best, box an animal.
///
/// **What replaces it needs no download.** Every detector below ships in the OS, runs on the
/// Neural Engine, and returns real geometry:
///
/// | Request | Gives |
/// |---|---|
/// | `DetectHumanRectanglesRequest` | people, upper-body flag, real box |
/// | `DetectFaceRectanglesRequest` | faces, real box |
/// | `RecognizeAnimalsRequest` | animal species label, real box |
/// | `DetectBarcodesRequest` | decoded payload and symbology, real box |
/// | `ClassifyImageRequest` | scene and object labels, **no** box |
///
/// Only the last one lacks geometry, and its results are now marked `isSceneLevel` instead of
/// being given a fake full-frame rectangle.
///
/// **A CoreML detector is still supported and still optional.** If a real object-detection
/// model is ever added to the bundle, `configure(withModelNamed:)` will use it and its results
/// are merged with the built-in detectors rather than replacing them. Nothing searches for a
/// model that is not there, and nothing logs a warning about its absence, because its absence
/// is the normal case.
actor LiveObjectDetectionService {

    static let shared = LiveObjectDetectionService()

    /// An optional CoreML object detector. Nil unless `configure(withModelNamed:)` succeeded.
    private var coreMLModel: CoreMLModelContainer?

    /// A frame to run detection on.
    ///
    /// `@unchecked Sendable` because `CGImage` and `CVPixelBuffer` are CoreFoundation types the
    /// compiler cannot reason about. Both are treated as read-only here: nothing in this file
    /// mutates a frame, and each is handed to Vision and then dropped.
    private struct Frame: @unchecked Sendable {
        enum Storage {
            case cgImage(CGImage)
            case pixelBuffer(CVPixelBuffer)
        }
        let storage: Storage
    }

    // MARK: - Optional CoreML model

    /// Load a CoreML object-detection model from the resource bundle, if one has been added.
    ///
    /// Returns false rather than throwing when the model is absent, because absent is the
    /// expected state. Call this only if a model has actually been shipped.
    func configure(withModelNamed name: String) -> Bool {
        guard let url = OpenIntelligenceResourceBundle.url(forResource: name, withExtension: "mlmodelc") else {
            return false
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let mlModel = try MLModel(contentsOf: url, configuration: configuration)
            coreMLModel = try CoreMLModelContainer(model: mlModel)
            Log.info("[Detection] Loaded CoreML detector \(name)", category: .ingestion)
            return true
        } catch {
            Log.warning("[Detection] \(name) present but unusable: \(error.localizedDescription)", category: .ingestion)
            return false
        }
    }

    var hasCoreMLDetector: Bool { coreMLModel != nil }

    // MARK: - Detection

    func detectObjects(in image: CGImage, confidenceThreshold: Float = 0.5) async -> [DetectedObject] {
        await detect(Frame(storage: .cgImage(image)), threshold: confidenceThreshold)
    }

    func detectObjects(in pixelBuffer: CVPixelBuffer, confidenceThreshold: Float = 0.5) async -> [DetectedObject] {
        await detect(Frame(storage: .pixelBuffer(pixelBuffer)), threshold: confidenceThreshold)
    }

    func detectObjects(in ciImage: CIImage, confidenceThreshold: Float = 0.5) async -> [DetectedObject] {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return [] }
        return await detectObjects(in: cgImage, confidenceThreshold: confidenceThreshold)
    }

    /// Runs every detector over one frame and merges the results.
    ///
    /// Each request goes through `VisionOCRThrottle` individually rather than as one batch. The
    /// throttle exists because concurrent Vision work races on the Metal command buffer, and a
    /// live camera feed is the most concurrent caller in the app. Serialising per request also
    /// means one detector failing does not lose the others: a thrown error is logged and skipped.
    private func detect(_ frame: Frame, threshold: Float) async -> [DetectedObject] {
        var objects: [DetectedObject] = []

        objects += await run("humans", frame) { frame in
            try await Self.perform(DetectHumanRectanglesRequest(), on: frame).map {
                DetectedObject(
                    label: $0.isUpperBodyOnly ? "Person (upper body)" : "Person",
                    confidence: $0.confidence,
                    boundingBox: $0.boundingBox.cgRect
                )
            }
            .filter { $0.confidence >= threshold }
        }

        objects += await run("faces", frame) { frame in
            try await Self.perform(DetectFaceRectanglesRequest(), on: frame)
                .filter { $0.confidence >= threshold }
                .map {
                    DetectedObject(label: "Face", confidence: $0.confidence, boundingBox: $0.boundingBox.cgRect)
                }
        }

        objects += await run("animals", frame) { frame in
            try await Self.perform(RecognizeAnimalsRequest(), on: frame).compactMap { observation in
                guard let top = observation.labels.first, top.confidence >= threshold else { return nil }
                return DetectedObject(
                    label: Self.formatLabel(top.identifier),
                    confidence: top.confidence,
                    boundingBox: observation.boundingBox.cgRect
                )
            }
        }

        objects += await run("barcodes", frame) { frame in
            try await Self.perform(DetectBarcodesRequest(), on: frame).map { observation in
                // The payload is the useful identifier. Falling back to the symbology name means
                // a barcode Vision located but could not decode still gets a box.
                // `BarcodeSymbology` is a plain enum with no raw value, so the case name is the
                // only stable text available for it.
                let payload = observation.payloadString ?? String(describing: observation.symbology)
                return DetectedObject(
                    label: payload,
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox.cgRect
                )
            }
        }

        // Scene labels last, and marked, because they describe the frame rather than a region.
        objects += await run("scene", frame) { frame in
            try await Self.perform(ClassifyImageRequest(), on: frame)
                .filter { $0.confidence >= threshold }
                .prefix(5)
                .map {
                    DetectedObject(
                        label: Self.formatLabel($0.identifier),
                        confidence: $0.confidence,
                        boundingBox: .zero,
                        isSceneLevel: true
                    )
                }
        }

        if let model = coreMLModel {
            objects += await run("coreml", frame) { frame in
                try await Self.perform(CoreMLRequest(model: model), on: frame)
                    .compactMap { $0 as? RecognizedObjectObservation }
                    .compactMap { observation in
                        guard let top = observation.labels.first, top.confidence >= threshold else { return nil }
                        return DetectedObject(
                            label: Self.formatLabel(top.identifier),
                            confidence: top.confidence,
                            boundingBox: observation.boundingBox.cgRect
                        )
                    }
            }
        }

        return objects
    }

    /// One throttled detector run. Returns an empty array and logs if it throws, so a single
    /// failing detector cannot take the rest of the frame's results with it.
    private func run(
        _ name: String,
        _ frame: Frame,
        _ body: @Sendable @escaping (Frame) async throws -> [DetectedObject]
    ) async -> [DetectedObject] {
        do {
            return try await VisionOCRThrottle.performAsync { try await body(frame) }
        } catch {
            Log.debug("[Detection] \(name) failed: \(error.localizedDescription)", category: .ingestion)
            return []
        }
    }

    /// Dispatches to the right `perform` overload for the frame's backing storage.
    private static func perform<R: ImageProcessingRequest>(_ request: R, on frame: Frame) async throws -> R.Result {
        switch frame.storage {
        case .cgImage(let image):
            return try await request.perform(on: image)
        case .pixelBuffer(let buffer):
            return try await request.perform(on: buffer)
        }
    }

    // MARK: - Helpers

    nonisolated static func formatLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

// MARK: - Descriptions for ingestion

extension LiveObjectDetectionService {

    /// A short phrase naming what was detected, for attaching to a captured image in the library.
    ///
    /// Scene labels are listed after located objects and are not counted, because "2 Persons,
    /// Office" reads correctly while "2 Offices" does not: a scene label describes the frame
    /// once no matter how many times the classifier named it.
    nonisolated func describeObjects(_ objects: [DetectedObject]) -> String {
        guard !objects.isEmpty else { return "" }

        var counts: [String: Int] = [:]
        var order: [String] = []
        for object in objects where !object.isSceneLevel {
            if counts[object.label] == nil { order.append(object.label) }
            counts[object.label, default: 0] += 1
        }

        var parts = order.map { label in
            let count = counts[label] ?? 1
            return count > 1 ? "\(count) \(label)s" : label
        }

        // A scene label can repeat something a located detector already named: `ClassifyImageRequest`
        // can return "Person" for a frame `DetectHumanRectanglesRequest` has already boxed twice,
        // which would otherwise read "2 Persons, Person". Anything already counted is dropped here.
        var seen = Set(counts.keys)
        for object in objects where object.isSceneLevel && seen.insert(object.label).inserted {
            parts.append(object.label)
        }

        return parts.joined(separator: ", ")
    }
}

//
//  CameraOverlayGeometry.swift
//  OpenIntelligence
//
//  The two pieces of the live camera overlay that were wrong in a way no build could catch:
//  where a box goes, and whether it is the same box as last frame.
//
//  Both are pure functions over value types precisely so they can be tested. Nothing here touches
//  AVFoundation, Vision or SwiftUI. A live camera feed cannot be exercised in a simulator, so
//  proving this arithmetic in a test is the only verification available short of holding the phone.
//

#if os(iOS)
    import CoreGraphics
    import Foundation

    // MARK: - Where a box goes

    enum CameraOverlayGeometry {

        /// Converts a Vision-normalized rect into overlay coordinates for a preview displayed with
        /// `.resizeAspectFill`.
        ///
        /// **What was wrong before.** Every one of the five call sites did this:
        ///
        /// ```swift
        /// let x = box.minX * containerSize.width
        /// let y = (1 - box.maxY) * containerSize.height
        /// ```
        ///
        /// The Y-flip is right. Vision's origin is lower-left and SwiftUI's is upper-left, and
        /// `(1 - maxY) * H` is the correct conversion. The error is the assumption underneath it:
        /// that the normalized space maps onto the **view's** bounds. It maps onto the **image's**
        /// bounds, and `AVCaptureVideoPreviewLayer` was set to `.resizeAspectFill`, which scales the
        /// image to cover the view and crops the overflow. The image displayed is larger than the
        /// view and offset outside it, so normalized coordinates and view coordinates are two
        /// different spaces that were being treated as one.
        ///
        /// Concretely, a 1920x1080 buffer shown portrait on a 393x852 pt screen is scaled to match
        /// the height, giving a displayed width near 479 pt against a 393 pt view: about 18% of the
        /// image is off-screen, 43 pt beyond each edge. Boxes computed the old way were compressed
        /// horizontally by roughly 0.82 and pulled toward the centre, and the error grew toward the
        /// edges. It was a systematic offset, not jitter, which is why it looked like the detector
        /// was wrong rather than the drawing.
        ///
        /// - Parameters:
        ///   - normalized: Vision's rect. Origin lower-left, both axes 0...1.
        ///   - sourceSize: the pixel size of the image Vision actually analysed. This must be the
        ///     size **after** any rotation the capture connection applied, which is why
        ///     `FrameAnalysis` carries it from `ciImage.extent` rather than anyone inferring it
        ///     from the session preset. A preset is a request; the extent is what arrived.
        ///   - viewSize: the overlay's bounds.
        /// - Returns: a rect in the overlay's coordinate space, upper-left origin. May extend
        ///   outside `viewSize`, which is correct: the detection really is partly off-screen.
        static func viewRect(
            normalized: CGRect,
            sourceSize: CGSize,
            viewSize: CGSize
        ) -> CGRect {
            // A degenerate size would make the scale infinite or NaN, and a NaN reaching a SwiftUI
            // frame is a crash rather than a glitch. This app has already shipped that bug once,
            // from `min(nan, 1.0)` in the Silicon HUD.
            guard sourceSize.width > 0, sourceSize.height > 0,
                viewSize.width > 0, viewSize.height > 0
            else {
                return .zero
            }

            // `.resizeAspectFill` covers the view, so the scale is the LARGER of the two ratios.
            // `.resizeAspect` would be the smaller one and would letterbox instead of cropping.
            let scale = max(viewSize.width / sourceSize.width, viewSize.height / sourceSize.height)
            let displayed = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

            // Negative on the cropped axis: the image starts outside the view.
            let originX = (viewSize.width - displayed.width) / 2
            let originY = (viewSize.height - displayed.height) / 2

            return CGRect(
                x: normalized.minX * displayed.width + originX,
                y: (1 - normalized.maxY) * displayed.height + originY,
                width: normalized.width * displayed.width,
                height: normalized.height * displayed.height
            )
        }

        /// The same conversion for a single point, used by the pose wireframes.
        static func viewPoint(
            normalized: CGPoint,
            sourceSize: CGSize,
            viewSize: CGSize
        ) -> CGPoint {
            let rect = viewRect(
                normalized: CGRect(x: normalized.x, y: normalized.y, width: 0, height: 0),
                sourceSize: sourceSize,
                viewSize: viewSize
            )
            return CGPoint(x: rect.minX, y: rect.minY)
        }
    }

    // MARK: - Whether it is the same box as last frame

    /// Carries a detection's identity from one frame to the next.
    ///
    /// **What was wrong before.** `DetectedRegion` declared `let id = UUID()`, and
    /// `performFrameAnalysis` builds every region fresh on every frame. So `ForEach` saw a
    /// completely new identity set each update and SwiftUI did the only thing it can with that:
    /// destroy every box view and insert a replacement.
    ///
    /// The consequence is not subtle. Two `interpolatingSpring` animations are written against
    /// these views, one on the state write and one on the shape's `frame`, and **neither can ever
    /// run**, because a spring interpolates a surviving view's property and no view survived. The
    /// boxes did not move badly; they did not move at all. They blinked out and reappeared
    /// somewhere else, several times a second. `smoothDocumentRegions` was defeated by the same
    /// thing: a perfectly smoothed rect still arrived in a brand-new view.
    ///
    /// Matching is greedy by intersection-over-union within the same `RegionType`. That is enough
    /// for this: detections move a little between frames at 10 FPS, and the alternative, a real
    /// tracker with motion prediction, would be a lot of machinery for boxes drawn over a live
    /// preview a tenth of a second apart.
    struct RegionIdentityTracker {

        /// Below this overlap, two rects are treated as different things rather than the same thing
        /// that moved. 0.3 is deliberately loose: a missed match costs one frame of animation, while
        /// a wrong match drags a box across the screen, which reads far worse.
        private let minimumOverlap: CGFloat

        private var previous: [(id: UUID, type: RegionType, box: CGRect)] = []

        init(minimumOverlap: CGFloat = 0.3) {
            self.minimumOverlap = minimumOverlap
        }

        /// Returns the same regions with ids carried over from whatever they matched last frame.
        mutating func assigningStableIDs(to regions: [DetectedRegion]) -> [DetectedRegion] {
            var availableIndices = Set(previous.indices)
            var result: [DetectedRegion] = []
            result.reserveCapacity(regions.count)

            for region in regions {
                var bestIndex: Int?
                var bestScore = minimumOverlap

                for index in availableIndices where previous[index].type == region.type {
                    let score = Self.intersectionOverUnion(previous[index].box, region.boundingBox)
                    if score >= bestScore {
                        bestScore = score
                        bestIndex = index
                    }
                }

                if let bestIndex {
                    availableIndices.remove(bestIndex)
                    result.append(region.withID(previous[bestIndex].id))
                } else {
                    result.append(region)
                }
            }

            previous = result.map { (id: $0.id, type: $0.type, box: $0.boundingBox) }
            return result
        }

        /// Forgets everything, so a reopened camera does not match against a stale frame.
        mutating func reset() {
            previous.removeAll()
        }

        static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let intersection = a.intersection(b)
            // `CGRect.intersection` returns `.null` for disjoint rects, whose width and height are
            // infinite, not zero. Multiplying those gives infinity rather than 0.
            guard !intersection.isNull, !intersection.isEmpty else { return 0 }

            let intersectionArea = intersection.width * intersection.height
            let unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea
            guard unionArea > 0 else { return 0 }
            return intersectionArea / unionArea
        }
    }
#endif

#if os(iOS)
    /// Carries a skeleton's identity from one frame to the next.
    ///
    /// Same problem and same shape as `RegionIdentityTracker`, for the same reason: `DetectedPose`
    /// used `let id = UUID()` and is rebuilt every frame, so SwiftUI replaced the whole skeleton
    /// view each time and the stable joint and bone ids inside it bought nothing, because their
    /// parent had not survived either.
    ///
    /// Matched on the pose's bounding box. Two people in frame keep their own skeletons as they
    /// move past each other, and a person who leaves and returns gets a new one, which is correct:
    /// interpolating a skeleton across a gap would drag it through space it never occupied.
    struct PoseIdentityTracker {

        private let minimumOverlap: CGFloat
        private var previous: [(id: UUID, isHuman: Bool, box: CGRect)] = []

        init(minimumOverlap: CGFloat = 0.3) {
            self.minimumOverlap = minimumOverlap
        }

        mutating func assigningStableIDs(to poses: [DetectedPose]) -> [DetectedPose] {
            var available = Set(previous.indices)
            var result: [DetectedPose] = []
            result.reserveCapacity(poses.count)

            for pose in poses {
                var bestIndex: Int?
                var bestScore = minimumOverlap

                // A human skeleton never matches an animal one, however much their boxes overlap:
                // a person standing over a dog should not hand the dog their limbs.
                for index in available where previous[index].isHuman == pose.isHuman {
                    let score = RegionIdentityTracker.intersectionOverUnion(previous[index].box, pose.boundingBox)
                    if score >= bestScore {
                        bestScore = score
                        bestIndex = index
                    }
                }

                if let bestIndex {
                    available.remove(bestIndex)
                    result.append(pose.withID(previous[bestIndex].id))
                } else {
                    result.append(pose)
                }
            }

            previous = result.map { (id: $0.id, isHuman: $0.isHuman, box: $0.boundingBox) }
            return result
        }

        mutating func reset() {
            previous.removeAll()
        }
    }
#endif

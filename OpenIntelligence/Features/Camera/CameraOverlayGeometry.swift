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

// Debug builds only (5.7), as are the camera screen and the types this file draws for (`DetectedRegion`,
// `DetectedPose`, `RegionType`): a Release build compiles none of the live camera.
#if os(iOS) && DEBUG
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

        /// The part of a box that can be drawn without covering the screen's controls, or nil when
        /// too little of it is left to be worth drawing.
        ///
        /// **What was wrong before (2026-11-10, the owner's iPhone 16 Pro Max).** Boxes were drawn
        /// at their full converted size over the whole screen, so a saliency box that really is
        /// partly outside the cropped preview ran off the left and bottom edges, a document box
        /// ran up under the navigation bar, and its label sat on top of Cancel and the title.
        /// `viewRect` is right to return a rect that extends past the view; drawing all of it was
        /// the mistake. `visible` is the open camera area between the top controls and the bottom
        /// panels, measured by the screen each layout pass.
        static func clippedRect(_ rect: CGRect, to visible: CGRect, minimumSide: CGFloat = 12) -> CGRect? {
            guard visible.width > 0, visible.height > 0 else { return nil }
            let clipped = rect.intersection(visible)
            guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else {
                return nil
            }
            return clipped
        }

        /// Where a box's label goes, as an offset from the box's own top-left corner.
        ///
        /// Above the box when there is room for it inside `visible`, otherwise just inside the
        /// box's top edge, so a box touching the top bar carries its label inside itself instead
        /// of under the bar. Horizontally it is kept inside `visible`, so a label on a box at the
        /// right edge does not run off the screen.
        static func labelOffset(box: CGRect, visible: CGRect, labelSize: CGSize, inset: CGFloat = 4) -> CGPoint {
            let roomAbove = box.minY - visible.minY
            let y = roomAbove >= labelSize.height + inset ? -(labelSize.height + inset) : inset

            let maxX = visible.maxX - labelSize.width - inset
            let wantedX = box.minX + inset
            let clampedX = max(visible.minX + inset, min(wantedX, maxX))
            return CGPoint(x: clampedX - box.minX, y: y)
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

    // MARK: - Which labels are honest

    /// Decides whether a classification of one crop may be shown as the name of that box.
    ///
    /// **What was wrong before (2026-11-10).** `CameraManager.classify` took the first result
    /// above 0.25 confidence. `ClassifyImageRequest`'s 1,303 identifiers are a hierarchy, and a
    /// parent always scores at least as high as its children, so the top result was usually a
    /// parent or a whole-scene word: the owner's monitor was labelled "Outdoor" (its blue screen
    /// reads as sky), a box over a keyboard "Machine 98%", a screen with text "Document 56%". The
    /// 98% was real and meant nothing, because "this crop contains a machine" is easy to be sure of.
    ///
    /// Two rules now. A result must pass Vision's own high-precision filter
    /// (`hasMinimumRecall(0.01, forPrecision: 0.9)`, Apple's documented pattern), and it must not be
    /// one of the parents or scene words below. The first result that passes both is the name; a
    /// crop with none is not labelled at all. Every word in `nonObjectIdentifiers` was checked
    /// against `ClassifyImageRequest().supportedIdentifiers` on macOS 27 on 2026-11-10.
    nonisolated enum ObjectLabelPolicy {
        static let nonObjectIdentifiers: Set<String> = [
            // Scenes and places: a description of where the camera is, not of a thing in a box.
            "outdoor", "interior_room", "interior_shop", "cityscape", "daytime", "cloudy", "haze",
            "sky", "blue_sky", "night_sky", "land", "water", "liquid", "light", "kitchen_room",
            "living_room", "bedroom", "bathroom_room", "dining_room", "classroom", "conference",
            "cubicle", "restaurant", "structure", "building", "domicile", "road", "road_other", "path",
            // Parents in the hierarchy: always at least as confident as the specific child.
            "machine", "consumer_electronics", "container", "conveyance", "material", "textile",
            "wood_processed", "furniture", "housewares", "appliance", "tool", "office_supplies",
            "people", "adult", "animal", "mammal", "plant", "foliage", "art", "illustrations", "games",
            "recreation", "sport", "music", "media", "performance", "celebration", "decoration",
            "clothing", "headgear", "footwear",
            // Page-like words. A document has its own detector; a screen or a sheet of paper
            // classified as "document" says nothing the dashed document box does not.
            "document", "screenshot", "printed_page", "handwriting",
        ]

        /// The index of the first acceptable result, or nil.
        ///
        /// - Parameter ranked: results in Vision's order (most confident first), each with whether
        ///   it passed the high-precision filter.
        static func acceptedIndex(in ranked: [(identifier: String, passesPrecision: Bool)]) -> Int? {
            ranked.firstIndex(where: { $0.passesPrecision && !nonObjectIdentifiers.contains($0.identifier) })
        }

        /// "computer_keyboard" becomes "Computer Keyboard".
        static func displayName(_ identifier: String) -> String {
            identifier.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Which text is real

    /// Rules for a line of live text, and the debounce that keeps blur from reaching the panel.
    ///
    /// **What was wrong before (2026-11-10).** `performFrameAnalysis` appended every observation
    /// `VNRecognizeTextRequest` returned, at any confidence and any size, and the panel showed
    /// whatever the latest single frame said. An out-of-focus monitor produced "48 ty, November10".
    /// Misreads of blur change from frame to frame; real text read in focus does not. So a line
    /// must pass the per-frame rules and then be seen in `requiredFrames` of the last
    /// `windowFrames` analysed frames before it is shown or captured.
    nonisolated struct LiveTextStabilizer {

        /// `.fast` recognition reports coarse confidences rather than a smooth score (the overlay's
        /// `filteredRegions` notes 0.5 for most lines). 0.5 keeps those and drops anything lower;
        /// the frame-to-frame debounce below does most of the work. Not measured on a device.
        static let minimumConfidence: Float = 0.5

        /// Line height as a fraction of the frame height. 0.012 is about 23 px of a 1920 px
        /// portrait frame: below that the fast recogniser is mostly guessing.
        static let minimumNormalizedHeight: CGFloat = 0.012

        private let windowFrames: Int
        private let requiredFrames: Int
        private var history: [Set<String>] = []

        init(windowFrames: Int = 4, requiredFrames: Int = 3) {
            self.windowFrames = max(1, windowFrames)
            self.requiredFrames = max(1, min(requiredFrames, windowFrames))
        }

        /// Whether one recognised line is worth considering at all.
        static func accepts(text: String, confidence: Float, normalizedHeight: CGFloat) -> Bool {
            guard confidence >= minimumConfidence, normalizedHeight >= minimumNormalizedHeight else {
                return false
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let alphanumerics = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
            // Three letters or digits, and mostly letters or digits: "|||" and ". , ." are not text.
            return alphanumerics >= 3 && Double(alphanumerics) >= Double(trimmed.count) * 0.5
        }

        /// The lines of this frame that have also been seen in enough recent frames, in this
        /// frame's order.
        mutating func stableLines(from lines: [String]) -> [String] {
            let keys = lines.map(Self.key)
            history.append(Set(keys))
            if history.count > windowFrames { history.removeFirst(history.count - windowFrames) }

            var seen = Set<String>()
            var result: [String] = []
            for (line, key) in zip(lines, keys) where !seen.contains(key) {
                let count = history.reduce(0) { $0 + ($1.contains(key) ? 1 : 0) }
                if count >= requiredFrames {
                    seen.insert(key)
                    result.append(line)
                }
            }
            return result
        }

        mutating func reset() {
            history.removeAll()
        }

        /// Case and spacing do not make two reads of a line different.
        static func key(_ line: String) -> String {
            line.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
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

#if os(iOS) && DEBUG
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

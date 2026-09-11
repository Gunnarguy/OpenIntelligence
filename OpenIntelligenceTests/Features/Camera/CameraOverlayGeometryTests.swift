//
//  CameraOverlayGeometryTests.swift
//  OpenIntelligenceTests
//
//  A live camera feed cannot be exercised in a simulator, so the overlay's arithmetic is the only
//  part of that screen that can be verified at all without a phone in hand. That is exactly why it
//  was extracted into pure functions: the defects it replaced were arithmetic defects that shipped
//  for the life of the feature because nothing could see them.
//

import XCTest

@testable import OpenIntelligence

#if os(iOS)

    final class CameraOverlayGeometryTests: XCTestCase {

        // A 1080x1920 portrait buffer on a 393x852 pt screen: the real case on an iPhone held
        // upright, once the capture connection rotates the buffer.
        private let source = CGSize(width: 1080, height: 1920)
        private let view = CGSize(width: 393, height: 852)

        // MARK: - The Y flip

        func testVisionOriginIsLowerLeftAndTheViewOriginIsUpper() {
            // A box hugging the TOP of the Vision frame (maxY == 1) must land at the TOP of the
            // view (y == 0). Getting this backwards is the classic mistake, and the code this
            // replaced actually had it right; the flip was never the bug.
            let topOfFrame = CGRect(x: 0, y: 0.9, width: 1, height: 0.1)
            let rect = CameraOverlayGeometry.viewRect(
                normalized: topOfFrame, sourceSize: source, viewSize: view
            )
            XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
        }

        func testABoxAtTheBottomOfVisionSpaceLandsAtTheBottomOfTheView() {
            let bottomOfFrame = CGRect(x: 0, y: 0, width: 1, height: 0.1)
            let rect = CameraOverlayGeometry.viewRect(
                normalized: bottomOfFrame, sourceSize: source, viewSize: view
            )
            XCTAssertEqual(rect.maxY, view.height, accuracy: 0.001)
        }

        // MARK: - The aspect-fill crop, which is what was actually broken

        func testAFullFrameDetectionCoversAtLeastTheWholeView() {
            // `.resizeAspectFill` guarantees the image covers the view. So a detection spanning the
            // entire image must produce a rect that covers the entire view, spilling outside it on
            // the cropped axis rather than sitting inside it.
            let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
            let rect = CameraOverlayGeometry.viewRect(
                normalized: whole, sourceSize: source, viewSize: view
            )
            XCTAssertLessThanOrEqual(rect.minX, 0.001)
            XCTAssertLessThanOrEqual(rect.minY, 0.001)
            XCTAssertGreaterThanOrEqual(rect.maxX, view.width - 0.001)
            XCTAssertGreaterThanOrEqual(rect.maxY, view.height - 0.001)
        }

        func testTheCenterOfTheImageIsTheCenterOfTheView() {
            // Aspect-fill crops symmetrically, so the image centre and the view centre coincide
            // whatever the aspect mismatch. This is the invariant the old code happened to satisfy,
            // which is why boxes near the middle looked almost right and boxes near the edges did
            // not, and why the bug read as "sometimes wrong" rather than "always wrong".
            let centre = CGRect(x: 0.5, y: 0.5, width: 0, height: 0)
            let rect = CameraOverlayGeometry.viewRect(
                normalized: centre, sourceSize: source, viewSize: view
            )
            XCTAssertEqual(rect.minX, view.width / 2, accuracy: 0.001)
            XCTAssertEqual(rect.minY, view.height / 2, accuracy: 0.001)
        }

        func testTheOldNaiveTransformDisagreesAwayFromTheCentre() {
            // Pins the actual defect rather than just the fix. The replaced code was
            // `x = minX * viewWidth`. At the left edge of a 16:9 buffer shown on a taller screen,
            // that lands at 0 while the truth is off-screen to the left, because the image is wider
            // than the view and is cropped. If these two ever agree, the aspect compensation has
            // been silently removed again.
            let wide = CGSize(width: 1920, height: 1080)
            let tallView = CGSize(width: 393, height: 852)
            let leftEdge = CGRect(x: 0, y: 0.4, width: 0.1, height: 0.1)

            let correct = CameraOverlayGeometry.viewRect(
                normalized: leftEdge, sourceSize: wide, viewSize: tallView
            )
            let naive = leftEdge.minX * tallView.width

            XCTAssertEqual(naive, 0, accuracy: 0.001)
            XCTAssertLessThan(
                correct.minX, -1,
                "a detection at the left edge of a cropped-wide image belongs off-screen"
            )
        }

        // MARK: - Degenerate input must not reach SwiftUI

        func testAZeroSourceSizeReturnsZeroRatherThanNaN() {
            // `sourceSize` is `.zero` until the first frame arrives. Dividing by it would produce
            // NaN or infinity, and a non-finite value in a SwiftUI frame aborts the app rather than
            // drawing wrong. This app has already shipped that crash once, from the Silicon HUD.
            let rect = CameraOverlayGeometry.viewRect(
                normalized: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                sourceSize: .zero,
                viewSize: view
            )
            XCTAssertEqual(rect, .zero)
            XCTAssertTrue(rect.origin.x.isFinite)
            XCTAssertTrue(rect.size.width.isFinite)
        }

        func testAZeroViewSizeReturnsZero() {
            let rect = CameraOverlayGeometry.viewRect(
                normalized: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                sourceSize: source,
                viewSize: .zero
            )
            XCTAssertEqual(rect, .zero)
        }

        // MARK: - Identity, which is what stopped the boxes strobing

        func testAStationaryDetectionKeepsItsIdentityAcrossFrames() {
            // The whole point. If the id changes, SwiftUI replaces the view instead of moving it,
            // and no animation in that file can run.
            var tracker = RegionIdentityTracker()
            let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)

            let first = tracker.assigningStableIDs(to: [
                DetectedRegion(type: .text, boundingBox: box, confidence: 0.9)
            ])
            let second = tracker.assigningStableIDs(to: [
                DetectedRegion(type: .text, boundingBox: box, confidence: 0.9)
            ])

            XCTAssertEqual(first[0].id, second[0].id)
        }

        func testADetectionThatMovesSlightlyIsStillTheSameThing() {
            var tracker = RegionIdentityTracker()
            let first = tracker.assigningStableIDs(to: [
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    confidence: 0.9)
            ])
            let second = tracker.assigningStableIDs(to: [
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.12, y: 0.11, width: 0.2, height: 0.2),
                    confidence: 0.9)
            ])

            XCTAssertEqual(first[0].id, second[0].id, "a small movement between frames is tracking, not a new object")
        }

        func testADetectionAcrossTheFrameIsADifferentThing() {
            // The failure that matters more than a missed match: a wrong match drags a box across
            // the screen, which reads far worse than one frame without animation.
            var tracker = RegionIdentityTracker()
            let first = tracker.assigningStableIDs(to: [
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                    confidence: 0.9)
            ])
            let second = tracker.assigningStableIDs(to: [
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2),
                    confidence: 0.9)
            ])

            XCTAssertNotEqual(first[0].id, second[0].id)
        }

        func testTypesDoNotBorrowEachOthersIdentity() {
            // A face and a text box can overlap almost exactly. They are not the same detection and
            // must not swap ids, or a face silhouette would morph into a text capsule.
            var tracker = RegionIdentityTracker()
            let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)

            let first = tracker.assigningStableIDs(to: [
                DetectedRegion(type: .face, boundingBox: box, confidence: 0.9)
            ])
            let second = tracker.assigningStableIDs(to: [
                DetectedRegion(type: .text, boundingBox: box, confidence: 0.9)
            ])

            XCTAssertNotEqual(first[0].id, second[0].id)
        }

        func testOnePreviousDetectionCannotClaimTwoNewOnes() {
            // Greedy matching must consume a match. Without the `availableIndices` bookkeeping, one
            // previous box would hand the same id to every overlapping new box, and SwiftUI would
            // see duplicate ids in a ForEach, which is undefined behaviour.
            var tracker = RegionIdentityTracker()
            _ = tracker.assigningStableIDs(to: [
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
                    confidence: 0.9)
            ])

            let second = tracker.assigningStableIDs(to: [
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
                    confidence: 0.9),
                DetectedRegion(
                    type: .text, boundingBox: CGRect(x: 0.11, y: 0.11, width: 0.3, height: 0.3),
                    confidence: 0.9),
            ])

            XCTAssertEqual(Set(second.map(\.id)).count, 2, "ForEach ids must be unique")
        }

        func testResetForgetsThePreviousFrame() {
            var tracker = RegionIdentityTracker()
            let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
            let first = tracker.assigningStableIDs(to: [
                DetectedRegion(type: .text, boundingBox: box, confidence: 0.9)
            ])
            tracker.reset()
            let second = tracker.assigningStableIDs(to: [
                DetectedRegion(type: .text, boundingBox: box, confidence: 0.9)
            ])

            XCTAssertNotEqual(first[0].id, second[0].id)
        }

        func testDisjointRectsScoreZeroRatherThanInfinity() {
            // `CGRect.intersection` returns `.null` for disjoint rects, and `.null` has INFINITE
            // width and height, not zero. Multiplying those gives infinity, and an infinite overlap
            // score would match every box to every other box.
            let score = RegionIdentityTracker.intersectionOverUnion(
                CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
                CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)
            )
            XCTAssertEqual(score, 0)
            XCTAssertTrue(score.isFinite)
        }

        func testIdenticalRectsScoreOne() {
            let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
            XCTAssertEqual(RegionIdentityTracker.intersectionOverUnion(box, box), 1, accuracy: 0.0001)
        }
    }

#endif

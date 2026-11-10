//
//  CameraOverlayHonestyTests.swift
//  OpenIntelligenceTests
//
//  The rules added on 2026-11-10 after the owner's iPhone 16 Pro Max showed boxes running off the
//  screen and under the title, a monitor labelled "Outdoor", a keyboard labelled "Machine 98%",
//  and blur read as "48 ty, November10". A live camera cannot run in a test, so these check the
//  pure parts: where a box and its label may be drawn, which classification may name a box, and
//  which recognised text may be shown.
//

import XCTest

@testable import OpenIntelligence

// Debug builds only, as is the camera code these tests check.
#if os(iOS) && DEBUG

    final class CameraOverlayHonestyTests: XCTestCase {

        // iPhone 16 Pro Max in portrait: 440x956 pt, and a 1080x1920 frame once the capture
        // connection has rotated it upright.
        private let source = CGSize(width: 1080, height: 1920)
        private let screen = CGSize(width: 440, height: 956)
        // The open camera area between the top controls and the bottom card.
        private let open = CGRect(x: 0, y: 120, width: 440, height: 600)

        // MARK: - Clipping to the open camera area

        func testABoxThatSpillsPastTheLeftEdgeIsClippedToTheScreen() {
            // A box starting at the left edge of the frame begins off screen, because aspect fill
            // crops about 49 pt from each side of a 1080x1920 frame on this screen.
            let full = CameraOverlayGeometry.viewRect(
                normalized: CGRect(x: 0, y: 0.3, width: 0.5, height: 0.3),
                sourceSize: source,
                viewSize: screen
            )
            XCTAssertLessThan(full.minX, 0, "precondition: aspect fill puts the frame's left edge off screen")

            let drawn = CameraOverlayGeometry.clippedRect(full, to: open)
            XCTAssertEqual(drawn?.minX ?? -1, open.minX, accuracy: 0.001)
            XCTAssertEqual(drawn?.maxX ?? -1, full.maxX, accuracy: 0.001)
        }

        func testABoxThatRunsUnderTheTitleAndTheBottomCardIsClippedToTheOpenArea() {
            // A document box covering the top of the frame used to run up under Cancel.
            let full = CameraOverlayGeometry.viewRect(
                normalized: CGRect(x: 0.05, y: 0.2, width: 0.9, height: 0.8),
                sourceSize: source,
                viewSize: screen
            )
            XCTAssertLessThan(full.minY, open.minY, "precondition: the box reaches the top bar")
            XCTAssertGreaterThan(full.maxY, open.maxY, "precondition: the box reaches the bottom card")

            let drawn = CameraOverlayGeometry.clippedRect(full, to: open)
            XCTAssertEqual(drawn?.minY ?? -1, open.minY, accuracy: 0.001)
            XCTAssertEqual(drawn?.maxY ?? -1, open.maxY, accuracy: 0.001)
        }

        func testABoxEntirelyUnderTheTopBarIsNotDrawn() {
            let full = CGRect(x: 20, y: 10, width: 100, height: 80)
            XCTAssertNil(CameraOverlayGeometry.clippedRect(full, to: open))
        }

        func testASliverLeftAfterClippingIsNotDrawn() {
            // Only 6 pt of this box is inside the open area.
            let full = CGRect(x: 20, y: 40, width: 100, height: 86)
            XCTAssertNil(CameraOverlayGeometry.clippedRect(full, to: open))
        }

        /// A box clipped to an empty area is dropped. The view clips to the whole screen until the open area is measured.
        func testABoxClippedToAnEmptyAreaIsDropped() {
            XCTAssertNil(CameraOverlayGeometry.clippedRect(CGRect(x: 0, y: 0, width: 50, height: 50), to: .zero))
        }

        // MARK: - Label placement

        private let label = CGSize(width: 80, height: 20)

        func testALabelGoesAboveABoxWhenThereIsRoom() {
            let box = CGRect(x: 100, y: 300, width: 200, height: 100)
            let offset = CameraOverlayGeometry.labelOffset(box: box, visible: open, labelSize: label)
            XCTAssertEqual(offset.y, -24, accuracy: 0.001)
            XCTAssertEqual(offset.x, 4, accuracy: 0.001)
        }

        func testALabelGoesInsideABoxThatTouchesTheTopBar() {
            // Above would put it under the top controls, which is where "Machine 98%" ended up.
            let box = CGRect(x: 100, y: 130, width: 200, height: 100)
            let offset = CameraOverlayGeometry.labelOffset(box: box, visible: open, labelSize: label)
            XCTAssertEqual(offset.y, 4, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(box.minY + offset.y, open.minY)
        }

        func testALabelOnABoxAtTheRightEdgeStaysOnScreen() {
            let box = CGRect(x: 400, y: 300, width: 40, height: 40)
            let offset = CameraOverlayGeometry.labelOffset(box: box, visible: open, labelSize: label)
            XCTAssertLessThanOrEqual(box.minX + offset.x + label.width, open.maxX)
            XCTAssertEqual(offset.x, -44, accuracy: 0.001)
        }

        func testALabelOnABoxStartingLeftOfTheScreenStaysOnScreen() {
            let box = CGRect(x: -50, y: 300, width: 200, height: 100)
            let offset = CameraOverlayGeometry.labelOffset(box: box, visible: open, labelSize: label)
            XCTAssertEqual(box.minX + offset.x, open.minX + 4, accuracy: 0.001)
        }

        // MARK: - Which classification may name a box

        func testAParentCategoryDoesNotNameABoxWhenASpecificChildPasses() {
            // Vision's order: parents first, because a parent is always at least as confident.
            let ranked: [(identifier: String, passesPrecision: Bool)] = [
                ("machine", true),
                ("consumer_electronics", true),
                ("computer_keyboard", true),
            ]
            XCTAssertEqual(ObjectLabelPolicy.acceptedIndex(in: ranked), 2)
            XCTAssertEqual(ObjectLabelPolicy.displayName(ranked[2].identifier), "Computer Keyboard")
        }

        func testASceneWordNeverNamesABox() {
            // The owner's blue monitor screen was labelled "Outdoor".
            let ranked: [(identifier: String, passesPrecision: Bool)] = [
                ("outdoor", true), ("sky", true), ("blue_sky", true), ("document", true),
            ]
            XCTAssertNil(ObjectLabelPolicy.acceptedIndex(in: ranked))
        }

        func testAResultThatFailsThePrecisionFilterIsSkipped() {
            let ranked: [(identifier: String, passesPrecision: Bool)] = [
                ("computer_monitor", false),
                ("television", true),
            ]
            XCTAssertEqual(ObjectLabelPolicy.acceptedIndex(in: ranked), 1)
        }

        func testNothingPassingMeansNoLabel() {
            let ranked: [(identifier: String, passesPrecision: Bool)] = [
                ("computer_monitor", false), ("printer", false),
            ]
            XCTAssertNil(ObjectLabelPolicy.acceptedIndex(in: ranked))
        }

        // MARK: - Which text may be shown

        func testAClearLineIsAccepted() {
            XCTAssertTrue(LiveTextStabilizer.accepts(text: "Invoice 2041", confidence: 1.0, normalizedHeight: 0.03))
        }

        func testLowConfidenceTinyOrSymbolOnlyLinesAreRejected() {
            XCTAssertFalse(LiveTextStabilizer.accepts(text: "Invoice 2041", confidence: 0.3, normalizedHeight: 0.03))
            XCTAssertFalse(LiveTextStabilizer.accepts(text: "Invoice 2041", confidence: 1.0, normalizedHeight: 0.005))
            XCTAssertFalse(LiveTextStabilizer.accepts(text: "|||", confidence: 1.0, normalizedHeight: 0.03))
            XCTAssertFalse(LiveTextStabilizer.accepts(text: "ab", confidence: 1.0, normalizedHeight: 0.03))
            XCTAssertFalse(LiveTextStabilizer.accepts(text: ". , . a", confidence: 1.0, normalizedHeight: 0.03))
        }

        func testALineIsShownOnlyAfterItRepeatsAcrossFrames() {
            var stabilizer = LiveTextStabilizer(windowFrames: 4, requiredFrames: 3)
            XCTAssertEqual(stabilizer.stableLines(from: ["Monday, November 10"]), [])
            XCTAssertEqual(stabilizer.stableLines(from: ["Monday, November 10"]), [])
            XCTAssertEqual(stabilizer.stableLines(from: ["Monday, November 10"]), ["Monday, November 10"])
        }

        func testBlurThatReadsDifferentlyEachFrameIsNeverShown() {
            var stabilizer = LiveTextStabilizer(windowFrames: 4, requiredFrames: 3)
            for reading in ["48 ty, November10", "4B tv, Novenber10", "48 tv Nouember1O", "AB ty, Nwember10"] {
                XCTAssertEqual(stabilizer.stableLines(from: [reading]), [], "shown: \(reading)")
            }
        }

        func testCaseAndSpacingDoNotBreakTheMatch() {
            var stabilizer = LiveTextStabilizer(windowFrames: 4, requiredFrames: 3)
            _ = stabilizer.stableLines(from: ["Hello  World"])
            _ = stabilizer.stableLines(from: ["hello world"])
            XCTAssertEqual(stabilizer.stableLines(from: ["HELLO WORLD"]), ["HELLO WORLD"])
        }

        func testALineThatLeavesForTooLongIsDropped() {
            var stabilizer = LiveTextStabilizer(windowFrames: 4, requiredFrames: 3)
            for _ in 0..<3 { _ = stabilizer.stableLines(from: ["Total 12.40"]) }
            _ = stabilizer.stableLines(from: [])
            _ = stabilizer.stableLines(from: [])
            // Only one of the last four frames held it now.
            XCTAssertEqual(stabilizer.stableLines(from: ["Total 12.40"]), [])
        }

        func testResetForgetsHistory() {
            var stabilizer = LiveTextStabilizer(windowFrames: 4, requiredFrames: 3)
            for _ in 0..<3 { _ = stabilizer.stableLines(from: ["Total 12.40"]) }
            stabilizer.reset()
            XCTAssertEqual(stabilizer.stableLines(from: ["Total 12.40"]), [])
        }
    }

#endif

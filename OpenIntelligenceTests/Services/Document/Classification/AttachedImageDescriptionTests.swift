//
//  AttachedImageDescriptionTests.swift
//  OpenIntelligenceTests
//
//  From 5.7, on iOS 27 and macOS 27, the import shows a picture to the on-device model when it asks
//  for a description of it. The model call cannot run in the simulator. These pin the two parts that
//  can: what size of image is handed over, and what the model is asked.
//

import CoreImage
import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class AttachedImageDescriptionTests: XCTestCase {
    private func image(width: CGFloat, height: CGFloat) -> CIImage {
        CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testALargeImageIsScaledDownToTheLimitOnItsLongestSide() throws {
        let scaled = try XCTUnwrap(ImageUnderstandingService.imageSizedForModel(image(width: 3000, height: 2000)))
        XCTAssertEqual(scaled.extent.width, 1024, accuracy: 1)
        XCTAssertEqual(scaled.extent.height, 683, accuracy: 1)

        let tall = try XCTUnwrap(ImageUnderstandingService.imageSizedForModel(image(width: 800, height: 4096)))
        XCTAssertEqual(tall.extent.height, 1024, accuracy: 1)
        XCTAssertEqual(tall.extent.width, 200, accuracy: 1)
    }

    func testAnImageWithinTheLimitIsHandedOverAsItIs() throws {
        let original = image(width: 640, height: 420)
        let sized = try XCTUnwrap(ImageUnderstandingService.imageSizedForModel(original))
        XCTAssertEqual(sized.extent, original.extent)
    }

    /// The shorter side is tested after scaling: a wide strip that scales down to a sliver keeps
    /// its text-only description.
    func testAStripThatScalesToASliverIsNotHandedOver() {
        XCTAssertNil(ImageUnderstandingService.imageSizedForModel(image(width: 2550, height: 200)))
        XCTAssertNotNil(ImageUnderstandingService.imageSizedForModel(image(width: 2550, height: 300)))
    }

    func testAnImageCutFromAPageIsMovedToTheOrigin() throws {
        let cut = CIImage(color: .gray).cropped(to: CGRect(x: 300, y: 1200, width: 640, height: 420))
        let sized = try XCTUnwrap(ImageUnderstandingService.imageSizedForModel(cut))
        XCTAssertEqual(sized.extent, CGRect(x: 0, y: 0, width: 640, height: 420))
    }

    func testAnIconOrAnImageWithNoSizeIsNotHandedOver() {
        XCTAssertNil(ImageUnderstandingService.imageSizedForModel(image(width: 48, height: 48)))
        XCTAssertNil(ImageUnderstandingService.imageSizedForModel(image(width: 800, height: 40)))
        XCTAssertNil(ImageUnderstandingService.imageSizedForModel(CIImage(color: .gray)), "an unbounded image")
        XCTAssertNil(ImageUnderstandingService.imageSizedForModel(CIImage.empty()))
    }

    func testThePromptCarriesThePagesNotesAndSaysTheImageDecides() {
        let prompt = ImageUnderstandingService.attachedImagePrompt(
            extractedText: "Units shipped per year 120 200 290",
            caption: "Figure 3. Shipments",
            precedingContext: "Shipments rose each year.",
            followingContext: nil
        )
        XCTAssertTrue(prompt.contains("which is attached"))
        XCTAssertTrue(prompt.contains("State only what is visible"))
        XCTAssertTrue(prompt.contains("only where they agree with the image"))
        XCTAssertTrue(prompt.contains("Caption on the page: Figure 3. Shipments"))
        XCTAssertTrue(prompt.contains("Text recognised in the image: Units shipped per year 120 200 290"))
        XCTAssertTrue(prompt.contains("Text before it on the page: Shipments rose each year."))
        XCTAssertFalse(prompt.contains("Text after it on the page"))
    }

    func testWithNoNotesThePromptHasNoNotesSection() {
        let prompt = ImageUnderstandingService.attachedImagePrompt(
            extractedText: nil, caption: "", precedingContext: nil, followingContext: nil)
        XCTAssertFalse(prompt.contains("Notes from the page"))
    }

    func testLongRecognisedTextIsCut() {
        let long = String(repeating: "x", count: 2_000)
        let prompt = ImageUnderstandingService.attachedImagePrompt(
            extractedText: long, caption: nil, precedingContext: nil, followingContext: nil)
        XCTAssertTrue(prompt.contains(String(repeating: "x", count: 500)))
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: 501)))
    }
}

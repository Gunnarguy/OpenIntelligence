//
//  ImageCodeReadingTests.swift
//  OpenIntelligenceTests
//
//  A barcode or QR code in a picture is read by Vision, and its contents go first in the picture's text, where a
//  search finds them and the model is given them (5.7, `ImageUnderstandingService.readCodes`). Shown a QR code
//  without them, the on-device model wrote a link the code did not hold (measured on the Mac on 2026-10-15). Vision
//  cannot create its barcode reader in the iOS Simulator, so the reading itself is checked only on a device or
//  the Mac; here the reading skips.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest

@testable import OpenIntelligence

final class ImageCodeReadingTests: XCTestCase {
    func testTheCodesGoFirstInThePicturesText() {
        let reading = ImageUnderstandingService.CodeReading.read(["QR code: https://example.com/manual/X-200"])
        XCTAssertEqual(
            ImageUnderstandingService.textWithCodes("Model X-200 quick start", reading: reading),
            "QR code: https://example.com/manual/X-200\nModel X-200 quick start")
        XCTAssertEqual(
            ImageUnderstandingService.textWithCodes(nil, reading: reading), "QR code: https://example.com/manual/X-200")
        XCTAssertEqual(ImageUnderstandingService.textWithCodes("Text", reading: .read([])), "Text")
        XCTAssertEqual(ImageUnderstandingService.textWithCodes("Text", reading: .unavailable), "Text")
    }

    func testThePromptNeverLeavesACodeToTheModelsEye() {
        let plain = ImageUnderstandingService.attachedImagePrompt(
            extractedText: "QR code: https://example.com/manual/X-200", caption: nil, precedingContext: nil,
            followingContext: nil)
        XCTAssertTrue(plain.contains("Never write what a barcode or QR code holds unless the notes list it."))
        XCTAssertTrue(plain.contains("QR code: https://example.com/manual/X-200"))

        let withTools = ImageUnderstandingService.attachedImagePrompt(
            extractedText: nil, caption: nil, precedingContext: nil, followingContext: nil, toolsOffered: true)
        XCTAssertTrue(withTools.contains("readBarcodes"))
        XCTAssertTrue(withTools.contains("passing the label \(ImageUnderstandingService.attachedImageLabel)"))
        XCTAssertTrue(withTools.contains("Never guess what a code holds."))
    }

    func testCodeKinds() {
        XCTAssertEqual(ImageUnderstandingService.codeKind(.qr), "QR code")
        XCTAssertEqual(ImageUnderstandingService.codeKind(.microQR), "QR code")
        XCTAssertEqual(ImageUnderstandingService.codeKind(.ean13), "Barcode")
    }

    func testVisionReadsAQRCode() async throws {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data("https://example.com/manual/X-200".utf8)
        let code = try XCTUnwrap(qr.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let canvas = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = code.transformed(by: CGAffineTransform(translationX: 40, y: 40)).composited(over: canvas)

        let reading = await ImageUnderstandingService.readCodes(in: image)
        if reading == .unavailable {
            throw XCTSkip("Vision cannot create its barcode reader in the iOS Simulator")
        }
        XCTAssertEqual(reading, .read(["QR code: https://example.com/manual/X-200"]))
    }
}

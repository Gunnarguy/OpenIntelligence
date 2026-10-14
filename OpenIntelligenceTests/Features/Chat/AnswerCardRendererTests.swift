//
//  AnswerCardRendererTests.swift
//  OpenIntelligenceTests
//
//  Share as Image (5.7): the answer drawn with its sources and a code for the App Store page.
//  These pin where a long answer is cut, that the picture comes out at the card's width and
//  scale, and that the code holds the tagged App Store link.
//

import CoreImage
import XCTest

@testable import OpenIntelligence

@MainActor
final class AnswerCardRendererTests: XCTestCase {
    func testAShortAnswerIsKeptWhole() {
        XCTAssertEqual(AnswerCardRenderer.cardText("  The deposit comes back within 60 days.  "), "The deposit comes back within 60 days.")
    }

    func testALongAnswerIsCutAtASentenceOrAWord() {
        let sentence = "The deposit comes back within sixty days of the lease ending. "
        let long = String(repeating: sentence, count: 30)
        let card = AnswerCardRenderer.cardText(long, limit: 200)
        XCTAssertLessThanOrEqual(card.count, 202)
        XCTAssertTrue(card.hasSuffix("ending. …"), card)

        let words = String(repeating: "word ", count: 100)
        let cut = AnswerCardRenderer.cardText(words, limit: 51)
        XCTAssertTrue(cut.hasSuffix("word…"), cut)
        XCTAssertLessThanOrEqual(cut.count, 51)
    }

    func testTheCardIsDrawnAtItsWidthAndScale() throws {
        let view = AnswerCardView(
            answer: "The deposit comes back within **60 days** [S1].",
            sources: [AnswerShareFormatter.Source(label: "S1", document: "Lease.pdf", pages: [4])],
            moreSources: 2,
            code: AnswerCardRenderer.qrCode(for: OpenIntelligenceLinks.sharedAppStoreURL))
        let data = try XCTUnwrap(AnswerCardRenderer.pngData(of: view))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(CGFloat(image.width), AnswerCardRenderer.width * AnswerCardRenderer.scale)
        XCTAssertGreaterThan(image.height, image.width / 3, "the answer, the source and the footer take room")
    }

    func testTheCodeHoldsTheTaggedAppStoreLink() throws {
        let url = OpenIntelligenceLinks.sharedAppStoreURL
        let code = try XCTUnwrap(AnswerCardRenderer.qrCode(for: url))
        let detector = try XCTUnwrap(
            CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        // Scale the one-pixel modules up so the detector can read them.
        let scaled = CIImage(cgImage: code).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let messages = detector.features(in: scaled).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(messages, [url.absoluteString])
        XCTAssertTrue(url.absoluteString.contains("ct=\(OpenIntelligenceLinks.shareCampaignTag)"))
    }
}

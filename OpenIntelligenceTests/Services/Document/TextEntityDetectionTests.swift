//
//  TextEntityDetectionTests.swift
//  OpenIntelligenceTests
//
//  Apple's data detector reads a document's text, not only table cells (5.7,
//  `StructuredDocumentParser.detectedEntities(inText:characterLimit:)`). The sentence is the one
//  measured on the Mac on 2026-10-14, where the detector found two phone numbers, a postal address,
//  an amount, a flight number, a link and a date in it. Not covered: a whole PDF on a device.
//

import XCTest

@testable import OpenIntelligence

final class TextEntityDetectionTests: XCTestCase {
    private let sentence =
        "Call us at +44 20 7946 0958 or (555) 123-4567, write to 1 Infinite Loop, Cupertino, CA 95014, "
        + "pay €59.99 by 12 March 2026, flight UA 857, see https://example.com."

    func testAParagraphsAddressesPhonesAndAmountsAreFound() async {
        let found = await StructuredDocumentParser.detectedEntities(inText: sentence, characterLimit: 10_000)
        let types = Set(found.map(\.type))
        XCTAssertTrue(types.contains(.phoneNumber), "\(found)")
        XCTAssertTrue(types.contains(.address), "\(found)")
        XCTAssertTrue(types.contains(.url), "\(found)")
        XCTAssertTrue(types.contains(.money), "\(found)")
    }

    func testOnlyTheFirstCharactersAreRead() async {
        let found = await StructuredDocumentParser.detectedEntities(inText: "No numbers here. " + sentence, characterLimit: 17)
        XCTAssertTrue(found.isEmpty, "\(found)")
    }

    @MainActor
    func testTheTextsEntitiesJoinTheCellsWithoutRepeats() {
        let processor = DocumentProcessor()
        let link = DetectedEntity(type: .url, value: "https://example.com", rawText: "https://example.com")
        processor.mergeDetectedEntities([link, link])
        XCTAssertEqual(processor.lastDetectedEntities.filter { $0.value == "https://example.com" }.count, 1)
    }
}

import XCTest
@testable import OpenIntelligenceEngine

final class RetrievalConfigTests: XCTestCase {

    func testRecommendedConfig_EmptyTypes() {
        let config = RetrievalConfig.recommended(forDocumentTypes: [])
        XCTAssertTrue(config.isCloseTo(.default))
    }

    func testRecommendedConfig_CodeHeavy_Majority() {
        // total 3, code 2 (> 3/2 = 1)
        let types: [DocumentType] = [.swift, .python, .pdf]
        let config = RetrievalConfig.recommended(forDocumentTypes: types)
        XCTAssertTrue(config.isCloseTo(.technicalManual))
    }

    func testRecommendedConfig_StructuredDataHeavy_MeetsThreshold() {
        // total 3, structured 2. structuredDataCount >= 2 (True) && 2 * 3 (6) >= 3 * 2 (6) (True)
        let types: [DocumentType] = [.csv, .excel, .pdf]
        let config = RetrievalConfig.recommended(forDocumentTypes: types)
        XCTAssertTrue(config.isCloseTo(.technicalManual))
    }

    func testRecommendedConfig_StructuredData_BelowMinimumCount() {
        // total 1, structured 1. structuredDataCount >= 2 (False)
        let types: [DocumentType] = [.csv]
        let config = RetrievalConfig.recommended(forDocumentTypes: types)
        XCTAssertTrue(config.isCloseTo(.default))
    }

    func testRecommendedConfig_NarrativeHeavy() {
        // total 3, narrative 2
        let types: [DocumentType] = [.pdf, .markdown, .swift]
        let config = RetrievalConfig.recommended(forDocumentTypes: types)
        XCTAssertTrue(config.isCloseTo(.default))
    }

    func testRecommendedConfig_MixedCorpus_Fallback() {
        // total 4: code 2, structured 1, narrative 1.
        // code 2 > 2 (False)
        // structured 1 >= 2 (False)
        // narrative 1 >= 2 (False)
        // Falls through to final return .default
        let types: [DocumentType] = [.swift, .python, .csv, .pdf]
        let config = RetrievalConfig.recommended(forDocumentTypes: types)
        XCTAssertTrue(config.isCloseTo(.default))
    }

    func testRecommendedConfig_AudioVideoAreNarrative() {
        let types: [DocumentType] = [.audio, .video, .mp3]
        let config = RetrievalConfig.recommended(forDocumentTypes: types)
        XCTAssertTrue(config.isCloseTo(.default))
    }
}

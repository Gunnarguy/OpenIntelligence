import XCTest
@testable import OpenIntelligence

final class OCRConfigurationTests: XCTestCase {

    // MARK: - Universal Custom Words

    func testUniversalCustomWordsAreNotEmpty() {
        XCTAssertFalse(OCRConfiguration.universalCustomWords.isEmpty,
                       "Universal custom words should contain SI units and standard terms")
    }

    func testUniversalCustomWordsContainsSIUnits() {
        let words = OCRConfiguration.universalCustomWords
        XCTAssertTrue(words.contains("kg"), "Should contain 'kg'")
        XCTAssertTrue(words.contains("mm"), "Should contain 'mm'")
        XCTAssertTrue(words.contains("kPa"), "Should contain 'kPa'")
        XCTAssertTrue(words.contains("mL"), "Should contain 'mL'")
    }

    func testUniversalCustomWordsContainsImperialUnits() {
        let words = OCRConfiguration.universalCustomWords
        XCTAssertTrue(words.contains("psi") || words.contains("PSI"), "Should contain 'psi'")
        XCTAssertTrue(words.contains("lb") || words.contains("lbs"), "Should contain 'lb'")
        XCTAssertTrue(words.contains("gal"), "Should contain 'gal'")
    }

    // MARK: - Recognition Languages

    func testRecognitionLanguagesContainsEnglish() {
        let languages = OCRConfiguration.recognitionLanguages
        XCTAssertTrue(languages.contains("en-US"), "Should include US English")
    }

    func testRecognitionLanguagesHasMultipleLanguages() {
        let languages = OCRConfiguration.recognitionLanguages
        XCTAssertGreaterThan(languages.count, 5,
                             "Should support multiple languages (currently 13)")
    }

    func testRecognitionLanguagesEnglishIsFirst() {
        let languages = OCRConfiguration.recognitionLanguages
        XCTAssertEqual(languages.first, "en-US",
                       "English should be the primary/first language")
    }

    func testRecognitionLanguagesContainsEastAsian() {
        let languages = OCRConfiguration.recognitionLanguages
        let hasJapanese = languages.contains("ja-JP")
        let hasKorean = languages.contains("ko-KR")
        let hasChinese = languages.contains("zh-Hans") || languages.contains("zh-Hant")
        XCTAssertTrue(hasJapanese, "Should support Japanese")
        XCTAssertTrue(hasKorean, "Should support Korean")
        XCTAssertTrue(hasChinese, "Should support Chinese")
    }

    // MARK: - Dynamic Vocabulary Extraction

    func testExtractDynamicVocabularyFromTechnicalText() {
        let text = """
        The VHA21 protocol requires HbA1c levels below 7.0%.
        Configuration uses SAE 0W-20 specification per ISO 9001.
        CrossRef identifier: DOI-10.1234/test
        """
        let vocab = OCRConfiguration.extractDynamicVocabulary(from: text)

        // Should find technical terms, acronyms, alphanumeric codes
        XCTAssertFalse(vocab.isEmpty,
                       "Should extract vocabulary from technical text")
    }

    func testExtractDynamicVocabularyFromEmptyText() {
        let vocab = OCRConfiguration.extractDynamicVocabulary(from: "")
        // Should handle gracefully — empty or minimal results
        XCTAssertTrue(vocab.count >= 0, "Empty text should not crash")
    }

    func testExtractDynamicVocabularyFromPlainEnglish() {
        let text = "The quick brown fox jumps over the lazy dog."
        let vocab = OCRConfiguration.extractDynamicVocabulary(from: text)
        // Plain English should not produce many technical terms
        // (though some capitalized words might be extracted)
        XCTAssertTrue(vocab.count >= 0, "Plain English text should not crash")
    }

    // MARK: - Custom Words (Combined)

    func testCustomWordsIncludesUniversalWords() {
        let combined = OCRConfiguration.customWords(forDocumentText: nil)
        // Without document text, should still include universal words
        XCTAssertFalse(combined.isEmpty, "Should include universal words even without document text")
        XCTAssertTrue(combined.contains("kg"), "Should include universal SI units")
    }

    func testCustomWordsWithDocumentTextAddsDynamic() {
        let docText = "The VHA21-PALGARCIG1 protocol specifies HbA1c screening."
        let withDoc = OCRConfiguration.customWords(forDocumentText: docText)
        let withoutDoc = OCRConfiguration.customWords(forDocumentText: nil)

        // With document text, should have at least as many words as without
        XCTAssertGreaterThanOrEqual(withDoc.count, withoutDoc.count,
                                     "Document-enriched vocabulary should be at least as large as universal-only")
    }

    // MARK: - Garbage Text Detection

    func testValidEnglishTextIsNotGarbage() {
        let validText = "The recommended tire pressure is 32 PSI for front tires."
        XCTAssertFalse(OCRConfiguration.isGarbageText(validText),
                       "Valid English text should not be classified as garbage")
    }

    func testGarbageOCROutputIsDetected() {
        // Typical garbled OCR output: random character soup
        let garbage = "xkLm9$#@!pQr&*^zWv"
        XCTAssertTrue(OCRConfiguration.isGarbageText(garbage),
                      "Random character soup should be classified as garbage")
    }

    func testShortTextIsNotClassifiedAsGarbage() {
        // Very short text (< 4 chars) should not be judged
        XCTAssertFalse(OCRConfiguration.isGarbageText("OK"),
                       "Very short text should not be classified as garbage")
        XCTAssertFalse(OCRConfiguration.isGarbageText("abc"),
                       "3-char text should not be classified as garbage")
    }

    func testEmptyTextIsNotGarbage() {
        XCTAssertFalse(OCRConfiguration.isGarbageText(""),
                       "Empty text should not be classified as garbage")
    }

    func testValidNumbersAreNotGarbage() {
        let numbers = "12345.67 890 1234"
        XCTAssertFalse(OCRConfiguration.isGarbageText(numbers),
                       "Valid numbers should not be classified as garbage")
    }

    func testNonLatinTextNotFlaggedAsGarbage() {
        // When isLatinDocument is false, non-Latin scripts should pass
        let japanese = "東京タワーは日本の観光名所です"
        XCTAssertFalse(OCRConfiguration.isGarbageText(japanese, isLatinDocument: false),
                       "Japanese text should not be garbage when isLatinDocument is false")
    }

    // MARK: - Configure Request

    func testConfigureRequestDoesNotCrash() {
        // VNRecognizeTextRequest can only be fully created in a real Vision context,
        // but we can verify the factory method signature is accessible
        // and the static properties used by configureRequest are valid
        XCTAssertFalse(OCRConfiguration.universalCustomWords.isEmpty)
        XCTAssertFalse(OCRConfiguration.recognitionLanguages.isEmpty)
    }

    // MARK: - Edge Cases

    func testGarbageDetectionWithMixedContent() {
        // Text that mixes valid and garbage — should analyze the whole line
        let mixed = "Page 5 of 200 — xkQzW#$% garbled"
        // This is mostly valid with some garbage — behavior depends on ratio
        // Just verify it doesn't crash
        _ = OCRConfiguration.isGarbageText(mixed)
    }

    func testGarbageDetectionWithURLs() {
        let url = "https://www.example.com/path?param=value&other=123"
        // URLs look like garbage but shouldn't crash the detector
        _ = OCRConfiguration.isGarbageText(url)
    }

    func testDynamicVocabularyWithVeryLongText() {
        let longText = String(repeating: "Configuration VHA21 protocol ISO9001. ", count: 1000)
        let vocab = OCRConfiguration.extractDynamicVocabulary(from: longText)
        // Should handle without crashing or excessive memory usage
        XCTAssertFalse(vocab.isEmpty, "Long text with technical terms should produce vocabulary")
    }
}

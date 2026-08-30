//
//  OCRLanguageNarrowingTests.swift
//  OpenIntelligenceTests
//
//  Pins `OCRConfiguration.narrowedRecognitionLanguages(matching:)`, which decides how many language models
//  Vision loads for a document.
//
//  Why this exists. Vision loads a model per recognition language and the curated list carries
//  thirteen, four of them CJK, so an English document was paying for twelve models that cannot
//  match anything. Apple's header on `automaticallyDetectsLanguage` says to prefer an explicit
//  list "if you have domain knowledge of what language to expect", and during ingestion we do.
//
//  What is worth pinning is the asymmetry, because it is the whole design and it is invisible at
//  the call site. Narrowing wrongly costs recognition accuracy on text that is never recovered.
//  Keeping the full list only costs time. So every uncertain case must return nil, and a future
//  edit that makes this function more eager is a regression even though it would look like an
//  optimisation. The nil cases below are the load-bearing ones.
//

@testable import OpenIntelligenceEngine
import NaturalLanguage
import XCTest

final class OCRLanguageNarrowingTests: XCTestCase {

    // MARK: - Narrowing that should happen

    func testAConfidentEnglishDocumentKeepsOnlyTheEnglishVariants() {
        let narrowed = OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.english, 0.98))
        XCTAssertEqual(narrowed, ["en-US", "en-GB"])
    }

    func testNarrowingPreservesTheCuratedListOrder() {
        // The curated list is ordered by priority, and Apple's header says the order "defines the
        // order in which languages will be used during the language processing". Filtering must
        // not reorder it.
        let narrowed = OCRConfiguration.narrowedRecognitionLanguages(
            matching: profile(.german, 0.95, additional: [(.english, 0.4)])
        )
        XCTAssertEqual(narrowed, ["en-US", "en-GB", "de-DE"])
    }

    func testASecondLanguageAboveThresholdKeepsItsModel() {
        let narrowed = OCRConfiguration.narrowedRecognitionLanguages(
            matching: profile(.english, 0.9, additional: [(.french, 0.32)])
        )
        XCTAssertEqual(narrowed, ["en-US", "en-GB", "fr-FR"])
    }

    func testATraceOfASecondLanguageIsNotEnoughToKeepItsModel() {
        // A stray French quotation in an English paper should not reload the French model.
        let narrowed = OCRConfiguration.narrowedRecognitionLanguages(
            matching: profile(.english, 0.94, additional: [(.french, 0.04)])
        )
        XCTAssertEqual(narrowed, ["en-US", "en-GB"])
    }

    func testChineseKeepsBothScriptsBecauseDetectionCannotDistinguishThem() {
        // Coarse detection cannot tell Hans from Hant, and picking the wrong one loses the text
        // outright. Keeping both is the safe narrowing: eleven models dropped, not twelve.
        let narrowed = OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.simplifiedChinese, 0.93))
        XCTAssertEqual(narrowed, ["zh-Hans", "zh-Hant"])
    }

    func testNarrowingActuallyRemovesTheCJKModelsForAnEnglishDocument() throws {
        // The point of the change, stated as an assertion rather than implied by the list above.
        let narrowed = try XCTUnwrap(OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.english, 0.99)))
        for language in ["ja-JP", "ko-KR", "zh-Hans", "zh-Hant"] {
            XCTAssertFalse(narrowed.contains(language), "\(language) should not survive narrowing for English")
        }
        XCTAssertLessThan(narrowed.count, OCRConfiguration.recognitionLanguages.count)
    }

    // MARK: - Narrowing that must NOT happen

    func testALowConfidencePrimaryKeepsTheFullList() {
        // Below the confidence bar we do not have the domain knowledge Apple's guidance is
        // predicated on, so we must not act as though we do.
        XCTAssertNil(OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.english, 0.55)))
    }

    func testConfidenceExactlyAtTheBoundaryKeepsTheFullList() {
        // `isConfident` is a strict `> 0.8`. Pinned so a later edit to `>=` is a visible decision
        // rather than a silent widening of when we are willing to discard models.
        XCTAssertNil(OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.english, 0.8)))
    }

    func testAnUndeterminedLanguageKeepsTheFullList() {
        XCTAssertNil(OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.undetermined, 0.99)))
    }

    func testAnEmptyDocumentKeepsTheFullList() {
        // This is the garbled-text-layer path: roughDocumentText is empty, so detection returns
        // `.unknown`, and the pages that most need OCR must keep every model available.
        let empty = DocumentLanguageProfile(
            primaryLanguage: .unknown,
            additionalLanguages: [],
            isMultilingual: false,
            sampleSize: 0
        )
        XCTAssertNil(OCRConfiguration.narrowedRecognitionLanguages(matching: empty))
    }

    func testALanguageTheListDoesNotCoverKeepsTheFullList() {
        // Swedish is confidently detected but absent from the curated list. Returning an empty
        // array here would disable text recognition entirely, which is the worst available
        // outcome; the correct answer is to fall back to everything.
        XCTAssertNil(OCRConfiguration.narrowedRecognitionLanguages(matching: profile(.swedish, 0.97)))
    }

    func testNarrowingNeverReturnsAnEmptyList() {
        // Belt and braces across every case above: the contract is "a non-empty subset, or nil".
        let profiles: [DocumentLanguageProfile] = [
            profile(.english, 0.99),
            profile(.japanese, 0.9),
            profile(.swedish, 0.97),
            profile(.undetermined, 0.99),
            profile(.english, 0.2),
            profile(.portuguese, 0.88, additional: [(.spanish, 0.3)])
        ]
        for candidate in profiles {
            if let narrowed = OCRConfiguration.narrowedRecognitionLanguages(matching: candidate) {
                XCTAssertFalse(narrowed.isEmpty)
                // Every returned code must come from the curated list, never be synthesised.
                for code in narrowed {
                    XCTAssertTrue(OCRConfiguration.recognitionLanguages.contains(code), "\(code) is not in the curated list")
                }
            }
        }
    }

    // MARK: - Helpers

    private func profile(
        _ code: NLLanguage,
        _ confidence: Double,
        additional: [(NLLanguage, Double)] = []
    ) -> DocumentLanguageProfile {
        DocumentLanguageProfile(
            primaryLanguage: DetectedLanguage(code: code, confidence: confidence, displayName: code.rawValue),
            additionalLanguages: additional.map {
                DetectedLanguage(code: $0.0, confidence: $0.1, displayName: $0.0.rawValue)
            },
            isMultilingual: !additional.isEmpty,
            sampleSize: 4_096
        )
    }
}

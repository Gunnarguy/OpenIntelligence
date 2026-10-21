//
//  ClaimCoverageFallbackTests.swift
//  OpenIntelligenceTests
//
//  A sentence the noun tagger finds no nouns in is checked on its content words, not counted as covered (5.7,
//  `VerificationGateService.isClaimCovered`). The iOS 27 Simulator passed "The security deposit is two months of
//  rent." against an unrelated passage because the tagger found nothing to compare.
//

import XCTest

@testable import OpenIntelligence

final class ClaimCoverageFallbackTests: XCTestCase {
    func testContentWordsDropShortWordsAndFillers() {
        let terms = VerificationGateService.contentWordTerms(in: "The security deposit is two months of rent.")
        XCTAssertEqual(terms, ["security", "deposit", "two", "months", "rent"])
    }

    func testContentWordsWorkInAScriptTheTaggerHasNoClassesFor() {
        let terms = VerificationGateService.contentWordTerms(in: "Η εγγύηση είναι δύο μηνιαία ενοίκια.")
        XCTAssertTrue(terms.contains("εγγύηση"))
        XCTAssertTrue(terms.contains("ενοίκια"))
    }

    func testGreekSentenceAbsentFromThePassageIsNotCovered() async {
        let gate = VerificationGateService()
        let corpus = "the pool is open from nine to six every day."
        let covered = await gate.isClaimCovered(
            claim: "Η εγγύηση είναι δύο μηνιαία ενοίκια.", inCorpus: corpus, query: "")
        XCTAssertFalse(covered)
    }

    func testGreekSentenceInThePassageIsCovered() async {
        let gate = VerificationGateService()
        let corpus = "η εγγύηση είναι δύο μηνιαία ενοίκια, σύμφωνα με το συμβόλαιο."
        let covered = await gate.isClaimCovered(
            claim: "Η εγγύηση είναι δύο μηνιαία ενοίκια.", inCorpus: corpus, query: "")
        XCTAssertTrue(covered)
    }

    /// Japanese and Chinese are written without spaces, so the fallback's words would be whole clauses; such a
    /// claim keeps the old rule rather than failing every rewording.
    func testScriptsWithoutSpacesAreRecognised() {
        XCTAssertTrue(VerificationGateService.usesUnspacedScript("敷金は家賃の二か月分です。"))
        XCTAssertTrue(VerificationGateService.usesUnspacedScript("押金为两个月租金。"))
        XCTAssertFalse(VerificationGateService.usesUnspacedScript("Η εγγύηση είναι δύο μηνιαία ενοίκια."))
        XCTAssertFalse(VerificationGateService.usesUnspacedScript("The security deposit is two months of rent."))
    }

    func testPronounsDoNotCountAsContentWords() {
        XCTAssertEqual(VerificationGateService.contentWordTerms(in: "You should pay them which rent"), ["pay", "rent"])
    }

    /// Gate F compares only the words that spell the abbreviation (5.7): a caption "Incidence Curves Showing Mild
    /// Cognitive Impairment (MCI)" failed an answer's correct "mild cognitive impairment (MCI)".
    func testAcronymTailKeepsTheWordsThatSpellTheAbbreviation() {
        XCTAssertEqual(
            VerificationGateService.acronymTail(
                of: "Incidence Curves Showing Mild Cognitive Impairment", abbreviation: "MCI"),
            "Mild Cognitive Impairment")
        XCTAssertEqual(
            VerificationGateService.acronymTail(of: "with incident mild cognitive impairment", abbreviation: "MCI"),
            "mild cognitive impairment")
        XCTAssertEqual(
            VerificationGateService.acronymTail(of: "Montreal Cognitive Index", abbreviation: "MCI"),
            "Montreal Cognitive Index")
        XCTAssertEqual(
            VerificationGateService.acronymTail(of: "a test of retrieval", abbreviation: "RAG"),
            "a test of retrieval", "no tail spells it, so the whole expansion is kept")
    }
}


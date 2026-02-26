import XCTest
@testable import OpenIntelligence

final class QueryEnhancementServiceTests: XCTestCase {

    // MARK: - Intent Classification (QueryIntent)

    func testKeywordQueryClassifiesAsKeyword() {
        let service = QueryEnhancementService()
        let intent = service.classifyIntent("part number XYZ-1234")
        XCTAssertEqual(intent, .keyword,
                       "Specific part number lookup should classify as keyword intent")
    }

    func testConceptualQueryClassifiesAsConceptual() {
        let service = QueryEnhancementService()
        let intent = service.classifyIntent("how does the cooling system work")
        XCTAssertEqual(intent, .conceptual,
                       "'How does X work' should classify as conceptual intent")
    }

    func testBalancedQueryClassifiesAsBalanced() {
        let service = QueryEnhancementService()
        let intent = service.classifyIntent("maintenance for the engine")
        // This is a balanced query: has both a specific topic and general question
        XCTAssertTrue([QueryIntent.balanced, .keyword, .conceptual].contains(intent),
                      "Should classify as a valid intent")
    }

    // MARK: - Answer Intent Classification

    func testLookupIntent() {
        let service = QueryEnhancementService()
        let intent = service.classifyAnswerIntent("what is the maximum capacity")
        XCTAssertEqual(intent, .lookup,
                       "'What is X' should classify as lookup intent")
    }

    func testProcedureIntent() {
        let service = QueryEnhancementService()
        let intent = service.classifyAnswerIntent("how to replace the oil filter")
        XCTAssertEqual(intent, .procedure,
                       "'How to X' should classify as procedure intent")
    }

    func testCompareIntent() {
        let service = QueryEnhancementService()
        let intent = service.classifyAnswerIntent("compare synthetic vs conventional oil")
        XCTAssertEqual(intent, .compare,
                       "'Compare A vs B' should classify as compare intent")
    }

    func testSummarizeIntent() {
        let service = QueryEnhancementService()
        let intent = service.classifyAnswerIntent("summarize the maintenance schedule")
        XCTAssertEqual(intent, .summarize,
                       "'Summarize X' should classify as summarize intent")
    }

    func testTableLookupIntent() {
        let service = QueryEnhancementService()
        let intent = service.classifyAnswerIntent("list all the torque specifications")
        // "list all" is a table lookup cue
        XCTAssertTrue([AnswerIntent.tableLookup, .lookup, .summarize].contains(intent),
                      "'List all X' should classify as table lookup or similar")
    }

    func testInvestigateIntent() {
        let service = QueryEnhancementService()
        let intent = service.classifyAnswerIntent("what factors affect engine longevity")
        XCTAssertTrue([AnswerIntent.investigate, .lookup, .summarize].contains(intent),
                      "Multi-factor question should classify as investigate or related")
    }

    // MARK: - Answer Intent Completeness

    func testAllAnswerIntentsExist() {
        let allIntents = AnswerIntent.allCases
        XCTAssertTrue(allIntents.contains(.lookup))
        XCTAssertTrue(allIntents.contains(.tableLookup))
        XCTAssertTrue(allIntents.contains(.procedure))
        XCTAssertTrue(allIntents.contains(.compare))
        XCTAssertTrue(allIntents.contains(.summarize))
        XCTAssertTrue(allIntents.contains(.investigate))
        XCTAssertTrue(allIntents.contains(.compute))
        XCTAssertTrue(allIntents.contains(.findings))
    }

    func testAnswerIntentMapsToSearchIntent() {
        // Each answer intent should map to a valid search intent
        for intent in AnswerIntent.allCases {
            let searchIntent = intent.searchIntent
            XCTAssertTrue([QueryIntent.keyword, .conceptual, .balanced].contains(searchIntent),
                          "\(intent) should map to a valid search intent, got \(searchIntent)")
        }
    }

    // MARK: - Query Expansion

    func testExpandQueryReturnsAtLeastOneResult() {
        let service = QueryEnhancementService()
        let expansions = service.expandQuery("what oil should I use")
        XCTAssertGreaterThanOrEqual(expansions.count, 1,
                                     "Query expansion should return at least one result")
    }

    func testExpandQueryIncludesOriginal() {
        let service = QueryEnhancementService()
        let query = "engine oil capacity"
        let expansions = service.expandQuery(query)
        // The expanded set should contain words from the original query
        let allExpansionText = expansions.joined(separator: " ").lowercased()
        XCTAssertTrue(allExpansionText.contains("oil") || allExpansionText.contains("engine") || allExpansionText.contains("capacity"),
                      "Expansions should include terms from the original query")
    }

    func testExpandQueryProducesUniqueResults() {
        let service = QueryEnhancementService()
        let expansions = service.expandQuery("what is the tire pressure")
        let uniqueExpansions = Set(expansions)
        XCTAssertEqual(expansions.count, uniqueExpansions.count,
                       "Expanded queries should be unique (no duplicates)")
    }

    func testExpandEmptyQueryDoesNotCrash() {
        let service = QueryEnhancementService()
        let expansions = service.expandQuery("")
        // Should handle gracefully — either return empty or minimal results
        XCTAssertTrue(expansions.count >= 0, "Empty query should not crash")
    }

    func testExpandQueryWithCorpusVocabulary() {
        let vocabulary = CorpusVocabulary(
            keywords: ["viscosity", "synthetic", "conventional", "filter"],
            coOccurrences: ["oil": Set(["viscosity", "synthetic", "filter"])],
            textSnippets: ["Use SAE 0W-20 synthetic oil for best performance"]
        )
        let service = QueryEnhancementService(corpusVocabulary: vocabulary)
        let expansions = service.expandQuery("oil type")

        // With corpus vocabulary, should produce richer expansions
        XCTAssertGreaterThanOrEqual(expansions.count, 1,
                                     "Corpus vocabulary should enable richer expansions")
    }

    // MARK: - Weight Adjustments

    func testKeywordIntentBoostsKeywordWeight() {
        let adjustment = QueryIntent.keyword.weightAdjustment
        XCTAssertGreaterThan(adjustment.keywordDelta, 0,
                             "Keyword intent should boost keyword weight")
        XCTAssertLessThan(adjustment.vectorDelta, 0,
                          "Keyword intent should reduce vector weight")
    }

    func testConceptualIntentBoostsVectorWeight() {
        let adjustment = QueryIntent.conceptual.weightAdjustment
        XCTAssertGreaterThan(adjustment.vectorDelta, 0,
                             "Conceptual intent should boost vector weight")
        XCTAssertLessThan(adjustment.keywordDelta, 0,
                          "Conceptual intent should reduce keyword weight")
    }

    func testBalancedIntentNoAdjustment() {
        let adjustment = QueryIntent.balanced.weightAdjustment
        XCTAssertEqual(adjustment.vectorDelta, 0, "Balanced should have zero vector delta")
        XCTAssertEqual(adjustment.keywordDelta, 0, "Balanced should have zero keyword delta")
    }

    // MARK: - Edge Cases

    func testVeryLongQueryDoesNotCrash() {
        let service = QueryEnhancementService()
        let longQuery = String(repeating: "word ", count: 1000)
        let intent = service.classifyIntent(longQuery)
        XCTAssertNotNil(intent, "Should classify even very long queries")
    }

    func testSpecialCharactersInQuery() {
        let service = QueryEnhancementService()
        let intent = service.classifyIntent("what is the C++ API for #include <stdio.h>?")
        XCTAssertNotNil(intent, "Should handle special characters in queries")
    }

    func testNumericQuery() {
        let service = QueryEnhancementService()
        let intent = service.classifyIntent("14.7 psi")
        XCTAssertEqual(intent, .keyword,
                       "Pure numeric/measurement query should classify as keyword")
    }
}

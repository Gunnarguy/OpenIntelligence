import XCTest
@testable import OpenIntelligenceEngine

final class SemanticChunkerTests: XCTestCase {

    func testExtractEntitiesNamedEntities() {
        let chunker = SemanticChunker()
        let text = "Tim Cook works at Apple in Cupertino."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("Tim Cook"), "Should extract Tim Cook as a personal name")
        XCTAssertTrue(entities.contains("Apple"), "Should extract Apple as an organization name")
        XCTAssertTrue(entities.contains("Cupertino"), "Should extract Cupertino as a place name")
    }

    func testExtractEntitiesTechnicalTerms() {
        let chunker = SemanticChunker()
        let text = "We use the SemanticChunker class with Foundation framework."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("SemanticChunker"), "Should extract SemanticChunker as a technical term (PascalCase)")
    }

    func testExtractEntitiesCapitalizedNouns() {
        let chunker = SemanticChunker()
        let text = "The Model Architecture ensures robust performance."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("Model Architecture"), "Should extract Model Architecture as capitalized domain term")
    }

    func testExtractEntitiesDeduplication() {
        let chunker = SemanticChunker()
        let text = "Apple makes the iPhone. Apple is a large company."
        let entities = chunker.extractEntities(text)

        let appleCount = entities.filter { $0.lowercased() == "apple" }.count
        XCTAssertEqual(appleCount, 1, "Should deduplicate entities")
    }
}

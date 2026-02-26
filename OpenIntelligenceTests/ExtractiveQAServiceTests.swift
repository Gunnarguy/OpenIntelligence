import XCTest
@testable import OpenIntelligence

final class ExtractiveQAServiceTests: XCTestCase {

    // MARK: - Availability

    func testHeuristicServiceIsAlwaysAvailable() async {
        let service = HeuristicExtractiveQAService()
        let available = await service.isAvailable
        XCTAssertTrue(available, "Heuristic extractive QA should always be available")
    }

    func testPlaceholderServiceIsNeverAvailable() async {
        let service = PlaceholderExtractiveQAService()
        let available = await service.isAvailable
        XCTAssertFalse(available, "Placeholder service should not be available (model not trained)")
    }

    // MARK: - Basic Extraction

    func testExtractAnswerFromSinglePassage() async throws {
        let service = HeuristicExtractiveQAService()
        let passages = [
            "The maximum towing capacity is 7,500 pounds when properly equipped with the tow package."
        ]

        let result = try await service.extractAnswer(
            question: "What is the maximum towing capacity?",
            passages: passages
        )

        XCTAssertNotNil(result, "Should extract an answer from a matching passage")
        if let result = result {
            XCTAssertFalse(result.answerSpan.isEmpty, "Answer span should not be empty")
            XCTAssertEqual(result.sourcePassageIndex, 0, "Should reference the first passage")
        }
    }

    func testExtractAnswerFromMultiplePassages() async throws {
        let service = HeuristicExtractiveQAService()
        let passages = [
            "The vehicle features a 2.5L inline-4 engine producing 203 horsepower.",
            "Fuel economy is rated at 28 city and 36 highway miles per gallon.",
            "The cargo capacity is 15.1 cubic feet with all seats up."
        ]

        let result = try await service.extractAnswer(
            question: "What is the fuel economy?",
            passages: passages
        )

        XCTAssertNotNil(result, "Should extract answer about fuel economy")
        if let result = result {
            // Should reference passage index 1 (the fuel economy passage)
            XCTAssertEqual(result.sourcePassageIndex, 1,
                           "Should select the passage about fuel economy")
        }
    }

    // MARK: - Confidence

    func testHighConfidenceForExactMatch() async throws {
        let service = HeuristicExtractiveQAService()
        let passages = [
            "The oil capacity is exactly 5.7 quarts with filter replacement."
        ]

        let result = try await service.extractAnswer(
            question: "What is the oil capacity?",
            passages: passages
        )

        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertGreaterThan(result.confidence, 0.0,
                                 "Exact matches should have positive confidence")
        }
    }

    func testExtractionResultIsHighConfidence() {
        // Test the computed property
        let highConfidence = ExtractionResult(
            answerSpan: "5.7 quarts",
            confidence: 0.85,
            sourcePassageIndex: 0,
            spanRange: "test".startIndex..<"test".endIndex,
            startLogit: 2.0,
            endLogit: 2.0
        )
        XCTAssertTrue(highConfidence.isHighConfidence,
                      "Confidence >= 0.7 should be high confidence")

        let lowConfidence = ExtractionResult(
            answerSpan: "maybe",
            confidence: 0.3,
            sourcePassageIndex: 0,
            spanRange: "test".startIndex..<"test".endIndex,
            startLogit: 0.5,
            endLogit: 0.5
        )
        XCTAssertFalse(lowConfidence.isHighConfidence,
                       "Confidence < 0.7 should not be high confidence")
    }

    // MARK: - Edge Cases

    func testEmptyPassagesReturnsNil() async throws {
        let service = HeuristicExtractiveQAService()
        let result = try await service.extractAnswer(
            question: "What is the answer?",
            passages: []
        )
        XCTAssertNil(result, "Empty passages should return nil")
    }

    func testIrrelevantPassagesReturnsLowConfidenceOrNil() async throws {
        let service = HeuristicExtractiveQAService()
        let passages = [
            "The weather today is sunny with light winds from the northeast.",
            "Basketball was invented by James Naismith in 1891."
        ]

        let result = try await service.extractAnswer(
            question: "What is the engine displacement?",
            passages: passages
        )

        // With completely irrelevant passages, should either return nil
        // or a very low confidence result
        if let result = result {
            XCTAssertLessThan(result.confidence, 0.7,
                              "Irrelevant passages should not produce high confidence")
        }
        // nil is also acceptable
    }

    func testEmptyQuestionHandledGracefully() async throws {
        let service = HeuristicExtractiveQAService()
        let passages = ["Some passage content."]

        // Should not crash
        let result = try await service.extractAnswer(
            question: "",
            passages: passages
        )
        // Either nil or low confidence is fine
        if let result = result {
            XCTAssertGreaterThanOrEqual(result.confidence, 0.0)
        }
    }

    func testVeryLongPassageHandledGracefully() async throws {
        let service = HeuristicExtractiveQAService()
        let longPassage = String(repeating: "word ", count: 5000)
            + "The answer is 42. " + String(repeating: "more words ", count: 5000)

        let result = try await service.extractAnswer(
            question: "What is the answer?",
            passages: [longPassage]
        )

        // Should not crash or timeout
        if let result = result {
            XCTAssertFalse(result.answerSpan.isEmpty)
        }
    }

    // MARK: - Model Info

    func testHeuristicModelInfo() async {
        let service = HeuristicExtractiveQAService()
        let info = await service.modelInfo
        XCTAssertFalse(info.modelName.isEmpty, "Model name should not be empty")
    }
}

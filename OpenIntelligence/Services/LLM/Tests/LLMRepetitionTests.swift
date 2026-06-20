import XCTest
@testable import OpenIntelligenceEngine

final class LLMRepetitionTests: XCTestCase {

    // We test the method on `AppleFoundationLLMServiceUnavailable` if iOS 26 isn't available
    // BUT `AppleFoundationLLMServiceUnavailable` DOES NOT have `isRepetitiveContent` since it's a stub class.
    // Wait... `isRepetitiveContent` is ONLY defined on `AppleFoundationLLMService` which is wrapped in `#if canImport(FoundationModels)` AND `@available(iOS 26.0, *)`
    // Therefore, if `FoundationModels` cannot be imported, we shouldn't even test it.

    #if canImport(FoundationModels)
    var service: AppleFoundationLLMService!

    override func setUp() {
        super.setUp()
        if #available(iOS 26.0, *) {
            service = AppleFoundationLLMService()
        }
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }
    #endif

    func testNonRepetitiveContent() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is a very beautiful city."
        let newText = "The population is over 2 million people and it has many famous landmarks."

        XCTAssertFalse(service.isRepetitiveContent(newText: newText, existingText: existingText))
        #endif
    }

    func testRepetitiveContent() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is a very beautiful city. The weather is nice today."
        let newText = "The capital of France is Paris. It is a very beautiful city."

        XCTAssertTrue(service.isRepetitiveContent(newText: newText, existingText: existingText))
        #endif
    }

    func testShortContent() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }

        // String with fewer than 30 characters
        let existingText = "The capital of France is Paris. It is a very beautiful city."
        let newText = "Paris is great."

        XCTAssertFalse(service.isRepetitiveContent(newText: newText, existingText: existingText))
        #endif
    }

    func testCaseInsensitiveRepetition() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is a very beautiful city. The weather is nice today."
        let newText = "tHE CaPiTaL oF fRaNcE iS pArIs. iT iS a VeRy bEaUtiFuL cItY."

        XCTAssertTrue(service.isRepetitiveContent(newText: newText, existingText: existingText))
        #endif
    }

    func testPartialRepetition() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is known for the Eiffel Tower and the Louvre Museum."
        // First part is repeated, second part is new.
        // Let's make sure >50% is overlapping windows.
        // "The capital of France is Paris. " is about 32 chars.
        // "It has great food and wine." is about 27 chars.
        // Total new text is 59 chars.
        let newText = "The capital of France is Paris. It has great food and wine."

        XCTAssertTrue(service.isRepetitiveContent(newText: newText, existingText: existingText))
        #endif
    }
}

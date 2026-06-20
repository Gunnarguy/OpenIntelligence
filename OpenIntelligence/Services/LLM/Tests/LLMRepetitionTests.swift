import XCTest
@testable import OpenIntelligenceEngine

final class LLMRepetitionTests: XCTestCase {

    // Using a mock class that inherits from LLMService or directly testing the extension if possible.
    // Let's create an instance of AppleFoundationLLMService if available, otherwise AppleChatGPTExtensionService.

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

    func testNonRepetitiveContent() {
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is a very beautiful city."
        let newText = "The population is over 2 million people and it has many famous landmarks."

        XCTAssertFalse(service.isRepetitiveContent(newText: newText, existingText: existingText))
    }

    func testRepetitiveContent() {
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is a very beautiful city. The weather is nice today."
        let newText = "The capital of France is Paris. It is a very beautiful city."

        XCTAssertTrue(service.isRepetitiveContent(newText: newText, existingText: existingText))
    }

    func testShortContent() {
        guard #available(iOS 26.0, *) else { return }

        // String with fewer than 30 characters
        let existingText = "The capital of France is Paris. It is a very beautiful city."
        let newText = "Paris is great."

        XCTAssertFalse(service.isRepetitiveContent(newText: newText, existingText: existingText))
    }

    func testCaseInsensitiveRepetition() {
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is a very beautiful city. The weather is nice today."
        let newText = "tHE CaPiTaL oF fRaNcE iS pArIs. iT iS a VeRy bEaUtiFuL cItY."

        XCTAssertTrue(service.isRepetitiveContent(newText: newText, existingText: existingText))
    }

    func testPartialRepetition() {
        guard #available(iOS 26.0, *) else { return }

        let existingText = "The capital of France is Paris. It is known for the Eiffel Tower and the Louvre Museum."
        // First part is repeated, second part is new.
        // Let's make sure >50% is overlapping windows.
        // "The capital of France is Paris. " is about 32 chars.
        // "It has great food and wine." is about 27 chars.
        // Total new text is 59 chars.
        let newText = "The capital of France is Paris. It has great food and wine."

        XCTAssertTrue(service.isRepetitiveContent(newText: newText, existingText: existingText))
    }
}

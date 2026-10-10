//
//  ModelErrorClassifierTests.swift
//  OpenIntelligenceTests
//
//  The code that recovers from a failed generation used to decide what failed from single words in
//  the error's text. These pin the classifier that replaced those tests: the app's own errors, the
//  error types Apple added in iOS 27, and the wording Apple's errors print (read from the macOS 27
//  SDK on 2026-10-09).
//

import XCTest

@testable import OpenIntelligenceEngine

#if canImport(FoundationModels)
    import FoundationModels
#endif

@MainActor
final class ModelErrorClassifierTests: XCTestCase {
    private typealias Classifier = ModelErrorClassifier

    // MARK: - The app's own errors

    func testTheAppsErrorsAreReadByCase() {
        XCTAssertEqual(Classifier.kind(of: LLMError.contextWindowExceeded), .contextOverflow)
        XCTAssertEqual(Classifier.kind(of: LLMError.rateLimited("wait")), .rateLimited)
        XCTAssertEqual(Classifier.kind(of: LLMError.concurrentRequests("busy")), .rateLimited)
        XCTAssertEqual(Classifier.kind(of: LLMError.modelUnavailable), .other)
    }

    /// The reasoning chain retried only the first of these two through 5.6.
    func testBothMessagesForAnUnreadableResponseAreTransient() {
        for message in [
            Classifier.emptyResponseMessage, Classifier.unparsedResponseMessage, Classifier.legacyDecodeFailureMessage,
        ] {
            let error = LLMError.generationFailed(message)
            XCTAssertEqual(Classifier.kind(of: error), .transient, message)
            XCTAssertTrue(Classifier.isWorthRetryingUnchanged(error), message)
        }
    }

    /// Each of these was read as a context overflow or a rate limit by the word tests.
    func testMessagesThatOnlyHoldAWordAreNotThatFailure() {
        let unsupportedLanguage = LLMError.generationFailed(
            "Apple Intelligence couldn't process this query. "
                + "Try rephrasing with more context (e.g., 'Tell me about X' or 'What is X?'). "
                + "Supported languages: en, es, fr.")
        XCTAssertEqual(Classifier.kind(of: unsupportedLanguage), .other)

        let mutated = LLMError.generationFailed(
            "The conversation changed while a response was being generated. Please try again.")
        XCTAssertEqual(Classifier.kind(of: mutated), .other)
        XCTAssertFalse(Classifier.isWorthRetryingUnchanged(mutated))

        XCTAssertEqual(Classifier.textKind(description: "The maximum response tokens setting was ignored."), .other)
        XCTAssertEqual(Classifier.textKind(description: "Could not separate the answer from its sources."), .other)
    }

    // MARK: - Text, for an error of no known type

    func testApplesWordingIsRecognised() {
        XCTAssertEqual(
            Classifier.textKind(description: "The session's transcript exceeded the model's context size."),
            .contextOverflow)
        XCTAssertEqual(Classifier.textKind(description: "The session has been rate limited."), .rateLimited)
        XCTAssertEqual(
            Classifier.textKind(description: "Multiple requests were made to the session concurrently."), .rateLimited)
        XCTAssertEqual(Classifier.textKind(description: "Failed to parse generated content."), .transient)
        XCTAssertEqual(Classifier.textKind(description: "The request timed out."), .other)
        // Private Cloud Compute's three errors, by the text Apple gives them. Their type is not
        // named in the app, so they are read as text and none starts a retry here; the fallback to
        // the on-device model runs after any failure.
        for cloudText in [
            "Service is unavailable. Please try again later.",
            "Your quota has been reached. Please try again later.",
            "A network failure occurred. Please try again.",
        ] {
            XCTAssertEqual(Classifier.textKind(description: cloudText), .other, cloudText)
        }
    }

    func testAnotherErrorsTextInsideTheAppsErrorIsStillRead() {
        let wrapped = LLMError.generationFailed("The context window size was exceeded by 300 tokens.")
        XCTAssertEqual(Classifier.kind(of: wrapped), .contextOverflow)
        XCTAssertEqual(
            Classifier.kind(
                of: NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Too many requests"])),
            .rateLimited)
        XCTAssertEqual(Classifier.kind(of: CancellationError()), .other)
    }

    // MARK: - Apple's types

    #if canImport(FoundationModels) && compiler(>=6.4)
        func testTheErrorTypesAddedInIOS27AreReadByType() throws {
            guard #available(iOS 27.0, macOS 27.0, *) else {
                throw XCTSkip("These error types exist from iOS 27.")
            }
            let overflow = LanguageModelError.contextSizeExceeded(
                .init(contextSize: 4096, tokenCount: 5000, debugDescription: "test"))
            XCTAssertEqual(Classifier.kind(of: overflow), .contextOverflow)
            XCTAssertEqual(
                Classifier.kind(of: LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "test"))),
                .rateLimited)
            XCTAssertEqual(
                Classifier.kind(of: LanguageModelError.guardrailViolation(.init(debugDescription: "test"))),
                .contentFiltered)
            XCTAssertEqual(
                Classifier.kind(of: LanguageModelError.timeout(.init(debugDescription: "test"))), .other)
            XCTAssertEqual(
                Classifier.kind(of: GeneratedContent.ParsingError(rawContent: "", debugDescription: "test")), .transient
            )
            XCTAssertEqual(Classifier.kind(of: LanguageModelSession.Error.concurrentRequests), .rateLimited)
            XCTAssertEqual(Classifier.kind(of: LanguageModelSession.Error.transcriptMutationWhileResponding), .other)
        }

        func testTheMapperWritesMessagesTheClassifierReadsBack() throws {
            guard #available(iOS 27.0, macOS 27.0, *) else {
                throw XCTSkip("These error types exist from iOS 27.")
            }
            for raw in ["", "{\"answer\": "] {
                let parsing = GeneratedContent.ParsingError(rawContent: raw, debugDescription: "test")
                guard case .throwError(let mapped)? = FoundationModelErrorMapper.mapModernError(parsing) else {
                    return XCTFail("a parsing error should map to an error")
                }
                XCTAssertEqual(Classifier.kind(of: mapped), .transient, "raw content: \(raw.debugDescription)")
            }

            let overflow = LanguageModelError.contextSizeExceeded(
                .init(contextSize: 4096, tokenCount: 5000, debugDescription: "test"))
            guard case .throwError(let mappedOverflow)? = FoundationModelErrorMapper.mapModernError(overflow) else {
                return XCTFail("a context overflow should map to an error")
            }
            XCTAssertEqual(Classifier.kind(of: mappedOverflow), .contextOverflow)
            XCTAssertEqual(FoundationModelErrorMapper.recoveryHint(for: overflow), .contextOverflow)

            XCTAssertNil(FoundationModelErrorMapper.mapModernError(CancellationError()))
        }
    #endif
}

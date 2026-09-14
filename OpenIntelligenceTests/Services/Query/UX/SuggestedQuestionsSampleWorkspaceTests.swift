import XCTest

@testable import OpenIntelligenceEngine

/// Pins the three pure decisions behind the sample library's suggested questions.
///
/// On 2026-09-14 the owner's General library, holding the current sample documents, showed
/// "What is nothing?", "What is the silicon?", "What is unlimited maximum?" and "What does the
/// study say about Product Guide?". Three things had to be true for that: a numbered sample copy
/// (`RAG-Technical-Architecture-2.md`) made the library stop matching the sample workspace by
/// exact filename; the template bank built in its place, on first launch with no model, was served
/// forever; and the template extractors accepted those topics. Each decision is a static function
/// now, so each of the four strings is pinned here rather than waited for on a phone.
final class SuggestedQuestionsSampleWorkspaceTests: XCTestCase {

    private let canonical = [
        "OpenIntelligence-Product-Guide.md",
        "RAG-Technical-Architecture.md",
        "Apple-Intelligence-&-Private-Cloud-Compute.md",
    ]

    // MARK: - Sample identity

    func testCanonicalName_isItsOwnIdentity() {
        XCTAssertEqual(
            SuggestedQuestionsService.sampleIdentity(for: "RAG-Technical-Architecture.md"),
            "RAG-Technical-Architecture.md"
        )
    }

    func testNumberedCopy_resolvesToTheCanonicalName() {
        XCTAssertEqual(
            SuggestedQuestionsService.sampleIdentity(for: "RAG-Technical-Architecture-2.md"),
            "RAG-Technical-Architecture.md"
        )
        XCTAssertEqual(
            SuggestedQuestionsService.sampleIdentity(for: "OpenIntelligence-Product-Guide-13.md"),
            "OpenIntelligence-Product-Guide.md"
        )
    }

    func testUsersOwnFile_isNotASample() {
        XCTAssertNil(SuggestedQuestionsService.sampleIdentity(for: "OpenIntelligence-Product-Guide-notes.md"))
        XCTAssertNil(SuggestedQuestionsService.sampleIdentity(for: "RAG-Technical-Architecture-2.pdf"))
        XCTAssertNil(SuggestedQuestionsService.sampleIdentity(for: "RAG-Technical-Architecture-.md"))
        XCTAssertNil(SuggestedQuestionsService.sampleIdentity(for: "Quarterly-Report.md"))
    }

    // MARK: - The sample workspace

    func testExactCanonicalSet_isTheSampleWorkspace() {
        XCTAssertTrue(SuggestedQuestionsService.isSampleWorkspace(filenames: canonical))
    }

    func testNumberedCopyInPlaceOfACanonical_isStillTheSampleWorkspace() {
        var names = canonical
        names[1] = "RAG-Technical-Architecture-2.md"
        XCTAssertTrue(SuggestedQuestionsService.isSampleWorkspace(filenames: names))
    }

    func testFiveDocumentsForThreeSamples_isStillTheSampleWorkspace() {
        let names = canonical + ["RAG-Technical-Architecture-2.md", "OpenIntelligence-Product-Guide-3.md"]
        XCTAssertTrue(SuggestedQuestionsService.isSampleWorkspace(filenames: names))
    }

    func testOneUserDocument_endsTheSampleWorkspace() {
        XCTAssertFalse(SuggestedQuestionsService.isSampleWorkspace(filenames: canonical + ["Quarterly-Report.pdf"]))
    }

    func testAMissingSample_isNotTheSampleWorkspace() {
        XCTAssertFalse(SuggestedQuestionsService.isSampleWorkspace(filenames: Array(canonical.prefix(2))))
        XCTAssertFalse(SuggestedQuestionsService.isSampleWorkspace(filenames: []))
    }

    // MARK: - Rebuilding a bank the model never wrote

    private func question(_ text: String, llm: Bool) -> SuggestedQuestionsService.SuggestedQuestion {
        SuggestedQuestionsService.SuggestedQuestion(
            id: UUID(),
            text: text,
            category: .factRetrieval,
            relevantDocuments: ["OpenIntelligence Product Guide"],
            relevantDocumentIds: nil,
            sourceSections: [],
            confidence: 0.8,
            isLLMGenerated: llm
        )
    }

    func testTemplateOnlyBank_isRebuiltWhenTheModelIsAvailable() {
        let bank = [question("What is nothing?", llm: false), question("What is the silicon?", llm: false)]
        XCTAssertTrue(SuggestedQuestionsService.shouldRebuildBank(bank, modelAvailable: true))
    }

    func testTemplateOnlyBank_isKeptWhileTheModelIsUnavailable() {
        let bank = [question("What is nothing?", llm: false)]
        XCTAssertFalse(SuggestedQuestionsService.shouldRebuildBank(bank, modelAvailable: false))
    }

    func testBankWithAnyModelQuestion_isNotRebuilt() {
        let bank = [question("What is nothing?", llm: false), question("How are citations checked?", llm: true)]
        XCTAssertFalse(SuggestedQuestionsService.shouldRebuildBank(bank, modelAvailable: true))
    }

    func testEmptyBank_isNotThisPathsBusiness() {
        XCTAssertFalse(SuggestedQuestionsService.shouldRebuildBank([], modelAvailable: true))
    }

    // MARK: - The topics from the screenshot

    private let guide = "OpenIntelligence-Product-Guide.md"

    func testTheFourJunkTopics_areRejected() {
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("nothing", documentName: guide))
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("the silicon", documentName: guide))
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("unlimited maximum", documentName: guide))
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("Product Guide", documentName: guide))
    }

    func testTitleRuns_areRejectedForTheirOwnDocumentOnly() {
        let rag = "RAG-Technical-Architecture-2.md"
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("RAG Technical", documentName: rag))
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("Technical Architecture", documentName: rag))
        // The same words are a real subject in a document that is not named after them.
        XCTAssertTrue(
            SuggestedQuestionsService.isAcceptableTemplateTopic(
                "Technical Architecture", documentName: "Vendor-Onboarding.pdf"))
    }

    func testRealTopics_areAccepted() {
        XCTAssertTrue(SuggestedQuestionsService.isAcceptableTemplateTopic("fuel tank capacity", documentName: guide))
        XCTAssertTrue(SuggestedQuestionsService.isAcceptableTemplateTopic("the evidence budget", documentName: guide))
        XCTAssertTrue(SuggestedQuestionsService.isAcceptableTemplateTopic("Private Cloud Compute", documentName: guide))
        XCTAssertTrue(SuggestedQuestionsService.isAcceptableTemplateTopic("citation verification", documentName: guide))
    }

    func testArticleAlone_orEmpty_isRejected() {
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("the", documentName: guide))
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("", documentName: guide))
        XCTAssertFalse(SuggestedQuestionsService.isAcceptableTemplateTopic("  ", documentName: guide))
    }
}

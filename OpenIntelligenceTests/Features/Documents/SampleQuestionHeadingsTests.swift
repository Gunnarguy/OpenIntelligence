import XCTest

@testable import OpenIntelligence

/// Pins the hand-written questions for the sample documents to the guides themselves.
///
/// Each question's chip names the sample and the heading the question was written from. The guides
/// were rewritten after the questions were, and by 5.7 four of the eight named headings no longer
/// existed, among them "How does dynamic model routing work?", which was also the question. This
/// fails when a guide loses a heading a question names, or a question names a sample there is not.
@MainActor
final class SampleQuestionHeadingsTests: XCTestCase {

    private let storedNames = [
        "OpenIntelligence-Product-Guide.md",
        "RAG-Technical-Architecture.md",
        "Apple-Intelligence-&-Private-Cloud-Compute.md",
    ]

    func testEveryQuestionNamesAHeadingItsGuideHas() throws {
        let bodies = SampleDocumentManager.shared.sampleBodiesByName
        XCTAssertEqual(bodies.count, 3)
        let questions = try XCTUnwrap(SuggestedQuestionsService.curatedSampleQuestions(forFilenames: storedNames))
        XCTAssertEqual(questions.count, 9)
        for question in questions {
            let document = try XCTUnwrap(question.relevantDocuments.first, question.text)
            XCTAssertEqual(question.relevantDocuments.count, 1, question.text)
            let body = try XCTUnwrap(bodies[document], "\(question.text) names \(document), which is not a sample")
            let headings = Set(
                body.split(separator: "\n").compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("#") else { return nil }
                    return trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                }
            )
            let section = try XCTUnwrap(question.sourceSections.first, question.text)
            XCTAssertTrue(headings.contains(section), "\(document) has no heading \"\(section)\" for \"\(question.text)\"")
        }
    }

    /// The names the questions use are the names the samples are imported under.
    func testEverySampleHasQuestions() {
        for name in storedNames {
            XCTAssertFalse(
                (SuggestedQuestionsService.curatedSampleQuestions(forFilenames: [name]) ?? []).isEmpty, name)
        }
    }
}

import XCTest

@testable import OpenIntelligenceEngine

/// Pins which files get suggested questions written when Chat shows a library (5.8).
///
/// On the owner's iPhone on 2026-11-07 a two-file library showed "No grounded suggestions are ready yet" for a minute
/// after its import: every run was cancelled (a library switch, a tab change, iOS ending the import's background task)
/// and each cancelled run was saved as "no questions". Questions were written only when the whole bank was empty, so a
/// file whose import-time run was cancelled never got any once the other file's were in.
final class SuggestedQuestionsFillTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func needing(
        bank: Set<String>, skip: Set<UUID> = [], attempts: [UUID: Int] = [:]
    ) -> [UUID] {
        SuggestedQuestionsService.documentsNeedingQuestions(
            bankDocumentNames: bank,
            documents: [(id: a, name: "Lease"), (id: b, name: "Study"), (id: c, name: "Manual")],
            skip: skip,
            interruptedAttempts: attempts)
    }

    func testFilesWithNoQuestionInANonEmptyBankAreFilled() {
        XCTAssertEqual(needing(bank: ["Lease"]), [b, c], "until 5.8 nothing was written once any file had questions")
    }

    func testAnEmptyBankFillsEveryFile() {
        XCTAssertEqual(needing(bank: []), [a, b, c])
    }

    func testFilesStillImportingOrAlreadyTriedAreLeftAlone() {
        XCTAssertEqual(needing(bank: [], skip: [b]), [a, c])
    }

    func testAFileStopsAfterThreeInterruptedRunsThisLaunch() {
        let limit = SuggestedQuestionsService.maxInterruptedFillAttempts
        XCTAssertEqual(limit, 3)
        XCTAssertEqual(needing(bank: [], attempts: [a: limit - 1, b: limit]), [a, c])
    }

    func testCancellationIsAnInterruptionAndAModelErrorIsNot() {
        XCTAssertTrue(SuggestedQuestionsService.isInterruption(CancellationError()))
        XCTAssertFalse(SuggestedQuestionsService.isInterruption(NSError(domain: "model", code: 1)))
    }
}

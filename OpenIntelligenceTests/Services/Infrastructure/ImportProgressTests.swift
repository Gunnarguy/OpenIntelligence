//
//  ImportProgressTests.swift
//  OpenIntelligenceTests
//
//  One figure for how far an import has got, which the background task, the Live Activity and
//  "Check Import Status" all show (5.7).
//

import XCTest

@testable import OpenIntelligence

final class ImportProgressTests: XCTestCase {
    private func item(_ stage: IngestionStage, progress: Double? = nil) -> IngestionItem {
        IngestionItem(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).txt"), stage: stage, progress: progress)
    }

    func testAFinishedDocumentCountsOnce() {
        // The background task's own figure read 100% here, as the first of two documents finished.
        XCTAssertEqual(ImportProgress.fraction(of: [item(.complete), item(.queued)]), 0.5)
    }

    func testTheDocumentInProgressAddsItsShare() {
        XCTAssertEqual(
            ImportProgress.fraction(of: [item(.complete), item(.embedding, progress: 0.4)]), 0.7, accuracy: 1e-9)
        XCTAssertEqual(
            ImportProgress.fraction(of: [item(.embedding, progress: 3)]), 1, "progress is kept within 0 and 1")
    }

    func testFailedAndStoppedDocumentsCountAsDone() {
        XCTAssertEqual(ImportProgress.fraction(of: [item(.failed), item(.cancelled), item(.complete)]), 1)
        XCTAssertEqual(ImportProgress.fraction(of: []), 0)
    }

    func testTheCurrentDocumentIsTheOneThatHasStarted() {
        let started = item(.embedding)
        XCTAssertEqual(ImportProgress.current(in: [item(.complete), item(.queued), started])?.id, started.id)
        let waiting = item(.queued)
        XCTAssertEqual(ImportProgress.current(in: [item(.complete), waiting])?.id, waiting.id)
        XCTAssertNil(ImportProgress.current(in: [item(.complete), item(.failed)]))
    }

    func testAStageWithoutItsOwnProgressCountsItsPlace() {
        let stages = IngestionStage.pipelineStages
        XCTAssertEqual(ImportProgress.fraction(of: [item(.loading)]), 1 / Double(stages.count), accuracy: 1e-9)
        XCTAssertEqual(ImportProgress.percent(of: [item(.complete), item(.complete), item(.queued)]), 67)
    }
}

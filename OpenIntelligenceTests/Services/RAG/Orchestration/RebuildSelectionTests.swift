import XCTest
@testable import OpenIntelligenceEngine

/// Pins the rebuild-selection logic behind "A library with no vectors cannot repair itself,
/// and the repair reports success."
///
/// Reported from real use on 2026-08-17: a document was added to an existing library,
/// ingested without error, and the library then showed a re-indexing state that never
/// resolved. Deleting the library was the only escape.
///
/// Two distinct failures produced that. **The veto was stage-blind**, so a finished
/// `.complete` queue entry excluded its own document from repair forever — and because
/// `pruneCompletedIngestionItems` bails whenever any item is non-terminal, one stuck
/// `.paused` entry pinned every completed entry in the array. **And an empty rebuild was
/// reported as a success**, so the caller logged `Self-healing rebuild completed
/// successfully`, cleared the banner having rebuilt nothing, and the next health check
/// re-flagged the library. That cycle does not terminate.
///
/// Everything else about this defect needs a device with a stuck ingestion queue. This is
/// the part provable without hardware, and it covers the branch that actually ships:
/// `reembedDocuments` calls `classifyRebuild` rather than deciding inline.
final class RebuildSelectionTests: XCTestCase {

    private let libraryA = UUID()
    private let libraryB = UUID()

    private func doc(_ name: String, container: UUID?) -> Document {
        Document(
            filename: name,
            fileURL: URL(fileURLWithPath: "/tmp/oi-test/\(name)"),
            contentType: .pdf,
            containerId: container
        )
    }

    private func item(_ name: String, stage: IngestionStage) -> IngestionItem {
        IngestionItem(url: URL(fileURLWithPath: "/tmp/oi-test/\(name)"), stage: stage)
    }

    // MARK: - Which queue items block a rebuild

    /// The correctness of the whole fix. A finished item must not veto its own document.
    func testTerminalQueueItemsDoNotBlock() {
        let items = [
            item("done.pdf", stage: .complete),
            item("gone.pdf", stage: .cancelled),
            item("bad.pdf", stage: .failed),
        ]
        XCTAssertTrue(RAGService.blockingIngestionURLs(in: items).isEmpty)
    }

    /// An in-flight item must still veto, which is the reason the filter exists at all.
    func testNonTerminalQueueItemsBlock() {
        let blocking = RAGService.blockingIngestionURLs(in: [
            item("queued.pdf", stage: .queued),
            item("done.pdf", stage: .complete),
        ])
        XCTAssertEqual(blocking, [URL(fileURLWithPath: "/tmp/oi-test/queued.pdf")])
    }

    // MARK: - Which documents are eligible

    func testSelectsOnlyDocumentsInTheTargetLibrary() {
        let docs = [doc("a.pdf", container: libraryA), doc("b.pdf", container: libraryB)]
        let eligible = RAGService.documentsEligibleForRebuild(
            in: docs, targetContainerId: libraryA, blockingURLs: [], fallbackContainerId: nil
        )
        XCTAssertEqual(eligible.map(\.filename), ["a.pdf"])
    }

    func testExcludesDocumentsAnInFlightIngestionIsHandling() {
        let docs = [doc("a.pdf", container: libraryA), doc("b.pdf", container: libraryA)]
        let eligible = RAGService.documentsEligibleForRebuild(
            in: docs,
            targetContainerId: libraryA,
            blockingURLs: RAGService.blockingIngestionURLs(in: [item("a.pdf", stage: .queued)]),
            fallbackContainerId: nil
        )
        XCTAssertEqual(eligible.map(\.filename), ["b.pdf"])
    }

    /// A document with no container belongs to the first library, matching the shipping rule.
    func testDocumentWithoutAContainerFallsBackToTheFirstLibrary() {
        let docs = [doc("orphan.pdf", container: nil)]
        XCTAssertEqual(
            RAGService.documentsEligibleForRebuild(
                in: docs, targetContainerId: libraryA, blockingURLs: [], fallbackContainerId: libraryA
            ).count,
            1
        )
        XCTAssertEqual(
            RAGService.documentsEligibleForRebuild(
                in: docs, targetContainerId: libraryA, blockingURLs: [], fallbackContainerId: libraryB
            ).count,
            0
        )
    }

    // MARK: - Telling the three empty cases apart

    func testWorkToDoIsRebuild() {
        XCTAssertEqual(
            RAGService.classifyRebuild(eligible: [doc("a.pdf", container: libraryA)], documentsInLibrary: 1),
            .rebuild(count: 1)
        )
    }

    /// A library with nothing in it is a genuine no-op and must not raise anything.
    func testEmptyLibraryIsNotAnError() {
        XCTAssertEqual(
            RAGService.classifyRebuild(eligible: [], documentsInLibrary: 0),
            .libraryEmpty
        )
    }

    /// The defect this row is named for. Documents present, none eligible: the repair did
    /// nothing and must NOT be reported as having succeeded.
    func testDocumentsPresentButAllVetoedIsBlockedNotEmpty() {
        XCTAssertEqual(
            RAGService.classifyRebuild(eligible: [], documentsInLibrary: 3),
            .blockedByQueue(blocked: 3)
        )
    }

    /// End to end over the two extracted functions, in the shape the incident took: a
    /// library holding one document whose only queue entry is stuck non-terminal.
    func testStuckQueueItemProducesBlockedRatherThanSilentSuccess() {
        let docs = [doc("stuck.pdf", container: libraryA)]
        let eligible = RAGService.documentsEligibleForRebuild(
            in: docs,
            targetContainerId: libraryA,
            blockingURLs: RAGService.blockingIngestionURLs(in: [item("stuck.pdf", stage: .paused)]),
            fallbackContainerId: nil
        )
        XCTAssertTrue(eligible.isEmpty, "the stuck item should veto its own document")
        XCTAssertEqual(
            RAGService.classifyRebuild(eligible: eligible, documentsInLibrary: docs.count),
            .blockedByQueue(blocked: 1),
            "a vetoed rebuild must be distinguishable from a completed one"
        )
    }
}

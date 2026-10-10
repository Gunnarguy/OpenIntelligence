//
//  WorkspaceSyncImportGuardTests.swift
//  OpenIntelligenceTests
//
//  A sync pass leaves a library's vector store alone while an import into it has not finished.
//
//  An import puts its passages in the vector store as it goes and saves its document record
//  last. The pass works from the document records, so during an import it reads the import's
//  passages as belonging to no document. On 2026-10-10 a device trace held 135 full reads of one
//  store during one import (144,247 passages, 381 MB on disk by the end), and the last of the
//  tests here shows what the same pass does in a library that has another document.
//

import XCTest

@testable import OpenIntelligence

final class WorkspaceSyncImportGuardTests: XCTestCase {
    private let thisDevice = "device-a"
    private let library = UUID()
    private let defaultLibrary = UUID()

    private func queue(_ items: [IngestionItem]) -> PersistedIngestionQueueStateRecord {
        PersistedIngestionQueueStateRecord(items: items, contexts: [], updatedAt: Date())
    }

    private func item(
        stage: IngestionStage, library: UUID?, leaseOwner: String? = nil
    ) -> IngestionItem {
        IngestionItem(
            url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).jsonl"),
            containerId: library, leaseOwnerDeviceId: leaseOwner, stage: stage)
    }

    private func importing(_ items: [IngestionItem]) -> Set<UUID> {
        WorkspaceSyncService.librariesWithUnfinishedImports(
            in: queue(items), deviceID: thisDevice, defaultContainerId: defaultLibrary)
    }

    func testAnImportThatIsRunningNamesItsLibrary() {
        for stage in IngestionStage.pipelineStages {
            XCTAssertEqual(
                importing([item(stage: stage, library: library)]), [library],
                "\(stage) is an import that is still writing passages")
        }
    }

    func testAnImportWaitingToBeContinuedNamesItsLibrary() {
        // What the queue holds after the app was ended in the middle of an import, and while an
        // import is paused. Its passages are in the store and the import will carry on from them.
        XCTAssertEqual(importing([item(stage: .queued, library: library)]), [library])
        XCTAssertEqual(importing([item(stage: .paused, library: library)]), [library])
    }

    func testAnImportThatEndedNamesNoLibrary() {
        let ended: [IngestionStage] = [.complete, .cancelled, .failed]
        XCTAssertEqual(importing(ended.map { item(stage: $0, library: library) }), [])
    }

    func testAnImportThisDeviceHoldsTheLeaseOnCounts() {
        XCTAssertEqual(
            importing([item(stage: .embedding, library: library, leaseOwner: thisDevice)]), [library])
    }

    func testAnImportAnotherDeviceHoldsIsNotListed() {
        // Its passages are in that device's store, not this one's.
        XCTAssertEqual(
            importing([item(stage: .embedding, library: library, leaseOwner: "device-b")]), [])
    }

    func testAnImportWithNoLibraryCountsForTheDefaultLibrary() {
        XCTAssertEqual(importing([item(stage: .embedding, library: nil)]), [defaultLibrary])
    }

    func testNoQueueNamesNoLibrary() {
        XCTAssertEqual(
            WorkspaceSyncService.librariesWithUnfinishedImports(
                in: nil, deviceID: thisDevice, defaultContainerId: defaultLibrary), [])
    }

    func testTheMergeLeavesOutPassagesWhoseDocumentHasNoRecordYet() {
        // Why the pass must wait. A library holds one finished document and an import in
        // progress. The pass knows the finished document only, and what it would write back
        // over the store on this device has none of the import's passages in it.
        let finished = UUID()
        let beingImported = UUID()
        func passages(_ document: UUID, _ count: Int) -> [DocumentChunk] {
            (0..<count).map {
                DocumentChunk(
                    documentId: document, content: "\(document.uuidString) passage \($0)",
                    embedding: [1, 0, 0, 0], metadata: ChunkMetadata(chunkIndex: $0))
            }
        }
        let onThisDevice = passages(finished, 2) + passages(beingImported, 3)
        let inICloud = Array(onThisDevice.prefix(2))

        let written = WorkspaceSyncService.mergeVectorChunks(
            shared: inICloud, local: onThisDevice, allowedDocumentIds: [finished])

        XCTAssertEqual(written.count, 2)
        XCTAssertFalse(written.contains { $0.documentId == beingImported })
    }
}

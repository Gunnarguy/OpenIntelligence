//
//  SyncFileWaitTests.swift
//  OpenIntelligenceTests
//
//  The wait before a sync pass (5.8, `WorkspaceSyncService.waitUntilSyncFilesAreFree`): which files it waits for, that
//  it returns at once when nothing holds them, and that it gives up when something holds one too long. On the owner's Mac on 2026-11-03 the window froze while the pass
//  waited for iCloud on the main thread.
//

import XCTest

@testable import OpenIntelligence

final class SyncFileWaitTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("syncwait-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [
            "containers.json", "documents_metadata.json", "deleted_documents.json", "deleted_containers.json",
            "ingestion_queue.json", "deleted_threads.json", "vector_database_ABC.json",
            "vector_database_ABC_vectors.bin", ".documents_metadata.json.icloud",
            // iCloud's conflict copies and files the pass doesn't read.
            "documents_metadata 3.json", "vector_database_ABC 2.json", "chat_history_X.json", "notes.txt",
        ] {
            try Data("{}".utf8).write(to: folder.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Not the vector stores, whose wait could last a download, and not conflict copies or placeholders.
    func testItWaitsForTheListsOnly() {
        let names = WorkspaceSyncService.syncFilesToWaitFor(in: folder).map(\.lastPathComponent)
        XCTAssertEqual(
            Set(names),
            [
                "containers.json", "documents_metadata.json", "deleted_documents.json", "deleted_containers.json",
                "ingestion_queue.json", "deleted_threads.json",
            ])
    }

    func testAMissingFolderWaitsForNothing() {
        XCTAssertTrue(WorkspaceSyncService.syncFilesToWaitFor(in: folder.appendingPathComponent("none")).isEmpty)
    }

    /// Off the main thread, and quick when no other process holds a file.
    func testTheWaitReturnsPromptlyForFreeFiles() async {
        let started = Date()
        await WorkspaceSyncService.waitUntilSyncFilesAreFree(in: [folder])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    /// A claim held past the limit: the wait gives up instead of holding the pass, and the main actor stays free.
    func testTheWaitGivesUpWhenAFileStaysHeld() async {
        let held = folder.appendingPathComponent("deleted_documents.json")
        let claimTaken = expectation(description: "claim taken")
        let thread = Thread {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: held, options: [], error: &error) { _ in
                claimTaken.fulfill()
                Thread.sleep(forTimeInterval: 4)
            }
        }
        thread.start()
        await fulfillment(of: [claimTaken], timeout: 5)

        let started = Date()
        let waiting = Task { await WorkspaceSyncService.waitUntilSyncFilesAreFree(in: [folder], timeout: .milliseconds(500)) }
        // The main actor answers while the wait is held.
        let mainAnswered = await MainActor.run { Date() }
        XCTAssertLessThan(mainAnswered.timeIntervalSince(started), 0.4)
        await waiting.value
        let waited = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(waited, 0.4, "the claim was held, so the wait should have waited")
        XCTAssertLessThan(waited, 3, "the wait should give up at its limit, not when the claim is released")
    }
}

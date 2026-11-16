//
//  SyncPassOffMainThreadTests.swift
//  OpenIntelligenceTests
//
//  A sync pass must never hold the main thread. With approachable concurrency on (the project's
//  `SWIFT_APPROACHABLE_CONCURRENCY = YES`), a `nonisolated async` function runs on its caller's actor, so
//  `synchronizeConfiguredLibraries`, called from the main-actor `WorkspaceSyncService`, ran its file coordination on
//  the main thread. On the owner's iPhone on 2026-11-16 (build 150) iOS killed the app in the background for it
//  (0x8BADF00D, scene-update watchdog, 10 s), stopped inside `coordinatedMergeData` from
//  `WorkspaceSyncService+LibrarySync.swift:263`.
//
//  The test holds `containers.json` with another coordinator for 1.5 s, as iCloud does, runs a pass from the main
//  actor and counts how often the main actor got to run meanwhile.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SyncPassOffMainThreadTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("syncmain-\(UUID().uuidString)")
        for name in ["local", "shared"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testASyncPassWaitingOnAHeldFileLeavesTheMainThreadFree() async throws {
        let localRoot = root.appendingPathComponent("local")
        let sharedRoot = root.appendingPathComponent("shared")
        let held = localRoot.appendingPathComponent("containers.json")
        try Data("[]".utf8).write(to: held)

        let suite = "SyncPassOffMainThreadTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = WorkspaceSyncService(defaults: defaults)

        // Another writer holds the file for 1.5 s.
        let acquired = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: held, options: [], error: &error) { _ in
                acquired.signal()
                Thread.sleep(forTimeInterval: 1.5)
            }
        }
        acquired.wait()

        var ticks = 0
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        let empty = WorkspaceInventory(containers: [], documents: [])
        let started = Date()
        try await service.synchronizeConfiguredLibraries(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            localInventory: empty,
            sharedInventory: empty,
            strategy: .mergeLibraries
        )
        let waited = Date().timeIntervalSince(started)
        ticker.cancel()

        XCTAssertGreaterThan(
            waited, 1.0, "The pass should have waited for the held file; the test proves nothing otherwise.")
        // Free, the Simulator gave 10 ticks in 1.36 s (its 50 ms sleeps run long); blocked, it gave 1 in 2.16 s.
        XCTAssertGreaterThan(ticks, 4, "The main actor ran \(ticks) times while the pass waited \(waited) s.")
    }
}

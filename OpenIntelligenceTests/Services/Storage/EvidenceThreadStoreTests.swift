//
//  EvidenceThreadStoreTests.swift
//  OpenIntelligenceTests
//

import XCTest
@testable import OpenIntelligenceEngine

final class EvidenceThreadStoreTests: XCTestCase {
    var store: EvidenceThreadStore!
    var testContainerId: UUID!
    var testThread: EvidenceThread!
    
    override func setUpWithError() throws {
        store = EvidenceThreadStore()
        testContainerId = UUID()
        
        let message = ChatMessage(role: .user, content: "Hello, testing!")
        testThread = EvidenceThread(
            containerId: testContainerId,
            title: "Test Thread",
            messages: [message]
        )
    }

    override func tearDownWithError() throws {
        // Cleanup the test threads
        if let threads = try? store.listThreads(containerId: testContainerId) {
            for thread in threads {
                try? store.deleteThread(id: thread.id, containerId: testContainerId)
            }
        }
    }

    func testSerializationAndDeserialization() throws {
        // Save the thread
        try store.saveThread(testThread)
        
        // Retrieve the thread
        let loadedThread = try store.getThread(id: testThread.id, containerId: testContainerId)
        
        // Verify properties
        XCTAssertEqual(loadedThread.id, testThread.id)
        XCTAssertEqual(loadedThread.containerId, testThread.containerId)
        XCTAssertEqual(loadedThread.title, "Test Thread")
        XCTAssertEqual(loadedThread.messages.count, 1)
        XCTAssertEqual(loadedThread.messages.first?.content, "Hello, testing!")
        XCTAssertEqual(loadedThread.messages.first?.role, .user)
    }

    func testListThreads() throws {
        // Save two threads
        try store.saveThread(testThread)
        
        let secondThread = EvidenceThread(containerId: testContainerId, title: "Second Thread")
        try store.saveThread(secondThread)
        
        let threads = try store.listThreads(containerId: testContainerId)
        XCTAssertEqual(threads.count, 2)
        
        let titles = threads.map { $0.title }
        XCTAssertTrue(titles.contains("Test Thread"))
        XCTAssertTrue(titles.contains("Second Thread"))
    }
    
    func testDeleteThread() throws {
        try store.saveThread(testThread)
        XCTAssertEqual(try store.listThreads(containerId: testContainerId).count, 1)
        
        try store.deleteThread(id: testThread.id, containerId: testContainerId)
        XCTAssertEqual(try store.listThreads(containerId: testContainerId).count, 0)
        
        // Ensure getting a deleted thread throws an error
        XCTAssertThrowsError(try store.getThread(id: testThread.id, containerId: testContainerId)) { error in
            XCTAssertEqual(error as? EvidenceThreadStore.Error, .threadNotFound)
        }
    }
    
    func testIsolation() throws {
        // Create thread in container A
        let containerA = UUID()
        let threadA = EvidenceThread(containerId: containerA, title: "Thread A")
        try store.saveThread(threadA)
        
        // Create thread in container B
        let containerB = UUID()
        let threadB = EvidenceThread(containerId: containerB, title: "Thread B")
        try store.saveThread(threadB)
        
        // List container A
        let listA = try store.listThreads(containerId: containerA)
        XCTAssertEqual(listA.count, 1)
        XCTAssertEqual(listA.first?.id, threadA.id)
        
        // List container B
        let listB = try store.listThreads(containerId: containerB)
        XCTAssertEqual(listB.count, 1)
        XCTAssertEqual(listB.first?.id, threadB.id)
        
        // Cleanup
        try store.deleteThread(id: threadA.id, containerId: containerA)
        try store.deleteThread(id: threadB.id, containerId: containerB)
    }
    
    func testConcurrency() async throws {
        let concurrentStore = EvidenceThreadStore()
        let container = UUID()
        let iterations = 100
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let thread = EvidenceThread(containerId: container, title: "Concurrent Thread \(i)")
                    try? concurrentStore.saveThread(thread)
                }
            }
        }
        
        let loadedThreads = try concurrentStore.listThreads(containerId: container)
        XCTAssertEqual(loadedThreads.count, iterations)
        
        // Cleanup
        for thread in loadedThreads {
            try concurrentStore.deleteThread(id: thread.id, containerId: container)
        }
    }

    // MARK: - Where threads are kept (5.7)

    /// A folder of its own for one test, removed afterwards.
    private func makeScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvidenceThreadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// On the main actor, where `EvidenceThread`'s `Encodable` conformance is.
    @MainActor
    @discardableResult
    private func write(_ thread: EvidenceThread, under root: URL, modified: Date) throws -> URL {
        let folder = root.appendingPathComponent(thread.containerId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = folder.appendingPathComponent("\(thread.id.uuidString).json")
        try encoder.encode(thread).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    /// The app's store saves where iCloud sync reads: `WorkspaceSyncService.synchronizeEvidenceThreads`
    /// works in `applicationSupportRoot()/EvidenceThreads/<library>/`. Through the first 5.7 builds the
    /// store saved one level up, where sync never looked.
    func testTheAppsStoreSavesInTheFolderICloudSyncReads() throws {
        let syncFolder = OpenIntelligenceRuntimePaths.applicationSupportRoot()
            .appendingPathComponent("EvidenceThreads", isDirectory: true)
        guard EvidenceThreadStore.defaultRoot().standardizedFileURL == syncFolder.standardizedFileURL else {
            throw XCTSkip("a run-path override is active, so the app's own folder is not in use")
        }
        try store.saveThread(testThread)
        let saved = syncFolder.appendingPathComponent("\(testContainerId.uuidString)/\(testThread.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path), "the thread is not in \(syncFolder.path)")
    }

    @MainActor
    func testThreadsInTheOldFoldersMoveWithTheirDates() throws {
        let scratch = try makeScratch()
        let old = scratch.appendingPathComponent("EvidenceThreads", isDirectory: true)
        let older = scratch.appendingPathComponent("LocalCache/EvidenceThreads", isDirectory: true)
        let root = scratch.appendingPathComponent("OpenIntelligence/EvidenceThreads", isDirectory: true)
        let library = UUID()
        let fromOld = EvidenceThread(containerId: library, title: "From the old folder")
        let fromOlder = EvidenceThread(containerId: library, title: "From the older folder")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        try write(fromOld, under: old, modified: date)
        try write(fromOlder, under: older, modified: date)

        let moved = EvidenceThreadStore(root: root, legacyRoots: [older, old])
        XCTAssertEqual(
            Set(try moved.listThreads(containerId: library).map(\.title)),
            ["From the old folder", "From the older folder"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "the old folder was left behind")
        XCTAssertFalse(FileManager.default.fileExists(atPath: older.path), "the older folder was left behind")
        let movedFile = root.appendingPathComponent("\(library.uuidString)/\(fromOld.id.uuidString).json")
        let kept = try movedFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertEqual(
            kept?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1,
            "sync picks the newer copy by this date")
    }

    @MainActor
    func testTheNewerCopyIsKeptWhenAThreadIsInBothPlaces() throws {
        let scratch = try makeScratch()
        let old = scratch.appendingPathComponent("EvidenceThreads", isDirectory: true)
        let root = scratch.appendingPathComponent("OpenIntelligence/EvidenceThreads", isDirectory: true)
        let library = UUID()
        let earlier = Date(timeIntervalSince1970: 1_790_000_000)
        let later = Date(timeIntervalSince1970: 1_790_000_100)
        let first = UUID()
        let second = UUID()
        try write(EvidenceThread(id: first, containerId: library, title: "newer"), under: old, modified: later)
        try write(EvidenceThread(id: first, containerId: library, title: "older"), under: root, modified: earlier)
        try write(EvidenceThread(id: second, containerId: library, title: "older"), under: old, modified: earlier)
        try write(EvidenceThread(id: second, containerId: library, title: "newer"), under: root, modified: later)

        let moved = EvidenceThreadStore(root: root, legacyRoots: [old])
        XCTAssertEqual(try moved.getThread(id: first, containerId: library).title, "newer")
        XCTAssertEqual(try moved.getThread(id: second, containerId: library).title, "newer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    /// A store a benchmark or a test points elsewhere never takes the person's threads.
    func testAStoreSomewhereElseTakesNoThreadsFromTheAppsFolders() {
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("benchmark/EvidenceThreads", isDirectory: true)
        XCTAssertEqual(EvidenceThreadStore.legacyRoots(for: elsewhere), [])
        let appFolder = OpenIntelligenceRuntimePaths.applicationSupportRoot()
            .appendingPathComponent("EvidenceThreads", isDirectory: true)
        XCTAssertEqual(EvidenceThreadStore.legacyRoots(for: appFolder).count, 2, "the app's own store moves the old folders")
    }

    /// A deleted conversation is recorded beside the threads folder for iCloud sync, and a copy that comes
    /// back before sync has removed it everywhere stays hidden. Without the record, sync copied a deleted
    /// conversation back from iCloud on its next pass (found by a refuting review, 2026-10-14).
    func testADeletedConversationIsRecordedAndAReturningCopyStaysHidden() throws {
        let scratch = try makeScratch()
        let root = scratch.appendingPathComponent("OpenIntelligence/EvidenceThreads", isDirectory: true)
        let moved = EvidenceThreadStore(root: root, legacyRoots: [])
        let library = UUID()
        let thread = EvidenceThread(containerId: library, title: "Deleted on purpose")
        try moved.saveThread(thread)
        let copy = try Data(contentsOf: root.appendingPathComponent("\(library.uuidString)/\(thread.id.uuidString).json"))

        try moved.deleteThread(id: thread.id, containerId: library)
        XCTAssertEqual(moved.deletedThreadIDs(), [thread.id.uuidString])
        let record = scratch.appendingPathComponent("OpenIntelligence/\(EvidenceThreadStore.deletedThreadsFileName)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path), "sync reads the record here")

        try copy.write(to: root.appendingPathComponent("\(library.uuidString)/\(thread.id.uuidString).json"))
        XCTAssertTrue(try moved.listThreads(containerId: library).isEmpty, "a copy on its way back stays hidden")
    }

    /// Sync joins the deleted conversations of this device and of iCloud, and writes the whole list to both.
    func testSyncJoinsTheDeletedConversationsOfBothSides() throws {
        let scratch = try makeScratch()
        let local = scratch.appendingPathComponent("local", isDirectory: true)
        let shared = scratch.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let name = EvidenceThreadStore.deletedThreadsFileName
        try JSONEncoder().encode(["a"]).write(to: local.appendingPathComponent(name))
        try JSONEncoder().encode(["b"]).write(to: shared.appendingPathComponent(name))

        XCTAssertEqual(WorkspaceSyncService.mergeDeletedThreads(localRoot: local, sharedRoot: shared), ["a", "b"])
        for side in [local, shared] {
            let ids = try JSONDecoder().decode([String].self, from: Data(contentsOf: side.appendingPathComponent(name)))
            XCTAssertEqual(Set(ids), ["a", "b"], side.lastPathComponent)
        }
    }

    /// The conversation limits the store's callers enforce, which the move does not change: 5 on Free,
    /// 20 on Pro, none on Lifetime.
    func testTheConversationLimitsAreFiveTwentyAndUnlimited() {
        XCTAssertEqual(QuotaPolicy.evidenceThreadLimit(for: .free), 5)
        XCTAssertEqual(QuotaPolicy.evidenceThreadLimit(for: .pro), 20)
        XCTAssertEqual(QuotaPolicy.evidenceThreadLimit(for: .lifetime), .max)
    }
}

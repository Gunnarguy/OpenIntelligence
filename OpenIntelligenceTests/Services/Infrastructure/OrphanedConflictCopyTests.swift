//
//  OrphanedConflictCopyTests.swift
//  OpenIntelligenceTests
//
//  Which of iCloud's numbered copies the sync pass removes (5.8). On the owner's iCloud on 2026-11-03 there were 497,
//  every one for a deleted library and none with an original beside it.
//

import XCTest

@testable import OpenIntelligence

final class OrphanedConflictCopyTests: XCTestCase {
    private var folder: URL!
    private let current = UUID()
    private let deleted = UUID()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("copies-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func make(_ name: String) {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("{}".utf8))
    }

    private func orphans() -> Set<String> {
        Set(WorkspaceSyncService.orphanedConflictCopies(in: folder, libraryIds: [current]).map(\.lastPathComponent))
    }

    func testACopyOfADeletedLibrarysFileWithNoOriginalIsRemoved() {
        make("transcript_\(deleted.uuidString) 2.json")
        make("vector_database_\(deleted.uuidString)_vectors 3.bin")
        make("conversation_memory_\(deleted.uuidString) 12.json")
        XCTAssertEqual(orphans().count, 3)
    }

    /// A library that still exists keeps every copy of its files: a copy could hold something real.
    func testACurrentLibrarysCopiesAreKept() {
        make("transcript_\(current.uuidString) 2.json")
        XCTAssertTrue(orphans().isEmpty)
    }

    func testACopyWithItsOriginalBesideItIsKept() {
        make("transcript_\(deleted.uuidString).json")
        make("transcript_\(deleted.uuidString) 2.json")
        XCTAssertTrue(orphans().isEmpty)
    }

    /// iCloud evicted the original, so it shows as a placeholder: still an original.
    func testAnEvictedOriginalStillCounts() {
        make(".transcript_\(deleted.uuidString).json.icloud")
        make("transcript_\(deleted.uuidString) 2.json")
        XCTAssertTrue(orphans().isEmpty)
    }

    func testOtherFilesAreNeverTouched() {
        make("transcript_\(deleted.uuidString).json")
        make("documents_metadata 3.json")
        make("containers 2.json")
        make("notes 2.txt")
        make("transcript_not-an-id 2.json")
        XCTAssertTrue(orphans().isEmpty)
    }

    /// With no library known the lists weren't read, and nothing is removed.
    func testNothingIsRemovedWhenNoLibraryIsKnown() {
        make("transcript_\(deleted.uuidString) 2.json")
        XCTAssertTrue(WorkspaceSyncService.orphanedConflictCopies(in: folder, libraryIds: []).isEmpty)
    }
}

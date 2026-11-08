//
//  OrphanedDocumentHoldingTests.swift
//  OpenIntelligenceTests
//
//  A sync pass deleted a document file no record named. On 2026-11-03 that was the only local copy of a PDF a rebuild
//  was reading (its record had been removed 23 seconds earlier). From 5.8 such a file is moved into a holding folder,
//  kept 30 days, and the pass leaves every file alone while an import or rebuild is unfinished.
//

import XCTest

@testable import OpenIntelligence

final class OrphanedDocumentHoldingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("orphan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("ImportedDocuments"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func importedFile(_ name: String) throws -> URL {
        let url = root.appendingPathComponent("ImportedDocuments/\(name)")
        try Data("pdf".utf8).write(to: url)
        return url
    }

    func testAnUnreferencedFileIsMovedAsideNotDeleted() throws {
        let file = try importedFile("Yagishita.pdf")
        let destination = try XCTUnwrap(WorkspaceSyncService.moveOrphanedDocumentFile(file, localRoot: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(destination.deletingLastPathComponent().lastPathComponent, "OrphanedDocuments")
        XCTAssertEqual(try Data(contentsOf: destination), Data("pdf".utf8))
    }

    func testASecondFileOfTheSameNameDoesNotOverwriteTheFirst() throws {
        let first = try XCTUnwrap(WorkspaceSyncService.moveOrphanedDocumentFile(try importedFile("A.pdf"), localRoot: root))
        let second = try XCTUnwrap(WorkspaceSyncService.moveOrphanedDocumentFile(try importedFile("A.pdf"), localRoot: root))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testAHeldFileIsDeletedOnlyAfterThirtyDays() throws {
        let movedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let held = try XCTUnwrap(
            WorkspaceSyncService.moveOrphanedDocumentFile(try importedFile("B.pdf"), localRoot: root, now: movedAt))
        XCTAssertEqual(
            WorkspaceSyncService.purgeOrphanedDocumentFiles(localRoot: root, now: movedAt.addingTimeInterval(29 * 86_400)), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: held.path))
        XCTAssertEqual(
            WorkspaceSyncService.purgeOrphanedDocumentFiles(localRoot: root, now: movedAt.addingTimeInterval(31 * 86_400)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: held.path))
    }

    func testPurgingWithNoHoldingFolderDoesNothing() {
        XCTAssertEqual(WorkspaceSyncService.purgeOrphanedDocumentFiles(localRoot: root), 0)
    }
}

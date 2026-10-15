//
//  FolderImportTests.swift
//  OpenIntelligenceTests
//
//  A dropped folder, or one chosen in the Mac's open panel, brings in the files inside it that the app
//  imports, through its subfolders (5.7). Through 5.6 a dropped folder was filtered out and refused,
//  and the open panel couldn't choose one. These tests walk a folder the way the import does
//  (`ImportedFileStaging.importableFiles`). Not covered: a drop from Finder or Files on a device.
//

import XCTest

@testable import OpenIntelligence

final class FolderImportTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Manuals/Older", isDirectory: true), withIntermediateDirectories: true)
        for name in [
            "Lease.pdf", "Notes.md", ".hidden.txt", "Manuals/Fryer.txt", "Manuals/Older/Kettle.txt",
            "Manuals/photo.unknownext",
        ] {
            try Data("text".utf8).write(to: folder.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map {
            $0.path.replacingOccurrences(of: folder.resolvingSymlinksInPath().path + "/", with: "")
                .replacingOccurrences(of: folder.path + "/", with: "")
        }
    }

    func testAFolderBringsInItsImportableFilesThroughItsSubfolders() {
        let found = ImportedFileStaging.importableFiles(in: folder, limit: 500)
        XCTAssertEqual(
            names(found), ["Lease.pdf", "Manuals/Fryer.txt", "Manuals/Older/Kettle.txt", "Notes.md"],
            "hidden files and types the app doesn't import are left out")
    }

    func testAFolderBringsInNoMoreThanItsLimit() {
        XCTAssertEqual(ImportedFileStaging.importableFiles(in: folder, limit: 2).count, 2)
        XCTAssertEqual(ImportedFileStaging.importableFiles(in: folder, limit: 0), [])
    }
}

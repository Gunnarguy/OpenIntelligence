//
//  LockedCaptureImportTests.swift
//  OpenIntelligenceTests
//
//  Pages scanned from the Lock Screen (5.7).
//

import XCTest

@testable import OpenIntelligence

final class LockedCaptureImportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LockedCaptureImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Every photo in every session folder is stored once, in name order, and leaves its folder; anything else stays.
    /// A folder whose photos were all stored is handed back.
    func testPhotosAreStoredOnceAndLeaveTheirFolder() throws {
        let first = root.appendingPathComponent("session-1", isDirectory: true)
        let second = root.appendingPathComponent("session-2", isDirectory: true)
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("b".utf8).write(to: first.appendingPathComponent("Scan 2.jpg"))
        try Data("a".utf8).write(to: first.appendingPathComponent("Scan 1.JPG"))
        try Data("c".utf8).write(to: second.appendingPathComponent("Scan 3.heic"))
        try Data("x".utf8).write(to: second.appendingPathComponent("notes.txt"))

        let out = root.appendingPathComponent("imports", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let store: (URL) throws -> URL = { file in
            let destination = out.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: destination)
            return destination
        }

        let taken = LockedCaptureImport.takeAll(from: [first, second], store: store)
        XCTAssertEqual(taken.staged.map(\.lastPathComponent), ["Scan 1.JPG", "Scan 2.jpg", "Scan 3.heic"])
        XCTAssertEqual(taken.finished, [first, second])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: second.path), ["notes.txt"])
        XCTAssertEqual(LockedCaptureImport.takeAll(from: [first, second], store: store).staged, [], "taken once")
    }

    /// A photo that couldn't be stored stays where it is, for the next time.
    func testAPhotoThatCannotBeStoredStays() throws {
        let folder = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("Scan.jpg"))
        let taken = LockedCaptureImport.takeAll(from: [folder]) { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertEqual(taken.staged, [])
        XCTAssertEqual(taken.finished, [], "the folder still holds the page")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Scan.jpg"])
    }

    /// Only as many photos are taken as the plan has room for (review of 2026-10-17): the Documents screen removes a file
    /// it can't add, and the camera's copy is the only one. The rest wait in their folder, which isn't handed back.
    func testOnlyWhatThePlanHasRoomForIsTaken() throws {
        let first = root.appendingPathComponent("session-1", isDirectory: true)
        let second = root.appendingPathComponent("session-2", isDirectory: true)
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("a".utf8).write(to: first.appendingPathComponent("Scan 1.jpg"))
        try Data("b".utf8).write(to: first.appendingPathComponent("Scan 2.jpg"))
        try Data("c".utf8).write(to: second.appendingPathComponent("Scan 3.jpg"))
        let out = root.appendingPathComponent("imports", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let store: (URL) throws -> URL = { file in
            let destination = out.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: destination)
            return destination
        }

        let taken = LockedCaptureImport.takeAll(from: [first, second], atMost: 2, store: store)
        XCTAssertEqual(taken.staged.map(\.lastPathComponent), ["Scan 1.jpg", "Scan 2.jpg"])
        XCTAssertEqual(taken.finished, [first])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: second.path), ["Scan 3.jpg"])
        XCTAssertEqual(LockedCaptureImport.waitingCount(in: [first, second]), 1)
        XCTAssertEqual(LockedCaptureImport.takeAll(from: [first, second], atMost: 0, store: store).staged, [])
    }
}

//
//  CheckpointFingerprintTests.swift
//  OpenIntelligenceTests
//
//  An import's checkpoints are kept under a key made from the file's name, size and bytes, not its path and date
//  (5.7). On the owner's iPhone an app update in the middle of a 913-page PDF moved the queued copy, the old key
//  changed, and 248 pages already read were read again from page 1.
//

import XCTest

@testable import OpenIntelligenceEngine

final class CheckpointFingerprintTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        folders.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    private func file(named name: String, bytes: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    func testTheSameFileInAnotherPlaceKeepsItsKey() throws {
        let bytes = Data((0..<300_000).map { UInt8($0 % 251) })
        let first = try file(named: "Manual.pdf", bytes: bytes)
        let moved = try file(named: "Manual.pdf", bytes: bytes)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: moved.path)
        let processor = DocumentProcessor()
        XCTAssertEqual(processor.computeDocumentFingerprint(at: first), processor.computeDocumentFingerprint(at: moved))
    }

    func testDifferentBytesGiveADifferentKey() throws {
        let processor = DocumentProcessor()
        let a = try file(named: "Manual.pdf", bytes: Data(repeating: 1, count: 4_000))
        let b = try file(named: "Manual.pdf", bytes: Data(repeating: 2, count: 4_000))
        XCTAssertNotEqual(processor.computeDocumentFingerprint(at: a), processor.computeDocumentFingerprint(at: b))
    }

    func testALargeFileIsSampledAtBothEnds() throws {
        var bytes = Data(repeating: 7, count: 3_000_000)
        let a = try file(named: "Big.pdf", bytes: bytes)
        bytes[bytes.count - 10] = 9  // differs only near the end
        let b = try file(named: "Big.pdf", bytes: bytes)
        let processor = DocumentProcessor()
        XCTAssertNotEqual(processor.computeDocumentFingerprint(at: a), processor.computeDocumentFingerprint(at: b))
        XCTAssertEqual(DocumentProcessor.fingerprintSample(of: a, size: 3_000_000)?.count, 2_097_152)
    }
}

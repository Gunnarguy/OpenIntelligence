//
//  CitationSourceDocumentTests.swift
//  OpenIntelligenceTests
//
//  A cited passage opens the library's own record of its document (5.7). Through 5.6 the sheet
//  built a stand-in whose file address was only the file name, so Quick Look and the file's size
//  could not reach it.
//

import XCTest

@testable import OpenIntelligence

final class CitationSourceDocumentTests: XCTestCase {
    private func passage(of documentId: UUID, source: String) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(documentId: documentId, content: "Rent is due on the first.", embedding: [], metadata: ChunkMetadata(chunkIndex: 3)),
            similarityScore: 0.8, rank: 0, sourceDocument: source, pageNumber: 2)
    }

    func testTheLibrarysOwnRecordIsUsedWhenItIsListed() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Lease-\(UUID().uuidString).txt")
        try "Rent is due on the first.".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let id = UUID()
        let listed = Document(id: id, filename: "Lease.txt", fileURL: file, contentType: .text)

        let resolved = CitationSourceDocument.resolve(passage(of: id, source: "Lease.txt"), found: listed)
        XCTAssertEqual(resolved.id, id)
        XCTAssertEqual(resolved.fileURL, file)
        XCTAssertTrue(CitationSourceDocument.hasFile(resolved))
    }

    func testAStandInIsBuiltWhenTheLibraryNoLongerListsIt() {
        let id = UUID()
        let resolved = CitationSourceDocument.resolve(passage(of: id, source: "Gone.pdf"), found: nil)
        XCTAssertEqual(resolved.id, id)
        XCTAssertEqual(resolved.filename, "Gone.pdf")
        XCTAssertFalse(CitationSourceDocument.hasFile(resolved))
        // A record of another document is never used for this passage.
        let other = Document(id: UUID(), filename: "Other.pdf", fileURL: URL(fileURLWithPath: "/tmp/Other.pdf"), contentType: .pdf)
        XCTAssertEqual(CitationSourceDocument.resolve(passage(of: id, source: "Gone.pdf"), found: other).id, id)
    }
}

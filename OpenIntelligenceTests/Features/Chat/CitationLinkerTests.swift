//
//  CitationLinkerTests.swift
//  OpenIntelligenceTests
//
//  "Citations you can tap" is the first sentence of the store description. Through 5.5 the answer
//  view linked only a bare `[3]`, and the answer prompt asks for `[S3]`, so no citation in a real
//  answer opened anything. These pin the forms an answer actually uses, and the case where the two
//  numberings an answer can carry disagree.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class CitationLinkerTests: XCTestCase {
    private let lease = "Rent is late after 11:59 p.m. on the 5th. A late charge of $75.00 applies on the 6th."
    private let rules = "Quiet hours are 10:00 p.m. to 7:00 a.m. every day. Grills are not allowed on balconies."
    private let policy = "Sudden and accidental discharge of water from a burst pipe is covered."

    private func chunk(_ text: String, _ document: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: 1,
            sectionTitle: nil,
            keywords: [],
            hasNumericData: false,
            hasListStructure: false,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.9,
            rank: 1,
            sourceDocument: document,
            pageNumber: 1
        )
    }

    private func evidence(_ chunk: RetrievedChunk) -> StructuredAnswer.Evidence {
        StructuredAnswer.Evidence(
            evidenceId: chunk.chunk.id.uuidString,
            page: 1,
            quote: String(chunk.chunk.content.prefix(240)),
            documentName: chunk.sourceDocument,
            sectionPath: nil
        )
    }

    private func link(_ label: String, _ chunk: RetrievedChunk) -> String {
        "[[\(label)]](citation://chunk/\(chunk.chunk.id.uuidString))"
    }

    // MARK: - The forms an answer uses

    func testSourceLabelBecomesALinkToItsChunk() {
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf")]
        let linked = CitationLinker.linkedMarkdown(
            "Quiet hours start at 10:00 p.m. [S2].",
            evidence: chunks.map(evidence),
            retrievedChunks: chunks
        )
        XCTAssertEqual(linked, "Quiet hours start at 10:00 p.m. \(link("S2", chunks[1])).")
    }

    func testBareNumberStillLinksByRetrievedOrder() {
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf")]
        let linked = CitationLinker.linkedMarkdown(
            "Rent is late after the 5th [1].", evidence: [], retrievedChunks: chunks)
        XCTAssertEqual(linked, "Rent is late after the 5th \(link("1", chunks[0])).")
    }

    func testGroupedAndNamedLabels() {
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf")]
        let ev = chunks.map(evidence)
        XCTAssertEqual(
            CitationLinker.linkedMarkdown("Both apply [S1, S2].", evidence: ev, retrievedChunks: chunks),
            "Both apply \(link("S1", chunks[0])) \(link("S2", chunks[1]))."
        )
        XCTAssertEqual(
            CitationLinker.linkedMarkdown(
                "A late charge applies [S1: Lease.pdf]", evidence: ev, retrievedChunks: chunks),
            "A late charge applies \(link("S1", chunks[0]))"
        )
    }

    // MARK: - What is left alone

    func testOrdinaryBracketsAndMarkdownLinksAreUntouched() {
        let chunks = [chunk(lease, "Lease.pdf")]
        let ev = chunks.map(evidence)
        for text in [
            "See [the lease](https://example.com) for details.",
            "The form has a blank [amount] field.",
            "Section [16] of 30 pages [S9].",
        ] {
            // "[S9]" and "[16]" resolve to no chunk in a one-chunk answer, so they stay plain text too.
            XCTAssertEqual(CitationLinker.linkedMarkdown(text, evidence: ev, retrievedChunks: chunks), text)
        }
    }

    func testNoChunksMeansNoLinks() {
        XCTAssertEqual(
            CitationLinker.linkedMarkdown("Late after the 5th [S1].", evidence: [], retrievedChunks: []),
            "Late after the 5th [S1].")
    }

    // MARK: - Two numberings

    func testWhenEvidenceOrderAndRetrievedOrderDisagreeTheSentenceDecides() {
        // Retrieved order: lease, rules, policy. Evidence order (rendered answers): policy, lease.
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf"), chunk(policy, "Policy.pdf")]
        let ev = [evidence(chunks[2]), evidence(chunks[0])]

        // "S1" is the policy by evidence order and the lease by retrieved order. The sentence is
        // about the burst pipe, so the policy is the passage it came from.
        let rendered = CitationLinker.linkedMarkdown(
            "A burst pipe that discharges water suddenly is covered [S1].",
            evidence: ev,
            retrievedChunks: chunks
        )
        XCTAssertEqual(rendered, "A burst pipe that discharges water suddenly is covered \(link("S1", chunks[2])).")

        // The model's own text, numbered by retrieved order: S1 is the lease.
        let modelText = CitationLinker.linkedMarkdown(
            "Rent is late after 11:59 p.m. on the 5th, and the late charge is $75.00 [S1].",
            evidence: ev,
            retrievedChunks: chunks
        )
        XCTAssertEqual(
            modelText,
            "Rent is late after 11:59 p.m. on the 5th, and the late charge is $75.00 \(link("S1", chunks[0]))."
        )
    }

    func testALabelPastTheEvidenceListCountsRetrievedChunks() {
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf"), chunk(policy, "Policy.pdf")]
        let ev = [evidence(chunks[0])]
        let linked = CitationLinker.linkedMarkdown(
            "Grills are not allowed [S2].", evidence: ev, retrievedChunks: chunks)
        XCTAssertEqual(linked, "Grills are not allowed \(link("S2", chunks[1])).")
    }

    // MARK: - Opening a link

    func testChunkForURLFindsTheChunkAndRejectsOtherURLs() throws {
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf")]
        let url = try XCTUnwrap(URL(string: "citation://chunk/\(chunks[1].chunk.id.uuidString)"))
        XCTAssertEqual(CitationLinker.chunk(for: url, in: chunks)?.chunk.id, chunks[1].chunk.id)

        let other = try XCTUnwrap(URL(string: "https://example.com/chunk/\(chunks[1].chunk.id.uuidString)"))
        XCTAssertNil(CitationLinker.chunk(for: other, in: chunks))
        let stale = try XCTUnwrap(URL(string: "citation://chunk/\(UUID().uuidString)"))
        XCTAssertNil(CitationLinker.chunk(for: stale, in: chunks))
        // The pre-5.6 form, which pointed at an index rather than a chunk.
        let legacy = try XCTUnwrap(URL(string: "citation://3"))
        XCTAssertNil(CitationLinker.chunk(for: legacy, in: chunks))
    }
}

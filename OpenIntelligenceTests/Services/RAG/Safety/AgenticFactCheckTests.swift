//
//  AgenticFactCheckTests.swift
//  OpenIntelligenceTests
//
//  Deep Think and Maximum build their structured answer before their gates run, so their Fact Check list read
//  "Not Checked" for every claim under a Verified badge (owner's iPhone, 2026-11-07). From 5.8 each listed claim is
//  checked on its own after the displayed text is fixed (`VerificationGateService.claimVerdicts`,
//  `StructuredAnswer.withClaimVerdicts`, `RAGService.factCheckedAgenticAnswer`). These pin that the check fills
//  verdicts and changes nothing else.
//

import XCTest

@testable import OpenIntelligence

final class AgenticFactCheckTests: XCTestCase {
    private func chunk(_ text: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: 4,
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
            sourceDocument: "Mitochondria review.pdf",
            pageNumber: 4
        )
    }

    private let passage = """
        Mitochondrial quality is maintained by mitophagy, which removes damaged mitochondria through the PINK1 and \
        Parkin pathway. Biogenesis is driven by PGC-1 alpha, which increases mitochondrial DNA replication.
        """

    private let answerText = """
        Mitochondrial quality depends on removal and renewal.
        - Mitophagy removes damaged mitochondria through the PINK1 and Parkin pathway.
        - Biogenesis is driven by PGC-1 alpha, which increases mitochondrial DNA replication.
        - Daily cold showers double mitochondrial density in two weeks.
        """

    func testEveryListedClaimGetsAVerdictAndTheAnswerIsUnchanged() async {
        let chunks = [chunk(passage)]
        let built = StructuredAnswer.from(
            response: answerText, retrievedChunks: chunks, answerIntent: .investigate, verificationResult: nil)
        XCTAssertFalse(built.claims.isEmpty)
        XCTAssertTrue(built.claims.allSatisfy { $0.verificationVerdict == nil }, "built before the gates: no verdicts")

        let results = await VerificationGateService().claimVerdicts(
            for: built.claims.map(\.claim), response: answerText, chunks: chunks,
            query: "What regulates mitochondrial quality?")
        let checked = built.withClaimVerdicts(results)

        XCTAssertEqual(checked.answer, built.answer)
        XCTAssertEqual(checked.claims.map(\.claim), built.claims.map(\.claim))
        XCTAssertEqual(checked.claims.map(\.evidenceIds), built.claims.map(\.evidenceIds))
        XCTAssertEqual(checked.claims.map(\.confidence), built.claims.map(\.confidence))
        XCTAssertEqual(checked.evidence.map(\.evidenceId), built.evidence.map(\.evidenceId))
        XCTAssertEqual(checked.refuse, built.refuse)
        XCTAssertTrue(
            checked.claims.allSatisfy { $0.verificationVerdict != nil },
            "every listed claim checked: \(checked.claims.map { "\($0.claim) -> \(String(describing: $0.verificationVerdict))" })"
        )

        let mitophagy = checked.claims.first { $0.claim.contains("Mitophagy") }
        XCTAssertEqual(mitophagy?.verificationVerdict, .supported)
        let coldShowers = checked.claims.first { $0.claim.contains("cold showers") }
        XCTAssertNotEqual(coldShowers?.verificationVerdict, .supported, "a claim no passage states is not supported")
    }

    func testNoResultsLeaveTheAnswerAsItIs() {
        let built = StructuredAnswer.from(
            response: answerText, retrievedChunks: [chunk(passage)], answerIntent: .investigate, verificationResult: nil
        )
        let checked = built.withClaimVerdicts([])
        XCTAssertEqual(checked.claims.map(\.claim), built.claims.map(\.claim))
        XCTAssertTrue(checked.claims.allSatisfy { $0.verificationVerdict == nil })
    }

    func testNoClaimsOrNoPassagesCheckNothing() async {
        let gates = VerificationGateService()
        let none = await gates.claimVerdicts(for: [], response: answerText, chunks: [chunk(passage)], query: "q")
        XCTAssertTrue(none.isEmpty)
        let noPassages = await gates.claimVerdicts(for: ["A claim."], response: answerText, chunks: [], query: "q")
        XCTAssertTrue(noPassages.isEmpty)
    }
}

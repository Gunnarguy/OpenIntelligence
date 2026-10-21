//
//  CitationLabelNumberingTests.swift
//  OpenIntelligenceTests
//
//  The labels the model is shown number the passages the answer keeps (5.7). On 2026-10-20 a pet-deposit
//  question drew sentences from three of six candidates, the context labelled them by candidate ([S1], [S5],
//  [S6]), the model cited all three correctly, and the answer, whose passages were numbered 1 to 3, opened [S1]
//  only. The whole-chunk assembler had the same gap after a near-duplicate it skips. These pin both.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class CitationLabelNumberingTests: XCTestCase {
    private func passage(_ text: String, _ document: String, rank: Int) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: rank,
            pageNumber: 1,
            sectionTitle: nil,
            keywords: [],
            hasNumericData: text.contains("$"),
            hasListStructure: false,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.9 - Float(rank) * 0.05,
            rank: rank,
            sourceDocument: document,
            pageNumber: 1
        )
    }

    /// Six passages; the pet deposit is in the first and the last two.
    private var lease: [RetrievedChunk] {
        [
            passage("Each pet requires a refundable pet deposit of $300.00 before move-in.", "Lease.pdf", rank: 0),
            passage("Quiet hours are 10:00 p.m. to 7:00 a.m. every day of the week.", "Rules.pdf", rank: 1),
            passage("Parking space 14 is assigned to Unit 4B for the whole lease term.", "Parking.pdf", rank: 2),
            passage("Grills and open flames are not allowed on any balcony or patio.", "Rules.pdf", rank: 3),
            passage("The pet deposit is returned within 21 days after move-out, less damage.", "Lease.pdf", rank: 4),
            passage("A second pet needs a second pet deposit and written consent.", "Addendum.pdf", rank: 5),
        ]
    }

    /// Every label number in `context`, in order.
    private func labels(in context: String) -> [Int] {
        let regex = try! NSRegularExpression(pattern: #"\[S(\d+)\]"#)
        let text = context as NSString
        return regex.matches(in: context, range: NSRange(location: 0, length: text.length)).compactMap {
            Int(text.substring(with: $0.range(at: 1)))
        }
    }

    /// The text of the block that label `n` opens: from the label to the next label or the end.
    private func block(_ n: Int, in context: String) -> String {
        guard let start = context.range(of: "[S\(n)]") else { return "" }
        let rest = context[start.upperBound...]
        let end = rest.range(of: #"\[S\d+\]"#, options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    func testTheSentenceExtractorNumbersTheSourcesItUsed() async {
        let candidates = lease
        let result = await RAGService().extractRelevantSentences(
            from: candidates, query: "How much is the pet deposit", maxChars: 2_000, compact: true,
            isExtractiveFirst: true, numberByUse: true)

        let used = result.usedSourceIndices
        XCTAssertFalse(used.isEmpty, result.context)
        XCTAssertEqual(
            Set(labels(in: result.context)), Set(1...used.count), "labels count the sources used: \(result.context)")
        for (place, index) in used.enumerated() {
            let opened = block(place + 1, in: result.context)
            let words = candidates[index].chunk.content.split(separator: " ").prefix(3).joined(separator: " ")
            XCTAssertTrue(opened.contains(words), "[S\(place + 1)] opens candidate \(index): \(opened)")
        }
        XCTAssertFalse(result.context.contains("\u{E000}"), "no number is left unfilled")
    }

    /// The needle rescue's labels continue the packed block's: with four sources packed, its first is [S5].
    func testARescueContinuesFromTheOffsetWithoutGaps() async {
        let candidates = lease
        let result = await RAGService().extractRelevantSentences(
            from: candidates, query: "How much is the pet deposit", maxChars: 2_000, compact: true,
            isExtractiveFirst: true, labelOffset: 4, numberByUse: true)

        let used = result.usedSourceIndices
        XCTAssertFalse(used.isEmpty, result.context)
        XCTAssertEqual(Set(labels(in: result.context)), Set(5...(4 + used.count)), result.context)
    }

    /// Deep Think's windows keep every routed passage, so without `numberByUse` a label stays the candidate's
    /// place plus the window's start: the passage the label names is the one at that place in the routed list.
    func testWithoutNumberByUseALabelIsTheCandidatesPlace() async {
        let candidates = lease
        let result = await RAGService().extractRelevantSentences(
            from: candidates, query: "How much is the pet deposit", maxChars: 2_000, compact: true,
            isExtractiveFirst: true, labelOffset: 10)

        let used = result.usedSourceIndices
        XCTAssertFalse(used.isEmpty, result.context)
        XCTAssertEqual(Set(labels(in: result.context)), Set(used.map { $0 + 11 }), result.context)
    }

    func testPlaceholdersAreNumberedInTheOrderOfTheSourcesUsed() {
        let context =
            "[S\u{E000}4\u{E001}] (Lease.pdf)\nA\n---\n[S\u{E000}12\u{E001}] (Rules.pdf)\nB\n[S\u{E000}1\u{E001}] C"
        XCTAssertEqual(
            RAGService.numberedLabels(in: context, usedSourceIndices: [1, 4, 12], labelOffset: 0),
            "[S2] (Lease.pdf)\nA\n---\n[S3] (Rules.pdf)\nB\n[S1] C",
            "index 1 is not read inside index 12")
        XCTAssertEqual(
            RAGService.numberedLabels(in: "[S\u{E000}7\u{E001}] x", usedSourceIndices: [7], labelOffset: 3), "[S4] x")
    }

    /// A near-duplicate the assembler skips takes no label: the passages after it keep their place.
    func testTheWholeChunkAssemblerNumbersThePassagesItKept() async {
        let a = passage(
            "Each pet requires a refundable pet deposit of three hundred dollars before the tenant moves in.",
            "Lease.pdf", rank: 0)
        let nearlyA = passage(
            "Each pet requires a refundable pet deposit of three hundred dollars before the tenant moves in today.",
            "Lease copy.pdf", rank: 1)
        let c = passage(
            "Quiet hours are ten at night to seven in the morning on every day of the week.", "Rules.pdf", rank: 2)
        let d = passage(
            "Parking space fourteen is assigned to Unit 4B for the whole lease term.", "Parking.pdf", rank: 3)

        let assembled = await RAGEngine.shared.assembleContext(
            chunks: [a, nearlyA, c, d], maxChars: 4_000, compact: true, useLostInMiddleMitigation: false)

        XCTAssertEqual(assembled.sources.map(\.chunk.id), [a, c, d].map(\.chunk.id), "the near-duplicate is skipped")
        XCTAssertEqual(labels(in: assembled.context), [1, 2, 3], assembled.context)
        XCTAssertTrue(block(2, in: assembled.context).contains("Quiet hours"), assembled.context)
        XCTAssertTrue(block(3, in: assembled.context).contains("Parking space"), assembled.context)
        XCTAssertTrue(assembled.context.hasSuffix("Cite only sources S1 to S3."), assembled.context)
    }
}

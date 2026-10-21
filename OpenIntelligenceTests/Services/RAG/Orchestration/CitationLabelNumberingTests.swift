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
            labels(in: result.context), Array(1...used.count), "the labels read 1, 2, 3 down the context: \(result.context)")
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
        XCTAssertEqual(labels(in: result.context), Array(5...(4 + used.count)), result.context)
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

    /// With the lead passage whole, it is [S1] and the rest follow in the order the context shows them. Numbered in
    /// candidate order they read [S1], [S8], [S9], [S6] down the household context on 2026-10-20.
    func testTheLeadIsS1AndTheLabelsReadInOrderDownTheContext() async {
        let candidates = lease
        let result = await RAGService().extractRelevantSentences(
            from: candidates, query: "How much is the pet deposit", maxChars: 2_000, compact: true,
            isExtractiveFirst: true, leadingCandidateWhole: true, numberByUse: true)

        let used = result.usedSourceIndices
        XCTAssertEqual(used.first, 0, result.context)
        guard !used.isEmpty else { return }
        XCTAssertEqual(labels(in: result.context), Array(1...used.count), result.context)
        for (place, index) in used.enumerated() {
            let opened = block(place + 1, in: result.context)
            let words = candidates[index].chunk.content.split(separator: " ").prefix(3).joined(separator: " ")
            XCTAssertTrue(opened.contains(words), "[S\(place + 1)] opens candidate \(index): \(opened)")
        }
    }

    /// The assembler chooses the passages that fit in rank order and then puts the best first and the second best
    /// last. It reordered every candidate before the budget, so with four of six fitting it kept ranks 1, 3, 5 and 6
    /// and cut rank 2 (the PostDesk session's code trace, 2026-10-20).
    func testTheSecondBestPassageIsKeptAndPlacedLast() async {
        let ranked = (0..<6).map { passage(filler($0), "D.pdf", rank: $0) }
        // A compact block is the passage's 200 characters and 18 of label, file name and separator: four fit in
        // 1,000 characters and five do not.
        let assembled = await RAGEngine.shared.assembleContext(
            chunks: ranked, maxChars: 1_000, compact: true, useLostInMiddleMitigation: true)

        XCTAssertEqual(assembled.used, 4, assembled.context)
        XCTAssertEqual(assembled.sources.map(\.chunk.id), [0, 2, 3, 1].map { ranked[$0].chunk.id }, assembled.context)
        XCTAssertEqual(labels(in: assembled.context), [1, 2, 3, 4], assembled.context)
        XCTAssertTrue(block(4, in: assembled.context).contains("w1x0 "), "rank 2 is [S4], last: \(assembled.context)")
        XCTAssertTrue(assembled.context.hasSuffix("Cite only sources S1 to S4."), assembled.context)
    }

    /// The needle rescue reads the candidates after the last one packed. `dropFirst(used)` counted a skipped
    /// near-duplicate as packed and handed back a passage already in the prompt.
    func testTheRescueReadsOnlyTheCandidatesPastTheLastPacked() {
        let candidates = lease
        let past = RAGService.candidatesPastThePacked(candidates, packed: [candidates[0], candidates[2], candidates[3]])
        XCTAssertEqual(past.map(\.chunk.id), [candidates[4], candidates[5]].map(\.chunk.id))
        XCTAssertEqual(RAGService.candidatesPastThePacked(candidates, packed: []).count, candidates.count)
    }

    /// A later copy of a packed passage is not where the assembler stopped: the passages between are still read.
    func testTheRescueSkipsALaterCopyOfAPackedPassage() {
        let candidates = lease
        let past = RAGService.candidatesPastThePacked(
            candidates + [candidates[0]], packed: [candidates[0], candidates[1]])
        XCTAssertEqual(past.map(\.chunk.id), candidates[2...].map(\.chunk.id))
    }

    /// A cloud envelope numbers its evidence in its own order, so the answer keeps the passages in that order.
    func testPassagesFollowTheCloudEnvelopesOrder() {
        let candidates = lease
        let carried = [candidates[2], candidates[0], candidates[4]]
        let envelope = CloudEvidenceEnvelope(
            planID: UUID(),
            query: "How much is the pet deposit",
            evidence: carried.map {
                CloudEvidenceItem(
                    sourceID: $0.chunk.id.uuidString, documentName: $0.sourceDocument, pageNumber: $0.pageNumber,
                    text: $0.chunk.content)
            },
            omittedChunkCount: 3,
            characterCount: 0
        )
        XCTAssertEqual(
            RAGService.passages(candidates, inTheOrderOf: envelope).map(\.chunk.id), carried.map(\.chunk.id))
    }

    /// 200 characters of words only this rank uses, so no two passages read as near-duplicates.
    private func filler(_ rank: Int) -> String {
        var text = ""
        var n = 0
        while text.count < 200 {
            text += "w\(rank)x\(n) "
            n += 1
        }
        return String(text.prefix(200))
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

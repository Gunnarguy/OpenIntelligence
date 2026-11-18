//
//  GraniteGroundingFloorMeasurementTests.swift
//  OpenIntelligenceTests
//
//  What the bundled Granite embedder (5.8) gives Gate E to work with, measured with the app's own provider (2026-11-18).
//  On the owner's iPhone a grounded Deep Think answer measured 0.031 against its best passage and its question 0.045,
//  under Gate E's 0.25 floor. These tests measure grounded answers, unrelated text and the same passage embedded twice,
//  print every figure, and pin the two rules that rest on them: with one model the floor is never reached by the
//  question, so a question under it means the passages hold another model's vectors (`runGateE`); and the same model
//  never scores a passage under `StoredVectorModelCheck.anotherModelCeiling` against itself.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class GraniteGroundingFloorMeasurementTests: XCTestCase {
    private struct Case {
        let question: String
        let source: String
        let groundedAnswer: String
    }

    private let cases: [Case] = [
        Case(
            question: "What role does the gut-brain axis play in canine anxiety?",
            source:
                "This review examines the gut-brain axis and its role in canine anxiety disorders. The intestinal microbiota "
                + "signals to the brain through the vagus nerve, immune mediators and microbial metabolites such as short-chain "
                + "fatty acids, and dogs with anxiety showed a different microbial composition from calm dogs.",
            groundedAnswer:
                "The gut-brain axis links the dog's intestinal microbiota to its brain through the vagus nerve, immune "
                + "mediators and metabolites such as short-chain fatty acids [S1]. Anxious dogs carry a different mix of gut "
                + "microbes than calm dogs, which the review presents as part of how anxiety arises [S1]."),
        Case(
            question: "How many days notice ends the lease?",
            source:
                "Either party may terminate this lease with sixty (60) days written notice to the other party, delivered by "
                + "certified mail. Notice is effective on the date it is received.",
            groundedAnswer:
                "Either side can end the lease by giving sixty days of written notice, sent by certified mail [S2]. The notice "
                + "counts from the day it is received [S2]."),
        Case(
            question: "What temperature should the oven be for the bread?",
            source:
                "Preheat the oven to 230 °C (450 °F) with a Dutch oven inside. Bake the loaf covered for 20 minutes, then "
                + "uncovered for a further 20 to 25 minutes until the crust is deep brown.",
            groundedAnswer:
                "Heat the oven to 230 °C, which is 450 °F, with the Dutch oven inside it [S3]. The loaf bakes covered for 20 "
                + "minutes and then uncovered for another 20 to 25 [S3]."),
        Case(
            question: "Which error code means the filter is blocked?",
            source:
                "Error E4 indicates a blocked filter. Switch the appliance off, remove the filter from the base, rinse it under "
                + "running water and refit it before restarting.",
            groundedAnswer:
                "E4 is the code for a blocked filter [S4]. Turn the appliance off, take the filter out, rinse it and put it back "
                + "before you start it again [S4]."),
    ]

    /// Text that shares nothing with the cases above, to read how far apart one model puts unrelated English.
    private let unrelated = [
        "The kitchen was renovated in 2019 with quartz counters and a new range hood.",
        "Jupiter's Great Red Spot is a storm larger than Earth that has lasted for centuries.",
        "let total = items.reduce(0) { $0 + $1.price } // sum of prices",
        "The midfielder scored twice in the second half to win the derby 3-1.",
        "Quarterly revenue rose 12 percent on higher subscription sales in Europe.",
        "1, 2, 3, 5, 8, 13, 21, 34, 55, 89",
    ]

    private func provider() async throws -> CoreMLSentenceEmbeddingProvider {
        let provider = CoreMLSentenceEmbeddingProvider()
        guard provider.isAvailable else { throw XCTSkip("embedding model not bundled") }
        for _ in 0..<100 where provider.countTokens("How many days notice ends the lease?") != 10 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return provider
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float { StoredVectorModelCheck.cosine(a, b) }

    func testGroundedAnswersUnrelatedTextAndTheFloor() async throws {
        let provider = try await provider()
        var grounded: [Float] = []
        var questionToSource: [Float] = []
        var crossCase: [Float] = []
        var unrelatedToSource: [Float] = []
        var report: [String] = []

        var vectors: [(q: [Float], s: [Float], a: [Float])] = []
        for item in cases {
            vectors.append(
                (
                    try await provider.embed(text: item.question), try await provider.embed(text: item.source),
                    try await provider.embed(text: item.groundedAnswer)
                ))
        }
        let unrelatedVectors = try await unrelated.asyncMap { try await provider.embed(text: $0) }

        for (index, v) in vectors.enumerated() {
            let answerToSource = cosine(v.a, v.s)
            let qToSource = cosine(v.q, v.s)
            grounded.append(answerToSource)
            questionToSource.append(qToSource)
            report.append(
                "case \(index): answer-source \(String(format: "%.3f", answerToSource)), question-source "
                    + "\(String(format: "%.3f", qToSource)), ratio \(String(format: "%.3f", answerToSource / qToSource))")
            for (other, w) in vectors.enumerated() where other != index {
                // Another case's answer against this case's source: an answer about something else.
                crossCase.append(cosine(w.a, v.s))
            }
            for u in unrelatedVectors {
                unrelatedToSource.append(cosine(u, v.s))
            }
        }
        var unrelatedPairs: [Float] = []
        for i in unrelatedVectors.indices {
            for j in unrelatedVectors.indices where j > i {
                unrelatedPairs.append(cosine(unrelatedVectors[i], unrelatedVectors[j]))
            }
        }

        func range(_ values: [Float]) -> String {
            "\(String(format: "%.3f", values.min() ?? .nan)) to \(String(format: "%.3f", values.max() ?? .nan))"
        }
        report.append("grounded answer to its source: \(range(grounded))")
        report.append("question to its source: \(range(questionToSource))")
        report.append("another case's answer to a source: \(range(crossCase))")
        report.append("unrelated text to a source: \(range(unrelatedToSource))")
        report.append("unrelated text to unrelated text: \(range(unrelatedPairs))")
        let lowestSameModel = (crossCase + unrelatedToSource + unrelatedPairs).min() ?? 0
        report.append("lowest same-model cosine of any two texts: \(String(format: "%.3f", lowestSameModel))")
        print("[GraniteGroundingFloor] " + report.joined(separator: "\n[GraniteGroundingFloor] "))
        add(XCTAttachment(string: report.joined(separator: "\n")))

        // A grounded answer is closer to its source than an answer about something else is.
        XCTAssertGreaterThan(grounded.min() ?? 0, crossCase.max() ?? 1)
        // With one model nothing reaches the floor, so a question under it is the passages' vectors being another
        // model's, not the question being far from them (`runGateE`).
        XCTAssertGreaterThan(lowestSameModel, VerificationGateService.semanticGroundingFloor)
        XCTAssertGreaterThan(lowestSameModel, StoredVectorModelCheck.anotherModelCeiling)
    }

    /// A stored vector is made from a prefix and the passage (`StoredVectorModelCheck.embeddedText`); the same model's
    /// vector for the passage alone still scores far above the ceiling, so a changed prefix cannot read as another model.
    func testTheSamePassageWithAndWithoutItsPrefixIsOneModels() async throws {
        let provider = try await provider()
        for item in cases {
            let withPrefix = try await provider.embed(text: "[From review.pdf] [Introduction] " + item.source)
            let bare = try await provider.embed(text: item.source)
            let similarity = cosine(withPrefix, bare)
            print("[GraniteGroundingFloor] prefix vs bare: \(String(format: "%.3f", similarity))")
            XCTAssertGreaterThan(similarity, StoredVectorModelCheck.anotherModelCeiling)
            XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreAnotherModels(stored: [withPrefix], fresh: [bare]))
        }
    }

    /// Gate E with the app's own vectors: grounded when the passages hold this model's vectors, and not checked when
    /// they hold vectors in another space. A fixed rotation of every coordinate (here a reversal and sign flip of
    /// alternate coordinates) stands in for another model: it keeps each vector's length and spreads the cosines
    /// around zero, as the owner's iPhone measured (0.016 to 0.101).
    func testGateEJudgesThisModelsPassagesAndDeclinesAnotherModels() async throws {
        let provider = try await provider()
        let item = cases[0]
        let question = try await provider.embed(text: item.question)
        let answer = try await provider.embed(text: item.groundedAnswer)
        let source = try await provider.embed(text: item.source)
        let otherModel = source.reversed().enumerated().map { $0.offset.isMultiple(of: 2) ? $0.element : -$0.element }
        print(
            "[GraniteGroundingFloor] stand-in other model: question \(String(format: "%.3f", cosine(question, otherModel))), "
                + "answer \(String(format: "%.3f", cosine(answer, otherModel)))")
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreAnotherModels(stored: [source], fresh: [source]))
        XCTAssertTrue(StoredVectorModelCheck.storedVectorsAreAnotherModels(stored: [otherModel], fresh: [source]))

        let metadata = ChunkMetadata(chunkIndex: 0, pageNumber: 1, wordCount: 40, characterCount: item.source.count)
        let chunk = RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: item.source, embedding: [], metadata: metadata),
            similarityScore: 0.9, rank: 1, sourceDocument: "review.pdf", pageNumber: 1)

        func gateE(_ passages: [[Float]], flagged: Bool = true) async -> RAGVerificationResult.GateResult? {
            await VerificationGateService().verify(
                response: item.groundedAnswer, query: item.question, retrievedChunks: [chunk], topScores: [0.9],
                responseEmbedding: answer, queryEmbedding: question, chunkEmbeddings: passages,
                passageVectorsMayBeAnotherModels: flagged
            ).gateResults.first { $0.gate == .semanticGrounding }
        }
        let sameResult = await gateE([source])
        let same = try XCTUnwrap(sameResult)
        XCTAssertTrue(same.passed, same.details)
        XCTAssertTrue(same.details.hasPrefix("Grounded"), same.details)
        let otherResult = await gateE([otherModel])
        let other = try XCTUnwrap(otherResult)
        XCTAssertTrue(other.passed, other.details)
        XCTAssertTrue(other.details.hasPrefix("NOT_CHECKED"), other.details)
        // Unflagged, the same vectors fail the answer: the gate declines only where the model check found them.
        let unflaggedResult = await gateE([otherModel], flagged: false)
        let unflagged = try XCTUnwrap(unflaggedResult)
        XCTAssertFalse(unflagged.passed, unflagged.details)
        // A flagged library whose vectors are this model's is judged as usual.
        let flaggedSameResult = await gateE([source], flagged: true)
        XCTAssertTrue(try XCTUnwrap(flaggedSameResult).details.hasPrefix("Grounded"))
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        out.reserveCapacity(count)
        for element in self { out.append(try await transform(element)) }
        return out
    }
}

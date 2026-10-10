//
//  ClaimCheckEvaluationTests.swift
//  OpenIntelligenceTests
//
//  The first use of Apple's Evaluations framework (Xcode 27) in this repository. It grades the check
//  that decides whether a sentence of an answer reads Supported: each sample is a sentence, the
//  passage it cites and the verdict a careful reader gives, and the subject is what
//  `VerificationGateService` says. No model runs, so it works in the simulator.
//
//  Two figures come out. "Agrees where the check claims to work" is asserted at 100%. "Agrees
//  overall" also counts four sentences the check is known to get wrong (a flipped "not", an ordinal,
//  a sentence half of whose words are in the passage without the passage saying it, and one that
//  shares a third of its words with a passage that says the opposite); that figure is printed, not
//  asserted, so the gap stays visible in the evaluation report.
//

import Evaluations
import Foundation
import Testing

@testable import OpenIntelligenceEngine

/// One labelled sentence.
nonisolated struct ClaimCheckSample: SampleProtocol {
    struct Input: CustomStringConvertible, Codable, Sendable {
        let sentence: String
        let passage: String
        /// The question the sentence answers. The check counts a word of the sentence as covered
        /// when the question holds it, so the question is part of the sample.
        let question: String
        var description: String { sentence }
    }

    let input: Input
    /// "supported" or "not supported", as a careful reader would mark the sentence.
    let expected: String?
    /// True for a sentence the word-and-number check is known not to judge correctly.
    let knownGap: Bool

    init(
        _ sentence: String, against passage: String, is expected: String, knownGap: Bool = false,
        asked question: String? = nil
    ) {
        let asked = question ?? (passage == ClaimCheckDataset.paper ? ClaimCheckDataset.paperQuestion : ClaimCheckDataset.leaseQuestion)
        self.input = Input(sentence: sentence, passage: passage, question: asked)
        self.expected = expected
        self.knownGap = knownGap
    }
}

nonisolated enum ClaimCheckDataset {
    static let supported = "supported"
    static let notSupported = "not supported"

    static let lease =
        "Rent is late after 11:59 p.m. on the 5th day of the month. A late charge of $75.00 applies on the 6th day. "
        + "Pets are not allowed without written permission from the landlord. "
        + "The tenant must give 60 days written notice before moving out."
    static let paper =
        "There are 3 billion parameters in the on-device model. "
        + "One of the external models it is compared with is Qwen-2.5-3B."
    static let leaseQuestion = "What does it say?"
    static let paperQuestion = "How many parameters does the on-device model have?"

    static let samples: [ClaimCheckSample] = [
        // Sentences the passage states.
        .init("A late charge of $75.00 applies on the 6th day.", against: lease, is: supported),
        .init("The tenant must give 60 days written notice before moving out.", against: lease, is: supported),
        .init("Rent is late after 11:59 p.m. on the 5th day of the month.", against: lease, is: supported),
        .init("The late charge is $75.", against: lease, is: supported),
        .init("The notice period is 60 days.", against: lease, is: supported),
        .init("There are 3 billion parameters in the on-device model.", against: paper, is: supported),
        .init("One of the external models is Qwen-2.5-3B.", against: paper, is: supported),
        // The same sentences with a figure the passage does not state.
        .init("The tenant must give 30 days written notice before moving out.", against: lease, is: notSupported),
        .init("The late charge is $57.", against: lease, is: notSupported),
        .init("Rent is late after 10:59 p.m. on the 5th day of the month.", against: lease, is: notSupported),
        .init("There are 2.5 billion parameters in the on-device model.", against: paper, is: notSupported),
        .init("The landlord may enter with 24 hours notice.", against: lease, is: notSupported),
        // A sentence about something the passage does not cover.
        .init("The warranty covers the compressor for ten years.", against: lease, is: notSupported),
        // Known gaps: the check compares words and numbers, and these differ in neither.
        .init(
            "Pets are allowed without written permission from the landlord.", against: lease, is: notSupported,
            knownGap: true),
        .init("A late charge applies on the 16th day.", against: lease, is: notSupported, knownGap: true),
        .init("The landlord may enter with notice.", against: lease, is: notSupported, knownGap: true),
        // The passage says pets are not allowed. Three of this sentence's nine words are in it,
        // which with a high retrieval score is enough for the check (found by this suite's first
        // run, 2026-10-09).
        .init(
            "Pets are allowed with a refundable deposit of four hundred dollars.", against: lease, is: notSupported,
            knownGap: true),
    ]
}

@available(iOS 27.0, macOS 27.0, *)
nonisolated struct ClaimCheckEvaluation: Evaluation {
    typealias Sample = ClaimCheckSample
    typealias Subject = ModelSubject<String>

    static let agreement = Metric("agrees overall")
    static let coveredAgreement = Metric("agrees where the check claims to work")

    var dataset: ArrayLoader<ClaimCheckSample> { ArrayLoader(samples: ClaimCheckDataset.samples) }

    func subject(from sample: ClaimCheckSample) async throws -> ModelSubject<String> {
        let sentence = sample.input.sentence
        let chunks = await Self.chunks(for: sample.input.passage)
        let result = await VerificationGateService().verify(
            response: sentence,
            query: sample.input.question,
            retrievedChunks: chunks,
            topScores: [0.9],
            structuredClaims: [StructuredRAGClaim(claim: sentence, citations: ["S1"], isExtracted: true)]
        )
        let supported = !result.claimResults.isEmpty && result.claimResults.allSatisfy { $0.verdict == .supported }
        return ModelSubject(value: supported ? ClaimCheckDataset.supported : ClaimCheckDataset.notSupported)
    }

    var evaluators: Evaluators {
        Evaluator<ClaimCheckSample> { sample, subject in
            subject.value == sample.expected
                ? Self.agreement.passing()
                : Self.agreement.failing(rationale: "said \(subject.value) for: \(sample.input.sentence)")
        }
        Evaluator<ClaimCheckSample> { sample, subject in
            if sample.knownGap { return Self.coveredAgreement.ignore(rationale: "a known gap of the check") }
            return subject.value == sample.expected
                ? Self.coveredAgreement.passing()
                : Self.coveredAgreement.failing(rationale: "said \(subject.value) for: \(sample.input.sentence)")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.agreement)
        aggregator.computeMean(of: Self.coveredAgreement)
    }

    @MainActor
    private static func chunks(for passage: String) -> [RetrievedChunk] {
        let metadata = ChunkMetadata(chunkIndex: 0, pageNumber: 1, wordCount: 40, characterCount: passage.count)
        return [
            RetrievedChunk(
                chunk: DocumentChunk(documentId: UUID(), content: passage, embedding: [], metadata: metadata),
                similarityScore: 0.9,
                rank: 1,
                sourceDocument: "Sample.pdf",
                pageNumber: 1
            )
        ]
    }
}

@Suite("Claim check, graded with Apple's Evaluations framework")
struct ClaimCheckEvaluationTests {
    @available(iOS 27.0, macOS 27.0, *)
    @Test(.evaluates(ClaimCheckEvaluation()))
    func theClaimCheckAgreesWithTheLabelsWhereItClaimsToWork() async throws {
        let result = EvaluationContext.current.result
        let covered = result.aggregateValue(.mean(of: ClaimCheckEvaluation.coveredAgreement))

        // Names each sentence the check and its label disagree on, so a failure says which.
        var disagreements: [String] = []
        let evaluation = ClaimCheckEvaluation()
        for sample in ClaimCheckDataset.samples where !sample.knownGap {
            let said = try await evaluation.subject(from: sample).value
            if said != sample.expected {
                disagreements.append("said \(said), labelled \(sample.expected ?? "nil"): \(sample.input.sentence)")
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: " | "))")
        #expect(covered == 1.0, "\(result.groupedSummary)")

        // Printed, not asserted: the known gaps are in this one.
        let overall = result.aggregateValue(.mean(of: ClaimCheckEvaluation.agreement))
        print("[ClaimCheckEvaluation] agrees overall: \(overall) over \(ClaimCheckDataset.samples.count) sentences")
    }
}

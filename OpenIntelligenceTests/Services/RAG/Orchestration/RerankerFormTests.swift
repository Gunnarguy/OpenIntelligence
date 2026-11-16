//
//  RerankerFormTests.swift
//  OpenIntelligenceTests
//
//  On Maximum the reranker starts on its default compiled form and swaps to the `.fastPrediction` form once that is
//  prepared in the background (5.8, 2026-11-16). The weights are the same, so the ranking must be too: this scores one
//  question against the same passages with both forms, at both input lengths, and asserts the order is identical.
//

import CoreML
import XCTest

@testable import OpenIntelligence

final class RerankerFormTests: XCTestCase {
    private let query = "How many days notice ends the lease?"
    private let passages = [
        "Either party may terminate this lease with sixty (60) days written notice to the other party, delivered by certified mail.",
        "The tenant shall pay rent of $1,850 on the first day of each month, with a late fee of $75 after the fifth.",
        "The kitchen was renovated in 2019 with quartz counters and a new range hood.",
        "Notice under this agreement is given in writing to the addresses listed on the signature page.",
        "The lease begins on June 1, 2026 and ends on May 31, 2027 unless renewed or terminated earlier.",
        "Pets are allowed with a deposit of $300 per animal, refundable at the end of the lease.",
        "Table 1 lists retention times for the sixteen PAHs; benzo[a]pyrene eluted at 37.24 min.",
        "If the tenant ends the lease early without notice, the deposit is forfeited and one month's rent is owed.",
    ]

    private func scores(_ models: [(length: Int, model: MLModel)], length: Int) async throws -> [Float] {
        let model = try XCTUnwrap(models.first { $0.length == length }?.model)
        var result: [Float] = []
        for passage in passages {
            let encoded = await RAGEngine.rerankerTokenIds(query: query, passage: passage)
            let ids = try XCTUnwrap(encoded, "the reranker tokenizer did not load")
            let inputIds = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            for i in 0..<length {
                inputIds[i] = NSNumber(value: i < ids.count ? ids[i] : 50283)
                mask[i] = NSNumber(value: i < ids.count ? 1 : 0)
            }
            let out = try await model.prediction(
                from: MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIds),
                    "attention_mask": MLFeatureValue(multiArray: mask),
                ]))
            result.append(try XCTUnwrap(out.featureValue(for: "logits")?.multiArrayValue)[0].floatValue)
        }
        return result
    }

    private func order(_ scores: [Float]) -> [Int] {
        scores.indices.sorted { scores[$0] > scores[$1] }
    }

    func testFastPredictionFormRanksLikeTheDefaultForm() async throws {
        let url = try XCTUnwrap(
            OpenIntelligenceResourceBundle.url(forResource: "ReRankerModel", withExtension: "mlmodelc"),
            "ReRankerModel.mlmodelc is not in the app")
        var start = Date()
        let standard = RAGEngine.loadRerankerFunctions(at: url, fast: false)
        let standardSeconds = Date().timeIntervalSince(start)
        start = Date()
        let fast = RAGEngine.loadRerankerFunctions(at: url, fast: true)
        let fastSeconds = Date().timeIntervalSince(start)
        print(
            "RerankerFormTests: default form loaded in \(String(format: "%.2f", standardSeconds)) s, "
                + "fastPrediction form in \(String(format: "%.2f", fastSeconds)) s")
        XCTAssertEqual(standard.count, 2, "the default form did not load both functions")
        guard fast.count == 2 else {
            throw XCTSkip("the fastPrediction form is not available here (loaded \(fast.count) of 2 functions)")
        }
        for length in [256, 512] {
            let a = try await scores(standard, length: length)
            let b = try await scores(fast, length: length)
            print("RerankerFormTests len\(length): default \(a), fastPrediction \(b)")
            XCTAssertEqual(order(a), order(b), "len\(length): the two forms rank the passages differently")
            for (x, y) in zip(a, b) {
                XCTAssertEqual(x, y, accuracy: 0.05, "len\(length): a logit moved between forms")
            }
        }
    }
}

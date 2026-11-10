//
//  RerankerModelTests.swift
//  OpenIntelligenceTests
//
//  Pins the bundled reranker (IBM granite-embedding-reranker-english-r2 since 5.8) to the Python reference that
//  `scripts/build_reranker_model.py` checks against: the app's tokenizer must produce the model's own token ids for a
//  question and passage, and each of the two Core ML functions must score the same pairs within rounding of the
//  Hugging Face model's logits. A tokenizer that splits words differently, or a model file from another build, would
//  still rank something, and nothing else would notice.
//

import CoreML
import XCTest

@testable import OpenIntelligence

final class RerankerModelTests: XCTestCase {
    /// The pairs, ids and logits printed by `scripts/build_reranker_model.py` on 2026-11-09 (transformers 5.22.2,
    /// revision d09d3d6971b689bf9c23839e45a470874d46e13a).
    private let pairs: [(query: String, passage: String, ids: [Int], logit: Float)] = [
        (
            "How many days notice ends the lease?",
            "Either party may terminate this lease with sixty (60) days written notice to the other party, delivered by certified mail.",
            [
                50281, 2347, 1142, 1897, 4366, 7637, 253, 16959, 32, 50282, 41311, 3128, 778, 24174, 436, 16959, 342,
                21116, 313, 1549, 10, 1897, 3542, 4366, 281, 253, 643, 3128, 13, 8549, 407, 18065, 8888, 15, 50282,
            ],
            2.800
        ),
        (
            "What was the retention time of benzo[a]pyrene?",
            "Table 1 lists retention times for the sixteen PAHs; benzo[a]pyrene eluted at 37.24 min under the gradient described in Section 2.3.",
            [
                50281, 1276, 369, 253, 17302, 673, 273, 2240, 8636, 60, 66, 62, 4789, 9457, 32, 50282, 3235, 337,
                10894, 17302, 2069, 323, 253, 25279, 8010, 31176, 28, 2240, 8636, 60, 66, 62, 4789, 9457, 48443, 387,
                5345, 15, 1348, 1054, 762, 253, 11786, 2529, 275, 5238, 374, 15, 20, 15, 50282,
            ],
            3.125
        ),
        (
            "What is the engine oil capacity?",
            "The kitchen was renovated in 2019 with quartz counters and a new range hood.",
            [
                50281, 1276, 310, 253, 3948, 4166, 5350, 32, 50282, 510, 8576, 369, 30074, 456, 275, 6247, 342, 40664,
                33605, 285, 247, 747, 2491, 21613, 15, 50282,
            ],
            0.799
        ),
    ]

    func testTokenizerMatchesTheModelsOwn() async throws {
        for pair in pairs {
            let ids = await RAGEngine.rerankerTokenIds(query: pair.query, passage: pair.passage)
            XCTAssertEqual(ids, pair.ids, "token ids differ for: \(pair.query)")
        }
        let pad = await RAGEngine.rerankerTokenId("[PAD]")
        let sep = await RAGEngine.rerankerTokenId("[SEP]")
        XCTAssertEqual(pad, 50283)
        XCTAssertEqual(sep, 50282)
    }

    func testBothFunctionsScoreLikeTheReference() async throws {
        let url = try XCTUnwrap(
            OpenIntelligenceResourceBundle.url(forResource: "ReRankerModel", withExtension: "mlmodelc"),
            "ReRankerModel.mlmodelc is not in the app")
        for length in [256, 512] {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            config.functionName = "len\(length)"
            let model = try MLModel(contentsOf: url, configuration: config)
            for pair in pairs {
                let encoded = await RAGEngine.rerankerTokenIds(query: pair.query, passage: pair.passage)
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
                let logit = try XCTUnwrap(out.featureValue(for: "logits")?.multiArrayValue)[0].floatValue
                // 4-bit palettized weights and float16 arithmetic move these logits slightly; the build script checks the same
                // pairs against the Hugging Face model and refuses a package more than 0.25 off.
                XCTAssertEqual(logit, pair.logit, accuracy: 0.25, "len\(length): \(pair.query)")
            }
        }
    }
}

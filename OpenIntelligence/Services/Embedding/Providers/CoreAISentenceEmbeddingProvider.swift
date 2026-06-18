//
//  CoreAISentenceEmbeddingProvider.swift
//  OpenIntelligence
//
//  Silicon-native embedding engine backed by Apple's new Core AI framework.
//

#if false
import Foundation
import Accelerate
import Tokenizers

#if canImport(CoreAI)
import CoreAI
#endif

@available(iOS 26.0, *)
final class CoreAISentenceEmbeddingProvider: EmbeddingProvider {
    // MARK: - Properties

    let dimension: Int = 384
    private let maxSequenceLength: Int

    #if canImport(CoreAI)
    private var model: AIModel?
    private var encodeFunction: InferenceFunction?
    #endif

    private var tokenizer: BertTokenizer?
    private let clsId: Int = 101
    private let sepId: Int = 102
    private let padId: Int = 0

    // MARK: - Init

    init(maxSequenceLength: Int = 512) {
        self.maxSequenceLength = maxSequenceLength
        setup()
    }

    private func setup() {
        // Load BertTokenizer vocabulary
        if let url = OpenIntelligenceResourceBundle.url(forResource: "embedding_vocab", withExtension: "json") {
            do {
                let vocabData = try Data(contentsOf: url)
                let vocabDict = try JSONDecoder().decode([String: Int].self, from: vocabData)
                tokenizer = BertTokenizer(
                    vocab: vocabDict,
                    merges: nil,
                    tokenizeChineseChars: true,
                    doLowerCase: true
                )
                Log.info("[CoreAISentenceEmbeddingProvider] Loaded tokenizer", category: .embedding)
            } catch {
                Log.error("[CoreAISentenceEmbeddingProvider] Failed to load tokenizer: \(error)", category: .embedding)
            }
        }

        #if canImport(CoreAI)
        // Load the .aimodel compiled from PyTorch
        let modelName = "EmbeddingModel"
        guard let url = OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "aimodel") else {
            Log.error("[CoreAISentenceEmbeddingProvider] Model \(modelName).aimodel not found in bundle", category: .embedding)
            return
        }

        Task {
            do {
                let loadedModel = try await AIModel(contentsOf: url)
                self.model = loadedModel
                self.encodeFunction = try loadedModel.loadFunction(named: "encode")
                Log.info("[CoreAISentenceEmbeddingProvider] Loaded Core AI model successfully", category: .embedding)
            } catch {
                Log.error("[CoreAISentenceEmbeddingProvider] Failed to load Core AI model: \(error)", category: .embedding)
            }
        }
        #endif
    }

    // MARK: - EmbeddingProvider Protocol

    var isAvailable: Bool {
        #if canImport(CoreAI)
        return model != nil && encodeFunction != nil && tokenizer != nil
        #else
        return false
        #endif
    }

    func countTokens(_ text: String) -> Int {
        guard let tokenizer = tokenizer else { return 0 }
        let tokens = tokenizer.tokenize(text: text)
        return tokens.count + 2
    }

    var maxSafeTokens: Int { maxSequenceLength - 2 }

    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }

        #if canImport(CoreAI)
        guard let encodeFunction = encodeFunction, let tokenizer = tokenizer else {
            throw EmbeddingError.modelUnavailable
        }

        let tokens = tokenizer.tokenize(text: text)
        var tokenIds = tokenizer.convertTokensToIds(tokens).compactMap { $0 }

        if tokenIds.count > maxSequenceLength - 2 {
            tokenIds = Array(tokenIds.prefix(maxSequenceLength - 2))
        }

        var inputIds = [clsId]
        inputIds.append(contentsOf: tokenIds)
        inputIds.append(sepId)

        let padLength = maxSequenceLength - inputIds.count
        if padLength > 0 {
            inputIds.append(contentsOf: repeatElement(padId, count: padLength))
        }

        // Zero-copy input tensor creation using the Swift array directly in unified memory
        let inputTensor = Tensor(shape: [1, maxSequenceLength], data: inputIds.map { Int32($0) })

        let outputs = try await encodeFunction.execute(["input_ids": inputTensor])
        guard let embeddingsTensor = outputs["embeddings"] else {
            throw EmbeddingError.outputParsingFailed
        }

        return embeddingsTensor.toArray(type: Float.self)
        #else
        throw EmbeddingError.modelUnavailable
        #endif
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try results.append(await embed(text: text))
        }
        return results
    }
}
#endif

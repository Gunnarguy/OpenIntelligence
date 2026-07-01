//
//  CoreAISentenceEmbeddingProvider.swift
//  OpenIntelligence
//
//  Silicon-native embedding engine backed by Apple's new Core AI framework.
//
import Foundation
import Accelerate
import Tokenizers

#if canImport(CoreAI)
import CoreAI
#endif

@available(iOS 27.0, macOS 27.0, *)
final class CoreAISentenceEmbeddingProvider: EmbeddingProvider {
    static let shared = CoreAISentenceEmbeddingProvider()

    // MARK: - Properties

    let dimension: Int = 384
    private let maxSequenceLength: Int

    #if canImport(CoreAI)
    private var model: AIModel?
    private var encodeFunction: InferenceFunction?
    #endif

    private var tokenizer: Tokenizer?
    private let clsId: Int = 101
    private let sepId: Int = 102
    private let padId: Int = 0

    // Async loading state tracking
    var isModelLoaded: Bool = false
    var isModelLoadingFailed: Bool = false

    // MARK: - Init

    init(maxSequenceLength: Int = 512) {
        self.maxSequenceLength = maxSequenceLength
        setup()
    }

    private func setup() {
        // Load Rust-backed tokenizer from the resource bundle directory
        if let url = OpenIntelligenceResourceBundle.url(forResource: "embedding_tokenizer", withExtension: nil) {
            Task {
                do {
                    tokenizer = try await AutoTokenizer.from(directory: url)
                    Log.info("[CoreAISentenceEmbeddingProvider] Loaded Rust-backed tokenizer", category: .embedding)
                } catch {
                    Log.error("[CoreAISentenceEmbeddingProvider] Failed to load tokenizer: \(error)", category: .embedding)
                }
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
                self.isModelLoaded = true
                Log.info("[CoreAISentenceEmbeddingProvider] Loaded Core AI model successfully", category: .embedding)
            } catch {
                self.isModelLoadingFailed = true
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

    func awaitReady() async {
        #if canImport(CoreAI)
        // Wait until isModelLoaded or isModelLoadingFailed is true AND tokenizer is not nil
        while (!isModelLoaded && !isModelLoadingFailed) || (tokenizer == nil && !isModelLoadingFailed) {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        #endif
    }

    func countTokens(_ text: String) -> Int {
        guard let tokenizer = tokenizer else { return 0 }
        do {
            let ids = try tokenizer.encode(text: text, addSpecialTokens: true)
            return ids.count
        } catch {
            return 0
        }
    }

    var maxSafeTokens: Int { maxSequenceLength }

    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }

        #if canImport(CoreAI)
        guard let encodeFunction = encodeFunction, let tokenizer = tokenizer else {
            throw EmbeddingError.modelUnavailable
        }

        var inputIds: [Int]
        do {
            inputIds = try tokenizer.encode(text: text, addSpecialTokens: true)
        } catch {
            throw EmbeddingError.outputParsingFailed
        }

        if inputIds.count > maxSequenceLength {
            inputIds = Array(inputIds.prefix(maxSequenceLength))
        } else if inputIds.count < maxSequenceLength {
            let padLength = maxSequenceLength - inputIds.count
            inputIds.append(contentsOf: repeatElement(padId, count: padLength))
        }

        // Zero-copy input tensor creation using the Swift array directly in unified memory
        let inputTensor = NDArray(scalars: inputIds.map { Int32($0) }, shape: [1, maxSequenceLength])

        var outputs = try await encodeFunction.run(inputs: ["input_ids": inputTensor])
        guard let embeddingsTensor = outputs.remove("embeddings")?.ndArray else {
            throw EmbeddingError.outputParsingFailed
        }

        let tensorView = embeddingsTensor.view(as: Float.self)
        guard let span = tensorView.contiguousElements else {
            throw EmbeddingError.outputParsingFailed
        }

        var array = [Float]()
        array.reserveCapacity(span.count)
        for i in 0..<span.count {
            array.append(span[i])
        }
        return array
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

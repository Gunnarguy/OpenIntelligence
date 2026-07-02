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
        if let url = OpenIntelligenceResourceBundle.url(forResource: "embedding_tokenizer", withExtension: "bundle") {
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
        var modelURL: URL? = nil
        
        if let url = OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "bundle") {
            modelURL = url
        } else if let mlirbURL = OpenIntelligenceResourceBundle.url(forResource: "main", withExtension: "mlirb") {
            modelURL = mlirbURL.deletingLastPathComponent()
            Log.info("[CoreAISentenceEmbeddingProvider] Core AI model flattened in bundle root, loading from parent directory", category: .embedding)
        }
        
        guard let sourceURL = modelURL else {
            self.isModelLoadingFailed = true
            Log.error("[CoreAISentenceEmbeddingProvider] Model \(modelName).bundle or main.mlirb not found in bundle", category: .embedding)
            return
        }

        // Core AI runtime strictly expects the model directory to end in .aimodel.
        // We create a symbolic link in the temporary directory ending in .aimodel pointing to the source directory.
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let symlinkURL = tempDir.appendingPathComponent("\(modelName).aimodel")
        
        do {
            // fileExists(atPath:) follows symlinks and returns false if the destination is missing.
            // Since app bundle UUIDs change on every build, the old symlink becomes broken.
            // We must unconditionally try to remove it.
            try? fileManager.removeItem(at: symlinkURL)
            
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: sourceURL)
            Log.info("[CoreAISentenceEmbeddingProvider] Created .aimodel symlink at \(symlinkURL.path)", category: .embedding)
        } catch {
            Log.error("[CoreAISentenceEmbeddingProvider] Failed to create symlink: \(error)", category: .embedding)
        }

        Task {
            do {
                let loadedModel = try await AIModel(contentsOf: symlinkURL)
                self.model = loadedModel
                // PyTorch export usually names the default graph "forward" or "main".
                self.encodeFunction = (try? loadedModel.loadFunction(named: "forward")) ?? 
                                      (try? loadedModel.loadFunction(named: "main")) ?? 
                                      (try? loadedModel.loadFunction(named: "encode"))
                
                if self.encodeFunction == nil {
                    throw EmbeddingError.modelUnavailable
                }
                
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
        return !isModelLoadingFailed
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
        await awaitReady()

        guard let encodeFunction = encodeFunction else {
            Log.error("[CoreAISentenceEmbeddingProvider] embed failed: encodeFunction is nil. isModelLoaded: \(isModelLoaded), isModelLoadingFailed: \(isModelLoadingFailed)", category: .embedding)
            throw EmbeddingError.modelUnavailable
        }
        guard let tokenizer = tokenizer else {
            Log.error("[CoreAISentenceEmbeddingProvider] embed failed: tokenizer is nil", category: .embedding)
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
        
        let tensorValue = outputs.remove("embeddings") ?? 
                          outputs.remove("output_0") ?? 
                          outputs.remove("output") ?? 
                          outputs.remove("_0")
        
        guard let embeddingsTensor = tensorValue?.ndArray else {
            Log.error("[CoreAISentenceEmbeddingProvider] missing output tensor (tried embeddings, output_0, output, _0).", category: .embedding)
            throw EmbeddingError.outputParsingFailed
        }

        let tensorView = embeddingsTensor.view(as: Float.self)
        
        var array = [Float]()
        if let span = tensorView.contiguousElements {
            array.reserveCapacity(span.count)
            for i in 0..<span.count {
                array.append(span[i])
            }
        } else {
            // Fallback for non-contiguous
            Log.error("[CoreAISentenceEmbeddingProvider] Tensor is not contiguous! This is the cause of the outputParsingFailed error.", category: .embedding)
            throw EmbeddingError.outputParsingFailed
        }
        return array
        #else
        Log.error("[CoreAISentenceEmbeddingProvider] embed failed: canImport(CoreAI) is false at compile time in this compilation unit", category: .embedding)
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

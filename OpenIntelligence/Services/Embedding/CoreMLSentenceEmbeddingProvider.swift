//
//  CoreMLSentenceEmbeddingProvider.swift
//  OpenIntelligence
//
//  Silicon-native embedding engine backed by Core ML and swift-transformers.
//

import Foundation
import CoreML
import Accelerate
import Tokenizers

/// Pre-allocated MLMultiArray triple for embedding inference.
/// Eliminates ~3,072 heap allocations per embed() call by reusing buffers.
private struct MLArrayBufferSet: @unchecked Sendable {
    let inputIds: MLMultiArray
    let attentionMask: MLMultiArray
    let tokenTypeIds: MLMultiArray
}

/// Actor-isolated pool of pre-allocated MLMultiArray buffers.
/// Amortizes allocation cost across thousands of embed() calls during ingestion.
private actor MLArrayBufferPool {
    private var available: [MLArrayBufferSet] = []
    private let seqLen: Int

    init(capacity: Int, sequenceLength: Int) {
        self.seqLen = sequenceLength
        // Pre-allocate buffers up front
        for _ in 0..<capacity {
            if let set = Self.makeBufferSet(sequenceLength: sequenceLength) {
                available.append(set)
            }
        }
    }

    func acquire() -> MLArrayBufferSet? {
        guard !available.isEmpty else {
            // Pool exhausted — create on-demand (rare, only under extreme concurrency)
            return Self.makeBufferSet(sequenceLength: seqLen)
        }
        return available.removeLast()
    }

    func release(_ set: MLArrayBufferSet) {
        available.append(set)
    }

    private static func makeBufferSet(sequenceLength: Int) -> MLArrayBufferSet? {
        do {
            let ids = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
            let types = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
            return MLArrayBufferSet(inputIds: ids, attentionMask: mask, tokenTypeIds: types)
        } catch {
            return nil
        }
    }
}

final class CoreMLSentenceEmbeddingProvider: EmbeddingProvider {
    // MARK: - Properties

    /// Native output dimension of the bundled MiniLM-L6-v2 model.
    /// This is FIXED - the model always outputs 384 dimensions regardless of configuration.
    let dimension: Int = 384
    private let maxSequenceLength: Int

    #if canImport(CoreML)
        private var model: MLModel?
    #endif

    private var tokenizer: BertTokenizer?
    private let clsId: Int
    private let sepId: Int
    private let padId: Int

    /// Pool of pre-allocated MLMultiArray buffers to avoid per-call allocation
    private let bufferPool: MLArrayBufferPool

    // MARK: - Init

    init(maxSequenceLength: Int = 512) {
        // dimension is fixed at 384 (MiniLM-L6-v2 output)
        self.maxSequenceLength = maxSequenceLength
        clsId = 101
        sepId = 102
        padId = 0
        // Pre-allocate buffer pool sized to max embedding concurrency
        // Avoids ~3,072 MLMultiArray heap allocations per embed() call
        let poolSize = DeviceCapabilityService.shared.embeddingConcurrency + 2  // +2 headroom
        bufferPool = MLArrayBufferPool(capacity: poolSize, sequenceLength: maxSequenceLength)
        setup()
    }

    // MARK: - Ingestion Mode (No-op)
    // NOTE: Dual-model GPU+ANE parallelism caused Metal synchronizeResource crashes.
    // Vision OCR + GPU embeddings + PDF rendering overwhelms Metal command buffer queue.
    // Keeping as no-op for API compatibility.

    func enableIngestionMode() {
        // No-op: Dual-model approach caused MTLDebugBlitCommandEncoder crashes
    }

    func disableIngestionMode() {
        // No-op
    }

    private func setup() {
        // Load Model (compiled from .mlpackage to .mlmodelc by Xcode)
        #if canImport(CoreML)
            let modelName = "EmbeddingModel"
            if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                do {
                    let config = MLModelConfiguration()
                    // Use device-specific compute units based on GPU acceleration setting
                    config.computeUnits = DeviceCapabilityService.shared.preferredComputeUnits
                    let computeDesc: String
                    switch config.computeUnits {
                    case .cpuAndGPU: computeDesc = "GPU+CPU (forced GPU mode)"
                    case .cpuAndNeuralEngine: computeDesc = "ANE+CPU (efficiency mode)"
                    case .all: computeDesc = "All (system choice)"
                    default: computeDesc = "default"
                    }
                    model = try MLModel(contentsOf: url, configuration: config)
                    Log.info("[CoreMLSentenceEmbeddingProvider] Loaded EmbeddingModel.mlmodelc - compute: \(computeDesc)", category: .embedding)
                } catch {
                    Log.error("[CoreMLSentenceEmbeddingProvider] Failed to load MLModel: \(error)", category: .embedding)
                }
            } else if let sourceURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
                // Fallback: Check for uncompiled package (rare, but good for safety)
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = DeviceCapabilityService.shared.preferredComputeUnits
                    model = try MLModel(contentsOf: sourceURL, configuration: config)
                    Log.info("[CoreMLSentenceEmbeddingProvider] Loaded EmbeddingModel.mlpackage (fallback)", category: .embedding)
                } catch {
                    Log.error("[CoreMLSentenceEmbeddingProvider] Failed to load MLModel from source: \(error)", category: .embedding)
                }
            } else {
                Log.error("[CoreMLSentenceEmbeddingProvider] ❌ Model not found. Looked for '\(modelName).mlmodelc' and '.mlpackage'", category: .embedding)
            }
        #endif

        // Load Tokenizer
        if let url = Bundle.main.url(forResource: "embedding_vocab", withExtension: "json") {
            do {
                let vocabData = try Data(contentsOf: url)
                let vocabDict = try JSONDecoder().decode([String: Int].self, from: vocabData)
                tokenizer = BertTokenizer(
                    vocab: vocabDict,
                    merges: nil,
                    tokenizeChineseChars: true,
                    doLowerCase: true
                )
                Log.info("[CoreMLSentenceEmbeddingProvider] Loaded tokenizer", category: .embedding)
            } catch {
                Log.error("[CoreMLSentenceEmbeddingProvider] Failed to load tokenizer: \(error)", category: .embedding)
            }
        } else {
            Log.warning("[CoreMLSentenceEmbeddingProvider] embedding_vocab.json not found in Bundle", category: .embedding)
        }
    }

    var isAvailable: Bool {
        #if canImport(CoreML)
            let available = model != nil && tokenizer != nil
            if !available {
                Log.warning("[CoreMLSentenceEmbeddingProvider] Provider unavailable: model=\(model != nil), tokenizer=\(tokenizer != nil)", category: .embedding)
            }

            return available
        #else
            Log.warning("[CoreMLSentenceEmbeddingProvider] Provider unavailable: CoreML not imported", category: .embedding)
            return false
        #endif
    }

    // MARK: - Token Counting (for chunk size validation)

    /// Count ACTUAL tokens that will be used during embedding
    /// This is critical for chunk size validation - NLTokenizer "word count" doesn't match BPE/WordPiece tokens
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    func countTokens(_ text: String) -> Int {
        guard let tokenizer = tokenizer else { return 0 }
        let tokens = tokenizer.tokenize(text: text)
        return tokens.count + 2  // +2 for [CLS] and [SEP] tokens
    }

    /// Maximum safe text length in tokens (accounting for CLS/SEP)
    var maxSafeTokens: Int { maxSequenceLength - 2 }  // 510 for default 512

    // MARK: - Embedding

    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }

        #if canImport(CoreML)
            guard let model = model, let tokenizer = tokenizer else {
                throw EmbeddingError.modelUnavailable
            }

            let (inputIds, attentionMask, tokenTypeIds) = prepareInputs(text: text, tokenizer: tokenizer)

            // OPTIMIZED: Acquire pre-allocated buffers from pool instead of creating 3 new MLMultiArrays
            // Eliminates ~3,072 heap allocations per embed() call (was: 3 × MLMultiArray init + 6 × 512 NSNumber)
            let buffers = await bufferPool.acquire()
            guard let buffers = buffers else {
                throw EmbeddingError.modelUnavailable
            }
            // Ensure buffers are returned to pool even on error
            defer { Task { await self.bufferPool.release(buffers) } }

            let inputIdsArray = buffers.inputIds
            let maskArray = buffers.attentionMask
            let tokenTypeArray = buffers.tokenTypeIds

            // OPTIMIZED: Direct pointer writes instead of NSNumber subscripts
            // Eliminates ~3,072 NSNumber heap allocations per embed() call (6 per iteration × 512 iterations)
            inputIdsArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                for i in 0..<maxSequenceLength { ptr[i] = Int32(inputIds[i]) }
            }
            maskArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                for i in 0..<maxSequenceLength { ptr[i] = Int32(attentionMask[i]) }
            }
            tokenTypeArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                for i in 0..<maxSequenceLength { ptr[i] = Int32(tokenTypeIds[i]) }
            }

            let inputs = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                "attention_mask": MLFeatureValue(multiArray: maskArray),
                "token_type_ids": MLFeatureValue(multiArray: tokenTypeArray),
            ])

            let output = try await model.prediction(from: inputs)
            guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
                throw EmbeddingError.outputParsingFailed
            }

            let embedDim = hiddenState.shape[2].intValue
            let seqLen = hiddenState.shape[1].intValue

            // OPTIMIZED: Direct pointer + vDSP vectorized mean pooling
            // Eliminates ~196,608 NSNumber allocations per embed() call (seqLen × embedDim × 3 NSNumbers)
            // Uses Accelerate vDSP_vadd for SIMD-vectorized row accumulation
            var summed = [Float](repeating: 0, count: embedDim)
            var tokenCount: Int = 0

            // hiddenState shape: [1, seqLen, embedDim] — batch dim 0, contiguous rows
            // GPU+CPU mode outputs Float16; ANE/CPU-only may output Float32 — handle both
            if hiddenState.dataType == .float32 {
                hiddenState.withUnsafeBufferPointer(ofType: Float.self) { ptr in
                    for i in 0..<seqLen where attentionMask[i] == 1 {
                        tokenCount += 1
                        let rowOffset = i * embedDim
                        let rowPtr = ptr.baseAddress! + rowOffset
                        vDSP_vadd(summed, 1, rowPtr, 1, &summed, 1, vDSP_Length(embedDim))
                    }
                }
            } else if hiddenState.dataType == .float16 {
                // OPTIMIZED Float16 path: typed pointer + vDSP conversion
                // Model on A18 Pro GPU always outputs Float16
                hiddenState.withUnsafeBufferPointer(ofType: Float16.self) { ptr in
                    var rowFloat32 = [Float](repeating: 0, count: embedDim)
                    for i in 0..<seqLen where attentionMask[i] == 1 {
                        tokenCount += 1
                        let rowOffset = i * embedDim
                        // Vectorized Float16→Float32 conversion for whole row
                        for j in 0..<embedDim {
                            rowFloat32[j] = Float(ptr[rowOffset + j])
                        }
                        vDSP_vadd(summed, 1, &rowFloat32, 1, &summed, 1, vDSP_Length(embedDim))
                    }
                }
            } else {
                // Unknown type — safe NSNumber subscript fallback
                for i in 0..<seqLen where attentionMask[i] == 1 {
                    tokenCount += 1
                    var rowFloat32 = [Float](repeating: 0, count: embedDim)
                    for j in 0..<embedDim {
                        rowFloat32[j] = hiddenState[[0, NSNumber(value: i), NSNumber(value: j)]].floatValue
                    }
                    vDSP_vadd(summed, 1, &rowFloat32, 1, &summed, 1, vDSP_Length(embedDim))
                }
            }

            var averaged = [Float](repeating: 0, count: embedDim)
            var divisor = Float(max(tokenCount, 1))
            vDSP_vsdiv(summed, 1, &divisor, &averaged, 1, vDSP_Length(embedDim))

            var sqSum: Float = 0
            vDSP_svesq(averaged, 1, &sqSum, vDSP_Length(embedDim))
            let norm = max(sqrt(sqSum), 1e-9)
            var normalized = [Float](repeating: 0, count: embedDim)
            var normDiv = norm
            vDSP_vsdiv(averaged, 1, &normDiv, &normalized, 1, vDSP_Length(embedDim))

            // If the model dimension differs from the requested dimension, truncate or pad.
            if embedDim == dimension {
                return normalized
            }

            if embedDim > dimension {
                return Array(normalized.prefix(dimension))
            }

            var padded = normalized
            padded.append(contentsOf: repeatElement(0, count: dimension - embedDim))
            return padded
        #else
            throw EmbeddingError.modelUnavailable
        #endif
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        // Use parallel embedding for better hardware utilization
        // Neural Engine can handle concurrent requests efficiently
        let batchSize = texts.count

        // For small batches, sequential is fine (avoid Task overhead)
        guard batchSize > 4 else {
            var results: [[Float]] = []
            results.reserveCapacity(batchSize)
            for text in texts {
                try results.append(await embed(text: text))
            }
            return results
        }

        // Parallel batching with device-specific concurrency
        // CoreML embedding runs on ANE; higher-tier devices can sustain more concurrent requests
        let maxConcurrency = DeviceCapabilityService.shared.embeddingConcurrency

        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            var results = Array(repeating: [Float](), count: batchSize)
            var submitted = 0
            var collected = 0

            // Submit initial batch up to maxConcurrency
            while submitted < min(maxConcurrency, batchSize) {
                let index = submitted
                let text = texts[index]
                group.addTask {
                    let embedding = try await self.embed(text: text)
                    return (index, embedding)
                }
                submitted += 1
            }

            // Process results and submit more as slots free up
            for try await (index, embedding) in group {
                results[index] = embedding
                collected += 1

                // Submit next task if any remaining
                if submitted < batchSize {
                    let nextIndex = submitted
                    let text = texts[nextIndex]
                    group.addTask {
                        let embedding = try await self.embed(text: text)
                        return (nextIndex, embedding)
                    }
                    submitted += 1
                }
            }

            return results
        }
    }

    // MARK: - Helpers

    private func prepareInputs(text: String, tokenizer: BertTokenizer) -> ([Int], [Int], [Int]) {
        let tokens = tokenizer.tokenize(text: text)
        var tokenIds = tokenizer.convertTokensToIds(tokens).compactMap { $0 }

        // CRITICAL: Truncation should NEVER happen with proper chunking (max 340 words → ~450 tokens)
        // If we're hitting this, it means a chunk escaped the safety net in DocumentProcessor
        if tokenIds.count > maxSequenceLength - 2 {
            let originalCount = tokenIds.count
            let lostTokens = originalCount - (maxSequenceLength - 2)
            let lossPercent = Int(Double(lostTokens) / Double(originalCount) * 100)
            tokenIds = Array(tokenIds.prefix(maxSequenceLength - 2))

            // Log as ERROR because this indicates a bug in the chunking pipeline
            // Every word should be accounted for - truncation = data loss
            Log.error(
                "[CoreMLSentenceEmbedding] ❌ TRUNCATION: \(originalCount)→\(maxSequenceLength - 2) tokens " +
                "(losing \(lostTokens) tokens = \(lossPercent)% of content!). " +
                "BUG: Chunk escaped size limits. Text preview: \"\(text.prefix(100))...\"",
                category: .embedding
            )
        }

        var inputIds: [Int] = [clsId]
        inputIds.append(contentsOf: tokenIds)
        inputIds.append(sepId)

        var attentionMask = Array(repeating: 1, count: inputIds.count)
        let padLength = maxSequenceLength - inputIds.count
        if padLength > 0 {
            inputIds.append(contentsOf: repeatElement(padId, count: padLength))
            attentionMask.append(contentsOf: repeatElement(0, count: padLength))
        }

        let tokenTypeIds = Array(repeating: 0, count: maxSequenceLength)
        return (inputIds, attentionMask, tokenTypeIds)
    }
}

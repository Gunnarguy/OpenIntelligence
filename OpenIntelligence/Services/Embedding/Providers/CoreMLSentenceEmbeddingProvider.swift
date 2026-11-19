//
//  CoreMLSentenceEmbeddingProvider.swift
//  OpenIntelligence
//
//  Silicon-native embedding engine backed by Core ML and swift-transformers.
//

import Accelerate
import CoreML
import Foundation
import Tokenizers

nonisolated final class CoreMLSentenceEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    /// Output dimension of the bundled model, IBM's granite-embedding-small-english-r2 (5.8; MiniLM-L6-v2 before, also
    /// 384). Fixed by the model.
    let dimension: Int = 384

    /// Pooling this provider actually performs. Part of `EmbeddingFingerprint`.
    ///
    /// Core ML mean-pools over the attention mask in Swift; Core AI reads `last_hidden_state[:, 0, :]`,
    /// the CLS position. Same weights, different vectors — the difference measured at
    /// `vector r@1` 0.000 to 0.571. Change this string whenever that changes.
    ///
    /// Since 5.8 the model is Granite small english r2, whose own pooling is its CLS vector; the graph takes it and
    /// L2-normalises it (`scripts/build_embedding_model.py`), so Swift does no pooling. MiniLM-L6-v2, through 5.7, was
    /// trained on MS MARCO, whose terms allow non-commercial research only (the owner's rule 1, 2026-11-12).
    var poolingRecipe: String { "cls-in-graph/l2" }
    var modelRevision: String { "granite-embedding-small-english-r2@2ab6fa8e/coreml-len256-len512" }
    private let maxSequenceLength: Int

    #if canImport(CoreML)
        /// Loaded on first use, never in `init`.
        ///
        /// This is a 43 MiB model and `MLModel(contentsOf:configuration:)` is synchronous. It used
        /// to load inside `setup()`, called from `init`, reached from `ContentView.init` by way of
        /// `RAGService` — so every launch paid for it before the first frame, and four device
        /// captures on 2026-08-18 recorded launch hangs of 2.94s, 3.75s, 4.31s and 4.06s. In none
        /// of those sessions did anything embed, so the cost bought nothing at all.
        ///
        /// Deferring it removes the work rather than moving it: a session that never ingests and
        /// never queries never loads the model.
        private var models: [(length: Int, model: MLModel)] = []

        /// Guards `model` against N concurrent first-callers each loading their own 43 MiB copy.
        ///
        /// `embed` runs at `DeviceCapabilityService.embeddingConcurrency` > 1 on background threads (the class is
        /// `nonisolated` and `@unchecked Sendable` since 2026-11-04), and Swift 5 language mode will not diagnose a
        /// race. The lock is held across the load, so the second caller waits for the first rather than duplicating
        /// it. A waiter blocks its thread for the load, so `embedBatch` loads once before it fans out.
        private let modelLock = NSLock()

        /// Set once a load has been attempted, successfully or not, so a missing or corrupt model
        /// is not re-read from disk on every embed call.
        private var modelLoadAttempted = false

        /// The compute units `model` was loaded with, and the ones the next `loadedModels()` should switch it to.
        ///
        /// An ingestion-mode switch only records what it wants (5.7); the reload happens in `loadedModels()`, on the
        /// next embed, which runs off the main thread. The switch is called from `RAGService.addDocument` on the main
        /// actor, and reloading this 43 MiB model there held the main thread for 2.36 s at the start of an import on
        /// the owner's iPhone (Instruments, 2026-10-21).
        private var loadedComputeUnits: MLComputeUnits?
        private var wantedComputeUnits: MLComputeUnits?
        /// When a failed prediction moved the model to the CPU (`prediction(from:length:model:)`); it goes back to the
        /// device's own compute units two minutes later.
        private var movedToCPUAt: Date?
        /// An import's units in front and in the background (5.8), read on the main actor when it starts, so
        /// `loadedModels()` can follow the app between them off the main thread.
        private var ingestionForegroundUnits: MLComputeUnits?
        private var ingestionBackgroundUnits: MLComputeUnits?
        /// Units whose load failed during this import, not tried again until the next one (5.8): a failed switch was
        /// otherwise tried on every embed, each a 43 MiB load attempt under `modelLock`.
        private var failedIngestionUnits: MLComputeUnits?
    #endif

    /// Written once by the load task in `loadTokenizer()` and read by `embed` and `countTokens`.
    ///
    /// The class is `nonisolated` and `embed` is `@concurrent` since 2026-11-04 (tokenizing and pooling held the
    /// main thread before), so the load task and up to `embeddingConcurrency` embeds touch this from different
    /// threads. The tokenizer itself is `Sendable` (swift-tokenizers' `Tokenizer` protocol); only this reference
    /// needs the lock.
    private var _tokenizer: Tokenizer?
    private let tokenizerLock = NSLock()
    private var tokenizer: Tokenizer? {
        get {
            tokenizerLock.lock()
            defer { tokenizerLock.unlock() }
            return _tokenizer
        }
        set {
            tokenizerLock.lock()
            _tokenizer = newValue
            tokenizerLock.unlock()
        }
    }
    private let clsId: Int
    private let sepId: Int
    private let padId: Int

    // MARK: - Init

    init(maxSequenceLength: Int = 512) {
        self.maxSequenceLength = maxSequenceLength
        // Granite's tokenizer: [CLS] 50281, [SEP] 50282, [PAD] 50283 (its tokenizer.json). The padding never reaches
        // the vector: the attention mask hides it in every layer.
        clsId = 50281
        sepId = 50282
        padId = 50283
        setup()
    }

    // MARK: - Ingestion Mode (GPU ↔ ANE Parallelism)
    // During ingestion, Vision OCR saturates the Neural Engine (16-core ANE).
    // Reloading the embedding model with .cpuAndGPU compute units forces embeddings
    // to run on GPU, creating TRUE parallelism: ANE → Vision OCR, GPU → Embeddings.
    //
    // This is NOT the dual-model approach that caused MTLDebugBlitCommandEncoder crashes.
    // We reload the SINGLE model with different compute units. An embed that already holds the old
    // model can still finish its prediction while the new one loads, so for the length of a reload two
    // copies can briefly be in use; that was true before embedding left the main thread (an `await`
    // let predictions overlap a reload) and is a wider window now.

    /// Guards the ingestion-mode state below, and only that, so switching the mode never waits for a model load (5.8,
    /// 2026-11-18). The switch took `modelLock`, which a load holds for as long as Core ML takes: on the owner's iPhone
    /// an import started while the app was in the background called `enableIngestionMode()` on the main thread, it
    /// waited on a load holding that lock, and iOS killed the app after 10 s (`0x8BADF00D`, scene-update watchdog,
    /// main thread in `__psynch_mutexwait` under `enableIngestionMode`). Lock order: `modelLock`, then `modeLock`.
    private let modeLock = NSLock()
    private var isIngestionMode = false
    /// Whether a model has been loaded, read by `disableIngestionMode()` without taking `modelLock`.
    private var hasLoadedModel = false

    func enableIngestionMode() {
        #if canImport(CoreML)
            // Nothing loads here: the model switches on the next embed (`loadedModels()`).
            let units = DeviceCapabilityService.shared.embeddingComputeUnitsDuringIngestion
            let inFront = DeviceCapabilityService.shared.embeddingComputeUnitsInFront
            let switched = modeLock.withLock { () -> Bool in
                guard !isIngestionMode else { return false }
                isIngestionMode = true
                wantedComputeUnits = units
                ingestionForegroundUnits = inFront
                ingestionBackgroundUnits = DeviceCapabilityService.embeddingComputeUnitsInBackground
                failedIngestionUnits = nil
                return true
            }
            if switched {
                Log.info(
                    "[CoreMLSentenceEmbeddingProvider] ⚡ Ingestion mode ON (the model switches on the next embed)",
                    category: .embedding)
            }
        #endif
    }

    func disableIngestionMode() {
        #if canImport(CoreML)
            let units = DeviceCapabilityService.shared.preferredComputeUnits
            let switched = modeLock.withLock { () -> Bool in
                guard isIngestionMode else { return false }
                isIngestionMode = false
                ingestionForegroundUnits = nil
                ingestionBackgroundUnits = nil
                failedIngestionUnits = nil
                // Only restore a model that was actually loaded. If nothing has embedded yet there is
                // nothing to restore, and loading 43 MiB here would reintroduce the cost this change
                // exists to remove, on a path the user cannot see.
                guard hasLoadedModel || wantedComputeUnits != nil else { return false }
                wantedComputeUnits = units
                return true
            }
            if switched {
                Log.info(
                    "[CoreMLSentenceEmbeddingProvider] Ingestion mode OFF (default compute units on the next embed)",
                    category: .embedding)
            }
        #endif
    }

    private func setup() {
        // The model is NOT loaded here; see `models` and `loadedModels()`. Only the tokenizer is,
        // because it is small, it is needed to answer `countTokens` without embedding anything,
        // and it already loads asynchronously.
        loadTokenizer()
    }

    /// Load the model's two functions on first use, shortest first. Empty if they cannot be loaded.
    #if canImport(CoreML)
        private func loadedModels() -> [(length: Int, model: MLModel)] {
            modelLock.lock()
            defer { modelLock.unlock() }

            var afterCPU: MLComputeUnits?
            if let moved = movedToCPUAt, Date().timeIntervalSince(moved) > 120 {
                movedToCPUAt = nil
                afterCPU = DeviceCapabilityService.shared.preferredComputeUnits
            }
            // An import's units follow where the app is (5.8, 2026-11-18). They were chosen once, when the import began: on
            // the owner's iPhone an import started in front loaded the model for all units, the app was left, iOS took the
            // GPU away (`backgroundGPU=disabled`), and the first prediction 2 minutes later waited 2 min 20 s with no answer
            // until the background task expired and cancelled it; coming back, the import sat queued behind that wait. The
            // background profile (`isBackgroundCPUSafeIngestionProfileActive`, set on every scene-phase change) is read on
            // each embed, and a change reloads the model before it predicts.
            let loaded = loadedComputeUnits
            let onCPUAfterFailure = movedToCPUAt != nil
            let inBackground =
                DeviceCapabilityService.isBackgroundCPUSafeIngestionProfileActive
                || DeviceCapabilityService.isAppInBackground
            // During an import the units are decided here, where the app is now, and they override a switch still
            // pending from when the import began: an import left before its first embed would otherwise load the units
            // chosen in front (review, 2026-11-18). After a failed prediction moved the model to the CPU it stays there
            // for the import; units whose load failed are not tried again in it.
            let wantedNow: MLComputeUnits? = modeLock.withLock {
                defer { wantedComputeUnits = nil }
                if isIngestionMode {
                    guard !onCPUAfterFailure,
                        let live = inBackground ? ingestionBackgroundUnits : ingestionForegroundUnits,
                        live != failedIngestionUnits
                    else { return nil }
                    if let loaded, live != loaded {
                        Log.info(
                            "[CoreMLSentenceEmbeddingProvider] Import \(inBackground ? "in the background" : "in front"); loading the model for compute units \(live.rawValue)",
                            category: .embedding)
                    }
                    return live
                }
                if let pending = afterCPU ?? wantedComputeUnits {
                    // A switch asked for in front (an import ending, the CPU fallback expiring) waits for the front.
                    return DeviceCapabilityService.isAppInBackground
                        ? DeviceCapabilityService.embeddingComputeUnitsInBackground : pending
                }
                // Outside an import the model follows the app too (5.8, 2026-11-19). On the owner's iPhone a Standard
                // answer finished writing just after he left the app (08:17:44), and the source check's embedding, on the
                // model loaded in front for all units, waited 2 min 10 s with no answer until iOS ended the background
                // time (08:19:54, "Unable to compute the asynchronous prediction"); the chat said "Checking sources..."
                // even after he came back. The same wait happened at 08:12:40. In the background the GPU is not
                // available (`backgroundGPU=disabled`), so an embed there loads the background units first, and the next
                // embed in front loads the device's own units again.
                guard !onCPUAfterFailure, let loaded else { return nil }
                let background = DeviceCapabilityService.embeddingComputeUnitsInBackground
                let appInBackground = DeviceCapabilityService.isAppInBackground
                if appInBackground, loaded != background { return background }
                if !appInBackground, loaded == background {
                    let inFront = DeviceCapabilityService.shared.preferredComputeUnits
                    return inFront == background ? nil : inFront
                }
                return nil
            }
            if let wanted = wantedNow {
                if models.isEmpty || loadedComputeUnits != wanted {
                    let reloaded = Self.makeModels(computeUnits: wanted)
                    if !reloaded.isEmpty {
                        models = reloaded
                        loadedComputeUnits = wanted
                        modelLoadAttempted = true
                        Log.info(
                            "[CoreMLSentenceEmbeddingProvider] Model loaded for compute units \(wanted.rawValue)",
                            category: .embedding)
                    } else {
                        modeLock.withLock { if isIngestionMode { failedIngestionUnits = wanted } }
                        Log.error(
                            "[CoreMLSentenceEmbeddingProvider] Failed to load the model for compute units \(wanted.rawValue); keeping the one loaded",
                            category: .embedding)
                    }
                }
            }
            if !models.isEmpty {
                modeLock.withLock { hasLoadedModel = true }
                return models
            }
            if modelLoadAttempted { return [] }
            modelLoadAttempted = true

            // The first load follows the app too (5.8, 2026-11-19): on the owner's iPhone a question asked just before he
            // left was the first embed after an install, the model loaded for all units in the background (09:25:41, 21 s),
            // and its prediction waited on a GPU iOS does not give a background app.
            let units =
                DeviceCapabilityService.isAppInBackground
                ? DeviceCapabilityService.embeddingComputeUnitsInBackground
                : DeviceCapabilityService.shared.preferredComputeUnits
            models = Self.makeModels(computeUnits: units)
            if !models.isEmpty {
                loadedComputeUnits = units
                modeLock.withLock { hasLoadedModel = true }
            }
            return models
        }

        /// One prediction that survives the model's handle going bad (5.8, 2026-11-13).
        ///
        /// On the owner's iPhone a Maximum question asked while the app was left and reopened three times failed whole
        /// with "Unable to compute the asynchronous prediction using ML Program" from this model, 12 s after the app came
        /// back, and Chat said "Something went wrong". The loaded model was held from before the app was suspended; a
        /// prediction on the Neural Engine can fail after that, or while the app is in the background. An embedding is
        /// too small a thing to lose an answer over: the model is loaded again and the prediction retried, and if that
        /// fails too it runs on the CPU, where nothing can be taken away (the same vectors to float rounding). Each step
        /// is journaled (`embedding.predictionRetry`).
        private func prediction(
            from inputs: MLFeatureProvider, length: Int, model: MLModel
        ) async throws -> MLFeatureProvider {
            do {
                return try await model.prediction(from: inputs)
            } catch {
                Log.warning(
                    "[CoreMLSentenceEmbeddingProvider] Prediction failed (\(error.localizedDescription)); loading the model again",
                    category: .embedding)
                // In the background the retry loads the units iOS allows there (5.8, 2026-11-19): retrying on the units that
                // just failed reloaded the model for all units, GPU included, and waited another 4 min 27 s before the CPU
                // attempt answered (owner's iPhone, 08:19:54 to 08:24:22).
                let units =
                    DeviceCapabilityService.isAppInBackground
                    ? DeviceCapabilityService.embeddingComputeUnitsInBackground
                    : (modelLock.withLock { loadedComputeUnits } ?? DeviceCapabilityService.shared.preferredComputeUnits)
                for (attempt, computeUnits) in [units, MLComputeUnits.cpuOnly].enumerated() {
                    let reloaded = Self.makeModels(computeUnits: computeUnits)
                    guard let fresh = reloaded.first(where: { $0.length == length })?.model else { continue }
                    do {
                        let output = try await fresh.prediction(from: inputs)
                        modelLock.withLock {
                            models = reloaded
                            loadedComputeUnits = computeUnits
                            movedToCPUAt = computeUnits == .cpuOnly && units != .cpuOnly ? Date() : nil
                        }
                        VerificationJournal.record(
                            "embedding.predictionRetry", .ok,
                            ["attempt": "\(attempt + 1)", "cpu": "\(computeUnits == .cpuOnly)"])
                        return output
                    } catch {
                        Log.warning(
                            "[CoreMLSentenceEmbeddingProvider] Retry \(attempt + 1) failed: \(error.localizedDescription)",
                            category: .embedding)
                    }
                }
                VerificationJournal.record("embedding.predictionRetry", .failed, ["error": error.localizedDescription])
                throw error
            }
        }

        /// The model's functions, `len256` and `len512`, at the given compute units, or empty.
        ///
        /// Loaded from one fixed copy (`RerankerModelLocation`, 5.8): Core ML finds the form it compiled for the Neural
        /// Engine by the model's location, and loading from the app bundle compiled again on most launches on the owner's
        /// iPhone (measured for the reranker, 2026-11-12).
        private static func makeModels(computeUnits: MLComputeUnits) -> [(length: Int, model: MLModel)] {
            let modelName = "EmbeddingModel"
            let computeDesc: String
            switch computeUnits {
            case .cpuAndGPU: computeDesc = "GPU+CPU"
            case .cpuAndNeuralEngine: computeDesc = "ANE+CPU"
            case .all: computeDesc = "All (system choice)"
            default: computeDesc = "default"
            }
            guard
                let bundled = OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "mlmodelc")
                    ?? OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "mlpackage")
            else {
                Log.error(
                    "[CoreMLSentenceEmbeddingProvider] ❌ Model not found. Looked for '\(modelName).mlmodelc' and '.mlpackage'",
                    category: .embedding)
                VerificationJournal.record("embedding.load", .failed, ["error": "notFound"])
                return []
            }
            let location = RerankerModelLocation.loadURL(for: bundled)
            let started = Date()
            var loaded: [(length: Int, model: MLModel)] = []
            for length in Self.functionLengths {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = computeUnits
                    config.functionName = "len\(length)"
                    // Maximum favours prediction speed over load time, memory and disk (5.8).
                    if DeviceCapabilityService.maximumProfileSelected {
                        config.optimizationHints.specializationStrategy = .fastPrediction
                    }
                    loaded.append((length, try MLModel(contentsOf: location.url, configuration: config)))
                } catch {
                    Log.error(
                        "[CoreMLSentenceEmbeddingProvider] Failed to load function len\(length): \(error)",
                        category: .embedding)
                }
            }
            let seconds = Date().timeIntervalSince(started)
            guard loaded.count == Self.functionLengths.count else {
                VerificationJournal.record(
                    "embedding.load", .failed, ["error": "function", "loaded": "\(loaded.count)"])
                return []
            }
            Log.info(
                "[CoreMLSentenceEmbeddingProvider] Loaded \(location.url.lastPathComponent) (\(location.fixedPath ? "fixed path" : "bundle")) in \(String(format: "%.2f", seconds)) s"
                    + " - compute: \(computeDesc)", category: .embedding)
            VerificationJournal.record(
                "embedding.load", .ok, durationMs: seconds * 1000,
                [
                    "compute": computeDesc, "newInstall": "\(VerificationJournal.firstLaunchOfThisInstall)",
                    "fastPrediction": "\(DeviceCapabilityService.maximumProfileSelected)",
                    "fixedPath": "\(location.fixedPath)",
                ])
            return loaded
        }

        /// The model's fixed input lengths: a fixed shape is what the Neural Engine runs, and most passages fit 256
        /// (median 210 tokens with their prefix, 90th percentile 390; 2026-11-08), which runs faster than 512.
        static let functionLengths = [256, 512]
    #endif

    private func loadTokenizer() {
        // Load Tokenizer
        if let url = OpenIntelligenceResourceBundle.url(forResource: "embedding_tokenizer", withExtension: "bundle") {
            Task {
                do {
                    tokenizer = try await AutoTokenizer.from(directory: url)
                    Log.info("[CoreMLSentenceEmbeddingProvider] Loaded Rust-backed tokenizer", category: .embedding)
                } catch {
                    Log.error(
                        "[CoreMLSentenceEmbeddingProvider] Failed to load tokenizer: \(error)", category: .embedding)
                }
            }
        } else {
            Log.warning(
                "[CoreMLSentenceEmbeddingProvider] embedding_tokenizer not found in Bundle", category: .embedding)
        }
    }

    var isAvailable: Bool {
        #if canImport(CoreML)
            // "Can this provider work", not "has it loaded yet".
            //
            // This read `model != nil`, which was equivalent while the model loaded in `init`.
            // With the load deferred it would report unavailable until something first embedded,
            // and callers route on this — `EmbeddingService.forProvider(allowFallback:)` would
            // silently fall back to a different provider on a cold app, which is the failure mode
            // that produces a library embedded by two different models.
            //
            // Resource presence is the honest test and costs a bundle lookup, not 43 MiB.
            // `model` is not read here: since 2026-11-04 it is written off the main thread under `modelLock`, and
            // taking that lock could wait out a 43 MiB load. A loaded model implies its resource is present.
            let available =
                OpenIntelligenceResourceBundle.url(forResource: "EmbeddingModel", withExtension: "mlmodelc") != nil
                || OpenIntelligenceResourceBundle.url(forResource: "EmbeddingModel", withExtension: "mlpackage") != nil
            if !available {
                Log.warning(
                    "[CoreMLSentenceEmbeddingProvider] Provider unavailable: EmbeddingModel not present in bundle",
                    category: .embedding)
            }

            return available
        #else
            Log.warning(
                "[CoreMLSentenceEmbeddingProvider] Provider unavailable: CoreML not imported", category: .embedding)
            return false
        #endif
    }

    // MARK: - Token Counting (for chunk size validation)

    /// Count ACTUAL tokens that will be used during embedding
    /// This is critical for chunk size validation - NLTokenizer "word count" doesn't match BPE/WordPiece tokens
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    func countTokens(_ text: String) -> Int {
        guard let tokenizer = tokenizer else {
            return text.count / 3 + 2
        }
        do {
            let ids = try tokenizer.encode(text: text, addSpecialTokens: true)
            return ids.count
        } catch {
            return text.count / 3 + 2
        }
    }

    /// Maximum safe text length in tokens (accounting for CLS/SEP)
    var maxSafeTokens: Int { maxSequenceLength }

    // MARK: - Embedding

    @concurrent func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }

        #if canImport(CoreML)
            // Wait up to 1 second for tokenizer to finish loading if it's nil (rare initialization race)
            var count = 0
            while tokenizer == nil && count < 20 {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                count += 1
            }

            let models = loadedModels()
            guard !models.isEmpty, let tokenizer = tokenizer else {
                throw EmbeddingError.modelUnavailable
            }

            let ids = tokenIds(text: text, tokenizer: tokenizer)
            // The shortest function that holds the passage; a longer one would only add padding to compute.
            let (length, model) = models.first(where: { $0.length >= ids.count }) ?? models[models.count - 1]
            let inputIds = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            let used = min(ids.count, length)
            inputIds.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                for i in 0..<length { ptr[i] = Int32(i < used ? ids[i] : padId) }
            }
            mask.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                for i in 0..<length { ptr[i] = i < used ? 1 : 0 }
            }

            let inputs = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIds),
                "attention_mask": MLFeatureValue(multiArray: mask),
            ])
            let output = try await prediction(from: inputs, length: length, model: model)
            guard let vector = output.featureValue(for: "embedding")?.multiArrayValue, vector.count == dimension else {
                throw EmbeddingError.outputParsingFailed
            }

            // The graph returns the CLS vector already L2-normalised; normalise again in Float32 so float16
            // rounding never leaves it off unit length.
            var values = [Float](repeating: 0, count: dimension)
            if vector.dataType == .float32 {
                vector.withUnsafeBufferPointer(ofType: Float.self) { ptr in
                    for i in 0..<dimension { values[i] = ptr[i] }
                }
            } else {
                for i in 0..<dimension { values[i] = vector[i].floatValue }
            }
            var sqSum: Float = 0
            vDSP_svesq(values, 1, &sqSum, vDSP_Length(dimension))
            var norm = max(sqrt(sqSum), 1e-9)
            var normalized = [Float](repeating: 0, count: dimension)
            vDSP_vsdiv(values, 1, &norm, &normalized, 1, vDSP_Length(dimension))
            return normalized
        #else
            throw EmbeddingError.modelUnavailable
        #endif
    }

    @concurrent func embedBatch(texts: [String]) async throws -> [[Float]] {
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

        #if canImport(CoreML)
            // Load (or switch compute units) once, before fanning out. `loadedModels()` holds `modelLock` across a
            // synchronous load of up to about 2.4 s; if every task of the group reached it first, up to
            // `maxConcurrency` threads of the shared concurrency pool would sit blocked on the lock for that time.
            guard !loadedModels().isEmpty else { throw EmbeddingError.modelUnavailable }
        #endif

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

    /// The passage's token ids, special tokens included, at most `maxSequenceLength` (the last kept token is then the
    /// closing [SEP], as the model was trained on).
    private func tokenIds(text: String, tokenizer: Tokenizer) -> [Int] {
        var ids = (try? tokenizer.encode(text: text, addSpecialTokens: true)) ?? [clsId, sepId]
        // CRITICAL: Truncation should NEVER happen with proper chunking
        if ids.count > maxSequenceLength {
            let originalCount = ids.count
            let lostTokens = originalCount - maxSequenceLength
            let lossPercent = Int(Double(lostTokens) / Double(originalCount) * 100)
            ids = Array(ids.prefix(maxSequenceLength - 1)) + [sepId]

            // Log as ERROR because this indicates a bug in the chunking pipeline
            // Every word should be accounted for - truncation = data loss
            Log.error(
                "[CoreMLSentenceEmbedding] ❌ TRUNCATION: \(originalCount)→\(maxSequenceLength) tokens "
                    + "(losing \(lostTokens) tokens = \(lossPercent)% of content!). "
                    + "BUG: Chunk escaped size limits. Text preview: \"\(text.prefix(100))...\"",
                category: .embedding
            )
        }
        return ids
    }
}

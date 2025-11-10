import Foundation

#if canImport(LocalLLMClient) && canImport(LocalLLMClientLlama)
    import LocalLLMClient
    import LocalLLMClientCore
    import LocalLLMClientLlama

    /// iOS in-process GGUF backend
    /// Loads models from ModelRegistry by UUID, enabling proper cartridge-style model management.
    /// The actual inference runtime (llama.cpp XCFramework) will be added in a future phase.
    final class LlamaCPPiOSLLMService: LLMService {

        // MARK: - Persistence Keys

        static let selectedModelIdKey = "selectedGGUFModelId"  // UUID string of selected model from registry

        // MARK: - Properties

    private static let computePreferenceKey = "ggufLocalComputePreference"

    private let modelId: UUID
    private let installedModel: InstalledModel
    private let computePreference: LocalComputePreference
    private let runtime = GGUFClientRuntime()
        var toolHandler: RAGToolHandler?

        var isAvailable: Bool {
            guard let url = installedModel.localURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }

        var modelName: String {
            "GGUF • \(installedModel.name)"
        }

        // MARK: - Init

        init(modelId: UUID, installedModel: InstalledModel, computePreference: LocalComputePreference) {
            self.modelId = modelId
            self.installedModel = installedModel
            self.computePreference = computePreference
            let shortId = String(modelId.uuidString.prefix(8))
            TelemetryCenter.emit(
                .system,
                title: "GGUF model configured",
                metadata: ["name": installedModel.name, "id": shortId]
            )
        }

        // MARK: - Factory

        /// Load a configured GGUF model from UserDefaults + ModelRegistry if available
        @MainActor
        static func fromRegistry() -> LlamaCPPiOSLLMService? {
            let defaults = UserDefaults.standard
            guard let idString = defaults.string(forKey: selectedModelIdKey),
                let id = UUID(uuidString: idString)
            else {
                return nil
            }

            let registry = ModelRegistry.shared
            guard let model = registry.model(id: id),
                model.backend == .gguf
            else {
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "GGUF registry lookup failed",
                    metadata: ["id": String(id.uuidString.prefix(8))]
                )
                return nil
            }

            return LlamaCPPiOSLLMService(
                modelId: id,
                installedModel: model,
                computePreference: currentPreference(from: defaults)
            )
        }

        /// Persist the selected model ID to UserDefaults
        static func saveSelection(modelId: UUID) {
            let defaults = UserDefaults.standard
            defaults.set(modelId.uuidString, forKey: selectedModelIdKey)
            TelemetryCenter.emit(
                .system,
                title: "GGUF model selected",
                metadata: ["id": String(modelId.uuidString.prefix(8))]
            )
        }

        /// Clear the persisted GGUF selection when the cartridge disappears.
        static func clearSelection() {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: selectedModelIdKey)
            TelemetryCenter.emit(
                .system,
                title: "GGUF model selection cleared",
                metadata: [:]
            )
        }

        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            let modelURL = try resolveModelURL()
            let parameter = makeParameter(from: config)
            let messages = makeMessages(prompt: prompt, context: context)
            let start = Date()
            TelemetryCenter.emit(
                .generation,
                title: "GGUF generation started",
                metadata: telemetryMetadata(for: config, url: modelURL)
            )

            let result = try await runtime.generate(
                modelURL: modelURL,
                parameter: parameter,
                messages: messages
            )

            TelemetryCenter.emit(
                .generation,
                title: "GGUF generation finished",
                metadata: [
                    "model": installedModel.name,
                    "duration": String(format: "%.2f", result.totalTime),
                    "tokens": "\(result.tokensGenerated)",
                ],
                duration: Date().timeIntervalSince(start)
            )

            return LLMResponse(
                text: result.text,
                tokensGenerated: result.tokensGenerated,
                timeToFirstToken: result.timeToFirstToken,
                totalTime: result.totalTime,
                modelName: modelName,
                toolCallsMade: 0
            )
        }

        private func resolveModelURL() throws -> URL {
            guard let url = installedModel.localURL,
                FileManager.default.fileExists(atPath: url.path)
            else {
                TelemetryCenter.emit(
                    .error,
                    severity: .error,
                    title: "GGUF model missing",
                    metadata: ["name": installedModel.name]
                )
                throw LLMError.modelUnavailable
            }
            return url
        }

        private func makeParameter(from config: InferenceConfig) -> LlamaClient.Parameter {
            let contextTokens = installedModel.contextWindow ?? max(config.maxTokens * 2, 2048)
            var parameter = LlamaClient.Parameter(
                context: contextTokens,
                seed: nil,
                numberOfThreads: ProcessInfo.processInfo.activeProcessorCount,
                batch: min(contextTokens, 512),
                temperature: config.temperature,
                topK: config.topK,
                topP: config.topP,
                typicalP: 1,
                penaltyLastN: min(contextTokens, max(64, config.maxTokens)),
                penaltyRepeat: config.repetitionPenalty,
                options: .init(
                    responseFormat: nil,
                    extraEOSTokens: Set(config.stopSequences),
                    verbose: false,
                    disableAutoPause: false
                )
            )
            switch computePreference {
            case .automatic:
                parameter.numberOfThreads = ProcessInfo.processInfo.activeProcessorCount
                parameter.options.gpuLayerOverride = nil
            case .gpuPreferred:
                parameter.numberOfThreads = ProcessInfo.processInfo.activeProcessorCount
                parameter.options.gpuLayerOverride = nil
            case .cpuOnly:
                parameter.numberOfThreads = ProcessInfo.processInfo.processorCount
                parameter.options.gpuLayerOverride = 0
                parameter.batch = min(parameter.batch, 256)
            }
            return parameter
        }

        private func makeMessages(prompt: String, context: String?) -> [LLMInput.Message] {
            var messages: [LLMInput.Message] = [
                .system(
                    "You are a helpful assistant. If context is provided, ground your answer in it and cite sources when available."
                )
            ]
            if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append(
                    .user(
                        """
                        Context:
                        \(context)

                        Question: \(prompt)
                        """))
            } else {
                messages.append(.user(prompt))
            }
            return messages
        }

        private func telemetryMetadata(for config: InferenceConfig, url: URL) -> [String: String] {
            let threadCount: Int
            switch computePreference {
            case .cpuOnly:
                threadCount = ProcessInfo.processInfo.processorCount
            default:
                threadCount = ProcessInfo.processInfo.activeProcessorCount
            }
            return [
                "model": installedModel.name,
                "file": url.lastPathComponent,
                "maxTokens": "\(config.maxTokens)",
                "temperature": String(format: "%.2f", config.temperature),
                "topK": "\(config.topK)",
                "topP": String(format: "%.2f", config.topP),
                "threads": "\(threadCount)",
                "stop": config.stopSequences.joined(separator: ","),
                "computePref": computePreference.rawValue,
            ]
        }
    }

    private extension LlamaCPPiOSLLMService {
        static func currentPreference(from defaults: UserDefaults) -> LocalComputePreference {
            LocalComputePreference.load(
                from: defaults, key: computePreferenceKey, fallback: .automatic)
        }
    }

    // MARK: - Runtime Coordinator

    /// Serializes llama.cpp usage and caches a parameter-matched client to avoid reloading GGUF weights on each call.
    private actor GGUFClientRuntime {
        private var cached: CachedClient?

        func generate(
            modelURL: URL,
            parameter: LlamaClient.Parameter,
            messages: [LLMInput.Message]
        ) async throws -> GenerationResult {
            let client = try await client(for: modelURL, parameter: parameter)
            let input = LLMInput.chat(messages)
            let start = Date()
            var aggregated = ""
            var firstToken: TimeInterval?

            let stream = try client.textStream(from: input)
            for try await chunk in stream {
                if firstToken == nil {
                    firstToken = Date().timeIntervalSince(start)
                }
                aggregated += chunk
                let currentText = aggregated
                await MainActor.run {
                    LLMStreamingContext.emit(text: currentText, isFinal: false)
                }
            }

            let total = Date().timeIntervalSince(start)
            let finalText = aggregated
            await MainActor.run {
                LLMStreamingContext.emit(text: finalText, isFinal: true)
            }
            return GenerationResult(
                text: aggregated,
                tokensGenerated: tokenEstimate(for: aggregated),
                timeToFirstToken: firstToken,
                totalTime: total
            )
        }

        private func client(for url: URL, parameter: LlamaClient.Parameter) async throws
            -> LlamaClient
        {
            let signature = ParameterSignature(parameter: parameter)
            if let cached, cached.url == url, cached.signature == signature {
                return cached.client
            }

            do {
                let client = try await LocalLLMClient.llama(url: url, parameter: parameter)
                cached = CachedClient(url: url, signature: signature, client: client)
                return client
            } catch let runtimeError as LocalLLMClientCore.LLMError {
                if case .invalidParameter(let reason) = runtimeError,
                    reason.localizedCaseInsensitiveContains("template")
                        || reason.localizedCaseInsensitiveContains("jinja")
                {
                    await MainActor.run {
                        Log.warning(
                            "⚠️  GGUF template invalid — retrying with ChatML processor",
                            category: .llm
                        )
                    }

                    let chatMLProcessor = MessageProcessorFactory.chatMLProcessor()
                    let client = try await LocalLLMClient.llama(
                        url: url,
                        parameter: parameter,
                        messageProcessor: chatMLProcessor
                    )
                    cached = CachedClient(url: url, signature: signature, client: client)
                    return client
                }
                throw runtimeError
            }
        }

        private func tokenEstimate(for text: String) -> Int {
            text.split { $0.isWhitespace || $0.isNewline }.count
        }

        private struct CachedClient {
            let url: URL
            let signature: ParameterSignature
            let client: LlamaClient
        }

        private struct ParameterSignature: Equatable {
            let context: Int
            let batch: Int
            let temperature: Float
            let topK: Int
            let topP: Float
            let penaltyRepeat: Float
            let penaltyLastN: Int
            let extraStops: Set<String>
            let disableAutoPause: Bool

            init(parameter: LlamaClient.Parameter) {
                context = parameter.context
                batch = parameter.batch
                temperature = parameter.temperature
                topK = parameter.topK
                topP = parameter.topP
                penaltyRepeat = parameter.penaltyRepeat
                penaltyLastN = parameter.penaltyLastN
                extraStops = parameter.options.extraEOSTokens
                disableAutoPause = parameter.options.disableAutoPause
            }
        }
    }

    private struct GenerationResult {
        let text: String
        let tokensGenerated: Int
        let timeToFirstToken: TimeInterval?
        let totalTime: TimeInterval
    }

    extension LlamaCPPiOSLLMService {
        static var runtimeAvailable: Bool { true }
    }

#else

    /// Placeholder implementation used when the LocalLLMClient runtime is unavailable.
    @MainActor
    final class LlamaCPPiOSLLMService: LLMService {
        static let selectedModelIdKey = "selectedGGUFModelId"

        var toolHandler: RAGToolHandler?

        var isAvailable: Bool { false }
        var modelName: String { "GGUF (Unavailable)" }

        init() {}

        func generate(prompt: String, context: String?, config: InferenceConfig) async throws
            -> LLMResponse
        {
            throw LLMError.modelUnavailable
        }

        static func fromRegistry() -> LlamaCPPiOSLLMService? { nil }

        static func saveSelection(modelId: UUID) {
            UserDefaults.standard.set(modelId.uuidString, forKey: selectedModelIdKey)
        }

        static var runtimeAvailable: Bool { false }
    }

#endif

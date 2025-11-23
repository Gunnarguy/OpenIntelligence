//
//  MLXLLMService.swift
//  OpenIntelligence
//
//  Experimental MLX cartridge inference path.
//  Mirrors the legacy MLXLocalLLMService transport but is scoped to the
//  `.mlx` ModelBackend so cartridges can opt into a dedicated pipeline.
//

import Foundation

#if os(macOS)

/// Dedicated transport for MLX-backed cartridges hosted on the local tensor server.
/// Mirrors the OpenAI-compatible wire format so we can reuse the same prompting surface
/// while keeping end-to-end routing on-device.
final class MLXLLMService: LLMService {
    struct Config {
        /// Base URL of the local server, e.g. http://127.0.0.1:17860
        let baseURL: URL
        /// Model identifier on the server (if required by the server)
        let model: String
        /// Endpoint path (defaults to OpenAI-compatible)
        let chatCompletionsPath: String
        /// Optional health endpoint (HEAD/GET)
        let healthPath: String
        /// Optional metadata endpoint describing the model
        let metadataPath: String
        /// Optional API key / bearer token for remote servers
        let apiKey: String?
        /// Additional headers to forward with every request
        let additionalHeaders: [String: String]
        /// Hosts that are considered safe targets (loopback by default)
        let allowedHosts: Set<String>
        /// Whether HTTPS is required for non-loopback hosts
        let requireTLSForRemoteHosts: Bool
        /// Streaming preference advertised by the server
        let streamingMode: StreamingMode
        /// Whether tool calls should be parsed and executed locally
        let supportsToolCalls: Bool
        /// Maximum number of concurrent completions to allow
        let maxConcurrentRequests: Int
        /// Retry/backoff configuration for transient network issues
        let retryPolicy: RetryPolicy

        init(baseURL: URL = URL(string: "http://127.0.0.1:17860")!,
             model: String = "mlx-cartridge",
             chatCompletionsPath: String = "/v1/chat/completions",
             healthPath: String = "/health",
             metadataPath: String = "/v1/models/:model",
             apiKey: String? = nil,
             additionalHeaders: [String: String] = [:],
             allowedHosts: Set<String> = ["127.0.0.1", "localhost"],
             requireTLSForRemoteHosts: Bool = true,
             streamingMode: StreamingMode = .disabled,
             supportsToolCalls: Bool = false,
             maxConcurrentRequests: Int = 2,
             retryPolicy: RetryPolicy = .defaultPolicy) {
            self.baseURL = baseURL
            self.model = model
            self.chatCompletionsPath = chatCompletionsPath
            self.healthPath = healthPath
            self.metadataPath = metadataPath
            self.apiKey = apiKey
            self.additionalHeaders = additionalHeaders
            self.allowedHosts = allowedHosts
            self.requireTLSForRemoteHosts = requireTLSForRemoteHosts
            self.streamingMode = streamingMode
            self.supportsToolCalls = supportsToolCalls
            self.maxConcurrentRequests = maxConcurrentRequests
            self.retryPolicy = retryPolicy
        }
    }

    enum StreamingMode {
        case disabled
        case serverSentEvents
    }

    struct RetryPolicy {
        let maxRetries: Int
        let initialBackoff: TimeInterval

        static let defaultPolicy = RetryPolicy(maxRetries: 2, initialBackoff: 0.35)

        func backoffDelay(for attempt: Int) -> TimeInterval {
            guard attempt > 0 else { return 0 }
            return initialBackoff * pow(2.0, Double(attempt - 1))
        }
    }

    actor RequestGate {
        private let maxConcurrent: Int
        private var current = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(maxConcurrent: Int) {
            self.maxConcurrent = max(1, maxConcurrent)
        }

        func withPermit<T>(operation: @Sendable () async throws -> T) async throws -> T {
            await acquire()
            do {
                let result = try await operation()
                await release()
                return result
            } catch {
                await release()
                throw error
            }
        }

        private func acquire() async {
            if current < maxConcurrent {
                current += 1
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        private func release() {
            current = max(0, current - 1)
            if let waiter = waiters.first {
                waiters.removeFirst()
                current += 1
                waiter.resume()
            }
        }
    }

    actor ServerState {
        private(set) var health: HealthStatus = .unknown
        private(set) var capabilities: CapabilitySnapshot = .empty

        func updateHealth(_ status: HealthStatus) {
            health = status
        }

        func updateCapabilities(_ snapshot: CapabilitySnapshot) {
            capabilities = snapshot
        }

        func snapshot() -> CapabilitySnapshot {
            capabilities
        }

        func healthStatus() -> HealthStatus {
            health
        }
    }

    struct CapabilitySnapshot: Sendable {
        let modelId: String
        let contextWindow: Int?
        let maxOutputTokens: Int?
        let metadata: [String: String]
        let fetchedAt: Date

        static let empty = CapabilitySnapshot(
            modelId: "unknown",
            contextWindow: nil,
            maxOutputTokens: nil,
            metadata: [:],
            fetchedAt: Date.distantPast
        )
    }

    enum HealthStatus: Sendable {
        case unknown
        case healthy(Date)
        case degraded(Date, reason: String)
        case unreachable(Date, reason: String)
    }

    struct ServerStatus: Sendable {
        let health: HealthStatus
        let capabilities: CapabilitySnapshot

        static let unknown = ServerStatus(health: .unknown, capabilities: .empty)
    }

    struct ToolCallPayload: Decodable {
        struct FunctionCall: Decodable {
            let name: String
            let arguments: String
        }
        let id: String
        let type: String
        let function: FunctionCall
    }

    struct ToolCallDeltaPayload: Decodable {
        struct FunctionCall: Decodable {
            let name: String?
            let arguments: String?
        }
        let id: String?
        let type: String?
        let function: FunctionCall?
    }

    private let config: Config
    private let backend: ModelBackend = .mlx
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let gate: RequestGate
    private let retryPolicy: RetryPolicy
    private let state = ServerState()
    private let hostPermitted: Bool
    @MainActor private var statusObserver: ((ServerStatus) -> Void)?

    var toolHandler: RAGToolHandler?  // Tool routing to be wired once MLX cartridges emit calls

    init(config: Config = Config(), urlSession: URLSession = .shared) {
        self.config = config
        self.session = urlSession
        self.gate = RequestGate(maxConcurrent: config.maxConcurrentRequests)
        self.retryPolicy = config.retryPolicy
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        self.hostPermitted = MLXLLMService.isHostPermitted(config: config)
        self.validateBaseURL()

        let descriptor = "\(config.baseURL.absoluteString) [model=\(config.model)]"
        Log.info(
            "🧪 MLXLLMService (\(backend.displayName)) ready → \(descriptor)",
            category: .llm
        )
        Log.debug(
            "Route ModelBackend.mlx cartridges here for native MLX tensor bundles.",
            category: .llm
        )

        if hostPermitted {
            Task {
                await refreshServerMetadata()
                await refreshHealth()
            }
        }
    }

    @MainActor
    func setStatusObserver(_ observer: ((ServerStatus) -> Void)?) {
        statusObserver = observer
    }

    func currentServerStatus() async -> ServerStatus {
        let snapshot = await state.snapshot()
        let health = await state.healthStatus()
        return ServerStatus(health: health, capabilities: snapshot)
    }

    private func notifyStatusObserver() async {
        let status = await currentServerStatus()
        await MainActor.run {
            self.statusObserver?(status)
        }
    }

    private static func isHostPermitted(config: Config) -> Bool {
        guard let host = config.baseURL.host?.lowercased() else { return false }
        if !config.allowedHosts.isEmpty && !config.allowedHosts.contains(host) {
            return false
        }
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if !loopback && config.requireTLSForRemoteHosts
            && config.baseURL.scheme?.lowercased() != "https"
        {
            return false
        }
        return true
    }

    private func validateBaseURL() {
        guard let host = config.baseURL.host?.lowercased() else {
            Log.error("MLX baseURL missing host", category: .llm)
            return
        }

        if !hostPermitted {
            Log.warning(
                "MLX endpoint host \(host) is not in the allow list; requests will be blocked.",
                category: .llm
            )
        }

        if !isLoopback(host: host)
            && config.requireTLSForRemoteHosts
            && config.baseURL.scheme?.lowercased() != "https"
        {
            Log.warning(
                "Remote MLX endpoints must use HTTPS when requireTLSForRemoteHosts is true.",
                category: .llm
            )
        }
    }

    private func isLoopback(host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    var isAvailable: Bool {
        hostPermitted
    }

    var modelName: String {
        "MLX Cartridge (\(config.model))"
    }

    /// Optional health check to verify server responsiveness
    func ping(timeout: TimeInterval = 2.0) async -> Bool {
        guard hostPermitted else { return false }
        var req = URLRequest(url: endpointURL(for: config.healthPath))
        req.timeoutInterval = timeout
        applyHeaders(to: &req)
        do {
            let (_, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status < 500 && status > 0
        } catch {
            Log.warning("MLX ping failed: \(error.localizedDescription)", category: .llm)
            return false
        }
    }

    func generate(prompt: String, context: String?, config userConfig: InferenceConfig) async throws -> LLMResponse {
        guard isAvailable else {
            throw LLMError.modelUnavailable
        }

        let requestId = UUID().uuidString.prefix(8)
        let start = Date()
        TelemetryCenter.emit(
            .generation,
            title: "MLX cartridge generation started",
            metadata: [
                "request": String(requestId),
                "model": self.config.model,
                "temp": String(format: "%.2f", userConfig.temperature),
                "maxTokens": "\(userConfig.maxTokens)"
            ]
        )

        let request = try buildRequest(prompt: prompt, context: context, inferenceConfig: userConfig)

        defer {
            LLMStreamingContext.emit(text: "", isFinal: true)
        }

        do {
            let response = try await gate.withPermit {
                try await executeWithRetry { try await performCompletionRequest(request: request) }
            }

            let total = Date().timeIntervalSince(start)

            TelemetryCenter.emit(
                .generation,
                title: "MLX cartridge generation complete",
                metadata: [
                    "request": String(requestId),
                    "model": self.config.model,
                    "tokens": "\(response.tokens)",
                    "duration": String(format: "%.2f", total)
                ],
                duration: total
            )

            return LLMResponse(
                text: response.text,
                tokensGenerated: response.tokens,
                timeToFirstToken: response.timeToFirstToken,
                totalTime: total,
                modelName: self.modelName,
                toolCallsMade: response.toolCallsMade
            )
        } catch {
            TelemetryCenter.emit(
                .generation,
                severity: .error,
                title: "MLX cartridge generation failed",
                metadata: [
                    "request": String(requestId),
                    "error": error.localizedDescription
                ]
            )
            await refreshHealth()
            throw error
        }
    }

    private func buildRequest(prompt: String, context: String?, inferenceConfig userConfig: InferenceConfig) throws -> URLRequest {
        let messages = composeMessages(prompt: prompt, context: context, systemPrompt: userConfig.systemPrompt)
        let payload = ChatCompletionRequest(
            model: self.config.model,
            messages: messages,
            maxTokens: userConfig.maxTokens,
            temperature: Double(userConfig.temperature),
            topP: Double(userConfig.topP),
            topK: userConfig.topK,
            frequencyPenalty: Double(userConfig.frequencyPenalty),
            presencePenalty: Double(userConfig.presencePenalty),
            repetitionPenalty: Double(userConfig.repetitionPenalty),
            stop: userConfig.stopSequences.isEmpty ? nil : userConfig.stopSequences
        )

        var request = URLRequest(
            url: endpointURL(for: self.config.chatCompletionsPath)
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try encoder.encode(payload)
        applyHeaders(to: &request)

        Log.info(
            "🌐 [MLX] POST \(request.url?.absoluteString ?? config.baseURL.absoluteString) — model=\(self.config.model)",
            category: .llm
        )
        Log.debug(
            "Params: maxTokens=\(userConfig.maxTokens) temp=\(userConfig.temperature) topP=\(userConfig.topP)",
            category: .llm
        )
        return request
    }

    private func composeMessages(prompt: String, context: String?, systemPrompt: String?) -> [ChatMessage] {
        let defaultSystemPrompt = """
        You are a helpful assistant. When provided with document context, ground your answer in that context and clearly indicate citations if applicable. If context is irrelevant, answer normally.
        """

        var messages = [ChatMessage(role: "system", content: systemPrompt ?? defaultSystemPrompt)]

        if let ctx = context, !ctx.isEmpty {
            let contextualUserMessage = """
            Context:
            \(ctx)

            Question: \(prompt)
            """
            messages.append(ChatMessage(role: "user", content: contextualUserMessage))
        } else {
            messages.append(ChatMessage(role: "user", content: prompt))
        }

        return messages
    }

    private func performCompletionRequest(request: URLRequest) async throws -> CompletionResult {
        switch config.streamingMode {
        case .serverSentEvents:
            return try await streamCompletion(request: request)
        case .disabled:
            return try await blockingCompletion(request: request)
        }
    }

    private func blockingCompletion(request: URLRequest) async throws -> CompletionResult {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid HTTP response")
        }
        guard http.statusCode == 200 else {
            throw classifyHTTPError(statusCode: http.statusCode, data: data)
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        let textOut = completion.primaryText ?? ""
        stream(textOut)

        let tokens = completion.completionTokens ?? textOut.approximateWordCount
        let (toolAppendix, toolCount) = try await handleToolCalls(completion.toolCalls)
        let finalText: String
        if toolAppendix.isEmpty {
            finalText = textOut
        } else {
            let toolText = "\n" + toolAppendix
            LLMStreamingContext.emit(text: toolText, isFinal: false)
            finalText = textOut + toolText
        }

        return CompletionResult(
            text: finalText,
            tokens: tokens,
            timeToFirstToken: nil,
            toolCallsMade: toolCount
        )
    }

    private func streamCompletion(request: URLRequest) async throws -> CompletionResult {
        let start = Date()
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid HTTP response")
        }
        guard http.statusCode == 200 else {
            var buffer = Data()
            for try await chunk in bytes {
                buffer.append(chunk)
            }
            throw classifyHTTPError(statusCode: http.statusCode, data: buffer)
        }

        var aggregated = ""
        var firstTokenTime: TimeInterval?
        var emittedTokens = 0

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard !payload.isEmpty, let data = payload.data(using: .utf8) else { continue }
            let chunk = try decoder.decode(ChatCompletionChunk.self, from: data)
            if let content = chunk.choices.first?.delta?.content, !content.isEmpty {
                aggregated.append(content)
                LLMStreamingContext.emit(text: content, isFinal: false)
                emittedTokens += content.approximateWordCount
                if firstTokenTime == nil {
                    firstTokenTime = Date().timeIntervalSince(start)
                }
            }

            if let toolCalls = chunk.choices.first?.delta?.toolCalls, !toolCalls.isEmpty {
                Log.warning(
                    "Streaming tool calls are not yet supported on MLX; ignoring chunk.",
                    category: .llm
                )
            }
        }

        return CompletionResult(
            text: aggregated,
            tokens: emittedTokens > 0 ? emittedTokens : aggregated.approximateWordCount,
            timeToFirstToken: firstTokenTime,
            toolCallsMade: 0
        )
    }

    private func handleToolCalls(_ toolCalls: [ToolCallPayload]) async throws -> (String, Int) {
        guard config.supportsToolCalls, !toolCalls.isEmpty else {
            return ("", 0)
        }
        guard let handler = toolHandler else {
            throw LLMError.generationFailed("Tool call requested but no handler is configured.")
        }

        var outputs: [String] = []
        for call in toolCalls {
            let result = try await executeToolCall(call, handler: handler)
            outputs.append("Tool \(call.function.name):\n\(result)")
        }
        let appendix = outputs.joined(separator: "\n\n")
        return (appendix, toolCalls.count)
    }

    private func executeToolCall(_ call: ToolCallPayload, handler: RAGToolHandler) async throws -> String {
        struct SearchArgs: Decodable { let query: String }
        struct SummaryArgs: Decodable { let documentName: String }

        let argumentsData = call.function.arguments.data(using: .utf8) ?? Data()

        switch call.function.name {
        case "search_documents":
            let args = try decoder.decode(SearchArgs.self, from: argumentsData)
            return try await handler.searchDocuments(query: args.query)
        case "list_documents":
            return try await handler.listDocuments()
        case "get_document_summary":
            let args = try decoder.decode(SummaryArgs.self, from: argumentsData)
            return try await handler.getDocumentSummary(documentName: args.documentName)
        default:
            throw LLMError.generationFailed("Unsupported tool call: \(call.function.name)")
        }
    }

    private func executeWithRetry<T>(operation: @escaping @Sendable () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0...retryPolicy.maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard isTransient(error), attempt < retryPolicy.maxRetries else {
                    throw error
                }
                let delay = retryPolicy.backoffDelay(for: attempt + 1)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError ?? LLMError.generationFailed("Unknown MLX failure")
    }

    private func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if case LLMError.generationFailed(let message) = error {
            return message.contains("HTTP 429") || message.contains("timeout")
        }
        return false
    }

    private func stream(_ text: String) {
        guard !text.isEmpty else { return }
        let chunkSize = 512
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index..<end])
            LLMStreamingContext.emit(text: chunk, isFinal: false)
            index = end
        }
    }

    private func classifyHTTPError(statusCode: Int, data: Data?) -> Error {
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
        if statusCode == 401 || statusCode == 403 {
            return LLMError.generationFailed("HTTP \(statusCode): Authentication failed – \(body)")
        } else if statusCode == 429 {
            return LLMError.generationFailed("HTTP 429: Rate limited – \(body)")
        } else if (400..<500).contains(statusCode) {
            return LLMError.generationFailed("HTTP \(statusCode): Client error – \(body)")
        } else {
            return LLMError.generationFailed("HTTP \(statusCode): Server error – \(body)")
        }
    }

    private func applyHeaders(to request: inout URLRequest) {
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in config.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func endpointURL(for path: String, replacements: [String: String] = [:]) -> URL {
        var resolved = path
        for (key, value) in replacements {
            resolved = resolved.replacingOccurrences(of: ":\(key)", with: value)
        }
        if let absolute = URL(string: resolved), absolute.scheme != nil {
            return absolute
        }
        var trimmed = resolved
        if trimmed.hasPrefix("/") {
            trimmed.removeFirst()
        }
        return config.baseURL.appendingPathComponent(trimmed)
    }

    @discardableResult
    private func refreshHealth() async -> HealthStatus {
        var request = URLRequest(url: endpointURL(for: config.healthPath))
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        applyHeaders(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.generationFailed("Invalid health response")
            }
            let status: HealthStatus
            if http.statusCode == 200 {
                status = .healthy(Date())
            } else {
                status = .degraded(Date(), reason: "HTTP \(http.statusCode)")
            }
            await state.updateHealth(status)
            await notifyStatusObserver()
            TelemetryCenter.emit(
                .system,
                title: "MLX health updated",
                metadata: ["status": "\(http.statusCode)"]
            )
            return status
        } catch {
            let status = HealthStatus.unreachable(Date(), reason: error.localizedDescription)
            await state.updateHealth(status)
            await notifyStatusObserver()
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "MLX health failed",
                metadata: ["error": error.localizedDescription]
            )
            return status
        }
    }

    private func refreshServerMetadata() async {
        var request = URLRequest(
            url: endpointURL(for: config.metadataPath, replacements: ["model": config.model])
        )
        request.timeoutInterval = 4
        applyHeaders(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LLMError.generationFailed("Metadata fetch failed")
            }
            let metadata = try decoder.decode(ModelMetadataResponse.self, from: data)
            let snapshot = CapabilitySnapshot(
                modelId: metadata.id ?? config.model,
                contextWindow: metadata.contextWindow,
                maxOutputTokens: metadata.maxOutputTokens,
                metadata: metadata.metadata ?? [:],
                fetchedAt: Date()
            )
            await state.updateCapabilities(snapshot)
            await notifyStatusObserver()
            TelemetryCenter.emit(
                .system,
                title: "MLX metadata synced",
                metadata: [
                    "model": snapshot.modelId,
                    "contextWindow": snapshot.contextWindow.map(String.init) ?? "n/a"
                ]
            )
        } catch {
            Log.debug("MLX metadata refresh skipped: \(error.localizedDescription)", category: .llm)
        }
    }

    private struct CompletionResult {
        let text: String
        let tokens: Int
        let timeToFirstToken: TimeInterval?
        let toolCallsMade: Int
    }

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let maxTokens: Int
        let temperature: Double
        let topP: Double
        let topK: Int
        let frequencyPenalty: Double
        let presencePenalty: Double
        let repetitionPenalty: Double
        let stop: [String]?
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let role: String?
                let content: String?
                let toolCalls: [ToolCallPayload]?
            }
            let message: Message?
            let text: String?
            let finishReason: String?
        }

        struct Usage: Decodable {
            let completionTokens: Int?
            let totalTokens: Int?
        }

        let choices: [Choice]
        let usage: Usage?

        var primaryText: String? {
            if let messageContent = choices.first?.message?.content {
                return messageContent
            }
            return choices.first?.text
        }

        var completionTokens: Int? {
            usage?.completionTokens
        }

        var toolCalls: [ToolCallPayload] {
            choices.first?.message?.toolCalls ?? []
        }
    }

    private struct ChatCompletionChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let toolCalls: [ToolCallDeltaPayload]?
            }
            let delta: Delta?
            let index: Int?
            let finishReason: String?
        }
        let choices: [Choice]
        let usage: ChatCompletionResponse.Usage?
    }

    private struct ModelMetadataResponse: Decodable {
        let id: String?
        let contextWindow: Int?
        let maxOutputTokens: Int?
        let metadata: [String: String]?
    }
}

#else

// Stub on non-macOS platforms
final class MLXLLMService: LLMService {
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { false }
    var modelName: String { "MLX Cartridge (macOS only)" }
    init(config: Any? = nil) {}
    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        throw LLMError.modelUnavailable
    }
}

#endif

#if os(macOS)
extension MLXLLMService.Config {
    static func fromDefaults(_ defaults: UserDefaults = .standard) -> MLXLLMService.Config? {
        let baseURLString = defaults.string(forKey: "mlxBaseURL")?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "http://127.0.0.1:17860"
        guard let url = URL(string: baseURLString) else { return nil }
        let modelName = defaults.string(forKey: "mlxModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "local-mlx-model"
        let streamEnabled = defaults.object(forKey: "mlxStream") as? Bool ?? false
        var allowed: Set<String> = ["127.0.0.1", "localhost"]
        if let host = url.host?.lowercased(), !host.isEmpty {
            allowed.insert(host)
        }
        return MLXLLMService.Config(
            baseURL: url,
            model: modelName,
            chatCompletionsPath: "/v1/chat/completions",
            healthPath: "/health",
            metadataPath: "/v1/models/:model",
            apiKey: nil,
            additionalHeaders: [:],
            allowedHosts: allowed,
            requireTLSForRemoteHosts: true,
            streamingMode: streamEnabled ? .serverSentEvents : .disabled,
            supportsToolCalls: true,
            maxConcurrentRequests: 2,
            retryPolicy: .defaultPolicy
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif

private extension String {
    var approximateWordCount: Int {
        split { $0.isWhitespace }.count
    }
}

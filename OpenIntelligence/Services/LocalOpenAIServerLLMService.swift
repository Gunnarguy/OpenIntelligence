//
//  LocalOpenAIServerLLMService.swift
//  OpenIntelligence
//
//  Unified local OpenAI-compatible server client.
//  Supports MLX, llama.cpp, Ollama, or any server exposing /v1/chat/completions.
//  Provides optional SSE streaming and basic health checks.
//
//  Created by Cline on 10/31/25.
//

import Foundation

/// A unified local LLM client for OpenAI-compatible servers running locally
/// Examples:
///  - MLX:       python -m mlx_lm.server --model qwen2.5-7b-instruct --port 17860
///  - llama.cpp: ./server -m ./models/xxx.gguf -c 8192 -ngl 99 -a 127.0.0.1 -p 8080
///  - Ollama:    ollama serve (and ensure OpenAI-compatible endpoint enabled if needed)
final class LocalOpenAIServerLLMService: LLMService {
    struct Config: Sendable {
        /// Base URL to local server, e.g. http://127.0.0.1:17860
        let baseURL: URL
        /// Model identifier sent to the server
        let model: String
        /// Chat completions path (OpenAI-compatible default)
        let chatCompletionsPath: String
        /// If true, attempts SSE streaming where the server supports it
        let stream: Bool
        /// Optional headers (Authorization, etc.), typically none for localhost
        let headers: [String: String]?

        init(
            baseURL: URL = URL(string: "http://127.0.0.1:17860")!,
            model: String = "local-model",
            chatCompletionsPath: String = "/v1/chat/completions",
            stream: Bool = false,
            headers: [String: String]? = nil
        ) {
            self.baseURL = baseURL
            self.model = model
            self.chatCompletionsPath = chatCompletionsPath
            self.stream = stream
            self.headers = headers
        }
    }

    private let config: Config

    // Tool handler not used for local OpenAI-compatible endpoints (no FC spec by default)
    var toolHandler: RAGToolHandler?

    init(config: Config = Config()) {
        self.config = config
        print("🧩 LocalOpenAIServerLLMService → \(config.baseURL.absoluteString) [model=\(config.model), stream=\(config.stream)]")
    }

    var isAvailable: Bool {
        // Optimistic local check; detailed check available via healthCheck()
        guard let host = config.baseURL.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    var modelName: String {
        "Local Server (\(config.model))"
    }

    /// Basic health check: tries GET on /v1/models, falling back to GET base URL.
    func healthCheck(timeout: TimeInterval = 2.5) async -> Bool {
        // Try /v1/models first (common across servers)
        let modelsURL = config.baseURL.appendingPathComponent("/v1/models")
        var req = URLRequest(url: modelsURL)
        req.timeoutInterval = timeout
        addHeaders(into: &req)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                return true
            }
        } catch {
            // Fall through to base URL check
        }

        var baseReq = URLRequest(url: config.baseURL)
        baseReq.timeoutInterval = timeout
        addHeaders(into: &baseReq)
        do {
            let (_, resp) = try await URLSession.shared.data(for: baseReq)
            return (resp as? HTTPURLResponse)?.statusCode ?? 0 < 500
        } catch {
            return false
        }
    }

    // MARK: - Generation

    func generate(prompt: String, context: String?, config userConfig: InferenceConfig) async throws -> LLMResponse {
        guard isAvailable else {
            throw LLMError.modelUnavailable
        }

        let url = config.baseURL.appendingPathComponent(config.chatCompletionsPath)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addHeaders(into: &req)

        // Compose OpenAI-style chat messages
        var messages: [[String: String]] = []
        messages.append([
            "role": "system",
            "content": """
            You are a helpful assistant. When document context is provided, ground your answer in that context and indicate citations if applicable. If context is irrelevant, answer normally.
            """
        ])
        if let ctx = context, !ctx.isEmpty {
            messages.append([
                "role": "user",
                "content": """
                Context:
                \(ctx)

                Question: \(prompt)
                """
            ])
        } else {
            messages.append([
                "role": "user",
                "content": prompt
            ])
        }

        // Build request body
        var body: [String: Any] = [
            "model": self.config.model,
            "messages": messages,
            // Many servers accept OpenAI-style params; those unsupported are ignored gracefully.
            "max_tokens": userConfig.maxTokens,
            "temperature": Double(userConfig.temperature)
        ]
        if !userConfig.stopSequences.isEmpty {
            body["stop"] = userConfig.stopSequences
        }
        // TopP/TopK commonly accepted by local servers (may be ignored)
        body["top_p"] = userConfig.topP
        body["top_k"] = userConfig.topK

        let start = Date()

        if self.config.stream {
            // Attempt SSE streaming
            body["stream"] = true
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            let payload = try JSONSerialization.data(withJSONObject: body)
            req.httpBody = payload
            req.timeoutInterval = 300

            print("🌐 [Local LLM] POST(stream) \(url.absoluteString)")
            print("    model=\(self.config.model) max_tokens=\(userConfig.maxTokens) temp=\(userConfig.temperature)")

            // Use async bytes streaming API
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                // Try to read body for error context (not available from bytes API)
                throw LLMError.generationFailed("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1): stream request failed")
            }

            var latestSnapshot = ""
            var firstTokenTTFT: TimeInterval?
            var tokenCountApprox = 0

            defer { LLMStreamingContext.emit(text: "", isFinal: true) }

            do {
                for try await line in bytes.lines {
                    // SSE may include keep-alive ":" or empty lines
                    if line.isEmpty || line.hasPrefix(":") { continue }

                    if line == "data: [DONE]" || line == "data:[DONE]" {
                        break
                    }

                    let dataPrefix = "data:"
                    guard let range = line.range(of: dataPrefix) else {
                        continue
                    }
                    let rawPayload = line[range.upperBound...].trimmingCharacters(in: .whitespaces)

                    var explicitDelta: String?
                    var snapshotCandidate: String?

                    if let jsonData = rawPayload.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                        if let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first {
                            if let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                explicitDelta = content
                            } else if let message = first["message"] as? [String: Any],
                                      let content = message["content"] as? String {
                                snapshotCandidate = content
                            } else if let text = first["text"] as? String {
                                snapshotCandidate = text
                            }
                        } else if let content = json["content"] as? String {
                            snapshotCandidate = content
                        }
                    } else {
                        explicitDelta = rawPayload
                    }

                    var addition = ""

                    if let delta = explicitDelta {
                        addition = delta
                        latestSnapshot += delta
                    } else if let snapshot = snapshotCandidate {
                        let prefix = latestSnapshot.commonPrefix(with: snapshot)
                        addition = String(snapshot.dropFirst(prefix.count))
                        latestSnapshot = snapshot
                    }

                    guard !addition.isEmpty else { continue }

                    if firstTokenTTFT == nil {
                        let ttft = Date().timeIntervalSince(start)
                        firstTokenTTFT = ttft
                        print("⚡ [Local LLM] First token in \(String(format: "%.2f", ttft))s")
                    }

                    tokenCountApprox += addition.split(separator: " ").count
                    LLMStreamingContext.emit(text: addition, isFinal: false)
                }
            } catch {
                print("⚠️ [Local LLM] Stream parsing error: \(error.localizedDescription)")
            }

            let total = Date().timeIntervalSince(start)
            return LLMResponse(
                text: latestSnapshot,
                tokensGenerated: tokenCountApprox,
                timeToFirstToken: firstTokenTTFT,
                totalTime: total,
                modelName: self.modelName,
                toolCallsMade: 0
            )
        } else {
            // Non-streaming JSON request
            let payload = try JSONSerialization.data(withJSONObject: body)
            req.httpBody = payload
            req.timeoutInterval = 120

            print("🌐 [Local LLM] POST \(url.absoluteString)")
            print("    model=\(self.config.model) max_tokens=\(userConfig.maxTokens) temp=\(userConfig.temperature)")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw LLMError.generationFailed("Invalid response")
            }
            guard http.statusCode == 200 else {
                let errStr = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMError.generationFailed("HTTP \(http.statusCode): \(errStr)")
            }

            // Parse OpenAI-like response
            let any = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = any as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first else {
                throw LLMError.generationFailed("Malformed response")
            }

            var content: String?
            if let message = first["message"] as? [String: Any] {
                content = message["content"] as? String
            }
            if content == nil, let text = first["text"] as? String {
                content = text
            }
            let textOut = content ?? ""

            let total = Date().timeIntervalSince(start)
            let words = textOut.split(separator: " ").count

            if !textOut.isEmpty {
                LLMStreamingContext.emit(text: textOut, isFinal: false)
            }
            LLMStreamingContext.emit(text: "", isFinal: true)

            return LLMResponse(
                text: textOut,
                tokensGenerated: words,
                timeToFirstToken: nil,
                totalTime: total,
                modelName: self.modelName,
                toolCallsMade: 0
            )
        }
    }

    // MARK: - Helpers

    private func addHeaders(into request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = config.headers {
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
    }
}

// MARK: - Thin Presets for Popular Local Backends

#if os(macOS)

/// MLX preset using LocalOpenAIServerLLMService under the hood
final class MLXPresetLLMService: LLMService {
    private let inner: LocalOpenAIServerLLMService
    var toolHandler: RAGToolHandler? {
        get { inner.toolHandler }
        set { inner.toolHandler = newValue }
    }

    init(baseURL: URL = URL(string: "http://127.0.0.1:17860")!,
         model: String = "local-mlx-model",
         stream: Bool = false) {
        self.inner = LocalOpenAIServerLLMService(
            config: .init(baseURL: baseURL, model: model, chatCompletionsPath: "/v1/chat/completions", stream: stream, headers: nil)
        )
        print("🧪 MLX Preset → \(baseURL.absoluteString) [model=\(model), stream=\(stream)]")
    }

    var isAvailable: Bool { inner.isAvailable }
    var modelName: String { "MLX Local (\(inner.modelName))" }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        try await inner.generate(prompt: prompt, context: context, config: config)
    }
}

/// llama.cpp preset using LocalOpenAIServerLLMService
final class LlamaCPPPresetLLMService: LLMService {
    private let inner: LocalOpenAIServerLLMService
    var toolHandler: RAGToolHandler? {
        get { inner.toolHandler }
        set { inner.toolHandler = newValue }
    }

    init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
         model: String = "local-llama-model",
         stream: Bool = true) {
        self.inner = LocalOpenAIServerLLMService(
            config: .init(baseURL: baseURL, model: model, chatCompletionsPath: "/v1/chat/completions", stream: stream, headers: nil)
        )
        print("🧪 llama.cpp Preset → \(baseURL.absoluteString) [model=\(model), stream=\(stream)]")
    }

    var isAvailable: Bool { inner.isAvailable }
    var modelName: String { "llama.cpp (\(inner.modelName))" }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        try await inner.generate(prompt: prompt, context: context, config: config)
    }
}

/// Ollama preset using LocalOpenAIServerLLMService (OpenAI-compatible path)
final class OllamaPresetLLMService: LLMService {
    private let inner: LocalOpenAIServerLLMService
    var toolHandler: RAGToolHandler? {
        get { inner.toolHandler }
        set { inner.toolHandler = newValue }
    }

    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
         model: String = "llama3.1",
         stream: Bool = true) {
        // Most modern Ollama builds expose OpenAI-compatible endpoints under /v1
        self.inner = LocalOpenAIServerLLMService(
            config: .init(baseURL: baseURL, model: model, chatCompletionsPath: "/v1/chat/completions", stream: stream, headers: nil)
        )
        print("🧪 Ollama Preset → \(baseURL.absoluteString) [model=\(model), stream=\(stream)]")
    }

    var isAvailable: Bool { inner.isAvailable }
    var modelName: String { "Ollama (\(inner.modelName))" }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        try await inner.generate(prompt: prompt, context: context, config: config)
    }
}

#endif

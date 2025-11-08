//
//  MLXLocalLLMService.swift
//  OpenIntelligence
//
//  macOS-only backend that talks to a locally running MLX LLM server (e.g., mlx-lm).
//  Goal: On-device private inference for larger open models using Apple Silicon.
//
//  Status: Initial skeleton with non-streaming request. Endpoint path configurable.
//  Assumes the MLX server exposes an OpenAI-compatible /v1/chat/completions endpoint.
//

import Foundation

#if os(macOS)

final class MLXLocalLLMService: LLMService {
    struct Config {
        /// Base URL of the local server, e.g. http://127.0.0.1:17860
        let baseURL: URL
        /// Model identifier on the server (if required by the server)
        let model: String
        /// Endpoint path (defaults to OpenAI-compatible)
        let chatCompletionsPath: String
        
        init(baseURL: URL = URL(string: "http://127.0.0.1:17860")!,
             model: String = "local-mlx-model",
             chatCompletionsPath: String = "/v1/chat/completions") {
            self.baseURL = baseURL
            self.model = model
            self.chatCompletionsPath = chatCompletionsPath
        }
    }
    
    private let config: Config
    var toolHandler: RAGToolHandler?  // Not used initially
    
    init(config: Config = Config()) {
        self.config = config
        print("🧪 MLXLocalLLMService initialized → \(config.baseURL.absoluteString) [model=\(config.model)]")
        print("   Hint: Start server with: mlx_lm.server --model <name> --port 17860")
    }
    
    var isAvailable: Bool {
        // Optimistic: Only checks local host scheme. A real health check is available via ping()
        return config.baseURL.host == "127.0.0.1" || config.baseURL.host == "localhost"
    }
    
    var modelName: String {
        "MLX Local (\(config.model))"
    }
    
    /// Optional health check to verify server responsiveness
    func ping(timeout: TimeInterval = 2.0) async -> Bool {
        var req = URLRequest(url: config.baseURL)
        req.timeoutInterval = timeout
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode ?? 0 < 500
        } catch {
            return false
        }
    }
    
    func generate(prompt: String, context: String?, config userConfig: InferenceConfig) async throws -> LLMResponse {
        guard isAvailable else {
            throw LLMError.modelUnavailable
        }
        
        let start = Date()
        
        // Compose messages in OpenAI chat format
        var messages: [[String: String]] = []
        messages.append([
            "role": "system",
            "content": """
            You are a helpful assistant. When provided with document context, ground your answer in that context and clearly indicate citations if applicable. If context is irrelevant, answer normally.
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
        
        // Request body (OpenAI-compatible)
        var body: [String: Any] = [
            "model": self.config.model,
            "messages": messages,
            "max_tokens": userConfig.maxTokens,
            "temperature": Double(userConfig.temperature)
        ]
        
        // Build request
        let url = self.config.baseURL.appendingPathComponent(self.config.chatCompletionsPath)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        
        let payload = try JSONSerialization.data(withJSONObject: body)
        req.httpBody = payload
        
        print("🌐 [MLX Local] POST \(url.absoluteString)")
        print("    model=\(self.config.model) max_tokens=\(userConfig.maxTokens) temp=\(userConfig.temperature)")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid response")
        }
        guard http.statusCode == 200 else {
            let errStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.generationFailed("HTTP \(http.statusCode): \(errStr)")
        }
        
        // Parse a minimal OpenAI-style response
        let jsonAny = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = jsonAny as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else {
            throw LLMError.generationFailed("Malformed response")
        }
        
        var content: String?
        if let message = first["message"] as? [String: Any] {
            content = message["content"] as? String
        }
        if content == nil, let text = first["text"] as? String { // fallback if server returns "text"
            content = text
        }
        let textOut = content ?? ""
        
        let total = Date().timeIntervalSince(start)
        let words = textOut.split(separator: " ").count
        
        return LLMResponse(
            text: textOut,
            tokensGenerated: words,               // approx
            timeToFirstToken: nil,                // non-streaming for now
            totalTime: total,
            modelName: self.modelName,
            toolCallsMade: 0
        )
    }
}

#else

// Stub on non-macOS platforms
final class MLXLocalLLMService: LLMService {
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { false }
    var modelName: String { "MLX Local (macOS only)" }
    init(config: Any? = nil) {}
    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        throw LLMError.modelUnavailable
    }
}

#endif

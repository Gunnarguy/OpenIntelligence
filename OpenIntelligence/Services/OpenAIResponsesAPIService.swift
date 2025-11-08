//
//  OpenAIResponsesAPIService.swift
//  OpenIntelligence
//
//  GPT-5 Responses API implementation with reasoning effort and CoT passing.
//  Only use this for GPT-5 models (gpt-5, gpt-5-mini, gpt-5-nano).
//  For other models, use OpenAILLMService (Chat Completions API).
//

import Foundation

/// LLM service for GPT-5 models using the Responses API endpoint
/// Supports reasoning effort, verbosity control, and chain-of-thought passing
/// Reference: https://platform.openai.com/docs/guides/latest-model
class OpenAIResponsesAPIService: LLMService {
    private let apiKey: String
    private let model: String
    private let endpoint = "https://api.openai.com/v1/responses"
    
    // Reasoning effort: minimal, low, medium, high
    var reasoningEffort: String = "medium"
    
    // Verbosity: low, medium, high
    var verbosity: String = "medium"
    
    // Store previous response ID for CoT passing
    private var lastResponseId: String?
    
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { !apiKey.isEmpty }
    var modelName: String { model }
    
    init(apiKey: String, model: String = "gpt-5", reasoningEffort: String = "medium", verbosity: String = "medium") {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.verbosity = verbosity
        
        if isAvailable {
            print("✅ GPT-5 Responses API initialized")
            print("   🔑 Using model: \(model)")
            print("   🧠 Reasoning effort: \(reasoningEffort)")
            print("   📝 Verbosity: \(verbosity)")
        }
    }
    
    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        guard !apiKey.isEmpty else {
            throw LLMError.modelUnavailable
        }
        
        print("\n🌐 [GPT-5 Responses] Starting API call...")
        print("   Model: \(model)")
        print("   Reasoning effort: \(reasoningEffort)")
        print("   Verbosity: \(verbosity)")
        
        let startTime = Date()
        
        // Construct input with context if provided
        var input: String
        if let context = context, !context.isEmpty {
            input = """
            Here is relevant information from the documents:
            
            \(context)
            
            Based on this information, please answer: \(prompt)
            """
        } else {
            input = prompt
        }
        
        // Build request body for Responses API
        var requestBody: [String: Any] = [
            "model": model,
            "input": input
        ]

        if responsesToggle(.includeReasoning, defaultValue: true) {
            requestBody["reasoning"] = ["effort": reasoningEffort]
        }

        if responsesToggle(.includeVerbosity, defaultValue: true) {
            requestBody["text"] = ["verbosity": verbosity]
        }
        
        // Add previous_response_id for CoT passing if available
        if responsesToggle(.includeCoT, defaultValue: true), let prevId = lastResponseId {
            requestBody["previous_response_id"] = prevId
            print("   🔗 Passing previous CoT: \(prevId)")
        }
        
        // Set max output tokens
        if responsesToggle(.includeMaxTokens, defaultValue: true), config.maxTokens > 0 {
            requestBody["max_output_tokens"] = config.maxTokens
        }
        
        // Prepare HTTP request
        guard let url = URL(string: endpoint) else {
            throw LLMError.generationFailed("Invalid endpoint URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Make API call
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid response type")
        }
        
        // Check for errors
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw LLMError.generationFailed("OpenAI API error (\(httpResponse.statusCode)): \(message)")
            }
            throw LLMError.generationFailed("OpenAI API error: HTTP \(httpResponse.statusCode)")
        }
        
        // Parse response
        guard let responseJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.generationFailed("Failed to parse JSON response")
        }
        
        // Extract response ID for next turn
        if let responseId = responseJson["id"] as? String {
            lastResponseId = responseId
            print("   💾 Stored response ID: \(responseId)")
        }
        
        // Extract text from response
        guard let outputText = responseJson["output_text"] as? String else {
            throw LLMError.generationFailed("Missing output_text in response")
        }
        
        // Extract usage stats
        var tokensGenerated = 0
        if let usage = responseJson["usage"] as? [String: Any],
           let outputTokens = usage["output_tokens"] as? Int {
            tokensGenerated = outputTokens
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        
        // Estimate TTFT (Responses API returns this in headers sometimes, but not always)
        let ttft = totalTime * 0.1  // Rough estimate: 10% of total time
        
        print("✅ [GPT-5 Responses] Generation complete")
        print("   ⏱️  Total time: \(String(format: "%.2f", totalTime))s")
        print("   🎯 Output tokens: \(tokensGenerated)")
        
        return LLMResponse(
            text: outputText,
            tokensGenerated: tokensGenerated,
            timeToFirstToken: ttft,
            totalTime: totalTime,
            modelName: modelName,
            toolCallsMade: 0
        )
    }
}

private extension OpenAIResponsesAPIService {
    enum ResponsesToggle: String {
        case includeReasoning = "responsesIncludeReasoning"
        case includeVerbosity = "responsesIncludeVerbosity"
        case includeCoT       = "responsesIncludeCoT"
        case includeMaxTokens = "responsesIncludeMaxTokens"
    }

    func responsesToggle(_ key: ResponsesToggle, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key.rawValue) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }
}

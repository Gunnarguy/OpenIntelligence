import Foundation
import XCTest
@testable import OpenIntelligence

// MARK: - LLM Mocks

final class MockLLMService: LLMService {
    var toolHandler: RAGToolHandler?
    let modelName: String
    let isAvailable: Bool
    private let responseText: String
    private let shouldThrow: Bool
    private let latency: TimeInterval
    private(set) var invocations: Int = 0
    private(set) var lastPrompt: String?
    private(set) var lastContext: String?

    init(
        modelName: String = "Mock LLM",
        responseText: String = "mock-response",
        isAvailable: Bool = true,
        shouldThrow: Bool = false,
        latency: TimeInterval = 0.0
    ) {
        self.modelName = modelName
        self.responseText = responseText
        self.isAvailable = isAvailable
        self.shouldThrow = shouldThrow
        self.latency = latency
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        invocations += 1
        lastPrompt = prompt
        lastContext = context

        if shouldThrow {
            throw LLMError.generationFailed("forced failure")
        }

        if latency > 0 {
            try await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000))
        }

        return LLMResponse(
            text: responseText,
            tokensGenerated: responseText.split(separator: " ").count,
            timeToFirstToken: latency,
            totalTime: latency,
            modelName: modelName,
            toolCallsMade: 0
        )
    }
}

// Always fails generation for fallback tests
final class FailingLLMService: LLMService {
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { true }
    let modelName: String

    init(modelName: String = "Failing LLM") {
        self.modelName = modelName
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        throw LLMError.generationFailed("intentional failure")
    }
}

// MARK: - Billing Mocks

@MainActor
final class MockBillingService: BillingService {
    private let stream: AsyncStream<BillingEvent>
    private let continuation: AsyncStream<BillingEvent>.Continuation

    var events: AsyncStream<BillingEvent> { stream }

    init() {
        var cont: AsyncStream<BillingEvent>.Continuation!
        self.stream = AsyncStream<BillingEvent> { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    func send(_ event: BillingEvent) {
        continuation.yield(event)
    }

    func refreshProducts() async { /* no-op */ }
    func purchase(_ product: BillingProduct) async throws -> Transaction? { nil }
    func restorePurchases() async { /* no-op */ }
}

// MARK: - Embedding Provider Mock

struct MockEmbeddingProvider: EmbeddingProvider {
    let dimension: Int
    var isAvailable: Bool { true }

    func embed(text: String) async throws -> [Float] {
        // Simple deterministic embedding: map each character to a float bucket
        var vector = Array(repeating: Float(0), count: dimension)
        for (idx, scalar) in text.unicodeScalars.enumerated() {
            let bucket = idx % max(dimension, 1)
            vector[bucket] += Float((scalar.value % 3) + 1)
        }
        return vector.map { $0 == 0 ? 0.25 : $0 / 10 }
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        try await texts.map { try embed(text: $0) }
    }
}

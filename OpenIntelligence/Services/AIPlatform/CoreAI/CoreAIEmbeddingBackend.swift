//
//  CoreAIEmbeddingBackend.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

public final class CoreAIEmbeddingBackend: Sendable {
    public static let shared = CoreAIEmbeddingBackend()
    
    private init() {}
    
    public func generateEmbedding(text: String, modelId: String) async throws -> [Float] {
        // Placeholder for CoreAI on-device embedding generation
        return []
    }
}

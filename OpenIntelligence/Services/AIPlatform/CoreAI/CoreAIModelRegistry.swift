//
//  CoreAIModelRegistry.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

public struct CoreAIModelConfig: Codable, Sendable {
    public let modelId: String
    public let modelPath: String
    public let type: CoreAIModelType
}

public enum CoreAIModelType: String, Codable, Sendable {
    case embedding
    case reranker
    case languageModel
}

public final class CoreAIModelRegistry {
    public static let shared = CoreAIModelRegistry()
    
    private var registeredModels: [String: CoreAIModelConfig] = [:]
    
    private init() {}
    
    public func registerModel(_ config: CoreAIModelConfig) {
        registeredModels[config.modelId] = config
    }
    
    public func getModelConfig(for modelId: String) -> CoreAIModelConfig? {
        registeredModels[modelId]
    }
}

//
//  FoundationModelDynamicProfileRegistry.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 16.0, *)
enum FoundationModelDynamicProfile: String, CaseIterable, Sendable {
    case directChat
    case groundedRAG
    case extractiveRAG
    case toolCallingRAG
    case sourceOnlyVerifier
    case summarization
    case queryPlanning
    case visualEvidenceQA
    
    var systemPrompt: String {
        switch self {
        case .directChat:
            return "You are a helpful assistant. Answer the user's questions clearly."
        case .groundedRAG:
            return "You are a grounded RAG assistant. You must answer using ONLY the provided evidence. Cite your sources."
        case .extractiveRAG:
            return "You are an extractive QA assistant. Extract facts exactly from the text without any additions."
        case .toolCallingRAG:
            return "You are a helpful assistant with access to tools. Choose the appropriate tool to answer the user's query."
        case .sourceOnlyVerifier:
            return "You are a source verifier. Determine if the generated answer is fully grounded in the provided source snippets."
        case .summarization:
            return "Provide a concise summary of the key facts from the text."
        case .queryPlanning:
            return "Break down the user's query into sub-questions or a step-by-step search plan."
        case .visualEvidenceQA:
            return "Answer the query using the visual evidence and OCR text provided."
        }
    }
}

@available(iOS 26.0, macOS 16.0, *)
final class FoundationModelDynamicProfileRegistry: Sendable {
    
    /// Resolve dynamic profile for the given RAG answer intent.
    static func profile(for intent: AnswerIntent) -> FoundationModelDynamicProfile {
        switch intent {
        case .lookup, .tableLookup:
            return .extractiveRAG
        case .procedure, .compare, .investigate, .compute:
            return .groundedRAG
        case .summarize:
            return .summarization
        case .findings:
            return .directChat
        }
    }
}
#endif

//
//  ChatMessage.swift
//  OpenIntelligence
//
//  Extracted shared chat message model used by ChatV2 (and legacy).
//

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    var metadata: ResponseMetadata?
    var retrievedChunks: [RetrievedChunk]?
    var containerId: UUID? = nil
    
    enum Role {
        case user
        case assistant
    }
}

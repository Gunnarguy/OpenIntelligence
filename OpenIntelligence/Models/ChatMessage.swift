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

    // User safety controls (GenAI/UGC compliance): allow hiding/reporting individual assistant messages.
    // Note: ChatV2 currently stores messages in-memory only (not persisted), so this is intentionally lightweight.
    var isHidden: Bool = false
    var userReportedAt: Date? = nil
    var userReportReason: String? = nil
    var userReportNotes: String? = nil

    enum Role {
        case user
        case assistant
    }
}

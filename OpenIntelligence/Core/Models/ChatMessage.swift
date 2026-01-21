//
//  ChatMessage.swift
//  OpenIntelligence
//
//  Extracted shared chat message model used by ChatV2 (and legacy).
//

import Foundation

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var metadata: ResponseMetadata?
    var retrievedChunks: [RetrievedChunk]?
    var containerId: UUID? = nil

    // User safety controls (GenAI/UGC compliance): allow hiding/reporting individual assistant messages.
    // Note: ChatV2 currently stores messages in-memory only (not persisted), so this is intentionally lightweight.
    var isHidden: Bool = false
    var userReportedAt: Date? = nil
    var userReportReason: String? = nil
    var userReportNotes: String? = nil

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        metadata: ResponseMetadata? = nil,
        retrievedChunks: [RetrievedChunk]? = nil,
        containerId: UUID? = nil,
        isHidden: Bool = false,
        userReportedAt: Date? = nil,
        userReportReason: String? = nil,
        userReportNotes: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
        self.retrievedChunks = retrievedChunks
        self.containerId = containerId
        self.isHidden = isHidden
        self.userReportedAt = userReportedAt
        self.userReportReason = userReportReason
        self.userReportNotes = userReportNotes
    }

    enum Role: String, Codable, Sendable { 
        case user
        case assistant
        case system
    }
}

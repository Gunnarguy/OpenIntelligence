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

    /// Captured pipeline trace lines (thinking events + pipeline log) for debugging export.
    /// Stored in-memory only — excluded from Codable persistence to keep data lean.
    var pipelineTrace: [String]? = nil

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
        pipelineTrace: [String]? = nil,
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
        self.pipelineTrace = pipelineTrace
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

    // Exclude pipelineTrace from persistence — it's in-memory debugging data only
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, metadata, retrievedChunks, containerId
        case isHidden, userReportedAt, userReportReason, userReportNotes
        // pipelineTrace intentionally excluded
    }
}

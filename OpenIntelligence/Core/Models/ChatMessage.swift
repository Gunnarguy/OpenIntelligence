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
    var structuredAnswer: StructuredAnswer?
    var containerId: UUID? = nil

    /// Original user prompt that produced this assistant turn.
    /// Stored in-memory only for trace export robustness when metadata omits it.
    var traceQuery: String? = nil

    /// Captured real-time thinking events for this turn.
    /// Stored in-memory only — excluded from Codable persistence.
    var thinkingEvents: [ThinkingEvent]? = nil

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
        structuredAnswer: StructuredAnswer? = nil,
        containerId: UUID? = nil,
        traceQuery: String? = nil,
        thinkingEvents: [ThinkingEvent]? = nil,
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
        self.structuredAnswer = structuredAnswer
        self.containerId = containerId
        self.traceQuery = traceQuery
        self.thinkingEvents = thinkingEvents
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
        case id, role, content, timestamp, metadata, retrievedChunks, structuredAnswer, containerId
        case isHidden, userReportedAt, userReportReason, userReportNotes
        // pipelineTrace intentionally excluded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        metadata = try container.decodeIfPresent(ResponseMetadata.self, forKey: .metadata)
        retrievedChunks = try container.decodeIfPresent([RetrievedChunk].self, forKey: .retrievedChunks)
        structuredAnswer = try container.decodeIfPresent(StructuredAnswer.self, forKey: .structuredAnswer)
        containerId = try container.decodeIfPresent(UUID.self, forKey: .containerId)
        traceQuery = nil
        thinkingEvents = nil
        pipelineTrace = nil
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        userReportedAt = try container.decodeIfPresent(Date.self, forKey: .userReportedAt)
        userReportReason = try container.decodeIfPresent(String.self, forKey: .userReportReason)
        userReportNotes = try container.decodeIfPresent(String.self, forKey: .userReportNotes)
    }
}

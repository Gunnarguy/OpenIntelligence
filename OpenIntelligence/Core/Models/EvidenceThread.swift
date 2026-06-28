//
//  EvidenceThread.swift
//  OpenIntelligence
//

import Foundation

/// Represents a distinct conversation thread in the Evidence Threads (Phase 1A) design.
/// Stored strictly as a local JSON file per thread.
struct EvidenceThread: Codable, Identifiable, Sendable {
    let id: UUID
    let containerId: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var metadata: [String: String]

    init(id: UUID = UUID(), containerId: UUID, title: String, createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ChatMessage] = [], metadata: [String: String] = [:]) {
        self.id = id
        self.containerId = containerId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.metadata = metadata
    }
}

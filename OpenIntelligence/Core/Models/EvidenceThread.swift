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
    var messages: [EvidenceThreadMessage]
    var metadata: [String: String]

    init(id: UUID = UUID(), containerId: UUID, title: String, createdAt: Date = Date(), updatedAt: Date = Date(), messages: [EvidenceThreadMessage] = [], metadata: [String: String] = [:]) {
        self.id = id
        self.containerId = containerId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.metadata = metadata
    }
}

/// A message belonging to an EvidenceThread.
struct EvidenceThreadMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    var sources: [EvidenceSource]?

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date(), sources: [EvidenceSource]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sources = sources
    }
}

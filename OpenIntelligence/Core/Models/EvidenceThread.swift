//
//  EvidenceThread.swift
//  OpenIntelligence
//

import Foundation

/// Represents a distinct conversation thread in the Evidence Threads (Phase 1A) design.
/// Stored strictly as a local JSON file per thread.
public struct EvidenceThread: Codable, Identifiable, Sendable {
    public let id: UUID
    public let containerId: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [EvidenceThreadMessage]
    public var metadata: [String: String]

    public init(id: UUID = UUID(), containerId: UUID, title: String, createdAt: Date = Date(), updatedAt: Date = Date(), messages: [EvidenceThreadMessage] = [], metadata: [String: String] = [:]) {
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
public struct EvidenceThreadMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let createdAt: Date
    public var sources: [EvidenceSource]?

    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date(), sources: [EvidenceSource]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sources = sources
    }
}

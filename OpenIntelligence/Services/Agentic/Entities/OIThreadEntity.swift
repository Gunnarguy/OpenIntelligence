//
//  OIThreadEntity.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// A saved conversation, as Shortcuts and Siri see it.
@available(iOS 16.0, macOS 13.0, *)
struct OIThreadEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Conversation")

    var id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Messages")
    var messageCount: Int

    @Property(title: "Date Created")
    var createdAt: Date

    @Property(title: "Last Updated")
    var updatedAt: Date

    @Property(title: "Library")
    var libraryName: String?

    init(id: UUID, title: String, messageCount: Int, createdAt: Date, updatedAt: Date, libraryName: String?) {
        self.id = id
        self.title = title
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.libraryName = libraryName
    }

    init(_ thread: EvidenceThread, libraryName: String?) {
        self.init(
            id: thread.id,
            title: thread.title,
            messageCount: thread.messages.count,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            libraryName: libraryName
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(messageCount) message\(messageCount == 1 ? "" : "s")"
        )
    }

    static var defaultQuery = OIThreadEntityQuery()
}

/// Lists saved conversations from every library, newest first, straight from the thread store.
@available(iOS 16.0, macOS 13.0, *)
struct OIThreadEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [OIThreadEntity.ID]) async throws -> [OIThreadEntity] {
        Self.loadAllThreads().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [OIThreadEntity] {
        Self.loadAllThreads()
    }

    func entities(matching displayName: String) async throws -> [OIThreadEntity] {
        Self.loadAllThreads().filter { $0.title.localizedCaseInsensitiveContains(displayName) }
    }

    func allEntities() async throws -> [OIThreadEntity] {
        Self.loadAllThreads()
    }

    static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Finds saved conversations by title, library, message count or date.",
            categoryName: "Chat",
            searchKeywords: ["find", "filter", "conversations"])
    }

    static func loadAllThreads() -> [OIThreadEntity] {
        let store = EvidenceThreadStore()
        var result: [OIThreadEntity] = []
        for container in OILibraryEntityQuery.loadContainers() {
            let threads = (try? store.listThreads(containerId: container.id)) ?? []
            result.append(contentsOf: threads.map { OIThreadEntity($0, libraryName: container.name) })
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }
}

//
//  OILibraryEntity.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// A library, as Shortcuts, Siri and Spotlight see it, with the properties a shortcut can read.
@available(iOS 16.0, macOS 13.0, *)
struct OILibraryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Library")

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Documents")
    var totalDocuments: Int

    @Property(title: "Passages")
    var totalChunks: Int

    @Property(title: "Date Created")
    var createdAt: Date?

    @Property(title: "Last Indexed")
    var lastIndexedAt: Date?

    init(
        id: UUID,
        name: String,
        totalDocuments: Int,
        totalChunks: Int = 0,
        createdAt: Date? = nil,
        lastIndexedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.totalDocuments = totalDocuments
        self.totalChunks = totalChunks
        self.createdAt = createdAt
        self.lastIndexedAt = lastIndexedAt
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(totalDocuments) document\(totalDocuments == 1 ? "" : "s")"
        )
    }

    static var defaultQuery = OILibraryEntityQuery()
}

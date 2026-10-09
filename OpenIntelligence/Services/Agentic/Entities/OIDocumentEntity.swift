//
//  OIDocumentEntity.swift
//  OpenIntelligence
//

import AppIntents
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A document in a library, as Shortcuts, Siri and Spotlight see it.
///
/// Through 5.6 this carried a title and a subtitle and no properties, so a shortcut could pick a
/// document and read nothing from it. The properties below are what Find, Filter and a model step
/// can read. The file itself can be handed to another app (`Transferable`).
@available(iOS 16.0, macOS 13.0, *)
struct OIDocumentEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Document")

    var id: UUID

    @Property(title: "Name")
    var filename: String

    @Property(title: "Type")
    var kind: String

    @Property(title: "Date Added")
    var addedAt: Date?

    @Property(title: "Pages")
    var pageCount: Int?

    @Property(title: "Words")
    var wordCount: Int?

    @Property(title: "Passages")
    var totalChunks: Int

    @Property(title: "Library")
    var libraryName: String?

    init(
        id: UUID,
        filename: String,
        totalChunks: Int,
        kind: String = "",
        addedAt: Date? = nil,
        pageCount: Int? = nil,
        wordCount: Int? = nil,
        libraryName: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.totalChunks = totalChunks
        self.kind = kind
        self.addedAt = addedAt
        self.pageCount = pageCount
        self.wordCount = wordCount
        self.libraryName = libraryName
    }

    var displayRepresentation: DisplayRepresentation {
        let passages = "\(totalChunks) passage\(totalChunks == 1 ? "" : "s")"
        let subtitle = libraryName.map { "\($0), \(passages)" } ?? passages
        return DisplayRepresentation(title: "\(filename)", subtitle: "\(subtitle)")
    }

    static var defaultQuery = OIDocumentEntityQuery()
}

@available(iOS 16.0, macOS 13.0, *)
extension OIDocumentEntity: Transferable {
    /// The stored file. A PDF is offered as a PDF so the receiving app can preview it; any other
    /// type goes as a plain file, named as it was imported.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { document in
            SentTransferredFile(try OIDocumentEntityQuery.storedFileURL(for: document.id))
        }
        .exportingCondition { $0.kind.lowercased() == "pdf" }

        FileRepresentation(exportedContentType: .data) { document in
            SentTransferredFile(try OIDocumentEntityQuery.storedFileURL(for: document.id))
        }
    }
}

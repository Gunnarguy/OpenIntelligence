//
//  CitationSourceDocument.swift
//  OpenIntelligence
//

import SwiftUI

/// The library's own record of the document a cited passage came from (5.7).
///
/// Through 5.6 the citation sheet built a stand-in document whose file address was only the
/// file name, so nothing that needed the file (its size, Quick Look) could reach it. The chat
/// screen now puts a lookup of the library's documents in the environment, and the sheet asks it.
nonisolated enum CitationSourceDocument {
    /// The document the passage belongs to (`found`, from the library's lookup), or a stand-in
    /// named after the passage's source when the library no longer lists it.
    static func resolve(_ chunk: RetrievedChunk, found: Document?) -> Document {
        if let found, found.id == chunk.chunk.documentId { return found }
        return Document(
            id: chunk.chunk.documentId,
            filename: chunk.sourceDocument,
            fileURL: URL(fileURLWithPath: chunk.sourceDocument),
            contentType: .unknown
        )
    }

    /// Whether a document's file is on this device, which Quick Look needs.
    static func hasFile(_ document: Document) -> Bool {
        FileManager.default.fileExists(atPath: document.fileURL.path)
    }
}

/// Finds one of the library's documents by its id, for the citation sheet. One object for the
/// chat's life: a closure made in the chat's `body` would be a new environment value on every
/// redraw, and every answer on screen would be drawn again on each tick of a streaming answer.
@MainActor
final class LibraryDocumentLookup {
    weak var ragService: RAGService?

    func document(_ id: UUID) -> Document? {
        ragService?.documents.first { $0.id == id }
    }
}

private struct LibraryDocumentLookupKey: EnvironmentKey {
    static let defaultValue: LibraryDocumentLookup? = nil
}

extension EnvironmentValues {
    /// The library's documents, for a cited passage's page. Set by the chat screen.
    var libraryDocumentLookup: LibraryDocumentLookup? {
        get { self[LibraryDocumentLookupKey.self] }
        set { self[LibraryDocumentLookupKey.self] = newValue }
    }
}

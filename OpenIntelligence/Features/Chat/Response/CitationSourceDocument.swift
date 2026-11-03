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

    /// The whole text of a cited passage, read by its id from its document's library (5.7). A saved conversation
    /// keeps each passage cut to 600 characters, so its page reads the passage again here. Nil when the library or
    /// the passage is gone.
    func passageText(_ id: UUID, in document: Document) async -> String? {
        guard let ragService, let containerId = document.containerId,
            ragService.containerService.containers.contains(where: { $0.id == containerId }),
            let database = try? await ragService.dbForContainer(containerId)
        else { return nil }
        return try? await database.chunks(withIDs: [id]).first?.content
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

/// A retrieved passage opened from a source chip (5.8): its PDF page with the passage highlighted, or its document's
/// text with the passage highlighted, as a citation opens it in `GroundedAnswerView`.
struct RetrievedSourceScreen: View {
    let chunk: RetrievedChunk
    let lookup: LibraryDocumentLookup?

    var body: some View {
        let document = CitationSourceDocument.resolve(chunk, found: lookup?.document(chunk.chunk.documentId))
        if let page = CitationSourceDocument.page(of: chunk, in: document) {
            SourcePageView(
                document: document, pageNumber: page, passage: chunk.chunk.content, chunk: chunk, lookup: lookup)
        } else {
            SourceTextView(document: document, passage: chunk.chunk.content, chunk: chunk, lookup: lookup)
        }
    }
}

/// A retrieved passage that a sheet can be presented for.
struct OpenedRetrievedChunk: Identifiable {
    let chunk: RetrievedChunk
    var id: UUID { chunk.chunk.id }
}

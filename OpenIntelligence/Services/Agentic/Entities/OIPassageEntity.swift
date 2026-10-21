//
//  OIPassageEntity.swift
//  OpenIntelligence
//

import AppIntents
import CoreTransferable
import Foundation

/// One passage of a document, as an item another action or another app can take.
///
/// A passage is handed out by a search or with an answer, kept for a day in `HandedOutItems`, and looked up
/// again by its id. Handed out whole (`TransientAppEntity`, the first 5.7 builds), it stopped the next
/// Shortcuts step; see `HandedOutItems`.
@available(iOS 16.0, macOS 13.0, *)
struct OIPassageEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Passage")
    static var defaultQuery = OIPassageEntityQuery()

    /// This handing-out of the passage, not the passage's place in its library: its score belongs to one search.
    var id: UUID

    /// The document the passage came from, so a passage of a deleted document leaves `HandedOutItems`. Not shown
    /// to the system.
    var documentId: UUID?

    @Property(title: "Text")
    var text: String

    @Property(title: "Document")
    var documentName: String

    @Property(title: "Page")
    var page: Int?

    @Property(title: "Section")
    var section: String?

    /// Retrieval score, higher is closer. Comparable within one search only.
    @Property(title: "Score")
    var score: Double

    init() {
        id = UUID()
        documentId = nil
        text = ""
        documentName = ""
        page = nil
        section = nil
        score = 0
    }

    init(text: String, documentName: String, page: Int?, section: String?, score: Double) {
        self.init()
        self.text = text
        self.documentName = documentName
        self.page = page
        self.section = section
        self.score = score
    }

    init(_ chunk: RetrievedChunk) {
        self.init(
            text: chunk.chunk.content,
            documentName: chunk.sourceDocument.isEmpty ? "Document" : chunk.sourceDocument,
            page: chunk.pageNumber ?? chunk.chunk.metadata.pageNumber,
            section: chunk.chunk.metadata.sectionTitle,
            score: Double(chunk.similarityScore)
        )
        documentId = chunk.chunk.documentId
    }

    init(_ stored: HandedOutItems.Passage) {
        self.init(
            text: stored.text, documentName: stored.documentName, page: stored.page, section: stored.section,
            score: stored.score)
        id = stored.id
        documentId = stored.documentId
    }

    /// The form `HandedOutItems` keeps.
    func stored(at date: Date) -> HandedOutItems.Passage {
        HandedOutItems.Passage(
            id: id, documentId: documentId, text: text, documentName: documentName, page: page, section: section,
            score: score,
            createdAt: date)
    }

    /// Passages for `chunks`, kept so the next step of a shortcut can look them up.
    static func handedOut(_ chunks: [RetrievedChunk], now: Date = Date()) -> [OIPassageEntity] {
        let passages = chunks.map(OIPassageEntity.init)
        HandedOutItems.record(passages: passages.map { $0.stored(at: now) }, now: now)
        return passages
    }

    /// "Lease.pdf, page 3", the line a citation shows.
    var sourceLine: String {
        page.map { "\(documentName), page \($0)" } ?? documentName
    }

    /// The passage with its source under it, the form another app receives.
    var textWithSource: String {
        "\(text)\n\n\(sourceLine)"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(sourceLine)", subtitle: "\(String(text.prefix(120)))")
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension OIPassageEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.textWithSource)
    }
}

/// Finds a handed-out passage by its id, for the system's next step.
@available(iOS 16.0, macOS 13.0, *)
struct OIPassageEntityQuery: EntityQuery {
    func entities(for identifiers: [OIPassageEntity.ID]) async throws -> [OIPassageEntity] {
        HandedOutItems.passages(identifiers).map(OIPassageEntity.init)
    }

    func suggestedEntities() async throws -> [OIPassageEntity] {
        []
    }
}

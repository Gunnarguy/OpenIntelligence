//
//  OIPassageEntity.swift
//  OpenIntelligence
//

import AppIntents
import CoreTransferable
import Foundation

/// One passage of a document, as an item another action or another app can take.
///
/// A passage is handed out by a search or with an answer and carries its own text, so it is not
/// looked up again by id (`TransientAppEntity`).
@available(iOS 16.0, macOS 13.0, *)
struct OIPassageEntity: TransientAppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Passage")

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

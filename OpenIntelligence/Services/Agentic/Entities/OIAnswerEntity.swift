//
//  OIAnswerEntity.swift
//  OpenIntelligence
//

import AppIntents
import CoreTransferable
import Foundation

/// An answer with the passages it was written from, as an item another action or app can take.
///
/// An answer from an action is kept for a day in `HandedOutItems` with its passages, and the system looks it
/// up again by its id. Handed out whole (`TransientAppEntity`, the first 5.7 builds), it stopped the next
/// Shortcuts step, Copy to Clipboard among them; see `HandedOutItems`. Handed to another app it arrives as
/// text with its sources listed.
@available(iOS 16.0, macOS 13.0, *)
struct OIAnswerEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Answer")
    static var defaultQuery = OIAnswerEntityQuery()

    var id: UUID

    @Property(title: "Answer")
    var text: String

    @Property(title: "Question")
    var question: String

    @Property(title: "Sources")
    var passages: [OIPassageEntity]

    /// One line per source the answer's labels point at ("[S1] Lease.pdf, page 4"), or for an answer without
    /// labels one per document its passages came from, with their pages.
    @Property(title: "Source List")
    var sourceList: String

    @Property(title: "Mode")
    var mode: OIAnswerMode

    @Property(title: "Model")
    var model: String

    init() {
        id = UUID()
        text = ""
        question = ""
        passages = []
        sourceList = ""
        mode = .standard
        model = ""
    }

    /// An action's answer, kept with its passages so the next step of a shortcut can look it up.
    init(question: String, response: RAGResponse, mode: OIAnswerMode, now: Date = Date()) {
        self.init()
        self.question = question
        self.text = response.generatedResponse
        self.passages = response.retrievedChunks.map(OIPassageEntity.init)
        self.sourceList = Self.sourceList(
            answer: response.generatedResponse, evidence: response.structuredAnswer?.evidence ?? [],
            retrievedChunks: response.retrievedChunks)
        self.mode = mode
        self.model = response.metadata.modelUsed
        HandedOutItems.record(answer: stored(at: now), passages: passages.map { $0.stored(at: now) }, now: now)
    }

    init(_ stored: HandedOutItems.Answer, passages: [HandedOutItems.Passage]) {
        self.init()
        id = stored.id
        question = stored.question
        text = stored.text
        sourceList = stored.sourceList
        mode = OIAnswerMode(rawValue: stored.mode) ?? .standard
        model = stored.model
        self.passages = passages.map(OIPassageEntity.init)
    }

    /// The form `HandedOutItems` keeps.
    func stored(at date: Date) -> HandedOutItems.Answer {
        HandedOutItems.Answer(
            id: id, question: question, text: text, sourceList: sourceList, mode: mode.rawValue, model: model,
            passageIds: passages.map(\.id), createdAt: date)
    }

    /// The answer followed by its sources, the form another app receives, as Copy and Share give it
    /// (`AnswerShareFormatter.textWithSources`). An answer that ends on a line of its own labels ("Sources: [S1]")
    /// loses that line here, since the list after it says what they point at: on 2026-10-20 a shortcut's Copy to
    /// Clipboard gave "Sources:" twice.
    var textWithSources: String {
        sourceList.isEmpty
            ? text : "\(AnswerShareFormatter.withoutClosingSourceLabels(text))\n\nSources:\n\(sourceList)"
    }

    /// The answer's opening in plain words (`AnswerPreview`): Shortcuts shows the title as it is, so through the
    /// first 5.7 builds a result read "### Pet Deposit Amount - **$300.00** [S1]".
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(AnswerPreview.plain(text, limit: 120))", subtitle: "\(question)")
    }

    /// What the answer's labels point at, one line each ("[S1] Lease.pdf, page 4"), the list the app's Share
    /// gives (`AnswerShareFormatter.sources`). An answer without labels lists the documents its passages came
    /// from, each once with its pages. Through the first 5.7 builds the list named documents only, so a copied
    /// answer's [S1] named nothing.
    static func sourceList(
        answer: String, evidence: [StructuredAnswer.Evidence], retrievedChunks: [RetrievedChunk]
    ) -> String {
        AnswerShareFormatter.sources(answer: answer, evidence: evidence, retrievedChunks: retrievedChunks)
            .map(AnswerShareFormatter.line(for:)).joined(separator: "\n")
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension OIAnswerEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.textWithSources)
    }
}

/// Finds a handed-out answer by its id, for the system's next step; offers the latest few in the editor.
@available(iOS 16.0, macOS 13.0, *)
struct OIAnswerEntityQuery: EntityQuery {
    func entities(for identifiers: [OIAnswerEntity.ID]) async throws -> [OIAnswerEntity] {
        HandedOutItems.answers(identifiers).map { answer in
            OIAnswerEntity(answer, passages: HandedOutItems.passages(answer.passageIds))
        }
    }

    func suggestedEntities() async throws -> [OIAnswerEntity] {
        HandedOutItems.recentAnswers(limit: 5).map { answer in
            OIAnswerEntity(answer, passages: HandedOutItems.passages(answer.passageIds))
        }
    }
}

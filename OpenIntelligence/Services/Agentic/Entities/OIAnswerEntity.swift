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

    /// One line per document the answer drew on, with its pages.
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
        self.sourceList = Self.sourceList(for: response.retrievedChunks)
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

    /// The answer followed by its sources, the form another app receives. An answer that ends on a line of source
    /// labels ("Sources: [S1]") loses that line here, since the list after it names the documents and a label means
    /// nothing outside the app: on 2026-10-20 a shortcut's Copy to Clipboard gave "Sources:" twice.
    var textWithSources: String {
        sourceList.isEmpty ? text : "\(Self.withoutClosingSourceLabels(text))\n\nSources:\n\(sourceList)"
    }

    /// `text` without a last line that holds only "Source:" or "Sources:" and labels such as [S1] or [2].
    static func withoutClosingSourceLabels(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard let last = lines.last,
            last.range(of: #"^\s*Sources?:\s*(\[S?\d+\][\s,;]*)+$"#, options: .regularExpression) != nil
        else { return text }
        lines.removeLast()
        while let end = lines.last, end.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.isEmpty ? text : lines.joined(separator: "\n")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(String(text.prefix(120)))", subtitle: "\(question)")
    }

    /// Documents in the order the passages came back, each once, with the pages cited from it.
    static func sourceList(for chunks: [RetrievedChunk]) -> String {
        var order: [String] = []
        var pages: [String: [Int]] = [:]
        for chunk in chunks {
            let name = chunk.sourceDocument.isEmpty ? "Document" : chunk.sourceDocument
            if pages[name] == nil {
                order.append(name)
                pages[name] = []
            }
            if let page = chunk.pageNumber ?? chunk.chunk.metadata.pageNumber, !(pages[name]?.contains(page) ?? false) {
                pages[name]?.append(page)
            }
        }
        return order.map { name -> String in
            let listed = (pages[name] ?? []).sorted()
            switch listed.count {
            case 0: return "- \(name)"
            case 1: return "- \(name), page \(listed[0])"
            default: return "- \(name), pages " + listed.map(String.init).joined(separator: ", ")
            }
        }.joined(separator: "\n")
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

//
//  OIAnswerEntity.swift
//  OpenIntelligence
//

import AppIntents
import CoreTransferable
import Foundation

/// An answer with the passages it was written from, as an item another action or app can take.
///
/// An answer from an action is stored nowhere, so it carries everything with it
/// (`TransientAppEntity`). Handed to another app it arrives as text with its sources listed.
@available(iOS 16.0, macOS 13.0, *)
struct OIAnswerEntity: TransientAppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Answer")

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
        text = ""
        question = ""
        passages = []
        sourceList = ""
        mode = .standard
        model = ""
    }

    init(question: String, response: RAGResponse, mode: OIAnswerMode) {
        self.init()
        self.question = question
        self.text = response.generatedResponse
        self.passages = response.retrievedChunks.map(OIPassageEntity.init)
        self.sourceList = Self.sourceList(for: response.retrievedChunks)
        self.mode = mode
        self.model = response.metadata.modelUsed
    }

    /// The answer followed by its sources, the form another app receives.
    var textWithSources: String {
        sourceList.isEmpty ? text : "\(text)\n\nSources:\n\(sourceList)"
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

//
//  OpenItemIntents.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Opens the app on a library's documents.
///
/// An item with an open action is one Siri and Spotlight can open by name ("Open Home in
/// OpenIntelligence"). Through 5.6 the app had none, so a library or a document found from outside
/// the app could be listed and not opened.
@available(iOS 26.0, macOS 26.0, *)
struct OpenLibraryIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Library"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence on a library's documents and makes it the active library.",
        categoryName: "Libraries",
        searchKeywords: ["open", "show", "library"]
    )

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Library")
    var target: OILibraryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    func perform() async throws -> some IntentResult {
        let id = target.id
        await MainActor.run { AppNavigationRequest.post(.library(id)) }
        return .result()
    }
}

/// Opens the chat, switches it to Deep Think and asks the question again: the Think Deeper button
/// on Siri's answer card (5.7). Deep Think runs for minutes, which is why it opens the app and does
/// not answer in the card. Not listed in Shortcuts.
@available(iOS 26.0, macOS 26.0, *)
struct ThinkDeeperIntent: AppIntent {
    static var title: LocalizedStringResource = "Think Deeper"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence and asks the question again in Deep Think.",
        categoryName: "Ask"
    )
    static let isDiscoverable = false

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question")
    var question: String

    init() {}

    init(question: String) {
        self.question = question
    }

    func perform() async throws -> some IntentResult {
        let asked = question
        await MainActor.run { AppNavigationRequest.post(.ask(asked, sendsAtOnce: true, inDeepThink: true)) }
        return .result()
    }
}

/// Opens the chat in a new conversation that starts with Siri's question and the answer it
/// showed, ready for the next question: the Ask a Follow-up button on Siri's answer card (5.7).
/// The answer is the card's, cut at a word near 600 characters. Not listed in Shortcuts.
@available(iOS 26.0, macOS 26.0, *)
struct AskFollowUpIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask a Follow-up"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence in a new conversation that starts with this question and answer.",
        categoryName: "Ask"
    )
    static let isDiscoverable = false

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question")
    var question: String

    @Parameter(title: "Answer")
    var answer: String

    init() {}

    init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }

    func perform() async throws -> some IntentResult {
        let asked = question
        let answered = answer
        await MainActor.run { AppNavigationRequest.post(.continueAnswer(question: asked, answer: answered)) }
        return .result()
    }
}

/// Opens the app on a document's page, in its library.
///
/// Through the first 5.7 builds this went to the document's library only; the Documents screen now
/// opens the document's page (`DocumentLibraryView.takeDocumentRequest`).
@available(iOS 26.0, macOS 26.0, *)
struct OpenDocumentIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Document"
    static var description: IntentDescription = .init(
        "Opens a document's page in OpenIntelligence.",
        categoryName: "Documents",
        searchKeywords: ["open", "show", "document"]
    )

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Document")
    var target: OIDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    func perform() async throws -> some IntentResult {
        let id = target.id
        await MainActor.run { AppNavigationRequest.post(.document(id)) }
        return .result()
    }
}

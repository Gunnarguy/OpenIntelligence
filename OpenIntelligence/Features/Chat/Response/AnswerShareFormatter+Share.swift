//
//  AnswerShareFormatter+Share.swift
//  OpenIntelligence
//

import Foundation

/// What Share and Copy send for one message. The answer and its source list are `AnswerShareFormatter`
/// (`Services/RAG/Citations`, compiled into the engine too); the app's name and App Store link are added here,
/// for Share only, since `OpenIntelligenceLinks` belongs to the app.
nonisolated extension AnswerShareFormatter {
    static let attribution = "Answered with OpenIntelligence"

    /// The text Share sends for one message. A message that is not an answer, or an answer with no
    /// sources, is returned with the attribution only when it is an answer.
    static func shareText(for message: ChatMessage) -> String {
        guard message.role == .assistant else { return message.content }
        return shareText(
            answer: message.content,
            evidence: message.structuredAnswer?.evidence ?? [],
            retrievedChunks: message.retrievedChunks ?? []
        )
    }

    static func shareText(
        answer: String,
        evidence: [StructuredAnswer.Evidence],
        retrievedChunks: [RetrievedChunk],
        appLink: URL = OpenIntelligenceLinks.sharedAppStoreURL
    ) -> String {
        let text = textWithSources(answer: answer, evidence: evidence, retrievedChunks: retrievedChunks)
        return [text, "\(attribution)\n\(appLink.absoluteString)"].joined(separator: "\n\n")
    }

    /// The text Copy puts on the clipboard for one message (5.7): an answer with the sources its labels point
    /// at, as Share sends it without the app's name and link. Through 5.6 Copy took the answer alone, so its
    /// [S1] labels named nothing once pasted.
    static func copyText(for message: ChatMessage) -> String {
        guard message.role == .assistant else { return message.content }
        return textWithSources(
            answer: message.content,
            evidence: message.structuredAnswer?.evidence ?? [],
            retrievedChunks: message.retrievedChunks ?? []
        )
    }
}

//
//  AnswerShareFormatter.swift
//  OpenIntelligence
//

import Foundation

/// Builds the text that leaves the app when an answer is shared: the answer, the documents it
/// cites, and the app's name with its App Store link.
///
/// Through 5.6, Share sent `message.content` alone, so a forwarded answer kept its `[S2]` labels and
/// lost what they pointed at.
nonisolated enum AnswerShareFormatter {
    /// One line of the source list.
    struct Source: Equatable, Sendable {
        /// The label as the answer wrote it ("S2", "3"), or nil when the answer cites nothing by label.
        let label: String?
        let document: String
        let pages: [Int]
    }

    static let attribution = "Answered with OpenIntelligence"

    /// At most this many documents are listed when the answer cites nothing by label.
    static let maxUnlabelledSources = 8

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
        var parts = [answer.trimmingCharacters(in: .whitespacesAndNewlines)]
        let listed = sources(answer: answer, evidence: evidence, retrievedChunks: retrievedChunks)
        if !listed.isEmpty {
            parts.append((["Sources:"] + listed.map(line(for:))).joined(separator: "\n"))
        }
        parts.append("\(attribution)\n\(appLink.absoluteString)")
        return parts.joined(separator: "\n\n")
    }

    /// The sources an answer names, in the order it names them. When the answer has no label that
    /// resolves to a passage, the documents its passages came from are listed instead, best first.
    static func sources(
        answer: String,
        evidence: [StructuredAnswer.Evidence],
        retrievedChunks: [RetrievedChunk]
    ) -> [Source] {
        guard !retrievedChunks.isEmpty else { return [] }

        let labelled = labelledSources(answer: answer, evidence: evidence, retrievedChunks: retrievedChunks)
        if !labelled.isEmpty { return labelled }

        var order: [String] = []
        var pagesByDocument: [String: [Int]] = [:]
        for chunk in retrievedChunks {
            let name = documentName(of: chunk)
            if pagesByDocument[name] == nil {
                guard order.count < maxUnlabelledSources else { continue }
                order.append(name)
                pagesByDocument[name] = []
            }
            if let page = page(of: chunk), !(pagesByDocument[name]?.contains(page) ?? false) {
                pagesByDocument[name]?.append(page)
            }
        }
        return order.map { Source(label: nil, document: $0, pages: (pagesByDocument[$0] ?? []).sorted()) }
    }

    static func line(for source: Source) -> String {
        var text = source.label.map { "[\($0)] " } ?? "- "
        text += source.document
        if source.pages.count == 1 {
            text += ", page \(source.pages[0])"
        } else if source.pages.count > 1 {
            text += ", pages " + source.pages.map(String.init).joined(separator: ", ")
        }
        return text
    }

    // MARK: - Labels

    /// Resolves each label through `CitationLinker`, the same code that makes the label tappable in
    /// the app, so the shared list names the passage a tap would open.
    private static func labelledSources(
        answer: String,
        evidence: [StructuredAnswer.Evidence],
        retrievedChunks: [RetrievedChunk]
    ) -> [Source] {
        let linked = CitationLinker.linkedMarkdown(answer, evidence: evidence, retrievedChunks: retrievedChunks)
        let pattern = #"\[\[([^\[\]]+)\]\]\(([a-z]+://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let text = linked as NSString
        var seen = Set<String>()
        var result: [Source] = []
        for match in regex.matches(in: linked, range: NSRange(location: 0, length: text.length)) {
            let label = text.substring(with: match.range(at: 1))
            guard let url = URL(string: text.substring(with: match.range(at: 2))),
                let chunk = CitationLinker.chunk(for: url, in: retrievedChunks),
                seen.insert(label.uppercased()).inserted
            else {
                continue
            }
            result.append(
                Source(label: label, document: documentName(of: chunk), pages: page(of: chunk).map { [$0] } ?? [])
            )
        }
        return result
    }

    private static func documentName(of chunk: RetrievedChunk) -> String {
        let name = chunk.sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Document" : name
    }

    private static func page(of chunk: RetrievedChunk) -> Int? {
        chunk.pageNumber ?? chunk.chunk.metadata.pageNumber
    }
}

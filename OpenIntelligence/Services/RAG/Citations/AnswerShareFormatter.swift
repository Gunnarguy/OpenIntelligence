//
//  AnswerShareFormatter.swift
//  OpenIntelligence
//

import Foundation

/// Builds the text that leaves the app with an answer: the answer and the documents its labels point at.
/// Share adds the app's name with its App Store link (`AnswerShareFormatter+Share.swift`, in the app);
/// Copy, an answer item handed to Shortcuts or another app (`OIAnswerEntity`), and an exported conversation
/// use the same list.
///
/// Through 5.6, Share sent `message.content` alone, so a forwarded answer kept its `[S2]` labels and
/// lost what they pointed at. In `Services/` since 5.7, so the engine target, which the answer item is
/// compiled into, has the same rule as the app's Share.
nonisolated enum AnswerShareFormatter {
    /// One line of the source list.
    struct Source: Equatable, Sendable {
        /// The label as the answer wrote it ("S2", "3"), or nil when the answer cites nothing by label.
        let label: String?
        let document: String
        let pages: [Int]
    }

    /// At most this many documents are listed when the answer cites nothing by label.
    static let maxUnlabelledSources = 8

    /// The answer followed by the sources its labels point at, under "Sources:", the form Copy and an answer
    /// item hand to another app. An answer with no passages comes back as written. An answer that ends on a
    /// line of its own labels ("Sources: [S1]") loses that line when the list follows, since the list says what
    /// they point at: on 2026-10-20 a shortcut's Copy to Clipboard gave "Sources:" twice.
    static func textWithSources(
        answer: String,
        evidence: [StructuredAnswer.Evidence],
        retrievedChunks: [RetrievedChunk]
    ) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let listed = sources(answer: answer, evidence: evidence, retrievedChunks: retrievedChunks)
        guard !listed.isEmpty else { return text }
        let list = (["Sources:"] + listed.map(line(for:))).joined(separator: "\n")
        return [withoutClosingSourceLabels(text), list].joined(separator: "\n\n")
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

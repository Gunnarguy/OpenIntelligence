//
//  CitationLinker.swift
//  OpenIntelligence
//

import Foundation

/// Turns the source labels in an answer (`[S2]`, `[S2, S5]`, `[3]`) into links the answer view opens.
///
/// An answer can number its sources two ways. Text rendered from claims labels them by position in
/// `StructuredAnswer.evidence` (`StructuredAnswer.citationLabels`). Text kept as the model wrote it
/// labels them by position in the retrieved chunks, the order the prompt listed them in. A label is
/// resolved to a chunk here, when the link is built, and the chunk's id goes into the link, so a tap
/// never has to guess which numbering the text used.
nonisolated enum CitationLinker {
    static let scheme = "citation"
    private static let chunkHost = "chunk"

    /// Returns the answer as markdown with every resolvable source label turned into a link.
    /// Labels that resolve to no chunk are left as plain text.
    static func linkedMarkdown(
        _ answer: String,
        evidence: [StructuredAnswer.Evidence],
        retrievedChunks: [RetrievedChunk]
    ) -> String {
        guard !retrievedChunks.isEmpty,
            let regex = try? NSRegularExpression(pattern: #"\[([^\[\]\n]{1,80})\](?!\()"#)
        else {
            return answer
        }

        let text = answer as NSString
        let matches = regex.matches(in: answer, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return answer }

        let labelExceedsEvidence = matches.contains { match in
            labels(in: text.substring(with: match.range(at: 1)))?.contains {
                $0.isSourceLabel && $0.number > evidence.count
            } ?? false
        }

        var result = ""
        var cursor = 0
        for match in matches {
            let whole = match.range
            result += text.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            cursor = whole.location + whole.length

            let inner = text.substring(with: match.range(at: 1))
            guard let parsed = labels(in: inner) else {
                result += text.substring(with: whole)
                continue
            }

            let context = sentence(endingAt: whole.location, in: text)
            let rendered = parsed.map { label -> String in
                let chunk = resolve(
                    label,
                    sentence: context,
                    evidence: evidence,
                    retrievedChunks: retrievedChunks,
                    preferPromptOrder: labelExceedsEvidence
                )
                guard let chunk else { return "[\(label.text)]" }
                return "[[\(label.text)]](\(scheme)://\(chunkHost)/\(chunk.chunk.id.uuidString))"
            }
            result += rendered.joined(separator: " ")
        }
        result += text.substring(from: cursor)
        return result
    }

    /// The chunk a citation link points at, or nil when the URL is not one of ours.
    static func chunk(for url: URL, in retrievedChunks: [RetrievedChunk]) -> RetrievedChunk? {
        guard url.scheme == scheme, url.host == chunkHost,
            let id = UUID(uuidString: url.lastPathComponent)
        else {
            return nil
        }
        return retrievedChunks.first { $0.chunk.id == id }
    }

    // MARK: - Labels

    struct Label: Equatable {
        /// The label as the answer wrote it, without brackets: "S2" or "3".
        let text: String
        /// One-based source number.
        let number: Int
        /// True for "S2", false for a bare "3".
        let isSourceLabel: Bool
    }

    /// Parses the inside of a bracket. Returns nil unless every comma-separated part is a source
    /// label, so ordinary bracketed text is left alone.
    static func labels(in inner: String) -> [Label]? {
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var labels: [Label] = []
        for part in parts {
            // "S2: Lease.pdf" carries a name after the number; the label is the part before it.
            let head = part.split(separator: ":", maxSplits: 1).first.map(String.init) ?? part
            let token = head.trimmingCharacters(in: .whitespaces)
            let isSourceLabel = token.first == "S" || token.first == "s"
            let digits = isSourceLabel ? String(token.dropFirst()) : token
            guard !digits.isEmpty, digits.count <= 3, digits.allSatisfy(\.isNumber),
                let number = Int(digits), number > 0
            else {
                return nil
            }
            labels.append(Label(text: token, number: number, isSourceLabel: isSourceLabel))
        }
        return labels
    }

    // MARK: - Resolution

    private static func resolve(
        _ label: Label,
        sentence: String,
        evidence: [StructuredAnswer.Evidence],
        retrievedChunks: [RetrievedChunk],
        preferPromptOrder: Bool
    ) -> RetrievedChunk? {
        let index = label.number - 1
        let byPrompt = retrievedChunks.indices.contains(index) ? retrievedChunks[index] : nil

        // A bare number is the model's own form and always counts retrieved chunks.
        guard label.isSourceLabel else { return byPrompt }

        var byEvidence: RetrievedChunk?
        if evidence.indices.contains(index) {
            let id = evidence[index].evidenceId
            byEvidence = retrievedChunks.first { $0.chunk.id.uuidString == id }
        }

        guard let byPrompt else { return byEvidence }
        guard let byEvidence else { return byPrompt }
        if byPrompt.chunk.id == byEvidence.chunk.id { return byPrompt }

        // The two numberings disagree. Take the passage the sentence was written from.
        let promptScore = overlap(of: sentence, with: byPrompt)
        let evidenceScore = overlap(of: sentence, with: byEvidence)
        if promptScore != evidenceScore {
            return promptScore > evidenceScore ? byPrompt : byEvidence
        }
        return preferPromptOrder ? byPrompt : byEvidence
    }

    /// The sentence a label closes: the text before it, back to the last sentence end or line break.
    private static func sentence(endingAt location: Int, in text: NSString) -> String {
        let before = text.substring(to: location) as NSString
        var start = 0
        for boundary in ["\n", ". ", "! ", "? "] {
            let found = before.range(of: boundary, options: .backwards)
            if found.location != NSNotFound {
                start = max(start, found.location + found.length)
            }
        }
        return before.substring(from: start)
    }

    private static func overlap(of sentence: String, with chunk: RetrievedChunk) -> Int {
        let words = sentence.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !($0.first == "s" && $0.dropFirst().allSatisfy(\.isNumber)) }
        guard !words.isEmpty else { return 0 }
        let content = (chunk.chunk.parentContent ?? chunk.chunk.content).lowercased()
        return Set(words).reduce(0) { $0 + (content.contains($1) ? 1 : 0) }
    }
}

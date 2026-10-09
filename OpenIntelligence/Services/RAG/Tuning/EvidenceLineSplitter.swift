//
//  EvidenceLineSplitter.swift
//  OpenIntelligence
//

import Foundation

/// Cuts a passage into the lines and sentences the evidence filter scores, without cutting inside
/// a sentence.
///
/// Through 5.6 the filter split a passage at every line break and then at every ". ". A sentence
/// wrapped over two lines became two fragments that were scored and kept separately, and "Rent is
/// late after 11:59 p.m. on the 5th." was cut after "p.m", so an answer could quote "on the 5th"
/// without its first half (roadmap row 3f349a74d54f81748e49d885416a4ced).
nonisolated enum EvidenceLineSplitter {
    /// A wrapped line is at least this long; a heading above lowercase text is shorter and is left
    /// on its own line so the lines under it can still inherit it.
    static let minimumWrappedLineLength = 40

    /// The passage's lines, trimmed, with a sentence that was wrapped across lines joined back
    /// together. Two lines are joined only when the first is long and ends in a word, a comma or
    /// an abbreviation's period ("p.m."), the second starts with a lowercase letter and is not a
    /// field ("model: on-device"), and neither is a table row. A blank line always ends a line.
    /// Lines of three characters or fewer are dropped, as before.
    static func lines(in content: String) -> [String] {
        var result: [String] = []
        var current = ""

        func flush() {
            if current.count > 3 { result.append(current) }
            current = ""
        }

        for raw in content.components(separatedBy: CharacterSet.newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
            } else if current.isEmpty {
                current = line
            } else if continues(current, into: line) {
                current += " " + line
            } else {
                flush()
                current = line
            }
        }
        flush()
        return result
    }

    /// The sentences of one line. A table or specification row is kept whole. Pieces of five
    /// characters or fewer are dropped, as before; if that leaves nothing the line is kept whole.
    static func units(in line: String) -> [String] {
        if isTableLike(line) { return [line] }
        let parts = AnswerSentenceSplitter.sentences(in: line).filter { $0.count > 5 }
        return parts.isEmpty ? [line] : parts
    }

    static func isTableLike(_ line: String) -> Bool {
        line.contains("\t") || line.contains("  ") || line.contains("|")
    }

    private static func continues(_ first: String, into second: String) -> Bool {
        guard first.count >= minimumWrappedLineLength,
            !isTableLike(first), !isTableLike(second),
            let opening = second.first, opening.isLetter, opening.isLowercase,
            !isFieldLine(second), !isLetteredItem(second)
        else {
            return false
        }
        let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]", "*", "_"]
        guard let last = first.last(where: { !closers.contains($0) }) else { return false }
        // A wrapped line breaks after a word or a comma. A line that ends in a figure, a bracket or
        // any other mark is more often a row or a line of code, and is left alone.
        if last.isLetter || last == "," { return true }
        // A line that ends in a period may end in "p.m." and not in a sentence.
        if last == "." { return !periodEndsSentence(first) }
        return false
    }

    /// A line that opens with a name and a colon or an equals sign ("model: on-device",
    /// "monthly rent: 1200", "retries = 3") is a field of a record or a setting, not the rest of a
    /// sentence. The name can be up to four words and in any script.
    static func isFieldLine(_ line: String) -> Bool {
        line.range(
            of: #"^[\p{L}_][\p{L}\p{N}_.\[\]-]*( [\p{L}\p{N}_.\[\]-]+){0,3}(:\s|:$|\s?=\s)"#,
            options: .regularExpression) != nil
    }

    /// A lettered list item: "a) under $20,000", "b. Pay rent".
    static func isLetteredItem(_ line: String) -> Bool {
        line.range(of: #"^[a-z][.)]\s"#, options: .regularExpression) != nil
    }

    /// Whether the period that ends `line` ends a sentence. It is judged with a capitalised word
    /// after it, because the sentence splitter reads a lowercase word after any period as the same
    /// sentence going on, which would make every line "continue" into a lowercase one. "p.m." and
    /// "Dr." do not end a sentence; "the 5th." does.
    private static func periodEndsSentence(_ line: String) -> Bool {
        let tail = String(line.suffix(80)).trimmingCharacters(in: .whitespaces)
        let pieces = AnswerSentenceSplitter.sentences(in: tail + " Next")
        return pieces.count > 1 && pieces.last == "Next"
    }
}

//
//  AnswerSentenceSplitter.swift
//  OpenIntelligence
//

import Foundation

/// Splits answer prose into sentences without ever cutting inside a number, a time or an
/// abbreviation.
///
/// The answer cleanup in `LLMService` split on every `.`, `!` and `?` and joined the pieces back with
/// ". ". It did that to every answer, duplicates or not, so "$300.00" came out "$300. 00", and
/// "10:00 p.m." came out "10:00 p." once the one-letter piece "m" was dropped as too short (seen on
/// 5.5, 2026-10-01).
///
/// Two rules make a split safe here. A sentence ends only where whitespace or the end of the text
/// follows its closing punctuation, so the pieces can be joined back with one space and read the same.
/// And every piece is a run of the original text, unchanged, so nothing is retyped: a line break
/// inside a sentence ("... at 6:50 p.m.\nThe gate ...", where "p.m." does not end one) stays in it.
nonisolated enum AnswerSentenceSplitter {
    /// Tokens that end in a period without ending a sentence. Compared lowercased, without the
    /// final period.
    private static let abbreviations: Set<String> = [
        "a.m", "p.m", "e.g", "i.e", "etc", "vs", "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st",
        "inc", "ltd", "co", "corp", "fig", "sec", "approx", "dept", "est", "u.s", "u.k", "u.s.a",
        "ph.d", "ave", "blvd", "apt", "ste", "ext", "no",
    ]

    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "*", "_"]

    /// The sentences of `text`, in order, each trimmed and each with its own closing punctuation.
    /// They are consecutive runs of `text` with only whitespace between them, so joining them with a
    /// single space gives back `text` with the whitespace between sentences reduced to one space.
    static func sentences(in text: String) -> [String] {
        let characters = Array(text)
        var sentences: [String] = []
        var start = 0
        var index = 0

        func flush(upTo end: Int) {
            let piece = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { sentences.append(piece) }
            start = end
        }

        while index < characters.count {
            let character = characters[index]
            guard character == "." || character == "!" || character == "?" else {
                index += 1
                continue
            }

            // Take the whole run of closing punctuation, then any closing quote or bracket.
            var end = index + 1
            while end < characters.count, [".", "!", "?"].contains(characters[end]) { end += 1 }
            while end < characters.count, closers.contains(characters[end]) { end += 1 }

            let atEnd = end == characters.count
            let followedBySpace = !atEnd && characters[end].isWhitespace
            guard atEnd || followedBySpace else {
                // "$300.00", "example.com", "3.5": no space follows, so this is not a sentence end.
                index = end
                continue
            }

            if !atEnd, character == ".", end == index + 1, !endsSentence(characters, periodAt: index, next: end) {
                index = end
                continue
            }

            flush(upTo: end)
            index = end
        }
        flush(upTo: characters.count)
        return sentences
    }

    /// The words in a sentence that carry a digit: amounts, dates, times, part numbers and codes
    /// such as "E1", "$75.00" and "6th". Two sentences that differ in any of these state different
    /// facts however alike the rest of their wording is, so the answer cleanup never treats them as
    /// repeats of each other. "E1 is the sensor's open circuit." and "E2 is the sensor's short
    /// circuit." share four of six words, which was enough for the near-duplicate pass to drop one.
    static func identifierTokens(in sentence: String) -> Set<String> {
        let trimmed = CharacterSet(charactersIn: ".,;:!?()[]{}\"'“”‘’*_`")
        var tokens: Set<String> = []
        for word in sentence.split(whereSeparator: { $0.isWhitespace }) {
            let token = word.trimmingCharacters(in: trimmed).lowercased()
            if token.contains(where: \.isNumber) { tokens.insert(token) }
        }
        return tokens
    }

    /// Whether a single period followed by whitespace closes a sentence.
    private static func endsSentence(_ characters: [Character], periodAt period: Int, next: Int) -> Bool {
        // The word before the period, back to the previous whitespace.
        var wordStart = period
        while wordStart > 0, !characters[wordStart - 1].isWhitespace { wordStart -= 1 }
        let word = String(characters[wordStart..<period])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“‘([*_"))
            .lowercased()

        if abbreviations.contains(word) { return false }
        // An initial: "J. Smith". A single letter after a number is a unit instead ("4.5 L.",
        // "250 g."), and a unit can close a sentence.
        if word.count == 1, word.first?.isLetter == true, !followsNumber(characters, wordStart: wordStart) {
            return false
        }

        // What follows: a lowercase letter continues the sentence ("p.m. every day").
        var following = next
        while following < characters.count, characters[following].isWhitespace { following += 1 }
        if following < characters.count, characters[following].isLowercase { return false }

        return true
    }

    /// Whether the word before the one starting at `wordStart` carries a digit.
    private static func followsNumber(_ characters: [Character], wordStart: Int) -> Bool {
        var end = wordStart
        while end > 0, characters[end - 1].isWhitespace { end -= 1 }
        var start = end
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        return characters[start..<end].contains(where: \.isNumber)
    }
}

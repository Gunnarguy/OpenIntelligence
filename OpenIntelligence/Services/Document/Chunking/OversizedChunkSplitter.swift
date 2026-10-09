//
//  OversizedChunkSplitter.swift
//  OpenIntelligence
//

import Foundation

/// Cuts a passage that is over the embedding token limit into parts that fit, without retyping it.
///
/// Through 5.6 the import split such a passage at every ".", "!", "?" and line break and joined the
/// pieces back with ". ". The stored passage then read "$75. 50" for "$75.50" and "Lease. pdf" for
/// "Lease.pdf", every "?" and "!" became ".", and every line break became ". ". The stored passage is
/// what search indexes, what a citation shows and what the model reads.
///
/// Here a part is made of the passage's own lines. A line that is too long for one part is cut at
/// its sentence ends (`AnswerSentenceSplitter`, which does not cut inside an amount, a time or an
/// abbreviation), a sentence that is still too long is cut between words, and a single run with no
/// space that is too long by itself is cut by characters. Lines keep their line breaks. The one change to the text is that the whitespace between two sentences of a line that
/// had to be cut becomes a single space.
nonisolated enum OversizedChunkSplitter {
    static func parts(of text: String, maxTokens: Int, countTokens: (String) -> Int) -> [String] {
        guard maxTokens > 0, countTokens(text) > maxTokens else { return [text] }

        // Units in order, each with the separator that follows it in the passage.
        var units: [(text: String, separator: String)] = []
        for line in text.components(separatedBy: "\n") {
            if countTokens(line) <= maxTokens {
                units.append((line, "\n"))
                continue
            }
            let sentences = AnswerSentenceSplitter.sentences(in: line)
            let pieces = sentences.isEmpty ? [line] : sentences
            var cut: [String] = []
            for sentence in pieces {
                if countTokens(sentence) <= maxTokens {
                    cut.append(sentence)
                } else {
                    cut.append(contentsOf: wordPieces(of: sentence, maxTokens: maxTokens, countTokens: countTokens))
                }
            }
            for (index, piece) in cut.enumerated() {
                units.append((piece, index == cut.count - 1 ? "\n" : " "))
            }
        }

        var parts: [String] = []
        var current = ""
        var used = 0
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
            current = ""
            used = 0
        }
        for unit in units {
            let cost = countTokens(unit.text) + 1
            if used + cost > maxTokens, !current.isEmpty { flush() }
            current += unit.text + unit.separator
            used += cost
        }
        flush()
        return parts.isEmpty ? [text] : parts
    }

    /// Cuts text between words into pieces of at most `maxTokens`. A single run with no space that is
    /// itself over the limit (Chinese, Japanese or Thai prose, a base64 block, a minified string) is
    /// cut by characters, halving until each piece fits, so no piece is left over the limit.
    static func wordPieces(of text: String, maxTokens: Int, countTokens: (String) -> Int) -> [String] {
        var pieces: [String] = []
        var words: [Substring] = []
        var used = 0
        func flush() {
            if !words.isEmpty { pieces.append(words.joined(separator: " ")) }
            words = []
            used = 0
        }
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let cost = countTokens(String(word)) + 1
            if cost > maxTokens {
                flush()
                pieces.append(contentsOf: characterPieces(of: String(word), maxTokens: maxTokens, countTokens: countTokens))
                continue
            }
            if used + cost > maxTokens { flush() }
            words.append(word)
            used += cost
        }
        flush()
        return pieces
    }

    private static func characterPieces(of run: String, maxTokens: Int, countTokens: (String) -> Int) -> [String] {
        guard run.count > 1, countTokens(run) > maxTokens else { return [run] }
        let middle = run.index(run.startIndex, offsetBy: run.count / 2)
        return characterPieces(of: String(run[..<middle]), maxTokens: maxTokens, countTokens: countTokens)
            + characterPieces(of: String(run[middle...]), maxTokens: maxTokens, countTokens: countTokens)
    }
}

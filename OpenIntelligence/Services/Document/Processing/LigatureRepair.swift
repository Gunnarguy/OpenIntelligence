//
//  LigatureRepair.swift
//  OpenIntelligence
//
//  Restores the "fi", "fl", "ff", "ffi" and "ffl" a PDF's text layer lost (5.8). A font whose ToUnicode map lacks its
//  ligature glyphs makes PDFKit drop them ("gures" for "figures"), read them as a bare "f" ("fbers", "diferent") or as a
//  space ("de ned", "immuno uorescence"); the PDF still prints them, Vision reads them, and `pdftotext`, which falls
//  back to glyph names, keeps them. Measured 2026-11-08 on eight PDFs from the owner's library: BL999 lost 18 "influence"
//  and 13 "inflammatory", fbioe's abstract stored "semide ned", BST stored "gures" and "ef ciency". The repair only joins
//  or fills a word when the result is a word in Apple's on-device lexicon for the page's language and the broken form is
//  not, and only on a page that shows the loss at least twice, so a clean page is never touched.
//

import CoreGraphics
import Foundation
import NaturalLanguage

nonisolated enum LigatureRepair {
    private static let ligatures = ["ffi", "ffl", "ff", "fi", "fl"]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lexicons: [NLLanguage: NLEmbedding?] = [:]

    /// Apple's word lexicon for `language` (NaturalLanguage word embeddings: English, Spanish, French, German, Italian,
    /// Portuguese, Simplified Chinese), loaded once.
    private static func lexicon(for language: NLLanguage) -> NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = lexicons[language] { return cached }
        let loaded = NLEmbedding.wordEmbedding(for: language)
        lexicons[language] = loaded
        return loaded
    }

    private struct Lexicon {
        let embedding: NLEmbedding
        func contains(_ word: String) -> Bool {
            LigatureRepair.lock.lock()
            defer { LigatureRepair.lock.unlock() }
            return embedding.contains(word.lowercased())
        }
    }

    private static func lexicon(forText text: String) -> Lexicon? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4_000)))
        guard let language = recognizer.dominantLanguage, let embedding = lexicon(for: language) else { return nil }
        return Lexicon(embedding: embedding)
    }

    private static func isLowercaseWord(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter && $0.isLowercase }
    }

    /// The one lexicon word `word` becomes with a ligature put back: inserted where it was dropped, or in place of an "f"
    /// it was read as. Nil when no candidate or more than one is a word, or when `word` is already one.
    private static func filled(_ word: String, in lexicon: Lexicon) -> String? {
        guard word.count >= 4, isLowercaseWord(word), !lexicon.contains(word) else { return nil }
        let characters = Array(word)
        var found = Set<String>()
        for index in 0...characters.count {
            let head = String(characters[..<index])
            for ligature in ligatures {
                let candidate = head + ligature + String(characters[index...])
                if lexicon.contains(candidate) { found.insert(candidate) }
                if found.count > 1 { return nil }
            }
            if index < characters.count, characters[index] == "f" {
                let tail = String(characters[(index + 1)...])
                for ligature in ligatures where ligature != "f" {
                    let candidate = head + ligature + tail
                    if lexicon.contains(candidate) { found.insert(candidate) }
                    if found.count > 1 { return nil }
                }
            }
        }
        return found.first
    }

    /// The one lexicon word two pieces make with a ligature between them ("de" + "ned" as "defined"), when at least one
    /// piece is not a word. Nil otherwise.
    private static func joined(_ first: String, _ second: String, in lexicon: Lexicon) -> String? {
        guard isLowercaseWord(first), isLowercaseWord(second), first.count + second.count >= 3 else { return nil }
        guard !lexicon.contains(first) || !lexicon.contains(second) else { return nil }
        let candidates = ligatures.map { first + $0 + second }.filter { lexicon.contains($0) }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private enum Edit {
        case fill(index: Int, word: String)
        case join(index: Int, word: String)
    }

    /// The edits for a sequence of word cores (letters only, punctuation stripped by the caller), or none when the page
    /// shows fewer than two distinct repairs.
    private static func edits(for cores: [String], lexicon: Lexicon, canJoin: (Int) -> Bool) -> [Edit] {
        var edits: [Edit] = []
        var distinct = Set<String>()
        var index = 0
        while index < cores.count {
            let core = cores[index]
            // Only joins that will be applied count toward the gate (refuting review, 2026-11-08: a join refused
            // later across a line break let one repair through alone).
            if index + 1 < cores.count, canJoin(index), let word = joined(core, cores[index + 1], in: lexicon) {
                edits.append(.join(index: index, word: word))
                distinct.insert(word)
                index += 2
                continue
            }
            if let word = filled(core, in: lexicon) {
                edits.append(.fill(index: index, word: word))
                distinct.insert(word)
            }
            index += 1
        }
        return distinct.count >= 2 ? edits : []
    }

    /// `word` split into leading punctuation, letters, trailing punctuation.
    private static func parts(_ word: String) -> (lead: Substring, core: Substring, trail: Substring) {
        let start = word.firstIndex(where: \.isLetter) ?? word.endIndex
        let end = word.lastIndex(where: \.isLetter).map { word.index(after: $0) } ?? start
        guard start < end else { return (word[...], "", "") }
        return (word[..<start], word[start..<end], word[end...])
    }

    /// A page's text with lost ligatures restored; unchanged when the page does not show the loss.
    nonisolated static func repair(_ text: String) -> String {
        guard text.count > 40, let lexicon = lexicon(forText: text) else { return text }
        let ns = text as NSString
        guard let expression = try? NSRegularExpression(pattern: #"\S+"#) else { return text }
        let ranges = expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        guard ranges.count > 6 else { return text }
        let split = ranges.map { parts(ns.substring(with: $0)) }
        // A join only across one space, with no punctuation between the pieces ("de, ned" stays).
        let found = edits(for: split.map { String($0.core) }, lexicon: lexicon) { index in
            let gap = NSRange(
                location: NSMaxRange(ranges[index]), length: ranges[index + 1].location - NSMaxRange(ranges[index]))
            return ns.substring(with: gap) == " " && split[index].trail.isEmpty && split[index + 1].lead.isEmpty
        }
        guard !found.isEmpty else { return text }
        // Each edit replaces a range of the original; applied from the end so earlier ranges stay valid.
        var replacements: [(range: NSRange, text: String)] = []
        for edit in found {
            switch edit {
            case .fill(let index, let word):
                replacements.append((ranges[index], String(split[index].lead) + word + String(split[index].trail)))
            case .join(let index, let word):
                replacements.append(
                    (
                        NSUnionRange(ranges[index], ranges[index + 1]),
                        String(split[index].lead) + word + String(split[index + 1].trail)
                    ))
            }
        }
        let output = NSMutableString(string: text)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            output.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return output as String
    }

    /// A page's text-layer words with lost ligatures restored, two pieces of a word joined into one with both boxes.
    nonisolated static func repair(words: [TextLayerWord]) -> [TextLayerWord] {
        guard words.count > 6 else { return words }
        let sample = words.prefix(800).map(\.text).joined(separator: " ")
        guard let lexicon = lexicon(forText: sample) else { return words }
        let split = words.map { parts($0.text) }
        // A join only of pieces on one line, the second to the right, with no punctuation between them.
        let found = edits(for: split.map { String($0.core) }, lexicon: lexicon) { index in
            let a = words[index].box
            let b = words[index + 1].box
            return abs(a.midY - b.midY) <= max(a.height, b.height) * 0.5 && b.minX >= a.minX
                && split[index].trail.isEmpty && split[index + 1].lead.isEmpty
        }
        guard !found.isEmpty else { return words }
        var output = words
        var removed = Set<Int>()
        for edit in found {
            switch edit {
            case .fill(let index, let word):
                output[index] = TextLayerWord(
                    text: String(split[index].lead) + word + String(split[index].trail), box: words[index].box,
                    pageSize: words[index].pageSize)
            case .join(let index, let word):
                let a = words[index].box
                let b = words[index + 1].box
                output[index] = TextLayerWord(
                    text: String(split[index].lead) + word + String(split[index + 1].trail), box: a.union(b),
                    pageSize: words[index].pageSize)
                removed.insert(index + 1)
            }
        }
        return output.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
    }
}

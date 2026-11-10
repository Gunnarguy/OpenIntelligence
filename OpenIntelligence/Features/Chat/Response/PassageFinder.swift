//
//  PassageFinder.swift
//  OpenIntelligence
//
//  Where a cited passage sits in a document's text, whatever the two texts' dashes, quotes, spacing, line breaks,
//  ligatures and table labels (5.8).
//

import Foundation

/// Finds a passage in a text by its letters and digits alone, and gives the place in the original text.
///
/// The stored passage and the file's own text differ in ways that are not the words: on the owner's iPhone on
/// 2026-11-10 a morin paper's page 2 reads "(4) Ischemia +Morin — in which" in PDFKit's text and "(4) Ischemia + Morin
/// - in which" in the stored passage, so the word-by-word search found nothing and the page showed no highlight under
/// "Found word for word". Folding both texts to their letters and digits (ligatures expanded, case folded) removes
/// every such difference at once: dashes, quotes, spaces, line breaks, a word hyphenated across a line, a table's
/// pipes. Each folded character keeps the range it came from, so a place found in the folded text is a place in the
/// original.
///
/// Three steps, the first that finds it wins: the whole passage; its sentences in order, from the first found to the
/// last (a passage that runs over a page edge, or whose middle differs); and, for text read by OCR, an approximate
/// place where most of the passage's short letter runs line up.
nonisolated enum PassageFinder {
    /// How the place was found.
    enum Method: String, Sendable {
        /// Every letter and digit of the passage, in order, with nothing between them.
        case whole
        /// Some of its sentences, in order; the place runs from the first found to the last.
        case sentences
        /// Most of its short letter runs line up at one place (text read by OCR).
        case approximate
    }

    struct Place: Equatable, Sendable {
        /// In the original text's UTF-16 offsets, as `NSString` and PDFKit count them.
        let range: NSRange
        let method: Method
    }

    /// A text folded to its letters and digits, with where each folded UTF-16 unit came from.
    struct Folded {
        let text: NSString
        /// The text it was folded from.
        let source: NSString
        /// For each UTF-16 unit of `text`, the range in the original text of the character it came from.
        let origins: [NSRange]

        init(_ original: String) {
            let source = original as NSString
            var folded = ""
            var origins: [NSRange] = []
            folded.reserveCapacity(source.length)
            origins.reserveCapacity(source.length)
            var location = 0
            while location < source.length {
                let range = source.rangeOfComposedCharacterSequence(at: location)
                let character = source.substring(with: range)
                // Compatibility mapping expands ligatures ("ﬁ" to "fi") and full-width forms; case is folded after.
                for scalar in character.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars
                where CharacterSet.alphanumerics.contains(scalar) {
                    folded.unicodeScalars.append(scalar)
                    for _ in 0..<String(scalar).utf16.count { origins.append(range) }
                }
                location = range.location + range.length
            }
            text = folded as NSString
            self.origins = origins
            self.source = source
        }

        /// The original range a folded range came from.
        func original(_ range: NSRange) -> NSRange {
            let first = origins[range.location]
            let last = origins[range.location + range.length - 1]
            return NSRange(location: first.location, length: last.location + last.length - first.location)
        }
    }

    /// Letters and digits a piece needs before it is looked for alone: a shorter one ("the", "2") is found anywhere.
    static let minimumPieceLength = 12
    /// The length of the letter runs the approximate step lines up.
    static let runLength = 8
    /// The share of the passage's runs that must line up at one place for an approximate find.
    static let approximateShare = 0.35

    /// Where `passage` is in `text`, or nil. Tries the passage as stored, without the labels the import adds to a
    /// table's passage, and as a table's cell values, each through the three steps.
    static func locate(_ passage: String, in text: String) -> Place? {
        locate(passage, in: Folded(text))
    }

    static func locate(_ passage: String, in folded: Folded) -> Place? {
        locateFolded(passage, in: folded).map {
            Place(range: withEdgePunctuation(folded.original($0.range), of: passage, in: folded.source), method: $0.method)
        }
    }

    /// The range grown to whole words, and over the punctuation the passage itself opens and closes with ("(4) Ischemia", "function."), up
    /// to that many characters, so the mark takes in what the passage shows. Folding drops punctuation, so a place
    /// starts and ends on a letter or digit.
    static func withEdgePunctuation(_ range: NSRange, of passage: String, in source: NSString) -> NSRange {
        let trimmed = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMark: (unichar) -> Bool = { unit in
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return !CharacterSet.alphanumerics.contains(scalar) && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        let leading = trimmed.utf16.prefix { isMark($0) }.count
        let trailing = trimmed.utf16.reversed().prefix { isMark($0) }.count
        var start = range.location
        var end = range.location + range.length
        // A mark covers whole words: a passage cut short mid-word ("Rinse it u...") ends at the word's end.
        let isWordUnit: (unichar) -> Bool = { unit in
            Unicode.Scalar(unit).map { CharacterSet.alphanumerics.contains($0) } ?? false
        }
        while start > 0, isWordUnit(source.character(at: start - 1)), isWordUnit(source.character(at: start)) {
            start -= 1
        }
        while end < source.length, end > 0, isWordUnit(source.character(at: end)), isWordUnit(source.character(at: end - 1)) {
            end += 1
        }
        var taken = 0
        while taken < leading, start > 0, isMark(source.character(at: start - 1)) {
            start -= 1
            taken += 1
        }
        taken = 0
        while taken < trailing, end < source.length, isMark(source.character(at: end)) {
            end += 1
            taken += 1
        }
        return NSRange(location: start, length: end - start)
    }

    /// The place in the folded text, before it is mapped back.
    static func locateFolded(_ passage: String, in folded: Folded) -> (range: NSRange, method: Method)? {
        guard folded.text.length > 0 else { return nil }
        let candidates = Self.candidates(of: passage)
        for candidate in candidates {
            if let range = whole(candidate, in: folded) { return (range, .whole) }
        }
        for candidate in candidates {
            if let range = sentences(of: candidate, in: folded) { return (range, .sentences) }
        }
        for candidate in candidates {
            if let range = approximate(candidate, in: folded) { return (range, .approximate) }
        }
        return nil
    }

    /// Every place to highlight: the passage's place and, unless it was found whole, each of its lines (a table's
    /// cells and rows, a list's items) found near it, so a table read row by row from the page image highlights its
    /// cells where the PDF's text holds them in another order. Lines need 4 letters or digits and are looked for no
    /// further from the place than the passage's own length plus 600. In the original text's offsets, in order, with
    /// overlaps merged. Empty when the passage is not found.
    static func places(_ passage: String, in text: String) -> [NSRange] {
        let folded = Folded(text)
        guard let primary = locateFolded(passage, in: folded) else { return [] }
        var ranges = [primary.range]
        if primary.method != .whole, let lines = candidates(of: passage).last {
            let reach = Folded(lines).text.length + 600
            let lower = max(0, primary.range.location - reach)
            let upper = min(folded.text.length, primary.range.location + primary.range.length + reach)
            var claimed = ranges
            for line in lines.components(separatedBy: .newlines) {
                let needle = Folded(line).text as String
                guard needle.count >= 4 else { continue }
                var from = lower
                while from < upper {
                    let hit = folded.text.range(
                        of: needle, options: [], range: NSRange(location: from, length: upper - from))
                    guard hit.location != NSNotFound else { break }
                    if !claimed.contains(where: { NSIntersectionRange($0, hit).length > 0 }) {
                        claimed.append(hit)
                        break
                    }
                    from = hit.location + 1
                }
            }
            ranges = claimed
        }
        let sorted = ranges.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in sorted {
            if let last = merged.last, range.location <= last.location + last.length {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        return merged.enumerated().map { index, range in
            let original = folded.original(range)
            // The passage's own opening and closing punctuation, on the first and last piece.
            return index == 0 || index == merged.count - 1
                ? withEdgePunctuation(original, of: passage, in: folded.source) : original
        }
    }

    /// The passage, then without the import's labels, then as a table's values; each once.
    static func candidates(of passage: String) -> [String] {
        var trimmed = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        // A passage cut short ("..." or "…", as a saved conversation keeps it) is looked for up to the cut.
        if trimmed.hasSuffix("...") {
            trimmed.removeLast(3)
        } else if trimmed.hasSuffix("\u{2026}") {
            trimmed.removeLast()
        }
        var list = [trimmed]
        let unlabeled = PassageLocator.withoutImportLabels(trimmed)
        if let unlabeled { list.append(unlabeled) }
        if let values = PassageLocator.cellValues(of: unlabeled ?? trimmed) { list.append(values) }
        var seen = Set<String>()
        return list.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The whole passage, folded, in the folded text.
    static func whole(_ passage: String, in folded: Folded) -> NSRange? {
        let needle = Folded(passage).text
        guard needle.length >= 2 else { return nil }
        let found = folded.text.range(of: needle as String)
        return found.location == NSNotFound ? nil : found
    }

    /// The passage's sentences (or, with fewer than two, its lines), each long enough to stand alone, found in order.
    /// Found pieces that sit together (no gap wider than the longest piece plus 300 letters) make a run, and the run
    /// holding the most of the passage's letters is the place: a sentence the page repeats far away (a running header,
    /// a table's header row) cannot stretch the highlight over a column or a page, as it did in 773 of 10,266 measured
    /// passages before this rule (`BenchmarkRuns/2026-11-10-passage-highlight`). Nil unless the run holds at least half
    /// the passage's letters.
    static func sentences(of passage: String, in folded: Folded) -> NSRange? {
        var pieces: [String] = []
        passage.enumerateSubstrings(in: passage.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence { pieces.append(sentence) }
        }
        if pieces.count < 2 { pieces = passage.components(separatedBy: .newlines) }
        let foldedPieces = pieces.map { Folded($0).text as String }.filter { $0.count >= minimumPieceLength }
        guard foldedPieces.count >= 2 else { return nil }
        let total = foldedPieces.reduce(0) { $0 + $1.count }
        let longest = foldedPieces.map(\.count).max() ?? 0
        var found: [(range: NSRange, letters: Int)] = []
        for piece in foldedPieces {
            let start = found.last.map { $0.range.location + $0.range.length } ?? 0
            guard start < folded.text.length else { break }
            let hit = folded.text.range(
                of: piece, options: [], range: NSRange(location: start, length: folded.text.length - start))
            guard hit.location != NSNotFound else { continue }
            found.append((hit, piece.count))
        }
        guard !found.isEmpty else { return nil }
        var runs: [[(range: NSRange, letters: Int)]] = [[found[0]]]
        for hit in found.dropFirst() {
            let previous = runs[runs.count - 1].last!.range
            if hit.range.location - (previous.location + previous.length) <= longest + 300 {
                runs[runs.count - 1].append(hit)
            } else {
                runs.append([hit])
            }
        }
        let best = runs.max { $0.reduce(0) { $0 + $1.letters } < $1.reduce(0) { $0 + $1.letters } }!
        guard best.reduce(0, { $0 + $1.letters }) * 2 >= total else { return nil }
        let first = best.first!.range
        let last = best.last!.range
        return NSRange(location: first.location, length: last.location + last.length - first.location)
    }

    /// For text read by OCR, where single letters differ: the passage's letter runs (`runLength` long, every fourth
    /// one) are looked up in the text, each found run votes for where the passage would start, and the start with the
    /// most votes wins when at least `approximateShare` of the runs agree. The place runs from the first agreeing run
    /// to the last.
    static func approximate(_ passage: String, in folded: Folded) -> NSRange? {
        let needle = Folded(passage).text
        let text = folded.text
        guard needle.length >= runLength * 3, text.length >= runLength else { return nil }
        var votes: [Int: [(textStart: Int, needleStart: Int)]] = [:]
        var runs = 0
        var offset = 0
        while offset + runLength <= needle.length {
            runs += 1
            let run = needle.substring(with: NSRange(location: offset, length: runLength))
            var searchFrom = 0
            var hits = 0
            while searchFrom < text.length, hits < 50 {
                let found = text.range(
                    of: run, options: [], range: NSRange(location: searchFrom, length: text.length - searchFrom))
                guard found.location != NSNotFound else { break }
                // Starts within 8 characters of one another are one place: OCR adds and drops letters.
                let start = (found.location - offset) / 8
                votes[start, default: []].append((found.location, offset))
                searchFrom = found.location + 1
                hits += 1
            }
            offset += 4
        }
        guard runs > 0 else { return nil }
        // A place's votes include its neighbours', so a start that drifted by a few letters still counts.
        let best = votes.keys.max { a, b in
            let countA = (votes[a - 1]?.count ?? 0) + (votes[a]?.count ?? 0) + (votes[a + 1]?.count ?? 0)
            let countB = (votes[b - 1]?.count ?? 0) + (votes[b]?.count ?? 0) + (votes[b + 1]?.count ?? 0)
            return countA < countB
        }
        guard let best else { return nil }
        let agreeing = (votes[best - 1] ?? []) + (votes[best] ?? []) + (votes[best + 1] ?? [])
        let distinctRuns = Set(agreeing.map(\.needleStart)).count
        guard Double(distinctRuns) >= Double(runs) * approximateShare else { return nil }
        let start = agreeing.map(\.textStart).min()!
        let end = agreeing.map { $0.textStart + runLength }.max()!
        return NSRange(location: start, length: end - start)
    }
}

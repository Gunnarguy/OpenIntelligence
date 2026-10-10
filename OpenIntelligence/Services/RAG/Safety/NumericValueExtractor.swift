//
//  NumericValueExtractor.swift
//  OpenIntelligence
//

import Foundation

/// Reads the numbers in a sentence as values, so the number check compares "2.5 billion" with what
/// the passages state and not with any "2.5" printed on the page.
///
/// Through 5.6 the numeric gate counted a number as present when its digits appeared anywhere in the
/// evidence. An answer giving a model "2.5 billion" parameters passed against a benchmark table row
/// that names another model "Qwen-2.5-3B", and the sentence was marked Supported.
///
/// Three things are read here that the old patterns did not read:
/// - a scale word after the number ("3 billion", "3-billion-parameter", "between 2 and 3 billion");
/// - whether the number is part of a name or code ("Qwen-2.5-3B", "GPT-4", "0W-30"), which is
///   matched as that name and never as a quantity;
/// - thousands separators, so "1,250" and "1250" are one value.
///
/// Units are not compared: "5 mg" and "5 kg" are both the value 5, as before. A scale stated once
/// for a table ("in millions") is accepted for a bare number in the same passage, so a wrong scale
/// can still pass there.
nonisolated enum NumericValueExtractor {
    enum Scale: String, Sendable, CaseIterable {
        case thousand, million, billion, trillion

        var multiplier: Double {
            switch self {
            case .thousand: return 1_000
            case .million: return 1_000_000
            case .billion: return 1_000_000_000
            case .trillion: return 1_000_000_000_000
            }
        }
    }

    /// One number, or one name that contains numbers.
    struct Mention: Equatable, Sendable {
        /// The digits as written: "2.5", "1,250". For a name, the whole name.
        var digits: String
        /// The number before any scale is applied. Zero for a name.
        var base: Double
        var scale: Scale?
        /// True when the scale was a suffix ("3B", "5k"), which also has other readings ("4K").
        var scaleIsSuffix: Bool
        /// The name or code the number is part of, or nil for a plain value.
        var identifier: String?
        /// The word just before the number, lowercased letters only ("ios" in "iOS 26").
        var precedingWord: String?
        /// Letters written against the digits that are not a scale: "psi" in "35psi", "th" in "5th".
        var attachedSuffix: String?
        /// One letter written against the front of the digits: "Q" in "Q3", "v" in "v2.1".
        var attachedPrefix: String?

        var value: Double { base * (scale?.multiplier ?? 1) }

        /// How the mention reads in a message: "2.5 billion", "Qwen-2.5-3B".
        var written: String {
            if let identifier { return identifier }
            let digits = (attachedPrefix ?? "") + digits
            guard let scale else { return digits }
            return scaleIsSuffix ? "\(digits) (\(scale.rawValue))" : "\(digits) \(scale.rawValue)"
        }
    }

    /// The numbers of one passage, with what is needed to match an answer against it.
    struct Evidence: Sendable {
        /// Plain values only. A number inside a name is not listed here.
        let values: [Mention]
        /// Names and codes that contain numbers, letters and digits only, lowercased.
        let compactIdentifiers: [String]
        /// The passage with everything but letters and digits removed, lowercased.
        let compactText: String
        /// Scale words in the passage that do not follow a number: "(in millions)".
        let freeScales: Set<Scale>
    }

    // MARK: - Reading

    /// The numbers an answer states. Citation labels ("[S2]", "[3]") and list numbers at the start
    /// of a line are not numbers the answer states, and are left out.
    static func mentions(inAnswer text: String) -> [Mention] {
        scan(strippingAnswerMarkup(text), forEvidence: false).mentions
    }

    static func evidence(from passages: [String]) -> [Evidence] {
        passages.map { passage in
            let result = scan(passage, forEvidence: true)
            return Evidence(
                values: result.mentions.filter { $0.identifier == nil },
                compactIdentifiers: result.mentions.compactMap { $0.identifier.map(compact) },
                compactText: compact(passage),
                freeScales: result.freeScales
            )
        }
    }

    // MARK: - Which numbers the gate counts

    /// Units the numeric gate has always read against the digits ("35psi").
    private static let gateUnits: Set<String> = ["mg", "kg", "ml", "L", "mm", "cm", "m", "psi", "kPa"]
    private static let oldCodePattern = try! NSRegularExpression(pattern: #"[A-Z0-9]+-[A-Z0-9]+"#)

    /// Whether the numeric gate counted this kind of number before 5.7. The gate's patterns skipped
    /// digits with a letter against either side ("5th", "10pm", "Q3", "4K", "iPhone17") and counted a
    /// name only when it had the shape of a code ("GPT-4", "0W-30"). 5.7 changes how a counted
    /// number is matched and stops counting citation labels and list numbers; it counts nothing
    /// the gate skipped, so a right answer that says "Q3" where the passage says "third quarter" is
    /// no worse off than it was.
    static func isCountedByGate(_ mention: Mention) -> Bool {
        if let identifier = mention.identifier {
            let range = NSRange(identifier.startIndex..., in: identifier)
            return oldCodePattern.firstMatch(in: identifier, range: range) != nil
        }
        if mention.attachedPrefix != nil || mention.scaleIsSuffix { return false }
        guard let suffix = mention.attachedSuffix else { return true }
        return gateUnits.contains(suffix)
    }

    // MARK: - Matching

    /// Whether any passage states this number.
    ///
    /// A name is supported when a passage contains the name. A value is supported when a passage
    /// states the same value outside a name, or when the answer writes a name's number after the
    /// name's word ("iOS 26" against "iOS26").
    static func isSupported(_ mention: Mention, by evidence: [Evidence]) -> Bool {
        if let identifier = mention.identifier {
            let wanted = compact(identifier)
            guard !wanted.isEmpty else { return true }
            return evidence.contains { $0.compactText.contains(wanted) }
        }

        for passage in evidence {
            if passage.values.contains(where: { sameValue(mention, $0) }) { return true }
            // "2.5 million" against a table cell "2.5" under a heading "(in millions)".
            if let scale = mention.scale, !mention.scaleIsSuffix, passage.freeScales.contains(scale),
                passage.values.contains(where: {
                    $0.scale == nil && equal($0.base, mention.base) && sameLabel(mention, $0)
                })
            {
                return true
            }
        }

        if mention.scale == nil, let word = mention.precedingWord, word.count >= 2 {
            let named = word + compact(mention.digits)
            if evidence.contains(where: { $0.compactIdentifiers.contains { $0.contains(named) } }) { return true }
        }
        return false
    }

    /// The first number in `sentence` that no passage states, or nil. `exempt` lets the caller pass
    /// numbers it does not check, such as years.
    static func firstUnsupportedMention(
        in sentence: String,
        evidence: [Evidence],
        exempt: (Mention) -> Bool = { _ in false }
    ) -> Mention? {
        mentions(inAnswer: sentence).first { !exempt($0) && !isSupported($0, by: evidence) }
    }

    private static func sameValue(_ a: Mention, _ b: Mention) -> Bool {
        guard sameLabel(a, b) else { return false }
        if equal(a.value, b.value) { return true }
        guard equal(a.base, b.base) else { return false }
        // "4K" and "4": a suffix has readings other than a scale, so the bare digits also match.
        return (a.scale == nil && b.scaleIsSuffix) || (b.scale == nil && a.scaleIsSuffix)
    }

    /// "M3" is not the number 3. A number with a letter against its front matches a number with the
    /// same letter, or one that follows a word starting with it ("version 2.1" and "v2.1").
    private static func sameLabel(_ a: Mention, _ b: Mention) -> Bool {
        switch (a.attachedPrefix?.lowercased(), b.attachedPrefix?.lowercased()) {
        case (nil, nil): return true
        case (let x?, let y?): return x == y
        case (let letter?, nil): return b.precedingWord?.hasPrefix(letter) ?? false
        case (nil, let letter?): return a.precedingWord?.hasPrefix(letter) ?? false
        }
    }

    private static func equal(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(abs(a), abs(b)) * 1e-9
    }

    // MARK: - Scanner

    private struct ScanResult {
        var mentions: [Mention] = []
        var freeScales: Set<Scale> = []
    }

    /// A number with thousands separators, or plain digits with an optional decimal part. The
    /// lookahead keeps "30,1200" from being read as "30,120" and "0".
    private static let numberPattern = try! NSRegularExpression(
        pattern: #"\d{1,3}(?:,\d{3})+(?!\d)(?:\.\d+)?|\d+(?:\.\d+)?"#)
    private static let citationPattern = try! NSRegularExpression(
        pattern: #"\[\^?[A-Za-z]{0,3}\d+(?:\s*[,;]\s*\^?[A-Za-z]{0,3}\d+)*\]"#)
    private static let listMarkerPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*\d{1,3}[.)][ \t]+"#, options: [.anchorsMatchLines])
    /// A grade code: letters against the first number or leading the run, a hyphen, a bare number.
    /// "0W-30", "5W-40", "A2-70", "M8-1.25". Not "8am-5pm" or "5mg-10mg", which are ranges.
    private static let gradeCodePattern = try! NSRegularExpression(
        pattern: #"^[A-Za-z]{0,2}\d+(?:\.\d+)?[A-Za-z]{0,2}[-‑–]\d+(?:\.\d+)?$"#)

    private static let leadingTrim = CharacterSet(charactersIn: "([{<\"'“”‘’*_`~≈")
    private static let trailingTrim = CharacterSet(charactersIn: ")]}>\"'“”‘’*_`.,;:!?…")
    private static let joiners: Set<Character> = ["-", "_", "/", "‑", "–"]
    /// Words between the two ends of a range that share one scale: "2 to 3 billion".
    private static let rangeWords: Set<String> = ["to", "and", "or", "through", "-", "–", "—"]

    private static let scaleWords: [String: Scale] = [
        "thousand": .thousand, "thousands": .thousand,
        "million": .million, "millions": .million,
        "billion": .billion, "billions": .billion,
        "trillion": .trillion, "trillions": .trillion,
    ]
    /// Suffixes written against the digits. "MB", "kg" and "km" are longer and do not match.
    private static let scaleSuffixes: [String: Scale] = [
        "K": .thousand, "k": .thousand, "M": .million, "B": .billion, "bn": .billion, "Bn": .billion,
    ]
    /// Letter runs that sit against an amount without making it a name.
    private static let currencyPrefixes: Set<String> = [
        "usd", "us", "cad", "ca", "aud", "au", "nzd", "nz", "eur", "gbp", "jpy", "cny", "rmb", "inr", "rs",
        "rm", "chf", "sgd", "hkd", "hk", "mxn", "brl", "krw", "sek", "nok", "dkk", "zar", "aed", "sar",
    ]

    private static func strippingAnswerMarkup(_ text: String) -> String {
        var result = text
        for pattern in [citationPattern, listMarkerPattern] {
            result = pattern.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        return result
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func scan(_ text: String, forEvidence: Bool) -> ScanResult {
        var result = ScanResult()
        // A table row can reach here without spaces around its bars.
        let runs = text.split(whereSeparator: { $0.isWhitespace || $0 == "|" }).map(String.init)
        var consumedAsScale = Set<Int>()
        // For each mention, the run it came from, and whether it is the second reading of a comma
        // list, which never takes part in a range.
        var origin: [(run: Int, alternate: Bool)] = []

        for (index, rawRun) in runs.enumerated() {
            let run = trimmed(rawRun)
            guard run.contains(where: \.isNumber) else { continue }
            let nsRun = run as NSString
            let matches = numberPattern.matches(in: run, range: NSRange(location: 0, length: nsRun.length))
            guard !matches.isEmpty else { continue }

            if isIdentifier(run, numbers: matches) {
                result.mentions.append(
                    Mention(
                        digits: run, base: 0, scale: nil, scaleIsSuffix: false, identifier: run,
                        precedingWord: nil, attachedSuffix: nil, attachedPrefix: nil))
                origin.append((index, false))
                continue
            }

            let preceding = index > 0 ? letters(of: runs[index - 1]) : nil
            // A scale word in the next run belongs to this number only when nothing closes the run
            // after it: "2.5 billion", not "in 2024. Millions were affected".
            let endsOpen = endsWithNumber(rawRun)

            for (position, match) in matches.enumerated() {
                let digits = nsRun.substring(with: match.range)
                guard let base = Double(digits.replacingOccurrences(of: ",", with: "")) else { continue }
                let before = nsRun.substring(to: match.range.location)
                let after = nsRun.substring(from: match.range.location + match.range.length)
                let isLast = position == matches.count - 1

                var scale: Scale?
                var scaleIsSuffix = false
                if let attached = attachedScale(after) {
                    scale = attached.scale
                    scaleIsSuffix = attached.isSuffix
                } else if isLast, endsOpen, after.isEmpty || after == "%", index + 1 < runs.count,
                    let next = leadingScaleWord(runs[index + 1])
                {
                    scale = next
                    consumedAsScale.insert(index + 1)
                }

                // ".5" is one half: the dot belongs to the number when nothing numeric precedes it.
                let leadingDot =
                    before.hasSuffix(".") && !(before.dropLast().last?.isLetter ?? false)
                    && !(before.dropLast().last?.isNumber ?? false) && !digits.contains(".")
                let value = leadingDot ? (Double("0." + digits) ?? base) : base

                result.mentions.append(
                    Mention(
                        digits: leadingDot ? "0." + digits : digits,
                        base: value,
                        scale: scale,
                        scaleIsSuffix: scaleIsSuffix,
                        identifier: nil,
                        precedingWord: position == 0 && before.isEmpty ? preceding : nil,
                        attachedSuffix: scale == nil ? attachedLetters(after) : nil,
                        attachedPrefix: attachedLetter(before)))
                origin.append((index, false))

                // "Widget,12,500,100" is a row of fields, and "12,500,100" inside it is also one
                // number. When a passage's run has commas outside the number, it is read both ways.
                // "100,000" standing alone is one number, so "100" does not match it.
                if forEvidence, digits.contains(","), before.contains(",") || after.contains(",") {
                    let whole = digits.split(separator: ".", maxSplits: 1)[0]
                    for part in whole.split(separator: ",") {
                        guard let partValue = Double(part) else { continue }
                        result.mentions.append(
                            Mention(
                                digits: String(part), base: partValue, scale: nil, scaleIsSuffix: false,
                                identifier: nil, precedingWord: nil, attachedSuffix: nil, attachedPrefix: nil))
                        origin.append((index, true))
                    }
                }
            }
        }

        shareRangeScales(in: &result.mentions, origin: origin, runs: runs)

        for (index, rawRun) in runs.enumerated() where !consumedAsScale.contains(index) {
            let word = letters(of: rawRun) ?? ""
            if let scale = scaleWords[word], !trimmed(rawRun).contains(where: \.isNumber) {
                result.freeScales.insert(scale)
            }
        }
        return result
    }

    /// "between 2 and 3 billion", "5 to 10 million", "2-3 billion": the scale after the last number
    /// of a range is the scale of the numbers before it.
    private static func shareRangeScales(
        in mentions: inout [Mention], origin: [(run: Int, alternate: Bool)], runs: [String]
    ) {
        let primary = mentions.indices.filter { !origin[$0].alternate }
        for (slot, index) in primary.enumerated().reversed() {
            // A scale word only. A suffix is written on each number that has one ("$2M and $3M").
            guard let scale = mentions[index].scale, !mentions[index].scaleIsSuffix,
                mentions[index].identifier == nil, slot > 0
            else { continue }
            var later = index
            for earlier in primary[..<slot].reversed() {
                let candidate = mentions[earlier]
                guard candidate.identifier == nil, candidate.scale == nil,
                    candidate.attachedPrefix == nil, candidate.attachedSuffix == nil,
                    inOneRange(origin[earlier].run, origin[later].run, runs: runs)
                else { break }
                mentions[earlier].scale = scale
                later = earlier
            }
        }
    }

    /// Two numbers are ends of one range when they sit in the same run with no letters ("2-3"), or
    /// one range word apart with nothing closing the first ("2 to 3", "2 and 3").
    private static func inOneRange(_ first: Int, _ second: Int, runs: [String]) -> Bool {
        if first == second { return !trimmed(runs[first]).contains(where: \.isLetter) }
        guard second - first == 2 else { return false }
        return rangeWords.contains(trimmed(runs[first + 1]).lowercased()) && endsWithNumber(runs[first])
    }

    private static func endsWithNumber(_ rawRun: String) -> Bool {
        rawRun.unicodeScalars.last.map { CharacterSet.decimalDigits.contains($0) || $0 == "%" } ?? false
    }

    /// A run is a name or code when letters lead into its digits ("Qwen-2.5-3B", "GPT-4",
    /// "iPhone17", "gpt-4o"), or when it is a grade code ("0W-30", "A2-70").
    ///
    /// These stay values: letters that only follow the digits ("35psi", "60-day",
    /// "3-billion-parameter", "8am-5pm"), a lowercase word hyphenated to one number that ends the
    /// run ("top-5", "under-21"), one letter before the digits ("v2.1", "Q3"), a currency code
    /// ("USD100"), and a year with a word in front ("mid-2025", "FY2024").
    private static func isIdentifier(_ run: String, numbers: [NSTextCheckingResult]) -> Bool {
        let nsRun = run as NSString
        guard let first = numbers.first, let last = numbers.last else { return false }

        if numbers.count == 1, let year = Int(nsRun.substring(with: first.range)), (1900...2100).contains(year) {
            return false
        }

        // Letters before the first number, joined to it directly or by one joiner.
        var prefix = Substring(nsRun.substring(to: first.range.location))
        let hyphenated = prefix.last.map { joiners.contains($0) } ?? false
        if hyphenated { prefix = prefix.dropLast() }
        let leadingLetters = String(prefix.reversed().prefix(while: { $0.isLetter }).reversed())
        if leadingLetters.count >= 2, !currencyPrefixes.contains(leadingLetters.lowercased()) {
            let tail = nsRun.substring(from: last.range.location + last.range.length)
            let plainCompound =
                hyphenated && numbers.count == 1 && tail.isEmpty
                && leadingLetters == leadingLetters.lowercased()
            if !plainCompound { return true }
        }

        guard run.contains(where: \.isLetter) else { return false }
        return gradeCodePattern.firstMatch(in: run, range: NSRange(location: 0, length: nsRun.length)) != nil
    }

    /// Letters written against the digits ("psi" in "35psi"), or nil.
    private static func attachedLetters(_ after: String) -> String? {
        let suffix = String(after.prefix(while: \.isLetter))
        return suffix.isEmpty ? nil : suffix
    }

    /// One letter written against the front of the digits ("Q" in "Q3"), or nil. Two or more make
    /// the run a name, which `isIdentifier` has already taken, or a currency code.
    private static func attachedLetter(_ before: String) -> String? {
        guard let last = before.last, last.isLetter else { return nil }
        guard !(before.dropLast().last?.isLetter ?? false) else { return nil }
        return String(last)
    }

    /// A scale written against the digits: "-billion", "-billion-parameter", "B", "k", "bn".
    private static func attachedScale(_ after: String) -> (scale: Scale, isSuffix: Bool)? {
        guard !after.isEmpty else { return nil }
        if let first = after.first, joiners.contains(first) {
            let word = String(after.dropFirst().prefix(while: \.isLetter)).lowercased()
            if let scale = scaleWords[word] { return (scale, false) }
            return nil
        }
        let suffix = String(after.prefix(while: \.isLetter))
        guard suffix.count == after.count || !(after.dropFirst(suffix.count).first?.isLetter ?? false) else {
            return nil
        }
        if let scale = scaleWords[suffix.lowercased()] { return (scale, false) }
        if let scale = scaleSuffixes[suffix] { return (scale, true) }
        return nil
    }

    /// The scale a following word names: "billion", "million.", "billion-parameter".
    private static func leadingScaleWord(_ rawRun: String) -> Scale? {
        let run = trimmed(rawRun)
        let word = String(run.prefix(while: \.isLetter)).lowercased()
        guard let scale = scaleWords[word] else { return nil }
        let rest = run.dropFirst(word.count)
        guard rest.isEmpty || joiners.contains(rest.first!) else { return nil }
        return scale
    }

    private static func trimmed(_ run: String) -> String {
        var scalars = Substring(run).unicodeScalars
        while let first = scalars.first, leadingTrim.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, trailingTrim.contains(last) { scalars.removeLast() }
        var result = String(scalars)
        for possessive in ["'s", "’s"] where result.hasSuffix(possessive) {
            result.removeLast(possessive.count)
        }
        return result
    }

    /// The run as lowercased letters, or nil when it has none or carries digits of its own.
    private static func letters(of rawRun: String) -> String? {
        let run = trimmed(rawRun)
        guard !run.isEmpty, !run.contains(where: \.isNumber) else { return nil }
        let word = String(run.filter(\.isLetter)).lowercased()
        return word.isEmpty ? nil : word
    }
}

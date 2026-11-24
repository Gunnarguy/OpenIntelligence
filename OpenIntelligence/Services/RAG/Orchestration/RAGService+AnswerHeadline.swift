//
//  RAGService+AnswerHeadline.swift
//  OpenIntelligence
//
//  Two repairs to the first line of an answer, both by rule (5.8, 2026-11-13).
//
//  On the owner's iPhone that day "How many participants received the creatine mix?" was answered "3. **49**" over
//  four bullets of 16, 16, 15 and 7 participants from four studies: a list number in front of nothing, and a total the
//  model added up itself (wrongly: they sum to 54) that no document states. The run before it wrote "1. **Six**" over
//  three bullets. The count instruction asked for "the exact count FIRST", so the model produced a number of its own.
//  Answers here come only from what the documents say, so a headline number the documents don't give is taken off and
//  the cited figures under it stand.
//

import Foundation

extension RAGService {
    /// Takes a list number off the front of an answer that is not a numbered list: "3. **49**" becomes "**49**". A
    /// real list (a second numbered line anywhere below) is left alone.
    nonisolated static func strippingStrayLeadingListNumber(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return text }
        let marker = #"^\s*\d{1,2}[.)]\s+(?=\S)"#
        guard let range = lines[first].range(of: marker, options: .regularExpression) else { return text }
        let others = lines[(first + 1)...].contains { $0.range(of: #"^\s*\d{1,2}[.)]\s+\S"#, options: .regularExpression) != nil }
        guard !others else { return text }
        lines[first].removeSubrange(range)
        return lines.joined(separator: "\n")
    }

    private nonisolated static let headlineNumberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
    ]

    private nonisolated static let headlineStopWords: Set<String> = [
        "many", "much", "what", "which", "does", "have", "were", "with", "from", "that", "this", "there", "their",
        "about", "into", "they", "them", "been", "will", "would", "could", "should", "your", "some",
    ]

    /// The number an answer opens with when its first line is nothing but a number ("**49**", "Six"), or nil.
    nonisolated static func headlineNumber(of line: String) -> Int? {
        let bare = line.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".:")))
        if let word = headlineNumberWords[bare.lowercased()] { return word }
        guard bare.range(of: #"^\d[\d,]*$"#, options: .regularExpression) != nil else { return nil }
        return Int(bare.replacingOccurrences(of: ",", with: ""))
    }

    /// Takes a headline number off an answer when the documents don't give it. The answer must open with a line that
    /// is only a number, over a list of two or more items. The number stays when it is the count of the items listed
    /// under it, or when a source passage states it as a count of something the question names ("16 participants"); otherwise the
    /// line goes and the list, with its citations, is the answer. Returns the text and the number taken off, if any.
    nonisolated static func droppingUnsupportedHeadlineNumber(
        _ text: String, question: String, sources: [String]
    ) -> (text: String, dropped: Int?) {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
            let value = headlineNumber(of: lines[first])
        else { return (text, nil) }
        let items = lines[(first + 1)...].filter {
            $0.range(of: #"^\s*([-*•]|\d{1,2}[.)])\s+\S"#, options: .regularExpression) != nil
        }
        guard items.count >= 2, value != items.count else { return (text, nil) }

        let keywords = Set(
            question.lowercased().components(separatedBy: CharacterSet.letters.inverted)
                .filter { $0.count >= 4 && !headlineStopWords.contains($0) })
        var forms = ["\(value)"]
        if value >= 1000 { forms.append(value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))) }
        forms.append(contentsOf: headlineNumberWords.filter { $0.value == value }.map(\.key))
        // Stated means the number counts a thing the question names: "16 participants", "sixteen enrolled participants".
        // A looser test (the number anywhere within 120 characters of a question word) kept "49" for "Page 49" two
        // lines under "participants", and "6" for "(6 MELAS, 1 myopathy)": the unit test's first run, 2026-11-13.
        let keywordPattern = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let stated = !keywords.isEmpty && sources.contains { source in
            let lower = source.lowercased()
            return forms.contains { form in
                let pattern =
                    #"(?<![\w.,])"# + NSRegularExpression.escapedPattern(for: form) + #"\s+(\w+\s+)?("# + keywordPattern + ")"
                return lower.range(of: pattern, options: .regularExpression) != nil
            }
        }
        guard !stated else { return (text, nil) }
        lines.remove(at: first)
        let kept = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (kept, value)
    }

    /// Takes a paper's own reference numbers out of an answer (5.8, 2026-11-13). Passages from research papers carry
    /// the paper's citations ("[222]", "[205, 206]"), and the model copied them into its answer in place of the app's
    /// "[S#]" labels: on the owner's iPhone a Standard answer cited "[124]", "[222]" and "[3]", and the chat drew "[3]"
    /// as a link to the answer's third source, which it was not. A bracketed number with no "S" is removed when a
    /// passage holds the same bracket or it is larger than the number of sources; the sentence's words stay, and the
    /// answer then gets its own labels from its passages (`CitationAttribution`). A marker no passage holds and that
    /// could be a source is left alone.
    nonisolated static func removingCopiedReferenceNumbers(_ text: String, sources: [String]) -> (text: String, removed: Int) {
        guard text.contains("["),
            let marker = try? NSRegularExpression(pattern: #"\s?\[(\d{1,4}(?:\s*[,;\u2013-]\s*\d{1,4})*)\]"#)
        else { return (text, 0) }
        func squeezed(_ value: String) -> String { value.filter { !$0.isWhitespace } }
        let held = sources.map(squeezed)
        var result = text as NSString
        var removed = 0
        for match in marker.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let inner = result.substring(with: match.range(at: 1))
            let numbers = inner.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            let bracket = "[" + squeezed(inner) + "]"
            let copied = held.contains { $0.contains(bracket) }
            let beyondSources = numbers.contains { $0 > sources.count }
            guard copied || beyondSources else {
                // The model's own shorthand for a source ("[2]" for "[S2]", "[2, 4]"): written out as the app's label,
                // so Fact Check and the chat read it as the citation it is.
                let labels = numbers.map { "S\($0)" }.joined(separator: ", ")
                let lead = result.substring(with: match.range).hasPrefix("[") ? "" : " "
                result = result.replacingCharacters(in: match.range, with: "\(lead)[\(labels)]") as NSString
                continue
            }
            result = result.replacingCharacters(in: match.range, with: "") as NSString
            removed += 1
        }
        return (result as String, removed)
    }

    private nonisolated static let promptSectionTitles: Set<String> = [
        "recent conversation", "conversation context", "previous conversation", "previous discussion summary",
        "earlier turns", "current question",
    ]

    /// Takes out of an answer what it echoed from its prompt (5.8, 2026-11-13): a section under one of the prompt's
    /// own titles ("Recent Conversation"), with its text up to the next heading, and a heading that only repeats the
    /// question. By rule, after generation, so an answer never shows them whatever the model does with its prompt.
    nonisolated static func removingEchoedPromptSections(_ text: String, question: String) -> (text: String, removed: Int) {
        func key(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
                .split(separator: " ").joined(separator: " ")
        }
        func headingTitle(_ line: String) -> String? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marks = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                return String(trimmed[marks.upperBound...])
            }
            if trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), trimmed.count > 4, !trimmed.dropFirst(2).dropLast(2).contains("**") {
                return String(trimmed.dropFirst(2).dropLast(2))
            }
            return nil
        }
        let asked = key(question)
        var kept: [String] = []
        var skipping = false
        var removed = 0
        for line in text.components(separatedBy: "\n") {
            if let title = headingTitle(line) {
                let titleKey = key(title)
                if promptSectionTitles.contains(titleKey) {
                    skipping = true
                    removed += 1
                    continue
                }
                skipping = false
                if !asked.isEmpty, titleKey == asked {
                    removed += 1
                    continue
                }
            }
            if !skipping { kept.append(line) }
        }
        guard removed > 0 else { return (text, 0) }
        let result = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Never an empty answer: if everything sat under an echoed title, the text is left as it was.
        return result.isEmpty ? (text, 0) : (result, removed)
    }

    /// Whether a question asks which document holds something ("Which document mentions ...?", "What file discusses
    /// ...?", "Find the source about ...", "In which paper ...").
    nonisolated static func asksWhichDocument(_ question: String) -> Bool {
        question.range(
            of: #"(?i)\b(which|what)\s+(document|file|source|paper|pdf|report|note|fixture|book|article)s?\b|\bfind\s+the\b.{0,60}\b(document|file|source|paper|note|report|article)\b|\bwhere\s+(is|are|does|do|can)\b.{0,80}\b(mentioned|discussed|described|covered|explained)\b"#,
            options: .regularExpression) != nil
    }

    /// Names the file in an answer to a which-document question (5.8, 2026-11-14). Asked "Which document mentions the
    /// ALPHA-17 review control?", every mode answered "The document that mentions it is [S1], which ...": the label can
    /// be tapped, but the answer never says the document's name, the one thing asked for (5 of 20 cases of the answer
    /// test failed on it in 5.7 and 5.8). When the question asks which document and the answer names none of its
    /// sources' files, the file of the first source it cites is written after that citation: "[S1] (lease.pdf)".
    /// `sourceNames` are the answer's sources in label order. An answer with no citation, or one that already names the
    /// cited file, is left as it is.
    ///
    /// Since 5.9 only the cited source's name counts as already named (2026-11-23). The guard looked for any source's
    /// file, and Deep Think's long answers always mention the distractor files, so all 26 of its failures on the three
    /// "which document" questions of the answer test named other files and never the cited one
    /// (`Docs/ai/plans/consistent-answers.md`, item 4).
    nonisolated static func namingTheCitedDocument(_ text: String, question: String, sourceNames: [String]) -> String {
        guard asksWhichDocument(question), !sourceNames.isEmpty,
            let marker = try? NSRegularExpression(pattern: #"\[S(\d+)(?:\s*[,;]\s*S?\d+)*\]"#),
            let first = marker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let labelRange = Range(first.range(at: 1), in: text), let label = Int(text[labelRange]),
            label >= 1, label <= sourceNames.count, let whole = Range(first.range, in: text)
        else { return text }
        let cited = sourceNames[label - 1]
        let lower = text.lowercased()
        let stem = (cited as NSString).deletingPathExtension.lowercased()
        let alreadyNamed =
            !stem.isEmpty
            && (lower.contains(cited.lowercased()) || lower.contains(stem)
                || lower.contains(stem.replacingOccurrences(of: "_", with: " ")))
        guard !alreadyNamed else { return text }
        var result = text
        result.insert(contentsOf: " (\(sourceNames[label - 1]))", at: whole.upperBound)
        return result
    }
}

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
}

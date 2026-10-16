//
//  DayOrdinals.swift
//  OpenIntelligence
//

import Foundation

/// Reads a day written as an ordinal beside a month name as the plain number, in the text a question searches with
/// (5.7): "September 30th" becomes "September 30", "the 1st of May" becomes "the 1 of May".
///
/// On 2026-10-15 "What happened on September 30th" missed the owner's notes, which head that day "September 30".
/// To the keyword index "30th" is one word that no passage contained, and the reranker put another day's passage
/// first; asked as "September 30", the same question's top passage was that day's. Only a number beside a month
/// name changes, so "21st century" and "5th generation" stay as they are. Both search entry points apply it:
/// `RAGService.queryInternal` for the question and `executeFullRetrievalPipeline` for Deep Think's and Maximum's
/// own searches.
nonisolated enum DayOrdinals {
    private static let months =
        "January|February|March|April|May|June|July|August|September|October|November|December"
        + "|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec"

    /// "September 30th", "Sept. 30th", "September the 30th".
    nonisolated private static let monthThenDay: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b("# + months + #")(\.?\s+(?:the\s+)?)(\d{1,2})(?:st|nd|rd|th)\b"#,
            options: .caseInsensitive
        )
    }()

    /// "30th September", "30th of September".
    nonisolated private static let dayThenMonth: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b(\d{1,2})(?:st|nd|rd|th)(\s+(?:of\s+)?(?:"# + months + #")\b)"#,
            options: .caseInsensitive
        )
    }()

    /// The text with every day ordinal beside a month name read as its number; anything else unchanged.
    static func cardinal(_ text: String) -> String {
        guard text.rangeOfCharacter(from: .decimalDigits) != nil else { return text }
        var result = text
        if let monthThenDay {
            result = monthThenDay.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1$2$3")
        }
        if let dayThenMonth {
            result = dayThenMonth.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1$2")
        }
        return result
    }
}

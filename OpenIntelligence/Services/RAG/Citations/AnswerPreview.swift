//
//  AnswerPreview.swift
//  OpenIntelligence
//

import Foundation

/// An answer's opening as plain text, for places that show one line of it: the widget (`WidgetSnapshot.preview`)
/// and an answer item's title in Shortcuts (`OIAnswerEntity`, 5.7). Moved here from `WidgetSnapshot` on
/// 2026-10-20 so the engine target, which the answer item is compiled into, has it too; a Shortcuts result showed
/// "### Pet Deposit Amount - **$300.00** [S1]" as the item's title.
nonisolated enum AnswerPreview {
    /// Citation labels, Markdown marks and list bullets taken out, spaces folded, and cut on a word at `limit`
    /// characters.
    static func plain(_ text: String, limit: Int = 160) -> String {
        var plain = text.replacingOccurrences(
            of: #"\[(?:S?\d+(?:\s*,\s*S?\d+)*)\]"#, with: "", options: .regularExpression)
        plain = plain.replacingOccurrences(of: #"(^|\s)#{1,6}\s"#, with: "$1", options: .regularExpression)
        // A list item's bullet or number at the start of a line ("- ", "• ", "2. "), which reads as stray punctuation
        // once the lines are joined.
        plain = plain.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:[-•◦▪+*]|\d{1,3}[.)])[ \t]+"#, with: "", options: .regularExpression)
        plain = plain.replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
        plain = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A label taken out before punctuation leaves a space there.
        plain = plain.replacingOccurrences(of: #" +([.,;:!?])"#, with: "$1", options: .regularExpression)
        guard plain.count > limit else { return plain }
        let cut = plain.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}

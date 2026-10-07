//
//  StreamingMarkdown.swift
//  OpenIntelligence
//

import Foundation

/// Hides markdown markers in an answer that is still arriving.
///
/// The streaming bubble draws plain `Text` on purpose: it is handed the whole accumulated answer on
/// every pump tick, and parsing markdown that often is work thrown away a few milliseconds later
/// (`MessageListV2`, `StreamingBubbleV2`). The cost of that choice was that "### Gym Membership
/// Cancellation" and "**60 to 65 minutes**" showed their markers until the answer finished and
/// rendered. This is one pass over the characters with no parsing: header marks, `**` and backticks
/// are dropped, and the words stay. The finished answer still goes through `MarkdownText`.
nonisolated enum StreamingMarkdown {
    static func withoutMarkers(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)

        var atLineStart = true
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if atLineStart, character == "#" {
                // "#" to "######" then a space is a header mark. At the very end of the text it is
                // a header mark that has not finished arriving, so it waits.
                var end = index
                var count = 0
                while end < text.endIndex, text[end] == "#", count < 6 {
                    count += 1
                    end = text.index(after: end)
                }
                if end == text.endIndex {
                    break
                }
                if text[end] == " " {
                    index = text.index(after: end)
                    atLineStart = false
                    continue
                }
            }

            if atLineStart, character == "*" {
                // "* item" is a bullet, not emphasis.
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == " " {
                    output.append("•")
                    index = next
                    atLineStart = false
                    continue
                }
            }

            if character == "*" {
                let next = text.index(after: index)
                if next == text.endIndex {
                    // Possibly the first half of "**". Hold it back until the next token says.
                    break
                }
                if text[next] == "*" {
                    index = text.index(after: next)
                    atLineStart = false
                    continue
                }
            }

            if character == "`" {
                index = text.index(after: index)
                atLineStart = false
                continue
            }

            output.append(character)
            atLineStart = character == "\n"
            index = text.index(after: index)
        }
        return output
    }
}

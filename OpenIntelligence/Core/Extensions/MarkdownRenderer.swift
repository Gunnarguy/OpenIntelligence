//
//  MarkdownRenderer.swift
//  OpenIntelligence
//
//  Block-level markdown renderer with full formatting support
//  Renders headers, lists, code fences, block quotes, and inline formatting
//  Platform-safe (iOS + macOS) pasteboard and styling
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Block-Level Markdown Parser

/// Represents a parsed markdown block
private enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case table(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
    case bulletList(items: [String])
    case numberedList(items: [(number: Int, text: String)])
    case codeFence(language: String?, code: String)
    case blockQuote(text: String)
    case horizontalRule
    case empty

    var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level)_\(text.prefix(40))"
        case .paragraph(let text): return "p_\(text.prefix(40))"
        case .table(let header, _, _): return "table_\(header.joined(separator: "|").prefix(40))"
        case .bulletList(let items): return "ul_\(items.first?.prefix(30) ?? "")"
        case .numberedList(let items): return "ol_\(items.first?.text.prefix(30) ?? "")"
        case .codeFence(let lang, let code): return "code_\(lang ?? "")_\(code.prefix(20))"
        case .blockQuote(let text): return "bq_\(text.prefix(40))"
        case .horizontalRule: return "hr_\(UUID().uuidString.prefix(8))"
        case .empty: return "empty_\(UUID().uuidString.prefix(8))"
        }
    }
}

private enum MarkdownTableAlignment {
    case leading
    case center
    case trailing
}

#if DEBUG
/// Test seam: the parser type is file-private, so hosted unit tests reach
/// horizontal-rule detection through this wrapper. Compiled out of Release.
enum MarkdownParserTesting {
    static func isHorizontalRule(_ line: String) -> Bool {
        MarkdownParser.isHorizontalRule(line)
    }

    /// The heading text a list item's content would become, or nil when it stays a bullet. Ignores the
    /// item after it, which decides only for a label with no colon (see `blockSummary`).
    static func labelHeadingText(_ item: String) -> String? {
        MarkdownParser.labelBullet(item)?.text
    }

    /// One line per parsed block: `h3: text`, `ul: a | b`, `ol: 1. a | 2. b`, `p: text`, `table: a | b`,
    /// `code: text`, `quote: text`, `hr`.
    static func blockSummary(_ text: String, promotesLabelBullets: Bool) -> [String] {
        MarkdownParser.parse(text, promotesLabelBullets: promotesLabelBullets).compactMap { block in
            switch block {
            case .heading(let level, let text): return "h\(level): \(text)"
            case .paragraph(let text): return "p: \(text)"
            case .table(let header, _, _): return "table: \(header.joined(separator: " | "))"
            case .bulletList(let items): return "ul: \(items.joined(separator: " | "))"
            case .numberedList(let items):
                return "ol: \(items.map { "\($0.number). \($0.text)" }.joined(separator: " | "))"
            case .codeFence(_, let code): return "code: \(code)"
            case .blockQuote(let text): return "quote: \(text)"
            case .horizontalRule: return "hr"
            case .empty: return nil
            }
        }
    }
}
#endif

/// Parses raw markdown text into an array of blocks
private struct MarkdownParser {

    /// Pre-process text to split inline markdown blocks onto separate lines.
    /// LLMs (especially small on-device models) sometimes emit markdown syntax
    /// all on one line, e.g. "### Title - **bullet**: text. - **bullet**: text."
    /// This normalizer inserts newlines so the block parser can handle them.
    private static func normalizeInlineMarkdown(_ text: String) -> String {
        var result = text

        // Insert newline before markdown headers that appear mid-line
        // Match: non-newline char followed by `#{1,6} ` (header)
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(#{1,6} )"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before bold bullet items (` - **text**`) anywhere mid-line.
        // This is safe — a dash immediately followed by bold is always a list item.
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(- \*\*)"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before plain bullet items after sentence-ending punctuation.
        // Only after punctuation to avoid breaking em-dashes in prose.
        result = result.replacingOccurrences(
            of: #"(?<=[.!?:]) +(- [A-Z])"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before numbered list items that appear mid-line
        // Match: text followed by ` 1. ` or ` 2) ` etc.
        result = result.replacingOccurrences(
            of: #"(?<=[.!?:]) +(\d+[.)]\s)"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before numbered items with bold (` 1. **text**`)
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(\d+[.)]\s+\*\*)"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before block quotes that appear mid-line
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(> )"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before code fences (``` or ~~~) that appear mid-line
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(```)"#,
            with: "\n$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(~~~)"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Split adjacent table rows that the model emitted on one line:
        // `| a | b | |---|---| | c | d |` -> each row on its own line.
        result = result.replacingOccurrences(
            of: #"(\|) +(\|)"#,
            with: "$1\n$2",
            options: .regularExpression
        )

        // Also split when the next row starts with a compact separator row or compact data row.
        result = result.replacingOccurrences(
            of: #"(?<=\|) +(\|[:\-][^\n]*\|)"#,
            with: "\n$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<=\|) +(\|\s*[^\n|][^\n]*\|)"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before table rows that appear mid-line
        // Matches: text followed by ` | ` then word chars (table header/data row)
        // or separator rows like `|---|---|`
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(\|[- :]+\|)"#,
            with: "\n$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(\| \S)"#,
            with: "\n$1",
            options: .regularExpression
        )

        // Insert newline before horizontal rules (---, ***, ___) mid-line
        result = result.replacingOccurrences(
            of: #"(?<=\S) +(---+|___+|\*\*\*+)\s*(?=$|\s)"#,
            with: "\n$1",
            options: .regularExpression
        )

        return result
    }

    /// `promotesLabelBullets` (answers only, 5.8): a list item that is only a bold label, such as
    /// `- **What stays on the device:**`, becomes a `###` heading, so the bullets under it read as its
    /// section. See `labelBullet(_:)` and `listBlocks(_:promotesLabelBullets:)`.
    /// Each text is parsed once (5.8, 2026-11-19). `MarkdownText.body` parsed its whole text on every redraw, and a chat
    /// redraws every answer while one is written (the elapsed clock ticks 5 times a second); on the owner's iPhone the
    /// main thread spent over 10 s in `MarkdownParser.parse` / `isNumberedLine` as the app changed scene state, and iOS
    /// killed it (0x8BADF00D, scene-update watchdog, 14:48:51), with a chat holding an answer of hundreds of lines.
    private final class ParsedBlocks {
        let blocks: [MarkdownBlock]
        init(_ blocks: [MarkdownBlock]) { self.blocks = blocks }
    }
    private static let parseCache: NSCache<NSString, ParsedBlocks> = {
        let cache = NSCache<NSString, ParsedBlocks>()
        cache.countLimit = 400
        cache.totalCostLimit = 8_000_000
        return cache
    }()

    static func parse(_ text: String, promotesLabelBullets: Bool = false) -> [MarkdownBlock] {
        let key = ((promotesLabelBullets ? "1|" : "0|") + text) as NSString
        if let hit = parseCache.object(forKey: key) { return hit.blocks }
        let blocks = parseUncached(text, promotesLabelBullets: promotesLabelBullets)
        parseCache.setObject(ParsedBlocks(blocks), forKey: key, cost: text.utf16.count)
        return blocks
    }

    private static func parseUncached(_ text: String, promotesLabelBullets: Bool) -> [MarkdownBlock] {
        let normalized = normalizeInlineMarkdown(text)
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Code fence (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fenceChar = trimmed.hasPrefix("```") ? "```" : "~~~"
                let language = String(trimmed.dropFirst(fenceChar.count)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fenceChar) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeFence(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Horizontal rule (---, ***, ___)
            if trimmed.count >= 3 &&
                (trimmed.allSatisfy({ $0 == "-" || $0 == " " }) && trimmed.filter({ $0 == "-" }).count >= 3 ||
                 trimmed.allSatisfy({ $0 == "*" || $0 == " " }) && trimmed.filter({ $0 == "*" }).count >= 3 ||
                 trimmed.allSatisfy({ $0 == "_" || $0 == " " }) && trimmed.filter({ $0 == "_" }).count >= 3) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Heading (# through ######)
            if let match = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let hashes = trimmed[trimmed.startIndex..<match.upperBound].filter { $0 == "#" }.count
                let headingText = String(trimmed[match.upperBound...])
                blocks.append(.heading(level: hashes, text: headingText))
                i += 1
                continue
            }

            // Block quote (> text)
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                    } else if ql == ">" {
                        quoteLines.append("")
                    } else if ql.isEmpty && !quoteLines.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.blockQuote(text: quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }

            // Markdown table
            if i + 1 < lines.count,
               isTableRow(trimmed),
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let header = parseTableCells(trimmed)
                let alignments = parseTableAlignments(lines[i + 1].trimmingCharacters(in: .whitespaces), expectedColumns: header.count)
                var rows: [[String]] = []
                i += 2

                while i < lines.count {
                    let tableLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(tableLine) else { break }
                    let cells = parseTableCells(tableLine)
                    if cells.count == header.count {
                        rows.append(cells)
                    } else if !cells.isEmpty {
                        let padded = cells + Array(repeating: "", count: max(0, header.count - cells.count))
                        rows.append(Array(padded.prefix(header.count)))
                    }
                    i += 1
                }

                blocks.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }

            // Bullet list (- item, * item, • item)
            if isBulletLine(trimmed) {
                var items: [String] = []
                // Whether each item's line was indented under another item (two spaces or a tab).
                var nested: [Bool] = []
                while i < lines.count {
                    let bl = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBulletLine(bl) {
                        items.append(stripBullet(bl))
                        nested.append(isNestedLine(lines[i]))
                    } else if bl.isEmpty && i + 1 < lines.count && isBulletLine(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                        // Allow one blank line between list items
                        i += 1
                        continue
                    } else if !bl.isEmpty && !items.isEmpty && !bl.hasPrefix("#") && !isNumberedLine(bl) {
                        // Continuation line for multi-line list item
                        if !items.isEmpty {
                            items[items.count - 1] += " " + bl
                        }
                    } else {
                        break
                    }
                    i += 1
                }
                if !items.isEmpty {
                    blocks.append(contentsOf: listBlocks(
                        zip(items, nested).map { (text: $0, nested: $1) },
                        promotesLabelBullets: promotesLabelBullets
                    ))
                }
                continue
            }

            // Numbered list (1. item, 1) item)
            if isNumberedLine(trimmed) {
                var items: [(number: Int, text: String)] = []
                while i < lines.count {
                    let nl = lines[i].trimmingCharacters(in: .whitespaces)
                    if let (num, text) = parseNumberedLine(nl) {
                        items.append((num, text))
                    } else if nl.isEmpty && i + 1 < lines.count && isNumberedLine(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                        i += 1
                        continue
                    } else if !nl.isEmpty && !items.isEmpty && !nl.hasPrefix("#") && !isBulletLine(nl) {
                        // Continuation line
                        if !items.isEmpty {
                            items[items.count - 1].text += " " + nl
                        }
                    } else {
                        break
                    }
                    i += 1
                }
                if !items.isEmpty {
                    blocks.append(.numberedList(items: items))
                }
                continue
            }

            // Regular paragraph — collect consecutive non-empty, non-special lines
            // Use \n (not space) to preserve line breaks from LLM output.
            // InlineMarkdownText with .inlineOnlyPreservingWhitespace renders \n as line breaks.
            var paraLines: [String] = []
            while i < lines.count {
                let pl = lines[i].trimmingCharacters(in: .whitespaces)
                if pl.isEmpty || pl.hasPrefix("#") || pl.hasPrefix("```") || pl.hasPrefix("~~~") ||
                    pl.hasPrefix("> ") || isBulletLine(pl) || isNumberedLine(pl) ||
                    isHorizontalRule(pl) ||
                    (i + 1 < lines.count && isTableRow(pl) && isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces))) {
                    break
                }
                paraLines.append(pl)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    /// A bullet list, with each label item turned into a `###` heading when `promotesLabelBullets` is on.
    /// The bullets between two labels stay one list, unchanged, under the first.
    ///
    /// A label is an item at the list's own level whose whole content is one bold span (`labelBullet`).
    /// One ending in ":" (inside or after the bold) always introduces what follows. One without a colon
    /// becomes a heading only when the next item is an ordinary bullet or one nested under it, so a list
    /// whose every item is a bold name (`- **Standard**`, `- **Deep Think**`) stays a list.
    private static func listBlocks(
        _ items: [(text: String, nested: Bool)], promotesLabelBullets: Bool
    ) -> [MarkdownBlock] {
        guard promotesLabelBullets else { return [.bulletList(items: items.map(\.text))] }
        var blocks: [MarkdownBlock] = []
        var run: [String] = []
        for (index, item) in items.enumerated() {
            var heading: String?
            if !item.nested, let label = labelBullet(item.text) {
                if label.endsWithColon {
                    heading = label.text
                } else if index + 1 < items.count {
                    let next = items[index + 1]
                    if next.nested || labelBullet(next.text) == nil { heading = label.text }
                }
            }
            if let heading {
                if !run.isEmpty { blocks.append(.bulletList(items: run)) }
                run = []
                blocks.append(.heading(level: 3, text: heading))
            } else {
                run.append(item.text)
            }
        }
        if !run.isEmpty { blocks.append(.bulletList(items: run)) }
        return blocks
    }

    /// The heading a list item's content makes when the whole of it is one bold span, optionally ending
    /// in ":" inside or after the bold: `**What stays on the device:**`, `**Risks**:`, `**Risks**`. The
    /// trailing colon is dropped, as `###` headings in answers carry none, and the bold marks go, as the
    /// heading style is already the weight. A citation inside the bold stays in the text, a link once
    /// `CitationLinker` has made it one. Nil for anything else: a bold lead-in followed by text, bold
    /// inside a sentence, two bold spans, an unclosed span (a line still streaming), a bold sentence
    /// ending in ".", "!" or "?" without a colon, and anything over 120 characters as read.
    static func labelBullet(_ item: String) -> (text: String, endsWithColon: Bool)? {
        let content = item.trimmingCharacters(in: .whitespaces)
        guard content.hasPrefix("**"),
            let close = content.range(of: "**", range: content.index(content.startIndex, offsetBy: 2)..<content.endIndex)
        else { return nil }
        let inner = String(content[content.index(content.startIndex, offsetBy: 2)..<close.lowerBound])
        let after = content[close.upperBound...].trimmingCharacters(in: .whitespaces)
        guard after.isEmpty || after == ":",
            let first = inner.first, let last = inner.last,
            !first.isWhitespace, !last.isWhitespace, first != "*", last != "*",
            !inner.contains("\n")
        else { return nil }

        let endsWithColon = after == ":" || last == ":"
        var text = inner
        while text.hasSuffix(":") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if !endsWithColon, let end = text.last, ".!?".contains(end) { return nil }
        // Length as read: a citation link counts as its label, not its URL.
        let read = text.replacingOccurrences(of: #"\]\([^)]*\)"#, with: "]", options: .regularExpression)
        guard read.count <= 120 else { return nil }
        return (text, endsWithColon)
    }

    /// Indented two spaces or a tab: an item nested under the one above it.
    private static func isNestedLine(_ line: String) -> Bool {
        line.hasPrefix("\t") || line.hasPrefix("  ")
    }

    private static func isBulletLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ")
    }

    private static func stripBullet(_ line: String) -> String {
        if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        return line
    }

    /// "12. " or "3) " at the start: digits, then "." or ")", then white space. A character check, not a regular
    /// expression: it runs on every line of every answer (5.8, 2026-11-19, see `parse`).
    private static func isNumberedLine(_ line: String) -> Bool {
        var index = line.startIndex
        var sawDigit = false
        while index < line.endIndex, line[index].isASCII, line[index].isNumber {
            sawDigit = true
            index = line.index(after: index)
        }
        guard sawDigit, index < line.endIndex, line[index] == "." || line[index] == ")" else { return false }
        let next = line.index(after: index)
        return next < line.endIndex && line[next].isWhitespace
    }

    private static func parseNumberedLine(_ line: String) -> (Int, String)? {
        guard let match = line.range(of: #"^(\d+)[.)]\s+"#, options: .regularExpression) else { return nil }
        let numberStr = line[line.startIndex..<match.upperBound].filter { $0.isNumber }
        let text = String(line[match.upperBound...])
        return (Int(numberStr) ?? 1, text)
    }

    fileprivate static func isHorizontalRule(_ line: String) -> Bool {
        // Edge trimming must stay exactly CharacterSet.whitespaces; interior
        // separators may only be ASCII spaces, never tabs or other whitespace.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var marker: Character?
        var markerCount = 0
        for char in trimmed {
            if char == " " { continue }
            guard char == "-" || char == "*" || char == "_" else { return false }
            if let marker {
                guard char == marker else { return false }
            } else {
                marker = char
            }
            markerCount += 1
        }
        // At least three of a single marker kind; mixed marker kinds never form a rule.
        return markerCount >= 3
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        return parseTableCells(trimmed).count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = parseTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func parseTableCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        let body: String
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
            body = String(trimmed.dropFirst().dropLast())
        } else {
            body = trimmed
        }

        return body.splitOnUnescapedPipes()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTableAlignments(_ separatorLine: String, expectedColumns: Int) -> [MarkdownTableAlignment] {
        let cells = parseTableCells(separatorLine)
        let alignments = cells.map { cell -> MarkdownTableAlignment in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let hasLeadingColon = trimmed.hasPrefix(":")
            let hasTrailingColon = trimmed.hasSuffix(":")
            switch (hasLeadingColon, hasTrailingColon) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }

        if alignments.count >= expectedColumns {
            return Array(alignments.prefix(expectedColumns))
        }

        return alignments + Array(repeating: .leading, count: max(0, expectedColumns - alignments.count))
    }
}

// MARK: - Inline Markdown Renderer

/// Renders inline markdown (bold, italic, code, links) using AttributedString
private struct InlineMarkdownText: View {
    let text: String
    let font: Font
    let foregroundColor: Color

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(font)
                .foregroundColor(foregroundColor)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Block Renderers

/// Renders a single markdown block
private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let font: Font
    let fontSize: CGFloat
    let foregroundColor: Color

    var body: some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            InlineMarkdownText(text: text, font: font, foregroundColor: foregroundColor)

        case .table(let header, let alignments, let rows):
            tableView(header: header, alignments: alignments, rows: rows)

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .codeFence(let language, let code):
            EnhancedCodeBlock(code: code, language: language)

        case .blockQuote(let text):
            blockQuoteView(text: text)

        case .horizontalRule:
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(DSColors.accent.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let headingFont: Font = switch level {
        case 1: .system(size: fontSize + 8, weight: .bold)
        case 2: .system(size: fontSize + 5, weight: .bold)
        case 3: .system(size: fontSize + 3, weight: .semibold)
        case 4: .system(size: fontSize + 1, weight: .semibold)
        default: .system(size: fontSize, weight: .semibold)
        }

        VStack(alignment: .leading, spacing: 4) {
            InlineMarkdownText(text: text, font: headingFont, foregroundColor: foregroundColor)
            if level <= 2 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [DSColors.accent.opacity(0.4), DSColors.accent.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: level == 1 ? 2 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            }
        }
        .padding(.top, level <= 2 ? 8 : 4)
        .padding(.bottom, level <= 2 ? 2 : 0)
    }

    @ViewBuilder
    private func bulletListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(DSColors.accent.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .offset(y: 1)
                    InlineMarkdownText(text: item, font: font, foregroundColor: foregroundColor)
                        // Its full height, always (5.8): with a heading above the list and citation links in the
                        // item, SwiftUI gave some items one line and cut them off with "…" (measured with `###`
                        // headings and with label headings, in ImageRenderer and in a UIKit window, iOS 27.0).
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 6)
    }

    @ViewBuilder
    private func numberedListView(items: [(number: Int, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(item.number)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(DSColors.accent.opacity(0.7))
                        )
                    InlineMarkdownText(text: item.text, font: font, foregroundColor: foregroundColor)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func blockQuoteView(text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DSColors.accent.opacity(0.6))
                .frame(width: 3)

            InlineMarkdownText(
                text: text,
                font: .system(size: fontSize, weight: .regular).italic(),
                foregroundColor: foregroundColor.opacity(0.8)
            )
            .padding(.leading, 12)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DSColors.accent.opacity(0.04))
        )
    }

    @ViewBuilder
    private func tableView(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(header.enumerated()), id: \.offset) { index, cell in
                        InlineMarkdownText(
                            text: cell,
                            font: .system(size: fontSize, weight: .semibold),
                            foregroundColor: foregroundColor
                        )
                        .frame(maxWidth: .infinity, alignment: swiftUIAlignment(for: alignment(for: alignments, index: index)))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
                .background(DSColors.accent.opacity(0.08))

                // Header divider
                Rectangle()
                    .fill(DSColors.accent.opacity(0.2))
                    .frame(height: 1.5)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                            InlineMarkdownText(
                                text: cell,
                                font: font,
                                foregroundColor: foregroundColor
                            )
                            .frame(maxWidth: .infinity, alignment: swiftUIAlignment(for: alignment(for: alignments, index: index)))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : DSColors.surface.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DSColors.border.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func alignment(for alignments: [MarkdownTableAlignment], index: Int) -> MarkdownTableAlignment {
        guard index < alignments.count else { return .leading }
        return alignments[index]
    }

    private func swiftUIAlignment(for alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

// MARK: - Public API (Drop-in Replacement)

public struct MarkdownText: View {
    public let text: String
    public let font: Font
    public let foregroundColor: Color
    private let fontSize: CGFloat
    /// Set by `init(_:scaledSize:foregroundColor:)`: the text and its headings are drawn at this size at the default
    /// text size and scale with Dynamic Type on iPhone and iPad (5.7).
    private let scaledSize: CGFloat?
    /// 1 at the default text size; how much Dynamic Type scales body text. Always 1 on the Mac.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    /// Set by `labelBulletsAsHeadings(_:)`: answers only, never a question the user typed (5.8).
    private var promotesLabelBullets = false

    public init(_ text: String, font: Font = .body, foregroundColor: Color = .primary) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        // Extract size from common font patterns, default 15
        self.fontSize = 15
        self.scaledSize = nil
    }

    /// The answer's text (5.7): `scaledSize` points at the default text size, scaled with Dynamic Type on iPhone and
    /// iPad and fixed on the Mac. A fixed `.system(size:)` here is what Apple's audit read as "Dynamic Type font sizes
    /// are unsupported" on every answer.
    public init(_ text: String, scaledSize: CGFloat, foregroundColor: Color = .primary) {
        self.text = text
        self.font = .system(size: scaledSize)
        self.foregroundColor = foregroundColor
        self.fontSize = scaledSize
        self.scaledSize = scaledSize
    }

    /// Initializer with explicit font size for block-level heading scaling
    public init(_ text: String, font: Font = .body, fontSize: CGFloat = 15, foregroundColor: Color = .primary) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
        self.scaledSize = nil
    }

    /// A list item that is only a bold label (`- **What stays on the device:**`) draws as a `###` heading,
    /// with the bullets after it as its section (5.8). For the model's answers: the parse is the view's
    /// alone, so Copy, Share and export still read the answer's own text.
    public func labelBulletsAsHeadings(_ enabled: Bool = true) -> MarkdownText {
        var copy = self
        copy.promotesLabelBullets = enabled
        return copy
    }

    public var body: some View {
        let blocks = MarkdownParser.parse(text, promotesLabelBullets: promotesLabelBullets)
        let size = scaledSize.map { $0 * textScale }
        let bodyFont = size.map { Font.system(size: $0) } ?? font
        let headingBase = size ?? fontSize

        // Fast path: if it's just one paragraph, render inline-only (no VStack overhead)
        if blocks.count == 1, case .paragraph = blocks[0] {
            InlineMarkdownText(text: text, font: bodyFont, foregroundColor: foregroundColor)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(
                        block: block,
                        font: bodyFont,
                        fontSize: headingBase,
                        foregroundColor: foregroundColor
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            MarkdownText("""
            ## Getting Started

            This is a **bold** and _italic_ paragraph with `inline code`.

            ### Features

            1. **Block-level rendering** — Headers, lists, code fences, block quotes
            2. **Inline formatting** — Bold, italic, code, links, strikethrough
            3. **Code blocks** — Syntax-highlighted with copy button

            - First bullet point with **bold text**
            - Second bullet with `code`
            - Third bullet

            > This is a block quote that shows important information
            > from the document source.

            ```swift
            struct Example: View {
                var body: some View {
                    Text("Hello, World!")
                }
            }
            ```

            ---

            That's a horizontal rule above.
            """)
        }
        .padding()
    }
}

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

    static func parse(_ text: String) -> [MarkdownBlock] {
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
                while i < lines.count {
                    let bl = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBulletLine(bl) {
                        items.append(stripBullet(bl))
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
                    blocks.append(.bulletList(items: items))
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

    private static func isBulletLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ")
    }

    private static func stripBullet(_ line: String) -> String {
        if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        return line
    }

    private static func isNumberedLine(_ line: String) -> Bool {
        line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil
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

        return body
            .components(separatedBy: "|")
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
                    .clipShape(RoundedRectangle(cornerRadius: 1))
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
            RoundedRectangle(cornerRadius: 2)
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

    public init(_ text: String, font: Font = .body, foregroundColor: Color = .primary) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        // Extract size from common font patterns, default 15
        self.fontSize = 15
    }

    /// Initializer with explicit font size for block-level heading scaling
    public init(_ text: String, font: Font = .body, fontSize: CGFloat = 15, foregroundColor: Color = .primary) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
    }

    public var body: some View {
        let blocks = MarkdownParser.parse(text)

        // Fast path: if it's just one paragraph, render inline-only (no VStack overhead)
        if blocks.count == 1, case .paragraph = blocks[0] {
            InlineMarkdownText(text: text, font: font, foregroundColor: foregroundColor)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(
                        block: block,
                        font: font,
                        fontSize: fontSize,
                        foregroundColor: foregroundColor
                    )
                }
            }
        }
    }
}

/// Simple code block view (monospace, copy button)
public struct CodeBlockView: View {
    public let code: String
    @State private var copied = false

    public init(code: String) {
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = code
                    DSHaptics.copy()
                    #elseif canImport(AppKit)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                    #endif
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(DSColors.surface)
        .cornerRadius(8)
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

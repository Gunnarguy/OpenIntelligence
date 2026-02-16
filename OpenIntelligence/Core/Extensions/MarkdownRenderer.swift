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
        case .bulletList(let items): return "ul_\(items.first?.prefix(30) ?? "")"
        case .numberedList(let items): return "ol_\(items.first?.text.prefix(30) ?? "")"
        case .codeFence(let lang, let code): return "code_\(lang ?? "")_\(code.prefix(20))"
        case .blockQuote(let text): return "bq_\(text.prefix(40))"
        case .horizontalRule: return "hr_\(UUID().uuidString.prefix(8))"
        case .empty: return "empty_\(UUID().uuidString.prefix(8))"
        }
    }
}

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
                    isHorizontalRule(pl) {
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
        line.hasPrefix("- ") || line.hasPrefix("• ") ||
        (line.hasPrefix("* ") && !line.dropFirst(2).contains("*")) // Avoid matching *italic*
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

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return (trimmed.allSatisfy({ $0 == "-" || $0 == " " }) && trimmed.filter({ $0 == "-" }).count >= 3) ||
               (trimmed.allSatisfy({ $0 == "*" || $0 == " " }) && trimmed.filter({ $0 == "*" }).count >= 3) ||
               (trimmed.allSatisfy({ $0 == "_" || $0 == " " }) && trimmed.filter({ $0 == "_" }).count >= 3)
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

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .codeFence(let language, let code):
            EnhancedCodeBlock(code: code, language: language)

        case .blockQuote(let text):
            blockQuoteView(text: text)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

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

        VStack(alignment: .leading, spacing: 2) {
            InlineMarkdownText(text: text, font: headingFont, foregroundColor: foregroundColor)
            if level <= 2 {
                Divider()
            }
        }
        .padding(.top, level <= 2 ? 6 : 4)
    }

    @ViewBuilder
    private func bulletListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(foregroundColor.opacity(0.6))
                        .frame(width: 12, alignment: .center)
                    InlineMarkdownText(text: item, font: font, foregroundColor: foregroundColor)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func numberedListView(items: [(number: Int, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.number).")
                        .font(.system(size: fontSize - 1, weight: .medium, design: .rounded))
                        .foregroundColor(foregroundColor.opacity(0.6))
                        .frame(minWidth: 20, alignment: .trailing)
                    InlineMarkdownText(text: item.text, font: font, foregroundColor: foregroundColor)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func blockQuoteView(text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(DSColors.accent.opacity(0.5))
                .frame(width: 3)

            InlineMarkdownText(
                text: text,
                font: .system(size: fontSize, weight: .regular).italic(),
                foregroundColor: foregroundColor.opacity(0.8)
            )
            .padding(.leading, 10)
        }
        .padding(.vertical, 2)
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
            VStack(alignment: .leading, spacing: 8) {
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

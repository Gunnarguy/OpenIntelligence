//
//  EnhancedCodeBlock.swift
//  OpenIntelligence
//
//  Code block with syntax highlighting, line numbers, and copy functionality
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EnhancedCodeBlock: View {
    let code: String
    let language: String?

    @State private var copied = false

    private var displayLanguage: String {
        language?.lowercased() ?? "code"
    }

    private var languageInfo: (icon: String, color: Color) {
        switch displayLanguage {
        case "swift":
            return ("swift", .orange)
        case "python", "py":
            return ("text.word.spacing", .blue)
        case "javascript", "js":
            return ("curlybraces", .yellow)
        case "typescript", "ts":
            return ("curlybraces.square", .blue)
        case "json":
            return ("doc.text", .green)
        case "html":
            return ("chevron.left.forwardslash.chevron.right", .red)
        case "css":
            return ("paintbrush", .purple)
        case "bash", "sh", "shell", "zsh":
            return ("terminal", .green)
        case "sql":
            return ("cylinder", .cyan)
        case "markdown", "md":
            return ("text.justify", .gray)
        default:
            return ("doc.text", .secondary)
        }
    }

    private var lines: [String] {
        code.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: languageInfo.icon)
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(languageInfo.color)

                Text(displayLanguage.uppercased())
                    .scaledFont(size: 10, weight: .bold, design: .monospaced)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                // Copy button
                Button {
                    copyCode()
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .scaledFont(size: 11, weight: .medium)
                        Text(copied ? "Copied" : "Copy")
                            .scaledFont(size: 10, weight: .medium)
                    }
                    .foregroundStyle(copied ? .green : DSColors.accent)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(copied ? Color.green.opacity(0.15) : DSColors.accent.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(DSColors.surfaceElevated)

            Divider()

            // Code content with line numbers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text("\(index + 1)")
                                .scaledFont(size: 12, weight: .regular, design: .monospaced)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(height: 18)
                        }
                    }
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColors.surfaceElevated.opacity(0.5))

                    // Separator
                    Rectangle()
                        .fill(DSColors.border.opacity(0.3))
                        .frame(width: 1)

                    // Code content
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            SyntaxHighlightedLine(
                                text: lines[index],
                                language: displayLanguage
                            )
                            .frame(height: 18, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                }
            }
            .background(DSColors.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .stroke(DSColors.border, lineWidth: 0.5)
        )
    }

    private func copyCode() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif

        withAnimation(DSAnimations.snappySpring) {
            copied = true
        }
        DSHaptics.copy()

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(DSAnimations.fastEase) {
                copied = false
            }
        }
    }
}

// MARK: - Syntax Highlighted Line

private struct SyntaxHighlightedLine: View {
    let text: String
    let language: String

    var body: some View {
        // Simple syntax highlighting using AttributedString
        Text(highlightedText)
            .scaledFont(size: 12, weight: .regular, design: .monospaced)
    }

    private var highlightedText: AttributedString {
        var result = AttributedString(text)

        // Apply basic highlighting based on language
        applyHighlighting(to: &result)

        return result
    }

    private func applyHighlighting(to text: inout AttributedString) {
        let plainText = String(text.characters)

        // Keywords by language
        let keywords: [String]
        let types: [String]

        switch language {
        case "swift":
            keywords = ["func", "var", "let", "if", "else", "for", "while", "return", "guard", "import", "struct", "class", "enum", "protocol", "extension", "private", "public", "internal", "fileprivate", "static", "override", "mutating", "async", "await", "throws", "try", "catch", "do", "switch", "case", "default", "break", "continue", "self", "Self", "nil", "true", "false", "init", "deinit", "where", "in", "as", "is", "@State", "@Binding", "@Published", "@MainActor", "@Environment"]
            types = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "View", "some", "Any", "AnyObject"]
        case "python", "py":
            keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "pass", "break", "continue", "and", "or", "not", "in", "is", "None", "True", "False", "async", "await", "yield", "raise", "assert", "global", "nonlocal", "del"]
            types = ["int", "str", "float", "bool", "list", "dict", "set", "tuple", "type", "object"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["function", "const", "let", "var", "if", "else", "for", "while", "return", "import", "export", "from", "class", "extends", "new", "this", "super", "static", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "default", "switch", "case", "break", "continue", "null", "undefined", "true", "false", "void", "delete"]
            types = ["number", "string", "boolean", "object", "Array", "Object", "Function", "Promise", "any", "never", "unknown"]
        default:
            keywords = []
            types = []
        }

        // Highlight keywords
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? Regex(pattern) {
                for match in plainText.matches(of: regex) {
                    if let range = Range(match.range, in: text) {
                        text[range].foregroundColor = .purple
                        text[range].font = .system(.caption, design: .monospaced).weight(.semibold)
                    }
                }
            }
        }

        // Highlight types
        for type in types {
            let pattern = "\\b\(type)\\b"
            if let regex = try? Regex(pattern) {
                for match in plainText.matches(of: regex) {
                    if let range = Range(match.range, in: text) {
                        text[range].foregroundColor = .cyan
                    }
                }
            }
        }

        // Highlight strings (simple approach)
        let stringPattern = #"\"[^\"]*\"|'[^']*'"#
        if let regex = try? Regex(stringPattern) {
            for match in plainText.matches(of: regex) {
                if let range = Range(match.range, in: text) {
                    text[range].foregroundColor = .red
                }
            }
        }

        // Highlight comments
        let commentPatterns = ["//.*$", "#.*$"]
        for pattern in commentPatterns {
            if let regex = try? Regex(pattern) {
                for match in plainText.matches(of: regex) {
                    if let range = Range(match.range, in: text) {
                        text[range].foregroundColor = .gray
                        text[range].font = .system(.caption, design: .monospaced).italic()
                    }
                }
            }
        }

        // Highlight numbers
        let numberPattern = #"\b\d+\.?\d*\b"#
        if let regex = try? Regex(numberPattern) {
            for match in plainText.matches(of: regex) {
                if let range = Range(match.range, in: text) {
                    text[range].foregroundColor = .orange
                }
            }
        }
    }
}

// MARK: - Compact Code Block

/// Minimal code block for inline use
struct CompactCodeBlock: View {
    let code: String
    let language: String?

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(code)
                .scaledFont(size: 12, design: .monospaced)
                .foregroundStyle(DSColors.primaryText)
                .padding(DSSpacing.sm)

            Spacer(minLength: 0)

            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = code
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                #endif
                withAnimation(DSAnimations.fastEase) { copied = true }
                DSHaptics.selection()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(DSAnimations.fastEase) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .scaledFont(size: 11)
                    .foregroundStyle(copied ? .green : DSColors.secondaryText)
                    .padding(DSSpacing.sm)
            }
            .buttonStyle(.plain)
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

#Preview("Enhanced Code Block") {
    VStack(spacing: 16) {
        EnhancedCodeBlock(
            code: """
            struct ContentView: View {
                @State private var count = 0

                var body: some View {
                    VStack {
                        Text("Count: \\(count)")
                        Button("Increment") {
                            count += 1
                        }
                    }
                }
            }
            """,
            language: "swift"
        )

        EnhancedCodeBlock(
            code: """
            def hello_world():
                print("Hello, World!")
                return 42
            """,
            language: "python"
        )
    }
    .padding()
    .background(DSColors.background)
}

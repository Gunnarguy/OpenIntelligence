//
//  MarkdownRenderer.swift
//  OpenIntelligence
//
//  Lightweight markdown-to-text renderer with safe fallback
//  Platform-safe (iOS + macOS) pasteboard and styling
//  Created by Cline on 10/28/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct MarkdownText: View {
    public let text: String
    public let font: Font
    public let foregroundColor: Color
    
    public init(_ text: String, font: Font = .body, foregroundColor: Color = .primary) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
    }
    
    public var body: some View {
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
    VStack(alignment: .leading, spacing: 12) {
        MarkdownText("This is **bold**, _italic_, and `inline code`.")
        CodeBlockView(code: """
        // Sample Swift code
        import SwiftUI

        struct Example: View {
            var body: some View { Text("Hello") }
        }
        """)
    }
    .padding()
}

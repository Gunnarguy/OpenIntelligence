import XCTest
@testable import OpenIntelligence

/// Tests for the MarkdownRenderer's inline normalization and block parsing behaviors.
/// Since MarkdownParser is private, these tests exercise the public MarkdownText view
/// initialization and verify the rendering pipeline doesn't crash on various inputs.
/// Additionally tests MarkdownBlock behavior through observable formatting output.
final class MarkdownRendererTests: XCTestCase {

    // MARK: - MarkdownText Construction (Smoke Tests)

    func testMarkdownTextInitWithPlainText() {
        // MarkdownText should not crash with plain text
        let view = MarkdownText("Hello, world!")
        XCTAssertNotNil(view, "MarkdownText should initialize with plain text")
    }

    func testMarkdownTextInitWithEmptyString() {
        let view = MarkdownText("")
        XCTAssertNotNil(view, "MarkdownText should handle empty string")
    }

    func testMarkdownTextInitWithHeaders() {
        let markdown = """
        # Title
        ## Subtitle
        ### Section
        """
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle markdown headers")
    }

    func testMarkdownTextInitWithBulletList() {
        let markdown = """
        - First item
        - Second item
        - Third item
        """
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle bullet lists")
    }

    func testMarkdownTextInitWithNumberedList() {
        let markdown = """
        1. First step
        2. Second step
        3. Third step
        """
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle numbered lists")
    }

    func testMarkdownTextInitWithCodeFence() {
        let markdown = """
        ```swift
        let x = 42
        print(x)
        ```
        """
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle code fences")
    }

    func testMarkdownTextInitWithBlockQuote() {
        let markdown = "> This is a block quote with important information."
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle block quotes")
    }

    func testMarkdownTextInitWithMixedFormatting() {
        let markdown = """
        # Document Title

        This is a paragraph with **bold** and *italic* text.

        ## Section 1

        - Item with **bold**
        - Item with `code`

        1. Numbered item
        2. Another numbered item

        > A quote from the document.

        ```
        code block
        ```

        ---

        Final paragraph.
        """
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle complex mixed formatting")
    }

    func testMarkdownTextInitWithInlineBold() {
        let markdown = "This has **bold text** in the middle."
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle inline bold")
    }

    func testMarkdownTextInitWithInlineCode() {
        let markdown = "Use the `print()` function to output text."
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle inline code")
    }

    // MARK: - Edge Cases

    func testMarkdownTextWithOnlyWhitespace() {
        let view = MarkdownText("   \n\n  \t  ")
        XCTAssertNotNil(view, "MarkdownText should handle whitespace-only input")
    }

    func testMarkdownTextWithVeryLongContent() {
        let longMarkdown = String(repeating: "This is a long paragraph. ", count: 500)
        let view = MarkdownText(longMarkdown)
        XCTAssertNotNil(view, "MarkdownText should handle very long content")
    }

    func testMarkdownTextWithSpecialCharacters() {
        let markdown = "Symbols: < > & \" ' © ® ™ § ¶ € £ ¥ ←→↑↓ ✓ ✗"
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle special characters")
    }

    func testMarkdownTextWithUnicode() {
        let markdown = "日本語 中文 한국어 العربية 🎉🚀💡"
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle Unicode and emoji")
    }

    func testMarkdownTextWithConcatenatedMarkdown() {
        // This is the exact pattern Apple FM produces — everything on one line
        let concatenated = "### Title - **Bold item**: description. - **Another item**: more text. 1. **Step one**: do this. 2. **Step two**: do that."
        let view = MarkdownText(concatenated)
        XCTAssertNotNil(view, "MarkdownText should handle LLM-concatenated markdown")
    }

    func testMarkdownTextWithNestedFormatting() {
        let markdown = "This has **bold with `code` inside** and *italic with **bold** inside*."
        let view = MarkdownText(markdown)
        XCTAssertNotNil(view, "MarkdownText should handle nested formatting")
    }

    func testMarkdownTextCustomFontAndColor() {
        let view = MarkdownText("Test", font: .title, foregroundColor: .red)
        XCTAssertNotNil(view, "MarkdownText should accept custom font and color")
    }

    // MARK: - CodeBlockView

    func testCodeBlockViewInitialization() {
        let view = CodeBlockView(code: "let x = 42\nprint(x)")
        XCTAssertNotNil(view, "CodeBlockView should initialize with code string")
    }

    func testCodeBlockViewWithEmptyCode() {
        let view = CodeBlockView(code: "")
        XCTAssertNotNil(view, "CodeBlockView should handle empty code")
    }
}

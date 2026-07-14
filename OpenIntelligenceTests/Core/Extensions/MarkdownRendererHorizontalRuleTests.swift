import XCTest
@testable import OpenIntelligence

/// Behavior-pinning tests for MarkdownParser.isHorizontalRule (reached via the
/// MarkdownParserTesting seam). Expected values match the shipped implementation,
/// not CommonMark:
/// - edge whitespace is trimmed with CharacterSet.whitespaces (Unicode Zs, tab,
///   and Foundation's legacy U+200B membership), with no indentation cap;
/// - interior separators may only be ASCII spaces (interior tabs are rejected);
/// - a rule needs three or more of a single marker kind; mixed kinds never match.
final class MarkdownRendererHorizontalRuleTests: XCTestCase {

    private func isRule(_ line: String) -> Bool {
        MarkdownParserTesting.isHorizontalRule(line)
    }

    // MARK: - Marker counts

    func testExactlyThreeMarkers() {
        XCTAssertTrue(isRule("---"))
        XCTAssertTrue(isRule("***"))
        XCTAssertTrue(isRule("___"))
    }

    func testMoreThanThreeMarkers() {
        XCTAssertTrue(isRule("----"))
        XCTAssertTrue(isRule("----------"))
        XCTAssertTrue(isRule("*****"))
        XCTAssertTrue(isRule("_____"))
    }

    func testFewerThanThreeMarkers() {
        XCTAssertFalse(isRule(""))
        XCTAssertFalse(isRule("-"))
        XCTAssertFalse(isRule("--"))
        XCTAssertFalse(isRule("**"))
        XCTAssertFalse(isRule("__"))
        XCTAssertFalse(isRule("- -"))
    }

    // MARK: - ASCII edge whitespace

    func testLeadingAndTrailingSpaces() {
        XCTAssertTrue(isRule(" ---"))
        XCTAssertTrue(isRule("--- "))
        XCTAssertTrue(isRule("   ***   "))
        // No indentation cap: four leading spaces still match (CommonMark would not).
        XCTAssertTrue(isRule("    ___"))
    }

    func testLeadingAndTrailingTabs() {
        XCTAssertTrue(isRule("\t---"))
        XCTAssertTrue(isRule("---\t"))
        XCTAssertTrue(isRule("\t\t***\t\t"))
        XCTAssertTrue(isRule(" \t___\t "))
    }

    func testWhitespaceOnlyLines() {
        XCTAssertFalse(isRule("   "))
        XCTAssertFalse(isRule("\t\t\t"))
        XCTAssertFalse(isRule(" \t "))
    }

    // MARK: - Interior separators

    func testInteriorAsciiSpaces() {
        XCTAssertTrue(isRule("- - -"))
        XCTAssertTrue(isRule("-- -"))
        XCTAssertTrue(isRule("*  *  *"))
        XCTAssertTrue(isRule("_ _ _"))
        XCTAssertTrue(isRule("  - - -  "))
    }

    func testInteriorTabsRejected() {
        XCTAssertFalse(isRule("-\t--"))
        XCTAssertFalse(isRule("- -\t-"))
        XCTAssertFalse(isRule("*\t*\t*"))
        XCTAssertFalse(isRule("_\t__"))
    }

    func testInteriorUnicodeWhitespaceRejected() {
        XCTAssertFalse(isRule("-\u{00A0}--"))   // no-break space
        XCTAssertFalse(isRule("*\u{2003}**"))   // em space
        XCTAssertFalse(isRule("_\u{3000}__"))   // ideographic space
    }

    // MARK: - Mixed markers

    func testMixedMarkersRejected() {
        XCTAssertFalse(isRule("-*-"))
        XCTAssertFalse(isRule("--*"))
        XCTAssertFalse(isRule("-**"))
        XCTAssertFalse(isRule("***---"))
        XCTAssertFalse(isRule("_-_"))
        XCTAssertFalse(isRule("* - *"))
        XCTAssertFalse(isRule("- _ -"))
        XCTAssertFalse(isRule("-- **"))
    }

    // MARK: - Embedded text and non-marker symbols

    func testEmbeddedTextRejected() {
        XCTAssertFalse(isRule("--- text"))
        XCTAssertFalse(isRule("text ---"))
        XCTAssertFalse(isRule("a---"))
        XCTAssertFalse(isRule("---a"))
        XCTAssertFalse(isRule("-x-"))
        XCTAssertFalse(isRule("3---"))
        XCTAssertFalse(isRule("---3"))
    }

    func testNonMarkerSymbolsRejected() {
        XCTAssertFalse(isRule("==="))
        XCTAssertFalse(isRule("\u{2022}\u{2022}\u{2022}"))  // bullet
        XCTAssertFalse(isRule("abc"))
        XCTAssertFalse(isRule("\u{1F389}\u{1F389}\u{1F389}"))  // emoji
    }

    // MARK: - Unicode whitespace classification (CharacterSet.whitespaces)

    func testEdgeWhitespaceInWhitespacesSetTrimmed() {
        XCTAssertTrue(isRule("\u{00A0}---"))              // no-break space (Zs)
        XCTAssertTrue(isRule("---\u{00A0}"))
        XCTAssertTrue(isRule("\u{2003}***\u{2003}"))      // em space (Zs)
        XCTAssertTrue(isRule("\u{3000}___"))              // ideographic space (Zs)
        XCTAssertTrue(isRule("\u{2000}---\u{200A}"))      // en quad / hair space (Zs)
        XCTAssertTrue(isRule(" \t\u{00A0}---\u{2003}\t "))
        // Foundation's .whitespaces also contains ZERO WIDTH SPACE (U+200B).
        XCTAssertTrue(isRule("\u{200B}---"))
    }

    func testEdgeCharactersOutsideWhitespacesSetRejected() {
        XCTAssertFalse(isRule("\u{000B}---"))  // line tabulation (Cc)
        XCTAssertFalse(isRule("\n---"))        // newline (the parser splits lines on \n)
        XCTAssertFalse(isRule("\u{2028}---"))  // line separator (Zl)
    }

    // MARK: - Unicode marker lookalikes

    func testMarkerLookalikesRejected() {
        XCTAssertFalse(isRule("\u{2014}\u{2014}\u{2014}"))  // em dash
        XCTAssertFalse(isRule("\u{FF0D}\u{FF0D}\u{FF0D}"))  // fullwidth hyphen-minus
        XCTAssertFalse(isRule("\u{2217}\u{2217}\u{2217}"))  // asterisk operator
        // Dash + combining acute forms a single grapheme that is not "-".
        XCTAssertFalse(isRule("-\u{0301}--"))
    }
}

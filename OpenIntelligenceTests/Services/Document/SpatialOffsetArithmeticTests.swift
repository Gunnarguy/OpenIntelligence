import XCTest

@testable import OpenIntelligenceEngine

/// Pins the range arithmetic behind `extractTextWithSpatialOrdering`.
///
/// That function asks PDFKit where a word sits on the page via
/// `page.selection(for: NSRange)`. Until 2026-08-21 it built that range from a hand-maintained
/// counter, and the counter under-counted in two independent ways that compounded:
///
/// 1. `split(whereSeparator:)` omits empty subsequences, so a run of whitespace — a double space,
///    an indent, a `\r\n` — collapsed into a single gap while the cursor advanced by exactly `+ 1`.
/// 2. `String.count` counts grapheme clusters, `NSRange` addresses UTF-16 code units. Ligatures,
///    accents and anything outside the BMP drift the two apart.
///
/// Both errors under-count, so the range stayed *in bounds* and `selection(for:)` kept returning
/// bounds — for different text than the word being positioned. The word appended to the line was
/// correct while the coordinates recorded against it belonged to something else. Nothing threw, no
/// log fired, and the damage only showed up as scrambled reading order in stored chunks.
///
/// These tests do not need PDFKit: the defect is entirely in mapping a `Substring` to a UTF-16
/// range over its base, which is exactly what `NSRange(_:in:)` does and what the counter did badly.
final class SpatialOffsetArithmeticTests: XCTestCase {

    /// The production expression, isolated. Mirrors the call in `extractTextWithSpatialOrdering`.
    ///
    /// `in: base` is load-bearing and is the point of this helper: passing `in: word` would yield
    /// word-relative offsets, which is the same defect wearing a different hat.
    private func ranges(in base: String) -> [(word: String, range: NSRange)] {
        base.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { (String($0), NSRange($0.startIndex..<$0.endIndex, in: base)) }
    }

    /// What the old code computed, kept so the regression stays legible rather than folklore.
    private func legacyRanges(in base: String) -> [(word: String, range: NSRange)] {
        var cursor = 0
        var out: [(String, NSRange)] = []
        for word in base.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let text = String(word)
            out.append((text, NSRange(location: cursor, length: text.count)))
            cursor += text.count + 1  // "+1 for separator"
        }
        return out
    }

    /// The invariant the whole function rests on: the range must address the word it belongs to,
    /// measured the way `NSRange` and PDFKit actually measure — in UTF-16 over the page string.
    private func assertRangesResolveToTheirWords(
        _ base: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let ns = base as NSString
        for (word, range) in ranges(in: base) {
            XCTAssertLessThanOrEqual(
                range.location + range.length, ns.length,
                "range for \"\(word)\" runs past the end of the string", file: file, line: line
            )
            XCTAssertEqual(
                ns.substring(with: range), word,
                "range resolved to different text than the word it was built for",
                file: file, line: line
            )
        }
    }

    // MARK: - The two drift sources

    func testSingleSpacedAsciiResolvesExactly() {
        assertRangesResolveToTheirWords("The dynamics of monoamine function occurs")
    }

    /// Error source 1. Every collapsed run is one character the old cursor never accounted for.
    func testRunsOfWhitespaceDoNotDriftTheRange() {
        assertRangesResolveToTheirWords("The  dynamics   of\n\nmonoamine\t\tfunction \r\n occurs")
    }

    /// Error source 2. `ﬁ`/`ﬂ` are single Characters; the surrounding accents and the emoji are
    /// where grapheme count and UTF-16 length part company outright.
    func testLigaturesAccentsAndAstralCharactersDoNotDriftTheRange() {
        assertRangesResolveToTheirWords("in\u{FB02}uence of a\u{FB01}rmative café naïve 🧬 signalling")
    }

    /// Both sources together, which is the real-document case: a two-column journal PDF extracted
    /// by PDFKit is full of ligatures *and* irregular whitespace.
    func testCombinedDriftSourcesStillResolveExactly() {
        assertRangesResolveToTheirWords(
            "The  dynamics of monoamine\n\nfunction occurs at the sub-second\r\n"
                + "to  second timescale, under which most behavioural\tdynamics have "
                + "been studied by electrical re\u{FB01}nement café 🧬 signalling"
        )
    }

    func testEmptyAndWhitespaceOnlyStringsProduceNoRanges() {
        XCTAssertTrue(ranges(in: "").isEmpty)
        XCTAssertTrue(ranges(in: "   \n\t  ").isEmpty)
    }

    // MARK: - The regression itself

    /// Guards against a well-meaning future "simplification" back to a counter.
    ///
    /// Asserted as a property rather than against a golden number: the old arithmetic must be
    /// *unable* to satisfy the invariant the fixed code satisfies. Both inputs below are cases the
    /// old code silently got wrong in production.
    func testTheOldCounterArithmeticCannotSatisfyTheInvariant() {
        for base in [
            "The  dynamics   of\n\nmonoamine function",
            "in\u{FB02}uence of a\u{FB01}rmative café 🧬 signalling",
        ] {
            let ns = base as NSString
            let legacyMatchesEverywhere = legacyRanges(in: base).allSatisfy { word, range in
                range.location + range.length <= ns.length && ns.substring(with: range) == word
            }
            XCTAssertFalse(
                legacyMatchesEverywhere,
                "The counter arithmetic resolved every word correctly for \"\(base)\", which it "
                    + "cannot do — if this fails the helper no longer models the old code and this "
                    + "test has stopped guarding anything."
            )
            // And the shipped expression must handle the same input.
            assertRangesResolveToTheirWords(base)
        }
    }

    /// The drift is silent precisely because it stays in bounds. Pinned so the *reason* the defect
    /// went unnoticed for so long is part of the test record, not just the defect itself.
    func testTheOldDriftStayedInBoundsWhichIsWhyItNeverThrew() {
        let base = "The  dynamics   of\n\nmonoamine function occurs"
        let ns = base as NSString
        let legacy = legacyRanges(in: base)
        XCTAssertTrue(
            legacy.allSatisfy { $0.range.location + $0.range.length <= ns.length },
            "Every drifted range was still a valid range. PDFKit returned bounds for all of them, "
                + "which is why the failure surfaced as scrambled reading order rather than an error."
        )
        XCTAssertTrue(
            legacy.contains { ns.substring(with: $0.range) != $0.word },
            "…and at least one of those valid ranges addressed the wrong text."
        )
    }
}

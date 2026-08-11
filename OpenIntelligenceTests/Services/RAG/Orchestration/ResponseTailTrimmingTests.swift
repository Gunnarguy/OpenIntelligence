//
//  ResponseTailTrimmingTests.swift
//  OpenIntelligenceTests
//
//  Pins the terminal-boundary test that decides whether an answer looks finished.
//
//  Why this exists. `trimIncompleteResponseTail` exists to cut a half-written sentence off the
//  end of a generation. Its boundary test accepted `. ! ? ] ) } " '` and not `*`, so any answer
//  ending in markdown emphasis was judged incomplete and truncated back to the previous full
//  stop, taking the closing emphasis markers with it.
//
//  The reproducible victim was the abstention banner. `SourceOnlyAnswerService.swift:349` emits
//  a well-formed `*(Reason: …)*`; on the 2026-08-09 and 2026-08-11 benchmark runs, 7 of 7 saved
//  reason blocks had lost exactly the final `)*`. `CHANGELOG.md` recorded that the closing
//  marker went missing "by a route not yet identified" and hardened the benchmark's regex
//  against it, leaving the app-side defect in place. This was the route.
//
//  It reached users, not only the harness: the single call site is `finalizeResponse`, which
//  every answer path returns through.
//
//  The cases below are the real strings from `BenchmarkRuns/20260811-133233-matrix/results.json`,
//  not invented ones.
//

@testable import OpenIntelligence
import XCTest

final class ResponseTailTrimmingTests: XCTestCase {
    // MARK: - The regression this file exists for

    /// The abstention banner must survive finalization with its closing `)*` intact.
    func testAbstentionBannerKeepsItsClosingMarkers() {
        let banner = """
        ⚠️ **[Needs Verification]** This answer was drafted but could not be strictly verified against the retrieved evidence:

        Owner-4A owns Project M4, and its reporting deadline is the Q4 review gate [S1], [S2].

        *(Reason: All necessary claims are supported by the evidence.)*
        """

        XCTAssertTrue(
            RAGService.hasResponseTerminalBoundary(banner),
            "The banner ends in markdown emphasis. Judging it incomplete truncates it back to the previous full stop and drops the closing ')*', which is the defect this test pins."
        )
    }

    /// The other real instance, whose reason contains its own parentheses and commas.
    func testAbstentionBannerWithNestedParenthesesSurvives() {
        let banner = "⚠️ **[Needs Verification]** drafted:\n\nThe owner is Owner-1A [S1] [S4].\n\n*(Reason: Evidence explicitly identifies owner and deadline but does not specify deadline type (e.g., date, time) or owner name beyond identifier.)*"

        XCTAssertTrue(RAGService.hasResponseTerminalBoundary(banner))
    }

    // MARK: - Emphasis in general, which is the wider bug

    /// Any answer ending in bold or italic is complete, not truncated.
    ///
    /// This is the part that was never about the banner. An answer whose last words are emphasised
    /// shipped with unbalanced markers, so the emphasis leaked into whatever followed it in the
    /// rendered view.
    func testAnswerEndingInEmphasisIsTreatedAsComplete() {
        for finished in [
            "The service interval is **every 7,500 miles.**",
            "The limit is _120 degrees Celsius._",
            "Use the flag `CODE_SIGNING_ALLOWED=NO`.",
            "Payload capacity is 1,620 lb.",
            "Did you mean the 2024 model?",
            "See the table above [S2]",
            "The answer is \"14.3 US gal\"",
        ] {
            XCTAssertTrue(
                RAGService.hasResponseTerminalBoundary(finished),
                "Should read as finished: \(finished)"
            )
        }
    }

    /// A genuinely unfinished tail must still be caught, which is the function's actual job.
    ///
    /// If this ever passes, the fix has been over-applied and the trimmer has stopped working.
    func testGenuinelyTruncatedTailsAreStillCaught() {
        for unfinished in [
            "The reporting deadline is the Q4 review gate and",
            "Fuel capacity is 14.3 US gal, but the towing figure depends on",
            "The owner is *",
            "Torque is rated at",
        ] {
            XCTAssertFalse(
                RAGService.hasResponseTerminalBoundary(unfinished),
                "Should read as unfinished: \(unfinished)"
            )
        }
    }

    /// A string that is nothing but emphasis has no boundary to find.
    func testEmphasisOnlyStringHasNoBoundary() {
        XCTAssertFalse(RAGService.hasResponseTerminalBoundary("***"))
        XCTAssertFalse(RAGService.hasResponseTerminalBoundary(""))
        XCTAssertFalse(RAGService.hasResponseTerminalBoundary("   \n  "))
    }
}

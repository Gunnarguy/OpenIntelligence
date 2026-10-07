//
//  StreamingMarkdownTests.swift
//  OpenIntelligenceTests
//
//  While an answer streamed on 5.5 the bubble showed "### Gym Membership Cancellation" and
//  "**60 to 65 minutes** at a temperature of **3" as typed. The streaming bubble stays plain text for
//  speed; this pins the filter that keeps the markers out of it.
//

import XCTest

@testable import OpenIntelligenceEngine

final class StreamingMarkdownTests: XCTestCase {
    func testHeaderAndBoldMarkersAreDropped() {
        XCTAssertEqual(
            StreamingMarkdown.withoutMarkers("### Gym Membership Cancellation\nSend **30 days'** written notice."),
            "Gym Membership Cancellation\nSend 30 days' written notice."
        )
    }

    func testAHalfArrivedMarkerWaits() {
        // The rows' own example, cut where the stream was mid-token.
        XCTAssertEqual(
            StreamingMarkdown.withoutMarkers("**60 to 65 minutes** at a temperature of **3"),
            "60 to 65 minutes at a temperature of 3"
        )
        XCTAssertEqual(StreamingMarkdown.withoutMarkers("Bake for *"), "Bake for ")
        XCTAssertEqual(StreamingMarkdown.withoutMarkers("Done.\n##"), "Done.\n")
    }

    func testBulletsCodeAndOrdinaryCharactersSurvive() {
        XCTAssertEqual(StreamingMarkdown.withoutMarkers("* First\n- Second\n1. Third"), "• First\n- Second\n1. Third")
        XCTAssertEqual(StreamingMarkdown.withoutMarkers("Run `xcodebuild` twice."), "Run xcodebuild twice.")
        // A "#" that is not a header mark, a lone "*", prices and underscores are text.
        XCTAssertEqual(StreamingMarkdown.withoutMarkers("Item #4 costs $300.00, 2 * 3 = 6, see file_name."), "Item #4 costs $300.00, 2 * 3 = 6, see file_name.")
        XCTAssertEqual(StreamingMarkdown.withoutMarkers("#hashtag stays"), "#hashtag stays")
        XCTAssertEqual(StreamingMarkdown.withoutMarkers(""), "")
    }
}

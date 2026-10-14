//
//  QueryLiveActivityStateTests.swift
//  OpenIntelligenceTests
//
//  What the answer's Live Activity shows (5.7).
//

#if os(iOS)
    import XCTest

    @testable import OpenIntelligence

    @MainActor
    final class QueryLiveActivityStateTests: XCTestCase {
        func testTheFractionStaysBetweenNothingAndAll() {
            XCTAssertEqual(QueryLiveActivityService.state(title: "A", subtitle: "", fraction: -0.2).progress, 0)
            XCTAssertEqual(QueryLiveActivityService.state(title: "A", subtitle: "", fraction: 1.7).progress, 1)
            XCTAssertEqual(QueryLiveActivityService.state(title: "A", subtitle: "", fraction: .nan).progress, 0)
            XCTAssertEqual(QueryLiveActivityService.state(title: "A", subtitle: "", fraction: 0.4).progress, 0.4)
        }

        func testLongTextIsCutAndAnEmptyTitleIsNamed() {
            let state = QueryLiveActivityService.state(
                title: String(repeating: "t", count: 200), subtitle: String(repeating: "s", count: 500), fraction: 0.5)
            XCTAssertEqual(state.title.count, 60)
            XCTAssertTrue(state.title.hasSuffix("…"))
            XCTAssertEqual(state.subtitle.count, 120)
            XCTAssertEqual(QueryLiveActivityService.state(title: "  ", subtitle: "", fraction: 0).title, "Answering your question")
        }
    }
#endif

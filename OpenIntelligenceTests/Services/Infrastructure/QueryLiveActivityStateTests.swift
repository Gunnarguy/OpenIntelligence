//
//  QueryLiveActivityStateTests.swift
//  OpenIntelligenceTests
//
//  What the answer's Live Activity shows (5.7), and its Stop button: the intent hands the chat the
//  Live Activity's id, and a Stop for an answer that is not running stops nothing. Not covered: a
//  tap on the Lock Screen of a device, which needs the system to run the intent.
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

        func testAStateWrittenWithoutFinishedStillDecodes() throws {
            let json = Data(#"{"progress":0.5,"title":"Answering your question","subtitle":"Searching"}"#.utf8)
            let state = try JSONDecoder().decode(QueryLiveActivityAttributes.ContentState.self, from: json)
            XCTAssertNil(state.finished, "a running answer's state has no finished flag, so the Stop button shows")
            XCTAssertNil(QueryLiveActivityService.state(title: "A", subtitle: "", fraction: 0.2).finished)
        }

        func testTheStopButtonHandsTheChatItsLiveActivitysID() async throws {
            let session = UUID()
            let posted = expectation(forNotification: .stopLongAnswer, object: nil) { notification in
                notification.userInfo?["sessionID"] as? String == session.uuidString
            }
            _ = try await StopLongAnswerIntent(sessionID: session).perform()
            await fulfillment(of: [posted], timeout: 2)
        }

        func testAStopForAnAnswerThatIsNotRunningStopsNothing() {
            XCTAssertFalse(QueryLiveActivityService.shared.isRunningActivity(sessionID: UUID().uuidString))
        }
    }
#endif

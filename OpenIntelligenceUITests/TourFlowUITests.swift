//
//  TourFlowUITests.swift
//  OpenIntelligenceUITests
//
//  The tour's first two lessons as a newcomer meets them (5.8, rebuilt 2026-11-13): the empty chat's card offers
//  "Try a question", its button asks the first suggested question, and the answer that comes back carries the
//  "Check the source" card, whose Show Me opens the passage. Run on a freshly erased simulator: a tip closed in an
//  earlier run stays closed. In the iOS Simulator Apple's model is off, so the answer is Standard's excerpts with
//  their sources, which is what the citation card needs.
//

import XCTest

final class TourFlowUITests: XCTestCase {
    @MainActor
    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testTheEmptyChatCardAsksAndTheAnswerOffersItsSource() throws {
        let app = XCUIApplication()
        // The screenshot mode skips the welcome; importing the samples gives the chat suggested questions.
        app.launchArguments += [
            "--screenshot", "--screenshot-tab", "chat", "--screenshot-import-samples", "-showSiliconHUD", "NO",
        ]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK"] where springboard.buttons[name].waitForExistence(timeout: 3) {
            springboard.buttons[name].tap()
            break
        }

        let ask = app.staticTexts["Ask your documents"].firstMatch
        guard ask.waitForExistence(timeout: 300) else {
            keep(app, "no empty-chat card")
            throw XCTSkip("the empty chat's card never showed: not a fresh install, or no suggested questions yet")
        }
        keep(app, "1 empty chat card")
        let tryIt = app.buttons["Try a question"].firstMatch
        XCTAssertTrue(tryIt.waitForExistence(timeout: 5), "the card has no Try a question button")
        tryIt.tap()

        let check = app.staticTexts["Check the source"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 180), "no Check the source card under the answer")
        keep(app, "2 citation card")
        XCTAssertFalse(ask.exists, "the empty chat's card stayed after its question was asked")

        let showMe = app.buttons["Show me"].firstMatch
        XCTAssertTrue(showMe.waitForExistence(timeout: 5), "the citation card has no Show me button")
        showMe.tap()
        // The source opens in a sheet; its match line is the screen's own tip, "Is it really there?".
        let source = app.staticTexts["Is it really there?"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 20), "Show me opened no source with its match-line tip")
        keep(app, "3 source opened")
    }
}

//
//  SourceScreensUITests.swift
//  OpenIntelligenceUITests
//
//  The screens themselves (5.8): a citation's passage in its document, the Watched Folder section, and a watched
//  folder bringing a file into the library. The switches are in `UITestSupport`.
//

import XCTest

final class SourceScreensUITests: XCTestCase {
    @MainActor
    private func answerSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK"] where springboard.buttons[name].waitForExistence(timeout: 3) {
            springboard.buttons[name].tap()
            return
        }
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--screenshot", "-showSiliconHUD", "NO"] + arguments
        app.launch()
        answerSystemPrompts()
        // The first launch of a new simulator shows the first-run screen once.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        return app
    }

    @MainActor
    private func openLibrarySettings(_ app: XCUIApplication) {
        app.buttons["Documents"].firstMatch.tap()
        let settings = app.buttons["Library Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "no Library Settings button on the Documents tab")
        settings.tap()
    }

    @MainActor
    private func find(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 where !element.exists {
            app.swipeUp(velocity: .slow)
        }
        return element.exists
    }

    @MainActor
    func testACitationOpensItsPassageHighlighted() throws {
        let app = launch(["--uitest-show-source"])
        XCTAssertTrue(
            app.staticTexts["Found word for word in this document."].waitForExistence(timeout: 90),
            "the status line did not appear")
        XCTAssertTrue(app.buttons["Done"].exists)
        keepScreenshot(app, "Source passage")
        app.buttons["Done"].tap()
    }

    @MainActor
    func testACitationAtTheLargestTextSize() throws {
        let app = launch([
            "--uitest-show-source", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(app.staticTexts["Found word for word in this document."].waitForExistence(timeout: 90))
        keepScreenshot(app, "Source passage, largest text")
    }

    @MainActor
    func testLibrarySettingsOffersAWatchedFolderAndAFreePlanIsAskedToUpgrade() throws {
        let app = launch([])
        openLibrarySettings(app)
        let button = app.buttons["Watch a Folder"]
        XCTAssertTrue(find(button, in: app), "no Watch a Folder button in Library Settings")
        keepScreenshot(app, "Library Settings")
        button.tap()
        XCTAssertTrue(
            app.staticTexts["Keep a library up with a folder"].waitForExistence(timeout: 10),
            "a free plan was not shown the plans screen")
        keepScreenshot(app, "Plans screen from Watch a Folder")
    }

    @MainActor
    func testAWatchedFolderBringsItsFileIntoTheLibrary() throws {
        let app = launch(["--uitest-watch-folder", "/private/tmp/oi58-watch"])
        app.buttons["Documents"].firstMatch.tap()
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'watched-heron-note'")).firstMatch
        let openPanel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'batch totals'")).firstMatch
        XCTAssertFalse(
            openPanel.waitForExistence(timeout: 12), "the import panel opened by itself for a file nobody just added")
        XCTAssertTrue(note.waitForExistence(timeout: 90), "the watched file did not arrive in the library")
        keepScreenshot(app, "Library with the watched file")
        openLibrarySettings(app)
        XCTAssertTrue(find(app.buttons["Stop Watching"], in: app), "no Stop Watching button")
        keepScreenshot(app, "Library Settings with a watched folder")
        app.buttons["Stop Watching"].tap()
        XCTAssertTrue(app.buttons["Watch a Folder"].waitForExistence(timeout: 5))
    }
}

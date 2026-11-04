//
//  DiagnosticsSettingsLoopUITests.swift
//  OpenIntelligenceUITests
//
//  Opens Settings, then Developer & Diagnostics, and stays there, as the owner did on 2026-11-04 at 14:22 PT,
//  after which his iPhone rebuilt the model service about every 0.5 s for 17 minutes. The development journal
//  then names each setting that was set (`settings.set`), so the run says which one keeps being set.
//

import XCTest

final class DiagnosticsSettingsLoopUITests: XCTestCase {
    @MainActor
    func testStayingOnDeveloperDiagnostics() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--screenshot", "-showSiliconHUD", "NO"]
        app.launch()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }

        let settingsTab = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15), "no Settings tab")
        settingsTab.tap()

        let row = app.staticTexts["Developer & Diagnostics"].firstMatch
        for _ in 0..<12 where !row.isHittable { app.swipeUp(velocity: .slow) }
        guard row.isHittable else { throw XCTSkip("no Developer & Diagnostics row (Release build?)") }
        row.tap()
        // Long enough for the 17-minute loop's period (about 0.5 s) to repeat many times.
        Thread.sleep(forTimeInterval: 25)
        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 10)
    }
}

//
//  TourTipCloseUITests.swift
//  OpenIntelligenceUITests
//
//  A tour tip closes on one tap of its X (5.8). On the owner's iPhone on 2026-11-04 the X of "Want to see
//  the work?" in Settings, Appearance took several taps. Run with the Silicon HUD off and on, since the HUD
//  redraws many times a second.
//

import XCTest

final class TourTipCloseUITests: XCTestCase {
    @MainActor
    private func launch(hud: Bool, only step: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-showSiliconHUD", hud ? "YES" : "NO"]
        app.launchArguments += step.map { ["-tourShowOnly", $0] } ?? ["-tourShowAll"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK"] where springboard.buttons[name].waitForExistence(timeout: 3) {
            springboard.buttons[name].tap()
            break
        }
        // Without `--screenshot` onboarding shows first; its button reads "Skip onboarding".
        let skip = app.buttons["Skip onboarding"]
        if skip.waitForExistence(timeout: 8) { skip.tap() }
        return app
    }

    /// Closes one tip with a single tap of its X. True when it went within 3 s; a tip that never showed or
    /// has no X fails the test with that reason, so it isn't counted as a tap that didn't work.
    @MainActor
    private func closesOnOneTap(_ title: String, in app: XCUIApplication) -> Bool {
        let tipTitle = app.staticTexts[title].firstMatch
        guard tipTitle.waitForExistence(timeout: 8) else {
            XCTFail("never shown: \(title)")
            return true
        }
        let close = app.buttons["Close"].firstMatch
        guard close.waitForExistence(timeout: 3) else {
            XCTFail("no Close button on \(title)")
            return true
        }
        close.tap()
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: tipTitle)], timeout: 3) == .completed
    }

    /// Settings shows its tips one at a time (`Tour.settings`, first available): four on the list, then
    /// "Want to see the work?" in Appearance. Each must close on one tap.
    @MainActor
    private func closeTheSettingsTipsOnOneTapEach(hud: Bool) throws {
        let app = launch(hud: hud)
        let settingsTab = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15), "no Settings tab")
        settingsTab.tap()

        var missed: [String] = []
        if !closesOnOneTap("How it really works", in: app) { missed.append("How it really works") }
        if !closesOnOneTap("You decide when it's used", in: app) { missed.append("You decide when it's used") }
        XCTAssertTrue(missed.isEmpty, "Settings tips still up after one tap of the X (HUD \(hud ? "on" : "off")): \(missed)")
    }

    /// "Want to see the work?" in Settings, Appearance, the tip the owner had to tap several times on 2026-11-04.
    @MainActor
    private func closeTheAppearanceTipOnOneTap(hud: Bool) throws {
        let app = launch(hud: hud, only: "technicalDetails")
        let settingsTab = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15), "no Settings tab")
        settingsTab.tap()
        var missed: [String] = []

        let appearance = app.staticTexts["Appearance"].firstMatch
        for _ in 0..<8 where !appearance.isHittable { app.swipeUp(velocity: .slow) }
        guard appearance.isHittable else {
            print("TIPTEST-TREE-BEGIN\n\(app.debugDescription)\nTIPTEST-TREE-END")
            throw XCTSkip("no Appearance row on screen")
        }
        appearance.tap()
        if !closesOnOneTap("Want to see the work?", in: app) { missed.append("Want to see the work?") }
        XCTAssertTrue(missed.isEmpty, "tips still up after one tap of the X (HUD \(hud ? "on" : "off")): \(missed)")
    }

    @MainActor
    func testTheListTipsCloseOnOneTap() throws {
        try closeTheSettingsTipsOnOneTapEach(hud: false)
    }

    @MainActor
    func testTheTipClosesOnOneTapWithTheHUDOff() throws {
        try closeTheAppearanceTipOnOneTap(hud: false)
    }

    @MainActor
    func testTheTipClosesOnOneTapWithTheHUDOn() throws {
        try closeTheAppearanceTipOnOneTap(hud: true)
    }
}

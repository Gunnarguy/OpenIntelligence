//
//  SettingsRowsUITests.swift
//  OpenIntelligenceUITests
//
//  Each Settings row opens its page on one tap (5.8). On the owner's iPhone on 2026-11-04 the rows opened
//  only now and then however often he tapped, with the main thread free; each row's link carried a tap
//  gesture for the tour, which moved to the page's onAppear. Run once with the Silicon HUD off and once
//  with it on, since the HUD floats in a window of its own above the app.
//

import XCTest

final class SettingsRowsUITests: XCTestCase {
    private static let rows = [
        "How This Works", "Plain English", "Intelligence Mode", "Apple Intelligence", "Private Cloud Compute",
        "Libraries & iCloud", "Device & Performance",
    ]

    @MainActor
    private func launch(hud: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--screenshot", "-showSiliconHUD", hud ? "YES" : "NO"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK"] where springboard.buttons[name].waitForExistence(timeout: 3) {
            springboard.buttons[name].tap()
            break
        }
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        return app
    }

    @MainActor
    private func openEveryRowOnOneTap(hud: Bool) {
        let app = launch(hud: hud)
        let settingsTab = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15), "no Settings tab")
        settingsTab.tap()
        XCTAssertTrue(
            app.staticTexts["How This Works"].firstMatch.waitForExistence(timeout: 10), "Settings did not open")

        var missed: [String] = []
        for title in Self.rows {
            let row = app.staticTexts[title].firstMatch
            for _ in 0..<6 where !row.isHittable { app.swipeUp(velocity: .slow) }
            guard row.isHittable else {
                missed.append("\(title) (not on screen)")
                continue
            }
            row.tap()
            // One tap, then the page's own title in the navigation bar.
            let opened = app.navigationBars[title].firstMatch.waitForExistence(timeout: 4)
            if !opened {
                missed.append(title)
                continue
            }
            app.navigationBars[title].buttons.firstMatch.tap()
            _ = app.staticTexts["How This Works"].firstMatch.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(missed.isEmpty, "rows that did not open on one tap (HUD \(hud ? "on" : "off")): \(missed)")
    }

    @MainActor
    func testEveryRowOpensOnOneTapWithTheHUDOff() {
        openEveryRowOnOneTap(hud: false)
    }

    @MainActor
    func testEveryRowOpensOnOneTapWithTheHUDOn() {
        openEveryRowOnOneTap(hud: true)
    }
}

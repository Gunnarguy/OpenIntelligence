//
//  AccessibilityAuditTests.swift
//  OpenIntelligenceUITests
//
//  Apple's accessibility audit on the screens people open first (5.7, roadmap row "VoiceOver"): the
//  first-run screen when it shows, then Chat, Documents and Settings. It runs the checks a VoiceOver
//  user meets: an element with no description, a tap area too small to hit, a wrong trait, and
//  elements the audit cannot find. The audit for an action with no name is macOS only
//  (XCUIAccessibilityAuditTypes.h in Xcode 27). The hardware X-Ray is switched off for the run: while its
//  floating window is up the audit reports mostly that window and little of the screens behind it (2026-10-15).
//  Contrast, Dynamic Type and clipped text are measured separately, on screenshots, because the audit's
//  contrast verdicts did not follow the drawn pixels for several elements (Docs/ai/RUNBOOK.md, "Apple's
//  accessibility audit, with the X-Ray off").
//  Not covered: navigating the app with VoiceOver on a device, which is what closes the row.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    @MainActor
    func testTheMainScreensPassTheAccessibilityAudit() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-stand-in-model", "-showSiliconHUD", "NO"]
        app.launch()

        var issues: [String] = []
        var notes: [String] = []
        func audit(_ screen: String) throws {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = screen
            screenshot.lifetime = .keepAlways
            add(screenshot)
            try app.performAccessibilityAudit(
                for: [.sufficientElementDescription, .hitRegion, .trait, .elementDetection]
            ) { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id '\($0.identifier)'" } ?? "no element"
                issues.append("\(screen): \(issue.compactDescription) [\(element)] \(issue.detailedDescription)")
                return true
            }
        }

        // The first-run screen covers the tabs until it is closed, so it is audited first and then closed the
        // way a person closes it. It shows only where the app has not been closed past it before.
        let skip = app.buttons["I'll add my own documents"]
        if skip.waitForExistence(timeout: 10) {
            try audit("First run")
            skip.tap()
        }

        for tab in ["Chat", "Documents", "Settings"] {
            let button = app.tabBars.buttons[tab]
            if button.waitForExistence(timeout: 20), !button.isHittable {
                // The tab bar shrinks while a list scrolls (5.7), and the audit can scroll one.
                app.swipeDown()
            }
            guard button.waitForExistence(timeout: 5), button.isHittable else {
                issues.append("\(tab): the tab button was not found or could not be tapped")
                // What covered it, for the log: once (2026-10-16) none of the tabs nor the first-run screen was found.
                print("SCREEN WITHOUT THE \(tab.uppercased()) TAB\n\(app.debugDescription)\nEND SCREEN")
                continue
            }
            button.tap()
            // An alert hides the screen under it from VoiceOver, so one that is up is closed first and
            // noted in the report. Through 5.7's first builds the Documents screen showed one at every
            // launch in the Simulator, which has no on-device model.
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 3) {
                notes.append("\(tab): closed the alert \"\(alert.label)\" before the audit")
                alert.buttons.firstMatch.tap()
            }
            try audit(tab)
        }

        let report = issues.joined(separator: "\n")
        let attachment = XCTAttachment(string: report.isEmpty ? "No issues" : report)
        attachment.name = "Accessibility audit"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("ACCESSIBILITY AUDIT\n\((notes + [report.isEmpty ? "No issues" : report]).joined(separator: "\n"))\nEND AUDIT")
        XCTAssertTrue(issues.isEmpty, "\(issues.count) accessibility issue(s):\n\(report)")
    }

    /// Every switch and slider on Settings' Appearance and Apple Intelligence pages has a name VoiceOver reads
    /// (5.7). Through 5.6 the X-Ray's switches, its glow slider and the Apple Intelligence feature switches had
    /// none, so VoiceOver read each one as a switch with nothing to say which. Those pages are a tap below the
    /// Settings list, where the audit above does not go, so this test runs Apple's description check on them too.
    @MainActor
    func testTheSwitchesAndSlidersInSettingsHaveNames() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-stand-in-model", "-showSiliconHUD", "NO"]
        app.launch()

        let skip = app.buttons["I'll add my own documents"]
        if skip.waitForExistence(timeout: 10) {
            skip.tap()
        }
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20), "the Settings tab was not found")
        settingsTab.tap()

        var issues: [String] = []
        /// The names of the switches and sliders on the open page. A SwiftUI switch also holds the system's own
        /// switch as an element with no label, one inside each named switch (the first run of this test,
        /// 2026-10-16); VoiceOver reads the outer one, so whether anything unnamed can be reached is the audit's call.
        func names(on page: String) -> [String] {
            (app.switches.allElementsBoundByIndex + app.sliders.allElementsBoundByIndex)
                .filter { $0.exists && !$0.label.isEmpty }.map(\.label).sorted()
        }
        /// Apple's check for elements VoiceOver reaches with no description, on the page that is open.
        func audit(_ page: String) throws {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription]) { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' at \($0.frame)" } ?? "no element"
                issues.append("\(page): \(issue.compactDescription) [\(element)]")
                return true
            }
        }
        /// Opens a page from the Settings list, scrolling the list until its row is on screen. A row reads as its
        /// title and subtitle ("Appearance, Accent colour and the hardware HUD").
        func open(_ page: String) -> Bool {
            let row = app.buttons.matching(
                NSPredicate(format: "label == %@ OR label BEGINSWITH %@", page, page + ",")
            ).firstMatch
            for _ in 0..<12 where !(row.exists && row.isHittable) {
                app.swipeUp()
            }
            guard row.exists, row.isHittable else { return false }
            row.tap()
            return true
        }

        XCTAssertTrue(open("Apple Intelligence"), "the Apple Intelligence row was not found")
        // Its feature switches show only where Apple Intelligence can run; every one shown must have a name.
        _ = app.switches.firstMatch.waitForExistence(timeout: 5)
        try audit("Apple Intelligence")
        print("APPLE INTELLIGENCE CONTROLS: \(names(on: "Apple Intelligence"))")
        app.navigationBars.buttons.firstMatch.tap()

        // Last, because the X-Ray's window floats over the screen once it is on, and a tap under it reaches it.
        XCTAssertTrue(open("Appearance"), "the Appearance row was not found")
        let hud = app.switches["Telemetry HUD"]
        XCTAssertTrue(hud.waitForExistence(timeout: 5), "the X-Ray's switch has no name: \(names(on: "Appearance"))")
        try audit("Appearance")
        if hud.exists {
            // Its own switches and the glow slider show only while it is on.
            hud.tap()
            XCTAssertTrue(app.sliders["Glow Intensity"].waitForExistence(timeout: 5), "the glow slider has no name")
            XCTAssertTrue(app.switches["Live Metrics"].exists, "the Live Metrics switch has no name")
            XCTAssertTrue(app.switches["Taptic Engine"].exists, "the Taptic Engine switch has no name")
            print("APPEARANCE CONTROLS: \(names(on: "Appearance"))")
            // Off again, as a new install has it: the setting is saved, and the other tests start from it.
            hud.tap()
        }

        print("SETTINGS PAGES AUDIT\n\(issues.isEmpty ? "No issues" : issues.joined(separator: "\n"))\nEND AUDIT")
        XCTAssertTrue(issues.isEmpty, "\(issues.count) element(s) with no description: \(issues)")
    }
}

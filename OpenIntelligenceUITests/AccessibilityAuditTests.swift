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
}

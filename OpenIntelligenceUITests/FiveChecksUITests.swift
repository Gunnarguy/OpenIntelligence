//
//  FiveChecksUITests.swift
//  OpenIntelligenceUITests
//
//  The screens of five roadmap checks run in the iOS 27 Simulator on 2026-11-14 (5.8). Each test keeps its
//  screenshots and what the screen's elements said under /private/tmp/oi-checks-shots, and as attachments.
//  The hosted half is `OpenIntelligenceTests/App/FiveChecksSimulatorTests.swift`.
//
//  - `testAStandardAnswerWithNoPassagesShowsNoSourcesAndIsNotSourceLocked`: needs the open library empty. The
//    answer's words come from the screenshot stand-in model (`--screenshot`); the path, the badge and the details
//    card are the app's own.
//  - `testTheGlossarysPrivateCloudComputeEntryAndTheMetricsBar`: captures the texts as shown.
//  - `testACitationPastS12OpensItsPassageAfterARelaunchAndCopyListsIt`: needs the conversation
//    `FiveChecksSimulatorTests.testSeedASavedAnswerThatCitesS13` saved in an earlier launch of the app.
//

import XCTest

final class FiveChecksUITests: XCTestCase {
    private static let folder = URL(fileURLWithPath: "/private/tmp/oi-checks-shots", isDirectory: true)

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
    }

    @MainActor
    private func keep(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        try? screenshot.pngRepresentation.write(to: Self.folder.appendingPathComponent("\(name).png"))
        try? app.debugDescription.write(
            to: Self.folder.appendingPathComponent("\(name).tree.txt"), atomically: true, encoding: .utf8)
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func note(_ name: String, _ text: String) {
        try? text.write(to: Self.folder.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[FiveChecks] \(name): \(text)")
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--screenshot", "-showSiliconHUD", "NO"] + arguments
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK"] where springboard.buttons[name].waitForExistence(timeout: 3) {
            springboard.buttons[name].tap()
            break
        }
        // The first-run screen can come up a few seconds in.
        // The welcome screen shows whenever the open library is empty; its Skip is labelled "Skip onboarding".
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Skip'")).firstMatch
        if skip.waitForExistence(timeout: 10) {
            skip.tap()
            sleep(2)
        }
        return app
    }

    /// Closes what can sit over the chat: the rating request, a tip.
    @MainActor
    private func clearTheScreen(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [app, springboard] where host.buttons["Not Now"].exists {
            host.buttons["Not Now"].firstMatch.tap()
            sleep(1)
        }
        for _ in 0..<3 where app.buttons["Close"].exists {
            app.buttons["Close"].firstMatch.tap()
            sleep(1)
        }
    }

    /// Every label on screen that contains `text`, longest first.
    @MainActor
    private func labels(containing text: String, in app: XCUIApplication) -> [String] {
        let found = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .allElementsBoundByIndex.map(\.label)
        return Array(Set(found)).sorted { $0.count > $1.count }
    }

    @MainActor
    private func openChat(_ app: XCUIApplication) {
        let chat = app.buttons["Chat"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 20), "no Chat tab")
        chat.tap()
        sleep(2)
        clearTheScreen(app)
    }

    /// Types a question in the chat's field and sends it.
    @MainActor
    private func ask(_ question: String, in app: XCUIApplication) {
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) { field = app.textFields.firstMatch }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no question field")
        field.tap()
        field.typeText(question)
        keep(app, "ask-typed")
        // The send button carries its symbol's name. A tip over the composer can take the first tap.
        let send = app.buttons["arrow.up"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no send button beside the field")
        for _ in 0..<3 {
            send.tap()
            sleep(2)
            let value = (field.value as? String) ?? ""
            if !value.contains(String(question.prefix(12))) { break }
        }
    }

    /// Opens the named library from the chips above the chat.
    @MainActor
    private func openLibrary(_ name: String, in app: XCUIApplication) {
        let chip = app.buttons[name].firstMatch
        // With one library there are no chips, and that library is the open one.
        guard chip.waitForExistence(timeout: 10) else {
            note("library-\(name)", "no \(name) chip above the chat; the open library is used as it is")
            return
        }
        chip.tap()
        sleep(2)
        note(
            "library-\(name)",
            "chip: label=\(chip.label) value=\(String(describing: chip.value)) selected=\(chip.isSelected)")
    }

    // MARK: - Screens, for a look at them (no assertions about content beyond being reachable)

    /// The Documents page with its watched folder row, the row's sheet, and the Settings list.
    @MainActor
    func testShotsOfTheDocumentsPageAndItsWatchedFolderRow() {
        let app = launch()
        let documents = app.buttons["Documents"].firstMatch
        XCTAssertTrue(documents.waitForExistence(timeout: 20), "no Documents tab")
        documents.tap()
        sleep(2)
        clearTheScreen(app)
        keep(app, "look-documents")
        let row = app.buttons["watchedFolderRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no watched folder row on the Documents page")
        note("look-watched-row", row.label)
        row.tap()
        sleep(2)
        keep(app, "look-watched-sheet")
        XCTAssertTrue(
            app.staticTexts["Watched Folder"].firstMatch.waitForExistence(timeout: 5), "the sheet did not open")
    }

    /// The Database tab, screen by screen as it scrolls, and the Settings list, for a look at their type.
    @MainActor
    func testShotsOfTheDatabaseTab() {
        shootTheDatabaseTab(technical: false)
    }

    /// The same with Technical Details on, which adds the Index and Performance sections (2026-11-15).
    @MainActor
    func testShotsOfTheDatabaseTabTechnical() {
        shootTheDatabaseTab(technical: true)
    }

    @MainActor
    private func shootTheDatabaseTab(technical: Bool) {
        let app = launch(["-showTechnicalDetails", technical ? "YES" : "NO"])
        let prefix = technical ? "database-tech" : "database"
        let tab = app.buttons["Database"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no Database tab")
        tab.tap()
        sleep(3)
        clearTheScreen(app)
        for index in 0..<4 {
            keep(app, String(format: "%@-%02d", prefix, index))
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
        // Every inner section, its top and one screen down (2026-11-15). The chips carry identifiers
        // `database.section.<rawValue>`; ones past the screen's edge are reached by swiping the chip row.
        // Every section in both runs (2026-11-16), since Technical Details changes the words on each, not only which
        // sections are listed.
        let customerSections = ["intelligence", "documents", "vocabulary", "maintenance", "search"]
        let sections = technical ? customerSections + ["index", "performance"] : customerSections
        for section in sections {
            for _ in 0..<5 { app.swipeDown(velocity: .fast) }
            sleep(1)
            let chip = app.buttons["database.section.\(section)"].firstMatch
            guard chip.waitForExistence(timeout: 3) else {
                note(
                    "database-missing-\(section)",
                    "no chip for \(section) (Index and Performance need Technical Details)")
                continue
            }
            var tries = 0
            while !chip.isHittable, tries < 4 {
                // A drag along the chip row, at the chip's height, from near the right edge to near the left.
                let y = chip.frame.midY / app.frame.height
                let row = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y))
                row.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y)))
                tries += 1
            }
            guard chip.isHittable else {
                note("database-missing-\(section)", "chip for \(section) not hittable")
                continue
            }
            chip.tap()
            sleep(2)
            keep(app, "\(prefix)-\(section)")
            app.swipeUp(velocity: .slow)
            sleep(1)
            keep(app, "\(prefix)-\(section)-2")
        }
    }

    /// Every Settings page, top and then a screen at a time to its end, for a look at them side by side.
    @MainActor
    func testShotsOfEverySettingsPage() {
        let app = launch()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "no Settings tab")
        settings.tap()
        sleep(2)
        clearTheScreen(app)
        keep(app, "settings-00-list")
        let pages = [
            "How This Works", "Plain English", "Intelligence Mode", "Model & Privacy", "Libraries & iCloud",
            "Device & Performance", "General", "Plan & Usage", "Siri & Shortcuts", "Advanced",
            "Developer & Diagnostics", "About", "Version History",
        ]
        for (index, page) in pages.enumerated() {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", page)).firstMatch
            var tries = 0
            while !row.isHittable, tries < 6 {
                app.swipeUp(velocity: .slow)
                tries += 1
            }
            guard row.exists, row.isHittable else {
                note("settings-missing-\(index)", "no row for \(page)")
                continue
            }
            row.tap()
            sleep(2)
            let name = String(format: "settings-%02d-%@", index + 1, page.replacingOccurrences(of: " ", with: "-"))
            keep(app, name)
            app.swipeUp(velocity: .slow)
            sleep(1)
            keep(app, name + "-2")
            // Down to the end of a long page, stopping when a swipe no longer changes it (2026-11-16).
            for depth in 3...8 {
                let before = app.debugDescription
                app.swipeUp(velocity: .slow)
                sleep(1)
                if app.debugDescription == before { break }
                keep(app, name + "-\(depth)")
            }
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() } else { settings.tap() }
            sleep(1)
        }
    }

    /// The plans screen from Settings, one screenshot per screen to its end (2026-11-15). Plan & Usage opened a page
    /// whose View Plans opened the plans; where that page is still there it is kept and its button tapped.
    @MainActor
    func testShotsOfThePlansScreen() {
        let app = launch()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "no Settings tab")
        settings.tap()
        sleep(2)
        clearTheScreen(app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan & Usage'")).firstMatch
        var tries = 0
        while !row.isHittable, tries < 6 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(row.isHittable, "no Plan & Usage row")
        row.tap()
        sleep(2)
        let viewPlans = app.buttons.matching(NSPredicate(format: "label IN {'View Plans', 'Upgrade Plan'}")).firstMatch
        var taps = 1
        if viewPlans.exists, viewPlans.isHittable {
            keep(app, "plans-page")
            viewPlans.tap()
            taps += 1
            sleep(3)
        }
        note(
            "plans-taps",
            "\(taps + 1) taps from the Settings tab to the plans (tab, row\(taps > 1 ? ", View Plans" : ""))")
        // Until a swipe no longer moves the page: the same pixels twice is the end.
        var previous = Data()
        for index in 0..<10 {
            let pixels = app.screenshot().pngRepresentation
            if pixels == previous { break }
            previous = pixels
            keep(app, String(format: "plans-%02d", index))
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
    }

    // MARK: - The rest of the app, screen by screen (5.8 premium pass, 2026-11-16)

    /// Screenshots `prefix-00`, `prefix-01` and on, swiping up until the screen stops changing or `limit` is reached.
    /// "Changing" is read from the element tree, which holds every element's frame: the status bar clock changes the
    /// pixels of a screen that did not move.
    @MainActor
    private func shootToTheEnd(_ app: XCUIApplication, _ prefix: String, limit: Int = 8) {
        var previous = ""
        for index in 0..<limit {
            let tree = app.debugDescription.components(separatedBy: "\n")
                .filter { $0.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) == nil }
                .joined(separator: "\n")
            if tree == previous { break }
            previous = tree
            keep(app, String(format: "%@-%02d", prefix, index))
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
    }

    @MainActor
    private func openTab(_ name: String, in app: XCUIApplication) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no \(name) tab")
        tab.tap()
        sleep(3)
        clearTheScreen(app)
    }

    /// Taps the first button whose label is one of `labels`; false when none is on screen.
    @MainActor
    @discardableResult
    private func tapButton(_ labels: [String], in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        guard button.waitForExistence(timeout: timeout), button.isHittable else { return false }
        button.tap()
        sleep(2)
        return true
    }

    /// The Documents tab, then the Library Settings sheet to its end, with the color and symbol pickers.
    @MainActor
    func testShotsOfTheDocumentsTabAndLibrarySettings() {
        let app = launch()
        openTab("Documents", in: app)
        shootToTheEnd(app, "documents", limit: 4)
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        guard tapButton(["Library Settings"], in: app) else {
            note("documents-missing-settings", "no Library Settings button")
            return
        }
        shootToTheEnd(app, "library-settings", limit: 12)
        // Open the sheet again at its top; swiping back up to it can pull the sheet closed.
        tapButton(["Cancel"], in: app)
        guard tapButton(["Library Settings"], in: app) else { return }
        let color = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Color'")).firstMatch
        if color.exists, color.isHittable {
            color.tap()
            sleep(2)
            shootToTheEnd(app, "color-picker", limit: 3)
            if !tapButton(["Done", "Cancel"], in: app) { app.swipeDown(velocity: .fast) }
        } else {
            note("library-settings-missing-color", "no Color button at the top of Library Settings")
        }
        let symbol = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Icon' OR label CONTAINS[c] 'Symbol'"))
            .firstMatch
        if symbol.exists, symbol.isHittable {
            symbol.tap()
            sleep(2)
            shootToTheEnd(app, "symbol-picker", limit: 3)
            if !tapButton(["Done", "Cancel"], in: app) { app.swipeDown(velocity: .fast) }
        } else {
            note("library-settings-missing-symbol", "no Icon button at the top of Library Settings")
        }
    }

    /// The sheets the Documents tab opens: Semantic Search, a document's details.
    @MainActor
    func testShotsOfTheDocumentsSheets() {
        let app = launch()
        openTab("Documents", in: app)
        if tapButton(["Semantic Search"], in: app) {
            keep(app, "semantic-search-00")
            let field = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("library\n")
                sleep(6)
                shootToTheEnd(app, "semantic-search-results", limit: 3)
            }
            tapButton(["Done"], in: app)
        } else {
            note("documents-missing-search", "no Semantic Search button")
        }
        // The first document card, in the guide library, which always has documents.
        let guide = app.buttons["OpenIntelligence Guide"].firstMatch
        if guide.waitForExistence(timeout: 5), guide.isHittable {
            guide.tap()
            sleep(2)
        }
        let card = app.buttons["documentCard"].firstMatch
        if card.waitForExistence(timeout: 5), card.isHittable {
            keep(app, "documents-guide")
            card.tap()
            sleep(3)
            shootToTheEnd(app, "document-details", limit: 8)
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
        } else {
            note("documents-missing-card", "no document card found")
        }
        // Back to the library the other tests start in.
        let general = app.buttons["General"].firstMatch
        if general.waitForExistence(timeout: 5), general.isHittable { general.tap() }
        sleep(1)
    }

    /// The Atlas tab and what its panels show.
    @MainActor
    func testShotsOfTheAtlasTab() {
        let app = launch()
        openTab("Atlas", in: app)
        sleep(4)
        shootToTheEnd(app, "atlas", limit: 4)
    }

    /// The chat's chrome around the bubbles: the empty state, the toolbar's menus and sheets.
    @MainActor
    func testShotsOfTheChatChrome() {
        let app = launch()
        openChat(app)
        keep(app, "chat-00")
        let menu = app.buttons.matching(NSPredicate(format: "label IN {'More', 'ellipsis.circle'}")).firstMatch
        if menu.exists, menu.isHittable {
            menu.tap()
            sleep(1)
            keep(app, "chat-menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            sleep(1)
        }
        // Every toolbar button in turn, a screenshot of what it opens.
        let toolbar = app.navigationBars.buttons.allElementsBoundByIndex.map(\.label)
        note("chat-toolbar", toolbar.joined(separator: " | "))
        for (index, label) in toolbar.enumerated() where !label.isEmpty && label != "More" {
            let button = app.navigationBars.buttons[label].firstMatch
            guard button.exists, button.isHittable else { continue }
            button.tap()
            sleep(2)
            keep(app, String(format: "chat-toolbar-%02d", index))
            if !tapButton(["Done", "Close", "Cancel"], in: app, timeout: 1) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
                sleep(1)
            }
        }
        // The mode picker and the library chips above the field.
        let mode = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH 'Standard' OR label BEGINSWITH 'Deep Think' OR label BEGINSWITH 'Maximum'")
        ).firstMatch
        if mode.exists, mode.isHittable {
            mode.tap()
            sleep(2)
            keep(app, "chat-mode")
            if !tapButton(["Done", "Close"], in: app, timeout: 1) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            }
        }
    }

    // MARK: - 3

    @MainActor
    func testAStandardAnswerWithNoPassagesShowsNoSourcesAndIsNotSourceLocked() throws {
        let app = launch(["-ragQualityMode", "standard", "-showTechnicalDetails", "NO"])
        openChat(app)
        openLibrary("General", in: app)
        keep(app, "check3-chat-before")
        ask("What is the tallest mountain in Scotland?", in: app)

        let badge = app.staticTexts["No Sources"].firstMatch
        let appeared = badge.waitForExistence(timeout: 120)
        keep(app, "check3-answer")
        XCTAssertTrue(appeared, "no No Sources badge under the answer")
        note(
            "check3-badge",
            "badge labels on screen: \(["No Sources", "Verified", "Partial", "Not supported", "Unverified", "Low Confidence"].filter { app.staticTexts[$0].exists })"
        )

        clearTheScreen(app)
        note(
            "check3-answer-text",
            labels(containing: " ", in: app).filter { $0.count > 20 }.joined(separator: "\n"))
        // The details card, from the chip that says where the answer was written.
        let route = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Answer generated by'")).firstMatch
        if route.waitForExistence(timeout: 5) {
            route.tap()
        } else {
            keep(app, "check3-no-route-chip")
            XCTFail("no route chip under the answer")
        }
        let titles = ["Source-Locked", "Partially Supported", "Not Enough Evidence", "Not Checked"]
        var shown: [String] = []
        for _ in 0..<20 where shown.isEmpty {
            shown = titles.filter { app.staticTexts[$0].exists }
            if shown.isEmpty { sleep(1) }
        }
        keep(app, "check3-details")
        note(
            "check3-details-card",
            "fidelity titles on the details card: \(shown); lines: \(labels(containing: "claims", in: app) + labels(containing: "evidence", in: app) + labels(containing: "No check ran", in: app))"
        )
        XCTAssertFalse(shown.isEmpty, "the details card shows no fidelity status")
        XCTAssertFalse(app.staticTexts["Source-Locked"].exists, "the details card says Source-Locked")
        XCTAssertTrue(
            labels(containing: "All claims are fully verified", in: app).isEmpty,
            "the details card says all claims are verified")
    }

    // MARK: - 5

    @MainActor
    func testTheGlossarysPrivateCloudComputeEntryAndTheMetricsBar() throws {
        let app = launch(["-showTechnicalDetails", "YES"])
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "no Settings tab")
        settings.tap()
        let row = app.staticTexts["Plain English"].firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable, "no Plain English row in Settings")
        row.tap()
        XCTAssertTrue(app.navigationBars["Plain English"].firstMatch.waitForExistence(timeout: 10))

        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search field in the glossary")
        search.tap()
        search.typeText("Private Cloud Compute")
        keep(app, "check5-glossary-search")
        note("check5-glossary-row", labels(containing: "Apple's servers", in: app).joined(separator: "\n---\n"))

        let term = app.staticTexts["Private Cloud Compute"].firstMatch
        XCTAssertTrue(term.waitForExistence(timeout: 5), "no Private Cloud Compute term in the results")
        term.tap()
        sleep(2)
        keep(app, "check5-glossary-entry")
        let plain = labels(containing: "Apple's servers", in: app)
        let technical =
            labels(containing: "CloudEvidenceMinimizer", in: app) + labels(containing: "consent sheet", in: app)
        note(
            "check5-glossary-entry",
            "PLAIN:\n\(plain.joined(separator: "\n---\n"))\n\nTECHNICAL:\n\(Array(Set(technical)).joined(separator: "\n---\n"))"
        )
        XCTAssertFalse(plain.isEmpty, "the entry's plain text is not on screen")
        // Its technical half, when the sheet keeps it behind a control.
        let technicalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'technical version'")).firstMatch
        if technicalRow.exists {
            technicalRow.tap()
            sleep(1)
            keep(app, "check5-glossary-entry-technical")
            note(
                "check5-glossary-entry-technical",
                (labels(containing: "CloudEvidenceMinimizer", in: app) + labels(containing: "consent sheet", in: app))
                    .joined(separator: "\n---\n"))
        }
        app.terminate()

        // The metrics bar: an answer, then the bar's panel.
        let chatApp = launch(["-showTechnicalDetails", "YES", "-ragQualityMode", "standard"])
        openChat(chatApp)
        openLibrary("OpenIntelligence Guide", in: chatApp)
        ask("What are the three quality modes?", in: chatApp)
        // The answer is done when the send button is back and the answer's own actions can be opened.
        sleep(45)
        clearTheScreen(chatApp)
        let bar = chatApp.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Standard,'")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "no metrics bar above the chat")
        note("check5-metrics-bar", bar.label)
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        sleep(2)
        keep(chatApp, "check5-metrics-panel-top")
        let location = chatApp.staticTexts["Processing Location"].firstMatch
        for _ in 0..<8 where !location.exists || !location.isHittable {
            chatApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(
                    forDuration: 0.05, thenDragTo: chatApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                )
            sleep(1)
        }
        keep(chatApp, "check5-metrics-panel-location")
        XCTAssertTrue(location.exists, "no Processing Location section in the metrics panel")
        note(
            "check5-metrics-panel-texts",
            labels(containing: " ", in: chatApp).joined(separator: "\n"))
        keep(chatApp, "check5-chat-answer")
        note(
            "check5-chat-cloud-lines",
            (labels(containing: "Private Cloud", in: chatApp) + labels(containing: "On-device model", in: chatApp)
                + labels(containing: "on this device", in: chatApp)).joined(separator: "\n---\n"))
    }

    // MARK: - 1

    @MainActor
    func testACitationPastS12OpensItsPassageAfterARelaunchAndCopyListsIt() throws {
        let app = launch(["-showTechnicalDetails", "NO"])
        openChat(app)
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'third step of the old dock'"))
            .firstMatch
        let loaded = answer.waitForExistence(timeout: 30)
        keep(app, "check1-relaunched-chat")
        XCTAssertTrue(loaded, "the saved answer is not on screen after the relaunch")

        // The label itself.
        var tapped = false
        for query in [app.links, app.buttons, app.staticTexts] where !tapped {
            let label = query.matching(NSPredicate(format: "label CONTAINS 'S13'")).firstMatch
            if label.exists, label.label.count < 12 {
                label.tap()
                tapped = true
                note("check1-tap", "tapped \(label.elementType.rawValue) '\(label.label)'")
            }
        }
        if !tapped, answer.exists {
            // The label ends the sentence: the end of the answer's last line.
            note("check1-tap", "no element for the label; tapping the end of the answer's text, frame \(answer.frame)")
            for offset in [
                CGVector(dx: 0.93, dy: 0.85), CGVector(dx: 0.85, dy: 0.85), CGVector(dx: 0.75, dy: 0.85),
                CGVector(dx: 0.6, dy: 0.85), CGVector(dx: 0.45, dy: 0.85), CGVector(dx: 0.3, dy: 0.85),
                CGVector(dx: 0.15, dy: 0.85),
            ]
            where !app.buttons["Done"].exists {
                answer.coordinate(withNormalizedOffset: offset).tap()
                if app.buttons["Done"].waitForExistence(timeout: 2) {
                    note("check1-tap-offset", "\(offset)")
                    break
                }
                // A tap beside the label opens the answer's actions; close them again.
                if app.buttons["Copy"].exists {
                    answer.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.1)).tap()
                }
            }
        }
        let opened = app.buttons["Done"].waitForExistence(timeout: 15)
        let status = app.staticTexts["Found word for word in this document."].waitForExistence(timeout: 30)
        keep(app, "check1-passage")
        note(
            "check1-passage",
            "sheet opened=\(opened) status line=\(status) passage lines: \(labels(containing: "boathouse key", in: app))"
        )
        XCTAssertTrue(opened, "tapping [S13] opened nothing")
        XCTAssertTrue(
            !labels(containing: "boathouse key sits under", in: app).isEmpty, "the passage's text is not on the page")
        if opened { app.buttons["Done"].firstMatch.tap() }

        // Copy, from the answer's actions.
        sleep(1)
        if !app.buttons["Copy"].exists {
            answer.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.15)).tap()
        }
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "no Copy button under the answer")
        keep(app, "check1-actions")
        copy.tap()
        sleep(1)
        keep(app, "check1-copied")
    }
}

//
//  LifecycleScenarioUITests.swift
//  OpenIntelligenceUITests
//
//  What happens to an answer or an import when the person leaves the app, locks the phone, or the app is ended
//  (5.8 retrospective, gap 4: answers failing after leaving the app were raised on 2026-11-04 and were still being
//  fixed on submission day, and no test covered any of it).
//
//  These tests only drive the app. The verdict comes from the journal the development build writes
//  (`VerificationJournal`, `Documents/verification_events.jsonl`), which `scripts/lifecycle_scenarios.py` reads
//  after the run: it starts them on a simulator of its own, against a copy of the app in which Apple's model
//  answers in the Simulator (`scripts/sim_model_copy.py`). Run them through that script:
//
//      python3 scripts/lifecycle_scenarios.py
//
//  The script passes the simulator's app-data folder in `OI_SIM_APPS`, so a test finds the journal and waits for
//  the event it needs (an answer starting, an import finishing) instead of sleeping for a guess. Without it a
//  test falls back to fixed waits. Each test prints BEGIN and END lines with the time, which is how the script
//  cuts the journal into one piece per scenario.
//
//  The numbers in the names set the order: the first needs a new install, and the second imports the note the
//  answers are asked about (a new install's library is empty, and an answer from an empty library needs no
//  search). No launch here carries `--screenshot` or `--uitest-stand-in-model`: those mark a launch's journal
//  lines as a robot's, and these lines are the evidence.
//

import XCTest

final class LifecycleScenarioUITests: XCTestCase {
    /// A question the imported note answers, so the answer runs a search and the model writes from passages.
    private static let question = "When does the ferry leave after high water?"
    private static let noteName = "Lifecycle tide notes.md"

    override func setUp() {
        continueAfterFailure = true
        say("BEGIN \(name)")
    }

    override func tearDown() {
        say("END \(name)")
    }

    // MARK: - The journal

    private var cachedJournal: URL?

    /// The newest journal under the simulator's app-data folder. An install can move the app's data folder, so
    /// the path is looked up, not passed in.
    private var journal: URL? {
        if let cachedJournal, FileManager.default.fileExists(atPath: cachedJournal.path) { return cachedJournal }
        guard let root = ProcessInfo.processInfo.environment["OI_SIM_APPS"] else { return nil }
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        var newest: (URL, Date)?
        for folder in folders {
            let url = URL(fileURLWithPath: root).appendingPathComponent(folder)
                .appendingPathComponent("Documents/verification_events.jsonl")
            guard
                let changed = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            else { continue }
            if newest == nil || changed > newest!.1 { newest = (url, changed) }
        }
        cachedJournal = newest?.0
        return cachedJournal
    }

    private var canReadTheJournal: Bool { ProcessInfo.processInfo.environment["OI_SIM_APPS"] != nil }

    /// The journal's time format: UTC with milliseconds, so two stamps compare as text.
    private func stamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func events(since: String) -> [[String: Any]] {
        guard let journal, let text = try? String(contentsOf: journal, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let time = object["t"] as? String, time > since
            else { return nil }
            return object
        }
    }

    /// Waits for an event after `since`. `field` narrows it to a value in the event's fields ("to": "complete").
    /// With no journal to read it waits `fallback` seconds and reports nothing seen.
    @discardableResult
    private func waitFor(
        _ name: String, since: String, field: (String, String)? = nil, timeout: TimeInterval, fallback: TimeInterval
    ) -> [String: Any]? {
        guard canReadTheJournal else {
            Thread.sleep(forTimeInterval: fallback)
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let match = events(since: since).first { event in
                guard event["e"] as? String == name else { return false }
                guard let field else { return true }
                return (event["f"] as? [String: Any])?[field.0].map { "\($0)" } == field.1
            }
            if let match { return match }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }

    private func say(_ text: String) {
        print("[Lifecycle] \(stamp()) \(text)")
    }

    // MARK: - Driving the app

    @MainActor
    private func launch(_ arguments: [String] = [], firstRun: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-showSiliconHUD", "NO"] + arguments
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK"] where springboard.buttons[name].waitForExistence(timeout: firstRun ? 4 : 1) {
            springboard.buttons[name].tap()
            break
        }
        // The welcome screen shows whenever the open library is empty; its Skip is labelled "Skip onboarding".
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Skip'")).firstMatch
        if skip.waitForExistence(timeout: firstRun ? 12 : 4) {
            skip.tap()
            sleep(2)
        }
        clearTheScreen(app)
        return app
    }

    /// Closes what can sit over the chat: What's New, the rating request, a tip.
    @MainActor
    private func clearTheScreen(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            var closed = false
            for host in [app, springboard] {
                for label in ["Not Now", "Close", "Continue", "Got It"] where host.buttons[label].exists {
                    host.buttons[label].firstMatch.tap()
                    closed = true
                    sleep(1)
                }
            }
            if !closed { break }
        }
    }

    @MainActor
    private func openChat(_ app: XCUIApplication) {
        let chat = app.buttons["Chat"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 30), "no Chat tab")
        chat.tap()
        sleep(2)
        clearTheScreen(app)
    }

    /// Types the question and sends it. Returns the time just before the send, for the journal waits.
    @MainActor
    private func ask(in app: XCUIApplication) -> String {
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) { field = app.textFields.firstMatch }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no question field")
        field.tap()
        field.typeText(Self.question)
        let asked = stamp()
        // The send button carries its symbol's name. A tip over the composer can take the first tap.
        let send = app.buttons["arrow.up"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no send button beside the field")
        for _ in 0..<3 {
            send.tap()
            sleep(2)
            let value = (field.value as? String) ?? ""
            if !value.contains(String(Self.question.prefix(12))) { break }
        }
        say("asked")
        return asked
    }

    /// Asks, and waits until the journal says the answer has started: the moment to leave.
    @MainActor
    private func askAndWaitForTheStart(in app: XCUIApplication) -> String {
        let asked = ask(in: app)
        let started = waitFor("answer.start", since: asked, timeout: 60, fallback: 4)
        say(started == nil ? "no answer.start seen in 60 s" : "answer started")
        sleep(2)
        return asked
    }

    private func waitForTheAnswer(since: String, timeout: TimeInterval = 300) {
        let done = waitFor("answer.done", since: since, timeout: timeout, fallback: 120)
        let outcome = done?["o"] as? String ?? "none"
        say("answer.done seen: \(done != nil), outcome \(outcome)")
    }

    private func lockThePhone() -> Bool {
        let selector = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: selector) else { return false }
        XCUIDevice.shared.perform(selector)
        return true
    }

    @MainActor
    private func unlockThePhone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(1)
        springboard.swipeUp()
        sleep(1)
    }

    // MARK: - Scenarios

    /// A new install: first launch, then a second one. The journal shows whether search setup ran once.
    @MainActor
    func test1FirstLaunchAfterInstall() {
        let begun = stamp()
        var app = launch(firstRun: true)
        let first = waitFor("launch.chatUsable", since: begun, timeout: 120, fallback: 45)
        say("first launch usable: \(first != nil)")
        openChat(app)
        // The search models' first load, which a second launch must not repeat in front of the person.
        let loaded = waitFor("reranker.load", since: begun, timeout: 120, fallback: 30)
        say("search models loaded: \(loaded != nil)")
        sleep(3)
        app.terminate()
        sleep(3)
        let again = stamp()
        app = launch()
        let second = waitFor("launch.chatUsable", since: again, timeout: 90, fallback: 30)
        say("second launch usable: \(second != nil)")
        openChat(app)
        waitFor("reranker.load", since: again, timeout: 60, fallback: 15)
        sleep(3)
    }

    /// Leave while a file is being imported, stay away past the point where the system suspends the app, and
    /// come back. The file reaches the app through the watched-folder hook (`--uitest-watch-folder`,
    /// `UITestSupport`), which starts two seconds after launch. The answers below are asked about this note.
    @MainActor
    func test2LeaveDuringAnImport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "oi-lifecycle-import", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let facts =
            "The tide table at the north pier lists high water at 6:14 and low water at 12:31. "
            + "The ferry leaves eleven minutes after each high water, from the east ramp.\n\n"
        let filler = (1...6000).map {
            "Entry \($0). The harbour log for berth \($0 % 17 + 1) records a mooring check, a rope count of \($0 * 3) and no faults.\n\n"
        }.joined()
        let body = "# Lifecycle tide notes\n\n" + facts + filler
        try body.write(to: folder.appendingPathComponent(Self.noteName), atomically: true, encoding: .utf8)
        say("wrote a \(body.utf8.count / 1024) KB note")

        let begun = stamp()
        let app = launch(["--uitest-watch-folder", folder.path])
        let started = waitFor("import.stage", since: begun, timeout: 90, fallback: 8)
        say("import started: \(started != nil)")
        XCUIDevice.shared.press(.home)
        say("left for the Home Screen")
        sleep(45)
        app.activate()
        say("came back")
        let complete = waitFor("import.stage", since: begun, field: ("to", "complete"), timeout: 420, fallback: 150)
        say("import complete: \(complete != nil)")
        sleep(5)
    }

    /// The baseline, and the model's warm-up: an answer with the app in front the whole time. A newly made
    /// simulator reports the model as not ready for about a minute, so a failed answer is asked again.
    @MainActor
    func test3AnswerInFront() {
        let app = launch()
        openChat(app)
        for attempt in 1...3 {
            let asked = ask(in: app)
            let done = waitFor("answer.done", since: asked, timeout: 300, fallback: 120)
            let outcome = done?["o"] as? String ?? "none"
            say("attempt \(attempt): answer.done outcome \(outcome)")
            if outcome == "ok" || !canReadTheJournal { break }
            sleep(45)
        }
        sleep(3)
    }

    /// Leave for the Home Screen while the answer is being written, stay away past the point where the system
    /// suspends the app, and come back.
    @MainActor
    func test4LeaveDuringAnAnswer() {
        let app = launch()
        openChat(app)
        let asked = askAndWaitForTheStart(in: app)
        XCUIDevice.shared.press(.home)
        say("left for the Home Screen")
        sleep(45)
        app.activate()
        say("came back")
        waitForTheAnswer(since: asked)
        sleep(5)
    }

    /// Lock the phone while the answer is being written, then unlock and come back.
    @MainActor
    func test5LockDuringAnAnswer() throws {
        let app = launch()
        openChat(app)
        let asked = askAndWaitForTheStart(in: app)
        guard lockThePhone() else { throw XCTSkip("this XCUIDevice has no lock button to press") }
        say("locked")
        sleep(30)
        unlockThePhone()
        app.activate()
        say("unlocked and came back")
        waitForTheAnswer(since: asked)
        sleep(5)
    }

    /// End the app while the answer is being written, and open it again: the question must not be lost.
    @MainActor
    func test6EndTheAppDuringAnAnswer() {
        var app = launch()
        openChat(app)
        let asked = askAndWaitForTheStart(in: app)
        app.terminate()
        say("ended the app")
        sleep(4)
        let reopened = stamp()
        app = launch()
        say("opened it again")
        let chat = app.buttons["Chat"].firstMatch
        if chat.waitForExistence(timeout: 30) { chat.tap() }
        // Either the reopened app shows the answer it had written, or it asks again and finishes.
        let restored = waitFor("answer.restoredWritten", since: reopened, timeout: 20, fallback: 10)
        if restored == nil { waitForTheAnswer(since: asked, timeout: 240) }
        let onScreen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "ferry leave")).count
        say("answer restored: \(restored != nil); question still on screen: \(onScreen > 0)")
        sleep(5)
    }
}

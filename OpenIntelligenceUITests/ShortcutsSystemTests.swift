//
//  ShortcutsSystemTests.swift
//  OpenIntelligenceUITests
//
//  Siri and Shortcuts actions run the way the system runs them (5.7). Apple's AppIntentsTesting sends
//  each action, by name, to the running app through the App Intents infrastructure, so this covers what
//  the unit suite cannot: an action's own `perform()` with the context the system gives it. The app is
//  launched with a stand-in model (`UITestSupport`), since the iOS Simulator has none.
//
//  Nothing here relies on a search's similarity floor. A library built in the iOS Simulator holds
//  all-zero vectors, and a note alone in its library gets no keyword boost, so "Find Passages" and
//  "Check a Claim" find nothing in it there (measured 2026-10-14) while they do on a device.
//  Superseded 2026-10-19: that was measured before 67977e4 (2026-10-14, 22:07), which gives a Simulator
//  library real vectors from the CPU embedder; whether the two find the note in the Simulator since then
//  has not been tried.
//

import AppIntentsTesting
import XCTest

final class ShortcutsSystemTests: XCTestCase {
    private static let bundleIdentifier = "Gunndamental.OpenIntelligence"
    private static let notePrefix = "UITest quillberry"
    private static let answer = "The quillberry deposit for the test flat is 4,321 dollars."

    private var definitions: IntentDefinitions!

    override func setUp() async throws {
        continueAfterFailure = false
        let answer = Self.answer
        await MainActor.run {
            let app = XCUIApplication()
            app.launchArguments += ["--uitest-stand-in-model"]
            app.launchEnvironment["UITEST_STAND_IN_ANSWER"] = answer
            app.launch()
        }
        definitions = IntentDefinitions(bundleIdentifier: Self.bundleIdentifier)
        try await definitions.intents["UITestRemoveDocumentsIntent"].makeIntent(namePrefix: Self.notePrefix).run()
    }

    override func tearDown() async throws {
        if let definitions {
            try await definitions.intents["UITestRemoveDocumentsIntent"].makeIntent(namePrefix: Self.notePrefix).run()
        }
    }

    /// Adds a note through "Add to Library" and waits, at most two minutes, until the document lookup
    /// Siri and Shortcuts use to find a document by name lists it with its passages. Returns the note's
    /// name and its item.
    private func addNote() async throws -> (name: String, item: AnyAppEntity) {
        let name = "\(Self.notePrefix) \(UUID().uuidString.prefix(8))"
        let added = try await definitions.intents["AddToLibraryIntent"]
            .makeIntent(
                text: "The quillberry deposit for the test flat is 4,321 dollars, paid before moving in.",
                name: name
            )
            .run()
        let names: [String] = try added.value
        XCTAssertEqual(names.count, 1, "Add to Library returned \(names)")

        let documents = definitions.entities["OIDocumentEntity"]
        var lastProblem = "no lookup ran"
        for _ in 0..<120 {
            do {
                if let note = try await documents.entities(matching: name).first {
                    let passages: Int = try note.totalChunks
                    if passages > 0 { return (name, note) }
                    lastProblem = "the note is listed with no passages yet"
                } else {
                    lastProblem = "no document is named \(name) yet"
                }
            } catch {
                lastProblem = "\(error)"
            }
            try await Task.sleep(for: .seconds(1))
        }
        XCTFail("the note was not imported within two minutes: \(lastProblem)")
        throw CancellationError()
    }

    /// "Ask My Documents" itself, which the unit suite cannot call on 27: a long-running action needs
    /// the context the system gives it.
    func testAskMyDocumentsAnswersFromANoteAddedThroughAddToLibrary() async throws {
        _ = try await addNote()
        let asked = try await definitions.intents["QueryDocumentsIntent"]
            .makeIntent(question: "How much is the quillberry deposit?")
            .run()
        let text: String = try asked.value.text
        XCTAssertTrue(text.contains("4,321"), text)
        let passages: [AnyTransientAppEntity] = try asked.value.passages
        XCTAssertFalse(passages.isEmpty, "the answer came back with no passages")
    }

    /// "Open Document" with the item the lookup returned: the app shows that document.
    func testOpenDocumentShowsTheNoteFoundByName() async throws {
        let (name, note) = try await addNote()
        try await definitions.intents["OpenDocumentIntent"].makeIntent(target: note).run()
        let shown = await MainActor.run {
            XCUIApplication()
                .descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", name))
                .firstMatch
                .waitForExistence(timeout: 20)
        }
        XCTAssertTrue(shown, "the app did not show \(name)")
    }

    // MARK: - Roadmap checks, 2026-10-19

    /// Waits up to `seconds` for an element of the app whose label contains `text`.
    @MainActor
    private func appShows(_ text: String, within seconds: TimeInterval = 20) -> Bool {
        XCUIApplication().descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
            .waitForExistence(timeout: seconds)
    }

    /// "Find Passages" through the system (roadmap row 3f449a74d54f818fa388ed8c60f3d280): the note's passage comes
    /// back as an item whose text the next step can read, within a few seconds.
    func testFindPassagesHandsBackTheNotesPassageQuickly() async throws {
        _ = try await addNote()
        let started = Date()
        let found = try await definitions.intents["SearchPassagesIntent"]
            .makeIntent(query: "quillberry deposit", limit: 5)
            .run()
        let took = Date().timeIntervalSince(started)
        let passages: [AnyTransientAppEntity] = try found.value
        let texts: [String] = try passages.map { passage -> String in try passage.text }
        print("FIND-PASSAGES \(String(format: "%.2f", took)) s, \(passages.count) passage(s)")
        XCTAssertTrue(texts.contains { $0.contains("4,321") }, "\(texts)")
        XCTAssertLessThan(took, 5, "Find Passages took \(took) s")
    }

    /// The answer card's Think Deeper button (roadmap row 3f449a74d54f8193a750d1099b83a8c5): the chat asks the
    /// question again, in Deep Think.
    func testThinkDeeperAsksTheQuestionAgainInDeepThink() async throws {
        let question = "How much is the quillberry deposit in Deep Think \(UUID().uuidString.prefix(4))?"
        try await definitions.intents["ThinkDeeperIntent"].makeIntent(question: question).run()
        let asked = await appShows(question)
        let inDeepThink = await appShows("Deep Think", within: 5)
        XCTAssertTrue(asked, "the chat does not show the question")
        XCTAssertTrue(inDeepThink, "the chat is not in Deep Think")
    }

    /// The answer card's Ask a Follow-up button (roadmap row 3f449a74d54f8193a750d1099b83a8c5): a new conversation
    /// that starts with the card's question and answer.
    func testAskAFollowUpStartsAConversationWithTheAnswer() async throws {
        let tag = UUID().uuidString.prefix(6)
        let question = "What is the quillberry deposit \(tag)?"
        let answer = "The quillberry deposit is 4,321 dollars \(tag)."
        try await definitions.intents["AskFollowUpIntent"].makeIntent(question: question, answer: answer).run()
        let asked = await appShows(question)
        let answered = await appShows(answer, within: 5)
        XCTAssertTrue(asked, "the conversation does not start with the question")
        XCTAssertTrue(answered, "the conversation does not hold the answer")
    }

    /// A document's page tells the system which document is on screen (roadmap row
    /// 38049a74d54f81dcae32fce70ba7751b): the page's view annotations name the note.
    func testTheDocumentPageNamesItsDocumentToTheSystem() async throws {
        let (name, note) = try await addNote()
        try await definitions.intents["OpenDocumentIntent"].makeIntent(target: note).run()
        let shown = await appShows(name)
        XCTAssertTrue(shown, "the app did not show \(name)")
        try await Task.sleep(for: .seconds(2))
        let annotations = try await definitions.entities["OIDocumentEntity"].viewAnnotations()
        print("VIEW-ANNOTATIONS \(annotations.count): \(annotations.map { "\($0.entity.identifier) selected=\($0.isSelected)" })")
        XCTAssertTrue(annotations.contains { $0.entity == note }, "no annotation names the open note")
    }

    /// Spotlight finds the note by a word in it (roadmap row 3f449a74d54f81beadd4f8e3dcaf38f5), as the system's own
    /// search reads the app's index. Waits up to a minute for the index.
    func testSpotlightFindsTheNoteByItsName() async throws {
        let (name, note) = try await addNote()
        let documents = definitions.entities["OIDocumentEntity"]
        var found: [AnyAppEntity] = []
        for _ in 0..<30 {
            found = try await documents.spotlightQuery(name)
            if found.contains(note) { break }
            try await Task.sleep(for: .seconds(2))
        }
        print("SPOTLIGHT \(found.count) result(s) for \(name)")
        XCTAssertTrue(found.contains(note), "Spotlight did not return \(name)")
    }

    /// "Delete Documents" with the app open (roadmap row 3f449a74d54f812f8a5aef4f34c9aa97): it asks first, the
    /// library shows Undo, and Undo puts the note back.
    func testDeleteDocumentsWithTheAppOpenCanBeUndone() async throws {
        let (name, note) = try await addNote()
        // The Undo bar is the Documents screen's.
        let onDocuments = await MainActor.run { () -> Bool in
            let tab = XCUIApplication().buttons.matching(NSPredicate(format: "label == 'Documents'")).firstMatch
            guard tab.waitForExistence(timeout: 10) else { return false }
            tab.tap()
            return true
        }
        XCTAssertTrue(onDocuments, "no Documents tab")
        do {
            try await definitions.intents["DeleteDocumentsIntent"].makeIntent(entities: [note]).run()
        } catch {
            print("DELETE-DOCUMENTS run threw: \(error)")
            throw error
        }
        let offered = await MainActor.run { () -> Bool in
            let undo = XCUIApplication().buttons["Undo"].firstMatch
            guard undo.waitForExistence(timeout: 5) else { return false }
            undo.tap()
            return true
        }
        print("DELETE-DOCUMENTS Undo offered: \(offered)")
        XCTAssertTrue(offered, "the library offered no Undo")
        guard offered else { return }
        try await Task.sleep(for: .seconds(3))
        let back = try await definitions.entities["OIDocumentEntity"].entities(matching: name)
        XCTAssertTrue(back.contains(note), "Undo did not put \(name) back")
    }
}

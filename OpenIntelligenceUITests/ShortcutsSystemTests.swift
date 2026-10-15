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
}

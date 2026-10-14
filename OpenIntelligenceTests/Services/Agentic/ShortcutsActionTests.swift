//
//  ShortcutsActionTests.swift
//  OpenIntelligenceTests
//
//  The first tests that run the actions themselves (5.7): "Add to Library" stores a note and the
//  app's engine imports it, and "Ask My Documents" answers from it. Each action's own `perform()`
//  runs in the app the suite is hosted in. Apple's AppIntentsTesting runs actions through the
//  system instead, and needs a UI-testing target. The iOS Simulator has no language model, so the
//  question runs on an engine with a stand-in model (`AskActionRunner.makeEngine`).
//

import AppIntents
import PDFKit
import XCTest

@testable import OpenIntelligence

@MainActor
final class ShortcutsActionTests: XCTestCase {
    /// Answers with a fixed sentence, so the rest of the question's path (retrieval, the checks,
    /// the answer item and the card) runs as it does with Apple's model.
    private final class StandInModel: LLMService {
        var toolHandler: RAGToolHandler?
        let answer: String
        init(answer: String) { self.answer = answer }
        var isAvailable: Bool { true }
        var modelName: String { "Stand-in" }
        func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
            LLMResponse(
                text: answer, tokensGenerated: 12, timeToFirstToken: 0.01, totalTime: 0.01, modelName: modelName,
                toolCallsMade: 0)
        }
    }

    /// The value an action's result carries.
    private func value(of result: Any) -> Any? {
        guard let held = Mirror(reflecting: result).children.first(where: { $0.label == "value" })?.value else {
            return nil
        }
        let optional = Mirror(reflecting: held)
        return optional.displayStyle == .optional ? optional.children.first?.value : held
    }

    /// Adds a note through "Add to Library" and waits, at most a minute, for the app's engine to
    /// import it. The note is deleted when the test ends.
    private func addNote(_ text: String) async throws -> Document {
        let add = AddToLibraryIntent()
        add.text = text
        add.name = "Shortcuts test \(UUID().uuidString.prefix(8))"
        let added = try await add.perform()
        let names = try XCTUnwrap(value(of: added) as? [String], "Add to Library returned no names")
        XCTAssertEqual(names.count, 1)
        let name = try XCTUnwrap(names.first)
        let engine = IntentSupport.engine()
        for _ in 0..<600 {
            if let document = engine.documents.first(where: { $0.filename == name }) {
                addTeardownBlock { @MainActor in try? await engine.removeDocument(document) }
                return document
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try XCTUnwrap(nil as Document?, "\(name) was not imported within a minute")
    }

    func testAddToLibraryStoresTheTextAndTheAppImportsIt() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let document = try await addNote(
            "The marlowe gate code for the test flat is 4417, and it changes every spring.")
        XCTAssertGreaterThan(document.totalChunks, 0, "the note was imported with no passages")
    }

    /// "Ask My Documents" inside its system wrapper: the action runs its question through
    /// `AskActionRunner.ask` and makes its card with `card`, and those run here as they do for the
    /// action. Its `perform()` itself, a long-running action on 27, needs the context the system
    /// gives an action it runs, and called in a test it fails with "No IntentContext available"
    /// (measured 2026-10-14).
    func testAskAnswersFromANoteAddedThroughAddToLibrary() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let document = try await addNote(
            "The zephyrine deposit for the test flat is 1,234 dollars, paid before moving in.")
        let model = StandInModel(answer: "The zephyrine deposit for the test flat is 1,234 dollars.")
        AskActionRunner.makeEngine = { RAGService(llmService: model) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }

        let question = "How much is the zephyrine deposit?"
        let outcome = try await AskActionRunner.ask(question, mode: .standard, topK: 3)
        XCTAssertTrue(outcome.answer.text.contains("1,234"), outcome.answer.text)
        XCTAssertTrue(
            outcome.answer.passages.contains { $0.documentName == document.filename },
            "the answer's passages are from \(outcome.answer.passages.map(\.documentName))")
        let card = AskActionRunner.card(question: question, outcome: outcome)
        XCTAssertEqual(card.sources.first?.id, document.id, "the card's first button is not the note")
        XCTAssertTrue(card.offersThinkDeeper, "a Standard answer from the whole library offers Think Deeper")
    }

    /// "Export Conversation" hands a saved conversation back as a file the shortcut can pass on.
    func testExportConversationHandsBackASavedConversationAsAPDF() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let libraryId = IntentSupport.engine().containerService.activeContainerId
        let thread = EvidenceThread(
            containerId: libraryId, title: "Export test \(UUID().uuidString.prefix(8))",
            messages: [
                ChatMessage(role: .user, content: "When is the zephyrine deposit due?"),
                ChatMessage(role: .assistant, content: "Before moving in."),
            ])
        try EvidenceThreadStore().saveThread(thread)
        addTeardownBlock { @MainActor in try? EvidenceThreadStore().deleteThread(id: thread.id, containerId: libraryId) }

        let export = ExportConversationIntent()
        export.conversation = OIThreadEntity(thread, libraryName: nil)
        export.format = .pdf
        let exported = try await export.perform()
        let file = try XCTUnwrap(value(of: exported) as? IntentFile, "Export Conversation returned no file")
        XCTAssertTrue(file.filename.hasSuffix(".pdf"), file.filename)
        let text = try XCTUnwrap(PDFDocument(data: file.data)?.string, "the file is not a PDF")
        XCTAssertTrue(text.contains("When is the zephyrine deposit due?"), text)
        XCTAssertTrue(text.contains("Before moving in."), text)
    }
}

//
//  ShortcutsActionTests.swift
//  OpenIntelligenceTests
//
//  The first tests that run the actions themselves (5.7), in the app the suite is hosted in: "Add to
//  Library" and "Export Conversation" through their own `perform()`, and "Ask My Documents" through
//  the runner its `perform()` calls (`AskActionRunner`), since its `perform()` needs the context the
//  system gives an action it runs. Apple's AppIntentsTesting runs actions through the system, and
//  needs a UI-testing target. The iOS Simulator has no language model, so the question runs on an
//  engine with a stand-in model (`AskActionRunner.makeEngine`).
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
        XCTAssertTrue(card.offersFollowUp)
        XCTAssertEqual(
            card.library?.id, IntentSupport.engine().containerService.activeContainerId,
            "the buttons open the chat on the library the question ran in")
    }

    /// A question asked again after the document that answered it is deleted. Through 5.6 a search kept in the
    /// query cache was reused for the same question whatever the libraries held, so the deleted note's passages came
    /// back, named "Unknown". Since 5.7 a cached search's key names every library's documents, so the second ask
    /// searches again and finds none of them.
    func testAQuestionAskedAgainAfterADeleteGetsNoPassageOfTheDeletedNote() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let document = try await addNote(
            "The brambleton parking permit for the test flat costs 85 dollars a year, paid in March.")
        // A second note stays, so the library is not empty when the question is asked again.
        _ = try await addNote("The recycling for the test flat goes out on Thursday mornings before seven.")
        let model = StandInModel(answer: "The brambleton parking permit for the test flat costs 85 dollars a year.")
        AskActionRunner.makeEngine = { RAGService(llmService: model) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }

        let question = "How much is the brambleton parking permit?"
        let first = try await AskActionRunner.ask(question, mode: .standard, topK: 3)
        XCTAssertTrue(
            first.answer.passages.contains { $0.documentName == document.filename },
            "the first answer's passages are from \(first.answer.passages.map(\.documentName))")

        try await IntentSupport.engine().removeDocument(document)
        let second = try await AskActionRunner.ask(question, mode: .standard, topK: 3)
        XCTAssertFalse(
            second.answer.passages.contains { $0.documentName == document.filename || $0.documentName == "Unknown" },
            "the second answer still has the deleted note: \(second.answer.passages.map(\.documentName))")
        XCTAssertFalse(
            second.answer.passages.contains { $0.text.contains("brambleton") },
            "a passage of the deleted note came back")
    }

    /// A passage of no document is not used in an answer (5.7, `passagesFromKnownDocuments` and
    /// `chunksOfListedDocuments`). Such passages were left by a deleted document or an import that stopped before
    /// recording its document, and answers cited them as "Unknown". The planted one is an overview, as
    /// `DocumentSummaryService` writes it, and it is asked about three ways: a Standard lookup, a Standard overview
    /// question, and Deep Think, which searches through `executeFullRetrievalPipeline`.
    func testAPassageOfNoDocumentIsNotUsedInAnAnswer() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        _ = try await addNote("The recycling for the test flat goes out on Thursday mornings before seven.")
        let engine = IntentSupport.engine()
        let library = try XCTUnwrap(engine.containerService.activeContainerId)
        let container = engine.containerService.containers.first { $0.id == library }
        let embedder = EmbeddingService.forProvider(
            id: container?.embeddingProviderId ?? "coreml_sentence_embedding",
            targetDimension: container?.embeddingDim ?? 384, allowFallback: true)
        let orphanText =
            "[Document Summary: deleted note] The thornfield parking permit for the test flat costs 999 dollars a year."
        let orphan = DocumentChunk(
            documentId: UUID(), content: orphanText, embedding: try await embedder.generateEmbedding(for: orphanText),
            metadata: ChunkMetadata(
                chunkIndex: -1, endPosition: orphanText.count, sectionTitle: "Document Summary", semanticDensity: 1.0,
                hasNumericData: true, wordCount: orphanText.split(separator: " ").count,
                characterCount: orphanText.count, abstractionLevel: .documentSummary))
        let db = try await engine.dbForContainer(library)
        try await db.storeBatch(chunks: [orphan])
        try await db.persist()
        addTeardownBlock { @MainActor in
            try? await db.deleteChunks(forDocument: orphan.documentId)
            try? await db.persist()
        }
        let planted = try await db.chunks(forDocument: orphan.documentId)
        XCTAssertEqual(planted.count, 1, "the passage was not stored, so this test would show nothing")

        let model = StandInModel(answer: "The recycling for the test flat goes out on Thursday mornings.")
        AskActionRunner.makeEngine = { RAGService(llmService: model) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }
        for (question, mode) in [
            ("How much is the thornfield parking permit?", OIAnswerMode.standard),
            ("Give me an overview of the thornfield parking permit note.", .standard),
            ("How much is the thornfield parking permit?", .deepThink),
        ] {
            let outcome = try await AskActionRunner.ask(question, mode: mode, topK: 3)
            XCTAssertFalse(
                outcome.answer.passages.contains { $0.text.contains("thornfield") },
                "\(mode) used the passage of no document for \"\(question)\": \(outcome.answer.passages.map(\.documentName))")
        }
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

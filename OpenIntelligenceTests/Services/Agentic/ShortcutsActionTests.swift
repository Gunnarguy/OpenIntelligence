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
import UniformTypeIdentifiers
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

    // MARK: - Roadmap checks, 2026-10-19

    /// Answers after a wait long enough for the system to stop the question first.
    private final class SlowModel: LLMService {
        var toolHandler: RAGToolHandler?
        var isAvailable: Bool { true }
        var modelName: String { "Slow stand-in" }
        func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
            try await Task.sleep(for: .seconds(30))
            return LLMResponse(
                text: "Too late.", tokensGenerated: 2, timeToFirstToken: 30, totalTime: 30, modelName: modelName,
                toolCallsMade: 0)
        }
    }

    /// Puts the app on a paid plan for the rest of the test: the free plan allows one library and five documents.
    private func onAPaidPlan() {
        let key = "entitlement.activeTier"
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: key)
        addTeardownBlock { UserDefaults.standard.set(saved, forKey: key) }
    }

    /// Waits, at most three minutes, until `names` are all documents of `library` with passages.
    private func imported(_ names: [String], in library: UUID) async throws -> [Document] {
        let engine = IntentSupport.engine()
        var found: [Document] = []
        for _ in 0..<1_800 {
            found = engine.documents.filter {
                $0.containerId == library && names.contains($0.filename) && $0.totalChunks > 0
            }
            if found.count == names.count { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        return found
    }

    /// "Ask About a Document" keeps to the document it names (roadmap row 3f449a74d54f81c0963bc125ccabbb33): two
    /// notes in one library disagree about the same deposit, and asked about each, every passage the answer rests on
    /// is that note's. The action asks the same way (`AskDocumentIntent.perform`).
    func testAskAboutADocumentRestsOnlyOnThatDocument() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let first = try await addNote("The larkspur deposit for the test flat is 500 dollars, paid before moving in.")
        let second = try await addNote("The larkspur deposit for the test flat is 900 dollars, paid before moving in.")
        let model = StandInModel(answer: "The larkspur deposit is in the note.")
        AskActionRunner.makeEngine = { RAGService(llmService: model) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }

        for (named, other) in [(first, second), (second, first)] {
            let outcome = try await AskActionRunner.ask(
                "How much is the larkspur deposit?", mode: .standard, topK: 6, documentIds: [named.id])
            let sources = outcome.response.retrievedChunks.map(\.chunk.documentId)
            XCTAssertFalse(sources.isEmpty, "the question about \(named.filename) rested on no passage")
            XCTAssertTrue(
                sources.allSatisfy { $0 == named.id },
                "asked about \(named.filename), the answer rested on \(Set(sources).count) document(s)")
            XCTAssertFalse(sources.contains(other.id), "a passage of \(other.filename) was used")
        }
    }

    /// A question the system stops ends within seconds and says which stop it was (roadmap row
    /// 3f449a74d54f812aadb2d2db3578b35a). The model here would take 30 seconds; the stop comes after half a second,
    /// as the system's own does through `AskControl`.
    func testAStoppedQuestionEndsAndSaysWhy() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        _ = try await addNote("The corrigan gate in the test flat's yard is painted green and locks at ten.")
        AskActionRunner.makeEngine = { RAGService(llmService: SlowModel()) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }

        for (reason, said) in [
            ("cancelled", "The question was stopped."),
            ("timeout", "The question was stopped because it ran too long in the background."),
        ] {
            let control = AskControl(progress: Progress())
            let started = Date()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                control.cancel(because: reason)
            }
            do {
                _ = try await AskActionRunner.ask(
                    "Summarize what the note says about the corrigan gate.", mode: .standard, control: control)
                XCTFail("a stopped question (\(reason)) handed back an answer")
            } catch {
                XCTAssertEqual((error as? OIIntentError)?.message, said, "\(error)")
            }
            let took = Date().timeIntervalSince(started)
            XCTAssertLessThan(took, 10, "stopped for \(reason), the question went on for \(took) s")
            print("STOPPED (\(reason)) after \(String(format: "%.2f", took)) s")
        }
    }

    /// The answer mode an ask action is given is the mode the answer runs in (roadmap row
    /// 3f449a74d54f8191a690c82195d5fbc9), as the engine records it on the answer.
    func testEachAnswerModeRunsInTheModeChosen() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        onAPaidPlan()
        _ = try await addNote("The tamsin bike store code for the test flat is 2468, changed every autumn.")
        let model = StandInModel(answer: "The tamsin bike store code for the test flat is 2468.")
        AskActionRunner.makeEngine = { RAGService(llmService: model) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }

        for (mode, name) in [(OIAnswerMode.standard, "Standard"), (.deepThink, "Deep Think"), (.maximum, "Maximum")] {
            let outcome = try await AskActionRunner.ask("What is the tamsin bike store code?", mode: mode, topK: 3)
            XCTAssertEqual(outcome.response.metadata.qualityModeName, name, "asked in \(mode)")
            XCTAssertEqual(outcome.answer.mode, mode)
        }
    }

    /// "Create Library", then "Add to Library" naming no library, then "Set Active Library" back, each through its
    /// own `perform()` (roadmap row 3f449a74d54f8193bd4be75cb1c301c1): the new library becomes the active one, the
    /// note goes into it, and the switch back takes.
    func testCreateLibraryMakesItActiveAndAddToLibraryFillsIt() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        onAPaidPlan()
        let libraries = IntentSupport.libraries()
        let engine = IntentSupport.engine()
        let before = try XCTUnwrap(libraries.activeContainerId)
        let create = CreateLibraryIntent()
        create.name = "Shortcuts library \(UUID().uuidString.prefix(8))"
        create.makeActive = true
        let createdResult = try await create.perform()
        let created = try XCTUnwrap(value(of: createdResult) as? OILibraryEntity)
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == created.id {
                try? await engine.removeDocument(document)
            }
            libraries.setActive(before)
            libraries.deleteContainer(id: created.id)
        }
        XCTAssertEqual(libraries.activeContainerId, created.id, "the new library is not the active one")

        let document = try await addNote("The fennimore boiler in the test flat was serviced in March and runs on gas.")
        XCTAssertEqual(document.containerId, created.id, "the note went to another library")

        let back = SetActiveLibraryIntent()
        back.library = OILibraryEntityQuery.entity(for: try XCTUnwrap(libraries.containers.first { $0.id == before }))
        _ = try await back.perform()
        XCTAssertEqual(libraries.activeContainerId, before, "Set Active Library did not switch back")
    }

    /// A question to a library with no documents, while another library has some, is answered with a sentence that
    /// says so (roadmap row 3f449a74d54f8129a1baf215e16bf18f), not with passages from elsewhere.
    func testAQuestionToAnEmptyLibrarySaysItHasNoDocuments() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        onAPaidPlan()
        _ = try await addNote("The ashgrove recycling for the test flat goes out on Thursday mornings.")
        let libraries = IntentSupport.libraries()
        let empty = try libraries.createContainer(name: "Empty library \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in libraries.deleteContainer(id: empty.id) }
        let model = StandInModel(answer: "The stand-in model should not have been asked.")
        AskActionRunner.makeEngine = { RAGService(llmService: model) }
        addTeardownBlock { @MainActor in AskActionRunner.makeEngine = { RAGService() } }

        let outcome = try await AskActionRunner.ask(
            "When does the ashgrove recycling go out?", mode: .standard, libraryId: empty.id)
        XCTAssertTrue(outcome.answer.text.contains("This library has no documents yet."), outcome.answer.text)
        XCTAssertTrue(outcome.answer.passages.isEmpty, "the answer used \(outcome.answer.passages.count) passage(s)")
    }

    /// One "Add to Library" run with a PDF, a web address and a paragraph, into a library it names (roadmap row
    /// 3f449a74d54f815ab796eb064a525ed3): three documents with passages in that library, and the page is its text.
    /// Needs the network.
    func testAddToLibraryTakesAFileALinkAndTextInOneRun() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        onAPaidPlan()
        let engine = IntentSupport.engine()
        let library = try engine.containerService.createContainer(name: "Add three \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == library.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: library.id)
        }
        let pdf = try IngestionFixtureFactory().textLayerPDF()
        let add = AddToLibraryIntent()
        add.file = IntentFile(data: try Data(contentsOf: pdf), filename: "Shortcuts service table.pdf", type: .pdf)
        add.link = URL(string: "https://en.wikipedia.org/wiki/Okapi_BM25")
        add.text = "The wexford storage cage for the test flat is number 12, on the lower level."
        add.name = "Shortcuts note \(UUID().uuidString.prefix(8))"
        add.library = OILibraryEntityQuery.entity(for: library)
        let added = try await add.perform()
        let names = try XCTUnwrap(value(of: added) as? [String], "Add to Library returned no names")
        XCTAssertEqual(names.count, 3, "\(names)")

        let documents = try await imported(names, in: library.id)
        XCTAssertEqual(Set(documents.map(\.filename)), Set(names), "imported with passages: \(documents.map(\.filename))")
        let page = try XCTUnwrap(documents.first { $0.filename.lowercased().contains("bm25") }, "no page among \(names)")
        let db = try await engine.dbForContainer(library.id)
        let text = try await db.chunks(forDocument: page.id).map(\.content).joined(separator: " ")
        XCTAssertTrue(text.contains("ranking function"), String(text.prefix(400)))
    }

    /// "Save a Web Page" downloads the page and imports its text into the active library (roadmap row
    /// 3f449a74d54f8152bc4af3b9baa7d8d4). Needs the network.
    func testSaveAWebPageImportsTheArticlesText() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        onAPaidPlan()
        let engine = IntentSupport.engine()
        let active = try XCTUnwrap(engine.containerService.activeContainerId)
        let save = IngestURLIntent()
        save.url = try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/Inverted_index"))
        let saved = try await save.perform()
        let name = try XCTUnwrap(value(of: saved) as? String, "Save a Web Page returned no name")
        let documents = try await imported([name], in: active)
        let page = try XCTUnwrap(documents.first, "\(name) was not imported with passages within three minutes")
        addTeardownBlock { @MainActor in try? await engine.removeDocument(page) }
        let db = try await engine.dbForContainer(active)
        let text = try await db.chunks(forDocument: page.id).map(\.content).joined(separator: " ")
        XCTAssertTrue(text.lowercased().contains("inverted index"), String(text.prefix(400)))
        XCTAssertFalse(text.contains("<div"), "the page was stored as markup")
    }

    /// "Check a Claim" on a note: a true sentence is supported, by the note's passage, and an untrue one is not
    /// (roadmap row 3f449a74d54f8131adddfbbf329b0179).
    func testCheckAClaimHoldsUpATrueSentenceAndNotAnUntrueOne() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let document = try await addNote("The pelham deposit for the test flat is 1,850 dollars, paid before moving in.")
        let check = CheckClaimIntent()

        check.claim = "The pelham deposit for the test flat is 1,850 dollars."
        let held = value(of: try await check.perform()) as? String
        XCTAssertEqual(held, "Supported")
        let engine = IntentSupport.engine()
        let chunks = Array(try await engine.searchDocumentsRaw(query: check.claim, topK: 6).prefix(6))
        let outcome = await ClaimCheck.check(check.claim, against: chunks)
        XCTAssertTrue(outcome.source?.hasPrefix(document.filename) ?? false, "checked against \(outcome.source ?? "nothing")")

        check.claim = "The pelham flat has a rooftop swimming pool that opens in May."
        let untrue = value(of: try await check.perform()) as? String
        print("CHECK-A-CLAIM untrue sentence: \(untrue ?? "nil")")
        XCTAssertTrue(untrue == "Not supported" || untrue == "Not found", untrue ?? "nil")
    }
}

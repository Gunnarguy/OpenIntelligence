//
//  RAGAppIntents.swift
//  OpenIntelligence
//
//  App Intents for Siri and Shortcuts integration
//  Enables voice-based RAG queries and document management
//
//  Created by GitHub Copilot on 10/15/25.
//

import AppIntents
import Foundation
import SwiftUI

private struct DocumentImportStatusSnapshot: Sendable {
    let activeCount: Int
    let currentFilename: String
    let currentStage: String
    let queuedFilenames: [String]
    let spokenResponse: String
}

// MARK: - What the ask actions share

/// Applies the free plan's daily Maximum allowance to an action, the way the chat applies it.
///
/// The chat counts each Maximum answer through `EntitlementStore.consumeMaximumModeUseIfNeeded`.
/// An action has no entitlement store of its own, so this reads the plan from where the app stores
/// it and uses the same counter (`MaximumModeQuotaStore` on the standard defaults). The allowance
/// is checked before the question and counted only after an answer came back, so a question that
/// fails does not spend one. The app's own remaining-runs display is refreshed the next time the
/// app recalculates it, not at once.
@available(iOS 26.0, macOS 26.0, *)
enum ShortcutsPlanGate {
    private static var isMetered: Bool { EntitlementStore.currentEffectiveTier() == .free }

    /// Throws when the free plan has no Maximum answer left today.
    @MainActor
    static func checkMaximumAvailable() throws {
        guard isMetered else { return }
        let limit = QuotaPolicy.freeMaximumModeDailyLimit
        if MaximumModeQuotaStore().currentState(limit: limit).remainingUses <= 0 {
            throw OIIntentError(
                "Today's \(limit) free Maximum answers are used. Choose Standard or Deep Think, or try again tomorrow.")
        }
    }

    /// Counts one Maximum answer.
    @MainActor
    static func countMaximumAnswer() {
        guard isMetered else { return }
        _ = MaximumModeQuotaStore().consumeIfAllowed(limit: QuotaPolicy.freeMaximumModeDailyLimit)
    }
}

/// Runs one question for an action and hands back the answer as an item.
///
/// Every ask action goes through here, so they share a mode, the engine's default generation
/// settings (through 5.6 each action cut its answer at 300 or 400 tokens and set its own
/// temperature), and one way of failing: a thrown error, which stops a shortcut, instead of a
/// successful result that carries an apology.
///
/// The question runs on an engine of its own, as it did through 5.6. An answer generating in the
/// app keeps its engine to itself: a second question on that engine would cancel it. The engine
/// built here does not take the app engine's place (`RAGService.init` registers itself only when
/// no engine is registered).
@available(iOS 26.0, macOS 26.0, *)
enum AskActionRunner {
    struct Outcome {
        let answer: OIAnswerEntity
        let response: RAGResponse
    }

    /// - Parameters:
    ///   - question: what the engine is asked.
    ///   - shownQuestion: what the answer item records as the question, when it differs.
    ///   - documentIds: when set, only these documents' passages are used (`RAGQueryScope`), and
    ///     the question runs in Standard whatever `mode` says: the limit is enforced and checked
    ///     on that path.
    static func ask(
        _ question: String,
        shownAs shownQuestion: String? = nil,
        mode: OIAnswerMode,
        topK: Int = 3,
        libraryId: UUID? = nil,
        documentIds: Set<UUID>? = nil
    ) async throws -> Outcome {
        let wanted = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { throw OIIntentError("There was no question to ask.") }

        let engine = await MainActor.run { RAGService() }
        let (documents, defaultLibraryId) = await MainActor.run {
            (engine.documents, engine.containerService.containers.first?.id)
        }
        guard !documents.isEmpty else {
            throw OIIntentError("There are no documents yet. Add one first.")
        }

        var container = libraryId
        var effectiveMode = mode
        if let documentIds {
            let named = documents.filter { documentIds.contains($0.id) }
            guard named.count == documentIds.count else {
                throw OIIntentError("That document is no longer in your libraries.")
            }
            // A document stored before libraries existed has no library id and lives in the first one.
            let homes = Set(named.compactMap { $0.containerId ?? defaultLibraryId })
            guard homes.count == 1 else {
                throw OIIntentError("Those documents are in different libraries. Choose documents from one library.")
            }
            container = homes.first
            effectiveMode = .standard
        }

        if effectiveMode == .maximum {
            try await MainActor.run { try ShortcutsPlanGate.checkMaximumAvailable() }
        }

        let response: RAGResponse
        do {
            response = try await RAGQueryScope.$documentIds.withValue(documentIds) {
                try await engine.query(
                    wanted, topK: min(max(topK, 1), 12), containerId: container,
                    qualityModeOverride: effectiveMode.qualityMode)
            }
        } catch {
            Log.error("[Shortcuts] Ask failed: \(error.localizedDescription)", category: .pipeline)
            throw OIIntentError("The question could not be answered. \(error.localizedDescription)")
        }

        // The last check on a question that named documents: the answer must rest on their
        // passages and on nothing else. If the engine answered from other passages, or from none,
        // the action fails; it does not hand back an answer that is not what was asked for.
        if let documentIds {
            let sources = response.retrievedChunks.map(\.chunk.documentId)
            guard !sources.isEmpty, sources.allSatisfy(documentIds.contains) else {
                Log.error(
                    "[Shortcuts] Ask refused: \(sources.filter { !documentIds.contains($0) }.count) of \(sources.count) passages were outside the named document(s)",
                    category: .pipeline)
                throw OIIntentError(
                    sources.isEmpty
                        ? "Nothing in the chosen document matched the question."
                        : "The answer could not be kept to the chosen document, so it was not returned.")
            }
        }

        if effectiveMode == .maximum {
            await MainActor.run { ShortcutsPlanGate.countMaximumAnswer() }
        }
        Log.info(
            "[Shortcuts] Ask complete (mode=\(effectiveMode.rawValue), answerChars=\(response.generatedResponse.count), passages=\(response.retrievedChunks.count), scoped=\(documentIds?.count ?? 0))",
            category: .pipeline)
        return Outcome(
            answer: OIAnswerEntity(question: shownQuestion ?? wanted, response: response, mode: effectiveMode),
            response: response)
    }

    /// The answer as Siri speaks it: markdown marks removed, and cut at 500 characters with a note
    /// that the full answer is on screen. The value an action returns is never cut.
    static func spoken(_ text: String) -> String {
        var formatted = text
        formatted = formatted.replacingOccurrences(of: "**", with: "")
        formatted = formatted.replacingOccurrences(of: "*", with: "")
        formatted = formatted.replacingOccurrences(of: "#", with: "")
        if formatted.count > 500 {
            formatted = String(formatted.prefix(500)) + "... The full answer is on screen."
        }
        return formatted
    }
}

// MARK: - Query Documents Intent (Siri Integration)

/// Asks a question of the active library, or of a chosen one.
/// Usage: "Ask OpenIntelligence a question"
@available(iOS 26.0, macOS 26.0, *)
struct QueryDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask My Documents"
    static var description: IntentDescription = .init(
        "Asks a question and answers it from your documents, with the passages the answer used.",
        categoryName: "Ask",
        searchKeywords: ["ask", "question", "answer", "search", "documents"]
    )

    static var openAppWhenRun: Bool = false // Can run in background

    @Parameter(title: "Question", description: "What would you like to know?")
    var question: String

    @Parameter(title: "Mode", description: "How much work goes into the answer", default: .standard)
    var mode: OIAnswerMode

    @Parameter(title: "Library", description: "Leave empty to use the active library")
    var library: OILibraryEntity?

    /// No range on purpose: a shortcut saved on 5.6 can hold a larger number, and a range would
    /// refuse it. The runner keeps the value between 1 and 12.
    @Parameter(
        title: "Passages",
        description: "How many passages to retrieve, from 1 to 12",
        default: 3
    )
    var topK: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question)") {
            \.$mode
            \.$library
            \.$topK
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetView {
        // Avoid logging user content; keep logs metadata-only.
        Log.info("[Siri] Ask My Documents invoked (questionChars=\(question.count), topK=\(topK))", category: .pipeline)

        let outcome = try await AskActionRunner.ask(question, mode: mode, topK: topK, libraryId: library?.id)
        let documentCount = OIDocumentEntityQuery.loadAllDocuments().count
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            view: RAGResponseSnippetView(
                question: question,
                answer: outcome.response.generatedResponse,
                chunkCount: outcome.response.retrievedChunks.count,
                documentCount: documentCount
            )
        )
    }
}

// MARK: - Add Document Intent

/// Opens the app so a document can be chosen.
@available(iOS 26.0, macOS 26.0, *)
struct AddDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Document"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence so you can choose a document to add. To add a file without opening the app, use Add to Library.",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = true // Need UI for file picker

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { AppNavigationRequest.post(.addDocument) }
        return .result(
            dialog: IntentDialog(stringLiteral: "Opening OpenIntelligence to add a document.")
        )
    }
}

// MARK: - List Documents Intent

/// Lists the documents in every library, or in one.
/// Usage: "What documents do I have in OpenIntelligence?"
@available(iOS 26.0, macOS 26.0, *)
struct ListDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Documents"
    static var description: IntentDescription = .init(
        "Returns the documents in your libraries, or in one library.",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Library", description: "Leave empty to list every library's documents")
    var library: OILibraryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("List the documents in \(\.$library)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[OIDocumentEntity]> & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] List Documents intent invoked", category: .pipeline)

        let all = await MainActor.run { IntentSupport.engine().documents }
        let documents = library.map { chosen in all.filter { $0.containerId == chosen.id } } ?? all
        let libraryNames = Dictionary(
            OILibraryEntityQuery.loadContainers().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let items = documents.map { OIDocumentEntityQuery.entity(for: $0, libraryNames: libraryNames) }

        guard !documents.isEmpty else {
            return .result(
                value: items,
                dialog: IntentDialog(stringLiteral: "There are no documents there yet."),
                view: DocumentListSnippetView(documents: documents)
            )
        }

        let documentNames = documents.map { $0.filename }.joined(separator: ", ")
        let spokenResponse = "You have \(documents.count) document\(documents.count == 1 ? "" : "s"): \(documentNames)"

        return .result(
            value: items,
            dialog: IntentDialog(stringLiteral: spokenResponse),
            view: DocumentListSnippetView(documents: documents)
        )
    }
}

// MARK: - Document Import Status Intent

/// Reports the status of any pending or active document imports.
@available(iOS 26.0, macOS 26.0, *)
struct DocumentImportStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Import Status"
    static var description: IntentDescription = .init(
        "See whether document imports are queued or running",
        categoryName: "Documents",
        searchKeywords: ["import", "ingestion", "status", "queue", "processing"]
    )

    static var openAppWhenRun: Bool = false

    /// Returns the sentence it speaks, so a shortcut can branch on it or show it.
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] Document Import Status intent invoked", category: .ingestion)

        let ragService = await MainActor.run { IntentSupport.engine() }
        await ragService.restoreIngestionQueueIfNeeded()

        let snapshot = await MainActor.run { () -> DocumentImportStatusSnapshot? in
            let pendingItems = ragService.ingestionItems.filter { !$0.stage.isTerminal }
            guard !pendingItems.isEmpty else { return nil }

            let activeItem = pendingItems.first(where: { $0.stage != .queued }) ?? pendingItems[0]
            let spokenResponse: String
            if pendingItems.count == 1 {
                spokenResponse = "One document import is \(activeItem.stage.displayName.lowercased()): \(activeItem.filename)."
            } else {
                spokenResponse = "\(pendingItems.count) document imports are pending. Current stage: \(activeItem.stage.displayName.lowercased()) for \(activeItem.filename)."
            }

            return DocumentImportStatusSnapshot(
                activeCount: pendingItems.count,
                currentFilename: activeItem.filename,
                currentStage: activeItem.stage.displayName,
                queuedFilenames: pendingItems.map(\.filename),
                spokenResponse: spokenResponse
            )
        }

        guard let snapshot else {
            return .result(
                value: "No document imports are pending right now.",
                dialog: IntentDialog(stringLiteral: "No document imports are pending right now."),
                view: ErrorSnippetView(message: "No pending imports")
            )
        }

        return .result(
            value: snapshot.spokenResponse,
            dialog: IntentDialog(stringLiteral: snapshot.spokenResponse),
            view: DocumentImportStatusSnippetView(
                activeCount: snapshot.activeCount,
                currentFilename: snapshot.currentFilename,
                currentStage: snapshot.currentStage,
                queuedFilenames: snapshot.queuedFilenames
            )
        )
    }
}

// MARK: - App Shortcuts Provider

/// The actions Siri and Spotlight offer without any setup. Apple allows ten, and this is ten:
/// an eleventh makes the whole set fail to register, with no error. `AppShortcutsProviderTests`
/// counts them. Every phrase has to contain the app's name, and may take one parameter.
@available(iOS 26.0, macOS 26.0, *)
struct RAGAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QueryDocumentsIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Ask my documents in \(.applicationName)",
                "Search my documents with \(.applicationName)",
            ],
            shortTitle: "Ask My Documents",
            systemImageName: "doc.text.magnifyingglass"
        )

        AppShortcut(
            intent: ListDocumentsIntent(),
            phrases: [
                "List my documents in \(.applicationName)",
                "Show my documents in \(.applicationName)",
                "What documents do I have in \(.applicationName)",
            ],
            shortTitle: "List Documents",
            systemImageName: "list.bullet.rectangle"
        )

        AppShortcut(
            intent: DocumentImportStatusIntent(),
            phrases: [
                "Is \(.applicationName) still importing",
                "Check import status in \(.applicationName)",
                "Show the import queue in \(.applicationName)",
            ],
            shortTitle: "Import Status",
            systemImageName: "arrow.down.doc.fill"
        )

        AppShortcut(
            intent: AskDocumentIntent(),
            phrases: [
                "Ask \(.applicationName) about \(\.$document)",
                "Ask about \(\.$document) in \(.applicationName)",
            ],
            shortTitle: "Ask About a Document",
            systemImageName: "doc.text.fill"
        )

        AppShortcut(
            intent: SummarizeDocumentIntent(),
            phrases: [
                "Summarize \(\.$document) in \(.applicationName)",
                "Summarize \(\.$document) with \(.applicationName)",
            ],
            shortTitle: "Summarize a Document",
            systemImageName: "text.justify.left"
        )

        AppShortcut(
            intent: CompareDocumentsIntent(),
            phrases: [
                "Compare documents in \(.applicationName)",
                "Compare two documents with \(.applicationName)",
            ],
            shortTitle: "Compare Two Documents",
            systemImageName: "arrow.2.squarepath"
        )

        AppShortcut(
            intent: SearchLibraryIntent(),
            phrases: [
                "Ask \(\.$library) in \(.applicationName)",
                "Search \(\.$library) in \(.applicationName)",
            ],
            shortTitle: "Ask a Library",
            systemImageName: "magnifyingglass.circle.fill"
        )

        AppShortcut(
            intent: IngestDocumentIntent(),
            phrases: [
                "Add this document to \(.applicationName)",
                "Save this file to \(.applicationName)",
                "Add a file to \(.applicationName)",
            ],
            shortTitle: "Add a File",
            systemImageName: "doc.badge.plus"
        )

        AppShortcut(
            intent: IngestURLIntent(),
            phrases: [
                "Save this page to \(.applicationName)",
                "Add this link to \(.applicationName)",
                "Save a web page to \(.applicationName)",
            ],
            shortTitle: "Save a Web Page",
            systemImageName: "link.badge.plus"
        )

        AppShortcut(
            intent: SearchPassagesIntent(),
            phrases: [
                "Find passages in \(.applicationName)",
                "Find passages with \(.applicationName)",
                "Search passages in \(.applicationName)",
            ],
            shortTitle: "Find Passages",
            systemImageName: "text.magnifyingglass"
        )
    }
}

// MARK: - Get Embedding Provider Intent

/// Tells the person which embedding model the active library uses.
@available(iOS 26.0, macOS 26.0, *)
struct GetEmbeddingProviderIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Embedding Model"
    static var description: IntentDescription = .init(
        "Returns the name of the embedding model the active library is searched with.",
        categoryName: "Settings",
        searchKeywords: ["embedding", "provider", "contextual", "model"]
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] Get Embedding Model intent invoked", category: .embedding)

        let providerId = await MainActor.run {
            IntentSupport.libraries().activeContainer?.embeddingProviderId ?? "coreml_sentence_embedding"
        }
        let (name, description, isHighAccuracy) = describeProvider(providerId)

        // No accuracy figure is spoken: none of these models has a measured one in this repository.
        return .result(
            value: name,
            dialog: IntentDialog(stringLiteral: "The active library uses \(name)."),
            view: EmbeddingProviderSnippetView(
                providerName: name,
                description: description,
                isHighAccuracy: isHighAccuracy
            )
        )
    }

    private func describeProvider(_ id: String) -> (name: String, description: String, isHighAccuracy: Bool) {
        switch id {
        case "nl_contextual_embedding":
            return ("Contextual Embedding", "BERT-style contextual model", true)
        case "nl_embedding":
            return ("Standard NL Embedding", "Fast and efficient word2vec-style model", false)
        case "coreml_sentence_embedding":
            return ("CoreML Sentence", "Sentence-level semantic embedding", false)
        case "coreai_sentence_embedding":
            return ("CoreAI Sentence", "Silicon-native sentence-level semantic embedding", false)
        case "apple_fm_embed":
            return ("Apple Foundation Model", "Apple Intelligence powered embedding", true)
        default:
            return ("Unknown", id, false)
        }
    }
}

// MARK: - Embedding Provider Snippet View

@available(iOS 26.0, macOS 26.0, *)
struct EmbeddingProviderSnippetView: View {
    let providerName: String
    let description: String
    let isHighAccuracy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isHighAccuracy ? "sparkles" : "bolt.badge.a")
                    .font(.system(size: 32))
                    .foregroundStyle(isHighAccuracy ? .purple : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Embedding Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(providerName)
                        .font(.headline)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isHighAccuracy {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("High accuracy mode active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
    }
}

// MARK: - Snippet Views (for Siri and Shortcuts UI)

@available(iOS 26.0, macOS 26.0, *)
struct RAGResponseSnippetView: View {
    let question: String
    let answer: String
    let chunkCount: Int
    let documentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            VStack(alignment: .leading, spacing: 4) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(question)
                    .font(.headline)
            }

            Divider()

            // Answer
            VStack(alignment: .leading, spacing: 4) {
                Text("Answer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(answer)
                    .font(.body)
            }

            Divider()

            // Metadata
            HStack {
                Label("\(chunkCount) chunks", systemImage: "doc.text")
                Spacer()
                Label("\(documentCount) docs", systemImage: "folder")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct DocumentListSnippetView: View {
    let documents: [Document]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Documents")
                .font(.headline)

            ForEach(documents.prefix(10)) { document in
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.filename)
                            .font(.body)
                        Text("\(document.totalChunks) chunks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if documents.count > 10 {
                Text("... and \(documents.count - 10) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct DocumentImportStatusSnippetView: View {
    let activeCount: Int
    let currentFilename: String
    let currentStage: String
    let queuedFilenames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Document Import")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(activeCount) pending")
                        .font(.headline)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentFilename)
                    .font(.body)
                Text(currentStage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if queuedFilenames.count > 1 {
                Text(queuedFilenames.dropFirst().prefix(2).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct ErrorSnippetView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Entity-Native App Intents

@available(iOS 26.0, macOS 26.0, *)
struct AskDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask About a Document"
    static var description: IntentDescription = .init(
        "Asks a question and answers it from one document only.",
        categoryName: "Ask"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Document")
    var document: OIDocumentEntity

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$document) about \(\.$question)")
    }

    /// Through 5.6 this wrote the file name into the question and searched the whole library, so
    /// the answer could come from any document. The search now runs inside the document, in
    /// Standard, and the runner refuses an answer that rests on any other document's passage.
    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetView {
        let outcome = try await AskActionRunner.ask(question, mode: .standard, topK: 6, documentIds: [document.id])
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            view: RAGResponseSnippetView(
                question: question,
                answer: outcome.response.generatedResponse,
                chunkCount: outcome.response.retrievedChunks.count,
                documentCount: 1
            )
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct SummarizeDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize a Document"
    static var description: IntentDescription = .init(
        "Writes a summary of one document, from that document only.",
        categoryName: "Ask"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Document")
    var document: OIDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$document)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetView {
        let prompt = "Provide a concise summary of the main points and key information in the document '\(document.filename)'."
        let outcome = try await AskActionRunner.ask(
            prompt, shownAs: "Summarize \(document.filename)", mode: .standard, topK: 8, documentIds: [document.id])
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(
                stringLiteral: AskActionRunner.spoken(
                    "Here is a summary of \(document.filename): \(outcome.response.generatedResponse)")),
            view: RAGResponseSnippetView(
                question: "Summarize \(document.filename)",
                answer: outcome.response.generatedResponse,
                chunkCount: outcome.response.retrievedChunks.count,
                documentCount: 1
            )
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CompareDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Compare Two Documents"
    static var description: IntentDescription = .init(
        "Compares what two documents in one library say about a topic, from those two documents only.",
        categoryName: "Ask"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "First Document")
    var document1: OIDocumentEntity

    @Parameter(title: "Second Document")
    var document2: OIDocumentEntity

    @Parameter(title: "Topic")
    var topic: String

    static var parameterSummary: some ParameterSummary {
        Summary("Compare \(\.$document1) and \(\.$document2) on \(\.$topic)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetView {
        guard document1.id != document2.id else {
            throw OIIntentError("Choose two different documents to compare.")
        }
        let prompt = "Compare what is stated in '\(document1.filename)' versus what is stated in '\(document2.filename)' on the topic: \(topic)."
        let shown = "Comparison of \(document1.filename) and \(document2.filename) on \(topic)"
        let outcome = try await AskActionRunner.ask(
            prompt, shownAs: shown, mode: .standard, topK: 8, documentIds: [document1.id, document2.id])
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            view: RAGResponseSnippetView(
                question: shown,
                answer: outcome.response.generatedResponse,
                chunkCount: outcome.response.retrievedChunks.count,
                documentCount: 2
            )
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct SearchLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask a Library"
    static var description: IntentDescription = .init(
        "Asks a question and answers it from one library. To get the matching passages without an answer, use Find Passages.",
        categoryName: "Ask"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Library")
    var library: OILibraryEntity

    @Parameter(title: "Question")
    var query: String

    @Parameter(title: "Mode", description: "How much work goes into the answer", default: .standard)
    var mode: OIAnswerMode

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$library) \(\.$query)") {
            \.$mode
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetView {
        let outcome = try await AskActionRunner.ask(query, mode: mode, libraryId: library.id)
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            view: RAGResponseSnippetView(
                question: query,
                answer: outcome.response.generatedResponse,
                chunkCount: outcome.response.retrievedChunks.count,
                documentCount: library.totalDocuments
            )
        )
    }
}

// MARK: - List Evidence Threads Intent

@available(iOS 26.0, macOS 26.0, *)
struct ListEvidenceThreadsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Conversations"
    static var description: IntentDescription = .init(
        "Returns the saved conversations in a library.",
        categoryName: "Chat",
        searchKeywords: ["threads", "history", "conversations", "chats"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Library", description: "Leave empty to use the active library", default: nil)
    var library: OILibraryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("List the conversations in \(\.$library)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[OIThreadEntity]> & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] List Conversations intent invoked", category: .pipeline)

        let ragService = await MainActor.run { IntentSupport.engine() }
        let containerId = await MainActor.run {
            library?.id ?? ragService.containerService.activeContainerId
        }
        let libraryName = await MainActor.run {
            ragService.containerService.containers.first { $0.id == containerId }?.name
        }
        let threads = await MainActor.run {
            ragService.listThreads(for: containerId)
        }
        let items = threads.map { OIThreadEntity($0, libraryName: libraryName) }

        guard !threads.isEmpty else {
            return .result(
                value: items,
                dialog: IntentDialog(stringLiteral: "There are no conversations in this library yet."),
                view: ThreadListSnippetView(threads: threads)
            )
        }

        let threadTitles = threads.map { $0.title }.joined(separator: ", ")
        let spokenResponse = "You have \(threads.count) conversation\(threads.count == 1 ? "" : "s"): \(threadTitles)"

        return .result(
            value: items,
            dialog: IntentDialog(stringLiteral: spokenResponse),
            view: ThreadListSnippetView(threads: threads)
        )
    }
}

// MARK: - Create New Evidence Thread Intent

@available(iOS 26.0, macOS 26.0, *)
struct CreateNewEvidenceThreadIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Conversation"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence on a new conversation in a library.",
        categoryName: "Chat",
        searchKeywords: ["new thread", "new chat", "start chat", "conversation"]
    )

    static var openAppWhenRun: Bool = true // Open app to show new chat screen

    @Parameter(title: "Library", description: "Leave empty to use the active library", default: nil)
    var library: OILibraryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a conversation in \(\.$library)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Log.info("[Siri] Start a Conversation intent invoked", category: .pipeline)

        let ragService = await MainActor.run { IntentSupport.engine() }
        let containerId = await MainActor.run {
            library?.id ?? ragService.containerService.activeContainerId
        }

        do {
            try await MainActor.run {
                try ragService.createNewThread(for: containerId)
                AppNavigationRequest.post(.newConversation(libraryId: containerId))
            }
        } catch {
            throw OIIntentError("A new conversation could not be started. \(error.localizedDescription)")
        }
        return .result(
            dialog: IntentDialog(stringLiteral: "Started a new conversation.")
        )
    }
}

// MARK: - Snippet Views

@available(iOS 26.0, macOS 26.0, *)
struct ThreadListSnippetView: View {
    let threads: [EvidenceThread]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversations")
                .font(.headline)

            ForEach(threads.prefix(10)) { thread in
                HStack {
                    Image(systemName: "chat.bubble.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.title)
                            .font(.body)
                            .lineLimit(1)
                        Text(thread.updatedAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if threads.count > 10 {
                Text("... and \(threads.count - 10) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}


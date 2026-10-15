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
import Combine
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

/// Lets the system stop an ask action and see how far it has got (5.7).
///
/// From iOS and macOS 26.4 the system can cancel an action (`CancellableIntent`): when it has gone
/// about 30 seconds in the background without reporting progress, or when a person stops it in
/// Siri, a Live Activity or Shortcuts. Through 5.6 nothing listened, so the model went on writing an
/// answer nobody would see. From 27 an action that reports progress can also run past those 30
/// seconds in the background (`LongRunningIntent`), and the system shows its progress as a Live
/// Activity. One `AskControl` serves one question: the cancel handler the system calls, and the
/// progress the question reports.
@available(iOS 26.0, macOS 26.0, *)
nonisolated final class AskControl: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: String?
    private var handlers: [@Sendable () -> Void] = []
    /// Set by `finish()`, after which nothing moves the bar.
    private var isFinished = false
    /// The action's own progress on 27, nil before.
    let progress: Progress?
    /// Brings the app forward when the question needs the Private Cloud Compute consent sheet
    /// (`AskActionRunner.foregroundRequest`); nil when the system would not let the action come forward.
    let bringForward: (@Sendable () async throws -> Void)?

    init(progress: Progress?, bringForward: (@Sendable () async throws -> Void)? = nil) {
        self.progress = progress
        self.bringForward = bringForward
        progress?.totalUnitCount = 100
    }

    /// "timeout" or "cancelled" once the system has stopped the action.
    var cancellationReason: String? { lock.withLock { reason } }

    func cancel(because reason: String) {
        let toRun: [@Sendable () -> Void] = lock.withLock {
            guard self.reason == nil else { return [] }
            self.reason = reason
            return handlers
        }
        toRun.forEach { $0() }
    }

    /// Runs `handler` when the action is stopped, at once if it already was.
    func whenCancelled(_ handler: @escaping @Sendable () -> Void) {
        let alreadyStopped: Bool = lock.withLock {
            if reason != nil { return true }
            handlers.append(handler)
            return false
        }
        if alreadyStopped { handler() }
    }

    /// A step the engine reached, as its status line names it. Each step moves the bar.
    func report(_ status: String) {
        guard let progress, !lock.withLock({ isFinished }) else { return }
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { progress.localizedDescription = trimmed }
        advance(by: 5)
    }

    /// Called every two seconds while the question runs, so the system sees progress during a
    /// long model call that changes no status. The system ends a long-running action whose
    /// progress stops changing, so the count never stops: near the end the total grows and the
    /// bar slows down instead.
    func tick() {
        advance(by: 1)
    }

    /// The bar fills and stays full: a tick or a status that arrives after this changes nothing.
    /// Without that, the heartbeat's last tick or a late status grew the total again and the
    /// finished action's bar fell back to about 91%.
    func finish() {
        guard let progress else { return }
        lock.withLock {
            isFinished = true
            progress.completedUnitCount = progress.totalUnitCount
        }
    }

    private func advance(by units: Int64) {
        guard let progress else { return }
        lock.withLock {
            guard !isFinished else { return }
            progress.completedUnitCount += units
            if progress.completedUnitCount * 100 >= progress.totalUnitCount * 95 {
                progress.totalUnitCount += max(10, progress.totalUnitCount / 10)
            }
        }
    }

    static func describe(_ reason: String) -> String {
        reason == "timeout"
            ? "The question was stopped because it ran too long in the background."
            : "The question was stopped."
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
    /// The engine a question runs on. A test hands it an engine with a stand-in model, since the
    /// iOS Simulator has no language model (`ShortcutsActionTests`).
    static var makeEngine: () -> RAGService = { RAGService() }

    struct Outcome {
        let answer: OIAnswerEntity
        let response: RAGResponse
        /// The documents the answer's card offers to open, up to three (`sourceEntities`).
        let sources: [OIDocumentEntity]
        /// The library the question ran in, which the card's buttons open the chat on.
        let library: OILibraryEntity?
        /// Whether the card offers Ask a Follow-up (`offersFollowUp(scoped:)`).
        let offersFollowUp: Bool
        /// Whether the card offers Think Deeper (`offersThinkDeeper(mode:scoped:)`).
        let offersThinkDeeper: Bool
    }

    /// Ask a Follow-up continues in the chat, which asks a whole library: so not after a question
    /// kept to chosen documents, which would continue across the library.
    static func offersFollowUp(scoped: Bool) -> Bool {
        !scoped
    }

    /// Think Deeper asks again in Deep Think in the chat: so only after a Standard answer (a Deep
    /// Think or Maximum one has had it) from a whole library.
    static func offersThinkDeeper(mode: OIAnswerMode, scoped: Bool) -> Bool {
        mode == .standard && !scoped
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
        documentIds: Set<UUID>? = nil,
        control: AskControl? = nil
    ) async throws -> Outcome {
        let wanted = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { throw OIIntentError("There was no question to ask.") }

        let engine = await MainActor.run { makeEngine() }
        let bringForward = control?.bringForward
        await MainActor.run {
            engine.bringAppForwardForConsent = bringForward
            engine.asksThroughRelay = true
        }
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

        // The question runs in a task of its own, so a stop from the system can cancel it, and the
        // engine's status and a two-second tick are its progress.
        let queryTask = Task { () async throws -> RAGResponse in
            try await RAGQueryScope.$documentIds.withValue(documentIds) {
                try await engine.query(
                    wanted, topK: min(max(topK, 1), 12), containerId: container,
                    qualityModeOverride: effectiveMode.qualityMode)
            }
        }
        let statusFeed = control.map { control in engine.$processingStatus.sink { control.report($0) } }
        let heartbeat = control.map { control in
            Task {
                // A cancelled sleep ends the loop, so no tick follows the answer.
                while (try? await Task.sleep(for: .seconds(2))) != nil {
                    control.tick()
                }
            }
        }
        control?.whenCancelled {
            queryTask.cancel()
            Task { @MainActor in engine.cancelActiveGeneration() }
        }
        defer {
            heartbeat?.cancel()
            statusFeed?.cancel()
        }

        let response: RAGResponse
        do {
            // The question's task is not a child of this one, so a cancellation of the action's own
            // task (all that stops an action before 26.4) is passed on to it.
            response = try await withTaskCancellationHandler {
                try await queryTask.value
            } onCancel: {
                queryTask.cancel()
            }
        } catch {
            if let reason = control?.cancellationReason {
                Log.info("[Shortcuts] Ask stopped by the system (\(reason))", category: .pipeline)
                throw OIIntentError(AskControl.describe(reason))
            }
            Log.error("[Shortcuts] Ask failed: \(error.localizedDescription)", category: .pipeline)
            throw OIIntentError("The question could not be answered. \(error.localizedDescription)")
        }
        if let reason = control?.cancellationReason {
            // The answer came back after the stop: it is not handed on, as the system has moved on.
            Log.info("[Shortcuts] Ask stopped by the system (\(reason)) as its answer arrived", category: .pipeline)
            throw OIIntentError(AskControl.describe(reason))
        }
        control?.finish()

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
        let askedIn = container
        let (sources, library) = await MainActor.run { () -> ([OIDocumentEntity], OILibraryEntity?) in
            let libraries = engine.containerService.containers
            let answeredIn = askedIn ?? engine.containerService.activeContainerId
            return (
                sourceEntities(of: response, documents: engine.documents, libraries: libraries),
                libraries.first { $0.id == answeredIn }.map(OILibraryEntityQuery.entity(for:))
            )
        }
        return Outcome(
            answer: OIAnswerEntity(question: shownQuestion ?? wanted, response: response, mode: effectiveMode),
            response: response, sources: sources, library: library,
            offersFollowUp: offersFollowUp(scoped: documentIds != nil),
            offersThinkDeeper: offersThinkDeeper(mode: effectiveMode, scoped: documentIds != nil))
    }

    /// The card for an answer (5.7): its question, its text and the documents it rests on.
    static func card(question: String, outcome: Outcome) -> AnswerCardSnippetIntent {
        AnswerCardSnippetIntent(
            question: question, answer: AnswerCardSnippetView.shown(outcome.response.generatedResponse),
            sources: outcome.sources, library: outcome.library, offersFollowUp: outcome.offersFollowUp,
            offersThinkDeeper: outcome.offersThinkDeeper)
    }

    /// Up to three of the documents an answer rests on (`sourceDocumentIds`), as app items made from
    /// the engine's own lists, so the card reads no file.
    static func sourceEntities(
        of response: RAGResponse, documents: [Document], libraries: [KnowledgeContainer]
    ) -> [OIDocumentEntity] {
        let records = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(libraries.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let ids = sourceDocumentIds(
            evidenceIds: response.structuredAnswer?.evidence.map(\.evidenceId) ?? [], passages: response.retrievedChunks)
        return ids.compactMap { records[$0] }.prefix(3).map { OIDocumentEntityQuery.entity(for: $0, libraryNames: names) }
    }

    /// The documents an answer rests on, once each: those of the passages its evidence list names,
    /// in that list's order (`StructuredAnswer.evidence`, which the chat's citation links resolve
    /// against, narrowed to the passages its accepted claims cite when they cite any). An answer
    /// with no evidence list falls back to the documents of every passage it was given, in the order
    /// they were retrieved.
    nonisolated static func sourceDocumentIds(evidenceIds: [String], passages: [RetrievedChunk]) -> [UUID] {
        let documentOfPassage = Dictionary(
            passages.map { ($0.chunk.id.uuidString, $0.chunk.documentId) }, uniquingKeysWith: { first, _ in first })
        let fromEvidence = evidenceIds.compactMap { documentOfPassage[$0] }
        let ordered = fromEvidence.isEmpty ? passages.map(\.chunk.documentId) : fromEvidence
        var seen = Set<UUID>()
        return ordered.filter { seen.insert($0).inserted }
    }

    /// The answer as Siri speaks it: markdown marks removed, and cut at 500 characters with a note
    /// that the full answer is on screen. The value an action returns is never cut. Nonisolated: the
    /// actions call it from `perform`, outside the main actor.
    nonisolated static func spoken(_ text: String) -> String {
        var formatted = text
        formatted = formatted.replacingOccurrences(of: "**", with: "")
        formatted = formatted.replacingOccurrences(of: "*", with: "")
        formatted = formatted.replacingOccurrences(of: "#", with: "")
        if formatted.count > 500 {
            formatted = String(formatted.prefix(500)) + "... The full answer is on screen."
        }
        return formatted
    }

    /// Runs an ask action's question where the system can stop it (iOS and macOS 26.4) and, on 27,
    /// as a long-running task that reports progress. Before 26.4 it runs as it did through 5.6. On
    /// every version the question can bring the app forward for the consent sheet (`foregroundRequest`).
    static func run<Intent: AppIntent>(
        _ intent: Intent, _ ask: @escaping (AskControl) async throws -> Outcome
    ) async throws -> Outcome {
        let bringForward = foregroundRequest(for: intent)
        if #available(iOS 27.0, macOS 27.0, *), let long = intent as? any (LongRunningIntent & CancellableIntent) {
            return try await runLong(long, bringForward: bringForward, ask)
        }
        if #available(iOS 26.4, macOS 26.4, *), let cancellable = intent as? any CancellableIntent {
            return try await runCancellable(cancellable, bringForward: bringForward, ask)
        }
        return try await ask(AskControl(progress: nil, bringForward: bringForward))
    }

    /// What brings the app forward when the question's engine needs the Private Cloud Compute
    /// consent sheet (`RAGService.bringAppForwardForConsent`, 5.7). Nil when the system would not let
    /// the action come forward, as on a locked iPhone: the question then uses Private Cloud Compute
    /// only with consent given before. The ask actions allow it with `.foreground(.dynamic)`.
    static func foregroundRequest<Intent: AppIntent>(for intent: Intent) -> (@Sendable () async throws -> Void)? {
        guard intent.systemContext.currentMode.canContinueInForeground else { return nil }
        return {
            try await intent.continueInForeground(
                "Private Cloud Compute needs your OK before this question goes to it.", alwaysConfirm: false)
        }
    }

    @available(iOS 27.0, macOS 27.0, *)
    private static func runLong<Intent: LongRunningIntent & CancellableIntent>(
        _ intent: Intent, bringForward: (@Sendable () async throws -> Void)?,
        _ ask: @escaping (AskControl) async throws -> Outcome
    ) async throws -> Outcome {
        let control = AskControl(progress: intent.progress, bringForward: bringForward)
        return try await intent.performBackgroundTask(
            operation: { try await ask(control) },
            onCancel: { reason in control.cancel(because: reason == .timeout ? "timeout" : "cancelled") })
    }

    @available(iOS 26.4, macOS 26.4, *)
    private static func runCancellable<Intent: CancellableIntent>(
        _ intent: Intent, bringForward: (@Sendable () async throws -> Void)?,
        _ ask: @escaping (AskControl) async throws -> Outcome
    ) async throws -> Outcome {
        let control = AskControl(progress: nil, bringForward: bringForward)
        return try await intent.withIntentCancellationHandler(
            operation: { try await ask(control) },
            onCancel: { reason in control.cancel(because: reason == .timeout ? "timeout" : "cancelled") })
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

    /// In the background, and in front only when the question needs the Private Cloud Compute consent
    /// sheet (`AskActionRunner.foregroundRequest`, 5.7). Through 5.6 it could not come forward.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

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

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetIntent {
        // Avoid logging user content; keep logs metadata-only.
        Log.info("[Siri] Ask My Documents invoked (questionChars=\(question.count), topK=\(topK))", category: .pipeline)

        let outcome = try await AskActionRunner.run(self) { control in
            try await AskActionRunner.ask(question, mode: mode, topK: topK, libraryId: library?.id, control: control)
        }
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            snippetIntent: await AskActionRunner.card(question: question, outcome: outcome)
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
            let items = ragService.currentImportItems
            let pendingItems = items.filter { !$0.stage.isTerminal }
            guard let activeItem = ImportProgress.current(in: items) else { return nil }
            // The same share the background task and the Live Activity show (`ImportProgress`).
            let done = "\(ImportProgress.percent(of: items))% of the import is done."
            let spokenResponse: String
            if pendingItems.count == 1 {
                spokenResponse = "One document import is \(activeItem.stage.displayName.lowercased()): \(activeItem.filename). \(done)"
            } else {
                spokenResponse = "\(pendingItems.count) document imports are pending. Current stage: \(activeItem.stage.displayName.lowercased()) for \(activeItem.filename). \(done)"
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

/// The card Siri and Shortcuts show for an answer (5.7): the question, the answer, and a button for
/// each of up to three documents it rests on (`AskActionRunner.sourceDocumentIds`), which opens that
/// document's page; for a question asked of a whole library, an Ask a Follow-up button, which opens
/// the chat on that library in a new conversation that starts with the question and this answer
/// (`AskFollowUpIntent`); and for a Standard answer from a whole library, a Think Deeper button,
/// which opens the chat on that library in Deep Think with the question (`ThinkDeeperIntent`). Through 5.6 the card was
/// a still picture with the passage and document counts. The system may create and perform a
/// snippet intent many times while its card is up, so `perform` must have no side effects and the
/// intent should carry the least data it can (Apple's "Displaying static and interactive
/// snippets", read 2026-10-14): this one only builds the view, from the question, the answer as
/// the card shows it, and the documents as app items.
@available(iOS 26.0, macOS 26.0, *)
struct AnswerCardSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Answer"
    static let isDiscoverable = false

    @Parameter(title: "Question")
    var question: String

    @Parameter(title: "Answer")
    var answer: String

    @Parameter(title: "Sources")
    var sources: [OIDocumentEntity]

    @Parameter(title: "Library")
    var library: OILibraryEntity?

    @Parameter(title: "Ask a Follow-up", default: false)
    var offersFollowUp: Bool

    @Parameter(title: "Think Deeper", default: false)
    var offersThinkDeeper: Bool

    init() {}

    init(
        question: String, answer: String, sources: [OIDocumentEntity], library: OILibraryEntity? = nil,
        offersFollowUp: Bool = false, offersThinkDeeper: Bool = false
    ) {
        self.question = question
        self.answer = answer
        self.sources = sources
        self.library = library
        self.offersFollowUp = offersFollowUp
        self.offersThinkDeeper = offersThinkDeeper
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(
            view: AnswerCardSnippetView(
                question: question, answer: answer, sources: Array(sources.prefix(3)), library: library,
                offersFollowUp: offersFollowUp, offersThinkDeeper: offersThinkDeeper))
    }
}

/// The answer arrives already cut (`shown`), so the card stays short; the full answer is the
/// action's value and in the app.
@available(iOS 26.0, macOS 26.0, *)
struct AnswerCardSnippetView: View {
    let question: String
    let answer: String
    let sources: [OIDocumentEntity]
    var library: OILibraryEntity?
    var offersFollowUp = false
    var offersThinkDeeper = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(answer)
                .font(.body)
                .lineLimit(9)
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources, id: \.id) { source in
                        Button(intent: Self.opening(source)) {
                            Label(source.filename, systemImage: "doc.text")
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            if offersFollowUp || offersThinkDeeper {
                HStack(spacing: 8) {
                    if offersFollowUp {
                        Button(intent: AskFollowUpIntent(question: question, answer: answer, library: library)) {
                            Label("Ask a Follow-up", systemImage: "bubble.left.and.text.bubble.right")
                        }
                        .buttonStyle(.bordered)
                    }
                    if offersThinkDeeper {
                        Button(intent: ThinkDeeperIntent(question: question, library: library)) {
                            Label("Think Deeper", systemImage: RAGQualityMode.deepThink.icon)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
    }

    /// The answer without its Markdown marks, cut at a word near 600 characters.
    nonisolated static func shown(_ answer: String) -> String {
        var text = answer
        for mark in ["**", "*", "#"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 600 else { return text }
        let cut = text.prefix(600)
        return String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut) + "…"
    }

    static func opening(_ document: OIDocumentEntity) -> OpenDocumentIntent {
        let intent = OpenDocumentIntent()
        intent.target = document
        return intent
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

    /// In the background, and in front only when the question needs the Private Cloud Compute consent
    /// sheet (`AskActionRunner.foregroundRequest`, 5.7). Through 5.6 it could not come forward.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

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
    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetIntent {
        let outcome = try await AskActionRunner.run(self) { control in
            try await AskActionRunner.ask(
                question, mode: .standard, topK: 6, documentIds: [document.id], control: control)
        }
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            snippetIntent: await AskActionRunner.card(question: question, outcome: outcome)
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

    /// In the background, and in front only when the question needs the Private Cloud Compute consent
    /// sheet (`AskActionRunner.foregroundRequest`, 5.7). Through 5.6 it could not come forward.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Document")
    var document: OIDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$document)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetIntent {
        let prompt = "Provide a concise summary of the main points and key information in the document '\(document.filename)'."
        let outcome = try await AskActionRunner.run(self) { control in
            try await AskActionRunner.ask(
                prompt, shownAs: "Summarize \(document.filename)", mode: .standard, topK: 8,
                documentIds: [document.id], control: control)
        }
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(
                stringLiteral: AskActionRunner.spoken(
                    "Here is a summary of \(document.filename): \(outcome.response.generatedResponse)")),
            snippetIntent: await AskActionRunner.card(question: "Summarize \(document.filename)", outcome: outcome)
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

    /// In the background, and in front only when the question needs the Private Cloud Compute consent
    /// sheet (`AskActionRunner.foregroundRequest`, 5.7). Through 5.6 it could not come forward.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "First Document")
    var document1: OIDocumentEntity

    @Parameter(title: "Second Document")
    var document2: OIDocumentEntity

    @Parameter(title: "Topic")
    var topic: String

    static var parameterSummary: some ParameterSummary {
        Summary("Compare \(\.$document1) and \(\.$document2) on \(\.$topic)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetIntent {
        guard document1.id != document2.id else {
            throw OIIntentError("Choose two different documents to compare.")
        }
        let prompt = "Compare what is stated in '\(document1.filename)' versus what is stated in '\(document2.filename)' on the topic: \(topic)."
        let shown = "Comparison of \(document1.filename) and \(document2.filename) on \(topic)"
        let outcome = try await AskActionRunner.run(self) { control in
            try await AskActionRunner.ask(
                prompt, shownAs: shown, mode: .standard, topK: 8, documentIds: [document1.id, document2.id],
                control: control)
        }
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            snippetIntent: await AskActionRunner.card(question: shown, outcome: outcome)
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

    /// In the background, and in front only when the question needs the Private Cloud Compute consent
    /// sheet (`AskActionRunner.foregroundRequest`, 5.7). Through 5.6 it could not come forward.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

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

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerEntity> & ProvidesDialog & ShowsSnippetIntent {
        let outcome = try await AskActionRunner.run(self) { control in
            try await AskActionRunner.ask(query, mode: mode, libraryId: library.id, control: control)
        }
        return .result(
            value: outcome.answer,
            dialog: IntentDialog(stringLiteral: AskActionRunner.spoken(outcome.response.generatedResponse)),
            snippetIntent: await AskActionRunner.card(question: query, outcome: outcome)
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

// MARK: - The system can stop the ask actions (26.4) and let them run long (27)

@available(iOS 26.4, macOS 26.4, *) extension QueryDocumentsIntent: CancellableIntent {}
@available(iOS 26.4, macOS 26.4, *) extension SearchLibraryIntent: CancellableIntent {}
@available(iOS 26.4, macOS 26.4, *) extension AskDocumentIntent: CancellableIntent {}
@available(iOS 26.4, macOS 26.4, *) extension SummarizeDocumentIntent: CancellableIntent {}
@available(iOS 26.4, macOS 26.4, *) extension CompareDocumentsIntent: CancellableIntent {}

@available(iOS 27.0, macOS 27.0, *) extension QueryDocumentsIntent: LongRunningIntent {}
@available(iOS 27.0, macOS 27.0, *) extension SearchLibraryIntent: LongRunningIntent {}
@available(iOS 27.0, macOS 27.0, *) extension AskDocumentIntent: LongRunningIntent {}
@available(iOS 27.0, macOS 27.0, *) extension SummarizeDocumentIntent: LongRunningIntent {}
@available(iOS 27.0, macOS 27.0, *) extension CompareDocumentsIntent: LongRunningIntent {}

//
//  ChatScreen+Actions.swift
//  OpenIntelligence
//
//  Part of ChatScreen, moved unchanged from ChatScreen.swift on 2026-11-05 (5.8 split).
//

import AppIntents
import Combine
import Foundation
import StoreKit
import SwiftUI
import TipKit
import Translation

#if os(iOS)
    import PDFKit
    import VisionKit
#endif


extension ChatScreen {
    // MARK: - Send Message
    var shouldShowFirstQueryHero: Bool {
        // Show the hero (with dynamic suggested questions) whenever the chat is empty —
        // not just before the first-ever query. hasAskedFirstQuery is an onboarding
        // completion flag, not a display gate. Gating on it permanently hides suggested
        // questions after the very first message the user ever sends.
        messages.isEmpty
    }

    /// Starter prompts: the service's questions for this library, which for a library of sample
    /// documents are the hand-written ones. Until the service has answered, a sample library shows
    /// that list straight away. A library that does not yield grounded prompts yet shows none
    /// rather than invented ones.
    ///
    /// Until 5.7 a second hand-written list here came first whenever two of three sample names were
    /// present, and one of the three was "OpenIntelligence Roadmap", a name no sample in this
    /// repository's history has had. So the set decided on 2026-09-14 showed only when the
    /// architecture or Private Cloud Compute guide was there as a numbered copy alone, the refresh
    /// button changed nothing under this list, a library of the samples and the person's own files
    /// kept showing questions about the samples, and a sample library without one of those two
    /// guides got neither list.
    var starterPrompts: [String] {
        if !dynamicSuggestedQuestions.isEmpty {
            return dynamicSuggestedQuestions
        }

        if let curated = curatedSampleQuestions {
            return curated.map(\.text)
        }

        // An empty library offers nothing to tap. Until 5.6 it offered four lines, the first an
        // instruction ("Import a document from the Documents tab to get started."), and a tap sent
        // any of them as a question, which an empty library answers with "No documents yet."
        return []
    }

    private var activeDocumentsForStarterPrompts: [Document] {
        let activeId = ragService.containerService.activeContainerId
        let defaultId = ragService.containerService.containers.first?.id

        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            }
            return activeId == defaultId
        }
    }

    /// The hand-written questions when every document in this library is a sample, else nil.
    private var curatedSampleQuestions: [SuggestedQuestionsService.SuggestedQuestion]? {
        SuggestedQuestionsService.curatedSampleQuestions(
            forFilenames: activeDocumentsForStarterPrompts.map(\.filename))
    }

    /// The source line and category for each prompt shown, the curated list's included before the
    /// service has answered, so its chips carry them from the first frame.
    var starterQuestionDetails: [String: SuggestedQuestionsService.SuggestedQuestion] {
        if !dynamicSuggestedQuestions.isEmpty {
            return dynamicQuestionDetails
        }
        guard let curated = curatedSampleQuestions else { return [:] }
        return Dictionary(curated.map { ($0.text, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Generate dynamic suggested questions based on library content
    func refreshDynamicQuestions() {
        refreshSuggestedQuestions(force: false)
    }

    /// Generate suggested questions, optionally forcing a refresh (bypasses cache, avoids repeats)
    func refreshSuggestedQuestions(force: Bool) {
        suggestedQuestionsTask?.cancel()
        if force {
            isRefreshingSuggestions = true
        }
        suggestedQuestionsTask = Task {
            defer {
                isRefreshingSuggestions = false
            }
            let containerId = ragService.containerService.activeContainerId

            // Get documents for the active container
            let documents = ragService.documents.filter { doc in
                if let docContainerId = doc.containerId {
                    return docContainerId == containerId
                }
                return containerId == ragService.containerService.containers.first?.id
            }

            guard !documents.isEmpty else {
                dynamicSuggestedQuestions = []
                dynamicQuestionDetails = [:]
                return
            }

            // Scale the analysis sample with library size so large containers do not
            // collapse into vague, library-wide suggestions.
            do {
                let hasValidCache: Bool
                if force {
                    hasValidCache = false
                } else {
                    hasValidCache = await suggestedQuestionsService.hasValidCache(
                        for: containerId, documentCount: documents.count)
                }

                let sampleChunks: [DocumentChunk]
                if hasValidCache {
                    sampleChunks = []
                } else {
                    let sampleLimit = min(max(documents.count * 4, 50), 160)
                    sampleChunks = try await ragService.getSampleChunks(for: containerId, limit: sampleLimit)
                }

                let questions = await suggestedQuestionsService.generateQuestions(
                    for: containerId,
                    documents: documents,
                    sampleChunks: sampleChunks,
                    count: 10,
                    forceRefresh: force
                )

                guard !Task.isCancelled else { return }

                // Verify we're still on the same container — prevents race where
                // a slow LLM generation from container A overwrites container B's state
                guard ragService.containerService.activeContainerId == containerId else {
                    Log.debug(
                        "[ChatScreen] Discarding stale questions for container \(containerId.uuidString.prefix(8)) — user switched"
                    )
                    return
                }

                dynamicSuggestedQuestions = questions.map { $0.text }
                dynamicQuestionDetails = Dictionary(
                    uniqueKeysWithValues: questions.map { ($0.text, $0) }
                )
                // What the chat's strip was given (5.8 journal): counts by kind, never the questions.
                if VerificationJournal.isEnabled {
                    let curated = questions.filter { SuggestedQuestionsService.curatedQuestionTexts.contains($0.text) }
                    let generated = questions.filter {
                        $0.isLLMGenerated && !SuggestedQuestionsService.curatedQuestionTexts.contains($0.text)
                    }
                    VerificationJournal.record(
                        "suggestions.shown",
                        ["library": VerificationJournal.anon(containerId),
                            "defaultLibrary": "\(containerId == ragService.containerService.containers.first?.id)",
                            "documents": "\(documents.count)",
                            "onlySamples": "\(SuggestedQuestionsService.curatedSampleQuestions(forFilenames: documents.map(\.filename)) != nil)",
                            "curated": "\(curated.count)", "generated": "\(generated.count)",
                            "template": "\(questions.count - curated.count - generated.count)",
                            "chatEmpty": "\(messages.isEmpty)", "inFront": "\(isAppeared)"])
                }
                Log.debug("[ChatScreen] Generated \(questions.count) dynamic suggested questions (force: \(force))")
            } catch {
                Log.warning("[ChatScreen] Failed to generate dynamic questions: \(error.localizedDescription)")
                dynamicSuggestedQuestions = []
                dynamicQuestionDetails = [:]
            }
        }
    }

    func persistChatHistory(for containerId: UUID?) {
        ragService.persistChatHistory(messages, for: containerId)
    }

    func appendAndPersistMessage(_ message: ChatMessage, for containerId: UUID) {
        if ragService.containerService.activeContainerId == containerId {
            messages.append(message)
            persistChatHistory(for: containerId)
            recordForLibraryWidget(message, in: containerId)
            return
        }

        var history = ragService.chatHistory(for: containerId)
        history.append(message)
        ragService.persistChatHistory(history, for: containerId)
    }

    /// The "Your Library" widget shows the last question in the open library and the start of its answer (5.7,
    /// `WidgetSnapshot`). Only an answer counts, which is a message with an answer's metadata: an error, a stopped
    /// answer or a notice in the chat is not written. Called after the conversation is saved, so it has its id.
    private func recordForLibraryWidget(_ message: ChatMessage, in containerId: UUID) {
        guard message.role == .assistant, message.metadata != nil, !message.content.isEmpty else { return }
        let question = message.traceQuery ?? messages.last(where: { $0.role == .user })?.content
        WidgetSnapshot.recordAnswer(
            question: question, answer: message.content, libraryId: containerId,
            threadId: ragService.activeThreadId, messageId: message.id)
    }

    /// A request that ends in this screen: a new conversation, the camera, text to ask about, or an
    /// answer from Siri to follow up on.
    func takeNavigationRequest() {
        let request = AppNavigationRequest.shared.take { destination in
            switch destination {
            case .newConversation, .scanDocument, .ask, .continueAnswer: return true
            default: return false
            }
        }
        switch request {
        case .newConversation:
            guard !isProcessing, !messages.isEmpty else { return }
            newChat()
        case .scanDocument:
            #if os(iOS)
                if SystemDocumentScanner.isSupported {
                    VerificationJournal.record("nav.taken", ["to": "scanDocument", "shows": "scanner"])
                    showDocumentScanner = true
                } else {
                    VerificationJournal.record("nav.taken", ["to": "scanDocument", "shows": "unsupported"])
                    toastManager.show(
                        ToastItem(title: "This device can't scan documents", icon: "doc.viewfinder", tint: .orange),
                        duration: 2.5)
                }
            #endif
        case .ask(let text, let sendsAtOnce, let inDeepThink, _):
            if inDeepThink {
                // Think Deeper: the mode is not switched under an answer still being written.
                guard !isProcessing else {
                    pushToast("Finish this answer first", icon: "hourglass", tint: .orange)
                    return
                }
                if settings.ragQualityMode != .deepThink {
                    settings.ragQualityMode = .deepThink
                    ragService.resetDeepThinkLiveMetrics()
                }
            }
            composerDraft = ComposerDraft(text: text, sendsAtOnce: sendsAtOnce)
        case .continueAnswer(let question, let answer, _):
            // A new conversation that starts with Siri's question and answer, saved as this chat's
            // history. An answer still being written here is left to finish, and nothing is put
            // in place of a conversation when a new one cannot be started (`newChat`).
            guard !isProcessing else {
                pushToast("Finish this answer first", icon: "hourglass", tint: .orange)
                return
            }
            if !messages.isEmpty, !newChat() { return }
            let now = Date()
            messages = [
                ChatMessage(role: .user, content: question, timestamp: now),
                ChatMessage(role: .assistant, content: answer, timestamp: now),
            ]
            let library = ragService.containerService.activeContainerId
            persistChatHistory(for: library)
            // The engine records each answer in the library's conversation memory, and Siri's
            // question normally reached it that way. When the memory has turns, the next question
            // is rewritten against them and given them as context instead of the history above,
            // so it gets this turn if its latest turn is another one.
            if #available(iOS 26.0, *), settings.enableConversationMemory {
                let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
                let latest = ConversationMemoryService.shared.memory(for: library).recentTurns.last
                if latest?.userQuery.trimmingCharacters(in: .whitespacesAndNewlines) != asked {
                    Task {
                        await ConversationMemoryService.shared.addTurn(
                            userQuery: question, assistantResponse: answer, for: library)
                    }
                }
            }
            composerDraft = ComposerDraft(text: "")
        default:
            break
        }
    }

    #if os(iOS)
        /// Saves the scan as one PDF and hands it to the Documents screen's import review, the same
        /// path as a file opened from another app. Pages are read and compressed one at a time, with
        /// a yield between them, so a long scan never holds every page image at once and the screen
        /// keeps drawing while it is saved.
        func storeScan(_ scan: VNDocumentCameraScan) {
            Log.info("[Scan] \(scan.pageCount) page(s) scanned", category: .ingestion)
            Task {
                let document = PDFDocument()
                for index in 0..<scan.pageCount {
                    autoreleasepool { ScannedDocument.append(scan.imageOfPage(at: index), to: document) }
                    await Task.yield()
                }
                do {
                    let file = try ScannedDocument.store(document, title: scan.title)
                    AppNavigationRequest.post(.importFiles([file]))
                } catch {
                    Log.error("[Scan] The scan could not be saved: \(error.localizedDescription)", category: .ingestion)
                    toastManager.show(
                        ToastItem(
                            title: "The scan could not be saved", icon: "exclamationmark.triangle", tint: .orange),
                        duration: 2.5)
                }
            }
        }
    #endif

    /// Writes the conversation to a temporary file and opens the share sheet on it. The title is
    /// the first question, because a chat has no name of its own here.
    func exportConversation(_ format: ConversationExporter.Format) {
        let firstQuestion = messages.first { message in
            if case .user = message.role { return true }
            return false
        }?.content
        let shown = messages
        Task {
            do {
                let url = try await ConversationExporter.writeTemporaryFileOffMainActor(
                    messages: shown,
                    title: firstQuestion,
                    format: format
                )
                conversationExport = ConversationExportFile(url: url)
                let answers = shown.filter { $0.role == .assistant }
                VerificationJournal.record(
                    "export.conversation", .ok,
                    ["format": "\(format.rawValue)", "answers": "\(answers.count)",
                        "withSources": "\(answers.filter { !($0.retrievedChunks ?? []).isEmpty }.count)",
                        "bytes": "\(VerificationJournal.fileBytes(url))", "via": "chatMenu"])
            } catch {
                VerificationJournal.record(
                    "export.conversation", .failed,
                    ["format": "\(format.rawValue)", "error": String(describing: type(of: error))])
                Log.error("[Chat] Conversation export failed: \(error.localizedDescription)", category: .pipeline)
                toastManager.show(
                    ToastItem(title: "Export failed", icon: "exclamationmark.triangle", tint: .orange),
                    duration: 2.0
                )
            }
        }
    }

    /// Starts a new conversation, and says whether one was started. One is refused when the plan's
    /// conversation limit is reached (`EvidenceThreadQuotaError`), and the screen is then left as it
    /// is: the conversation stays on it and stays the one its next answer is saved to (5.7). Through
    /// 5.6 the screen was emptied first while the old conversation stayed the one being saved, so the
    /// next question was saved over it with only the new messages. Every caller runs it only while
    /// no answer is being written.
    @discardableResult
    func newChat() -> Bool {
        Tour.used(.moreMenu)
        do {
            try ragService.createNewThread(for: ragService.containerService.activeContainerId)
        } catch let quotaError as EvidenceThreadQuotaError {
            DSHaptics.error()
            toastManager.show(
                ToastItem(title: quotaError.localizedDescription, icon: "lock.fill", tint: .red),
                duration: 4.0
            )
            return false
        } catch {
            Log.error(
                "[ChatScreen] Failed to create new thread: \(error.localizedDescription)", category: .initialization)
            return false
        }

        // Cancel any in-flight query task
        cancelInFlightQueryWork()
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil

        // Reset processing state
        if isProcessing {
            resetStreamingState()
            isProcessing = false
        }

        messages.removeAll()
        stage = .idle
        execution = .unknown
        ttft = nil
        generationStart = nil
        queryStart = nil
        embeddingStart = nil
        searchingStart = nil
        generatingStartTS = nil
        embeddingElapsedFinal = nil
        searchingElapsedFinal = nil
        generatingElapsedFinal = nil
        currentRetrievedChunks = []
        currentMetadata = nil
        currentStructuredAnswer = nil
        followUpSuggestions = []
        toastManager.clearAll()
        showRetrievedDetails = false
        thinkingEvents.removeAll()
        requestedExecutionContext = .automatic
        return true
    }

    func clearChat() {
        // Cancel any in-flight query task
        cancelInFlightQueryWork()
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil

        // Reset processing state
        if isProcessing {
            resetStreamingState()
            isProcessing = false
        }

        messages.removeAll()
        stage = .idle
        generationStart = nil
        queryStart = nil
        embeddingStart = nil
        searchingStart = nil
        generatingStartTS = nil
        embeddingElapsedFinal = nil
        searchingElapsedFinal = nil
        generatingElapsedFinal = nil
        currentRetrievedChunks = []
        currentMetadata = nil
        currentStructuredAnswer = nil
        followUpSuggestions = []
        toastManager.clearAll()
        showRetrievedDetails = false
        thinkingEvents.removeAll()
        requestedExecutionContext = .automatic
        ragService.clearChatHistory(for: ragService.containerService.activeContainerId)
        // The "Your Library" widget drops the cleared conversation's last answer (5.7).
        WidgetSnapshot.forgetAnswer(inLibrary: ragService.containerService.activeContainerId)
    }

    /// Stops generation immediately and preserves partial response
    func stopGeneration() {
        guard isProcessing else { return }

        // An answer whose text is complete is finished, not stopped. Cancelling here would save
        // the text without its sources, because they arrive with the response, so the pipeline
        // is asked to end its checks and return that response instead.
        if isCheckingFinishedAnswer {
            ragService.finishAnswerNow()
            DSHaptics.selection()
            return
        }

        // Cancel the running query task
        cancelInFlightQueryWork()

        // Flush any buffered text immediately
        flushStreamingBufferToVisibleText()

        // If we have partial text, save it as a message
        let sanitizedPartial = sanitizeFinalResponse(streamingText)
        let keptContent = partialResponseMessageContent(
            sanitizedPartial: sanitizedPartial,
            userInitiatedStop: true
        )
        VerificationJournal.record(
            "answer.stopped",
            ["mode": "\(effectiveQualityMode)", "kept": "\(keptContent != nil)",
                "characters": "\(sanitizedPartial.count)"])
        if let partialContent = keptContent {
            var partial = ChatMessage(
                role: .assistant,
                content: partialContent
            )
            partial.containerId = ragService.containerService.activeContainerId
            appendAndPersistMessage(partial, for: partial.containerId ?? ragService.containerService.activeContainerId)
        }

        // Reset all processing state
        resetStreamingState()
        isProcessing = false
        stage = .idle
        DSHaptics.selection()
    }

    /// Regenerates a response by finding the preceding user query
    func regenerateResponse(for message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard !isProcessing else { return }

        // Find the user message that preceded this assistant response
        if let index = messages.firstIndex(where: { $0.id == message.id }),
            index > 0
        {
            let previousMessage = messages[index - 1]
            if previousMessage.role == .user {
                // Remove the assistant response we're regenerating
                messages.remove(at: index)

                // Remove the user message too (sendMessage will re-add it)
                messages.remove(at: index - 1)

                // Re-send the query
                DSHaptics.selection()
                sendMessage(previousMessage.content)
            }
        }
    }

    /// Re-queries the last question using forced agentic (deep reasoning) mode.
    /// Called when user taps "Go Deeper" on a single-pass response.
    func goDeeper() {
        guard !isProcessing else { return }

        DSHaptics.selection()
        cancelInFlightQueryWork()
        followUpSuggestionsTask?.cancel()
        followUpSuggestionsTask = nil
        followUpSuggestions = []

        // Show immediate feedback
        toastManager.show(
            ToastItem(
                title: "Diving deeper with multi-step reasoning...",
                icon: "brain",
                tint: .purple
            ),
            duration: 2.0
        )

        let querySessionId = UUID()
        currentQuerySessionId = querySessionId

        currentQueryTask = Task(priority: .userInitiated) { [weak ragService] in
            guard let capturedService = ragService else { return }

            defer {
                Task { @MainActor in
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.currentQuerySessionId = nil
                    self.currentQueryTask = nil
                    self.isProcessing = false
                    if self.stage == .searching || self.stage == .generating {
                        self.stage = .idle
                    }
                }
            }

            await MainActor.run {
                self.isProcessing = true
                self.stage = .searching
                self.resetStreamingState()
                let start = Date()
                self.queryStart = start
                self.nowTick = start
                self.generationStart = start
            }

            do {
                if let response = try await capturedService.reQueryWithAgenticMode(streamHandler: nil) {
                    await MainActor.run {
                        guard self.currentQuerySessionId == querySessionId else { return }
                        let containerId = capturedService.containerService.activeContainerId
                        // Add the deeper response as a new assistant message
                        var deeperMessage = ChatMessage(
                            role: .assistant,
                            content: sanitizeFinalResponse(response.generatedResponse),
                            metadata: response.metadata,
                            retrievedChunks: response.retrievedChunks,
                            structuredAnswer: response.structuredAnswer
                        )
                        deeperMessage.containerId = containerId
                        deeperMessage.thinkingEvents = self.thinkingEvents
                        self.appendAndPersistMessage(deeperMessage, for: containerId)

                        self.currentRetrievedChunks = response.retrievedChunks
                        self.currentMetadata = response.metadata
                        self.currentStructuredAnswer = response.structuredAnswer
                        if let start = self.queryStart {
                            self.generatingElapsedFinal = Date().timeIntervalSince(start)
                        }
                        self.resetStreamingState()
                        self.stage = .idle

                        DSHaptics.success()
                    }
                } else {
                    await MainActor.run {
                        guard self.currentQuerySessionId == querySessionId else { return }
                        toastManager.show(
                            ToastItem(
                                title: "No previous query to analyze deeper",
                                icon: "exclamationmark.triangle",
                                tint: .orange
                            ),
                            duration: 2.0
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId else { return }
                    self.resetStreamingState()
                }
            } catch {
                await MainActor.run {
                    guard self.currentQuerySessionId == querySessionId else { return }
                    toastManager.show(
                        ToastItem(
                            title: "Deeper analysis failed: \(error.localizedDescription)",
                            icon: "xmark.circle",
                            tint: .red
                        ),
                        duration: 3.0
                    )
                    self.resetStreamingState()
                }
            }
        }
    }

    // MARK: - AI Hub Helpers

    /// Whether there are any assistant messages to operate on
    private var hasAssistantMessages: Bool {
        messages.contains { $0.role == .assistant }
    }

    /// Text content of the last assistant message (for Writing Tools / Image Playground)
    private var lastAssistantMessageText: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }

    /// Present Image Playground with enriched concepts from the last assistant response
    private func illustrateLastResponse() {
        Tour.used(.aiHub)
        guard let text = lastAssistantMessageText else { return }
        illustrate(text)
    }

    /// Opens Image Playground with an answer's text, from the AI Hub (the last answer) or from any answer's Illustrate
    /// button. That button never showed until 5.8: the chat never handed the message list its action (found
    /// 2026-11-03).
    func illustrate(_ text: String) {
        // Wire Image Playground pipeline events into the thinking stream
        ImagePlaygroundService.shared.onThinkingEvent = { event in
            Task { @MainActor in
                thinkingEvents.append(event)
            }
        }

        ImagePlaygroundService.shared.presentPlaygroundFromResponse(text)
    }

    // MARK: - AI Hub Toolbar Button

    /// Extracted into its own @ViewBuilder to prevent type-checker timeout in body.
    @ViewBuilder var aiHubToolbarButton: some View {
        Menu {
            Button {
                guard let text = lastAssistantMessageText else { return }
                performTransformAction(.keyFacts, on: text)
            } label: {
                Label("Key Facts", systemImage: "list.bullet.rectangle")
            }

            Button {
                guard let text = lastAssistantMessageText else { return }
                performTransformAction(.stepByStep, on: text)
            } label: {
                Label("Step-by-Step", systemImage: "checklist")
            }

            Button {
                guard let text = lastAssistantMessageText else { return }
                performTransformAction(.simplify, on: text)
            } label: {
                Label("Plain English", systemImage: "text.bubble")
            }

            Button {
                guard let text = lastAssistantMessageText else { return }
                let q = messages.last(where: { $0.role == .user })?.content ?? ""
                performTransformAction(.whatsMissing, on: text, question: q)
            } label: {
                Label("What's Missing?", systemImage: "questionmark.circle")
            }

            Button {
                illustrateLastResponse()
            } label: {
                Label("Illustrate", systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            Image(systemName: "apple.intelligence")
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hasAssistantMessages ? DSColors.accent : .secondary)
                .tour(.aiHub, in: Tour.chat)
        }
        .disabled(!hasAssistantMessages || isProcessing || writingToolsProcessing)
    }

    // MARK: - WritingTools Actions

    // MARK: - Response Transform Actions (RAG-grounded)

    enum TransformAction {
        case keyFacts, stepByStep, simplify, whatsMissing

        var title: String {
            switch self {
            case .keyFacts: return "Key Facts"
            case .stepByStep: return "Step-by-Step"
            case .simplify: return "Plain English"
            case .whatsMissing: return "What's Missing?"
            }
        }

        var icon: String {
            switch self {
            case .keyFacts: return "list.bullet.rectangle"
            case .stepByStep: return "checklist"
            case .simplify: return "text.bubble"
            case .whatsMissing: return "questionmark.circle"
            }
        }
    }

    /// Transforms the last AI response using RAG-grounded context (source chunks + response).
    /// Each action receives the retrieved chunks so output is backed by the user's actual documents.
    private func performTransformAction(_ action: TransformAction, on text: String, question: String = "") {
        Tour.used(.aiHub)
        guard !writingToolsProcessing else { return }
        DSHaptics.selection()

        writingToolsProcessing = true
        writingToolsTitle = action.title

        // Capture the source chunks that backed this response
        let chunks = currentRetrievedChunks

        // Pre-warm the FM session — reduces first-token latency for the transform.
        // Fire-and-forget: best-effort, silently ignores errors.
        let prewarmService = ResponseTransformService()
        prewarmService.prewarmSession(responsePrefix: String(text.prefix(300)))

        Task {
            do {
                let service = ResponseTransformService()
                let result: String

                switch action {
                case .keyFacts:
                    result = try await service.keyFacts(response: text, chunks: chunks)
                case .stepByStep:
                    result = try await service.stepByStep(response: text, chunks: chunks)
                case .simplify:
                    result = try await service.simplify(response: text, chunks: chunks)
                case .whatsMissing:
                    result = try await service.whatsMissing(response: text, question: question, chunks: chunks)
                }

                await MainActor.run {
                    writingToolsResult = result
                    showWritingToolsResult = true
                    writingToolsProcessing = false
                    DSHaptics.success()
                }
            } catch {
                await MainActor.run {
                    writingToolsProcessing = false
                    let errorMsg = error.localizedDescription
                    let isRateLimit = errorMsg.lowercased().contains("rate") || errorMsg.lowercased().contains("limit")

                    toastManager.show(
                        ToastItem(
                            title: isRateLimit
                                ? "\(action.title) rate-limited — try again"
                                : "\(action.title) failed — try again",
                            icon: "exclamationmark.triangle",
                            tint: .orange
                        ),
                        duration: 4.0
                    )
                }
            }
        }
    }

}

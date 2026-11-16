//
//  ConversationMemoryServiceTests.swift
//  OpenIntelligenceTests
//
//  Pins the 5.8 conversation-context fix of 2026-11-15: a cleared memory stays cleared, a refused answer never goes
//  back into a prompt, and nothing from before a library's documents changed does either. None of it needs Apple's
//  model.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ConversationMemoryServiceTests: XCTestCase {
    private var memory: ConversationMemoryService { ConversationMemoryService.shared }

    override func setUp() {
        super.setUp()
        DirectModelCallsForTesting.disabled = true
    }

    override func tearDown() {
        DirectModelCallsForTesting.disabled = false
        super.tearDown()
    }

    private func savedMemory(_ library: UUID) throws -> ConversationMemory? {
        let url = AppSupportPaths.baseDir().appendingPathComponent("conversation_memory_\(library.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConversationMemory.self, from: Data(contentsOf: url))
    }

    // MARK: A. A clear sticks

    func testAClearSavesAnEmptyMemoryInsteadOfDeletingTheFile() async throws {
        let library = UUID()
        await memory.addTurn(
            userQuery: "What is the rent?", assistantResponse: "The rent is $1,200 [S1].", for: library)
        memory.flushPendingSavesNow()
        ConversationMemoryService.waitForWrites()
        XCTAssertEqual(try savedMemory(library)?.recentTurns.count, 1)

        memory.clearMemory(for: library)
        ConversationMemoryService.waitForWrites()

        let saved = try XCTUnwrap(try savedMemory(library), "an empty memory is saved, so an iCloud merge keeps it")
        XCTAssertTrue(saved.recentTurns.isEmpty)
        XCTAssertTrue(saved.summary.isEmpty)
        XCTAssertTrue(saved.entities.isEmpty)
        memory.dropCachedMemories()
        XCTAssertTrue(memory.memory(for: library).recentTurns.isEmpty)
    }

    func testAClearDropsTheSaveStillWaitingForItsDebounce() async throws {
        let library = UUID()
        await memory.addTurn(
            userQuery: "What is the rent?", assistantResponse: "The rent is $1,200 [S1].", for: library)
        memory.clearMemory(for: library)
        // The debounce is two seconds; past it, the turn must not have been written back.
        try await Task.sleep(for: .seconds(2.6))
        ConversationMemoryService.waitForWrites()
        XCTAssertEqual(try savedMemory(library)?.recentTurns.count, 0)
        memory.dropCachedMemories()
        XCTAssertTrue(memory.memory(for: library).recentTurns.isEmpty)
    }

    func testASummaryStartedBeforeAClearDoesNotWriteTheConversationBack() async throws {
        let library = UUID()
        // The ninth turn (3 kept + 5 before summarizing) starts a background summary.
        for index in 0..<9 {
            await memory.addTurn(
                userQuery: "Question \(index) about the lease?", assistantResponse: "Answer \(index). It says so [S1].",
                for: library)
        }
        memory.clearMemory(for: library)
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(memory.memory(for: library).recentTurns.isEmpty)
        XCTAssertTrue(memory.memory(for: library).summary.isEmpty)
    }

    // MARK: D. Refused turns

    func testTheRefusalPredicate() {
        let refusal = StructuredAnswer.refusal(reason: "Not found in your documents.")
        XCTAssertTrue(ConversationContextRules.isRefusal(structuredAnswer: refusal, gatingDecision: nil))
        for decision in [
            "no_sources", "rerank_empty", "low_confidence", "mmr_empty", "high_accuracy_blocked", "context_empty",
            "relevance_gate_failed", "missing_citations", "source_only_abstained",
            "verification_gates_failed:citation,coverage", "relevance_gate_failed,finished_early_by_person",
        ] {
            XCTAssertTrue(
                ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: decision), decision)
        }
        for decision in ["no_documents", "excerpts_only", "verified:92%", "answers:none", "source_only_refined"] {
            XCTAssertFalse(
                ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: decision), decision)
        }
        XCTAssertFalse(ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: nil))
    }

    func testARefusedTurnIsKeptButNeverInjected() async {
        let library = UUID()
        await memory.addTurn(
            userQuery: "What is the pet policy?", assistantResponse: "Your documents do not say.", refused: true,
            for: library)
        XCTAssertEqual(memory.memory(for: library).recentTurns.count, 1)
        XCTAssertTrue(memory.memory(for: library).recentTurns[0].refused)
        XCTAssertEqual(memory.contextInjection(for: library, query: "And the deposit?"), "")

        await memory.addTurn(
            userQuery: "What is the rent?", assistantResponse: "The rent is $1,200 a month [S1].", for: library)
        let context = memory.contextInjection(for: library, query: "When is it due?")
        XCTAssertTrue(context.contains("What is the rent?"), context)
        XCTAssertFalse(context.contains("pet policy"), context)
        XCTAssertFalse(context.contains("do not say"), context)
        memory.clearMemory(for: library)
    }

    func testAMemorySavedBeforeTheRefusedFieldStillReads() throws {
        let json = """
            {"id":"\(UUID().uuidString)","userQuery":"Q","assistantResponse":"A","timestamp":"2026-11-01T10:00:00Z",
             "extractedFacts":["A."],"importanceScore":0.5}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let turn = try decoder.decode(MemoryTurn.self, from: Data(json.utf8))
        XCTAssertFalse(turn.refused)
        XCTAssertEqual(turn.userQuery, "Q")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var refused = MemoryTurn(userQuery: "Q", assistantResponse: "A", refused: true)
        refused.importanceScore = 0.4
        let back = try decoder.decode(MemoryTurn.self, from: encoder.encode(refused))
        XCTAssertTrue(back.refused)
        XCTAssertEqual(back.importanceScore, 0.4)
    }

    // MARK: C. A change of documents ends the earlier context

    func testTurnsFromBeforeTheDocumentsChangedAreNotInjected() async {
        let library = UUID()
        await memory.addTurn(
            userQuery: "What is the rent?", assistantResponse: "The rent is $1,200 a month [S1].", for: library)
        let changed = Date().addingTimeInterval(1)
        XCTAssertEqual(memory.contextInjection(for: library, query: "When is it due?", documentsChangedAt: changed), "")
        XCTAssertFalse(
            memory.contextInjection(
                for: library, query: "When is it due?", documentsChangedAt: changed.addingTimeInterval(-3600)
            ).isEmpty)
        memory.clearMemory(for: library)
    }

    func testTheSummaryIsUsedOnlyWhenItBeganAfterTheChange() {
        var memory = ConversationMemory(containerId: UUID())
        memory.summary = "They asked about the rent."
        let changed = Date()
        XCTAssertTrue(ConversationContextRules.summaryIsUsable(memory, documentsChangedAt: nil))
        XCTAssertFalse(
            ConversationContextRules.summaryIsUsable(memory, documentsChangedAt: changed), "unknown start is not used")
        memory.firstTurnAt = changed.addingTimeInterval(-10)
        XCTAssertFalse(ConversationContextRules.summaryIsUsable(memory, documentsChangedAt: changed))
        memory.firstTurnAt = changed.addingTimeInterval(10)
        XCTAssertTrue(ConversationContextRules.summaryIsUsable(memory, documentsChangedAt: changed))
    }

    func testAMemorySavedBeforeFirstTurnAtNeverCountsAsBegunAfterAChange() async throws {
        let library = UUID()
        var old = ConversationMemory(containerId: library)
        old.summary = "They asked about the old lease's rent."
        old.entities = ["Old Lease"]
        old.recentTurns = [
            MemoryTurn(userQuery: "Old?", assistantResponse: "Old answer.", timestamp: Date(timeIntervalSinceNow: -600))
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoder.encode(old)) as? [String: Any])
        json.removeValue(forKey: "firstTurnAt")
        let url = AppSupportPaths.baseDir().appendingPathComponent("conversation_memory_\(library.uuidString).json")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        memory.dropCachedMemories()
        XCTAssertNil(memory.memory(for: library).firstTurnAt, "a file from before 5.8 reads")
        XCTAssertEqual(memory.memory(for: library).summary, old.summary)

        let changed = Date()
        try await Task.sleep(for: .milliseconds(20))
        await memory.addTurn(userQuery: "What is the rent now?", assistantResponse: "It is $1,300 [S1].", for: library)
        XCTAssertEqual(memory.memory(for: library).firstTurnAt, .distantPast)
        let context = memory.contextInjection(for: library, query: "When is it due?", documentsChangedAt: changed)
        XCTAssertTrue(context.contains("What is the rent now?"), context)
        XCTAssertFalse(context.contains("old lease"), context)
        XCTAssertFalse(context.contains("Old Lease"), context)
        XCTAssertFalse(context.contains("Old?"), context)
        memory.clearMemory(for: library)
    }

    func testEarlierMessagesLeaveOutRefusalsFailuresAndTheirQuestions() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func answer(
            _ text: String, at offset: TimeInterval, gating: String? = "verified:90%", refusal: Bool = false
        )
            -> ChatMessage
        {
            ChatMessage(
                role: .assistant, content: text, timestamp: base.addingTimeInterval(offset),
                metadata: ResponseMetadata(
                    totalGenerationTime: 1, tokensGenerated: 10, modelUsed: "test", retrievalTime: 0,
                    gatingDecision: gating),
                structuredAnswer: refusal ? StructuredAnswer.refusal(reason: text) : nil)
        }
        func question(_ text: String, at offset: TimeInterval) -> ChatMessage {
            ChatMessage(role: .user, content: text, timestamp: base.addingTimeInterval(offset))
        }
        let messages = [
            ChatMessage(role: .system, content: "system", timestamp: base),
            question("Q1 old", at: 1), answer("A1 old", at: 2),
            question("Q2 refused", at: 10), answer("A2 refused", at: 11, refusal: true),
            question("Q3 gated", at: 12), answer("A3 gated", at: 13, gating: "relevance_gate_failed"),
            question("Q4 failed", at: 14),
            ChatMessage(role: .assistant, content: "Something went wrong.", timestamp: base.addingTimeInterval(15)),
            question("Q5 good", at: 16), answer("A5 good", at: 17),
            question("Q6 open", at: 18),
        ]
        let all = ConversationContextRules.usableEarlierMessages(messages, documentsChangedAt: nil).map(\.content)
        XCTAssertEqual(all, ["Q1 old", "A1 old", "Q5 good", "A5 good", "Q6 open"])
        let afterChange = ConversationContextRules.usableEarlierMessages(
            messages, documentsChangedAt: base.addingTimeInterval(5)
        ).map(\.content)
        XCTAssertEqual(afterChange, ["Q5 good", "A5 good", "Q6 open"])
        let straddling = ConversationContextRules.usableEarlierMessages(
            messages, documentsChangedAt: base.addingTimeInterval(16.5)
        ).map(\.content)
        XCTAssertEqual(straddling, ["Q6 open"], "an answer whose question came before the change goes with it")
    }

    func testADocumentChangeIsRecordedPerLibraryAndSurvivesARelaunch() throws {
        let suite = "ConversationMemoryServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lease = UUID()
        let manual = UUID()
        let leaseDoc = UUID()
        let manualDoc = UUID()
        let changes = LibraryDocumentChanges(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            changes.record([(leaseDoc, lease, 10), (manualDoc, manual, 40)], now: start), [],
            "the first look records no change")
        XCTAssertNil(changes.changedAt(lease))
        XCTAssertEqual(changes.record([(manualDoc, manual, 40), (leaseDoc, lease, 10)], now: start + 1), [])

        // A re-import gives the document a new id; a re-parse changes its passage count.
        let reimported = UUID()
        XCTAssertEqual(changes.record([(reimported, lease, 10), (manualDoc, manual, 40)], now: start + 2), [lease])
        XCTAssertEqual(changes.changedAt(lease), start + 2)
        XCTAssertNil(changes.changedAt(manual))
        XCTAssertEqual(changes.record([(reimported, lease, 12), (manualDoc, manual, 40)], now: start + 3), [lease])
        XCTAssertEqual(changes.changedAt(lease), start + 3)

        // The last document going is a change; so is one coming back.
        XCTAssertEqual(changes.record([(reimported, lease, 12)], now: start + 4), [manual])
        XCTAssertEqual(changes.record([(reimported, lease, 12)], now: start + 5), [])
        XCTAssertEqual(changes.record([(reimported, lease, 12), (manualDoc, manual, 40)], now: start + 6), [manual])

        // After the first look, a library given its first documents is a change.
        let fresh = UUID()
        XCTAssertEqual(
            changes.record([(reimported, lease, 12), (manualDoc, manual, 40), (UUID(), fresh, 3)], now: start + 6.5),
            [fresh])

        let relaunched = LibraryDocumentChanges(defaults: defaults)
        XCTAssertEqual(relaunched.changedAt(lease), start + 3)
        XCTAssertEqual(relaunched.changedAt(manual), start + 6)
        XCTAssertEqual(relaunched.record([(reimported, lease, 12), (manualDoc, manual, 40)], now: start + 7), [fresh])

        // A first look at libraries that are all empty still counts as the first look.
        let emptySuite = "ConversationMemoryServiceTests.\(UUID().uuidString)"
        let emptyDefaults = try XCTUnwrap(UserDefaults(suiteName: emptySuite))
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let emptyStart = LibraryDocumentChanges(defaults: emptyDefaults)
        XCTAssertEqual(emptyStart.record([], now: start), [])
        XCTAssertEqual(emptyStart.record([(leaseDoc, lease, 10)], now: start + 1), [lease])
    }

    // MARK: F. Refusals no gate recorded (2026-11-16)

    func testTheRefusalMarkIsReadAsARefusalAndLeavesTheBadgeAsItWas() {
        let token = ConversationContextRules.refusedToken
        XCTAssertEqual(ConversationContextRules.markingRefusal(nil), token)
        XCTAssertEqual(ConversationContextRules.markingRefusal(""), token)
        XCTAssertEqual(ConversationContextRules.markingRefusal("excerpts_only"), "excerpts_only,\(token)")
        XCTAssertEqual(
            ConversationContextRules.markingRefusal("excerpts_only,\(token)"), "excerpts_only,\(token)", "marked once")
        for decision in [nil, "excerpts_only", "verified:90%", "unverified:coverage", "no_documents", "answers:none"] {
            let marked = ConversationContextRules.markingRefusal(decision)
            XCTAssertTrue(ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: marked), marked)
            XCTAssertEqual(
                VerificationOutcome.from(gatingDecision: marked), VerificationOutcome.from(gatingDecision: decision),
                "the badge reads the mark as nothing: \(marked)")
        }
    }

    func testStandardsNotFoundTextAndThePlannersAbstentionAreRefusals() {
        for answer in [RAGService.notFoundAnswer, RAGService.plannerAbstention] {
            let marked = RAGService.markingUngatedRefusal("verification_skipped", answer: answer, cutOffByGuardrail: false)
            XCTAssertTrue(ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: marked), answer)
        }
    }

    func testAnAnswerAGuardrailCutOffIsARefusal() {
        XCTAssertEqual(
            ModelErrorClassifier.kind(of: LLMError.generationFailed(ModelErrorClassifier.guardrailMessage)),
            .contentFiltered, "what the app throws for the guardrail reads as one")
        let marked = RAGService.markingUngatedRefusal(
            "verified:88%", answer: "The recommended dose for adults is", cutOffByGuardrail: true)
        XCTAssertTrue(ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: marked))
        XCTAssertEqual(
            RAGService.markingUngatedRefusal(
                "verified:88%", answer: "The recommended dose for adults is 5 mg [S1].", cutOffByGuardrail: false),
            "verified:88%", "a whole answer is left as it was")
    }

    func testTheChatShowsTheGatingDecisionWithoutTheMark() {
        let token = ConversationContextRules.refusedToken
        XCTAssertNil(ConversationContextRules.shownGatingDecision(nil))
        XCTAssertNil(ConversationContextRules.shownGatingDecision(token), "no badge where none showed")
        XCTAssertEqual(ConversationContextRules.shownGatingDecision("excerpts_only,\(token)"), "excerpts_only")
        XCTAssertEqual(ConversationContextRules.shownGatingDecision("verified:90%"), "verified:90%")
    }

    func testDeepThinksNotFoundExitIsARefusal() {
        let marked = RAGService.markingUngatedRefusal(
            nil, answer: "I couldn't find information about \"x\" in your documents.", cutOffByGuardrail: false,
            refused: true)
        XCTAssertEqual(marked, ConversationContextRules.refusedToken)
        let result = AgenticResult(
            finalAnswer: "a", steps: [], totalTokens: 0, totalDuration: 0, confidence: 1, sourcesUsed: 0,
            retrievedChunks: [])
        XCTAssertFalse(result.refused, "a run's answer is not a refusal unless the run says so")
    }

    func testTheModelRefusingInItsOwnWords() {
        for refusal in [
            "Your documents do not say what the pet policy is.",
            "I couldn\u{2019}t find any information about the parking rules in the provided documents.",
            "The provided documents do not contain information about the deposit. You could try adding the addendum.",
            "I'm unable to find the warranty period in these passages.",
            "There is no information about late fees in your documents.",
            "Insufficient evidence in provided sources.",
        ] {
            XCTAssertTrue(ConversationContextRules.refusesInItsOwnWords(refusal), refusal)
            XCTAssertNotNil(
                RAGService.markingUngatedRefusal(nil, answer: refusal, cutOffByGuardrail: false), refusal)
        }
        let longGap =
            "The documents do not mention a grace period. "
            + String(repeating: "Rent is due on the first of each month and is paid by bank transfer. ", count: 8)
        for answer in [
            "The rent is $1,200 a month [S1].",
            "The lease does not mention a pet fee, but pets need written approval [S2].",
            "Rent is due on the first. The lease does not mention a grace period.",
            // Negative findings are answers, and usually uncited (review, 2026-11-16).
            "No, the lease does not mention pets.",
            "No, the contract does not contain a non-compete clause.",
            "The policy doesn't say who pays; section 4 assigns repairs to the tenant.",
            "The lease does not mention a pet fee.",
            longGap,
            "",
        ] {
            XCTAssertFalse(ConversationContextRules.refusesInItsOwnWords(answer), answer)
            XCTAssertEqual(
                RAGService.markingUngatedRefusal("verified:90%", answer: answer, cutOffByGuardrail: false),
                "verified:90%", answer)
        }
    }

    func testAMarkedRefusalIsLeftOutOfTheChatHistoryAndTheMemory() async {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let marked = ConversationContextRules.markingRefusal("excerpts_only")
        let messages = [
            ChatMessage(role: .user, content: "Q1 pets", timestamp: base),
            ChatMessage(
                role: .assistant, content: "I couldn't find words in your documents that answer this.",
                timestamp: base.addingTimeInterval(1),
                metadata: ResponseMetadata(
                    totalGenerationTime: 0, tokensGenerated: 0, modelUsed: "Quotes only", retrievalTime: 0,
                    gatingDecision: marked)),
            ChatMessage(role: .user, content: "Q2 open", timestamp: base.addingTimeInterval(2)),
        ]
        XCTAssertEqual(
            ConversationContextRules.usableEarlierMessages(messages, documentsChangedAt: nil).map(\.content),
            ["Q2 open"])

        let library = UUID()
        await memory.addTurn(
            userQuery: "Q1 pets", assistantResponse: "I couldn't find words in your documents that answer this.",
            refused: ConversationContextRules.isRefusal(structuredAnswer: nil, gatingDecision: marked), for: library)
        XCTAssertEqual(memory.contextInjection(for: library, query: "And the deposit?"), "")
        memory.clearMemory(for: library)
    }

    // MARK: G. Siri's hand-off answer (2026-11-16)

    func testASiriHandOffAnswerStaysInTheChatHistory() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let handOff = ConversationContextRules.handOffMessages(
            question: "When is the rent due?", answer: "On the first of each month.", at: base)
        let messages = handOff + [ChatMessage(role: .user, content: "And the late fee?", timestamp: base + 5)]
        XCTAssertEqual(
            ConversationContextRules.usableEarlierMessages(messages, documentsChangedAt: nil).map(\.content),
            ["When is the rent due?", "On the first of each month.", "And the late fee?"],
            "with conversation memory off, the chat history is the only way the next question sees Siri's answer")

        // As the chat saves and reloads it.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let reloaded = try messages.map { message in
            try decoder.decode(ChatMessage.self, from: encoder.encode(message.sanitizedForPersistence()))
        }
        XCTAssertEqual(
            ConversationContextRules.usableEarlierMessages(reloaded, documentsChangedAt: nil).map(\.content),
            ["When is the rent due?", "On the first of each month.", "And the late fee?"])

        // A refusal Siri handed over goes, with its question, like any refusal.
        let refusedHandOff = ConversationContextRules.handOffMessages(
            question: "What is the pet policy?", answer: "I couldn't find the pet policy in your documents.", at: base)
        XCTAssertEqual(
            ConversationContextRules.usableEarlierMessages(
                refusedHandOff + [ChatMessage(role: .user, content: "And the deposit?", timestamp: base + 5)],
                documentsChangedAt: nil
            ).map(\.content), ["And the deposit?"])

        // An error message the app wrote still goes, with its question.
        let failed = [
            ChatMessage(role: .user, content: "Q", timestamp: base),
            ChatMessage(role: .assistant, content: "Something went wrong.", timestamp: base + 1),
        ]
        XCTAssertEqual(ConversationContextRules.usableEarlierMessages(failed, documentsChangedAt: nil).count, 0)
    }

    // MARK: H. A deleted library's memory (2026-11-16)

    private func memoryFileExists(_ library: UUID) -> Bool {
        FileManager.default.fileExists(
            atPath: AppSupportPaths.baseDir().appendingPathComponent(
                "conversation_memory_\(library.uuidString).json"
            ).path)
    }

    func testRemovingALibrarysMemoryDeletesTheFileAndNothingWritesItBack() async {
        let library = UUID()
        await memory.addTurn(userQuery: "What is the rent?", assistantResponse: "$1,200 [S1].", for: library)
        memory.flushPendingSavesNow()
        ConversationMemoryService.waitForWrites()
        XCTAssertTrue(memoryFileExists(library))

        // A turn waiting for its debounced save when the library goes.
        await memory.addTurn(userQuery: "When is it due?", assistantResponse: "On the first [S1].", for: library)
        memory.removeMemory(for: library)
        memory.flushPendingSavesNow()
        ConversationMemoryService.waitForWrites()
        XCTAssertFalse(memoryFileExists(library))

        // A turn or a clear arriving after the deletion writes nothing.
        await memory.addTurn(userQuery: "Late?", assistantResponse: "Ten days [S2].", for: library)
        memory.clearMemory(for: library)
        memory.flushPendingSavesNow()
        ConversationMemoryService.waitForWrites()
        XCTAssertFalse(memoryFileExists(library))
        XCTAssertTrue(memory.memory(for: library).recentTurns.isEmpty)
    }

    func testDeletingALibraryRemovesItsConversationMemory() async throws {
        #if os(macOS)
            // It makes and deletes a library, which on the Mac is the owner's real library list.
            throw XCTSkip("Simulator only")
        #endif
        // A second library needs a paid plan, as `ShortcutsActionTests` sets it.
        let tierKey = "entitlement.activeTier"
        let savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        addTeardownBlock { UserDefaults.standard.set(savedTier, forKey: tierKey) }
        let libraries = ContainerService()
        let library = try libraries.createContainer(name: "Memory delete \(UUID().uuidString.prefix(8))")
        let id = library.id
        addTeardownBlock { @MainActor in
            if libraries.containers.contains(where: { $0.id == id }) { libraries.deleteContainer(id: id) }
        }
        await memory.addTurn(userQuery: "What is the rent?", assistantResponse: "$1,200 [S1].", for: library.id)
        memory.flushPendingSavesNow()
        ConversationMemoryService.waitForWrites()
        XCTAssertTrue(memoryFileExists(library.id))

        libraries.deleteContainer(id: library.id)
        XCTAssertFalse(libraries.containers.contains { $0.id == library.id }, "the library was deleted")
        ConversationMemoryService.waitForWrites()
        XCTAssertFalse(memoryFileExists(library.id), "its memory went with it")
    }
}

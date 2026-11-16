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
}

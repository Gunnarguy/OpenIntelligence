//
//  ConversationMemoryService.swift
//  OpenIntelligence
//
//  Provides persistent conversation memory with intelligent summarization.
//  Enables multi-turn RAG by injecting relevant conversation context into queries.
//
//  Key Features:
//  - Summarizes long conversation history to fit within context window
//  - Extracts key entities and topics mentioned across turns
//  - Provides memory injection for follow-up questions
//  - Maintains per-container conversation context
//
//  Research Basis:
//  - "MemGPT" (Packer et al., 2023): Hierarchical memory for unbounded context
//  - "Conversation Memory" patterns from LangChain/LlamaIndex
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Conversation Memory Types

/// A compressed summary of conversation history for context injection
struct ConversationMemory: Codable, Sendable {
    /// Unique identifier for the memory
    let id: UUID

    /// Container this memory belongs to
    let containerId: UUID

    /// Summarized conversation context (compressed)
    var summary: String

    /// Key entities mentioned in the conversation (people, places, concepts)
    var entities: [String]

    /// Recent exchange pairs (last N turns) for immediate context
    var recentTurns: [MemoryTurn]

    /// Topics discussed in this conversation
    var topics: [String]

    /// When this memory was last updated
    var lastUpdated: Date

    /// Number of total turns summarized into this memory
    var totalTurnsSummarized: Int

    /// When the first turn behind the summary and the key topics was added (5.8). Nil in a memory saved before 5.8,
    /// which is read as "unknown": once the library's documents change, that memory's summary and topics are not
    /// given to the model.
    var firstTurnAt: Date?

    init(containerId: UUID) {
        id = UUID()
        self.containerId = containerId
        summary = ""
        entities = []
        recentTurns = []
        topics = []
        lastUpdated = Date()
        totalTurnsSummarized = 0
    }
}

/// A single conversation turn (user query + assistant response) for memory tracking
struct MemoryTurn: Codable, Sendable, Identifiable {
    let id: UUID
    let userQuery: String
    let assistantResponse: String
    let timestamp: Date

    /// Key facts extracted from this turn
    var extractedFacts: [String]

    /// Importance score (0-1) for prioritizing high-value turns during summarization
    /// Higher scores = preserved longer before summarization
    var importanceScore: Float

    /// Whether the answer was a refusal (5.8, `ConversationContextRules.isRefusal`). A refused turn and its question
    /// are kept on record but never given to the model or the query rewriter again: through 5.8's first builds a
    /// refusal from before a re-import kept the next questions refusing until Clear Chat. False in older files.
    var refused: Bool

    init(userQuery: String, assistantResponse: String, timestamp: Date = Date(), refused: Bool = false) {
        id = UUID()
        self.userQuery = userQuery
        self.assistantResponse = assistantResponse
        self.timestamp = timestamp
        extractedFacts = []
        importanceScore = 0.5 // Default mid-importance
        self.refused = refused
    }

    private enum CodingKeys: String, CodingKey {
        case id, userQuery, assistantResponse, timestamp, extractedFacts, importanceScore, refused
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userQuery = try container.decode(String.self, forKey: .userQuery)
        assistantResponse = try container.decode(String.self, forKey: .assistantResponse)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        extractedFacts = try container.decode([String].self, forKey: .extractedFacts)
        importanceScore = try container.decode(Float.self, forKey: .importanceScore)
        refused = try container.decodeIfPresent(Bool.self, forKey: .refused) ?? false
    }

    /// Calculate importance based on information density
    mutating func calculateImportance() {
        var score: Float = 0.5

        // Longer, more substantive responses are more important
        let responseWordCount = assistantResponse.split(separator: " ").count
        if responseWordCount > 100 { score += 0.15 }
        else if responseWordCount > 50 { score += 0.1 }
        else if responseWordCount < 15 { score -= 0.1 }

        // Turns with extracted facts are more important
        score += Float(min(extractedFacts.count, 5)) * 0.05

        // Questions with specificity indicators are more important
        let specificityIndicators = ["how", "why", "explain", "what is", "difference between", "compare"]
        if specificityIndicators.contains(where: { userQuery.lowercased().contains($0) }) {
            score += 0.1
        }

        // Technical/factual queries are more important to remember
        let technicalIndicators = ["specification", "number", "date", "name", "definition", "formula"]
        if technicalIndicators.contains(where: { userQuery.lowercased().contains($0) }) {
            score += 0.1
        }

        importanceScore = min(1.0, max(0.0, score))
    }
}

// MARK: - What earlier turns may reach a prompt (5.8)

/// Which earlier turns of a conversation may be given to the model and the query rewriter. Two rules, both from a
/// person who re-imported fixed documents and kept getting refusals in the open chat until Clear Chat (2026-11-15):
/// a refused answer never goes back into a prompt, and nothing from before the library's documents last changed does.
nonisolated enum ConversationContextRules {
    /// The gating decisions only a refusal records. "no_documents" is not one: an answer given without passages
    /// records it too. A refusal with that decision is caught by `StructuredAnswer.refuse` instead.
    static let refusalDecisions: Set<String> = [
        "no_sources", "rerank_empty", "low_confidence", "mmr_empty", "high_accuracy_blocked", "context_empty",
        "relevance_gate_failed", "missing_citations", "source_only_abstained",
    ]
    /// A decision that starts with this is a refusal too; the failed gates follow it.
    static let refusalDecisionPrefix = "verification_gates_failed"

    /// Whether an answer was a refusal: its structured answer says so, or its gating decision (a comma-separated
    /// record) holds a decision only a refusal records.
    static func isRefusal(structuredAnswer: StructuredAnswer?, gatingDecision: String?) -> Bool {
        if structuredAnswer?.refuse == true { return true }
        guard let gatingDecision else { return false }
        return gatingDecision.split(separator: ",").contains { token in
            let decision = token.trimmingCharacters(in: .whitespaces)
            return refusalDecisions.contains(decision) || decision.hasPrefix(refusalDecisionPrefix)
        }
    }

    /// An assistant message the app wrote for a failure (an error, or an answer cut off), which has neither the
    /// answer's metadata nor a structured answer.
    @MainActor static func isErrorMessage(_ message: ChatMessage) -> Bool {
        message.role == .assistant && message.metadata == nil && message.structuredAnswer == nil
    }

    /// Whether a memory turn may be given to the model: not refused, and not older than the library's last change
    /// of documents.
    @MainActor static func isUsable(_ turn: MemoryTurn, documentsChangedAt: Date?) -> Bool {
        guard !turn.refused else { return false }
        guard let documentsChangedAt else { return true }
        return turn.timestamp >= documentsChangedAt
    }

    /// Whether a memory's summary and key topics may be given to the model: they come from turns since
    /// `firstTurnAt`, so not once the documents changed after that (or when it is unknown).
    @MainActor static func summaryIsUsable(_ memory: ConversationMemory, documentsChangedAt: Date?) -> Bool {
        guard let documentsChangedAt else { return true }
        guard let firstTurnAt = memory.firstTurnAt else { return false }
        return firstTurnAt >= documentsChangedAt
    }

    /// The earlier messages of a chat that may be given to the model, oldest first: no system messages, none from
    /// before the library's documents last changed, and no refused or failed answer, together with the question
    /// it answered.
    @MainActor static func usableEarlierMessages(_ messages: [ChatMessage], documentsChangedAt: Date?) -> [ChatMessage] {
        let conversation = messages.filter { $0.role != .system }
        var dropped = Set<Int>()
        for (index, message) in conversation.enumerated() {
            let asked = index > 0 && conversation[index - 1].role == .user ? index - 1 : nil
            // An answer goes with its question: one asked before the change goes, even if answered after it.
            if let documentsChangedAt {
                let questionBefore =
                    message.role == .assistant && asked.map { conversation[$0].timestamp < documentsChangedAt } == true
                if message.timestamp < documentsChangedAt || questionBefore {
                    dropped.insert(index)
                    continue
                }
            }
            guard message.role == .assistant else { continue }
            let refused =
                isErrorMessage(message)
                || isRefusal(structuredAnswer: message.structuredAnswer, gatingDecision: message.metadata?.gatingDecision)
            guard refused else { continue }
            dropped.insert(index)
            if let asked { dropped.insert(asked) }
        }
        return conversation.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
    }
}

/// When each library's set of documents last changed (5.8), kept in this device's defaults so it survives a relaunch.
/// A change is a document added to or gone from the library, or a document whose passage count changed; a document's
/// summary passage or its content tags are not. Earlier conversation turns are not given to the model once the
/// documents they were answered from changed (`ConversationContextRules`).
@MainActor
final class LibraryDocumentChanges {
    static let shared = LibraryDocumentChanges(defaults: .standard)

    static let tokensKey = "libraryDocumentTokens"
    static let changedAtKey = "libraryDocumentsChangedAt"
    static let seededKey = "libraryDocumentTokensSeeded"

    private let defaults: UserDefaults
    private var tokens: [String: String]
    private var changedAt: [String: Double]
    /// Whether a first look has been recorded. After it, a library seen for the first time (one that had no
    /// documents, given its first) is a change.
    private var seeded: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        tokens = defaults.dictionary(forKey: Self.tokensKey) as? [String: String] ?? [:]
        changedAt = defaults.dictionary(forKey: Self.changedAtKey) as? [String: Double] ?? [:]
        seeded = defaults.bool(forKey: Self.seededKey)
    }

    /// When the library's documents last changed, or nil if no change has been seen since 5.8.
    func changedAt(_ libraryId: UUID) -> Date? {
        changedAt[libraryId.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    /// Compares each library's documents (id and passage count) with what was last recorded, and records `now` for
    /// each library whose set differs. The first look records no change, so the first launch of 5.8 ends no
    /// conversation; after it, a library given its first documents is a change, and so is one left with none.
    @discardableResult
    func record(_ documents: [(id: UUID, library: UUID, passages: Int)], now: Date = Date()) -> [UUID] {
        var byLibrary: [String: [(id: UUID, passages: Int)]] = [:]
        for document in documents {
            byLibrary[document.library.uuidString, default: []].append((id: document.id, passages: document.passages))
        }
        var current: [String: String] = [:]
        for (library, documents) in byLibrary {
            current[library] = RAGService.queryCacheDocumentsToken(documents, appVersion: "")
        }
        let emptyToken = RAGService.queryCacheDocumentsToken([], appVersion: "")
        var changed: [UUID] = []
        for library in Set(current.keys).union(tokens.keys) {
            let new = current[library] ?? emptyToken
            guard let old = tokens[library] ?? (seeded ? emptyToken : nil) else { continue }
            if old != new, let id = UUID(uuidString: library) {
                changedAt[library] = now.timeIntervalSince1970
                changed.append(id)
            }
        }
        var next = tokens
        for (library, token) in current { next[library] = token }
        for library in tokens.keys where current[library] == nil { next[library] = emptyToken }
        if !seeded {
            seeded = true
            defaults.set(true, forKey: Self.seededKey)
        }
        guard next != tokens || !changed.isEmpty else { return [] }
        tokens = next
        defaults.set(tokens, forKey: Self.tokensKey)
        if !changed.isEmpty {
            defaults.set(changedAt, forKey: Self.changedAtKey)
        }
        return changed
    }
}

/// Configuration for conversation memory behavior
struct ConversationMemoryConfig: Sendable {
    /// Maximum recent turns to keep verbatim (not summarized)
    let maxRecentTurns: Int

    /// Maximum characters for the memory summary
    let maxSummaryLength: Int

    /// Minimum turns before triggering summarization
    let summarizationThreshold: Int

    /// Maximum entities to track
    let maxEntities: Int

    /// Maximum topics to track
    let maxTopics: Int

    static let `default` = ConversationMemoryConfig(
        maxRecentTurns: 3,
        maxSummaryLength: 1000,
        summarizationThreshold: 5,
        maxEntities: 20,
        maxTopics: 10
    )

    static let compact = ConversationMemoryConfig(
        maxRecentTurns: 2,
        maxSummaryLength: 500,
        summarizationThreshold: 3,
        maxEntities: 10,
        maxTopics: 5
    )
}

// MARK: - Conversation Memory Service

/// Service for managing conversation memory with intelligent summarization.
///
/// Provides:
/// 1. **Incremental Summarization**: Compresses old turns into a running summary
/// 2. **Entity Tracking**: Maintains list of key entities across the conversation
/// 3. **Context Injection**: Formats memory for inclusion in RAG prompts
/// 4. **Persistence**: Saves/loads memory to disk per container
/// 5. **Semantic Relevance Scoring**: Prioritizes memory most relevant to current query
/// 6. **Query-Adaptive Budgeting**: Scales memory injection based on query complexity
///
/// Performance Optimizations:
/// - Debounced disk writes (2 second delay) to prevent thrashing
/// - Non-blocking summarization (runs in background)
/// - Token-aware context injection to respect 4K limit
/// - Semantic filtering to maximize signal-to-noise ratio
@available(iOS 26.0, *)
@MainActor
final class ConversationMemoryService {
    // MARK: - Singleton

    static let shared = ConversationMemoryService()
    private init() {}

    // MARK: - In-Memory Cache

    /// Per-container memory cache
    private var memoryCache: [UUID: ConversationMemory] = [:]

    // MARK: - Debounced Persistence

    /// Containers with pending saves (debounced to prevent disk thrashing)
    private var pendingSaves: Set<UUID> = []
    private var saveTask: Task<Void, Never>?
    private let saveDebounceDuration: TimeInterval = 2.0

    /// Every write of a memory file goes through this one queue, in order, so the empty memory a clear writes is
    /// never overtaken by an older write still on its way (5.8).
    private nonisolated static let writeQueue = DispatchQueue(label: "ConversationMemoryService.write", qos: .utility)

    /// Counts the clears of each library's memory (5.8). A background summary started before a clear finds the count
    /// moved and is dropped instead of writing the cleared conversation back.
    private var clearCounts: [UUID: Int] = [:]

    // MARK: - Adaptive Token Budget

    /// Base character budget for memory context
    private let baseMemoryBudget: Int = 2000

    /// Minimum budget (for simple queries)
    private let minMemoryBudget: Int = 500

    /// Maximum budget (for complex multi-part queries)
    private let maxMemoryBudget: Int = 3000

    /// Calculate adaptive budget based on query complexity
    private func adaptiveBudget(for query: String) -> Int {
        let wordCount = query.split(separator: " ").count
        let hasPronouns = query.range(of: "\\b(it|this|that|they|them|those|these|he|she|his|her)\\b", options: .regularExpression) != nil
        let hasFollowUp = query.lowercased().hasPrefix("and ") || query.lowercased().hasPrefix("also ") || query.lowercased().hasPrefix("what about")
        let hasReference = query.contains("mentioned") || query.contains("earlier") || query.contains("before") || query.contains("previous")

        var budget = baseMemoryBudget

        // Simple short queries need less memory context
        if wordCount < 5 && !hasPronouns && !hasFollowUp {
            budget = minMemoryBudget
        }
        // Queries with references to prior conversation need more
        else if hasReference || hasFollowUp {
            budget = maxMemoryBudget
        }
        // Queries with pronouns need moderate context for resolution
        else if hasPronouns {
            budget = baseMemoryBudget + 500
        }

        return budget
    }

    // MARK: - Configuration

    private var config: ConversationMemoryConfig = .default

    func configure(with config: ConversationMemoryConfig) {
        self.config = config
    }

    // MARK: - Memory Management

    /// Get or create memory for a container
    func memory(for containerId: UUID) -> ConversationMemory {
        if let cached = memoryCache[containerId] {
            return cached
        }

        // Try loading from disk
        if let loaded = loadMemory(for: containerId) {
            memoryCache[containerId] = loaded
            return loaded
        }

        // Create new memory
        let newMemory = ConversationMemory(containerId: containerId)
        memoryCache[containerId] = newMemory
        return newMemory
    }

    /// Add a new conversation turn and update memory
    ///
    /// Optimized for non-blocking operation:
    /// - Synchronous updates to in-memory cache (fast)
    /// - Debounced disk writes (prevents thrashing)
    /// - Background summarization (doesn't block caller)
    /// - Importance scoring for intelligent summarization prioritization
    /// `refused` (5.8): the answer was a refusal (`ConversationContextRules.isRefusal`). The turn is kept on record and
    /// adds nothing to the key topics; it is never given to the model again.
    func addTurn(
        userQuery: String,
        assistantResponse: String,
        refused: Bool = false,
        for containerId: UUID
    ) async {
        var memory = memory(for: containerId)

        // Create the new turn
        var turn = MemoryTurn(userQuery: userQuery, assistantResponse: assistantResponse, refused: refused)

        if !refused {
            // Extract facts from the response (simple extraction - fast, no LLM)
            turn.extractedFacts = extractFacts(from: assistantResponse)
        }

        // DYNAMIC: Calculate importance score for prioritized summarization
        turn.calculateImportance()

        // Add to recent turns
        memory.recentTurns.append(turn)
        if memory.firstTurnAt == nil {
            // A memory saved before 5.8 already holds turns, a summary or topics of unknown age: its start is
            // unknown, so it never counts as begun after a change of documents.
            let heldEarlierTurns =
                memory.recentTurns.count > 1 || !memory.summary.isEmpty || !memory.entities.isEmpty
                || !memory.topics.isEmpty
            memory.firstTurnAt = heldEarlierTurns ? .distantPast : turn.timestamp
        }

        if !refused {
            // Extract and track entities from the query and response (fast regex, no LLM)
            let newEntities = extractEntities(from: userQuery + " " + assistantResponse)
            memory.entities = Array(Set(memory.entities + newEntities).prefix(config.maxEntities))

            // Extract topics (fast, no LLM)
            let newTopics = extractTopics(from: userQuery)
            memory.topics = Array(Set(memory.topics + newTopics).prefix(config.maxTopics))
        }

        // Update timestamp
        memory.lastUpdated = Date()

        // Update cache immediately (fast)
        memoryCache[containerId] = memory

        // Schedule debounced disk save (non-blocking)
        scheduleDebouncedSave(for: containerId)

        // Check if we need to summarize older turns (background, non-blocking)
        if memory.recentTurns.count > config.maxRecentTurns + config.summarizationThreshold {
            let memorySnapshot = memory
            let clearCount = clearCounts[containerId, default: 0]
            Task.detached(priority: .utility) { [weak self] in
                await self?.performBackgroundSummarization(for: memorySnapshot, clearCount: clearCount)
            }
        }

        Log.debug("[ConversationMemory] Added turn. Recent: \(memory.recentTurns.count), Entities: \(memory.entities.count)", category: .retrieval)
    }

    // MARK: - Semantic Relevance Scoring

    /// Score how relevant a memory turn is to the current query
    /// Uses keyword overlap and entity matching (fast, no LLM needed)
    private func relevanceScore(turn: MemoryTurn, to query: String) -> Float {
        let queryWords = Set(query.lowercased().split(separator: " ").map(String.init))
        let turnWords = Set((turn.userQuery + " " + turn.assistantResponse).lowercased().split(separator: " ").map(String.init))

        // Jaccard similarity for keyword overlap
        let intersection = queryWords.intersection(turnWords)
        let union = queryWords.union(turnWords)
        let jaccard = union.isEmpty ? 0 : Float(intersection.count) / Float(union.count)

        // Boost for entity matches
        let queryEntities = extractEntities(from: query)
        let turnEntities = extractEntities(from: turn.userQuery + " " + turn.assistantResponse)
        let entityOverlap = Float(Set(queryEntities).intersection(Set(turnEntities)).count)

        // Boost for fact relevance
        let factBoost: Float = turn.extractedFacts.contains { fact in
            queryWords.contains { word in fact.lowercased().contains(word) }
        } ? 0.2 : 0

        // Recency boost (more recent = higher score)
        let age = Date().timeIntervalSince(turn.timestamp)
        let recencyBoost = max(0, Float(1.0 - age / 3600)) * 0.1 // Decay over 1 hour

        return jaccard + (entityOverlap * 0.15) + factBoost + recencyBoost
    }

    /// Rank turns by relevance to query and return top-k
    private func rankTurnsByRelevance(_ turns: [MemoryTurn], to query: String, topK: Int) -> [MemoryTurn] {
        let scored = turns.map { (turn: $0, score: relevanceScore(turn: $0, to: query)) }
        let sorted = scored.sorted { $0.score > $1.score }
        return Array(sorted.prefix(topK).map { $0.turn })
    }

    /// Generate context injection string for RAG prompts
    ///
    /// **Dynamic Optimizations:**
    /// - Query-adaptive token budget (simple queries get less, follow-ups get more)
    /// - Semantic relevance scoring (prioritizes memory relevant to current query)
    /// - Prioritizes recent turns over summary, and summary over entities
    ///
    /// Refused turns, and turns from before `documentsChangedAt` (the library's last change of documents), are left
    /// out; so are the summary and key topics when they may hold such turns (5.8, `ConversationContextRules`).
    func contextInjection(for containerId: UUID, query: String = "", documentsChangedAt: Date? = nil) -> String {
        var memory = memory(for: containerId)
        memory.recentTurns = memory.recentTurns.filter {
            ConversationContextRules.isUsable($0, documentsChangedAt: documentsChangedAt)
        }
        if !ConversationContextRules.summaryIsUsable(memory, documentsChangedAt: documentsChangedAt) {
            memory.summary = ""
            memory.entities = []
        }

        guard !memory.summary.isEmpty || !memory.recentTurns.isEmpty else {
            return ""
        }

        // DYNAMIC: Adaptive budget based on query characteristics
        let budget = query.isEmpty ? baseMemoryBudget : adaptiveBudget(for: query)

        var context = "## Conversation Context\n\n"
        var remainingBudget = budget - context.count

        // PRIORITY 1: Recent turns (ranked by relevance if query provided)
        if !memory.recentTurns.isEmpty && remainingBudget > 200 {
            var recentSection = "### Recent Conversation\n"

            // DYNAMIC: Rank by relevance if query provided, otherwise by recency
            let turnsToShow: [MemoryTurn]
            if !query.isEmpty && memory.recentTurns.count > 2 {
                turnsToShow = rankTurnsByRelevance(memory.recentTurns, to: query, topK: config.maxRecentTurns)
            } else {
                turnsToShow = Array(memory.recentTurns.suffix(config.maxRecentTurns))
            }

            for (index, turn) in turnsToShow.enumerated() {
                let turnText = "User (\(index + 1)): \(turn.userQuery)\n"
                // Dynamically truncate based on remaining budget
                let maxResponseLen = min(300, max(100, remainingBudget - turnText.count - 50))
                let truncatedResponse = String(turn.assistantResponse.prefix(maxResponseLen))
                let suffix = turn.assistantResponse.count > maxResponseLen ? "..." : ""
                let fullTurn = turnText + "Assistant: \(truncatedResponse)\(suffix)\n\n"

                if recentSection.count + fullTurn.count < remainingBudget {
                    recentSection += fullTurn
                }
            }

            context += recentSection
            remainingBudget -= recentSection.count
        }

        // PRIORITY 2: Summary (provides broader context if budget allows)
        if !memory.summary.isEmpty && remainingBudget > 150 {
            let summaryHeader = "### Previous Discussion Summary\n"
            let availableForSummary = remainingBudget - summaryHeader.count - 50
            let truncatedSummary = String(memory.summary.prefix(availableForSummary))
            let summarySection = summaryHeader + truncatedSummary + "\n\n"

            context += summarySection
            remainingBudget -= summarySection.count
        }

        // PRIORITY 3: Key entities (filter to query-relevant if possible)
        if !memory.entities.isEmpty && remainingBudget > 100 {
            let entitiesHeader = "### Key Topics: "

            // DYNAMIC: Prioritize entities that appear in query
            let relevantEntities: [String]
            if !query.isEmpty {
                let queryLower = query.lowercased()
                let (matching, other) = memory.entities.reduce(into: ([String](), [String]())) { result, entity in
                    if queryLower.contains(entity.lowercased()) {
                        result.0.append(entity)
                    } else {
                        result.1.append(entity)
                    }
                }
                relevantEntities = Array((matching + other).prefix(5))
            } else {
                relevantEntities = Array(memory.entities.prefix(5))
            }

            let entitiesSection = entitiesHeader + relevantEntities.joined(separator: ", ") + "\n\n"

            if entitiesSection.count < remainingBudget {
                context += entitiesSection
            }
        }

        Log.debug("[ConversationMemory] Context injection: \(context.count) chars (budget: \(budget), query-aware: \(!query.isEmpty))", category: .retrieval)
        return context
    }

    /// Generate a concise context string for pronoun resolution
    func pronounResolutionContext(for containerId: UUID) -> String {
        let memory = memory(for: containerId)

        guard let lastTurn = memory.recentTurns.last else {
            return ""
        }

        // For pronoun resolution, we mainly need the last Q&A pair
        var context = "Previous question: \(lastTurn.userQuery)\n"

        // Include key facts from the answer
        if !lastTurn.extractedFacts.isEmpty {
            context += "Key information: \(lastTurn.extractedFacts.joined(separator: "; "))\n"
        }

        // Include tracked entities
        if !memory.entities.isEmpty {
            context += "Mentioned topics: \(memory.entities.prefix(5).joined(separator: ", "))\n"
        }

        return context
    }

    /// Clear memory for a container
    ///
    /// Saves an empty memory instead of deleting the file (5.8): with iCloud on, the library's shared copy is merged
    /// newest-file-wins, so a deleted local file was copied back from the shared one and the cleared conversation
    /// returned. A save still waiting for its debounce is dropped, and a summary still being written is discarded.
    func clearMemory(for containerId: UUID) {
        clearCounts[containerId, default: 0] += 1
        pendingSaves.remove(containerId)
        let empty = ConversationMemory(containerId: containerId)
        memoryCache[containerId] = empty
        saveMemory(empty)
        Log.debug("[ConversationMemory] Cleared memory for container \(containerId)", category: .retrieval)
    }

    /// Waits until every memory file write queued so far is on disk. For tests.
    nonisolated static func waitForWrites() {
        writeQueue.sync {}
    }

    /// Forgets the in-memory copies so the next read comes from disk. For tests.
    func dropCachedMemories() {
        memoryCache.removeAll()
    }

    /// Writes any save waiting for its debounce now. For tests.
    func flushPendingSavesNow() {
        saveTask?.cancel()
        flushPendingSaves()
    }

    // MARK: - Debounced Persistence

    /// Schedule a debounced save operation to prevent disk thrashing
    private func scheduleDebouncedSave(for containerId: UUID) {
        pendingSaves.insert(containerId)

        // Cancel existing task if any
        saveTask?.cancel()

        // Schedule new debounced save
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.flushPendingSaves()
            }
        }
    }

    /// Flush all pending saves to disk
    private func flushPendingSaves() {
        let containersToSave = pendingSaves
        pendingSaves.removeAll()

        for containerId in containersToSave {
            if let memory = memoryCache[containerId] {
                saveMemory(memory)
            }
        }

        if !containersToSave.isEmpty {
            Log.debug("[ConversationMemory] Flushed \(containersToSave.count) pending saves to disk", category: .retrieval)
        }
    }

    /// Perform background summarization without blocking the caller
    ///
    /// DYNAMIC: Uses importance scoring to preserve high-value turns longer.
    /// Low-importance turns are summarized first, high-importance turns are kept verbatim.
    private func performBackgroundSummarization(for memory: ConversationMemory, clearCount: Int) async {
        var mutableMemory = memory

        // DYNAMIC: Sort turns by importance - summarize LOW importance first
        // Keep high-importance turns in recentTurns longer
        let sortedByImportance = mutableMemory.recentTurns.sorted { $0.importanceScore < $1.importanceScore }

        // Calculate how many to summarize (keep maxRecentTurns, but prioritize high importance)
        let countToSummarize = max(0, sortedByImportance.count - config.maxRecentTurns)
        guard countToSummarize > 0 else { return }

        // Take the LOWEST importance turns for summarization
        let turnsToSummarize = Array(sortedByImportance.prefix(countToSummarize))
        let turnsToKeep = Array(sortedByImportance.suffix(config.maxRecentTurns))

        // Re-sort kept turns by timestamp for proper ordering
        let orderedTurnsToKeep = turnsToKeep.sorted { $0.timestamp < $1.timestamp }

        // Build text to summarize
        var textToSummarize = ""
        if !mutableMemory.summary.isEmpty {
            textToSummarize += "Previous summary: \(mutableMemory.summary)\n\nNew conversation:\n"
        }

        // A refused turn is never given to the model again, a summary included (5.8).
        for turn in turnsToSummarize where !turn.refused {
            // Include importance in summary for context
            let importanceLabel = turn.importanceScore > 0.7 ? "[Important] " : ""
            textToSummarize += "\(importanceLabel)Q: \(turn.userQuery)\nA: \(String(turn.assistantResponse.prefix(500)))\n\n"
        }

        // Generate summary using LLM (this is the slow part). Turns that were all refused leave the summary as it was.
        let newSummary: String
        if turnsToSummarize.contains(where: { !$0.refused }) {
            newSummary = await generateSummary(for: textToSummarize)
        } else {
            newSummary = mutableMemory.summary
        }

        // The memory was cleared while the summary was written (5.8): writing it back would restore the conversation.
        guard clearCounts[memory.containerId, default: 0] == clearCount else {
            Log.debug("[ConversationMemory] Dropped a summary of a cleared memory", category: .retrieval)
            return
        }

        // Update memory atomically
        mutableMemory.summary = String(newSummary.prefix(config.maxSummaryLength))
        mutableMemory.recentTurns = orderedTurnsToKeep
        mutableMemory.totalTurnsSummarized += turnsToSummarize.count
        mutableMemory.lastUpdated = Date()

        // Update cache and schedule save
        memoryCache[memory.containerId] = mutableMemory
        scheduleDebouncedSave(for: memory.containerId)

        let avgImportance = turnsToSummarize.map(\.importanceScore).reduce(0, +) / Float(turnsToSummarize.count)
        Log.info("[ConversationMemory] Background summarization: \(turnsToSummarize.count) low-importance turns (avg: \(String(format: "%.2f", avgImportance))) → \(mutableMemory.summary.count) chars", category: .retrieval)
    }

    // MARK: - Summarization

    /// Generate a summary using Apple Foundation Models
    private func generateSummary(for text: String) async -> String {
        #if canImport(FoundationModels)
            do {
                let model = SystemLanguageModel.default
                guard !DirectModelCallsForTesting.isOn, model.isAvailable else {
                    return extractiveSummary(from: text)
                }

                // Built with an explicit model and instructions, not the bare `LanguageModelSession()`.
                // Every service that used the bare initialiser failed deterministically with
                // ParsingError / "Session ended without producing a response", while every path built
                // through `FoundationModelSessionFactory` (which supplies `model:` and `instructions:`)
                // succeeded. Confirmed on an empty library with the one-word query "Test" and zero
                // retrieved chunks, which rules out content, guardrails, context size and token caps.
                // An Instruments capture of the Foundation Models template shows `assets: ""` on exactly
                // these responses, consistent with a session that never received its model assets.
                let session = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: Instructions("You summarise conversation history. Be concise and factual.")
                )
                let prompt = """
                Summarize this conversation concisely, preserving key facts, decisions, and topics discussed.
                Focus on information that would be relevant for follow-up questions.
                Keep the summary under 200 words.

                Conversation:
                \(text)

                Summary:
                """

                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            } catch {
                Log.warning("[ConversationMemory] LLM summarization failed: \(error). Using extractive fallback.", category: .retrieval)
                return extractiveSummary(from: text)
            }
        #else
            return extractiveSummary(from: text)
        #endif
    }

    /// Extractive fallback when LLM is unavailable
    private func extractiveSummary(from text: String) -> String {
        // Simple extractive summary: take first sentence of each turn's answer
        let lines = text.components(separatedBy: "\n")
        var summary: [String] = []

        for line in lines {
            if line.hasPrefix("A: ") {
                let answer = String(line.dropFirst(3))
                if let firstSentence = answer.components(separatedBy: ". ").first {
                    summary.append(firstSentence)
                }
            }
        }

        return summary.prefix(5).joined(separator: ". ") + "."
    }

    // MARK: - Entity & Topic Extraction

    /// Extract named entities from text (simple NLP approach)
    private func extractEntities(from text: String) -> [String] {
        var entities: [String] = []

        // Extract capitalized phrases (potential proper nouns)
        let words = text.components(separatedBy: .whitespaces)
        var currentPhrase: [String] = []

        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            guard !cleaned.isEmpty else { continue }

            guard let firstChar = cleaned.first else { continue }
            if firstChar.isUppercase, cleaned.count > 1 {
                currentPhrase.append(cleaned)
            } else {
                if currentPhrase.count >= 1 {
                    let phrase = currentPhrase.joined(separator: " ")
                    // Filter out common sentence starters
                    let commonStarters = ["The", "This", "That", "It", "I", "We", "You", "He", "She", "They", "What", "How", "Why", "When", "Where", "Is", "Are", "Was", "Were", "If", "For", "To", "A", "An"]
                    if !commonStarters.contains(phrase), phrase.count > 2 {
                        entities.append(phrase)
                    }
                }
                currentPhrase = []
            }
        }

        // Add any remaining phrase
        if currentPhrase.count >= 1 {
            let phrase = currentPhrase.joined(separator: " ")
            entities.append(phrase)
        }

        return Array(Set(entities))
    }

    /// Extract topics from a query
    private func extractTopics(from query: String) -> [String] {
        // Remove question words and extract key noun phrases
        let stopWords: Set<String> = ["what", "how", "why", "when", "where", "who", "which", "is", "are", "was", "were", "do", "does", "did", "can", "could", "would", "should", "the", "a", "an", "to", "for", "of", "in", "on", "at", "by", "with", "about", "this", "that", "it", "i", "me", "my", "you", "your"]

        let words = query.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }

        return Array(Set(words).prefix(5))
    }

    /// Extract key facts from an assistant response
    private func extractFacts(from response: String) -> [String] {
        // Extract sentences that contain definitive statements
        let sentences = response.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Take first 3 sentences as key facts (simple heuristic)
        return Array(sentences.prefix(3).map { $0 + "." })
    }

    // MARK: - Persistence

    private func memoryURL(for containerId: UUID) -> URL {
        AppSupportPaths.baseDir().appendingPathComponent("conversation_memory_\(containerId.uuidString).json")
    }

    private func saveMemory(_ memory: ConversationMemory) {
        let url = memoryURL(for: memory.containerId)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(memory)
            Self.writeQueue.async {
                do {
                    try WorkspaceSyncService.coordinatedWriteData(data, to: url)
                } catch {
                    Log.error("[ConversationMemory] Failed to save memory: \(error)", category: .retrieval)
                }
            }
        } catch {
            Log.error("[ConversationMemory] Failed to encode memory: \(error)", category: .retrieval)
        }
    }

    private func loadMemory(for containerId: UUID) -> ConversationMemory? {
        let url = memoryURL(for: containerId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try WorkspaceSyncService.coordinatedReadData(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ConversationMemory.self, from: data)
        } catch {
            Log.error("[ConversationMemory] Failed to load memory: \(error)", category: .retrieval)
            return nil
        }
    }
}

// MARK: - Fallback for Pre-iOS 26

/// Stub implementation for devices without FoundationModels
@available(iOS, deprecated: 26.0, message: "Use ConversationMemoryService on iOS 26+")
final class ConversationMemoryServiceUnavailable {
    static let shared = ConversationMemoryServiceUnavailable()
    private init() {}

    func memory(for _: UUID) -> ConversationMemory? { nil }
    func addTurn(userQuery _: String, assistantResponse _: String, for _: UUID) async {}
    func contextInjection(for _: UUID) -> String { "" }
    func clearMemory(for _: UUID) {}
}

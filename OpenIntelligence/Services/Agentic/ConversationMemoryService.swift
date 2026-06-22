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

    init(userQuery: String, assistantResponse: String) {
        id = UUID()
        self.userQuery = userQuery
        self.assistantResponse = assistantResponse
        timestamp = Date()
        extractedFacts = []
        importanceScore = 0.5 // Default mid-importance
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
    func addTurn(
        userQuery: String,
        assistantResponse: String,
        for containerId: UUID
    ) async {
        var memory = memory(for: containerId)

        // Create the new turn
        var turn = MemoryTurn(userQuery: userQuery, assistantResponse: assistantResponse)

        // Extract facts from the response (simple extraction - fast, no LLM)
        turn.extractedFacts = extractFacts(from: assistantResponse)

        // DYNAMIC: Calculate importance score for prioritized summarization
        turn.calculateImportance()

        // Add to recent turns
        memory.recentTurns.append(turn)

        // Extract and track entities from the query and response (fast regex, no LLM)
        let newEntities = extractEntities(from: userQuery + " " + assistantResponse)
        memory.entities = Array(Set(memory.entities + newEntities).prefix(config.maxEntities))

        // Extract topics (fast, no LLM)
        let newTopics = extractTopics(from: userQuery)
        memory.topics = Array(Set(memory.topics + newTopics).prefix(config.maxTopics))

        // Update timestamp
        memory.lastUpdated = Date()

        // Update cache immediately (fast)
        memoryCache[containerId] = memory

        // Schedule debounced disk save (non-blocking)
        scheduleDebouncedSave(for: containerId)

        // Check if we need to summarize older turns (background, non-blocking)
        if memory.recentTurns.count > config.maxRecentTurns + config.summarizationThreshold {
            let memorySnapshot = memory
            Task.detached(priority: .utility) { [weak self] in
                await self?.performBackgroundSummarization(for: memorySnapshot)
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
    func contextInjection(for containerId: UUID, query: String = "") -> String {
        let memory = memory(for: containerId)

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
    func clearMemory(for containerId: UUID) {
        memoryCache.removeValue(forKey: containerId)
        deleteMemory(for: containerId)
        Log.debug("[ConversationMemory] Cleared memory for container \(containerId)", category: .retrieval)
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
    private func performBackgroundSummarization(for memory: ConversationMemory) async {
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

        for turn in turnsToSummarize {
            // Include importance in summary for context
            let importanceLabel = turn.importanceScore > 0.7 ? "[Important] " : ""
            textToSummarize += "\(importanceLabel)Q: \(turn.userQuery)\nA: \(String(turn.assistantResponse.prefix(500)))\n\n"
        }

        // Generate summary using LLM (this is the slow part)
        let newSummary = await generateSummary(for: textToSummarize)

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
                guard model.isAvailable else {
                    return extractiveSummary(from: text)
                }

                let session = LanguageModelSession()
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
            Task.detached {
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

    private func deleteMemory(for containerId: UUID) {
        let url = memoryURL(for: containerId)
        Task.detached {
            try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
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

//
//  AgenticOrchestrator+Maximum.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

extension AgenticOrchestrator {
    // MARK: - TRUE UNLIMITED REASONING
    // This is what a 10x expert would build: ACTUALLY runs until 98% confident
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Result from true unlimited reasoning
    struct UnlimitedResult: Sendable {
        let finalAnswer: String
        let steps: [ThinkingStep]
        let totalTokens: Int
        let sessionsRun: Int
        let confidence: Float
        let terminationReason: TerminationReason

        enum TerminationReason: String, Sendable {
            /// Deliberately not "98% confidence achieved": the string is shown beside
            /// the live confidence value, and a device screenshot read
            /// "98% confidence achieved - Confidence: 78%" in a single row.
            case confidenceReached = "Confidence target reached"
            case contentSaturated = "No new insights (content saturated)"
            /// Sub-question coverage stopped improving: the chain kept finding new
            /// text but none of it answered more of the question, which means the
            /// remaining parts are not in this corpus.
            case answerNotInCorpus = "Remaining sub-questions not present in the documents"
            case maxSessionsReached = "Maximum sessions reached"
            case thermalLimit = "Thermal throttling detected"
            case userCancelled = "User cancelled"
            case error = "Model unavailable (inference failed)"
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // HIERARCHICAL FACT COMPRESSION
    // Solves the "alternator overflow" problem by compressing at each level
    //
    // Level 0: Raw chunks (unlimited) → Level 1: Insights (~800 chars)
    // Level 1: Insights → Level 2: Condensed facts (~200 chars each)
    // Level 2: Facts → Level 3: Core Fact Bank (fixed ~1500 chars)
    // Level 3: Fact Bank → Level 4: Final answer (unlimited via output chaining)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// A scored fact with relevance to the original query
    struct ScoredFact {
        let content: String
        let normalizedClaim: String
        let supportTerms: [String]
        let evidenceKind: EvidenceKind
        var relevanceScore: Float  // 0-1, higher = more relevant to query
        let sessionAdded: Int  // When it was added (for recency bonus)
        /// Source markers ([S1], [S2] …) captured from the originating sentence.
        ///
        /// Held separately rather than left inline in `content`, because every
        /// extracted sentence is truncated to 150 characters (200 for conceptual
        /// queries) and a citation almost always sits at the end of its sentence —
        /// so the truncation silently ate the attribution. That is why every
        /// Maximum device run reported `citations=0/0` while Deep Think, which
        /// passes untruncated insight text straight through, verified 13–17.
        let sources: [String]

        enum EvidenceKind: String {
            case numeric
            case cited
            case procedural
            case descriptive
        }
    }

    /// Sub-question for query decomposition
    struct SubQuestion {
        let question: String
        var answered: Bool = false
        var evidence: [String] = []  // Facts that address this sub-question
    }

    /// The Fact Bank - intelligent prioritized buffer with query decomposition
    /// Evicts LOW RELEVANCE facts first, not just oldest
    /// Tracks which sub-questions have been answered for REAL confidence
    struct FactBank {
        struct Update {
            let addedFacts: Int
            let noveltyScore: Float
            let newlyAnsweredSubQuestions: Int
            let evidenceCoverage: Float
        }

        /// Core facts with relevance scores
        var scoredFacts: [ScoredFact] = []
        /// Maximum characters for the entire fact bank
        let maxChars: Int = 1500

        /// Sub-questions derived from query decomposition
        var subQuestions: [SubQuestion] = []

        /// Original query terms for relevance scoring
        var queryTerms: Set<String> = []

        /// Uses the app's existing QueryIntent for consistency across the pipeline
        var queryIntent: QueryIntent = .balanced

        /// Current session number for recency scoring
        var currentSession: Int = 0

        /// Initialize with query decomposition
        mutating func initializeWithQuery(_ query: String) {
            // Extract query terms for relevance scoring
            let words = query.lowercased().split(separator: " ").map(String.init)
            let stopWords = Set([
                "what", "how", "why", "does", "do", "the", "a", "an", "is", "are", "of", "in", "to", "and", "or", "for",
            ])
            queryTerms = Set(words.filter { $0.count > 2 && !stopWords.contains($0) })

            // Decompose into sub-questions (heuristic-based)
            subQuestions = decomposeQuery(query)
        }

        /// Decompose a complex query into sub-questions
        /// Generates topic-specific sub-questions for better coverage tracking
        private func decomposeQuery(_ query: String) -> [SubQuestion] {
            var subs: [SubQuestion] = []
            let lower = query.lowercased()

            // Extract key topic words for sub-question generation
            let stopWords = Set([
                "what", "how", "why", "does", "do", "the", "a", "an", "is", "are", "of", "in", "to", "and", "or", "for",
                "on", "with", "about",
            ])
            let topicWords = lower.split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !stopWords.contains($0) }

            // Generate topic-specific sub-questions using actual query terms
            if !topicWords.isEmpty {
                let mainTopic = topicWords.prefix(3).joined(separator: " ")

                // Core sub-questions using the actual topic
                subs.append(SubQuestion(question: "evidence \(mainTopic)"))
                subs.append(SubQuestion(question: "benefits \(mainTopic)"))
                subs.append(SubQuestion(question: "effects \(mainTopic)"))
            }

            // Add dimension-based sub-questions based on query patterns
            let dimensions: [(pattern: String, keywords: [String])] = [
                ("effect", ["effect", "impact", "influence", "change"]),
                ("affect", ["effect", "impact", "influence", "change"]),
                ("benefit", ["benefit", "advantage", "improvement", "positive"]),
                ("harm", ["harm", "risk", "negative", "damage", "concern"]),
                ("cognitive", ["cognitive", "mental", "brain", "thinking", "memory", "attention"]),
                ("how", ["mechanism", "process", "method", "how"]),
                ("why", ["reason", "cause", "because", "why"]),
            ]

            for (pattern, keywords) in dimensions where lower.contains(pattern) {
                subs.append(SubQuestion(question: keywords.joined(separator: " ")))
            }

            // Document-grounded checks (not research-oriented — source docs may be manuals, not papers)
            subs.append(SubQuestion(question: "specific details values numbers"))
            subs.append(SubQuestion(question: "notes warnings exceptions"))

            // Deduplicate
            var seen = Set<String>()
            subs = subs.filter { q in
                let key = q.question.prefix(20).lowercased()
                if seen.contains(String(key)) { return false }
                seen.insert(String(key))
                return true
            }

            return subs
        }

        /// Check if a fact addresses any sub-questions and mark them
        /// Uses loose matching - any keyword overlap counts
        private mutating func updateSubQuestionCoverage(fact: String) {
            let factLower = fact.lowercased()
            let factWords = Set(factLower.split(separator: " ").map(String.init).filter { $0.count > 3 })

            for i in 0..<subQuestions.count {
                // Split sub-question into keywords
                let questionWords = Set(
                    subQuestions[i].question.lowercased()
                        .split(separator: " ")
                        .map(String.init)
                        .filter { $0.count > 3 })

                // Check for ANY overlap (loose matching)
                let matchCount = questionWords.intersection(factWords).count

                if matchCount >= 1 {
                    subQuestions[i].evidence.append(String(fact.prefix(80)))
                    // Mark answered after just 1 piece of evidence (loose threshold)
                    if subQuestions[i].evidence.count >= 1 {
                        subQuestions[i].answered = true
                    }
                }
            }
        }

        /// Calculate relevance score for a fact against the query
        private func scoreRelevance(_ fact: String, session: Int) -> Float {
            var score: Float = 0.3  // Base score

            let factLower = fact.lowercased()

            // Query term overlap (0-0.4)
            let matchingTerms = queryTerms.filter { factLower.contains($0) }
            score += Float(matchingTerms.count) / Float(max(1, queryTerms.count)) * 0.4

            // Evidence markers (0-0.2)
            let evidenceMarkers = [
                "found", "showed", "demonstrated", "significant", "effect", "improved", "increased", "decreased",
            ]
            if evidenceMarkers.contains(where: { factLower.contains($0) }) {
                score += 0.15
            }

            // Quantitative content (0-0.15)
            if fact.contains(where: { $0.isNumber }) || fact.contains("%") {
                score += 0.15
            }

            // Citation (0-0.1)
            if fact.contains("(") && fact.contains(")") && fact.contains(where: { $0.isNumber }) {
                score += 0.1
            }

            // Recency bonus (0-0.1) - newer facts get slight boost
            let recencyBonus = min(0.1, Float(session) / 50.0 * 0.1)
            score += recencyBonus

            return min(1.0, score)
        }

        /// Add new facts with relevance scoring
        mutating func addFacts(from insight: String) -> Update {
            currentSession += 1

            // Extract content based on query intent
            let newFacts = extractFactsFromInsight(insight)
            var existingKeys = Set(scoredFacts.map { normalizedFactKey($0.content) })
            let answeredBefore = subQuestions.filter(\.answered).count
            var addedFacts = 0
            var noveltyScores: [Float] = []

            for (factContent, factSources) in newFacts {
                let normalizedKey = normalizedFactKey(factContent)
                guard !normalizedKey.isEmpty, !existingKeys.contains(normalizedKey) else { continue }

                existingKeys.insert(normalizedKey)
                noveltyScores.append(noveltyScore(for: factContent))
                let score = scoreRelevance(factContent, session: currentSession)
                scoredFacts.append(
                    ScoredFact(
                        content: factContent,
                        normalizedClaim: normalizedKey,
                        supportTerms: supportTerms(for: factContent),
                        evidenceKind: evidenceKind(for: factContent),
                        relevanceScore: score,
                        sessionAdded: currentSession,
                        sources: factSources
                    ))
                addedFacts += 1

                // Check if this fact addresses any sub-questions
                updateSubQuestionCoverage(fact: factContent)
            }

            // Compress using RELEVANCE-BASED eviction
            compressIntelligently()

            let answeredAfter = subQuestions.filter(\.answered).count
            let averageNovelty =
                noveltyScores.isEmpty
                ? 0
                : noveltyScores.reduce(0, +) / Float(noveltyScores.count)

            return Update(
                addedFacts: addedFacts,
                noveltyScore: averageNovelty,
                newlyAnsweredSubQuestions: max(0, answeredAfter - answeredBefore),
                evidenceCoverage: subQuestionConfidence
            )
        }

        /// Compress by removing LEAST RELEVANT facts first
        private mutating func compressIntelligently() {
            var totalChars = scoredFacts.map(\.content).joined().count

            while totalChars > maxChars && scoredFacts.count > 3 {
                // Find the lowest relevance fact
                if let minIndex = scoredFacts.enumerated().min(by: {
                    $0.element.relevanceScore < $1.element.relevanceScore
                })?.offset {
                    scoredFacts.remove(at: minIndex)
                    totalChars = scoredFacts.map(\.content).joined().count
                } else {
                    break
                }
            }

            // Further compress by truncating if still over
            if totalChars > maxChars {
                scoredFacts = scoredFacts.map { fact in
                    ScoredFact(
                        content: String(fact.content.prefix(100)),
                        normalizedClaim: fact.normalizedClaim,
                        supportTerms: fact.supportTerms,
                        evidenceKind: fact.evidenceKind,
                        relevanceScore: fact.relevanceScore,
                        sessionAdded: fact.sessionAdded,
                        // Attribution survives this pass deliberately: content is cut
                        // to 100 characters here, which would destroy any marker left
                        // inline, so `sources` being a separate field is what keeps
                        // the claim citable after compression.
                        sources: fact.sources
                    )
                }
            }
        }

        /// Extract content from prose insight based on query intent
        /// Pull the `[S#]` markers out of a sentence before it is truncated.
        private func sourceMarkers(in sentence: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: "\\[S\\d+\\]") else { return [] }
            let range = NSRange(sentence.startIndex..., in: sentence)
            var found: [String] = []
            for m in regex.matches(in: sentence, range: range) {
                if let r = Range(m.range, in: sentence) {
                    let marker = String(sentence[r])
                    if !found.contains(marker) { found.append(marker) }
                }
            }
            return found
        }

        private func extractFactsFromInsight(_ insight: String) -> [(text: String, sources: [String])] {
            var extracted: [(text: String, sources: [String])] = []
            // Sessions cite once, at the top: "[S1] REVIEW ARTICLE — (Psychiatry Clin
            // Neurosci - 2019 …" followed by the reasoning. Splitting into sentences
            // therefore leaves the marker on the *first* fragment and every substantive
            // claim after it with no attribution — and those later claims are the ones
            // that reach the answer. A device run carried [S#] in 14 places and still
            // reported citations=0/0 for exactly this reason.
            //
            // An insight prefixed [S1] is derived from S1 throughout, so a sentence
            // with no marker of its own inherits the insight's.
            let insightSources = sourceMarkers(in: insight)
            let sentences = insight.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 20 }

            for sentence in sentences {
                let shouldKeep: Bool

                switch queryIntent {
                case .keyword:
                    // PRECISION: quantitative and cited content
                    let hasNumber = sentence.contains(where: { $0.isNumber })
                    let hasPercent = sentence.contains("%")
                    let hasCitation = sentence.contains("(") && sentence.contains(")")
                    let hasKeyTerms = ["found", "showed", "improved", "increased", "decreased", "significant"]
                        .contains { sentence.lowercased().contains($0) }
                    shouldKeep = hasNumber || hasPercent || hasCitation || hasKeyTerms

                case .conceptual:
                    // COMPLETENESS: explanatory and contextual content
                    let hasExplanation = [
                        "because", "therefore", "means", "indicates", "suggests",
                        "however", "although", "while", "this", "these",
                    ]
                    .contains { sentence.lowercased().contains($0) }
                    let hasContext = [
                        "context", "background", "generally", "typically", "often",
                        "can", "may", "include", "involve", "relate",
                    ]
                    .contains { sentence.lowercased().contains($0) }
                    let isSubstantive = sentence.count > 50
                    shouldKeep = hasExplanation || hasContext || isSubstantive

                case .balanced:
                    // BOTH facts AND context
                    let hasNumber = sentence.contains(where: { $0.isNumber })
                    let hasPercent = sentence.contains("%")
                    let hasCitation = sentence.contains("(") && sentence.contains(")")
                    let hasKeyTerms = [
                        "found", "showed", "improved", "increased", "decreased", "significant",
                        "because", "therefore", "however", "suggests", "indicates",
                    ]
                    .contains { sentence.lowercased().contains($0) }
                    let isSubstantive = sentence.count > 60
                    shouldKeep = hasNumber || hasPercent || hasCitation || hasKeyTerms || isSubstantive
                }

                if shouldKeep {
                    let maxLen = queryIntent == .conceptual ? 200 : 150
                    // Capture attribution from the *full* sentence before truncating.
                    let ownSources = sourceMarkers(in: sentence)
                    extracted.append(
                        (
                            String(sentence.prefix(maxLen)),
                            ownSources.isEmpty ? insightSources : ownSources
                        ))
                }
            }

            // Fallback if nothing extracted
            if extracted.isEmpty && !insight.isEmpty {
                let fallbackLen = queryIntent == .conceptual ? 250 : 150
                extracted.append((String(insight.prefix(fallbackLen)), insightSources))
            }

            return extracted
        }

        private func normalizedFactKey(_ fact: String) -> String {
            fact.lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !Self.factStopWords.contains($0) }
                .prefix(20)
                .joined(separator: " ")
        }

        private func noveltyScore(for fact: String) -> Float {
            let factTokens = tokenSet(for: fact)
            guard !factTokens.isEmpty else { return 0 }
            guard !scoredFacts.isEmpty else { return 1 }

            let maxOverlap = scoredFacts.reduce(Float(0)) { currentMax, existing in
                let existingTokens = tokenSet(for: existing.content)
                guard !existingTokens.isEmpty else { return currentMax }
                let overlap = Float(factTokens.intersection(existingTokens).count)
                let union = Float(factTokens.union(existingTokens).count)
                guard union > 0 else { return currentMax }
                return max(currentMax, overlap / union)
            }

            return max(0, 1 - maxOverlap)
        }

        private func supportTerms(for fact: String) -> [String] {
            var seen: Set<String> = []
            return fact.lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !Self.factStopWords.contains($0) }
                .filter { seen.insert($0).inserted }
                .prefix(5)
                .map { $0 }
        }

        private func evidenceKind(for fact: String) -> ScoredFact.EvidenceKind {
            let lower = fact.lowercased()
            if fact.contains(where: { $0.isNumber }) || fact.contains("%") {
                return .numeric
            }
            if fact.contains("[S") || (fact.contains("(") && fact.contains(")")) {
                return .cited
            }
            if lower.hasPrefix("step") || lower.hasPrefix("first") || lower.hasPrefix("then") {
                return .procedural
            }
            return .descriptive
        }

        private func tokenSet(for text: String) -> Set<String> {
            Set(
                text.lowercased()
                    .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count > 3 && !Self.factStopWords.contains($0) }
            )
        }

        private static let factStopWords: Set<String> = [
            "about", "after", "also", "among", "been", "being", "could", "from", "into", "just",
            "more", "much", "only", "over", "same", "some", "than", "that", "their", "there",
            "these", "they", "this", "very", "were", "what", "when", "where", "which", "with",
            "would",
        ]

        /// Get fact bank as context string (sorted by relevance)
        func asContext() -> String {
            if scoredFacts.isEmpty { return "" }
            let sorted = scoredFacts.sorted { $0.relevanceScore > $1.relevanceScore }
            // Only the claim and its attribution. `evidenceKind` and `supportTerms`
            // are internal scoring artifacts whose sole consumer was this string —
            // nothing dedupes or ranks on them downstream — so they cost roughly 55
            // characters per claim of context the synthesizer has to read past.
            //
            // That is not free. This block shares a fixed budget with the recent
            // findings, and a device run with 13 claims squeezed the findings from
            // 1622 characters to 430, producing a 258-character answer covering two
            // of the neurotransmitters when the evidence supported more.
            return "CLAIM BANK:\n"
                + sorted.map { fact in
                    let sourceSummary = fact.sources.isEmpty ? "" : " " + fact.sources.joined(separator: " ")
                    return "• \(fact.content)\(sourceSummary)"
                }.joined(separator: "\n")
        }

        /// Get REAL confidence based on sub-question coverage
        var subQuestionConfidence: Float {
            guard !subQuestions.isEmpty else { return 0.5 }
            let answeredCount = subQuestions.filter(\.answered).count
            return Float(answeredCount) / Float(subQuestions.count)
        }

        /// Get unanswered sub-questions for gap-aware expansion
        var unansweredQuestions: [String] {
            subQuestions.filter { !$0.answered }.map(\.question)
        }

        /// Get count and size info
        var summary: String {
            let answered = subQuestions.filter(\.answered).count
            return "\(scoredFacts.count) claims, \(answered)/\(subQuestions.count) sub-Qs answered"
        }

        /// Legacy accessor for coreFacts (compatibility)
        var coreFacts: [String] {
            scoredFacts.map(\.content)
        }
    }

    /// TRUE UNLIMITED REASONING: Continues until 98% confident or saturated
    /// Uses hierarchical compression to NEVER hit token limits
    ///
    /// Architecture:
    /// ┌─────────────────────────────────────────────────────────────┐
    /// │ Session N: [Query + 3 chunks + Fact Bank hint] → Insight   │
    /// │     ↓                                                       │
    /// │ Extract facts → Add to Fact Bank (auto-compresses)         │
    /// │     ↓                                                       │
    /// │ Every 5 sessions: Synthesize running answer                 │
    /// │     ↓                                                       │
    /// │ Repeat until 98% confident or saturated                     │
    /// │     ↓                                                       │
    /// │ Chain multiple output passes for final answer               │
    /// └─────────────────────────────────────────────────────────────┘
    func executeTrueUnlimitedReasoning(
        query: String,
        allChunks: [RetrievedChunk],
        targetConfidence: Float = 0.98,
        maxSessions: Int = 50,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> UnlimitedResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // Scale the ceiling to the evidence actually retrieved rather than always
        // allowing 50. Each session reads 3 chunks and prefers unseen ones, so a pool
        // of N chunks is fully covered in about N/3 sessions; 1.5x leaves room to
        // revisit and connect. A one-document library therefore gets roughly a dozen
        // sessions and a large corpus still gets the full budget.
        //
        // This is a backstop, not the mechanism — the convergence rule below is what
        // should normally end a run. It exists so that a pathological case cannot
        // spend 26 minutes re-reading 65 chunks, which is what a device trace showed
        // when the stop condition was unreachable.
        // The ceiling is a runaway guard, not a policy lever. Convergence is what
        // ends a run, and it works: a device trace stopped at session 23 on its own.
        //
        // An earlier version of this budgeted only the top 60% of the relevance-ordered
        // pool, on the theory that late sessions read the weakest chunks. The same
        // trace refutes it — sessions 16 through 22 ran at 66–86% novelty and the chain
        // stopped on *saturation*, with `lowNoveltyStreak=0`, meaning it was still
        // finding new material when it quit. A 60% ceiling would have cut seven
        // productive sessions.
        //
        // The division of labour that is actually correct: retrieval decides what is
        // relevant, and does so with scores you can inspect; convergence decides when
        // reasoning has stopped paying; the ceiling only stops a pathological run.
        // A blunt percentage is neither a score nor an earned stop, so it belongs to
        // neither stage.
        let chunksPerSession = 3
        let coveragePasses = Int(ceil(Double(allChunks.count) / Double(chunksPerSession)))
        let evidenceScaledCeiling = max(8, Int(Double(coveragePasses) * 1.5))
        let effectiveMaxSessions = min(maxSessions, evidenceScaledCeiling)
        if effectiveMaxSessions < maxSessions {
            Log.info(
                "[Unlimited] Session ceiling scaled to evidence: \(effectiveMaxSessions) "
                    + "(pool=\(allChunks.count) chunks, requested max=\(maxSessions))",
                category: .llm
            )
        }

        let unlimitedPolicy = AgenticPolicyService.unlimitedReasoningPolicy(
            targetConfidence: targetConfidence,
            maxSessions: effectiveMaxSessions
        )

        let startTime = Date()
        var totalTokens = 0
        var allInsights: [String] = []
        var steps: [ThinkingStep] = []

        // Create detailed event forwarder for console output (Maximum mode gets full pipeline visibility)
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        // Use the app's unified QueryIntent classification for consistency
        // This aligns FactBank extraction with hybrid search weight adjustments
        let queryEnhancer = QueryEnhancementService()
        let queryIntent = queryEnhancer.classifyIntent(query)

        var factBank = FactBank()
        factBank.queryIntent = queryIntent
        factBank.initializeWithQuery(query)  // Decompose query into sub-questions
        Log.info(
            "[Unlimited] FactBank: QueryIntent=\(queryIntent.rawValue), \(factBank.subQuestions.count) sub-questions",
            category: .llm)

        var currentAnswer = ""
        var confidence: Float = unlimitedPolicy.initialConfidence
        var terminationReason: UnlimitedResult.TerminationReason = .maxSessionsReached

        // Track content saturation via semantic similarity
        var saturationStreak = 0
        var lowNoveltyStreak = 0
        // Sub-question coverage over time. Novelty measures new *text*; this measures
        // new *answer*. A device run held coverage at 80% from session 1 through 22
        // while novelty ran 66–86% — the chain was reading fresh material that
        // answered nothing further, for twenty sessions, because nothing else it
        // needed was in the document. That is the signal for "the rest is not here",
        // and neither novelty nor saturation can express it.
        var coveragePlateauStreak = 0
        var bestCoverage: Float = -1
        var consecutiveFailures = 0  // Track empty/failed responses from model
        var expansionCount = 0
        let maxExpansions = 3  // Allow up to 3 retrieval expansions (theoretically unlimited chunks)

        // Mutable chunk pool - can EXPAND during reasoning via adaptive retrieval
        var sortedChunks = allChunks.sorted { $0.similarityScore > $1.similarityScore }
        var usedChunkIds = Set<UUID>()  // Track which chunks we've already processed

        Log.info(
            "[Unlimited] Starting TRUE unlimited reasoning: target=\(Int(targetConfidence * 100))%, max=\(effectiveMaxSessions) sessions, chunks=\(sortedChunks.count)",
            category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // THE UNLIMITED LOOP - runs until confidence OR exhaustion
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        for sessionNum in 1...effectiveMaxSessions {
            // A one second gap between sessions while the system asks apps to scale back (iOS 27),
            // as in the reasoning chain. The loop had no cancellation check of its own.
            if sessionNum > 1 {
                await SystemResourceAdvice.easeOff(for: .seconds(1))
                try Task.checkCancellation()
            }
            let evidenceCoverageTarget = unlimitedPolicy.evidenceCoverageTarget(
                for: factBank.subQuestions.count
            )
            let sourceCoverage = Float(usedChunkIds.count) / Float(max(sortedChunks.count, 1))
            let noveltyExhausted = unlimitedPolicy.noveltyExhausted(
                lowNoveltyStreak: lowNoveltyStreak,
                saturationStreak: saturationStreak,
                sourceCoverage: sourceCoverage
            )

            // Two independent reasons to stop, not one conjunction of three.
            //
            // The old condition required confidence >= 0.98 AND coverage AND novelty
            // exhaustion simultaneously, and 0.98 is unreachable: `sessionProgress`
            // caps at 0.68, and the rest has to come from coverage and novelty terms
            // minus a saturation penalty that grows as the chain matures. High novelty
            // late means you have not saturated; low novelty means the penalty eats
            // the gain. Device runs peaked at 89% and therefore always ran the full
            // 50 sessions, even with novelty at 50% and saturation at 90% — the chain
            // knew it was finished and kept going.
            //
            // `noveltyExhausted` is already a correct marginal-gain stopping rule
            // (streak-based patience over low novelty, high saturation, or 85% source
            // coverage). It was simply gated behind a number it could never reach.
            //
            //   completed  — the question is answered to target confidence
            //   converged  — nothing new is being learned, and enough of the evidence
            //                has been seen that this is exhaustion rather than a
            //                cold start
            // Has answering *progressed*, as distinct from text being *new*?
            let coverageNow = factBank.subQuestionConfidence
            if coverageNow > bestCoverage + 0.001 {
                bestCoverage = coverageNow
                coveragePlateauStreak = 0
            } else {
                coveragePlateauStreak += 1
            }

            let completed =
                confidence >= targetConfidence
                && factBank.subQuestionConfidence >= evidenceCoverageTarget
            let converged =
                noveltyExhausted
                && sessionNum >= unlimitedPolicy.minimumSessionsBeforeConvergence
            // A flat coverage streak is *observed and logged, but not acted on*.
            //
            // It was briefly a stop condition and that was a mistake, measured on the
            // same corpus and question across three runs:
            //
            //   ceiling 50, no convergence   50 sessions   48 chars, 0 citations
            //   saturation convergence       23 sessions  209 chars, 1/2 verified, accept
            //   coverage plateau              8 sessions   67 chars, 0/1 verified, retry
            //
            // Coverage measures *breadth* — which sub-questions are answered — and it
            // was flat from session 1 because the last one was never in the document.
            // Novelty stayed at 61–86% because the chain was still accumulating
            // *depth*: more supporting evidence for the sub-questions already covered.
            // That depth is what let synthesis produce a citation the verifier could
            // check. Stopping on breadth alone cut it off and produced a shorter,
            // more confident, *less supported* answer — the worst direction to move.
            //
            // Saturation-based convergence is the empirically better proxy. Keep the
            // plateau visible for diagnosis; do not let it end a run.
            if coveragePlateauStreak == unlimitedPolicy.coveragePlateauStreakThreshold {
                Log.info(
                    "[Unlimited] Session \(sessionNum): sub-question coverage flat at "
                        + "\(Int(bestCoverage * 100))% for \(coveragePlateauStreak) sessions — "
                        + "remaining sub-questions look absent from this corpus. Continuing: "
                        + "later sessions still add supporting depth.",
                    category: .llm
                )
            }
            if completed || converged {
                terminationReason = .confidenceReached
                Log.info(
                    "[Unlimited] Session \(sessionNum): confidence=\(Int(confidence * 100))%, coverage=\(Int(factBank.subQuestionConfidence * 100))%, lowNoveltyStreak=\(lowNoveltyStreak) - STOPPING",
                    category: .llm
                )
                break
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // ADAPTIVE RETRIEVAL: When saturated, expand chunk pool
            // This is the "truly unlimited" part - we fetch MORE data
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if saturationStreak >= unlimitedPolicy.saturationStreakThreshold {
                if expansionCount < maxExpansions {
                    // Generate new queries based on what FactBank has learned
                    let expansionQueries = generateExpansionQueries(
                        originalQuery: query,
                        factBank: factBank
                    )

                    await detailedForwarder?(
                        .iterative, "Adaptive expansion", "Generating \(expansionQueries.count) new search queries")

                    var newChunks: [RetrievedChunk] = []
                    for (idx, expQuery) in expansionQueries.enumerated() {
                        await detailedForwarder?(
                            .retrieval, "Expansion \(idx + 1)/\(expansionQueries.count)",
                            "\"\(expQuery.prefix(40))...\"")

                        // Use full retrieval pipeline with event forwarding for Maximum mode visibility
                        if let chunks = try? await ragService.executeFullRetrievalPipeline(
                            query: expQuery,
                            topK: 20,
                            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(
                                for: qualityMode, stage: .fallback),
                            qualityMode: qualityMode,
                            onDetailedEvent: detailedForwarder
                        ) {
                            for chunk in chunks where !usedChunkIds.contains(chunk.chunk.id) {
                                newChunks.append(chunk)
                            }
                        }
                    }

                    if !newChunks.isEmpty {
                        // Add new chunks to the pool
                        sortedChunks.append(contentsOf: newChunks)
                        sortedChunks.sort { $0.similarityScore > $1.similarityScore }
                        expansionCount += 1
                        saturationStreak = 0  // Reset saturation

                        Log.info(
                            "[Unlimited] EXPANSION \(expansionCount)/\(maxExpansions): Added \(newChunks.count) new chunks (total: \(sortedChunks.count))",
                            category: .llm)

                        await detailedForwarder?(
                            .iterative, "Expansion complete", "+\(newChunks.count) chunks (pool: \(sortedChunks.count))"
                        )

                        // Emit expansion step
                        let expansionStep = ThinkingStep(
                            id: UUID(),
                            type: .searching,
                            input: "Adaptive retrieval expansion",
                            output: "Found \(newChunks.count) additional sources to explore",
                            tokensUsed: 0,
                            duration: 0.2,
                            timestamp: Date(),
                            confidence: confidence
                        )
                        steps.append(expansionStep)
                        await onStep?(expansionStep)
                    } else {
                        // No new chunks found - truly saturated
                        terminationReason = .contentSaturated
                        Log.info(
                            "[Unlimited] Session \(sessionNum): No new content found after expansion - STOPPING",
                            category: .llm)
                        break
                    }
                } else {
                    // Max expansions reached - all avenues exhausted
                    terminationReason = .contentSaturated
                    Log.info(
                        "[Unlimited] Session \(sessionNum): Max expansions (\(maxExpansions)) reached - STOPPING",
                        category: .llm)
                    break
                }
            }

            // Select UNUSED chunks for this session - prioritize fresh content
            let unusedChunks = sortedChunks.filter { !usedChunkIds.contains($0.chunk.id) }
            let sessionChunks: [RetrievedChunk]
            if unusedChunks.count >= 3 {
                sessionChunks = Array(unusedChunks.prefix(3))
            } else if !unusedChunks.isEmpty {
                // Use remaining unused + cycle back to highest relevance
                sessionChunks = unusedChunks + Array(sortedChunks.prefix(3 - unusedChunks.count))
            } else {
                // All chunks used - cycle through top chunks
                let chunkStartIdx = ((sessionNum - 1) * 2) % max(1, sortedChunks.count)
                sessionChunks = Array(sortedChunks.dropFirst(chunkStartIdx).prefix(3))
            }

            // Mark these chunks as used
            for chunk in sessionChunks {
                usedChunkIds.insert(chunk.chunk.id)
            }

            // Build context with strict character limit
            // SENTENCE-LEVEL EXTRACTION: Instead of packing 2-3 whole chunks into
            // 2500 chars, extract query-relevant sentences from the session's chunks.
            // This fits targeted data from all available chunks instead of
            // truncating mid-sentence. Universal across all document types.
            let maxContextChars = 2500  // ~600 tokens, leaves room for prompt + response
            let extraction = await ragService.extractRelevantSentences(
                from: sessionChunks,
                query: query,
                maxChars: maxContextChars,
                compact: true
            )
            let context = extraction.context
            Log.debug(
                "[Unlimited] Session \(sessionNum): \(extraction.sentencesIncluded) sentences from \(extraction.sourcesUsed) sources (\(context.count) chars)",
                category: .retrieval)

            // Asking the model to reason over nothing produces a request for context,
            // not a finding. `executeReasoningChain` has skipped empty windows for a
            // while; this loop did not, and a device trace shows the consequence:
            // "Session 7: 0 sentences from 0 sources (0 chars)" was sent anyway, came
            // back as 385 characters of the model asking for input, and tripped the
            // third strike that ended the run with "model unavailable".
            if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Log.debug(
                    "[Unlimited] Session \(sessionNum) skipped — empty context window",
                    category: .retrieval
                )
                // Report the skip rather than vanishing. Skipping is correct — the
                // window held no query-relevant sentences, so generating against it
                // would waste ~25s and produce a request for context — but emitting
                // nothing left the live list jumping 4 → 7 → 8 → 17 → 19, which reads
                // as a broken pipeline rather than a working one. Tagged `.searching`
                // because an empty window is a retrieval-side outcome.
                let skipStep = ThinkingStep(
                    id: UUID(),
                    type: .searching,
                    input: "Session \(sessionNum)/\(effectiveMaxSessions)",
                    output: "Skipped — no query-relevant text in this window",
                    tokensUsed: 0,
                    duration: 0,
                    timestamp: Date(),
                    confidence: confidence
                )
                steps.append(skipStep)
                await onStep?(skipStep)
                continue
            }

            // Build prompt based on session stage
            let (prompt, systemPrompt) = buildUnlimitedSessionPrompt(
                sessionNum: sessionNum,
                query: query,
                context: context,
                previousInsights: allInsights,
                currentAnswer: currentAnswer
            )

            // Adaptive temperature: higher early (exploration), lower late (precision)
            let adaptiveTemp: Float
            if sessionNum <= 3 {
                adaptiveTemp = 0.7  // Early: divergent, exploratory
            } else if sessionNum <= 8 {
                adaptiveTemp = 0.5  // Middle: balanced
            } else {
                adaptiveTemp = 0.3  // Late: focused, precise
            }

            // Execute LLM call - tools DISABLED to prevent context overflow
            // Chunks are already gathered and passed in the prompt
            let sessionStart = Date()
            let response: LLMResponse
            do {
                response = try await ragService.generateWithProperConsent(
                    prompt: prompt,
                    context: "",
                    systemPrompt: systemPrompt,
                    maxTokens: 1000,
                    disableTools: true,
                    temperature: adaptiveTemp,
                    // Same defect that made Deep Think inert, in Maximum's own loop:
                    // `context` is deliberately empty because the prompt already embeds
                    // the evidence, so with no chunks the planner saw `chunkCount == 0`,
                    // judged `insufficientEvidence`, and abstained on every session.
                    // A device run retrieved 103 chunks at 84/72/67% and then reported
                    // "Integrating 0 insights" before bailing in 17.8s.
                    //
                    // `sortedChunks` rather than `allChunks`: this loop grows its pool
                    // through adaptive retrieval when it saturates, so the live pool is
                    // what the planner must judge.
                    sourceChunks: sortedChunks,
                    forceOnDevice: true
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // This loop already survives a session that *returns* nothing, via
                // the `consecutiveFailures` three-strike counter below. A session
                // that *throws* skipped that machinery entirely and killed the whole
                // query. Observed on device: session 1 succeeded, session 2 hit
                // "[RAG] Primary LLM rate-limited", retried, failed with
                // ParsingError / "Session ended without producing a response", and
                // the run ended with no answer at all.
                //
                // The equivalent guard was added to `executeReasoningChain` in
                // fda58ed; Maximum runs this loop instead and never received it.
                // Route thrown failures into the same counter rather than inventing
                // a second recovery path.
                consecutiveFailures += 1
                Log.warning(
                    "[Unlimited] Session \(sessionNum) threw (failure \(consecutiveFailures)/3): "
                        + "\(type(of: error)) — \(error.localizedDescription)",
                    category: .llm
                )
                if consecutiveFailures >= 3 {
                    Log.error(
                        "[Unlimited] STOPPING: 3 consecutive generation failures",
                        category: .llm
                    )
                    terminationReason = .error
                    break
                }
                // Transient decode failures cluster right after a rate-limit backoff,
                // so give the model a moment before the next session.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                continue
            }
            let sessionDuration = Date().timeIntervalSince(sessionStart)
            totalTokens += response.tokensGenerated

            let insight = cleanupFinalAnswer(response.text, isFinalAnswer: false)
            let responseTextLength = response.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            let insightLength = insight.trimmingCharacters(in: .whitespacesAndNewlines).count

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // CRITICAL: Detect model failures (0 tokens = ANE/PCC failure)
            // Don't count empty responses toward confidence or session count
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Two different things, deliberately not sharing a counter.
            //
            // A hard failure means the model produced nothing: no tokens, no text.
            // Three of those in a row genuinely means it is unavailable.
            //
            // Unusable content means the model worked and said something that cannot
            // serve as a finding. Folding that into the same counter killed a run: a
            // device trace logged "EMPTY RESPONSE DETECTED (failure 3/3) - tokens=59,
            // rawLen=385, cleanLen=385" and stopped with "model unavailable", while
            // the model went on to generate the synthesis three seconds later. It had
            // been handed an empty context window and said so.
            let hardFailure =
                response.tokensGenerated == 0
                || responseTextLength == 0
                || insightLength == 0
            let unusable = !hardFailure && isUnusableInsight(insight)
            let isEmpty = hardFailure

            if unusable {
                Log.debug(
                    "[Unlimited] Session \(sessionNum): produced no usable finding "
                        + "(\(insightLength) chars) — skipping, not counted as a failure",
                    category: .llm
                )
                let skipStep = ThinkingStep(
                    id: UUID(),
                    type: .analyzing,
                    input: "Session \(sessionNum)/\(effectiveMaxSessions)",
                    output: "No usable finding in this window",
                    tokensUsed: response.tokensGenerated,
                    duration: sessionDuration,
                    timestamp: Date(),
                    confidence: confidence
                )
                steps.append(skipStep)
                await onStep?(skipStep)
                continue
            }

            if isEmpty {
                consecutiveFailures += 1
                Log.warning(
                    "[Unlimited] Session \(sessionNum): EMPTY RESPONSE DETECTED (failure \(consecutiveFailures)/3) - tokens=\(response.tokensGenerated), rawLen=\(responseTextLength), cleanLen=\(insightLength)",
                    category: .llm)

                // Stop after 3 consecutive failures to avoid infinite loop
                if consecutiveFailures >= 3 {
                    Log.error("[Unlimited] STOPPING: 3 consecutive empty responses - model unavailable", category: .llm)
                    terminationReason = .error
                    break
                }

                // Don't update confidence or add to insights - just try next session
                continue
            }

            // Reset failure counter on successful response
            consecutiveFailures = 0
            allInsights.append(insight)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // HIERARCHICAL COMPRESSION: Extract facts into Fact Bank
            // This is the "alternator" that never overflows
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let factUpdate = factBank.addFacts(from: insight)
            if factUpdate.addedFacts == 0 || factUpdate.noveltyScore < unlimitedPolicy.lowNoveltyThreshold {
                lowNoveltyStreak += 1
            } else {
                lowNoveltyStreak = 0
            }

            if sessionNum % 3 == 0 {
                Log.info(
                    "[Unlimited] Fact Bank: \(factBank.summary), +\(factUpdate.addedFacts) facts, novelty=\(Int(factUpdate.noveltyScore * 100))%, coverage=\(Int(factUpdate.evidenceCoverage * 100))%",
                    category: .llm
                )
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // REAL CONFIDENCE CALCULATION - blends session progress with sub-question coverage
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let usedSourceCoverage = Float(usedChunkIds.count) / Float(max(sortedChunks.count, 1))
            let (newConfidence, saturationScore) = calculateRealConfidence(
                allInsights: allInsights,
                query: query,
                sessionNum: sessionNum,
                subQuestionConfidence: factBank.subQuestionConfidence,
                noveltyScore: factUpdate.noveltyScore,
                sourceCoverage: usedSourceCoverage,
                maxConfidence: unlimitedPolicy.maxConfidence
            )

            // Update saturation tracking
            if unlimitedPolicy.shouldTreatAsSaturated(
                saturationScore: saturationScore,
                noveltyScore: factUpdate.noveltyScore,
                newlyAnsweredSubQuestions: factUpdate.newlyAnsweredSubQuestions
            ) {
                saturationStreak += 1
                Log.info(
                    "[Unlimited] Session \(sessionNum): High saturation (\(Int(saturationScore * 100))%), streak=\(saturationStreak)",
                    category: .llm)
            } else {
                saturationStreak = 0  // Reset streak on valuable session
            }

            // Confidence can only go UP (ratchet)
            confidence = max(confidence, newConfidence)

            // Every 5 sessions, compress insights using the Fact Bank
            // This prevents the "alternator overflow" problem
            if sessionNum % 5 == 0 {
                currentAnswer = try await synthesizeRunningAnswer(
                    query: query,
                    factBank: factBank,
                    recentInsights: Array(allInsights.suffix(3)),
                    previousAnswer: currentAnswer,
                    sourceChunks: sortedChunks
                )
                totalTokens += 200  // Estimate for synthesis
            }

            // Every session here is a reasoning pass over evidence that was already
            // retrieved before session 1 began — the console shows "Retrieval
            // complete" above them. Labelling the first two `.searching` rendered
            // them as RETRIEVAL in the live pipeline, the same class of mislabel as
            // `.analyzing` reporting as RE-RANKING. Only a session that is actually
            // consolidating gets `.synthesizing`.
            let stepType: ThinkingStep.StepType = confidence >= 0.9 ? .synthesizing : .analyzing

            // Emit step with REAL confidence
            let step = ThinkingStep(
                id: UUID(),
                type: stepType,
                input: "Session \(sessionNum)/\(effectiveMaxSessions)",
                output: String(insight.prefix(500)) + (insight.count > 500 ? "..." : ""),
                tokensUsed: response.tokensGenerated,
                duration: sessionDuration,
                timestamp: Date(),
                confidence: confidence
            )
            steps.append(step)
            await onStep?(step)

            Log.info(
                "[Unlimited] Session \(sessionNum): confidence=\(Int(confidence * 100))%, coverage=\(Int(factBank.subQuestionConfidence * 100))%, novelty=\(Int(factUpdate.noveltyScore * 100))%, saturation=\(Int(saturationScore * 100))%, tokens=\(response.tokensGenerated)",
                category: .llm
            )
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // FINAL SYNTHESIS - produce the comprehensive answer
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let synthesisStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Final synthesis",
            output: "Integrating \(allInsights.count) insights into comprehensive answer...",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date(),
            confidence: min(confidence + 0.02, unlimitedPolicy.maxConfidence)
        )
        steps.append(synthesisStep)
        await onStep?(synthesisStep)

        let finalAnswer = try await synthesizeFinalUnlimitedAnswer(
            query: query,
            factBank: factBank,
            allInsights: allInsights,
            currentAnswer: currentAnswer,
            sourceChunks: sortedChunks
        )
        totalTokens += 500  // Estimate for final synthesis

        let totalDuration = Date().timeIntervalSince(startTime)

        Log.info(
            "[Unlimited] COMPLETE: \(allInsights.count) sessions, \(Int(confidence * 100))% confident, \(terminationReason.rawValue), \(String(format: "%.1f", totalDuration))s",
            category: .llm)

        // Emit completion step
        let completionStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Complete",
            output: terminationReason.rawValue,
            tokensUsed: 0,
            duration: totalDuration,
            timestamp: Date(),
            confidence: confidence
        )
        steps.append(completionStep)
        await onStep?(completionStep)

        return UnlimitedResult(
            finalAnswer: finalAnswer,
            steps: steps,
            totalTokens: totalTokens,
            sessionsRun: allInsights.count,
            confidence: confidence,
            terminationReason: terminationReason
        )
    }

    /// Calculate REAL confidence based on multiple factors
    /// Balances sub-question coverage with session progress and content quality
    private func calculateRealConfidence(
        allInsights: [String],
        query: String,
        sessionNum: Int,
        subQuestionConfidence: Float,
        noveltyScore: Float,
        sourceCoverage: Float,
        maxConfidence: Float
    ) -> (confidence: Float, saturationScore: Float) {
        AgenticPolicyService.calculateProgressConfidence(
            allInsights: allInsights,
            query: query,
            sessionNum: sessionNum,
            subQuestionConfidence: subQuestionConfidence,
            noveltyScore: noveltyScore,
            sourceCoverage: sourceCoverage,
            maxConfidence: maxConfidence
        )
    }

    /// Build prompt for unlimited session based on stage
    /// CRITICAL: Each prompt must fit in ~1500 tokens to leave room for context + response
    private func buildUnlimitedSessionPrompt(
        sessionNum: Int,
        query: String,
        context: String,
        previousInsights: [String],
        currentAnswer: String
    ) -> (prompt: String, systemPrompt: String) {
        // Keep insight summary very compact - just hints, not full content
        let insightSummary =
            previousInsights.isEmpty
            ? ""
            : "Prior findings: " + previousInsights.suffix(2).map { String($0.prefix(150)) }.joined(separator: " | ")

        // Core instruction for all sessions: document-grounded, anti-hallucination
        let coreInstruction =
            "Report ONLY facts found in these documents. Never invent statistics, studies, or claims not in the text."

        if sessionNum == 1 {
            // First session: Initial exploration
            return (
                """
                Q: \(query)

                DOCUMENTS FROM USER'S LIBRARY:
                \(context)

                Extract specific facts, numbers, and details from these documents.
                \(coreInstruction)
                """,
                "Document analyst. Extract ONLY facts present in the documents. Never fabricate statistics or research claims."
            )
        } else if sessionNum <= 5 {
            // Early sessions: Build breadth
            return (
                """
                Q: \(query)
                \(insightSummary)

                ADDITIONAL DOCUMENTS:
                \(context)

                What NEW facts or details do these documents add? Avoid repeating prior findings.
                \(coreInstruction)
                """,
                "Document analyst. Find new details from documents only. Never fabricate. Avoid repetition."
            )
        } else if sessionNum <= 15 {
            // Middle sessions: Build depth - use currentAnswer summary
            let answerHint =
                currentAnswer.isEmpty ? "" : "Current summary covers: \(String(currentAnswer.prefix(300)))..."
            return (
                """
                Q: \(query)
                \(answerHint)

                DOCUMENTS:
                \(context)

                Add nuances or deeper details not yet covered from these documents.
                \(coreInstruction)
                """,
                "Document analyst. Find nuances from documents only. Never invent facts."
            )
        } else {
            // Later sessions: Refine and verify
            return (
                """
                Q: \(query)

                DOCUMENTS:
                \(context)

                Verify findings against these documents. Add supporting details found in the text.
                \(coreInstruction)
                """,
                "Document analyst. Verify against source text. Never fabricate."
            )
        }
    }

    /// Synthesize running answer using the Fact Bank (hierarchical compression)
    /// Uses the compressed fact bank instead of raw insights to prevent overflow
    private func synthesizeRunningAnswer(
        query: String,
        factBank: FactBank,
        recentInsights: [String],
        previousAnswer: String,
        /// The live retrieved pool. Passed for post-retrieval planning only — never
        /// rendered on the on-device branch — so the planner can judge evidence
        /// sufficiency instead of seeing zero chunks and abstaining.
        sourceChunks: [RetrievedChunk]
    ) async throws -> String {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // The Fact Bank is already compressed to ~1500 chars
        let factContext = factBank.asContext()

        // Take only 2 most recent insights (freshest context), capped at 300 chars each
        let freshInsights = recentInsights.suffix(2).map { String($0.prefix(300)) }
        let freshContext = freshInsights.isEmpty ? "" : "RECENT:\n" + freshInsights.joined(separator: "\n")

        // Previous answer summary - just key structure
        let prevSummary = previousAnswer.isEmpty ? "" : "PRIOR:\n\(String(previousAnswer.prefix(400)))...\n\n"

        let prompt = """
            Q: \(query)

            \(factContext)

            \(freshContext)

            \(prevSummary)Synthesize into a coherent answer. Preserve all facts, numbers, and citations.
            If the question was vague, interpret it based on the facts gathered.
            """

        let response = try await ragService.generateWithProperConsent(
            prompt: prompt,
            context: "",
            systemPrompt:
                "Synthesize facts into clear answers. Preserve all data. Only include facts from the documents. Never fabricate statistics or research claims. Reply in plain prose only — never JSON, key-value pairs, or field names.",
            maxTokens: 1000,
            disableTools: true,
            sourceChunks: sourceChunks,
            // Runs inside the session loop, so it stays local for the same reason the
            // sessions do: escalating every intermediate pass would turn one query
            // into dozens of cloud round-trips. Final synthesis is where PCC belongs.
            forceOnDevice: true
        )

        return cleanupFinalAnswer(response.text, isFinalAnswer: false)
    }

    /// Final synthesis of unlimited reasoning - SINGLE PASS with optional refinement
    /// Replaces the old multi-pass concatenation approach that caused massive duplication.
    /// Uses FactBank as the single source of truth — one comprehensive synthesis, then
    /// an optional REPLACEMENT refinement pass (never concatenation).
    private func synthesizeFinalUnlimitedAnswer(
        query: String,
        factBank: FactBank,
        allInsights: [String],
        currentAnswer: String,
        /// The live retrieved pool, for post-retrieval planning. This is the final
        /// synthesis, so unlike the session loop it is deliberately *not* pinned
        /// on-device -- this is the point where escalation is warranted.
        sourceChunks: [RetrievedChunk]
    ) async throws -> String {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // SINGLE-PASS SYNTHESIS — one comprehensive answer from FactBank
        // No concatenation. Optional refinement REPLACES, never appends.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let factContext = factBank.asContext()  // Already compressed to ~1500 chars

        // Gather supplementary context from recent insights (non-overlapping with FactBank)
        let supplementary: String
        if allInsights.count > 3 {
            // Fit the supplementary block into whatever the window has left after the
            // fact bank, the fixed instruction text, and the reserved output.
            //
            // This block was originally suffix(3) × prefix(300), which starved the
            // synthesizer on a 50-session run. Widening it without checking the budget
            // made things worse, not better: a device trace then showed a ~3506-token
            // prompt requesting 1500 output tokens against a 4096-token on-device
            // window. 5006 into 4096 does not go — the model was left almost no room
            // and emitted five tokens, a 48-character answer after 22,292 tokens of
            // reasoning. Size the input to the window instead of assuming it fits.
            let perInsight = allInsights.count > 20 ? 220 : 320
            let maxKeep = min(8, max(3, allInsights.count / 4))
            let recent = allInsights.suffix(maxKeep).map { String($0.prefix(perInsight)) }
            let header = "\n\nSUPPLEMENTARY FINDINGS:\n"
            let joined = recent.joined(separator: "\n")

            let remaining = supplementaryCharBudget(
                factContextChars: factContext.count,
                queryChars: query.count
            )
            if remaining <= header.count + 80 {
                supplementary = ""
                Log.info(
                    "[Synthesis] Supplementary findings dropped — no context budget left "
                        + "(fact bank \(factContext.count) chars)",
                    category: .llm
                )
            } else if joined.count + header.count > remaining {
                let fitted = truncateAtSentenceBoundary(joined, limit: remaining - header.count)
                supplementary = header + fitted
                Log.info(
                    "[Synthesis] Supplementary findings trimmed to fit context: "
                        + "\(joined.count) → \(fitted.count) chars",
                    category: .llm
                )
            } else {
                supplementary = header + joined
            }
        } else {
            supplementary = ""
        }

        Log.info(
            "[Synthesis] Single-pass synthesis with Fact Bank (\(factBank.summary)), \(allInsights.count) insights",
            category: .llm)

        // ── PASS 1: Comprehensive answer from ALL evidence ──
        let synthesisPrompt = """
            Q: \(query)

            DOCUMENT FINDINGS:
            \(factContext)\(supplementary)

            Write a thorough answer using ONLY the document findings above:
            - Include ALL specific values, numbers, names, and details from the findings
            - Use **bold** sparingly for key terms only — do NOT bold every noun or defined term
            - Organize by topic/theme with clear headings
            - Include practical details, caveats, or limitations ONLY if mentioned in the findings
            - Do NOT invent facts, statistics, or research claims not in the findings
            - Do NOT add "research perspective" or "future research" sections
            - Every statement must trace back to the document findings
            - Carry through the [S1], [S2] markers attached to each claim above. Cite only
              markers that appear in the findings; never invent one.
            - Preserve any uncertainty the findings express. If a finding questions a term
              or notes a possible source error, keep that qualification.
            Never repeat the same information twice.
            """

        // A throw here discards everything the run produced: up to 50 sessions and,
        // on one device trace, 26 minutes of work. `currentAnswer` is the running
        // synthesis the loop maintained along the way, so it is a real answer rather
        // than a placeholder. Degrade to it instead of failing the query outright.
        let coreResponse: LLMResponse
        do {
            coreResponse = try await LLMStreamingContext.$handler.withValue(LLMStreamingContext.answerHandler) {
                try await ragService.generateWithProperConsent(
                    prompt: synthesisPrompt,
                    context: "",
                    systemPrompt:
                        "Document analyst. Answer using ONLY the provided findings. Never fabricate facts or statistics. Use **bold** sparingly for key terms only. Never repeat content. Reply in plain prose only — never JSON, key-value pairs, or field names.",
                    maxTokens: Self.synthesisOutputTokenReserve,  // must match supplementaryCharBudget
                    disableTools: true,
                    sourceChunks: sourceChunks
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let fallback = cleanupFinalAnswer(currentAnswer).trimmingCharacters(in: .whitespacesAndNewlines)
            Log.warning(
                "[Unlimited] Final synthesis threw (\(type(of: error))); "
                    + "returning the accumulated running answer (\(fallback.count) chars)",
                category: .llm
            )
            if !fallback.isEmpty { return fallback }
            throw error
        }
        var finalAnswer = cleanupFinalAnswer(coreResponse.text)

        // ── PASS 2: Refinement (REPLACES, never appends) — only if sufficient evidence ──
        // This pass checks for missing facts and removes duplication.
        // Only triggers when we have substantial evidence (8+ insights) AND the answer is long enough
        // that it might have missed something or contain repetition.
        if allInsights.count > 8 && finalAnswer.count > 800 {
            let refinementPrompt = """
                Q: \(query)

                FACT BANK (all known facts):
                \(factContext)

                DRAFT ANSWER:
                \(String(finalAnswer.prefix(1800)))

                Improve this draft:
                1. Add any facts from the FACT BANK that are missing from the draft
                2. Remove any duplicated or repeated content
                3. Remove any claims not supported by the FACT BANK
                4. Keep the same structure and formatting
                Return the improved complete answer.
                """

            // This pass is optional by design -- it only replaces the answer when it
            // comes back substantial. A throw should therefore cost nothing at all,
            // rather than discarding a core synthesis that already succeeded.
            let refinedText = try? await ragService.runFinishableStage {
                try await ragService.generateWithProperConsent(
                    prompt: refinementPrompt,
                    context: "",
                    systemPrompt:
                        "Editor. Only include facts from the FACT BANK. Remove repetition. Remove unsupported claims. Reply in plain prose only — never JSON, key-value pairs, or field names.",
                    maxTokens: Self.synthesisOutputTokenReserve,  // must match supplementaryCharBudget
                    disableTools: true,
                    sourceChunks: sourceChunks
                ).text
            }
            let refined = cleanupFinalAnswer(refinedText ?? "")

            // Only use refinement if it's substantial AND it keeps the draft's citations.
            //
            // The length test alone was the one replacement site in this file not covered by
            // `shouldAcceptReplacement`, found by enumerating them on 2026-08-25. A refinement
            // returning 60% of the draft's length with zero citations replaced a fully cited
            // answer and nothing checked.
            //
            // This path is more likely to produce that than any other, not less: the prompt
            // above instructs the editor to "remove any claims not supported by the FACT BANK",
            // and an editor following that instruction strips citation markers, which look
            // exactly like unsupported cruft. The guard belongs here most of all.
            if refined.count > finalAnswer.count / 2,
                Self.shouldAcceptReplacement(previous: finalAnswer, replacement: refined)
            {
                finalAnswer = refined  // REPLACE, never append
            }
        }

        // ── Final cross-pass deduplication ──
        finalAnswer = deduplicateSynthesizedAnswer(finalAnswer)

        Log.info(
            "[Synthesis] Final answer: \(finalAnswer.count) chars from \(allInsights.count) insights", category: .llm)

        return finalAnswer
    }

}

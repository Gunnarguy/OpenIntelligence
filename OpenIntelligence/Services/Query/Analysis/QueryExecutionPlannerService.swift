import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum QueryExecutionMode: String, Sendable {
    case conversational
    case directLookup
    case standardRetrieval
    case decomposedRetrieval
    case agenticRetrieval

    var displayName: String {
        switch self {
        case .conversational: return "Conversational"
        case .directLookup: return "Direct Lookup"
        case .standardRetrieval: return "Standard Retrieval"
        case .decomposedRetrieval: return "Decomposed Retrieval"
        case .agenticRetrieval: return "Agentic Retrieval"
        }
    }
}

struct QueryExecutionPlan: Sendable {
    let query: String
    let profile: QueryProfile
    let needsRetrieval: Bool
    let executionMode: QueryExecutionMode
    let preferLiteralQuery: Bool
    let useToolCalling: Bool
    let useStructuredEvidenceLookup: Bool
    let searchQueries: [String]
    let subqueries: [String]
    let reasoning: String

    var shouldDecompose: Bool {
        executionMode == .decomposedRetrieval
    }

    var shouldAutoEscalateToAgentic: Bool {
        executionMode == .decomposedRetrieval || executionMode == .agenticRetrieval
    }
}

final class QueryExecutionPlannerService {
    static let shared = QueryExecutionPlannerService()

    private static let conversationalPrefixes: [String] = [
        "hello", "hi", "hey", "thanks", "thank you", "bye", "goodbye",
        "how are you", "what's your name", "who are you", "help", "what can you do",
    ]

    private static let decompositionMarkers: [String] = [
        "compare", "versus", " vs ", "difference between", "similarities between",
        "across all", "pros and cons", "advantages and disadvantages", "why", "explain why",
        "as well as", "in addition", "along with",
    ]

    private static let searchStopWords: Set<String> = [
        "what", "how", "why", "when", "where", "who", "which", "does", "do", "is",
        "are", "was", "were", "the", "a", "an", "of", "in", "to", "for", "and",
        "or", "on", "with", "this", "that", "these", "those", "about", "please",
        "tell", "show", "give", "me", "mean", "means", "meaning",
    ]

    func buildPlan(
        for query: String,
        profile: QueryProfile? = nil,
        requestedQualityMode: RAGQualityMode = .standard,
        allowToolCalling: Bool = true
    ) async -> QueryExecutionPlan {
        let resolvedProfile: QueryProfile
        if let profile {
            resolvedProfile = profile
        } else {
            resolvedProfile = await QueryProfileService.shared.buildProfile(for: query, routingEnabled: false)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let planned = await buildFoundationModelPlan(
                for: query,
                profile: resolvedProfile,
                requestedQualityMode: requestedQualityMode,
                allowToolCalling: allowToolCalling
           )
        {
            return planned
        }
        #endif

        return buildHeuristicPlan(
            for: query,
            profile: resolvedProfile,
            requestedQualityMode: requestedQualityMode,
            allowToolCalling: allowToolCalling
        )
    }

    private func buildHeuristicPlan(
        for query: String,
        profile: QueryProfile,
        requestedQualityMode: RAGQualityMode,
        allowToolCalling: Bool
    ) -> QueryExecutionPlan {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isConversational = profile.isTrivial && Self.conversationalPrefixes.contains { normalized == $0 || normalized.hasPrefix($0) }

        if isConversational {
            return QueryExecutionPlan(
                query: query,
                profile: profile,
                needsRetrieval: false,
                executionMode: .conversational,
                preferLiteralQuery: true,
                useToolCalling: false,
                useStructuredEvidenceLookup: false,
                searchQueries: [query],
                subqueries: [],
                reasoning: "Conversational/meta query - no document retrieval needed"
            )
        }

        let preferLiteralQuery = profile.isSimpleGroundedLookup
        let decompositionNeeded = shouldDecompose(query: normalized, profile: profile)
        let useStructuredEvidenceLookup = profile.answerIntent.isExtractiveFirst

        let executionMode: QueryExecutionMode
        if preferLiteralQuery {
            executionMode = .directLookup
        } else if decompositionNeeded {
            executionMode = requestedQualityMode.canonical == .standard ? .decomposedRetrieval : .agenticRetrieval
        } else if requestedQualityMode.usesAgenticOrchestrator {
            executionMode = .agenticRetrieval
        } else {
            executionMode = .standardRetrieval
        }

        let searchQueries = normalizedSearchQueries(
            query,
            profile: profile,
            executionMode: executionMode
        )

        let subqueries = executionMode == .decomposedRetrieval || executionMode == .agenticRetrieval
            ? normalizedSubqueries(for: query, profile: profile)
            : []

        let useToolCalling = allowToolCalling
            && requestedQualityMode.usesAgenticOrchestrator
            && !preferLiteralQuery
            && executionMode != .conversational

        let reasoning: String
        switch executionMode {
        case .conversational:
            reasoning = "Conversational query"
        case .directLookup:
            reasoning = "Extractive/manual lookup - keep entities and wording literal"
        case .standardRetrieval:
            reasoning = "Single focused grounded retrieval"
        case .decomposedRetrieval:
            reasoning = "Multi-part query - decompose into searchable sub-questions"
        case .agenticRetrieval:
            reasoning = "Deep/maximum mode - use agentic retrieval with shared search plan"
        }

        return QueryExecutionPlan(
            query: query,
            profile: profile,
            needsRetrieval: true,
            executionMode: executionMode,
            preferLiteralQuery: preferLiteralQuery,
            useToolCalling: useToolCalling,
            useStructuredEvidenceLookup: useStructuredEvidenceLookup,
            searchQueries: searchQueries,
            subqueries: subqueries,
            reasoning: reasoning
        )
    }

    private func shouldDecompose(query: String, profile: QueryProfile) -> Bool {
        if profile.answerIntent == .compare || profile.answerIntent == .investigate || profile.answerIntent == .findings {
            return true
        }

        if profile.reasoningComplexity.suggestedMode == .agentic,
           profile.reasoningComplexity.complexity == .complex
        {
            return true
        }

        if Self.decompositionMarkers.contains(where: { query.contains($0) }) {
            return true
        }

        return query.filter { $0 == "?" }.count > 1
    }

    private func normalizedSearchQueries(
        _ query: String,
        profile: QueryProfile,
        executionMode: QueryExecutionMode
    ) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var queries: [String] = [trimmed]
        let terms = distilledSearchTerms(from: trimmed)
        if !terms.isEmpty {
            queries.append(terms.joined(separator: " "))
        }

        if executionMode == .decomposedRetrieval || executionMode == .agenticRetrieval {
            for subquery in normalizedSubqueries(for: trimmed, profile: profile) {
                queries.append(subquery)
            }
        }

        if profile.answerIntent == .lookup || profile.answerIntent == .tableLookup {
            if !terms.isEmpty {
                queries.append((terms + ["specification"]).joined(separator: " "))
                queries.append((terms + ["table"]).joined(separator: " "))
            }
        }

        return deduplicatedQueries(queries, originalQuery: trimmed)
    }

    private func normalizedSubqueries(for query: String, profile: QueryProfile) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var subqueries: [String] = []
        let lower = trimmed.lowercased()

        if lower.contains(" compare ") || lower.contains(" versus ") || lower.contains(" vs ") {
            let separators = [" compare ", " versus ", " vs "]
            for separator in separators where lower.contains(separator) {
                let parts = trimmed.components(separatedBy: separator)
                let normalizedParts = parts
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if normalizedParts.count >= 2 {
                    subqueries.append("details about \(normalizedParts[0])")
                    subqueries.append("details about \(normalizedParts[1])")
                    subqueries.append("differences between \(normalizedParts[0]) and \(normalizedParts[1])")
                    break
                }
            }
        }

        if subqueries.isEmpty {
            let clauses = trimmed
                .components(separatedBy: CharacterSet(charactersIn: "?;"))
                .flatMap { clause in
                    clause.components(separatedBy: " and ")
                }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.split(whereSeparator: { $0.isWhitespace }).count >= 3 }

            if clauses.count >= 2 {
                subqueries.append(contentsOf: clauses.prefix(4))
            }
        }

        if subqueries.isEmpty {
            let terms = distilledSearchTerms(from: trimmed)
            if !terms.isEmpty {
                let topic = terms.prefix(4).joined(separator: " ")
                switch profile.answerIntent {
                case .compare:
                    subqueries = ["key facts \(topic)", "differences \(topic)", "limitations \(topic)"]
                case .investigate, .findings:
                    subqueries = ["evidence \(topic)", "key findings \(topic)", "warnings exceptions \(topic)"]
                default:
                    subqueries = ["key facts \(topic)", "details \(topic)"]
                }
            }
        }

        return deduplicatedQueries(subqueries, originalQuery: trimmed)
            .prefix(4)
            .map { $0 }
    }

    private func distilledSearchTerms(from query: String) -> [String] {
        query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !Self.searchStopWords.contains($0) }
    }

    private func deduplicatedQueries(_ candidates: [String], originalQuery: String) -> [String] {
        var seen = Set<String>()
        var deduped: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            deduped.append(trimmed)
        }

        if deduped.isEmpty {
            return [originalQuery]
        }

        return Array(deduped.prefix(5))
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension QueryExecutionPlannerService {
    @Generable
    struct GuidedQueryExecutionPlan {
        var needsRetrieval: Bool
        var executionMode: String
        var preferLiteralQuery: Bool
        var useToolCalling: Bool
        var useStructuredEvidenceLookup: Bool
        var searchQueries: [String]
        var subqueries: [String]
        var reasoning: String
    }

    func buildFoundationModelPlan(
        for query: String,
        profile: QueryProfile,
        requestedQualityMode: RAGQualityMode,
        allowToolCalling: Bool
    ) async -> QueryExecutionPlan? {
        guard SystemLanguageModel.default.availability == .available else {
            return nil
        }

        let instructions = Instructions(
            "You are a retrieval execution planner for a document QA engine. Return a compact, retrieval-first plan. Only skip retrieval for obvious greetings or assistant-meta requests. Keep entities, colors, units, model numbers, and codes literal."
        )

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )
        session.prewarm(promptPrefix: Prompt("Question:\nExecution mode:"))

        let prompt = """
        Question: \(query)
        Requested quality mode: \(requestedQualityMode.displayName)
        Tool calling allowed: \(allowToolCalling ? "yes" : "no")

        Query profile:
        - word count: \(profile.wordCount)
        - trivial: \(profile.isTrivial)
        - answer intent: \(profile.answerIntent.rawValue)
        - search intent: \(profile.searchIntent.rawValue)
        - routing type: \(profile.routingClassification.queryType.rawValue)
        - reasoning complexity: \(profile.reasoningComplexity.complexity.rawValue)
        - reasoning mode: \(profile.reasoningComplexity.suggestedMode.rawValue)

        Execution mode must be one of:
        - conversational
        - direct_lookup
        - standard_retrieval
        - decomposed_retrieval
        - agentic_retrieval

        Rules:
        - This is a retrieval-first engine.
        - direct_lookup is for literal manual/spec/table/state lookups.
        - decomposed_retrieval is for multi-part or compare/investigate questions that need sub-questions.
        - agentic_retrieval is for deep exploratory reasoning when the requested mode already allows it.
        - searchQueries must be concrete and searchable, with literal entities preserved.
        - subqueries should be empty unless decomposition is clearly useful.
        - useToolCalling should be false for direct lookups and false when tool calling is not allowed.
        """

        do {
            let planned = try await session.respond(
                to: prompt,
                generating: GuidedQueryExecutionPlan.self
            )
            let content = planned.content

            let executionMode: QueryExecutionMode
            switch content.executionMode.lowercased() {
            case "conversational":
                executionMode = .conversational
            case "direct_lookup":
                executionMode = .directLookup
            case "decomposed_retrieval":
                executionMode = .decomposedRetrieval
            case "agentic_retrieval":
                executionMode = .agenticRetrieval
            default:
                executionMode = .standardRetrieval
            }

            return QueryExecutionPlan(
                query: query,
                profile: profile,
                needsRetrieval: content.needsRetrieval,
                executionMode: executionMode,
                preferLiteralQuery: content.preferLiteralQuery,
                useToolCalling: allowToolCalling && content.useToolCalling,
                useStructuredEvidenceLookup: content.useStructuredEvidenceLookup,
                searchQueries: deduplicatedQueries(content.searchQueries.isEmpty ? [query] : content.searchQueries, originalQuery: query),
                subqueries: deduplicatedQueries(content.subqueries, originalQuery: query),
                reasoning: content.reasoning.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            )
        } catch {
            Log.warning("[QueryPlanner] Foundation Models planning failed: \(error.localizedDescription)", category: .retrieval)
            return nil
        }
    }
}
#endif

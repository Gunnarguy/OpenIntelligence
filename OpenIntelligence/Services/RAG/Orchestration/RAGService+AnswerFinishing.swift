//
//  RAGService+AnswerFinishing.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Document Content Classification

    /// Classify document domain from filename patterns and corpus signals.
    /// Returns a short human-readable domain like "Vehicle Manual" or "Technical Report".
    static func classifyDocumentDomain(
        filename: String,
        signals: LibraryIntelligenceCenter.CorpusSignals,
        entities: [String]
    ) -> String {
        let lower = filename.lowercased()
        let joinedEntities = entities.joined(separator: " ").lowercased()
        let combined = lower + " " + joinedEntities

        // Filename-based quick matches
        let domainPatterns: [(keywords: [String], domain: String)] = [
            (["owner", "manual", "vehicle", "car", "truck", "suv", "sedan", "automotive", "motor"], "Vehicle Manual"),
            (["study", "protocol", "cohort", "assay", "sample", "specimen", "pharma"], "Life Sciences Document"),
            (["legal", "contract", "agreement", "statute", "law", "regulation", "compliance"], "Legal Document"),
            (
                ["financial", "accounting", "balance sheet", "income statement", "revenue", "fiscal"],
                "Financial Document"
            ),
            (["recipe", "cooking", "ingredient", "culinary", "baking"], "Recipe Collection"),
            (["syllabus", "curriculum", "course", "lecture", "education", "textbook", "exam"], "Educational Material"),
            (["api", "sdk", "documentation", "reference", "developer", "programming"], "API Documentation"),
            (["research", "abstract", "methodology", "hypothesis", "findings", "journal"], "Research Paper"),
            (["resume", "cv", "curriculum vitae", "experience", "qualifications"], "Resume / CV"),
            (["invoice", "receipt", "purchase", "order", "billing", "payment"], "Invoice / Receipt"),
            (["patent", "invention", "claims", "prior art"], "Patent Document"),
            (["blueprint", "schematic", "wiring", "circuit", "engineering", "cad"], "Engineering Drawing"),
            (["safety", "msds", "hazard", "sds", "material safety"], "Safety Data Sheet"),
            (["report", "analysis", "summary", "overview", "assessment"], "Report"),
            (["manual", "guide", "handbook", "instructions", "procedure"], "Reference Manual"),
            (["specification", "spec", "requirements", "standard"], "Specification"),
            (["presentation", "slide", "deck"], "Presentation"),
            (["memo", "memorandum", "circular", "notice"], "Memo / Notice"),
        ]

        for pattern in domainPatterns {
            let matchCount = pattern.keywords.filter { combined.contains($0) }.count
            if matchCount >= 2 { return pattern.domain }
        }

        // Single keyword fallback with high confidence
        for pattern in domainPatterns.prefix(10) {
            if pattern.keywords.contains(where: { lower.contains($0) }) {
                return pattern.domain
            }
        }

        // Signal-based fallback
        if signals.hasCode && signals.technicalDensity > 0.3 {
            return "Source Code"
        }
        if signals.hasMath {
            return "Technical Document"
        }
        if signals.technicalDensity > 0.4 {
            return "Technical Document"
        }

        return "Document"
    }

    /// Build a short content descriptor from document profiles.
    static func buildContentDescriptor(
        signals: LibraryIntelligenceCenter.CorpusSignals,
        entities: [String]
    ) -> String {
        // Use top entities to describe what the content is about
        let uniqueTopics = Array(Set(entities.map { $0.lowercased().capitalized })).prefix(4)
        if !uniqueTopics.isEmpty {
            return uniqueTopics.joined(separator: ", ")
        }

        // Fallback: describe by content characteristics
        var traits: [String] = []
        if signals.hasCode { traits.append("code") }
        if signals.hasMath { traits.append("formulas") }
        if signals.technicalDensity > 0.3 { traits.append("technical") }
        if signals.multilingualScore > 0.3 { traits.append("multilingual") }
        if signals.structuredRatio > 0.5 { traits.append("structured data") }
        return traits.isEmpty ? "General content" : traits.joined(separator: " & ")
    }

    /// Extract meaningful content categories from entities and signals.
    static func extractContentCategories(
        entities: [String],
        signals: LibraryIntelligenceCenter.CorpusSignals
    ) -> [String] {
        var categories: [String] = []

        // Use entity topics
        let uniqueEntities = Array(Set(entities.map { $0.capitalized }))
        categories.append(contentsOf: uniqueEntities.prefix(5))

        // Add signal-derived categories
        if signals.hasCode { categories.append("Code") }
        if signals.hasMath { categories.append("Mathematics") }
        if signals.multilingualScore > 0.3 { categories.append("Multilingual") }

        return Array(Set(categories)).sorted()
    }

    /// Map raw NLLanguage code to human-readable name.
    static func languageDisplayName(_ code: String) -> String {
        let map: [String: String] = [
            "en": "English", "es": "Spanish", "fr": "French",
            "de": "German", "it": "Italian", "pt": "Portuguese",
            "nl": "Dutch", "pl": "Polish", "ja": "Japanese",
            "ko": "Korean", "zh-Hans": "Chinese (Simplified)",
            "zh-Hant": "Chinese (Traditional)", "ar": "Arabic",
            "ru": "Russian", "hi": "Hindi", "sv": "Swedish",
            "da": "Danish", "fi": "Finnish", "nb": "Norwegian",
            "tr": "Turkish", "th": "Thai", "vi": "Vietnamese",
        ]
        return map[code] ?? code.uppercased()
    }

    // MARK: - Provider Display Names

    /// Maps embedding provider IDs to concise, SWE-accurate display names.
    /// These shorthand names maintain technical precision while fitting in pill UI elements.
    static func shortProviderName(for providerId: String) -> String {
        switch providerId.lowercased() {
        case "coreml_sentence_embedding", "coreml_sentence":
            return "CoreML"  // MiniLM-L6-v2 sentence transformer
        case "nl_embedding", "nlembedding":
            return "NL"  // NaturalLanguage.framework
        case "apple_foundation", "apple_fm":
            return "FM"  // Foundation Models (Apple Intelligence)
        case "openai_embedding", "openai":
            return "OpenAI"  // text-embedding-3-small/large
        case "nl_contextual", "contextual":
            return "NLCtx"  // NLContextualEmbedding
        default:
            // Fallback: first word capitalized, or abbreviate long names
            let parts = providerId.split(separator: "_")
            if parts.count >= 2 {
                // Take first letters of each word for long providers
                return parts.prefix(2).map { $0.prefix(4).capitalized }.joined()
            }
            return String(providerId.prefix(8)).capitalized
        }
    }

    /// Returns a configured service for the given settings key, if available.
    /// Simplified: only Apple Intelligence and On-Device Analysis are supported.
    static func instantiateService(
        for modelKey: String,
        entitlementStore _: EntitlementStore?
    ) -> LLMService? {
        // Migrate deprecated model keys to supported types
        let effectiveKey = LLMModelType.isDeprecatedRawValue(modelKey) ? "apple_intelligence" : modelKey

        switch effectiveKey {
        case "apple_intelligence":
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    guard foundationService.isAvailable else {
                        Log.warning(
                            "Apple Foundation Models unavailable on this device",
                            category: .initialization
                        )
                        return nil
                    }
                    foundationService.startWarmup()
                    Log.info(
                        "✓ Using Apple Foundation Models (on-device + PCC)",
                        category: .initialization
                    )
                    Log.debug(
                        "🔥 Preloading model in background for instant first query",
                        category: .initialization
                    )
                    return foundationService
                } else {
                    Log.warning(
                        "Apple Intelligence requires iOS 26.0 or later", category: .initialization
                    )
                }
            #endif
            return nil
        case "on_device_analysis":
            // on_device_analysis is now handled by Apple Intelligence; silent fallthrough
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    if foundationService.isAvailable {
                        foundationService.startWarmup()
                        return foundationService
                    }
                }
            #endif
            return nil
        default:
            // Unknown model type - try Apple Intelligence
            Log.warning("Unknown model type: \(modelKey); trying Apple Intelligence", category: .initialization)
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    if foundationService.isAvailable {
                        foundationService.startWarmup()
                        return foundationService
                    }
                }
            #endif
            return nil
        }
    }

    /// Builds an ordered list of fallback services, excluding the user's primary selection.
    static func buildFallbackChain(excluding modelKey: String) -> [LLMService] {
        var fallbacks: [LLMService] = []

        let capabilities = checkDeviceCapabilities()
        let appleCapable = capabilities.supportsAppleIntelligence || capabilities.supportsFoundationModels

        // Try Apple Intelligence first (if available and not primary)
        #if canImport(FoundationModels)
            if modelKey != "apple_intelligence" {
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    if foundationService.isAvailable {
                        fallbacks.append(foundationService)
                        Log.debug("Added Apple Intelligence to fallback chain", category: .initialization)
                    }
                }
            }
        #endif

        // No additional fallbacks - Apple Intelligence is the only supported provider
        // If Apple Intelligence is unavailable, generation will fail with a clear error
        if !appleCapable {
            Log.warning(
                "Device does not support Apple Intelligence - no fallbacks available", category: .initialization)
        }

        return fallbacks
    }

    /// Log structured query statistics for debugging and telemetry dashboards
    @MainActor
    private func logQueryStats(query: String, response: RAGResponse) async {
        let queryWords = wordCount(of: query)
        let responseWords = wordCount(of: response.generatedResponse)
        let chunkWordCounts = response.retrievedChunks.map { wordCount(of: $0.chunk.content) }
        let chunkWordTotal = chunkWordCounts.reduce(0, +)
        let averageChunkWords =
            chunkWordCounts.isEmpty
            ? 0.0
            : Double(chunkWordTotal) / Double(chunkWordCounts.count)

        var statsContent: [String] = [
            "Query: \(String(query.prefix(50)))… (≈\(queryWords) words)",
            "Chunks: \(response.retrievedChunks.count) (≈\(Int(averageChunkWords.rounded())) words avg)",
            "Retrieval: \(String(format: "%.2f", response.metadata.retrievalTime))s",
            "Generation: \(String(format: "%.2f", response.metadata.totalGenerationTime))s",
            "Response words: \(responseWords)",
            "Model: \(response.metadata.modelUsed)",
        ]

        if let ttft = response.metadata.timeToFirstToken {
            statsContent.append("Time to first token: \(String(format: "%.2f", ttft))s")
        }
        if let tps = response.metadata.tokensPerSecond {
            statsContent.append("Tokens per second: \(String(format: "%.1f", tps))")
        }

        Log.info("📊 RAG Query Statistics", category: .pipeline)
        for line in statsContent {
            Log.info("  • \(line)", category: .pipeline)
        }

        TelemetryCenter.emit(
            .system,
            title: "Query stats",
            metadata: [
                "queryWords": "\(queryWords)",
                "responseWords": "\(responseWords)",
                "chunkWords": "\(chunkWordTotal)",
                "chunkCount": "\(response.retrievedChunks.count)",
                "retrievalTime": String(format: "%.2f", response.metadata.retrievalTime),
                "generationTime": String(format: "%.2f", response.metadata.totalGenerationTime),
                "model": response.metadata.modelUsed,
            ]
        )
    }

    @MainActor
    private func recordRetrievalHistory(
        query: String,
        containerId: UUID,
        containerName: String,
        chunks: [RetrievedChunk]
    ) {
        guard !chunks.isEmpty else { return }
        let entry = RetrievalLogEntry(
            timestamp: Date(),
            query: query,
            containerId: containerId,
            containerName: containerName,
            chunks: chunks
        )
        retrievalHistory.append(entry)
        if retrievalHistory.count > retrievalHistoryLimit {
            retrievalHistory.removeFirst(retrievalHistory.count - retrievalHistoryLimit)
        }
    }

    func finalizeResponse(
        query: String,
        containerId: UUID,
        containerName: String,
        response: RAGResponse
    ) async -> RAGResponse {
        // Clean up the response text (normalize whitespace, preserve markdown formatting)
        let cleanedResponse = cleanupResponseText(response.generatedResponse)
        let stabilizedResponse = trimIncompleteResponseTail(cleanedResponse)
        let repairedResponse = repairMalformedURLs(stabilizedResponse)
        // A label past the end of the answer's passages opens nothing, and it means the labels the model was shown
        // and the passages the answer keeps were numbered differently. It is logged, not removed, as for the
        // reasoning trace above ("This logs rather than rewrites"): on 2026-10-20 "$300.00 [S1], [S5], [S6]" was the
        // model citing correctly from a context the sentence extractor numbered by candidate, against three passages
        // numbered 1 to 3, and taking the labels out would have hidden that (fixed where the labels are made,
        // `extractRelevantSentencesOffMain` and `RAGEngine.assembleContext`).
        let unmatched = AgenticOrchestrator.danglingCitations(
            in: repairedResponse, sourceCount: response.retrievedChunks.count)
        if !unmatched.isEmpty {
            Log.warning(
                "[RAGService] The answer cites \(unmatched.map { "[S\($0)]" }.joined(separator: ", ")) against "
                    + "\(response.retrievedChunks.count) source(s); the labels and the answer's passages were numbered "
                    + "differently, so those labels open nothing.",
                category: .llm
            )
        }
        let finalizedStructuredAnswer = response.structuredAnswer?.updatingAnswer(repairedResponse)
        let fallbackReasoningTrace = await MainActor.run {
            self.thinkingEvents.compactReasoningTrace()
        }
        var finalizedMetadata = response.metadata.withReasoningTrace(fallbackReasoningTrace)
        // An answer the person finished before its later stages ran says so in its own record, so a
        // saved answer or an exported trace never reads as checked when the check was skipped.
        if await MainActor.run(body: { self.finishAnswerNowRequested }) {
            finalizedMetadata = finalizedMetadata.appendingGatingDecision("finished_early_by_person")
        }
        // Apple's count for the whole answer (5.7), set by `query`'s tally.
        if let usage = AnswerUsageTally.current?.total {
            finalizedMetadata.appleUsage = usage
        }
        var finalResponse = response
        finalResponse = RAGResponse(
            queryId: response.queryId,
            retrievedChunks: response.retrievedChunks,
            generatedResponse: repairedResponse,
            metadata: finalizedMetadata,
            confidenceScore: response.confidenceScore,
            qualityWarnings: response.qualityWarnings,
            structuredAnswer: finalizedStructuredAnswer
        )

        await MainActor.run {
            self.recordRetrievalHistory(
                query: query,
                containerId: containerId,
                containerName: containerName,
                chunks: finalResponse.retrievedChunks
            )
        }

        // Record conversation turn for memory service (enables multi-turn context)
        // IMPORTANT: Fire-and-forget to avoid blocking response delivery
        let useConversationMemory = await MainActor.run { settingsStore?.enableConversationMemory ?? true }
        if #available(iOS 26.0, *), useConversationMemory {
            // Detached task prevents blocking the response return
            Task.detached(priority: .utility) {
                await ConversationMemoryService.shared.addTurn(
                    userQuery: query,
                    assistantResponse: finalResponse.generatedResponse,
                    for: containerId
                )
            }
        }

        await logQueryStats(query: query, response: finalResponse)
        return finalResponse
    }

    nonisolated func appendedGatingDecision(_ existing: String?, _ decision: String) -> String {
        existing.map { "\($0),\(decision)" } ?? decision
    }

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        func sourceOnlyOutcomeIfNeeded(
            query: String,
            candidateAnswer: String,
            retrievedChunks: [RetrievedChunk],
            answerIntent: AnswerIntent,
            verificationResult: RAGVerificationResult?,
            isSourceLocked: Bool = false
        ) async -> SourceOnlyAnswerOutcome? {
            let trimmedAnswer = candidateAnswer.trimmingCharacters(in: .whitespacesAndNewlines)

            // Every exit from this gate now says why. Three device runs were spent trying to
            // reach this stage and all three missed it silently, because a `return nil` looks
            // identical to a stage that ran and found nothing. Pairs with the `AnswerIntent`
            // line in `QueryEnhancementService.classifyAnswerIntent`: that one says what the
            // query was classified as, this one says what the gate did about it.
            func decline(_ reason: String) -> SourceOnlyAnswerOutcome? {
                Log.info(
                    "[SourceOnly] Skipped — \(reason). intent=\(answerIntent), "
                        + "chunks=\(retrievedChunks.count), answerChars=\(trimmedAnswer.count)",
                    category: .llm
                )
                return nil
            }

            guard !trimmedAnswer.isEmpty, !retrievedChunks.isEmpty else {
                return decline(trimmedAnswer.isEmpty ? "candidate answer is empty" : "no retrieved chunks")
            }
            guard answerIntent.isExtractiveFirst else {
                return decline("intent is not extractive-first; only .lookup and .tableLookup are")
            }
            guard !isSourceLocked else { return decline("query is source-locked") }
            guard !finishAnswerNowRequested else { return decline("the person finished the answer early") }

            let preserveAbstention = (Self.isStateLookupQuery(query) || isPrecisionValueQuery(query)) && !isSourceLocked

            // An exact early exit (5.8). How much of the answer the check would be shown is fixed by token budgets
            // before any model call (`candidateCoverageBeforeModel`, the same code the check runs). Below the floor,
            // and with no abstention to preserve, `sourceOnlyVerdict` keeps the generated answer for every outcome
            // the model could return (`SourceOnlyVerdictTests` walks them all), so the draft and its review would be
            // spent for nothing: 46.6 s at 17% coverage on his iPhone on 2026-11-04 before "Declining to replace"
            // (`~/Library/Developer/OpenIntelligence-evidence/2026-11-04_141602`) `[evidence_level: measured]`.
            if !preserveAbstention,
                let coverage = SourceOnlyAnswerService.shared.candidateCoverageBeforeModel(
                    query: query, candidateAnswer: trimmedAnswer, retrievedChunks: retrievedChunks,
                    answerIntent: answerIntent),
                coverage < Self.sourceOnlyMinCandidateCoverage
            {
                return decline(
                    "the check would see \(Int((coverage * 100).rounded()))% of the answer, under the "
                        + "\(Int((Self.sourceOnlyMinCandidateCoverage * 100).rounded()))% floor, so it could only keep it")
            }

            Log.info(
                "[SourceOnly] Running for intent \(answerIntent) over \(retrievedChunks.count) chunk(s), "
                    + "candidate \(trimmedAnswer.count) chars",
                category: .llm
            )

            // A task of its own so `finishAnswerNow()` can end it. Cancelling a model call returns
            // at once (measured 2026-09-23: a cancelled `respond(generating:)` threw
            // `CancellationError` 0.00 s after `cancel()`), and `verifyAndRender` answers nil for
            // any thrown error, so the generated answer stands. The cancellation handler keeps the
            // composer's Stop button reaching the check as it did when this was a direct call.
            let checkStart = Date()
            let check = Task { @MainActor in
                await SourceOnlyAnswerService.shared.verifyAndRender(
                    query: query,
                    candidateAnswer: trimmedAnswer,
                    retrievedChunks: retrievedChunks,
                    answerIntent: answerIntent,
                    verificationResult: verificationResult
                )
            }
            activeSourceOnlyCheck = check
            let checked = await withTaskCancellationHandler {
                await check.value
            } onCancel: {
                check.cancel()
            }
            activeSourceOnlyCheck = nil
            let checkSeconds = String(format: "%.1f", Date().timeIntervalSince(checkStart))

            if finishAnswerNowRequested {
                return decline("the person finished the answer during the check, after \(checkSeconds)s")
            }
            guard let outcome = checked else {
                Log.info(
                    "[SourceOnly] Finished in \(checkSeconds)s with no outcome; keeping the generated answer",
                    category: .llm
                )
                return nil
            }
            Log.info(
                "[SourceOnly] Finished in \(checkSeconds)s: abstain=\(outcome.shouldAbstain), "
                    + "supported=\(outcome.supportedClaims.count), unsupported=\(outcome.unsupportedClaims.count), "
                    + "fidelity=\(String(format: "%.2f", outcome.fidelityScore)), "
                    + "coverage=\(String(format: "%.2f", outcome.candidateCoverage))",
                category: .llm
            )

            func applied(_ outcome: SourceOnlyAnswerOutcome) -> SourceOnlyAnswerOutcome {
                Log.info(
                    "[SourceOnly] Applied: the \(outcome.shouldAbstain ? "abstention" : "source-only answer") "
                        + "replaces the generated answer",
                    category: .llm
                )
                return outcome
            }

            // Keep this conservative for user-facing quality.
            // Use source-only when it strengthens a grounded lookup answer, not when it
            // downgrades a plausible answer into a brittle abstention or ultra-thin rewrite.
            // Direct source-locked extractions are already pinned to retrieved evidence.
            switch Self.sourceOnlyVerdict(
                shouldAbstain: outcome.shouldAbstain, supportedClaimCount: outcome.supportedClaims.count,
                fidelity: outcome.fidelityScore, coverage: outcome.candidateCoverage,
                preserveAbstention: preserveAbstention)
            {
            case .replace:
                return applied(outcome)
            case .keep:
                return nil
            case .keepForCoverage:
                Log.warning(
                    "[SourceOnly] Declining to replace the answer: the extraction stage saw only "
                        + "\(Int((outcome.candidateCoverage * 100).rounded()))% of it "
                        + "(floor \(Int((Self.sourceOnlyMinCandidateCoverage * 100).rounded()))%). "
                        + "Keeping the generated answer.",
                    category: .llm
                )
                return nil
            }
        }

        enum SourceOnlyVerdict: Equatable {
            case replace
            case keep
            /// Kept because the check saw too little of the answer to be allowed to replace it.
            case keepForCoverage
        }

        /// Whether the source-only outcome replaces the generated answer. The rules were inline in
        /// `sourceOnlyOutcomeIfNeeded` until 5.8 and are unchanged; they are a function now so the early exit there
        /// can be proven against them (`SourceOnlyVerdictTests`).
        ///
        /// Keep this conservative for user-facing quality. Use source-only when it strengthens a grounded lookup
        /// answer, not when it downgrades a plausible answer into a brittle abstention or ultra-thin rewrite.
        static func sourceOnlyVerdict(
            shouldAbstain: Bool, supportedClaimCount: Int, fidelity: Float, coverage: Double, preserveAbstention: Bool
        ) -> SourceOnlyVerdict {
            if shouldAbstain {
                return preserveAbstention ? .replace : .keep
            }
            guard supportedClaimCount > 0 else {
                return preserveAbstention ? .replace : .keep
            }
            guard fidelity >= 0.72 else { return .keep }

            // A verification stage that could not read its own input must decline
            // rather than overwrite. Neither guard above can see this: both
            // `supportedClaims` and `fidelityScore` are computed over whatever
            // fragment the drafter was shown, so a confident verdict about 1.5% of an
            // answer is indistinguishable from a confident verdict about all of it.
            //
            // On 2026-08-24 that is exactly what shipped: a 472-word answer that
            // Self-RAG had already accepted at 95% relevance and 80% confidence was
            // handed to this stage, which saw 50 of its 3,415 characters and returned
            // a 9-word fallback after 146.7 seconds. No inference ran after the trim.
            // The comment above already names the failure mode — "not when it
            // downgrades a plausible answer into a brittle abstention or ultra-thin
            // rewrite" — and this is the guard that makes that intent enforceable
            // rather than aspirational.
            //
            // The floor is high on purpose. This stage's output *replaces* the answer,
            // so partial input makes the replacement unsound rather than merely
            // weaker, and the generated answer it would replace has already passed
            // verification. Declining costs grounding polish; accepting costs the
            // answer.
            guard coverage >= sourceOnlyMinCandidateCoverage else { return .keepForCoverage }
            return .replace
        }

        /// Whether a Standard answer skips the source-only check because the verification gates
        /// passed it. Deep Think and Maximum never skip it here, and a Standard answer the gates
        /// failed, or never judged, still gets it. See the call site in the single-pass pipeline.
        static func standardSkipsSourceOnlyCheck(qualityMode: RAGQualityMode, gatesPassed: Bool?) -> Bool {
            qualityMode.canonical == .standard && gatesPassed == true
        }

        /// How much of the candidate answer the source-only stage must have been shown
        /// before it is allowed to replace that answer. See the guard in
        /// `sourceOnlyVerdict` for why this is strict.
        private static let sourceOnlyMinCandidateCoverage = 0.85
    #endif

    /// Repair malformed URLs in LLM output so links are tappable and correct.
    /// Fixes: spaces within URLs, missing percent-encoding, whitespace before TLDs.
    /// Preserves valid markdown links and bare URLs — only repairs, never removes.
    nonisolated func repairMalformedURLs(_ text: String) -> String {
        var result = text

        // 1. Fix markdown links [text](broken url) — repair the URL portion
        if let markdownLinkRegex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\((https?://[^\)]*)\)"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = markdownLinkRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                    let labelRange = Range(match.range(at: 1), in: result),
                    let urlRange = Range(match.range(at: 2), in: result)
                else { continue }
                let label = String(result[labelRange])
                let rawURL = String(result[urlRange])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(fullRange, with: "[\(label)](\(fixed))")
            }
        }

        // 2. Fix bare URLs (not inside markdown link parens)
        if let bareURLRegex = try? NSRegularExpression(
            pattern: #"(?<!\()https?://\S+"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = bareURLRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let rawURL = String(result[range])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(range, with: fixed)
            }
        }

        return result
    }

    /// Repair a single URL string: remove internal spaces, fix encoding.
    private nonisolated static func repairURL(_ url: String) -> String {
        var fixed = url
        // Remove spaces (LLM inserts spaces like "github .com" or "blob/ main")
        fixed = fixed.replacingOccurrences(of: " ", with: "")
        // Remove trailing punctuation the LLM may have appended
        while fixed.hasSuffix(".") || fixed.hasSuffix(",") || fixed.hasSuffix(";") || fixed.hasSuffix(")") {
            fixed = String(fixed.dropLast())
        }
        return fixed
    }

    /// Clean up response text — normalize whitespace while preserving markdown formatting
    /// Headers, bullet lists, numbered lists, code fences, and block quotes are kept intact
    /// for rendering by the block-level MarkdownText view (v1.2+)
    nonisolated func cleanupResponseText(_ text: String) -> String {
        var result = text

        // NOTE: Markdown formatting (headers, lists, code fences, block quotes) is now preserved.
        // MarkdownText renders full block-level markdown as of v1.2.
        // Only whitespace normalization and orphan cleanup remain here.

        // ═══════════════════════════════════════════════════════════════
        // PHASE 0: Intra-sentence repetition loop detection
        // ═══════════════════════════════════════════════════════════════
        // Catches degenerate LLM output like:
        //   "02/23/2024, 02/23/2024, 02/23/2024, 02/23/2024, ..."
        // where a phrase repeats >3 times consecutively within a single
        // sentence or bullet point. The sentence-level dedup in
        // compactDegenerateResponse can't catch this because it's ONE
        // long sentence, not repeated sentences.
        result = collapseIntraLineRepetition(result)

        // Remove orphaned list markers with no content (just "-" or "•" or "1." alone on a line)
        result = result.components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Remove empty bullet markers
                if trimmed == "-" || trimmed == "*" || trimmed == "•" {
                    return ""
                }
                // Remove empty numbered markers (e.g., "2." or "3)" with nothing after)
                if trimmed.range(of: #"^\d+[.)]?\s*$"#, options: .regularExpression) != nil {
                    return ""
                }
                return line
            }
            .joined(separator: "\n")

        // Collapse multiple blank lines into single
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects and collapses intra-line/intra-sentence phrase repetition loops.
    /// e.g. "02/23/2024, 02/23/2024, 02/23/2024, ..." → "02/23/2024."
    /// Works on comma-separated, space-separated, and semicolon-separated repetition.
    nonisolated func collapseIntraLineRepetition(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var changed = false

        for lineIdx in 0..<lines.count {
            let line = lines[lineIdx]
            guard line.count > 60 else { continue }  // Short lines can't have meaningful repetition

            // Strategy 1: Comma/semicolon-separated repetition
            // Split on ", " or "; " and check for dominant phrase
            for separator in [", ", "; "] {
                let parts = line.components(separatedBy: separator)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 4 else { continue }

                var freq: [String: Int] = [:]
                for part in parts {
                    let normalized = part.lowercased()
                        .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    guard !normalized.isEmpty else { continue }
                    freq[normalized, default: 0] += 1
                }

                if let (dominant, count) = freq.max(by: { $0.value < $1.value }),
                    count >= 3, Double(count) / Double(parts.count) >= 0.4
                {
                    // Find the actual (non-normalized) first occurrence
                    let firstOccurrence =
                        parts.first {
                            $0.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) == dominant
                        } ?? dominant

                    // Keep everything before the first repetition starts, then one occurrence
                    let uniqueParts = parts.filter {
                        $0.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) != dominant
                    }

                    var replacement: String
                    if uniqueParts.isEmpty {
                        // Entire line was repetition — keep just one
                        // Preserve any leading markdown/bullet prefix
                        let prefix = extractLeadingPrefix(from: line)
                        replacement = prefix + firstOccurrence + "."
                    } else {
                        // Mix of unique + repeated — keep uniques + one occurrence of repeated
                        var kept = uniqueParts
                        kept.append(firstOccurrence)
                        replacement = kept.joined(separator: separator)
                    }

                    lines[lineIdx] = replacement
                    changed = true
                    Log.info(
                        "[RepetitionFilter] Collapsed \(count)× repetition of '\(dominant.prefix(30))' on line \(lineIdx + 1)",
                        category: .llm)
                    break  // Only apply one separator strategy per line
                }
            }

            // Strategy 2: Word-level repetition (same word/token 5+ times in a row)
            // Catches: "the the the the the" or "data data data data"
            if !changed || lines[lineIdx].count > 200 {
                let words = lines[lineIdx].split(separator: " ")
                guard words.count >= 6 else { continue }

                var collapsed: [Substring] = []
                var consecutiveCount = 1

                for i in 0..<words.count {
                    if i > 0, words[i].lowercased() == words[i - 1].lowercased() {
                        consecutiveCount += 1
                    } else {
                        consecutiveCount = 1
                    }

                    if consecutiveCount <= 2 {  // Allow max 2 consecutive same words
                        collapsed.append(words[i])
                    } else if consecutiveCount == 3 {
                        // On 3rd+ repetition, don't add
                        changed = true
                    }
                }

                if changed {
                    lines[lineIdx] = collapsed.joined(separator: " ")
                    Log.info(
                        "[RepetitionFilter] Collapsed word-level repetition on line \(lineIdx + 1)", category: .llm)
                }
            }
        }

        return changed ? lines.joined(separator: "\n") : text
    }

    /// Extracts leading markdown prefix (bullet, number, header) from a line
    private nonisolated func extractLeadingPrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Match: "* ", "- ", "• ", "1. ", "### ", etc.
        if let match = trimmed.range(of: #"^(\s*(?:[*•\-]|\d+[.)]|#{1,4})\s+)"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return ""
    }

    /// Replace cryptic [S1], [S2] citations with human-readable source references
    /// e.g., [S1] → [📄 Manual.pdf, p.12] or [Source 1] if chunks unavailable
    private nonisolated func humanizeCitations(_ text: String, chunks: [RetrievedChunk]) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Match [S1], [S2], [S3], etc. (also handles [S1][S2] adjacent and [S1, S2] combined)
        // First handle combined citations like [S1, S2]
        let combinedPattern = #"\[S(\d+)(?:\s*,\s*S(\d+))*\]"#
        if let combinedRegex = try? NSRegularExpression(pattern: combinedPattern, options: []) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = combinedRegex.matches(in: result, options: [], range: nsRange)

            // Process in reverse to preserve string indices
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else { continue }
                let matchText = String(result[matchRange])

                // Extract all S-numbers from this match
                let numPattern = #"S(\d+)"#
                guard let numRegex = try? NSRegularExpression(pattern: numPattern, options: []) else { continue }
                let numMatches = numRegex.matches(
                    in: matchText, options: [], range: NSRange(matchText.startIndex..., in: matchText))

                var refs: [String] = []
                for numMatch in numMatches {
                    if let numRange = Range(numMatch.range(at: 1), in: matchText),
                        let idx = Int(matchText[numRange])
                    {
                        let chunkIndex = idx - 1  // [S1] = chunks[0]
                        if chunkIndex >= 0 && chunkIndex < chunks.count {
                            let chunk = chunks[chunkIndex]
                            let filename =
                                chunk.sourceDocument.isEmpty
                                ? "Document"
                                : URL(fileURLWithPath: chunk.sourceDocument).lastPathComponent
                            if let page = chunk.pageNumber {
                                refs.append("📄 \(filename), p.\(page)")
                            } else {
                                refs.append("📄 \(filename)")
                            }
                        } else {
                            refs.append("Source \(idx)")
                        }
                    }
                }

                if !refs.isEmpty {
                    let replacement = "[" + refs.joined(separator: "; ") + "]"
                    result.replaceSubrange(matchRange, with: replacement)
                }
            }
        }

        return result
    }

    nonisolated func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private nonisolated func isTrivialQuery(_ query: String) -> Bool {
        QueryProfileService.isTrivialQuery(query)
    }

    func buildNeighborAwareFallback(
        seeds: [RetrievedChunk],
        pool: [RetrievedChunk],
        maxTotal: Int,
        neighborsPerSeed: Int = 1
    ) -> [RetrievedChunk] {
        guard !seeds.isEmpty else { return [] }
        let limit = max(1, maxTotal)

        var byDocument: [UUID: [RetrievedChunk]] = [:]
        for chunk in pool {
            byDocument[chunk.chunk.documentId, default: []].append(chunk)
        }
        for key in byDocument.keys {
            byDocument[key]?.sort { $0.chunk.metadata.chunkIndex < $1.chunk.metadata.chunkIndex }
        }

        var selected: [RetrievedChunk] = []
        var seenIds = Set<UUID>()

        func appendIfNeeded(_ chunk: RetrievedChunk) {
            if selected.count >= limit { return }
            let chunkId = chunk.chunk.id
            if seenIds.insert(chunkId).inserted {
                selected.append(chunk)
            }
        }

        for seed in seeds {
            appendIfNeeded(seed)
            guard selected.count < limit else { break }
            guard let docChunks = byDocument[seed.chunk.documentId],
                let seedIndex = docChunks.firstIndex(where: { $0.chunk.id == seed.chunk.id })
            else {
                continue
            }

            if neighborsPerSeed > 0 {
                for offset in 1...neighborsPerSeed {
                    let prev = seedIndex - offset
                    if prev >= 0 {
                        appendIfNeeded(docChunks[prev])
                    }
                    let next = seedIndex + offset
                    if next < docChunks.count {
                        appendIfNeeded(docChunks[next])
                    }
                    if selected.count >= limit { break }
                }
            }
        }

        return selected
    }

    func mergeUniqueChunks(
        _ primary: [RetrievedChunk],
        _ secondary: [RetrievedChunk]
    ) -> [RetrievedChunk] {
        var seen = Set<UUID>()
        var merged: [RetrievedChunk] = []
        merged.reserveCapacity(primary.count + secondary.count)

        for chunk in primary + secondary {
            if seen.insert(chunk.chunk.id).inserted {
                merged.append(chunk)
            }
        }
        return merged
    }

    private func buildPrecisionLookupCandidates(
        included: [RetrievedChunk],
        ordered: [RetrievedChunk],
        desiredCount: Int
    ) -> [RetrievedChunk] {
        guard !ordered.isEmpty else { return included }

        let expandedCount = min(ordered.count, max(included.count, desiredCount))
        let expanded = Array(ordered.prefix(expandedCount))
        return mergeUniqueChunks(included, expanded)
    }

    func extractQueryTerms(_ question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but",
            "is", "are", "was", "were", "be", "being",
            "of", "to", "for", "in", "on", "at", "by",
            "this", "that", "these", "those",
            "what", "whats", "what's", "how", "why", "when", "where",
            "i", "you", "we", "they", "it", "my", "your", "our", "their",
        ]
        return
            question
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    func extractSnippet(from text: String, queryTerms: [String], maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        if maxChars <= 0 { return "" }
        if !queryTerms.isEmpty {
            for term in queryTerms {
                if let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let half = maxChars / 2
                    let start =
                        text.index(range.lowerBound, offsetBy: -half, limitedBy: text.startIndex) ?? text.startIndex
                    let end = text.index(range.upperBound, offsetBy: half, limitedBy: text.endIndex) ?? text.endIndex
                    return String(text[start..<end])
                }
            }
        }
        return String(text.prefix(maxChars))
    }

    private func buildExtractiveChunks(
        _ chunks: [RetrievedChunk],
        question: String,
        maxCharsPerChunk: Int
    ) -> [RetrievedChunk] {
        guard maxCharsPerChunk > 0 else { return chunks }
        let terms = extractQueryTerms(question)
        return chunks.map { retrieved in
            let content = extractSnippet(
                from: retrieved.chunk.content,
                queryTerms: terms,
                maxChars: maxCharsPerChunk
            )
            if content.count == retrieved.chunk.content.count {
                return retrieved
            }
            let trimmedChunk = DocumentChunk(
                id: retrieved.chunk.id,
                documentId: retrieved.chunk.documentId,
                content: content,
                parentContent: nil,
                contextualPrefix: retrieved.chunk.contextualPrefix,
                embedding: retrieved.chunk.embedding,
                metadata: retrieved.chunk.metadata
            )
            return RetrievedChunk(
                chunk: trimmedChunk,
                similarityScore: retrieved.similarityScore,
                rank: retrieved.rank,
                sourceDocument: retrieved.sourceDocument,
                pageNumber: retrieved.pageNumber
            )
        }
    }

    func resolvedDisplayResponse(
        fallback: String,
        structuredAnswer: StructuredAnswer?
    ) -> String {
        let fallbackText = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = structuredAnswer?.answer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !candidate.isEmpty else { return fallbackText }
        guard !fallbackText.isEmpty else { return candidate }

        // If the verification gates failed and the system refused to answer, return the refusal candidate.
        if let structuredAnswer, structuredAnswer.refuse {
            return candidate
        }

        // Otherwise, always prefer the fallback (raw LLM generated response) to preserve the streaming structure/layout
        return fallbackText
    }

    private nonisolated func trimIncompleteResponseTail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if Self.hasResponseTerminalBoundary(trimmed) {
            return trimmed
        }

        if Self.looksLikeStandaloneValueResponse(trimmed) {
            return trimmed
        }

        let incompleteMarkers: Set<String> = [
            "and", "or", "but", "the", "a", "an", "to", "of", "in", "for", "with", "if", "when", "because", "that",
            "which",
        ]
        let lastWord = String(trimmed.split(separator: " ").last ?? "").lowercased()
        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let lastLine = nonEmptyLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lastLineWordCount = lastLine.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let looksShortDanglingLine = lastLineWordCount > 0 && lastLineWordCount <= 6
            let looksBullet = lastLine.range(of: #"^(?:[-•*]|\d+[.)])\s+"#, options: .regularExpression) != nil

            if (looksShortDanglingLine || incompleteMarkers.contains(lastWord)) && nonEmptyLines.count > 1 {
                let droppedLastLine = nonEmptyLines.dropLast().joined(separator: "\n").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if !droppedLastLine.isEmpty && (Self.hasResponseTerminalBoundary(droppedLastLine) || !looksBullet) {
                    return droppedLastLine
                }
            }
        }

        if let boundaryIndex = Self.lastCompleteSentenceBoundary(in: trimmed) {
            let candidate = String(trimmed[...boundaryIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= max(24, trimmed.count / 3) {
                return candidate
            }
        }

        return trimmed
    }

    /// Whether `text` ends on something that reads as the end of a thought.
    ///
    /// Markdown emphasis is stripped from the tail before the test. Without that, an answer
    /// ending in bold or italic fails this check, `trimIncompleteResponseTail` concludes the
    /// model stopped mid-sentence, and `lastCompleteSentenceBoundary` truncates back to the
    /// previous `.`, amputating the closing markers and shipping unbalanced emphasis.
    ///
    /// The reproducible case was the abstention banner. `SourceOnlyAnswerService.swift:349`
    /// emits a well-formed `*(Reason: …)*`, and users and the benchmark both received it with
    /// the final `)*` missing. `finalizeResponse` is the single call site and every answer
    /// path returns through it, so this affected everything, not just the banner: on the
    /// 2026-08-09 and 2026-08-11 runs, 7 of 7 saved reason blocks had lost exactly those two
    /// characters. `CHANGELOG.md` recorded the route as "not yet identified"; this was it.
    ///
    /// Stripping rather than adding `*` to the accepted set is deliberate. `…evidence.)*`
    /// now tests as `)` and passes, `…evidence.**` tests as `.` and passes, and a genuinely
    /// truncated `…and *` still tests as `d` and is still trimmed, which is the behaviour
    /// this function exists for.
    ///
    /// Internal rather than private so `ResponseTailTrimmingTests` can pin it directly, the same
    /// reason `DeviceCapabilityService.migrateGPUExecutionProfile` is internal. Testing it through
    /// a full query would need a model, a container and an ingested corpus to assert a two
    /// character difference.
    nonisolated static func hasResponseTerminalBoundary(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.reversed().first(where: { $0 != "*" && $0 != "_" && $0 != "`" })
        else { return false }
        return [".", "!", "?", "]", ")", "}", "\"", "'"].contains(last)
    }

    private nonisolated static func looksLikeStandaloneValueResponse(_ text: String) -> Bool {
        text.range(
            of:
                #"^\s*(?:\d+(?:[.,]\d+)?(?:\s*[A-Za-z%/.-]+){0,4}|[A-Za-z][A-Za-z0-9 /_-]{0,24}:\s*\d+(?:[.,]\d+)?(?:\s*[A-Za-z%/.-]+){0,4})(?:\s*\[[^\]]+\])?\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func lastCompleteSentenceBoundary(in text: String) -> String.Index? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for index in trimmed.indices.reversed() {
            let character = trimmed[index]
            if character == "." || character == "!" || character == "?" {
                return index
            }
        }

        return nil
    }

    private func citationCount(in text: String) -> Int {
        guard let regex = Self.citationRegex else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    func highPrecisionLookupOverrideAnswer(
        question: String,
        answerIntent: AnswerIntent,
        retrievedChunks: [RetrievedChunk]
    ) async -> String? {
        await highPrecisionLookupOverride(
            question: question, answerIntent: answerIntent, retrievedChunks: retrievedChunks)?.answer
    }

    /// The direct answer an extracted value gives, and the value itself (5.7: the value, so a caller holding the
    /// model's answer can tell whether that answer already states it).
    func highPrecisionLookupOverride(
        question: String,
        answerIntent: AnswerIntent,
        retrievedChunks: [RetrievedChunk]
    ) async -> (answer: String, value: String)? {
        guard !retrievedChunks.isEmpty else { return nil }
        guard !isConceptualLookupQuery(question) else { return nil }

        // Universal behavior: if intent classification misses but the query is clearly
        // asking for a precise value/spec, still attempt extractive locking with a stricter threshold.
        let forceExtractiveAttempt = !answerIntent.isExtractiveFirst && isPrecisionValueQuery(question)
        guard answerIntent.isExtractiveFirst || forceExtractiveAttempt else { return nil }

        let candidateChunks: [RetrievedChunk]
        if EvidenceScoringPolicyService.isStateLookupQuery(question) {
            candidateChunks = prioritizedStateLookupCandidates(from: Array(retrievedChunks.prefix(18)), query: question)
        } else {
            candidateChunks = Array(retrievedChunks.prefix(18))
        }
        let extractorIntent: AnswerIntent = answerIntent.isExtractiveFirst ? answerIntent : .lookup
        let extraction = await specificationExtractor.extract(
            query: question,
            chunks: candidateChunks,
            answerIntent: extractorIntent
        )

        let confidenceThreshold = EvidenceScoringPolicyService.precisionLockThreshold(
            forceExtractiveAttempt: forceExtractiveAttempt
        )
        guard case .success(let result) = extraction,
            result.confidence >= confidenceThreshold
        else {
            return nil
        }

        // For forced attempts, only lock if the extracted span looks like a concrete
        // measurement/value (prevents accidental override for open-ended prompts).
        if forceExtractiveAttempt,
            !hasQuantitativeAnswerSignal(result.answerSpan)
        {
            return nil
        }

        // The value has to be about what was asked (5.7). Every one of the five places that let an
        // extracted value stand in for the answer comes through here.
        guard
            Self.extractedValueAnswersQuestion(
                question, label: result.matchedLabel,
                context: Self.valueLine(result.answerSpan, in: result.sourceChunk.chunk) ?? result.surroundingContext)
        else {
            Log.info(
                "[RAGService] Extracted value not used as the answer: \"\(result.matchedLabel ?? result.answerSpan)\" "
                    + "shares no subject word with the question",
                category: .pipeline)
            return nil
        }

        let answerSpan = enrichedPrecisionAnswerSpan(for: result)

        if let label = result.matchedLabel, !label.isEmpty {
            return ("\(label): \(answerSpan). \(result.citation)", result.answerSpan)
        }

        if isPrecisionValueQuery(question) || result.specificationType == "Measurement" {
            return ("\(answerSpan). \(result.citation)", result.answerSpan)
        }

        // The sentence that holds the value, whole (5.7). `formattedAnswer` used the extractor's window of
        // characters around the value, which can start mid-word and stop at the value: on 2026-10-19 it gave
        // "e harbor the crew measured 3163 units … the harbor lantern code is VERMILION-4417" for a row that goes
        // on ", kept in the blue ledger."
        if let line = Self.valueLine(result.answerSpan, in: result.sourceChunk.chunk) {
            return ("\(Self.readableValueLine(line)) \(result.citation)", result.answerSpan)
        }
        return (result.formattedAnswer, result.answerSpan)
    }

    /// Whether an answer already states a value, ignoring case and spacing (5.7).
    nonisolated static func answerStates(value: String, in answer: String) -> Bool {
        func squeezed(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }
        let wanted = squeezed(value)
        return !wanted.isEmpty && squeezed(answer).contains(wanted)
    }

    /// A table row's line as a sentence (5.7): "ROW 19: The final instruction | the code is X." reads
    /// "The final instruction: the code is X.". Other lines are returned trimmed.
    nonisolated static func readableValueLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let row = text.range(of: #"^ROW \d+:\s*"#, options: .regularExpression) {
            text.removeSubrange(row)
            if let bar = text.range(of: " | ") { text.replaceSubrange(bar, with: ": ") }
            text = text.replacingOccurrences(of: " | ", with: ", ")
        }
        return text
    }

    /// Whether an extracted value is about what the question asks (5.7, roadmap row "Regex extraction
    /// can pre-empt or replace the model's answer at five places, with no check that it answers the
    /// question").
    ///
    /// A value locked by score alone: on 2026-09-26 a probe over a car manual's capacities list
    /// locked the engine oil's 4.5 L for "What is the fuel tank capacity?" and for "How much fuel does
    /// the tank hold?", and its 4.8 US qt for "How much coolant does it need?". Now the value's label,
    /// or the line that holds it (`valueLine`), must share a word with the question's subject: its
    /// words without the ones any value question uses ("how much", "capacity", a unit, "give"), with
    /// the extractor's synonyms added (`SpecificationExtractor.subjectSynonyms`). A question with no
    /// subject words left is not checked. A value that fails is not used, and the model answers as it
    /// would without one.
    nonisolated static func extractedValueAnswersQuestion(_ question: String, label: String?, context: String) -> Bool {
        var subject = lookupWords(in: question).subtracting(genericValueWords)
        guard !subject.isEmpty else { return true }
        for (word, synonyms) in SpecificationExtractor.subjectSynonyms where subject.contains(word) {
            subject.formUnion(synonyms)
        }
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let about = lookupWords(in: trimmedLabel.isEmpty ? context : trimmedLabel)
        return !subject.isDisjoint(with: about)
    }

    /// Lowercased words of three letters or more, with a plural's final "s" dropped from a word of five
    /// letters or more ("tanks", "quarts"), so "does", "this" and "gas" stay whole, and not after "ss",
    /// "us" or "is" ("glass", "status", "analysis").
    nonisolated static func lookupWords(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }
                .map { word in
                    guard word.count >= 5, word.hasSuffix("s"),
                        !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is")
                    else { return word }
                    return String(word.dropLast())
                })
    }

    /// The sentence of a passage's line that holds an extracted value (5.7). Its label is there, as in
    /// "Fuel tank: 14.3 US gal (54 L)". The extractor's `surroundingContext` cut sentences at every ".",
    /// so it never held a value with a decimal point and fell back to 50 characters each side, which in a
    /// capacities list reached the neighbouring lines' labels. A decimal point is not a sentence end
    /// here: a sentence ends at ".", "!" or "?" followed by a space.
    nonisolated static func valueLine(_ value: String, in chunk: DocumentChunk) -> String? {
        for text in [chunk.content, chunk.parentContent].compactMap({ $0 }) {
            guard let range = text.range(of: value) else { continue }
            let start = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let end = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[start..<end])
            let sentences = line.replacingOccurrences(
                of: #"(?<=[.!?])\s+"#, with: "\n", options: .regularExpression
            ).split(separator: "\n")
            return sentences.first { $0.contains(value) }.map(String.init) ?? line
        }
        return nil
    }

    /// Words any question about a value can use, which say nothing about which value: question words,
    /// quantity words, units, function words and the verbs a question asks with ("give", "move out"
    /// keeps "move"), in the singular `lookupWords` gives.
    nonisolated static let genericValueWords: Set<String> = [
        "what", "which", "how", "much", "many", "does", "the", "for", "and", "with", "that", "this", "there",
        "need", "take", "use", "hold", "require", "have", "can", "get", "should", "must", "will", "would",
        "capacity", "size", "amount", "number", "total", "value", "level", "rating", "volume", "weight",
        "length", "height", "width", "depth", "limit", "maximum", "minimum", "max", "min", "spec",
        "specification", "type", "kind", "long", "big", "far", "often", "cost", "price",
        "day", "days", "week", "month", "year", "hour", "minute", "second", "liter", "litre", "quart", "gallon",
        "pound", "ounce", "inch", "foot", "feet", "meter", "metre", "mile", "percent",
        "are", "was", "were", "been", "has", "had", "did", "could", "may", "might", "not", "but", "out",
        "off", "over", "under", "into", "from", "about", "before", "after", "during", "between", "through",
        "these", "those", "here", "then", "than", "when", "where", "who", "why", "all", "any", "each",
        "every", "some", "only", "also", "just", "very", "your", "you", "our", "their", "they", "them",
        "his", "her", "him", "she", "its", "give", "got", "put", "make", "know", "tell", "keep", "let",
    ]

    private func prioritizedStateLookupCandidates(
        from chunks: [RetrievedChunk],
        query: String
    ) -> [RetrievedChunk] {
        chunks.sorted { lhs, rhs in
            let lhsScore = stateLookupCandidatePriority(lhs, query: query)
            let rhsScore = stateLookupCandidatePriority(rhs, query: query)
            if lhsScore == rhsScore {
                if lhs.similarityScore == rhs.similarityScore {
                    return lhs.rank < rhs.rank
                }
                return lhs.similarityScore > rhs.similarityScore
            }
            return lhsScore > rhsScore
        }
    }

    private func stateLookupCandidatePriority(_ chunk: RetrievedChunk, query: String) -> Int {
        let content = chunk.chunk.contextText.lowercased()
        var score = 0

        if EvidenceScoringPolicyService.satisfiesStateLookupAnchors(query: query, content: content) {
            score += 6
        }

        if content.contains("table:") || content.contains("[rows]") || content.contains("row 1:") {
            score += 4
        }

        if content.contains("[summary]") || content.contains("this reference table")
            || content.contains("this technical reference")
        {
            score += 2
        }

        if content.contains("[cells]") || content.contains("cell r") {
            score -= 5
        }

        if content.contains("column 1") || content.contains("column 2") {
            score -= 2
        }

        return score
    }

    private func enrichedPrecisionAnswerSpan(for result: SpecificationExtractionResult) -> String {
        let base = result.answerSpan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("(") else { return base }

        let content = result.sourceChunk.chunk.contextText
        guard let baseRange = content.range(of: base) else { return base }

        let suffix = String(content[baseRange.upperBound...].prefix(40))
        guard
            let equivalentRange = suffix.range(
                of:
                    #"^\s*\(\s*\d+(?:[.,]\d+)?\s*(?:L|l|liter|liters|litre|litres|gal|gallon|gallons|qt|quart|quarts|ml|mL)\s*\)"#,
                options: [.regularExpression, .caseInsensitive]
            )
        else {
            return base
        }

        let equivalent = String(suffix[equivalentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base) \(equivalent)"
    }

    func shouldFallbackAgenticPrecisionQuery(error: Error, question: String) -> Bool {
        guard isPrecisionValueQuery(question) else { return false }
        if error is CancellationError { return false }

        if let llmError = error as? LLMError {
            switch llmError {
            case .modelUnavailable, .rateLimited, .concurrentRequests, .generationFailed:
                return true
            default:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        let indicators = [
            "foundationmodels.languagemodelsession.generationerror",
            "generationerror",
            "apple intelligence",
            "physical device",
            "model unavailable",
            "concurrent request",
            "rate-limited",
            "temporarily rate-limited",
        ]
        return indicators.contains { description.contains($0) }
    }

    /// Detects lookup questions that are really asking for a conceptual explanation,
    /// even when they contain values like “4,096” that might otherwise look extractive.
    nonisolated func isConceptualLookupQuery(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        let normalized = lower.trimmingCharacters(in: .punctuationCharacters)
        let conceptualOpeners = [
            "what is ", "what are ", "what's ", "how does ", "how do ",
            "why is ", "why does ", "explain ", "tell me about ", "walk me through ",
        ]
        let hasConceptualOpener = conceptualOpeners.contains { normalized.hasPrefix($0) }
        guard hasConceptualOpener else { return false }

        let conceptualMarkers = [
            "token limit", "context window", "private cloud compute", "apple intelligence",
            "foundation model", "hybrid search", "rag pipeline", "retrieval augmented generation",
            "retrieval-augmented generation", "architecture", "workflow", "quality mode",
            "on-device", "on device", "citation", "source card", "file format", "supported format",
            "document import", "sample workspace", "grounded answer", "grounded response", "4,096", "4096",
        ]
        guard conceptualMarkers.contains(where: { normalized.contains($0) }) else { return false }

        let strongValueMarkers = [
            "capacity", "size", "amount", "value", "rating", "weight", "length", "width", "height",
            "volume", "pressure", "temperature", "speed", "torque", "power", "voltage", "current",
            "frequency", "dose", "dosage", "price", "cost", "part number", "model number", "serial number",
            "catalog number", "item number", "product code", "sku",
        ]
        guard !strongValueMarkers.contains(where: { normalized.contains($0) }) else { return false }

        return true
    }

    /// Detects queries that ask for a concrete numeric/measurement value.
    /// This is domain-agnostic and intentionally conservative.
    nonisolated func isPrecisionValueQuery(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        guard !isConceptualLookupQuery(lower) else { return false }

        let strongNumericIntentMarkers = [
            "how many", "how much", "give me the", "exact", "spec", "specification",
        ]
        let weakNumericIntentMarkers = ["what is", "what's"]
        let strongValueMarkers = [
            "capacity", "size", "amount", "value", "rating", "weight", "length", "width", "height",
            "volume", "pressure", "temperature", "speed", "torque", "power", "voltage", "current", "frequency",
            "dose", "dosage", "price", "cost", "count", "number", "total", "date", "deadline", "fee",
            "part number", "model number", "serial number", "catalog number", "item number", "product code", "sku",
        ]
        let ambiguousValueMarkers = [
            "limit", "range", "setting", "mode", "level", "interval", "threshold",
        ]

        let hasStrongNumericIntent = strongNumericIntentMarkers.contains { lower.contains($0) }
        let hasWeakNumericIntent = weakNumericIntentMarkers.contains { lower.contains($0) }
        let hasStrongValueTarget = strongValueMarkers.contains { lower.contains($0) }
        let hasAmbiguousValueTarget = ambiguousValueMarkers.contains { lower.contains($0) }

        // Unit-like tokens in the question are a strong indicator of precision lookup.
        let unitPattern =
            #"\b(?:gal(?:lon)?s?|l(?:iter)?s?|ml|kg|g|lb?s?|oz|mm|cm|m|km|mi|mph|km/h|psi|kpa|bar|v|a|w|kw|hz|mhz|ghz|°c|°f|%)\b"#
        let hasUnits = lower.range(of: unitPattern, options: .regularExpression) != nil

        if hasStrongNumericIntent && (hasStrongValueTarget || hasAmbiguousValueTarget || hasUnits) {
            return true
        }

        if hasWeakNumericIntent && (hasStrongValueTarget || hasUnits) {
            return true
        }

        return false
    }

    /// Ensures we only force-lock answers that contain concrete values.
    private nonisolated func hasQuantitativeAnswerSignal(_ text: String) -> Bool {
        EvidenceScoringPolicyService.hasQuantitativeSignal(text)
    }

    func buildEvidencePackContext(
        question: String,
        candidates: [RetrievedChunk],
        maxContextChars: Int,
        maxChunks: Int,
        maxCharsPerChunk: Int? = nil
    ) async -> (context: String, usedChunks: [RetrievedChunk]) {
        guard !candidates.isEmpty else { return ("", []) }

        var seen = Set<UUID>()
        let deduped = candidates.filter { seen.insert($0.chunk.id).inserted }
        let limited = Array(deduped.prefix(max(1, min(maxChunks, deduped.count))))
        let perChunk =
            maxCharsPerChunk
            ?? max(220, min(900, maxContextChars / max(1, limited.count)))

        let trimmed = buildExtractiveChunks(
            limited,
            question: question,
            maxCharsPerChunk: perChunk
        )

        let engine = RAGEngine.shared
        let assembled = await engine.assembleContext(
            chunks: trimmed,
            maxChars: maxContextChars,
            compact: true
        )
        // `assembled.sources`, not `trimmed.prefix(assembled.used)`: labels are numbered after
        // Lost-in-the-Middle reordering, so a prefix of the input array is a different set.
        return (assembled.context, assembled.sources)
    }

    func shouldAttemptCorrectiveRetrieval(
        query: String,
        candidates: [RetrievedChunk],
        answerIntentIsExtractive: Bool,
        targetCount: Int
    ) -> Bool {
        if answerIntentIsExtractive {
            return true
        }

        let lexical = checkLexicalRelevance(query: query, chunks: Array(candidates.prefix(5)))
        let topSimilarity = candidates.first?.similarityScore ?? 0
        let minimumCandidateCount = max(3, min(targetCount, 5))

        return candidates.count < minimumCandidateCount
            || lexical < 0.45
            || topSimilarity < 0.52
    }

    private func buildCorrectiveRetrievalQueries(from question: String) -> [String] {
        var seen = Set<String>()
        let orderedTerms = extractQueryTerms(question).filter { seen.insert($0).inserted }

        var queries: [String] = [question]
        if !orderedTerms.isEmpty {
            queries.append(orderedTerms.prefix(4).joined(separator: " "))
        }
        if orderedTerms.count >= 2 {
            queries.append(orderedTerms.prefix(2).joined(separator: " "))
        }
        if orderedTerms.count >= 3 {
            queries.append(Array(orderedTerms.suffix(3)).joined(separator: " "))
        }

        var dedupedSeen = Set<String>()
        return
            queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && dedupedSeen.insert($0).inserted }
    }

    private nonisolated static func isStateLookupQuery(_ query: String) -> Bool {
        EvidenceScoringPolicyService.isStateLookupQuery(query)
    }

    private nonisolated static func isDefinitionStyleLookupQuery(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        let normalized = lower.trimmingCharacters(in: .punctuationCharacters)
        let definitionPatterns = [
            "what is ", "what are ", "what's ", "define ",
            "definition of ", "meaning of ", "what does ",
        ]
        let hasDefinitionCue =
            definitionPatterns.contains { normalized.hasPrefix($0) }
            || normalized.contains(" definition of ")
            || normalized.contains(" meaning of ")

        guard hasDefinitionCue else { return false }

        let exactValueSignals = [
            "capacity", "spec", "specification", "torque", "pressure", "temperature", "speed",
            "voltage", "current", "frequency", "power", "weight", "height", "width", "length",
            "dimensions", "size", "setting", "mode", "level", "schedule", "interval", "dose",
            "dosage", "reference number", "part number", "model number", "serial number",
            "catalog number", "item number", "product code", "sku", "recommended", "maximum", "minimum",
        ]
        if exactValueSignals.contains(where: { normalized.contains($0) }) {
            return false
        }

        let numericUnitPattern =
            #"\b\d+(?:[.,]\d+)?\s*(?:%|mg|g|kg|mcg|ug|ml|l|qt|gal|mm|cm|m|km|in|ft|psi|kpa|bar|v|a|w|kw|hz|mhz|ghz|°c|°f)\b"#
        if normalized.range(of: numericUnitPattern, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    private nonisolated func isStandardEquivalentQualityMode(_ qualityMode: RAGQualityMode) -> Bool {
        switch qualityMode {
        case .standard, .balanced, .fast, .thorough:
            return true
        case .deepThink, .agentic, .maximum:
            return false
        }
    }

    nonisolated func shouldUseContextualDefinitionLookupMode(
        query: String,
        answerIntent: AnswerIntent,
        qualityMode: RAGQualityMode,
        hasSummaryChunks: Bool
    ) -> Bool {
        guard isStandardEquivalentQualityMode(qualityMode) else { return false }
        guard answerIntent == .lookup else { return false }
        guard hasSummaryChunks else { return false }
        if isConceptualLookupQuery(query) { return true }
        guard !isPrecisionValueQuery(query) else { return false }
        return Self.isDefinitionStyleLookupQuery(query)
    }

    func looksTableLike(text: String, structureType: String?) -> Bool {
        EvidenceScoringPolicyService.isStructuredEvidence(text: text, structureType: structureType)
    }

    private func correctiveRetrievalScore(
        content: String,
        queryTerms: [String],
        structureType: String?,
        baseScore: Float
    ) -> Float {
        EvidenceScoringPolicyService.correctiveRetrievalScore(
            content: content,
            queryTerms: queryTerms,
            structureType: structureType,
            baseScore: baseScore
        )
    }

    func performCorrectiveRetrieval(
        query: String,
        containerId: UUID,
        allChunks: [DocumentChunk]?,
        existingCandidates: [RetrievedChunk],
        answerIntent: AnswerIntent,
        targetCount: Int
    ) async -> [RetrievedChunk] {
        var seenTerms = Set<String>()
        let queryTerms = extractQueryTerms(query).filter { seenTerms.insert($0).inserted }
        guard !queryTerms.isEmpty else { return [] }

        let queryVariants = buildCorrectiveRetrievalQueries(from: query)
        let useStateAnchorGuard = Self.isStateLookupQuery(query)
        let useStructuredRowRescue = answerIntent.isExtractiveFirst || isPrecisionValueQuery(query)
        let chunkLookup: [String: DocumentChunk] = {
            guard let allChunks else { return [:] }
            var lookup: [String: DocumentChunk] = [:]
            lookup.reserveCapacity(allChunks.count)
            for chunk in allChunks {
                lookup["\(chunk.documentId.uuidString)_\(chunk.metadata.chunkIndex)"] = chunk
            }
            return lookup
        }()

        var seenChunkIds = Set(existingCandidates.map { $0.chunk.id })
        var seenPageKeys = Set(
            existingCandidates.compactMap { candidate -> String? in
                guard let pageNumber = candidate.pageNumber else { return nil }
                return "\(candidate.chunk.documentId.uuidString)_page_\(pageNumber)"
            })
        var scoredHits: [(chunk: RetrievedChunk, score: Float, structured: Bool)] = []

        for variant in queryVariants {
            let chunkHits = await SQLiteFullTextService.shared.searchChunks(
                query: variant,
                containerId: containerId,
                limit: max(6, targetCount * 2)
            )

            for hit in chunkHits {
                let lookupKey = "\(hit.documentId.uuidString)_\(hit.chunkIndex)"
                guard let docChunk = chunkLookup[lookupKey], !seenChunkIds.contains(docChunk.id) else { continue }

                var score = correctiveRetrievalScore(
                    content: docChunk.content,
                    queryTerms: queryTerms,
                    structureType: docChunk.metadata.structureType,
                    baseScore: 0.50
                )
                if useStateAnchorGuard {
                    score += EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                        query: query,
                        content: docChunk.content,
                        structureType: docChunk.metadata.structureType
                    )
                }
                guard score >= 0.48 else { continue }

                let docName = await documentName(for: docChunk.documentId)
                let retrieved = RetrievedChunk(
                    chunk: docChunk,
                    similarityScore: score,
                    rank: scoredHits.count,
                    sourceDocument: docName,
                    pageNumber: docChunk.metadata.pageNumber
                )
                scoredHits.append(
                    (
                        chunk: retrieved,
                        score: score,
                        structured: looksTableLike(
                            text: docChunk.content, structureType: docChunk.metadata.structureType)
                    ))
                seenChunkIds.insert(docChunk.id)
            }

            let pageHits = await SQLiteFullTextService.shared.searchPages(
                query: variant,
                containerId: containerId,
                limit: max(4, targetCount)
            )

            for hit in pageHits {
                let pageKey = "\(hit.documentId.uuidString)_page_\(hit.pageNumber)"
                guard seenPageKeys.insert(pageKey).inserted else { continue }

                let snippet = extractSnippet(
                    from: hit.content,
                    queryTerms: queryTerms,
                    maxChars: 1200
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !snippet.isEmpty else { continue }

                let structureType = looksTableLike(text: hit.content, structureType: nil) ? "table" : nil
                var score = correctiveRetrievalScore(
                    content: snippet,
                    queryTerms: queryTerms,
                    structureType: structureType,
                    baseScore: 0.56
                )
                if useStateAnchorGuard {
                    score += EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                        query: query,
                        content: snippet,
                        structureType: structureType
                    )
                }
                guard score >= 0.50 else { continue }

                let syntheticChunk = DocumentChunk(
                    documentId: hit.documentId,
                    content: snippet,
                    parentContent: nil,
                    contextualPrefix: nil,
                    embedding: [],
                    metadata: ChunkMetadata(
                        chunkIndex: max(0, hit.pageNumber * 1000),
                        pageNumber: hit.pageNumber,
                        keywords: queryTerms,
                        hasNumericData: snippet.rangeOfCharacter(from: .decimalDigits) != nil,
                        wordCount: wordCount(of: snippet),
                        characterCount: snippet.count,
                        structureType: structureType
                    )
                )

                let docName = await documentName(for: hit.documentId)
                let retrieved = RetrievedChunk(
                    chunk: syntheticChunk,
                    similarityScore: score,
                    rank: scoredHits.count,
                    sourceDocument: docName,
                    pageNumber: hit.pageNumber
                )
                scoredHits.append(
                    (
                        chunk: retrieved,
                        score: score,
                        structured: structureType == "table"
                    ))
            }
        }

        if useStructuredRowRescue {
            let rowHits = await SQLiteFullTextService.shared.searchStructuredRows(
                query: query,
                containerId: containerId,
                limit: max(6, targetCount * 2)
            )

            for hit in rowHits {
                if useStateAnchorGuard,
                    !EvidenceScoringPolicyService.satisfiesStateLookupAnchors(query: query, content: hit.content)
                {
                    continue
                }

                let lookupKey = "\(hit.documentId.uuidString)_\(hit.chunkIndex)"
                let contentForScore = hit.content.isEmpty ? (chunkLookup[lookupKey]?.content ?? "") : hit.content
                var score = correctiveRetrievalScore(
                    content: contentForScore,
                    queryTerms: queryTerms,
                    structureType: "table",
                    baseScore: 0.64
                )
                if useStateAnchorGuard {
                    score += EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                        query: query,
                        content: contentForScore,
                        structureType: "table"
                    )
                }
                guard score >= 0.56 else { continue }

                let docName = await documentName(for: hit.documentId)

                if let docChunk = chunkLookup[lookupKey] {
                    guard !seenChunkIds.contains(docChunk.id) else { continue }

                    let retrieved = RetrievedChunk(
                        chunk: docChunk,
                        similarityScore: score,
                        rank: scoredHits.count,
                        sourceDocument: docName,
                        pageNumber: docChunk.metadata.pageNumber
                    )
                    scoredHits.append((chunk: retrieved, score: score, structured: true))
                    seenChunkIds.insert(docChunk.id)
                } else {
                    let syntheticChunk = DocumentChunk(
                        documentId: hit.documentId,
                        content: hit.content,
                        parentContent: nil,
                        contextualPrefix: nil,
                        embedding: [],
                        metadata: ChunkMetadata(
                            chunkIndex: hit.chunkIndex,
                            pageNumber: hit.pageNumber,
                            keywords: queryTerms,
                            hasNumericData: hit.content.rangeOfCharacter(from: .decimalDigits) != nil,
                            wordCount: wordCount(of: hit.content),
                            characterCount: hit.content.count,
                            structureType: "table"
                        )
                    )

                    let retrieved = RetrievedChunk(
                        chunk: syntheticChunk,
                        similarityScore: score,
                        rank: scoredHits.count,
                        sourceDocument: docName,
                        pageNumber: hit.pageNumber
                    )
                    scoredHits.append((chunk: retrieved, score: score, structured: true))
                }
            }
        }

        scoredHits.sort {
            if abs($0.score - $1.score) < 0.01 {
                return $0.structured && !$1.structured
            }
            return $0.score > $1.score
        }

        let limited = scoredHits.prefix(max(targetCount, 6))
        return limited.enumerated().map { index, entry in
            RetrievedChunk(
                chunk: entry.chunk.chunk,
                similarityScore: entry.score,
                rank: index,
                sourceDocument: entry.chunk.sourceDocument,
                pageNumber: entry.chunk.pageNumber
            )
        }
    }

    /// Guarantee that at least a subset of the retrieved chunks span multiple documents when available.
    func ensureDocumentCoverage(
        candidates: [RetrievedChunk],
        fallbackPool: [RetrievedChunk],
        desiredDocuments: Int,
        maxCandidates: Int
    ) -> (chunks: [RetrievedChunk], addedDocuments: Int) {
        let limit = max(1, maxCandidates)
        if desiredDocuments <= 1 {
            let baseline = candidates.isEmpty ? fallbackPool : candidates
            return (Array(baseline.prefix(limit)), 0)
        }

        var augmented = candidates
        if augmented.count > limit {
            augmented = Array(augmented.prefix(limit))
        }

        var seenDocuments = Set(augmented.map { $0.chunk.documentId })
        var addedDocs = 0

        for candidate in fallbackPool {
            if augmented.count >= limit { break }
            let docId = candidate.chunk.documentId
            if seenDocuments.contains(docId) { continue }
            augmented.append(candidate)
            seenDocuments.insert(docId)
            addedDocs += 1
            if seenDocuments.count >= desiredDocuments { break }
        }

        if augmented.isEmpty {
            let fallback = Array(fallbackPool.prefix(limit))
            let coveredDocs = Set(fallback.map { $0.chunk.documentId }).count
            return (fallback, min(desiredDocuments, coveredDocs))
        }

        return (augmented, addedDocs)
    }

}

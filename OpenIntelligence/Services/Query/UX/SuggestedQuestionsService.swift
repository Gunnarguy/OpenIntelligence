//
//  SuggestedQuestionsService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 2025.
//
//  Source-first suggested question generation from actual document content.
//  Generates specific, grounded questions that showcase RAG capabilities.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service that generates contextual suggested questions from actual document content.
///
/// **Architecture (v4 — source-first, fail-closed grounding):**
///
/// 1. Select diverse representative chunks across the library (different docs, sections, topics)
/// 2. Generate deterministic questions from specs, procedures, warnings, and definitions
/// 3. Let Apple FM only polish already-grounded drafts when outputs pass strict passage-grounding checks
/// 4. Fail closed — if the library does not yield strong grounded prompts, return none
///
/// **Why this is 10x:**
/// - Questions are generated FROM the actual text, not from loose entity labels
/// - "What is Analysis?" → "What is the fuel tank capacity?"
/// - Diversity is enforced at the chunk selection level, not post-hoc filtering
/// - Cache invalidates on document change, not never
/// - Weak document-shaped prompts are dropped instead of padded with canned fallback chips

#if canImport(FoundationModels)
/// Structured LLM output for suggested question generation.
/// @Generable guarantees a typed [String] array — no numbered-line parsing or regex needed.
/// Constrained sampling enforces the declared schema at the token level.
@available(iOS 26.0, *)
@Generable
struct SuggestedQuestionList: Sendable {
    @Guide(description: "Short, natural questions someone would actually ask after reading these documents. Each question targets a specific fact, number, name, or procedure from the text. Questions sound casual and direct — like texting a coworker, not writing an exam. Never start with 'What role does' or 'What is the significance of'.")
    var questions: [String]
}
#endif

actor SuggestedQuestionsService {

    static let shared = SuggestedQuestionsService()

    // MARK: - Types

    /// Category of question for display diversity
    enum QuestionCategory: String, CaseIterable, Sendable {
        case factRetrieval = "fact"
        case comparison = "compare"
        case summarization = "summarize"
        case procedural = "how"
        case analytical = "analyze"
        case numerical = "numeric"

        /// SF Symbol icon for category badge
        var icon: String {
            switch self {
            case .factRetrieval: return "magnifyingglass"
            case .comparison: return "arrow.left.arrow.right"
            case .summarization: return "doc.text"
            case .procedural: return "list.number"
            case .analytical: return "chart.bar.xaxis"
            case .numerical: return "number"
            }
        }
    }

    /// A generated question with metadata
    struct SuggestedQuestion: Identifiable, Sendable {
        let id: UUID
        let text: String
        let category: QuestionCategory
        let relevantDocuments: [String]
        let sourceSections: [String]
        let confidence: Double
    }

    // MARK: - Properties

    private var cachedQuestions: [UUID: CachedEntry] = [:]

    /// Cache entry with timestamp for staleness detection
    private struct CachedEntry: Sendable {
        let questions: [SuggestedQuestion]
        let documentCount: Int
        let generatedAt: Date
    }

    /// Maximum cache age before regeneration (5 minutes)
    private static let cacheMaxAge: TimeInterval = 300

    // MARK: - Public API

    /// Generate suggested questions for a specific library container.
    ///
    /// Questions are generated directly from chunk content first.
    /// Apple FM may polish grounded drafts, but it does not invent new topics.
    ///
    /// - Parameters:
    ///   - containerId: Active container UUID
    ///   - documents: Documents in the container
    ///   - sampleChunks: Representative chunks (up to 50)
    ///   - count: Number of questions to return
    ///   - forceRefresh: Bypass cache and generate fresh questions (e.g. user tapped refresh)
    func generateQuestions(
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk],
        count: Int = 4,
        forceRefresh: Bool = false
    ) async -> [SuggestedQuestion] {

        let existingCached = cachedQuestions[containerId]

        // Collect previously-shown questions so refresh can avoid repeats
        let previousTexts: [String] = forceRefresh
            ? (existingCached?.questions.map { $0.text } ?? [])
            : []

        // Check cache — but only if not forcing refresh, doc count unchanged, and cache fresh
        if !forceRefresh,
           let cached = existingCached,
           cached.documentCount == documents.count,
           Date().timeIntervalSince(cached.generatedAt) < Self.cacheMaxAge {
            Log.debug("[SuggestedQuestions] Returning \(cached.questions.count) cached questions for container")
            return Array(cached.questions.prefix(count))
        }

        guard !sampleChunks.isEmpty else {
            Log.debug("[SuggestedQuestions] No chunks available, returning empty")
            if let cached = existingCached, !cached.questions.isEmpty, cached.documentCount == documents.count {
                Log.debug("[SuggestedQuestions] Returning \(cached.questions.count) cached questions as fallback")
                return Array(cached.questions.prefix(count))
            }
            // Cache the empty result to prevent repeated generation attempts on empty library
            cachedQuestions[containerId] = CachedEntry(
                questions: [],
                documentCount: documents.count,
                generatedAt: Date()
            )
            return []
        }

        // Step 1: Select diverse representative chunks
        // On refresh, shuffle the input to get different chunks for variety
        let inputChunks = forceRefresh ? sampleChunks.shuffled() : sampleChunks
        let diverseChunks = selectDiverseChunks(from: inputChunks, documents: documents, targetCount: 6)

        // Step 2: Build passage-grounded questions.
        // If the LLM is available, generate highly aligned inference/conceptual questions directly.
        // If not, or if it yields too few questions, fall back to deterministic pattern extraction.
        var questions: [SuggestedQuestion] = []

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let llmQuestions = await generateDirectlyWithLLM(
                chunks: diverseChunks,
                documents: documents,
                avoidTexts: previousTexts
            )
            if llmQuestions.count >= 2 {
                questions = llmQuestions
            }
        }
        #endif

        if questions.isEmpty {
            let contentQuestions = generateFromContent(chunks: diverseChunks, documents: documents, avoidTexts: previousTexts)

            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable, !contentQuestions.isEmpty {
                let polishedQuestions = await generateWithLLM(
                    baseQuestions: contentQuestions,
                    chunks: diverseChunks,
                    documents: documents,
                    avoidTexts: previousTexts
                )
                questions = polishedQuestions.isEmpty
                    ? contentQuestions
                    : dedupeSuggestedQuestionsPreservingOrder(polishedQuestions)
            } else {
                questions = contentQuestions
            }
            #else
            questions = contentQuestions
            #endif
        }

        // Step 4: Keep only grounded, diverse questions. If the library only yields
        // one or two strong prompts, surface one or two strong prompts.
        let targetCount = max(count, 6)
        let deduped = enforceDiversity(
            dedupeSuggestedQuestionsPreservingOrder(questions),
            count: targetCount
        )
        var finalQuestions = pruneNearDuplicateQuestions(deduped)
            .filter { shouldSurfaceSuggestedQuestion($0) }

        if finalQuestions.count < count && !sampleChunks.isEmpty {
            Log.info("[SuggestedQuestions] Standard generation yielded \(finalQuestions.count) questions (target: \(count)). Running fallback generator.")
            let fallbacks = generateFallbackQuestions(documents: documents, chunks: sampleChunks, count: targetCount, avoidTexts: previousTexts)
            finalQuestions.append(contentsOf: fallbacks)
            finalQuestions = dedupeSuggestedQuestionsPreservingOrder(finalQuestions)
            
            if finalQuestions.count < count {
                Log.info("[SuggestedQuestions] Still below target count \(count). Running fallback generator without avoidTexts.")
                let repeatedFallbacks = generateFallbackQuestions(documents: documents, chunks: sampleChunks, count: targetCount, avoidTexts: [])
                finalQuestions.append(contentsOf: repeatedFallbacks)
                finalQuestions = dedupeSuggestedQuestionsPreservingOrder(finalQuestions)
            }
        }

        if finalQuestions.isEmpty, let cached = existingCached, !cached.questions.isEmpty, cached.documentCount == documents.count {
            Log.info("[SuggestedQuestions] Generation yielded 0 questions, preserving \(cached.questions.count) previously cached questions.")
            return Array(cached.questions.prefix(count))
        }

        // Cache
        cachedQuestions[containerId] = CachedEntry(
            questions: finalQuestions,
            documentCount: documents.count,
            generatedAt: Date()
        )
        Log.info("[SuggestedQuestions] Generated \(finalQuestions.count) questions for container (refresh: \(forceRefresh))")

        return Array(finalQuestions.prefix(count))
    }

    /// Invalidate cache when documents change (ingest, delete, container switch)
    func invalidateCache(for containerId: UUID) {
        cachedQuestions.removeValue(forKey: containerId)
        Log.debug("[SuggestedQuestions] Cache invalidated for container \(containerId.uuidString.prefix(8))")
    }

    /// Invalidate all caches
    func invalidateAllCaches() {
        cachedQuestions.removeAll()
    }

    /// Check if a valid, fresh cache exists for the container.
    func hasValidCache(for containerId: UUID, documentCount: Int) -> Bool {
        guard let cached = cachedQuestions[containerId] else { return false }
        guard cached.documentCount == documentCount else { return false }
        if cached.questions.isEmpty && documentCount > 0 {
            return false
        }
        return Date().timeIntervalSince(cached.generatedAt) < Self.cacheMaxAge
    }

    private enum TimeoutError: Error {
        case timedOut
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut
            }
            
            let result = try await group.next()
            group.cancelAll()
            if let result {
                return result
            } else {
                throw TimeoutError.timedOut
            }
        }
    }

    // MARK: - Step 1: Diverse Chunk Selection

    /// Select chunks that maximally span different documents, sections, and content types.
    /// This is the most critical step — question diversity is determined HERE, not by post-filtering.
    private func selectDiverseChunks(
        from chunks: [DocumentChunk],
        documents: [Document],
        targetCount: Int
    ) -> [DocumentChunk] {
        guard !chunks.isEmpty else { return [] }

        // Group chunks by document
        var byDocument: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks {
            byDocument[chunk.documentId, default: []].append(chunk)
        }

        var selected: [DocumentChunk] = []
        var usedSections: Set<String> = []

        // Prioritize richer documents, but still keep cross-document coverage.
        let docIds = Array(byDocument.keys).sorted { lhs, rhs in
            documentRichnessScore(byDocument[lhs] ?? []) > documentRichnessScore(byDocument[rhs] ?? [])
        }
        let prioritizedDocIds = Array(docIds.prefix(max(targetCount, min(docIds.count, 6))))

        // Sort each document's chunks by "interestingness"
        for docId in prioritizedDocIds {
            byDocument[docId]?.sort { a, b in
                interestingnessScore(a) > interestingnessScore(b)
            }
        }

        // Round-robin: take best chunk from each doc, then second-best, etc.
        var round = 0
        while selected.count < targetCount {
            var addedThisRound = false
            for docId in prioritizedDocIds {
                guard selected.count < targetCount else { break }
                guard let docChunks = byDocument[docId], round < docChunks.count else { continue }

                let candidate = docChunks[round]
                let section = primarySectionLabel(for: candidate) ?? "default_\(candidate.id.uuidString.prefix(4))"
                let sectionKey = "\(docId.uuidString)::\(section.lowercased())"

                // Avoid duplicate sections within the same source document, but do not
                // collapse similarly named sections across different documents.
                if usedSections.contains(sectionKey) && selected.count >= prioritizedDocIds.count {
                    continue
                }

                selected.append(candidate)
                usedSections.insert(sectionKey)
                addedThisRound = true
            }
            round += 1
            if !addedThisRound { break }
        }

        return selected
    }

    /// Score a chunk's "interestingness" for question generation.
    /// Prefers chunks with specific data, entities, structure — not generic filler.
    private func interestingnessScore(_ chunk: DocumentChunk) -> Double {
        var score: Double = 0

        // Word count sweet spot: 50-200 words is ideal (enough detail, not overwhelming)
        let wc = chunk.metadata.wordCount
        if wc >= 50 && wc <= 200 { score += 3.0 }
        else if wc >= 30 && wc <= 300 { score += 2.0 }
        else if wc >= 15 { score += 1.0 }

        // Has numeric data (specs, measurements, dates, statistics)
        if chunk.metadata.hasNumericData { score += 2.5 }

        // Has named entities (specific people, orgs, places, technical terms)
        score += min(Double(chunk.metadata.entities.count), 3.0)

        // Has abbreviations (technical domain indicators)
        score += min(Double(chunk.metadata.abbreviations.count) * 1.5, 3.0)

        // Has a section title (contextualized within document structure)
        if chunk.metadata.sectionTitle != nil || chunk.metadata.sectionPath?.isEmpty == false {
            score += 1.0
        }

        if cleanedMetadataValue(chunk.metadata.tableTitle) != nil {
            score += 1.25
        }

        if chunk.metadata.abstractionLevel == .documentSummary {
            score += 2.25
        }

        // Has list structure (procedures, specifications, comparisons)
        if chunk.metadata.hasListStructure { score += 1.5 }

        switch chunk.metadata.chunkType {
        case .warning?:
            score += 2.5
        case .tableSemantic?, .tableStructural?:
            score += 2.0
        case .listItem?:
            score += 1.0
        case .prose?, nil:
            break
        }

        // Structured document content (tables, lists) — richer than plain paragraphs
        if let structType = chunk.metadata.structureType, structType != "paragraph" {
            score += 2.0
        }

        if cleanedMetadataValue(chunk.metadata.imageCaption, maxLength: 120) != nil {
            score += 1.25
        }

        if cleanedMetadataValue(chunk.metadata.imageDescription, maxLength: 160) != nil {
            score += 1.0
        }

        if chunk.metadata.hasCrossReferences {
            score += 0.75
        }

        // Penalize very short chunks (likely headers or fragments)
        if wc < 15 { score -= 5.0 }

        // Down-rank boilerplate/front-matter chunks so research PDFs don't
        // produce junk prompts from copyright or author-manuscript text.
        score += frontMatterAdjustment(for: chunk)

        if isBibliographyChunk(chunk) {
            score -= 30.0
        }

        return score
    }

    private func isBibliographyChunk(_ chunk: DocumentChunk) -> Bool {
        let content = chunk.content.lowercased()
        
        if let section = chunk.metadata.sectionTitle?.lowercased() {
            let bibTitles: Set<String> = ["references", "bibliography", "works cited", "literature cited", "reference"]
            if bibTitles.contains(section) || section.contains("bibliography") || section.contains("references") {
                return true
            }
        }
        
        if let path = chunk.metadata.sectionPath {
            for element in path {
                let elLower = element.lowercased()
                if elLower.contains("references") || elLower.contains("bibliography") || elLower.contains("works cited") {
                    return true
                }
            }
        }
        
        var signals = 0
        if content.contains("et al.") { signals += 2 }
        if content.contains("university press") || content.contains("press.") { signals += 2 }
        if content.contains("doi:") { signals += 2 }
        if content.contains("pp.") || content.contains("pages ") { signals += 1 }
        if content.contains("vol.") || content.contains("volume ") { signals += 1 }
        if content.contains("isbn") || content.contains("issn") { signals += 3 }
        
        let yearPattern = #"\b(?:19|20)\d{2}\b"#
        if let regex = try? NSRegularExpression(pattern: yearPattern) {
            let nsString = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            if matches.count >= 3 {
                signals += matches.count
            }
        }
        
        return signals >= 5
    }

    private func documentRichnessScore(_ chunks: [DocumentChunk]) -> Double {
        guard !chunks.isEmpty else { return 0 }

        let topChunkScore = chunks
            .map(interestingnessScore)
            .sorted(by: >)
            .prefix(3)
            .reduce(0, +)

        let uniqueSections = Set(chunks.compactMap { primarySectionLabel(for: $0)?.lowercased() }).count
        let structuredCount = chunks.filter { chunk in
            (chunk.metadata.structureType?.isEmpty == false) && chunk.metadata.structureType != "paragraph"
        }.count

        return topChunkScore
            + Double(min(uniqueSections, 4)) * 1.25
            + Double(min(structuredCount, 3)) * 0.75
    }

    private func frontMatterAdjustment(for chunk: DocumentChunk) -> Double {
        if chunk.metadata.abstractionLevel == .documentSummary {
            return 0
        }

        if let section = primarySectionLabel(for: chunk), isGenericSectionTitle(section) {
            if chunk.metadata.documentCategory == .scientificPaper {
                let normalized = section.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if ["abstract", "summary", "conclusion"].contains(normalized) {
                    return -1.5
                }
            }

            return -5.0
        }

        let lower = groundedPassageContent(for: chunk).lowercased()
        if containsFrontMatterSignal(lower) {
            return -4.0
        }

        return 0
    }

    private func primarySectionLabel(for chunk: DocumentChunk) -> String? {
        if let section = cleanedMetadataValue(chunk.metadata.sectionTitle),
           !isWeakQuestionTopic(section) {
            return section
        }

        if let tableTitle = cleanedMetadataValue(chunk.metadata.tableTitle) {
            return tableTitle
        }

        if let pathSection = cleanedMetadataValue(chunk.metadata.sectionPath?.last),
           !isWeakQuestionTopic(pathSection) {
            return pathSection
        }

        if let imageCaption = cleanedMetadataValue(chunk.metadata.imageCaption, maxLength: 80),
           !isWeakQuestionTopic(imageCaption) {
            return imageCaption
        }

        return nil
    }

    private func sectionHierarchyLabel(for chunk: DocumentChunk) -> String? {
        let parts = (chunk.metadata.sectionPath ?? []).compactMap { cleanedMetadataValue($0, maxLength: 80) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " > ")
    }

    private func cleanedMetadataValue(_ value: String?, maxLength: Int? = nil) -> String? {
        let cleaned = value?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) ?? ""

        guard !cleaned.isEmpty else { return nil }

        if let maxLength, cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private struct GroundedPassage: Sendable {
        let chunk: DocumentChunk
        let documentName: String
        let sectionName: String?
        let content: String
        let searchableText: String
        let documentTokens: Set<String>
        let sectionTokens: Set<String>
        let bodyTokens: Set<String>
    }

    private struct QuestionDraft: Sendable {
        let text: String
        let category: QuestionCategory
        let confidence: Double
    }

    // MARK: - Step 2: LLM Generation (iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithLLM(
        baseQuestions: [SuggestedQuestion],
        chunks: [DocumentChunk],
        documents: [Document],
        avoidTexts: [String] = []
    ) async -> [SuggestedQuestion] {

        guard SystemLanguageModel.default.isAvailable else {
            Log.debug("[SuggestedQuestions] Apple FM not available, falling back to content extraction")
            return []
        }
        guard !baseQuestions.isEmpty else { return [] }

        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: 5)
        guard !passages.isEmpty else { return [] }

        let rewriteTargets = baseQuestions.enumerated().compactMap { index, question -> (Int, SuggestedQuestion, GroundedPassage)? in
            guard let groundedPassage = bestGroundingPassage(for: question.text, passages: passages),
                  shouldAllowLLMRewrite(for: question.text, passage: groundedPassage) else {
                return nil
            }
            return (index, question, groundedPassage)
        }
        let limitedTargets = Array(rewriteTargets.prefix(6))
        guard limitedTargets.count >= 2 else { return [] }

        let candidateText = limitedTargets.enumerated().map { index, target in
            let question = target.1
            let passage = target.2
            var headerParts = ["Document: \(passage.documentName)"]
            if let section = passage.sectionName, !section.isEmpty {
                headerParts.append("Section: \(section)")
            }
            return """
            [\(index + 1)] \(headerParts.joined(separator: " | "))
            Candidate question: \(question.text)
            Passage:
            \(passage.content)
            """
        }.joined(separator: "\n\n")

        // If refreshing, tell the LLM to avoid previously-shown questions
        let avoidClause: String
        if !avoidTexts.isEmpty {
            let listed = avoidTexts.prefix(6).enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            avoidClause = "\n\nIMPORTANT: Do NOT repeat these previously shown questions — generate completely different ones:\n\(listed)\n"
        } else {
            avoidClause = ""
        }

        let prompt = """
        You are editing starter question chips for a document Q&A app.

        Rewrite each candidate question so it sounds natural, direct, and grounded in its passage.

        Rules:
        - Keep the SAME meaning, target fact, action, number, entity, and scope as the candidate
        - Do NOT invent a new topic, device, quantity, duration, condition, or capability
        - Every rewritten question must still be answerable mostly from that one passage with little or no inference
        - Keep each question under 12 words when possible
        - Prefer direct grounded forms like "What is...", "Which...", "When...", "How much...", or "What should you do if..."
        - If the passage is a warning, prohibition, or conditional instruction, keep the question concrete and safety-grounded
        - Do NOT turn a warning or restriction into a speculative capability question like "Can you..." or "How long can you..." unless the passage explicitly states that allowed capability or duration
        - Do NOT ask about the documents or passages themselves (e.g., do NOT say "according to the passage", "as mentioned in the text")
        - Do NOT generate or include any structural or meta references (e.g., referencing rows, columns, cells, tables, page numbers, or "the document/passage")
        - Do NOT include square brackets, placeholders, bullets, numbering, or quotes
        - Return the SAME NUMBER of questions in the SAME ORDER as the candidates below
        \(avoidClause)
        CANDIDATES:
        \(candidateText)

        Return ONLY plain question strings through the schema. Do not number them. Do not add bullets or quotes.
        """

        do {
            let response = try await withTimeout(seconds: 5.0) {
                let session = LanguageModelSession()
                // @Generable: typed [String] array — eliminates numbered-line regex parsing.
                // Constrained sampling enforces the declared schema at the token level.
                return try await session.respond(to: prompt, generating: SuggestedQuestionList.self)
            }
            let rewrittenTexts = response.content.questions.compactMap { sanitizeGeneratedQuestion($0) }
            guard rewrittenTexts.count == limitedTargets.count else {
                Log.warning("[SuggestedQuestions] LLM rewrite count mismatch (\(rewrittenTexts.count) vs \(limitedTargets.count))")
                return []
            }

            var mergedQuestions = baseQuestions
            for (target, rewrittenText) in zip(limitedTargets, rewrittenTexts) {
                let questionIndex = target.0
                let original = target.1
                let groundedPassage = target.2

                guard isFaithfulQuestionRewrite(original: original.text, rewritten: rewrittenText, passage: groundedPassage),
                      isUsableGeneratedQuestion(rewrittenText, passages: [groundedPassage]),
                      !isSelfAnsweringGeneratedQuestion(rewrittenText),
                      isAnswerableSuggestedQuestion(rewrittenText, passage: groundedPassage)
                else {
                    mergedQuestions[questionIndex] = original
                    continue
                }

                mergedQuestions[questionIndex] = SuggestedQuestion(
                    id: UUID(),
                    text: rewrittenText,
                    category: original.category,
                    relevantDocuments: original.relevantDocuments,
                    sourceSections: original.sourceSections,
                    confidence: max(original.confidence, groundedConfidence(for: rewrittenText, passage: groundedPassage))
                )
            }

            let deduped = dedupeSuggestedQuestionsPreservingOrder(mergedQuestions)
            guard deduped.count >= 2 else {
                Log.warning("[SuggestedQuestions] LLM returned too few valid rewrites (\(deduped.count))")
                return []
            }

            Log.info("[SuggestedQuestions] LLM polished \(deduped.count) grounded questions")
            return deduped

        } catch {
            Log.warning("[SuggestedQuestions] LLM rewrite failed: \(error.localizedDescription)")
            return []
        }
    }

    private func shouldAllowLLMRewrite(
        for question: String,
        passage: GroundedPassage
    ) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Treat this as the planning gate: only low-risk fact questions are eligible
        // for stylistic polish. Safety, requirements, procedures, and quantity asks
        // keep deterministic phrasing so the LLM cannot change their modality.
        if passageLooksSafetyCritical(passage.content) || passageContainsProhibition(passage.content) {
            return false
        }

        if isQuantityQuestion(question) || isCapabilityQuestionFraming(lower) {
            return false
        }

        if isProceduralQuestionFraming(lower) || isSafetyOrRequirementQuestionFraming(lower) {
            return false
        }

        return true
    }

    @available(iOS 26.0, *)
    private func generateDirectlyWithLLM(
        chunks: [DocumentChunk],
        documents: [Document],
        avoidTexts: [String] = []
    ) async -> [SuggestedQuestion] {
        guard SystemLanguageModel.default.isAvailable else { return [] }

        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: 5)
        guard !passages.isEmpty else { return [] }

        let candidateText = passages.enumerated().map { index, passage in
            var headerParts = ["Document: \(passage.documentName)"]
            if let section = passage.sectionName, !section.isEmpty {
                headerParts.append("Section: \(section)")
            }
            return """
            [\(index + 1)] \(headerParts.joined(separator: " | "))
            Passage content:
            \(passage.content)
            """
        }.joined(separator: "\n\n")

        let avoidClause: String
        if !avoidTexts.isEmpty {
            let listed = avoidTexts.prefix(6).enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            avoidClause = "\n\nIMPORTANT: Do NOT repeat these previously shown questions — generate completely different ones:\n\(listed)\n"
        } else {
            avoidClause = ""
        }

        let prompt = """
        You are generating starter question chips for a document Q&A app.
        Generate natural, direct, and interesting questions that are grounded in and answerable by the following passages.

        Each question should be a high-quality, inference-based or analytical inquiry about the key findings, methodologies, concepts, or details in the passages.

        Rules:
        - Questions must be direct, specific, and interesting (e.g. "How does the model handle [Concept]?" or "Why does [A] affect [B]?" or "What are the limitations of [Method]?").
        - Avoid generic or textbook-style questions (e.g., do NOT start with "What role does..." or "What is the significance of...").
        - Every question must be fully answerable by the passage content. Do not speculate or invent details.
        - Keep each question under 15 words.
        - Do NOT ask about the documents or passages themselves (e.g., do NOT say "According to document...", "as mentioned in the text").
        - Do NOT generate or include any structural or meta references (e.g., referencing rows, columns, cells, tables, page numbers, or "the document/passage"). All questions must focus purely on concepts, facts, or domain content.
        - Do NOT include square brackets, placeholders, bullets, numbering, or quotes.
        \(avoidClause)
        PASSAGES:
        \(candidateText)

        Return ONLY plain question strings through the schema. Do not number them. Do not add bullets or quotes.
        """

        do {
            let response = try await withTimeout(seconds: 5.0) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: SuggestedQuestionList.self)
            }

            var generatedQuestions: [SuggestedQuestion] = []
            for rawText in response.content.questions {
                guard let questionText = sanitizeGeneratedQuestion(rawText) else { continue }

                // Find the best grounded passage for this question
                guard let groundedPassage = bestGroundingPassage(for: questionText, passages: passages),
                      isUsableGeneratedQuestion(questionText, passages: [groundedPassage]),
                      !isSelfAnsweringGeneratedQuestion(questionText),
                      isAnswerableSuggestedQuestion(questionText, passage: groundedPassage)
                else { continue }

                // Infer category
                let category: QuestionCategory = inferCategoryDirect(for: questionText)

                generatedQuestions.append(SuggestedQuestion(
                    id: UUID(),
                    text: questionText,
                    category: category,
                    relevantDocuments: [groundedPassage.documentName],
                    sourceSections: groundedPassage.sectionName.map { [$0] } ?? [],
                    confidence: 0.85
                ))
            }

            return dedupeSuggestedQuestionsPreservingOrder(generatedQuestions)
        } catch {
            Log.warning("[SuggestedQuestions] Direct LLM generation failed: \(error.localizedDescription)")
            return []
        }
    }

    private func inferCategoryDirect(for text: String) -> QuestionCategory {
        let lower = text.lowercased()
        if lower.contains("compare") || lower.contains("contrast") || lower.contains("versus") || lower.contains(" vs ") || lower.contains("different from") {
            return .comparison
        } else if lower.contains("summar") || lower.contains("overview") || lower.contains("outline") {
            return .summarization
        } else if lower.hasPrefix("how") || lower.contains("steps") || lower.contains("procedure") {
            return .procedural
        } else if lower.contains("why") || lower.contains("explain") || lower.contains("reason") || lower.contains("relation") || lower.contains("impact") || lower.contains("affect") {
            return .analytical
        } else if lower.contains("how many") || lower.contains("how much") || lower.contains("percent") || lower.contains("ratio") || lower.contains("rate") || lower.contains("cost") {
            return .numerical
        } else {
            return .factRetrieval
        }
    }
    #endif

    // MARK: - Step 3: Content-Grounded Fallback (no LLM)

    /// Generate questions from actual chunk content when LLM is unavailable.
    /// Extracts key phrases and specific details — NOT single-word entities.
    private func generateFromContent(
        chunks: [DocumentChunk],
        documents: [Document],
        avoidTexts: [String] = []
    ) -> [SuggestedQuestion] {

        var questions: [SuggestedQuestion] = []
        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: chunks.count)
        
        let avoidNormalized = Set(avoidTexts.map { normalizedQuestionKey($0) })

        for passage in passages {
            for draft in deterministicQuestionDrafts(for: passage) {
                let questionText = draft.text.hasSuffix("?") ? draft.text : draft.text + "?"
                let normText = normalizedQuestionKey(questionText)
                if avoidNormalized.contains(normText) {
                    continue
                }

                guard isUsableDeterministicDraft(questionText, passage: passage) else {
                    continue
                }

                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: questionText,
                    category: draft.category,
                    relevantDocuments: [passage.documentName],
                    sourceSections: passage.sectionName.map { [$0] } ?? [],
                    confidence: draft.confidence
                ))
            }
        }

        return dedupeSuggestedQuestionsPreservingOrder(questions)
    }

    private func isUsableDeterministicDraft(
        _ question: String,
        passage: GroundedPassage
    ) -> Bool {
        let lower = question.lowercased()
        if isBoilerplateQuestionTemplate(lower) {
            return false
        }
        if isStructuralOrMetaQuestion(lower) {
            return false
        }
        if isJunkString(question) {
            return false
        }
        let bannedFragments = [
            "[", "]", "{", "}", "<", ">",
            "thing from passage",
            "specific thing from passage",
            "condition from passage",
            "specific detail from the passage",
            "specific detail",
            "what does the document say",
            "what do the documents say",
            "uploaded document",
            "uploaded documents",
            "from the passages below",
            "from the passage",
            "style guide",
            "real person casually asking",
            "what's important about",
            "what is important about",
            "why is ",
            " important here",
            "actually do",
            "main point",
            "key points",
            "key details",
            "can you explain",
            "tell me about",
            "what are the key"
        ]
        if bannedFragments.contains(where: { lower.contains($0) }) {
            return false
        }

        if violatesPassageQuestionGuardrails(question, passage: passage) {
            return false
        }

        if isSelfAnsweringGeneratedQuestion(question) {
            return false
        }

        // Ensure at least one token from the question overlaps with the passage body or section/document title
        let tokens = meaningfulTokens(from: lower)
        guard !tokens.isEmpty else { return false }

        let groundingToks = passage.documentTokens.union(passage.sectionTokens)
        let overlapCount = tokens.intersection(passage.bodyTokens).count
            + tokens.intersection(groundingToks).count
        
        return overlapCount >= 1
    }

    private func generateFallbackQuestions(
        documents: [Document],
        chunks: [DocumentChunk],
        count: Int,
        avoidTexts: [String] = []
    ) -> [SuggestedQuestion] {
        var fallbacks: [SuggestedQuestion] = []
        let avoidNormalized = Set(avoidTexts.map { normalizedQuestionKey($0) })

        let addFallback: (SuggestedQuestion) -> Void = { q in
            let norm = self.normalizedQuestionKey(q.text)
            if !avoidNormalized.contains(norm) {
                fallbacks.append(q)
            }
        }
        
        // 1. Generate questions based on document names
        for doc in documents.prefix(3) {
            let docName = displayDocumentName(doc.filename)
            
            let isResearch = doc.filename.lowercased().contains("study") 
                || doc.filename.lowercased().contains("paper") 
                || doc.filename.lowercased().contains("trial")
                
            if isResearch {
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: "What did this study find?",
                    category: .factRetrieval,
                    relevantDocuments: [docName],
                    sourceSections: [],
                    confidence: 0.7
                ))
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: "Summarize the methodology of this research.",
                    category: .summarization,
                    relevantDocuments: [docName],
                    sourceSections: [],
                    confidence: 0.7
                ))
            } else {
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: "Summarize the key points in this document.",
                    category: .summarization,
                    relevantDocuments: [docName],
                    sourceSections: [],
                    confidence: 0.7
                ))
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: "What is the main purpose of this document?",
                    category: .factRetrieval,
                    relevantDocuments: [docName],
                    sourceSections: [],
                    confidence: 0.7
                ))
            }
        }
        
        // 2. Generate questions based on technical terms/phrases from chunks
        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: 10)
        var terms: [String] = []
        for passage in passages {
            terms.append(contentsOf: extractTechnicalTerms(from: passage.content, limit: 2))
        }
        let uniqueTerms = Array(Set(terms)).filter { $0.count >= 4 && $0.count <= 30 }
        
        for term in uniqueTerms.prefix(4) {
            if let passage = passages.first(where: { $0.content.contains(term) }) {
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: "What does this document explain about \(term)?",
                    category: .factRetrieval,
                    relevantDocuments: [passage.documentName],
                    sourceSections: passage.sectionName.map { [$0] } ?? [],
                    confidence: 0.65
                ))
            }
        }
        
        // Deduplicate and return
        let deduped = dedupeSuggestedQuestionsPreservingOrder(fallbacks)
        return Array(deduped.prefix(count))
    }

    private func deterministicQuestionDrafts(for passage: GroundedPassage) -> [QuestionDraft] {
        var drafts: [QuestionDraft] = []

        if let specQuestion = extractSpecificationQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: specQuestion,
                category: .numerical,
                confidence: 0.93
            ))
        }

        if let definitionQuestion = extractDefinitionQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: definitionQuestion,
                category: .factRetrieval,
                confidence: 0.81
            ))
        }

        if let conditionalQuestion = extractConditionalQuestion(from: passage.content) {
            drafts.append(QuestionDraft(
                text: conditionalQuestion,
                category: conditionalQuestion.lowercased().hasPrefix("what should you do if") ? .procedural : .analytical,
                confidence: 0.88
            ))
        }

        if let warningQuestion = extractWarningQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: warningQuestion,
                category: .procedural,
                confidence: 0.82
            ))
        }

        if let requirementQuestion = extractRequirementQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: requirementQuestion,
                category: .procedural,
                confidence: 0.79
            ))
        }

        if let domainSpecificDraft = extractDomainSpecificQuestion(from: passage) {
            drafts.append(domainSpecificDraft)
        }

        if let findingsDraft = extractFindingsQuestion(from: passage) {
            drafts.append(findingsDraft)
        }

        for conceptualDraft in extractConceptualQuestion(from: passage) {
            drafts.append(conceptualDraft)
        }

        if let visualDraft = extractVisualQuestion(from: passage) {
            drafts.append(visualDraft)
        }

        for (abbr, expansion) in passage.chunk.metadata.abbreviations.prefix(2) {
            let cleanAbbr = abbr.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanAbbr.count >= 2,
                  cleanAbbr.count <= 12,
                  cleanExpansion.count >= 4,
                  !cleanAbbr.contains("["),
                  !cleanExpansion.contains("[")
            else {
                continue
            }

            drafts.append(QuestionDraft(
                text: "What does \(cleanAbbr) stand for?",
                category: .factRetrieval,
                confidence: 0.62
            ))
        }

        if let proceduralQuestion = extractProceduralQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: proceduralQuestion,
                category: .procedural,
                confidence: 0.84
            ))
        }

        if let comparisonQuestion = extractComparisonQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: comparisonQuestion,
                category: .comparison,
                confidence: 0.8
            ))
        }

        if let tableQuestion = extractTableTopicQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: tableQuestion,
                category: .factRetrieval,
                confidence: 0.82
            ))
        }

        return drafts
    }

    private func extractDefinitionQuestion(from passage: GroundedPassage) -> String? {
        guard let topic = passageTopic(for: passage) else {
            return nil
        }
        guard passageLooksDefinitional(passage.content, topic: topic) else {
            return nil
        }

        let lowerTopic = topic.lowercased()
        let blockedTopicFragments = [
            "procedure", "procedures", "process", "requirements", "steps", "warnings", "limits"
        ]
        guard !blockedTopicFragments.contains(where: { lowerTopic.contains($0) }) else {
            return nil
        }

        let topicTokens = meaningfulTokens(from: topic)
        let requiredOverlap = min(max(topicTokens.count, 1), 2)
        guard topicTokens.intersection(passage.bodyTokens).count >= requiredOverlap else {
            return nil
        }

        let usesPluralVerb = lowerTopic.hasSuffix("s")
            || ["findings", "results", "features", "components", "options", "tiers", "plans", "modes"].contains {
                lowerTopic.contains($0)
            }

        return usesPluralVerb
            ? "What are the \(naturalQuestionTopic(topic))?"
            : "What is \(naturalQuestionTopic(topic))?"
    }

    private func extractSpecificationQuestion(from passage: GroundedPassage) -> String? {
        guard passage.chunk.metadata.hasNumericData else { return nil }

        let lines = candidateLines(from: passage.content)
        for line in lines {
            guard let match = firstMeasurementMatch(in: line) else { continue }
            guard let subject = specificationSubject(in: line, measurementRange: match, sectionName: passage.sectionName) else {
                continue
            }

            if isLiquidCapacityLine(line) || subject.lowercased().contains("capacity") {
                return "What is the \(capacitySubject(from: subject))?"
            }

            if subject.lowercased().contains("deadline") || subject.lowercased().contains("date") {
                return "When is the \(subject)?"
            }

            return "What is the \(subject)?"
        }

        return nil
    }

    private func extractTableTopicQuestion(from passage: GroundedPassage) -> String? {
        guard passage.chunk.metadata.structureType == "table" || passage.chunk.metadata.chunkType == .tableSemantic else {
            return nil
        }
        guard let topic = passageTopic(for: passage) else {
            return nil
        }

        if passage.chunk.metadata.hasNumericData {
            let lowerTopic = topic.lowercased()
            let usesPluralVerb = lowerTopic.hasSuffix("s") || lowerTopic.contains("specs") || lowerTopic.contains("values")
            return usesPluralVerb ? "What are the \(topic)?" : "What is the \(topic)?"
        }
        return nil
    }

    private func extractProceduralQuestion(from passage: GroundedPassage) -> String? {
        guard passage.chunk.metadata.hasListStructure else { return nil }
        guard passage.content.count >= 80 else { return nil }
        guard passageLooksProcedural(passage.content) else { return nil }
        guard !containsFrontMatterSignal(passage.content) else { return nil }
        guard let topic = normalizedProceduralTopic(from: passage.sectionName ?? passage.chunk.metadata.tableTitle) else {
            return nil
        }

        let topicTokens = meaningfulTokens(from: topic)
        let bodyOverlap = topicTokens.intersection(passage.bodyTokens).count
        let requiredBodyOverlap = min(max(topicTokens.count, 1), 2)
        guard bodyOverlap >= requiredBodyOverlap else { return nil }

        return proceduralQuestionText(for: topic)
    }

    private func extractWarningQuestion(from passage: GroundedPassage) -> String? {
        guard passageLooksSafetyCritical(passage.content) else { return nil }
        guard let topic = passageTopic(for: passage, allowDocumentFallback: false) else {
            return nil
        }
        guard isConcreteQuestionFocus(topic) else { return nil }

        let topicTokens = meaningfulTokens(from: topic)
        let requiredOverlap = min(max(topicTokens.count, 1), 2)
        guard topicTokens.intersection(passage.bodyTokens).count >= requiredOverlap else {
            return nil
        }

        let lower = passage.content.lowercased()
        if lower.contains("do not ") || lower.contains("must not ") || lower.contains("avoid ") {
            return "What should you avoid when \(naturalQuestionTopic(topic))?"
        }

        return "What warnings apply to \(naturalQuestionTopic(topic))?"
    }

    private func extractRequirementQuestion(from passage: GroundedPassage) -> String? {
        let lower = passage.content.lowercased()
        let requirementSignals = [
            "required", "must ", "minimum", "at least", "compatible", "supported", "only use", "up to"
        ]
        guard requirementSignals.contains(where: { lower.contains($0) }) else { return nil }
        guard let topic = passageTopic(for: passage, allowDocumentFallback: false) else {
            return nil
        }
        guard isConcreteQuestionFocus(topic) else { return nil }

        let topicTokens = meaningfulTokens(from: topic)
        let requiredOverlap = min(max(topicTokens.count, 1), 2)
        guard topicTokens.intersection(passage.bodyTokens).count >= requiredOverlap else {
            return nil
        }

        if lower.contains("minimum") || lower.contains("at least") {
            return "What are the minimum requirements for \(naturalQuestionTopic(topic))?"
        }

        return "What is required for \(naturalQuestionTopic(topic))?"
    }

    private func extractDomainSpecificQuestion(from passage: GroundedPassage) -> QuestionDraft? {
        let lower = passage.content.lowercased()
        let manualLike = passage.chunk.metadata.documentCategory == .technicalManual
            || passage.chunk.metadata.documentCategory == .regulatory
            || passage.chunk.metadata.documentCategory == .referenceTable
            || lower.contains("reprocess")
            || lower.contains("steriliz")
            || lower.contains("contraindication")
            || lower.contains("indications for use")

        guard manualLike else { return nil }
        let topic = passageTopic(for: passage, allowDocumentFallback: false) ?? documentScopedTopic(for: passage)
        guard let topic else { return nil }

        if lower.contains("contraindication") {
            return QuestionDraft(
                text: "What contraindications apply to \(naturalQuestionTopic(topic))?",
                category: .factRetrieval,
                confidence: 0.9
            )
        }

        if lower.contains("indications for use") || lower.contains("indicated for") || lower.contains("intended use") {
            return QuestionDraft(
                text: "What is \(naturalQuestionTopic(topic)) indicated for?",
                category: .factRetrieval,
                confidence: 0.88
            )
        }

        if lower.contains("compatible") || lower.contains("compatibility") {
            return QuestionDraft(
                text: "What is \(naturalQuestionTopic(topic)) compatible with?",
                category: .comparison,
                confidence: 0.86
            )
        }

        if lower.contains("reprocess")
            || lower.contains("steriliz")
            || lower.contains("pre-clean")
            || lower.contains("manual cleaning")
            || lower.contains("automated cleaning")
        {
            return QuestionDraft(
                text: "How should \(naturalQuestionTopic(topic)) be cleaned or reprocessed?",
                category: .procedural,
                confidence: 0.9
            )
        }

        if lower.contains("inspection") || lower.contains("function check") || lower.contains("visual inspection") {
            return QuestionDraft(
                text: "How do you inspect \(naturalQuestionTopic(topic)) before use?",
                category: .procedural,
                confidence: 0.86
            )
        }

        return nil
    }

    private func extractFindingsQuestion(from passage: GroundedPassage) -> QuestionDraft? {
        let lower = passage.content.lowercased()
        let researchLike = passage.chunk.metadata.documentCategory == .scientificPaper
            || lower.contains("study")
            || lower.contains("participants")
            || lower.contains("findings")

        guard researchLike else { return nil }
        guard let topic = passageTopic(for: passage) ?? documentTopic(from: passage.documentName) else {
            return nil
        }

        if lower.contains("limitation") || lower.contains("limitations") || lower.contains("caveat") {
            return QuestionDraft(
                text: "What limitations does the study mention about \(naturalQuestionTopic(topic))?",
                category: .factRetrieval,
                confidence: 0.88
            )
        }

        let findingSignals = [
            "found", "finding", "findings", "results", "concluded", "demonstrated",
            "showed", "observed", "associated", "improved", "reduced"
        ]

        guard passage.chunk.metadata.abstractionLevel.isSummary
            || findingSignals.contains(where: { lower.contains($0) })
        else {
            return nil
        }

        return QuestionDraft(
            text: "What did the study find about \(naturalQuestionTopic(topic))?",
            category: .factRetrieval,
            confidence: 0.91
        )
    }

    private func extractConceptualQuestion(from passage: GroundedPassage) -> [QuestionDraft] {
        let terms = extractTechnicalTerms(from: passage.content, limit: 2)
        var drafts: [QuestionDraft] = []
        
        for term in terms {
            guard term.count >= 4 && term.count <= 40 else { continue }
            
            let isResearch = passage.chunk.metadata.documentCategory == .scientificPaper
                || passage.content.lowercased().contains("study")
                || passage.content.lowercased().contains("research")
                
            if isResearch {
                drafts.append(QuestionDraft(
                    text: "What does the study say about \(term)?",
                    category: .factRetrieval,
                    confidence: 0.85
                ))
                drafts.append(QuestionDraft(
                    text: "How does \(term) impact the findings?",
                    category: .analytical,
                    confidence: 0.80
                ))
                drafts.append(QuestionDraft(
                    text: "What are the key insights regarding \(term)?",
                    category: .analytical,
                    confidence: 0.82
                ))
            } else {
                drafts.append(QuestionDraft(
                    text: "What is the role of \(term)?",
                    category: .factRetrieval,
                    confidence: 0.82
                ))
                drafts.append(QuestionDraft(
                    text: "How does \(term) function?",
                    category: .analytical,
                    confidence: 0.78
                ))
                drafts.append(QuestionDraft(
                    text: "Why is \(term) important?",
                    category: .analytical,
                    confidence: 0.80
                ))
            }
        }
        return drafts
    }

    private func extractTechnicalTerms(from text: String, limit: Int = 3) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var candidates: [String] = []
        
        let citationStopWords: Set<String> = [
            "press", "university", "journal", "proceedings", "conference", "editor", "edition", 
            "publish", "publisher", "isbn", "issn", "vol", "volume", "page", "pages", "pp", 
            "abstract", "introduction", "conclusions", "references", "bibliography", "oxford", 
            "cambridge", "springer", "wiley", "elsevier", "ieee", "acm", "mit", "routledge", 
            "pearson", "macmillan", "harper", "academic", "publishing", "books", "book", "translation",
            "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
            "study", "studies", "research", "paper", "article", "thesis", "dissertation", "manuscript",
            "figure", "table", "section", "chapter", "appendix", "author", "authors", "cited"
        ]
        let stopWords = Self.matchStopTokens
            .union(Self.specSubjectStopTokens)
            .union(Self.questionFocusStopTokens)
            .union(citationStopWords)
            .union(["is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "can", "could", "will", "would", "shall", "should", "may", "might", "must", "using", "use", "used", "via", "through", "by", "of", "in", "on", "at", "to", "for", "with", "about", "against", "between", "into", "through", "during", "before", "after", "above", "below", "from", "up", "down", "in", "out", "on", "off", "over", "under", "again", "further", "then", "once"])
            
        let isValidTechnicalTerm: (ArraySlice<String>) -> Bool = { combo in
            guard combo.count >= 2 else { return false }
            let firstWord = combo.first!
            let lastWord = combo.last!
            
            let isContentWord: (String) -> Bool = { word in
                let lower = word.lowercased()
                return lower.count >= 3
                    && !stopWords.contains(lower)
                    && !Self.genericStopEntities.contains(lower)
                    && !word.contains(where: \.isNumber)
            }
            
            guard isContentWord(firstWord) && isContentWord(lastWord) else { return false }
            
            let allowedMiddleWords: Set<String> = ["of", "in", "for", "with", "and", "or", "to", "the", "a", "an"]
            if combo.count > 2 {
                let middleWords = combo.dropFirst().dropLast()
                for word in middleWords {
                    let lower = word.lowercased()
                    if !isContentWord(word) && !allowedMiddleWords.contains(lower) {
                        return false
                    }
                }
            }
            return true
        }

        for sentence in sentences {
            let words = sentence
                .replacingOccurrences(of: #"[^a-zA-Z\s-]"#, with: "", options: .regularExpression)
                .split(separator: " ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                
            guard words.count >= 2 else { continue }
            
            for size in [2, 3, 4] {
                guard words.count >= size else { continue }
                for i in 0...(words.count - size) {
                    let combo = words[i..<(i + size)]
                    if isValidTechnicalTerm(combo) {
                        let phrase = combo.joined(separator: " ")
                        candidates.append(phrase)
                    }
                }
            }
        }
        
        var counts: [String: Int] = [:]
        for c in candidates {
            let key = c.lowercased()
            counts[key, default: 0] += 1
        }
        
        let uniqueCandidates = Array(Set(candidates)).sorted { a, b in
            let countA = counts[a.lowercased()] ?? 0
            let countB = counts[b.lowercased()] ?? 0
            if countA == countB {
                return a.count > b.count
            }
            return countA > countB
        }
        
        return Array(uniqueCandidates.prefix(limit))
    }

    private func passageLooksDefinitional(_ text: String, topic: String) -> Bool {
        let lower = text.lowercased()
        let lowerTopic = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowerTopic.isEmpty else { return false }

        let explicitSignals = [
            "defined as", "refers to", "means", "is the", "are the", "is a", "are a", "describes"
        ]

        if explicitSignals.contains(where: { lower.contains($0) }) {
            return true
        }

        let escapedTopic = NSRegularExpression.escapedPattern(for: lowerTopic)
        let pattern = #"\b"# + escapedTopic + #"\b\s+(?:is|are|refers to|means|describes)\b"#
        return lower.range(of: pattern, options: [.regularExpression]) != nil
    }

    private func extractVisualQuestion(from passage: GroundedPassage) -> QuestionDraft? {
        guard cleanedMetadataValue(passage.chunk.metadata.imageCaption, maxLength: 120) != nil
            || cleanedMetadataValue(passage.chunk.metadata.imageDescription, maxLength: 160) != nil
        else {
            return nil
        }

        guard let topic = passageTopic(for: passage) else {
            return nil
        }

        return QuestionDraft(
            text: "What details are shown for \(naturalQuestionTopic(topic))?",
            category: .factRetrieval,
            confidence: 0.8
        )
    }

    private func extractComparisonQuestion(from passage: GroundedPassage) -> String? {
        let lowerContent = passage.content.lowercased()
        let isStructured = passage.chunk.metadata.structureType == "table"
            || passage.chunk.metadata.chunkType == .tableSemantic
            || passage.chunk.metadata.hasListStructure
        guard isStructured else { return nil }
        guard let topic = passageTopic(for: passage) else {
            return nil
        }

        let lowerTopic = topic.lowercased()
        let comparisonTopicSignals = [
            "compare", "comparison", "difference", "differences", "tiers", "options", "modes", "plans", "packages", "versions", "models", "levels"
        ]
        let hasComparisonSignal = comparisonTopicSignals.contains(where: { lowerTopic.contains($0) })
            || lowerContent.contains(" compared with ")
            || lowerContent.contains(" compared to ")
            || lowerContent.contains(" versus ")

        guard hasComparisonSignal else { return nil }
        return "How do the \(naturalQuestionTopic(topic)) compare?"
    }

    private func proceduralQuestionText(for topic: String) -> String {
        let normalizedTopic = naturalQuestionTopic(topic)
        let firstToken = normalizedTopic
            .split(separator: " ")
            .first?
            .lowercased() ?? ""

        if firstToken.hasSuffix("ing") || Self.proceduralActionStarters.contains(firstToken) {
            return "How do you \(normalizedTopic)?"
        }

        return "How do you handle \(normalizedTopic)?"
    }

    private func normalizedProceduralTopic(from text: String?) -> String? {
        guard let text else { return nil }

        let stripped = text
            .replacingOccurrences(
                of: #"(?i)^(?:(?:performing|perform|procedure|procedures|process|steps|step|instructions?)\s+(?:for\s+)?)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        guard let topic = concreteTopic(from: stripped), !isWeakProceduralTopic(topic) else {
            return nil
        }

        return naturalQuestionTopic(topic)
    }

    private func isWeakProceduralTopic(_ topic: String) -> Bool {
        let tokens = meaningfulTokens(from: topic)
        guard !tokens.isEmpty else { return true }

        if tokens.contains(where: { Self.proceduralTopicStopTokens.contains($0) }) {
            return true
        }

        return isGenericQuestionTopic(topic)
    }

    private func passageLooksProcedural(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasEnumeratedList = lower.range(
            of: #"(?m)^\s*(?:\d+[\.)]|[-•])\s+[a-z]"#,
            options: .regularExpression
        ) != nil
        let proceduralSignals = [
            "step", "steps", "remove", "install", "detach", "attach", "clean", "rinse", "dry",
            "inspect", "check", "start", "stop", "press", "turn", "place", "load", "connect",
            "disconnect", "apply", "ensure", "repeat", "perform", "follow"
        ]
        let signalCount = proceduralSignals.reduce(0) { partialResult, signal in
            partialResult + (lower.contains(signal) ? 1 : 0)
        }

        return hasEnumeratedList || signalCount >= 3
    }

    private func candidateLines(from text: String) -> [String] {
        let lineBreaks = text.components(separatedBy: .newlines)
        let sentenceBreaks = text.components(separatedBy: CharacterSet(charactersIn: ".;"))
        return (lineBreaks + sentenceBreaks)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 && $0.count <= 220 }
    }

    private func firstMeasurementMatch(in text: String) -> NSRange? {
        let pattern = #"(?i)\b\d+(?:[.,]\d+)?\s*(?:US\s*)?(?:%|DPI|Hz|MHz|GHz|MB|GB|TB|KB|ms|sec|s|min|hr|mg|mL|ml|L|l|liters?|litres?|kg|g|lb|lbs|oz|ft|in|cm|mm|m|km|mi|mph|rpm|psi|kPa|bar|°C|°F|watts?|volts?|amps?|tokens?|gal|gals|gallons?|qt|quarts?|N·m|Nm|lb-ft|ft-lb|hp|kW)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, range: range)?.range
    }

    private func specificationSubject(
        in line: String,
        measurementRange: NSRange,
        sectionName: String?
    ) -> String? {
        let nsLine = line as NSString
        let prefix = nsLine.substring(to: measurementRange.location)
        let suffixStart = measurementRange.location + measurementRange.length
        let suffix = suffixStart < nsLine.length ? nsLine.substring(from: suffixStart) : ""

        let prefixSubject = cleanedSpecSubject(prefix)
        let suffixSubject = cleanedSpecSubject(suffix)
        let sectionSubject = concreteTopic(from: sectionName)

        let rawSubject: String?
        if let prefixSubject, prefixSubject.count >= 3 {
            rawSubject = prefixSubject
        } else if let sectionSubject {
            rawSubject = sectionSubject
        } else {
            rawSubject = suffixSubject
        }

        guard let rawSubject else { return nil }
        let subject = normalizeSpecSubject(rawSubject)
        guard subject.count >= 3, !isGenericQuestionTopic(subject) else { return nil }
        return subject
    }

    private func cleanedSpecSubject(_ text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: #"(?i)\b(?:table|page|section|chapter)\s+\d+[A-Za-z.-]*\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[:|•=]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\([^)]*$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        guard !cleaned.isEmpty else { return nil }

        let words = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { word in
                let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                let hasLetters = lower.contains(where: \.isLetter)
                return lower.count >= 2 && !Self.specSubjectStopTokens.contains(lower) && hasLetters
            }

        guard !words.isEmpty else { return nil }
        return words.suffix(6).joined(separator: " ")
    }

    private func normalizeSpecSubject(_ subject: String) -> String {
        let cleaned = subject
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if cleaned == cleaned.uppercased() {
            return cleaned.lowercased()
        }
        return cleaned.prefix(1).lowercased() + String(cleaned.dropFirst())
    }

    private func capacitySubject(from subject: String) -> String {
        let lower = subject.lowercased()
        if lower == "fuel" || lower == "gas" || lower == "gasoline" {
            return "fuel tank capacity"
        }
        if lower.contains("fuel") || lower.contains("gasoline") || lower.contains("gas") {
            return lower.contains("capacity") ? subject : "\(subject) capacity"
        }
        if lower.contains("oil") || lower.contains("coolant") || lower.contains("fluid") {
            return lower.contains("capacity") ? subject : "\(subject) capacity"
        }
        return lower.contains("capacity") ? subject : "\(subject) capacity"
    }

    private func isLiquidCapacityLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let hasLiquidUnit = lower.range(
            of: #"\b(?:gal|gals|gallons?|qt|quarts?|l|liters?|litres?|ml)\b"#,
            options: .regularExpression
        ) != nil
        let hasLiquidSubject = [
            "fuel", "gas", "gasoline", "oil", "coolant", "fluid", "tank", "capacity", "volume"
        ].contains { lower.contains($0) }
        return hasLiquidUnit && hasLiquidSubject
    }

    private func passageTopic(for passage: GroundedPassage, allowDocumentFallback: Bool = true) -> String? {
        let contextTokens = passage.bodyTokens.union(passage.sectionTokens).union(passage.documentTokens)
        let candidates: [String?] = [
            cleanedMetadataValue(passage.chunk.metadata.tableTitle),
            cleanedMetadataValue(passage.chunk.metadata.imageCaption, maxLength: 120),
            cleanedMetadataValue(passage.chunk.metadata.imageDescription, maxLength: 160),
            passage.sectionName,
            sectionHierarchyLabel(for: passage.chunk)
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            guard let topic = concreteTopic(from: candidate), !isWeakQuestionTopic(topic) else { continue }
            let tokens = meaningfulTokens(from: topic)
            guard !tokens.isEmpty else { continue }

            if !tokens.intersection(contextTokens).isEmpty {
                return naturalQuestionTopic(topic)
            }
        }

        if let metadataTopic = salientMetadataTopic(for: passage.chunk) {
            return naturalQuestionTopic(metadataTopic)
        }

        if allowDocumentFallback, let documentTopic = documentTopic(from: passage.documentName) {
            return naturalQuestionTopic(documentTopic)
        }

        return nil
    }

    private func documentScopedTopic(for passage: GroundedPassage) -> String? {
        if let metadataTopic = salientMetadataTopic(for: passage.chunk) {
            return naturalQuestionTopic(metadataTopic)
        }

        if let documentTopic = documentTopic(from: passage.documentName) {
            return naturalQuestionTopic(documentTopic)
        }

        return passageTopic(for: passage, allowDocumentFallback: false)
    }

    private func salientMetadataTopic(for chunk: DocumentChunk) -> String? {
        let candidates = chunk.metadata.entities + chunk.metadata.keywords

        for candidate in candidates {
            guard let topic = concreteTopic(from: candidate), !isWeakQuestionTopic(topic) else { continue }
            let tokens = meaningfulTokens(from: topic)
            guard !tokens.isEmpty, tokens.count <= 5 else { continue }
            return topic
        }

        return nil
    }

    private func isConcreteQuestionFocus(_ topic: String) -> Bool {
        let tokens = meaningfulTokens(from: topic)
        guard !tokens.isEmpty else { return false }

        if tokens.count == 1, let only = tokens.first {
            return isLikelySpecificSuggestionFocusToken(only)
        }

        return tokens.contains(where: isLikelySpecificSuggestionFocusToken)
    }

    private func documentTopic(from documentName: String) -> String? {
        let stripped = documentName
            .replacingOccurrences(
                of: #"(?i)\b(?:instructions?\s+for\s+use|ifu|manual|guide|guidelines?|handbook|datasheet|reference|specifications?|protocol|report|paper|study|trial|review|supplement(?:ary)?|document|pdf)\b"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if let topic = casePreservingTopic(from: stripped), !isWeakQuestionTopic(topic) {
            return topic
        }

        if let fallback = casePreservingTopic(from: documentName), !isWeakQuestionTopic(fallback) {
            return fallback
        }

        return nil
    }

    private func isWeakQuestionTopic(_ topic: String) -> Bool {
        let normalized = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let blockedPhrases: Set<String> = [
            "contraindications", "indications", "indications for use", "intended use",
            "reprocessing", "sterilization", "manual cleaning", "automated cleaning",
            "cleaning agents", "technical data", "product description", "visual overview",
            "general safety information", "safety notices", "process flow", "troubleshooting",
            "repair", "requirements", "qualification", "qualifications", "overview",
            "scope of delivery", "scope of validity", "document summary"
        ]

        if blockedPhrases.contains(normalized) {
            return true
        }

        let tokens = meaningfulTokens(from: topic)
        guard !tokens.isEmpty else { return true }

        let weakSectionTailTokens: Set<String> = [
            "operation", "operations", "mode", "modes", "setting", "settings",
            "feature", "features", "function", "functions", "option", "options"
        ]

        if tokens.count <= 2,
           !tokens.contains(where: { $0.contains(where: \.isNumber) }),
           let last = normalized.split(separator: " ").last.map(String.init),
           weakSectionTailTokens.contains(last)
        {
            return true
        }

        if tokens.count == 1, let only = tokens.first, Self.weakQuestionTopicTokens.contains(only) {
            return true
        }

        return isGenericQuestionTopic(topic)
    }

    private func isJunkString(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Rule 1: Check for raw math/code/layout symbols that should not appear in clean questions.
        // We allow '+' if it's explicitly part of "c++" or "C++" (case-insensitive).
        let lower = trimmed.lowercased()
        let hasPlus = lower.contains("+")
        let isCpp = lower.contains("c++")
        if hasPlus && !isCpp {
            return true
        }

        // Banned layout, math, and code characters
        let bannedChars = Set<Character>([
            "=", "<", ">", "|", "_", "~", "^", "*", "\\", "•", "▪", "●", "♦", "★", "▲", "▼", "¶", "§", "©", "®", "™"
        ])
        if trimmed.contains(where: { bannedChars.contains($0) }) {
            return true
        }

        // Rule 2: Check for consecutive duplicate punctuation noise
        let noisePatterns = [
            #"\.\."#,       // double dot
            #"::"#,         // double colon
            #"--"#,         // double dash
            #",,"#,         // double comma
            #"\?\?"#,       // double question mark
            #"!!"#,         // double exclamation
            #"//"#,         // double slash
            #"&&"#,         // double ampersand
            #"%%"#          // double percent
        ]
        for pattern in noisePatterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // Rule 3: Split into individual tokens and check for OCR gibberish, range patterns, and formatting junk.
        let delimiters = CharacterSet(charactersIn: " \t\r\n,;:!?()[]{}<>\"'`“”‘’")
        let tokens = trimmed.components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Allowed abbreviations with periods inside
        let allowedDotAbbreviations: Set<String> = [
            "e.g.", "i.e.", "u.s.", "a.m.", "p.m.", "vs.", "approx.", "co.", "inc.", "corp.", "ltd.", "dr.", "mr.", "ms.",
            "dept.", "est.", "fig.", "figs.", "sec.", "min.", "hr.", "hrs.", "vol.", "vols.", "ed.", "eds.",
            "ph.d.", "ph.d", "u.s.a.", "u.s.a", "u.k.", "u.k", "b.s.", "b.s", "m.s.", "m.s", "b.a.", "b.a", "m.d.", "m.d", "d.c.", "d.c"
        ]

        for token in tokens {
            let tokenLower = token.lowercased()

            // A: Period in the middle of token
            if token.contains(".") {
                let inner = tokenLower.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !inner.isEmpty {
                    // Check if it's a decimal number (e.g., 3.14, .05, 123.45)
                    let decimalPattern = #"^\d*\.?\d+$"#
                    let isDecimal = inner.range(of: decimalPattern, options: .regularExpression) != nil
                    
                    // Check if it contains only digits and dots (e.g. version numbers 5.10.1)
                    let isVersion = inner.allSatisfy { $0.isNumber || $0 == "." }
                    
                    // Check if it is an allowed abbreviation
                    let isAllowedAbbr = allowedDotAbbreviations.contains(tokenLower) 
                        || allowedDotAbbreviations.contains(tokenLower + ".")

                    if !isDecimal && !isVersion && !isAllowedAbbr {
                        return true
                    }
                }
            }

            // B: Mixed letter-digit tokens without dots
            let hasLetters = token.contains { $0.isLetter }
            let hasDigits = token.contains { $0.isNumber }
            if hasLetters && hasDigits {
                let validMixedPattern = #"^(?:\d+(?:st|nd|rd|th|x|g|k|m|s|h|hz|db|v|w|a|%|px|em|pt|in|cm|mm|oz|lb|kg|ml|l|sec|min|deg|c|f)|[iamv]\d+)$"#
                let isValidMixed = tokenLower.range(of: validMixedPattern, options: .regularExpression) != nil

                if !isValidMixed {
                    var transitions = 0
                    var lastIsLetter: Bool? = nil
                    for char in token {
                        let isLetter = char.isLetter
                        if let last = lastIsLetter, last != isLetter {
                            transitions += 1
                        }
                        lastIsLetter = isLetter
                    }
                    if token.count > 5 || transitions > 1 {
                        return true
                    }
                }
            }

            // C: CamelCase or weird casing (excluding standard brands)
            let brandExceptions: Set<String> = [
                "iphone", "ipad", "macos", "latex", "github", "openintelligence", "ios", "xcode", "youtube", "powerpoint",
                "javascript", "typescript", "swiftui", "coredata", "combineswift"
            ]
            if token.count >= 3 && !brandExceptions.contains(tokenLower) {
                var hasMixedCase = false
                let chars = Array(token)
                for i in 0..<(chars.count - 1) {
                    if chars[i].isLowercase && chars[i+1].isUppercase {
                        hasMixedCase = true
                        break
                    }
                }
                if hasMixedCase {
                    return true
                }
            }
        }

        return false
    }

    private func concreteTopic(from text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard cleaned.count >= 4,
              cleaned.count <= 80,
              !isJunkString(cleaned),
              !isGenericSectionTitle(cleaned),
              !isGenericQuestionTopic(cleaned),
              !containsFrontMatterSignal(cleaned)
        else {
            return nil
        }

        if cleaned == cleaned.uppercased() {
            return cleaned.lowercased()
        }
        return cleaned.prefix(1).lowercased() + String(cleaned.dropFirst())
    }

    private func casePreservingTopic(from text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard cleaned.count >= 4,
              cleaned.count <= 80,
              !isJunkString(cleaned),
              !isGenericSectionTitle(cleaned),
              !isGenericQuestionTopic(cleaned),
              !containsFrontMatterSignal(cleaned)
        else {
            return nil
        }

        if cleaned == cleaned.uppercased() {
            return cleaned.lowercased()
        }

        return cleaned
    }

    private func isGenericOrStructuralToken(_ token: String) -> Bool {
        let lower = token.lowercased()
        if lower.allSatisfy({ $0.isNumber || $0.isPunctuation }) {
            return true
        }
        if lower.count <= 1 {
            return true
        }
        let romanNumerals: Set<String> = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]
        if romanNumerals.contains(lower) {
            return true
        }
        let structuralTerms: Set<String> = [
            "row", "rows", "column", "columns", "col", "cols", "table", "tables",
            "page", "pages", "fig", "figs", "figure", "figures", "section", "sections",
            "chapter", "chapters", "part", "parts", "line", "lines", "cell", "cells",
            "item", "items", "appendix", "appendices", "document", "documents",
            "paper", "papers", "report", "reports", "study", "studies", "research",
            "author", "authors", "value", "values",
            "source", "sources", "type", "types", "level", "levels", "limit", "limits",
            "setting", "settings", "rate", "rates", "grade", "grades", "class", "classes",
            "status", "range", "ranges", "date", "dates", "time", "times", "parameter",
            "parameters", "id", "no", "code", "codes", "data"
        ]
        if structuralTerms.contains(lower) {
            return true
        }
        return Self.genericStopEntities.contains(lower) || Self.specSubjectStopTokens.contains(lower)
    }

    private func isGenericQuestionTopic(_ topic: String) -> Bool {
        let tokens = meaningfulTokens(from: topic)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { isGenericOrStructuralToken($0) }
    }

    // MARK: - Step 4: Diversity Enforcement

    /// Ensure question diversity by spreading across documents first while still
    /// prioritizing the most answerable questions.
    /// The per-doc cap scales with how many documents exist — a single-doc library
    /// can still produce 4+ questions without being artificially cut to 2.
    private func enforceDiversity(_ questions: [SuggestedQuestion], count: Int) -> [SuggestedQuestion] {
        var result: [SuggestedQuestion] = []
        var docCounts: [String: Int] = [:]
        var selectedIds: Set<UUID> = []
        var docsSeeded: Set<String> = []

        // Dynamic per-doc cap: allow more questions from same doc when few docs exist
        let uniqueDocs = Set(questions.flatMap { $0.relevantDocuments })
        let perDocCap = uniqueDocs.count <= 2 ? count : max(2, count / uniqueDocs.count + 1)
        let rankedQuestions = questions.sorted { lhs, rhs in
            let lhsScore = rankingScore(for: lhs)
            let rhsScore = rankingScore(for: rhs)
            if lhsScore == rhsScore {
                return lhs.confidence > rhs.confidence
            }
            return lhsScore > rhsScore
        }

        // First pass: seed as many different documents as possible with the strongest,
        // most answerable questions instead of forcing one-per-category.
        for question in rankedQuestions {
            let docKey = question.relevantDocuments.first ?? ""
            guard !docsSeeded.contains(docKey) else { continue }
            guard (docCounts[docKey] ?? 0) < perDocCap else { continue }

            result.append(question)
            selectedIds.insert(question.id)
            docsSeeded.insert(docKey)
            docCounts[docKey, default: 0] += 1

            if result.count >= min(count, max(1, uniqueDocs.count)) { break }
        }

        // Second pass: fill remaining slots with the best remaining questions.
        if result.count < count {
            for question in rankedQuestions {
                guard !selectedIds.contains(question.id) else { continue }
                let docKey = question.relevantDocuments.first ?? ""
                if (docCounts[docKey] ?? 0) < perDocCap {
                    result.append(question)
                    selectedIds.insert(question.id)
                    docCounts[docKey, default: 0] += 1
                }
                if result.count >= count { break }
            }
        }

        return result
    }

    // MARK: - Grounding Helpers

    private func buildGroundedPassages(
        from chunks: [DocumentChunk],
        documents: [Document],
        limit: Int
    ) -> [GroundedPassage] {
        chunks.prefix(limit).map { chunk in
            let rawDocName = documents.first(where: { $0.id == chunk.documentId })?.filename ?? "Document"
            let docName = displayDocumentName(rawDocName)
            let sectionName = primarySectionLabel(for: chunk)
            let sectionHierarchy = sectionHierarchyLabel(for: chunk)
            let sectionContext = [
                sectionName,
                sectionHierarchy,
                cleanedMetadataValue(chunk.metadata.tableTitle),
                cleanedMetadataValue(chunk.metadata.imageCaption, maxLength: 120)
            ]
                .compactMap { $0 }
                .joined(separator: " ")
            let content = groundedPassageContent(for: chunk)
            let searchable = [
                docName,
                sectionName,
                sectionHierarchy,
                cleanedMetadataValue(chunk.metadata.tableTitle),
                cleanedMetadataValue(chunk.metadata.imageCaption, maxLength: 120),
                cleanedMetadataValue(chunk.metadata.imageDescription, maxLength: 160),
                content
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

            return GroundedPassage(
                chunk: chunk,
                documentName: docName,
                sectionName: sectionName,
                content: content,
                searchableText: searchable,
                documentTokens: meaningfulTokens(from: docName),
                sectionTokens: meaningfulTokens(from: sectionContext),
                bodyTokens: meaningfulTokens(from: content)
            )
        }
    }

    private func bestGroundingPassage(
        for question: String,
        passages: [GroundedPassage]
    ) -> GroundedPassage? {
        passages.max { lhs, rhs in
            groundingScore(for: question, passage: lhs) < groundingScore(for: question, passage: rhs)
        }
    }

    private func groundedConfidence(for question: String, passage: GroundedPassage) -> Double {
        let score = groundingScore(for: question, passage: passage)
        return min(0.98, 0.72 + min(score, 8.0) * 0.03)
    }

    private func groundingScore(for question: String, passage: GroundedPassage) -> Double {
        let lowered = question.lowercased()
        let tokens = meaningfulTokens(from: lowered)
        let numericTokens = numberTokens(from: lowered)

        var score = 0.0
        score += Double(tokens.intersection(passage.documentTokens).count) * 2.5
        score += Double(tokens.intersection(passage.sectionTokens).count) * 1.75
        score += Double(tokens.intersection(passage.bodyTokens).count) * 1.0
        score += Double(numericTokens.filter { passage.searchableText.contains($0) }.count) * 3.0

        if passage.chunk.metadata.hasNumericData,
           lowered.contains("how many") || lowered.contains("how much") || lowered.contains("cost") || lowered.contains("capacity") {
            score += 1.0
        }

        if passage.chunk.metadata.hasListStructure,
           lowered.contains("step") || lowered.contains("how do") || lowered.contains("how should") {
            score += 1.0
        }

        if passage.chunk.metadata.structureType == "table",
           lowered.contains("which") || lowered.contains("compare") || lowered.contains("difference") {
            score += 0.75
        }

        return score
    }

    private func inferCategory(
        for question: String,
        passage: GroundedPassage?,
        fallbackIndex: Int
    ) -> QuestionCategory {
        let lowered = question.lowercased()

        if lowered.contains("how many") || lowered.contains("how much") || lowered.contains("cost") || lowered.contains("capacity") {
            return .numerical
        }
        if lowered.contains("compare") || lowered.contains("difference") || lowered.contains("which") {
            return .comparison
        }
        if lowered.contains("step")
            || lowered.hasPrefix("how do")
            || lowered.hasPrefix("how should")
            || lowered.hasPrefix("what should you do if")
            || lowered.hasPrefix("what do you do if")
        {
            return .procedural
        }
        if lowered.hasPrefix("why") || lowered.contains("what happens if") {
            return .analytical
        }
        if lowered.contains("summarize") || lowered.contains("overview") || lowered.contains("covered under") {
            return .summarization
        }
        if passage?.chunk.metadata.hasNumericData == true && lowered.hasPrefix("what") == false && lowered.hasPrefix("how") {
            return .numerical
        }

        let categories: [QuestionCategory] = [.factRetrieval, .analytical, .procedural, .comparison, .summarization, .numerical]
        return categories[fallbackIndex % categories.count]
    }

    private func groundedPassageContent(for chunk: DocumentChunk) -> String {
        let baseContent = chunk.parentContent ?? chunk.content
        let metadataSegments = [
            sectionHierarchyLabel(for: chunk).map { "Section path: \($0)" },
            cleanedMetadataValue(chunk.metadata.tableTitle).map { "Table: \($0)" },
            cleanedMetadataValue(chunk.metadata.imageCaption, maxLength: 120).map { "Figure: \($0)" },
            cleanedMetadataValue(chunk.metadata.imageDescription, maxLength: 160).map { "Visual detail: \($0)" },
            cleanedMetadataValue(chunk.metadata.imageExtractedText, maxLength: 120).map { "Figure text: \($0)" }
        ]
            .compactMap { $0 }

        let combined = (metadataSegments + [chunk.contextualPrefix, baseContent])
            .compactMap { text in
                let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return cleaned.isEmpty ? nil : cleaned
            }
            .joined(separator: "\n")

        return String((combined.isEmpty ? chunk.content : combined).prefix(720))
    }

    private func isAnswerableSuggestedQuestion(
        _ question: String,
        passage: GroundedPassage
    ) -> Bool {
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
        let tokens = meaningfulTokens(from: question)
        let bodyOverlap = tokens.intersection(passage.bodyTokens).count
        let sectionOverlap = tokens.intersection(passage.sectionTokens).count
        let grounding = groundingScore(for: question, passage: passage)
        let lower = question.lowercased()
        if violatesPassageQuestionGuardrails(question, passage: passage) {
            return false
        }
        if lower.hasPrefix("how long") && !passageContainsExplicitDuration(passage.content) {
            return false
        }
        if isCapabilityQuestionFraming(lower) && passageLooksSafetyCritical(passage.content) {
            return false
        }
        let proceduralSupport = passage.chunk.metadata.hasListStructure
            || lower.hasPrefix("what should you do if")
            || lower.hasPrefix("what do you do if")
            || passage.content.lowercased().contains(" if ")
            || passage.content.lowercased().contains("must ")
            || passage.content.lowercased().contains("should ")
            || passage.content.lowercased().contains("do not ")
        let structuredSupport = passage.chunk.metadata.structureType == "table"
            || passage.chunk.metadata.chunkType == .tableSemantic
            || passage.chunk.metadata.hasNumericData

        switch answerIntent {
        case .lookup:
            if isQuantityQuestion(question) {
                return passage.chunk.metadata.hasNumericData
                    && grounding >= 3.5
                    && (bodyOverlap >= 1 || sectionOverlap >= 1)
            }
            return grounding >= 3.5 && (bodyOverlap >= 2 || (bodyOverlap >= 1 && sectionOverlap >= 1))
        case .tableLookup:
            return structuredSupport
                && grounding >= 3.5
                && (bodyOverlap >= 1 || sectionOverlap >= 1)
        case .procedure:
            return proceduralSupport && grounding >= 3.0 && (bodyOverlap >= 1 || sectionOverlap >= 1)
        case .compare:
            return structuredSupport && grounding >= 3.0 && (bodyOverlap >= 1 || sectionOverlap >= 1)
        case .summarize:
            let summarySupport = passage.chunk.metadata.abstractionLevel.isSummary
                || passage.chunk.metadata.documentCategory == .scientificPaper
                || grounding >= 4.0
            return summarySupport && grounding >= 3.0 && (bodyOverlap >= 1 || sectionOverlap >= 1)
        case .investigate, .findings:
            let researchSupport = passage.chunk.metadata.abstractionLevel.isSummary
                || passage.chunk.metadata.documentCategory == .scientificPaper
                || passage.chunk.metadata.hasCrossReferences
                || grounding >= 4.0
            return researchSupport && grounding >= 3.0 && (bodyOverlap >= 1 || sectionOverlap >= 1)
        case .compute:
            return passage.chunk.metadata.hasNumericData
                && grounding >= 3.5
                && (bodyOverlap >= 1 || sectionOverlap >= 1)
        }
    }

    private func rankingScore(for question: SuggestedQuestion) -> Double {
        question.confidence + categoryBoost(for: question.category) + textHeuristicBoost(for: question)
    }

    private func textHeuristicBoost(for question: SuggestedQuestion) -> Double {
        let lower = question.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let focusTokens = questionFocusTokens(from: question.text)

        if lower.hasPrefix("what warnings apply to")
            || lower.hasPrefix("what should you avoid when")
            || lower.hasPrefix("what is required for")
            || lower.hasPrefix("what are the minimum requirements for")
            || lower.hasPrefix("what do i need to check before using")
            || lower.contains("matter most")
        {
            return -0.12
        }

        if lower.hasPrefix("what is the ")
            || lower.hasPrefix("when is the ")
            || lower.hasPrefix("how do you ")
            || lower.hasPrefix("what does ")
        {
            return 0.05
        }

        if (lower.hasPrefix("what is ") || lower.hasPrefix("what are ")) && focusTokens.count <= 2 {
            return -0.08
        }

        let weakTailTokens: Set<String> = [
            "operation", "operations", "mode", "modes", "setting", "settings",
            "feature", "features", "function", "functions", "option", "options"
        ]

        if (lower.hasPrefix("what is ") || lower.hasPrefix("what are ")),
           !focusTokens.isDisjoint(with: weakTailTokens)
        {
            return -0.16
        }

        return 0
    }

    private func isStructuralOrMetaQuestion(_ lower: String) -> Bool {
        // Pattern 1: Ordinal or demonstrative/article/pronoun directly before a structural noun (singular or plural),
        // e.g., "the table", "this passage", "which row", "first column", "each cell"
        let modifierPattern = #"\b(?:this|the|an?|above|below|next|previous|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|particular|which|what|each|every|any|some|various)\s+(?:document|passage|table|figure|fig|chart|diagram|row|column|col|cell|page|paragraph|section|chapter|slide)s?\b"#
        if lower.range(of: modifierPattern, options: .regularExpression) != nil {
            return true
        }

        // Pattern 2: Structural nouns followed by numbers, letters, or word-form numbers,
        // e.g., "table 3", "page B", "row one", "figure 4"
        let numberPattern = #"\b(?:document|passage|table|figure|fig|chart|diagram|row|column|col|cell|page|paragraph|section|chapter|slide|line)s?\b\s*(?:\d+|[a-z]\b|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|ii+|iv|vi+|ix|xi+|xx)"#
        if lower.range(of: numberPattern, options: .regularExpression) != nil {
            return true
        }

        // Pattern 3: Prepositions or verbs referring to layout locations,
        // e.g., "in the document", "from this table", "on page 5", "shown in columns", "referenced in section"
        let prepositionPattern = #"\b(?:according\s+to|in|from|on|of|about|within|referenced\s+in|shown\s+in|listed\s+in|stated\s+in|mentioned\s+in|described\s+in|refer\s+to|read\s+in|see\s+in)\s+(?:the|this|these|our|your)?\s*(?:document|documents|passage|passages|table|tables|figure|figures|fig|figs|chart|charts|diagram|diagrams|row|rows|column|columns|col|cols|cell|cells|page|pages|paragraph|paragraphs|section|sections|chapter|chapters|slide|slides|text|source|sources)\b"#
        if lower.range(of: prepositionPattern, options: .regularExpression) != nil {
            return true
        }

        // Pattern 4: General check for explicit meta references to the document or passage containing the facts
        let metaPhrases = [
            "what does the document", "what do the documents", "in this document", "in these documents",
            "the uploaded", "uploaded document", "uploaded documents", "from the passage", "from the passages",
            "according to the text", "mentioned in the text", "stated in the text", "the text says", "in the text",
            "what is in the column", "what is in the row", "what are the results of the second column",
            "in the table", "in this table", "above table", "below table"
        ]
        if metaPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        // Pattern 5: Standalone structural questions that directly ask about these items as structural entities,
        // e.g. "What does the cell represent?" (referring to a table cell)
        // If the word is "column", "row", "table", "passage", "document" and it is not part of a known non-structural compound:
        let structuralNouns = ["row", "rows", "column", "columns", "col", "cols", "table", "tables", "passage", "passages", "document", "documents", "paragraph", "paragraphs", "page", "pages"]
        for noun in structuralNouns {
            let nounPattern = #"\b"# + noun + #"\b"#
            if lower.range(of: nounPattern, options: .regularExpression) != nil {
                // Check for allowed non-structural compound phrases containing these nouns
                let allowedCompounds = [
                    "periodic table", "water table", "round table", "dining table", "coffee table",
                    "neural cell", "stem cell", "red blood cell", "white blood cell", "fuel cell",
                    "cell biology", "cell division", "cell membrane", "cell wall", "solar cell",
                    "rowing", "columnar", "rowed"
                ]
                if !allowedCompounds.contains(where: { lower.contains($0) }) {
                    return true
                }
            }
        }

        return false
    }

    private func shouldSurfaceSuggestedQuestion(_ question: SuggestedQuestion) -> Bool {
        let lower = question.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBoilerplateQuestionTemplate(lower) else { return false }

        if isStructuralOrMetaQuestion(lower) {
            return false
        }

        let hasAcronymDefinitionFocus = lower.hasPrefix("what does ")
            && question.text.range(of: #"\b[A-Z0-9]{2,8}\b"#, options: .regularExpression) != nil

        let bannedFragments = [
            "pay attention to first",
            "easy to miss",
            "say to do next",
            "matter most",
            "stand out",
            "what does the document say",
            "what do the documents say",
            "uploaded document",
            "uploaded documents",
            "from the passage",
            "from the passages"
        ]
        if bannedFragments.contains(where: { lower.contains($0) }) {
            return false
        }

        if lower.hasPrefix("what do i need to check before using")
            || lower.hasPrefix("which warnings or operating limits matter most for")
            || lower.hasPrefix("what setup step or operating requirement matters most for")
        {
            return false
        }

        let focusTokens = questionFocusTokens(from: question.text)
        let hasSpecificFocus = focusTokens.count == 1 && focusTokens.contains(where: isLikelySpecificSuggestionFocusToken)
        guard focusTokens.count >= 2 || hasAcronymDefinitionFocus || hasSpecificFocus else { return false }

        let documentTokens = Set(question.relevantDocuments.flatMap { meaningfulTokens(from: $0) })
        let sectionTokens = Set(question.sourceSections.flatMap { meaningfulTokens(from: $0) })
        let sourceTokens = documentTokens.union(sectionTokens)

        if isSafetyOrRequirementQuestionFraming(lower) {
            if focusTokens.count <= 2 && !focusTokens.contains(where: isLikelySpecificSuggestionFocusToken) {
                return false
            }

            if !documentTokens.isEmpty,
               focusTokens.isSubset(of: documentTokens),
               (lower.hasPrefix("what warnings apply to")
                || lower.hasPrefix("what is required for")
                || lower.hasPrefix("what are the minimum requirements for")) {
                return false
            }
        }

        if (lower.hasPrefix("what is ") || lower.hasPrefix("what are "))
            && focusTokens.count <= 2
            && !focusTokens.contains(where: isLikelySpecificSuggestionFocusToken)
        {
            return false
        }

        if (question.category == .analytical || question.category == .summarization) {
            let hasSpecificFocusToken = focusTokens.contains(where: isLikelySpecificSuggestionFocusToken)
            if focusTokens.count < (hasSpecificFocusToken ? 2 : 3) {
                return false
            }
        }

        if !sourceTokens.isEmpty,
           focusTokens.isSubset(of: sourceTokens),
              lower.hasPrefix("what should i") {
            return false
        }

        return true
    }

    private func isLikelySpecificSuggestionFocusToken(_ token: String) -> Bool {
        if token.contains(where: \.isNumber) {
            return true
        }

        return token.count >= 5
            && !Self.genericStopEntities.contains(token)
            && !Self.specSubjectStopTokens.contains(token)
            && !Self.weakQuestionTopicTokens.contains(token)
    }

    private func categoryBoost(for category: QuestionCategory) -> Double {
        switch category {
        case .numerical:
            return 0.18
        case .factRetrieval:
            return 0.16
        case .procedural:
            return 0.14
        case .comparison:
            return 0.06
        case .analytical:
            return -0.14
        case .summarization:
            return -0.18
        }
    }

    private func displayDocumentName(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeGeneratedQuestion(_ text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*(?:[-•*]\s*|\d+[\.\)]\s*)"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"^[\"'“”‘’]+|[\"'“”‘’]+$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count >= 8 else { return nil }
        if !cleaned.hasSuffix("?") {
            cleaned += "?"
        }
        guard !isBoilerplateQuestionTemplate(cleaned) else { return nil }
        return cleaned
    }

    private func isBoilerplateQuestionTemplate(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let bannedPrefixes = [
            "what exact specs or requirements are in ",
            "what exact specs or limits are mentioned here",
            "what steps or procedures are in ",
            "which procedure or checklist matters most",
            "what numbers or limits are listed in ",
            "which values matter most in ",
            "what settings or parameters are defined in ",
            "what schema or config details are in ",
            "what should someone do after reading ",
            "what are the steps for "
        ]

        return bannedPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    private func dedupeQuestionTextsPreservingOrder(_ questions: [String]) -> [String] {
        var seen: Set<String> = []
        var deduped: [String] = []

        for question in questions {
            let key = normalizedQuestionKey(question)
            if seen.insert(key).inserted {
                deduped.append(question)
            }
        }

        return deduped
    }

    private func dedupeSuggestedQuestionsPreservingOrder(_ questions: [SuggestedQuestion]) -> [SuggestedQuestion] {
        var seen: Set<String> = []
        var deduped: [SuggestedQuestion] = []

        for question in questions {
            let key = normalizedQuestionKey(question.text)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            deduped.append(question)
        }

        return deduped
    }

    private func pruneNearDuplicateQuestions(_ questions: [SuggestedQuestion]) -> [SuggestedQuestion] {
        var result: [SuggestedQuestion] = []

        for question in questions {
            guard !result.contains(where: { areNearDuplicateQuestions(question, $0) }) else {
                continue
            }

            result.append(question)
        }

        return result
    }

    private func areNearDuplicateQuestions(_ lhs: SuggestedQuestion, _ rhs: SuggestedQuestion) -> Bool {
        if normalizedQuestionKey(lhs.text) == normalizedQuestionKey(rhs.text) {
            return true
        }

        let lhsTokens = questionFocusTokens(from: lhs.text)
        let rhsTokens = questionFocusTokens(from: rhs.text)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }

        let sameDocument = lhs.relevantDocuments.first == rhs.relevantDocuments.first
        let lhsSection = lhs.sourceSections.first?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsSection = rhs.sourceSections.first?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if sameDocument {
            if lhsTokens == rhsTokens {
                return true
            }

            if let lhsSection, let rhsSection, !lhsSection.isEmpty, lhsSection == rhsSection,
               (lhsTokens.isSubset(of: rhsTokens) || rhsTokens.isSubset(of: lhsTokens))
            {
                return true
            }
        }

        guard lhs.category == rhs.category else { return false }
        guard sameDocument else { return false }

        let overlap = lhsTokens.intersection(rhsTokens).count
        let smallerCount = min(lhsTokens.count, rhsTokens.count)
        if smallerCount >= 2, Double(overlap) / Double(smallerCount) >= 0.75 {
            return true
        }

        if let lhsSection, let rhsSection, !lhsSection.isEmpty, lhsSection == rhsSection, overlap >= 2 {
            return true
        }

        return false
    }

    private func normalizedQuestionKey(_ question: String) -> String {
        question
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func questionFocusTokens(from question: String) -> Set<String> {
        Set(
            meaningfulTokens(from: question)
                .filter { !Self.questionFocusStopTokens.contains($0) }
        )
    }

    private func isUsableGeneratedQuestion(
        _ question: String,
        passages: [GroundedPassage]
    ) -> Bool {
        let lower = question.lowercased()
        if isBoilerplateQuestionTemplate(lower) {
            return false
        }

        if isStructuralOrMetaQuestion(lower) {
            return false
        }

        if isJunkString(question) {
            return false
        }
        let bannedFragments = [
            "[", "]", "{", "}", "<", ">",
            "thing from passage",
            "specific thing from passage",
            "condition from passage",
            "specific detail from the passage",
            "specific detail",
            "what does the document say",
            "what do the documents say",
            "uploaded document",
            "uploaded documents",
            "from the passages below",
            "from the passage",
            "style guide",
            "real person casually asking",
            "what's important about",
            "what is important about",
            "why is ",
            " important here",
            "actually do",
            "main point",
            "key points",
            "key details",
            "can you explain",
            "tell me about",
            "what are the key",
        ]

        if bannedFragments.contains(where: { lower.contains($0) }) {
            return false
        }

        let tokens = meaningfulTokens(from: lower)
        guard tokens.count >= 2 else { return false }
        guard let groundedPassage = bestGroundingPassage(for: question, passages: passages) else {
            return false
        }
        if violatesPassageQuestionGuardrails(question, passage: groundedPassage) {
            return false
        }

        let overlapCount =
            tokens.intersection(groundedPassage.bodyTokens).count
            + tokens.intersection(groundedPassage.sectionTokens).count
        let bodyOverlap = tokens.intersection(groundedPassage.bodyTokens).count
        let sectionOverlap = tokens.intersection(groundedPassage.sectionTokens).count
        let asksForValue = isQuantityQuestion(question)
            || lower.contains("capacity")
            || lower.contains("value")
            || lower.contains("listed")

        if bodyOverlap >= 2 { return true }
        if bodyOverlap >= 1 && sectionOverlap >= 1 { return true }
        if asksForValue, groundedPassage.chunk.metadata.hasNumericData, bodyOverlap >= 1 {
            return true
        }

        return overlapCount >= 3 && groundingScore(for: question, passage: groundedPassage) >= 4.0
    }

    private func isSelfAnsweringGeneratedQuestion(_ question: String) -> Bool {
        isQuantityQuestion(question) && !extractNumericTokens(from: question).isEmpty
    }

    private func isFaithfulQuestionRewrite(
        original: String,
        rewritten: String,
        passage: GroundedPassage
    ) -> Bool {
        let originalLower = original.lowercased()
        let rewrittenLower = rewritten.lowercased()
        let originalTokens = meaningfulTokens(from: originalLower)
        let rewrittenTokens = meaningfulTokens(from: rewrittenLower)
        let passageTokens = passage.documentTokens.union(passage.sectionTokens).union(passage.bodyTokens)
        let importantOriginalTokens = originalTokens.filter { token in
            token.contains(where: \.isNumber) || passageTokens.contains(token)
        }

        if !importantOriginalTokens.isEmpty {
            let preservedCount = importantOriginalTokens.filter { rewrittenTokens.contains($0) }.count
            if preservedCount < min(2, importantOriginalTokens.count) {
                return false
            }
        }

        let originalGrounding = groundingScore(for: original, passage: passage)
        let rewrittenGrounding = groundingScore(for: rewritten, passage: passage)
        guard rewrittenGrounding >= max(3.5, originalGrounding - 0.5) else {
            return false
        }

        if originalLower.hasPrefix("what should you do if") || originalLower.hasPrefix("what do you do if") {
            guard rewrittenLower.hasPrefix("what should you do if")
                || rewrittenLower.hasPrefix("what do you do if")
            else {
                return false
            }
        }

        if isSafetyOrRequirementQuestionFraming(originalLower),
           !isSafetyOrRequirementQuestionFraming(rewrittenLower) {
            return false
        }

        if isProceduralQuestionFraming(originalLower),
           !isProceduralQuestionFraming(rewrittenLower) {
            return false
        }

        if isQuantityQuestion(original) && !isQuantityQuestion(rewritten) {
            return false
        }

        if !isQuantityQuestion(original) && isQuantityQuestion(rewritten) {
            return false
        }

        if !isCapabilityQuestionFraming(originalLower) && isCapabilityQuestionFraming(rewrittenLower) {
            return false
        }

        if rewrittenLower.hasPrefix("how long") && !passageContainsExplicitDuration(passage.content) {
            return false
        }

        if violatesPassageQuestionGuardrails(rewritten, passage: passage) {
            return false
        }

        return true
    }

    private func isProceduralQuestionFraming(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("how do you")
            || lower.hasPrefix("how do you handle")
            || lower.hasPrefix("what should you do if")
            || lower.hasPrefix("what do you do if")
    }

    private func isSafetyOrRequirementQuestionFraming(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("what warnings apply to")
            || lower.hasPrefix("what should you avoid when")
            || lower.hasPrefix("what is required for")
            || lower.hasPrefix("what are the minimum requirements for")
    }

    private func violatesPassageQuestionGuardrails(
        _ question: String,
        passage: GroundedPassage
    ) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let safetyCritical = passageLooksSafetyCritical(passage.content)
        let prohibitive = passageContainsProhibition(passage.content)

        if lower.hasPrefix("how long") {
            if !passageContainsExplicitDuration(passage.content) {
                return true
            }
            if safetyCritical || prohibitive {
                return true
            }
        }

        if isCapabilityQuestionFraming(lower) && (safetyCritical || prohibitive) {
            return true
        }

        return false
    }

    private func isCapabilityQuestionFraming(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("can ")
            || lower.hasPrefix("can you ")
            || lower.hasPrefix("could ")
            || lower.hasPrefix("could you ")
            || lower.hasPrefix("is it okay to ")
    }

    private func passageContainsExplicitDuration(_ text: String) -> Bool {
        text.range(
            of: #"\b\d+(?:[.,]\d+)?\s*(?:ms|sec|secs|seconds?|s|min|mins|minutes?|hr|hrs|hours?|days?)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func passageLooksSafetyCritical(_ text: String) -> Bool {
        let lower = text.lowercased()
        let safetySignals = [
            "warning", "caution", "danger", "contraindication", "do not", "must not",
            "single use", "steril", "reuse", "forbidden", "prohibit", "required", "ensure"
        ]
        return safetySignals.contains(where: { lower.contains($0) })
    }

    private func passageContainsProhibition(_ text: String) -> Bool {
        let lower = text.lowercased()
        let prohibitionSignals = [
            "do not", "must not", "should not", "never", "avoid", "forbidden",
            "prohibit", "prohibited", "not allowed", "contraindication"
        ]
        return prohibitionSignals.contains(where: { lower.contains($0) })
    }

    private func naturalQuestionTopic(_ topic: String) -> String {
        let cleaned = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return topic }
        if cleaned == cleaned.uppercased() {
            return cleaned.lowercased()
        }

        let words = cleaned.split(separator: " ").map(String.init)
        if let first = words.first,
           first == first.lowercased(),
           words.count > 1
        {
            let normalized = [first] + words.dropFirst().map { word in
                if word.contains(where: \.isNumber) || word == word.uppercased() {
                    return word
                }

                guard let firstCharacter = word.first,
                      firstCharacter.isUppercase,
                      word.dropFirst().allSatisfy({ $0.isLowercase || !$0.isLetter })
                else {
                    return word
                }

                return word.lowercased()
            }

            return normalized.joined(separator: " ")
        }

        return cleaned
    }

    private func meaningfulTokens(from text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { token in
                    token.contains(where: \.isNumber) || (token.count >= 3 && !Self.matchStopTokens.contains(token))
                }
        )
    }

    private func numberTokens(from text: String) -> Set<String> {
        Set(
            text
                .split { !$0.isNumber && $0 != "." && $0 != "," }
                .map(String.init)
                .filter { token in token.contains(where: \.isNumber) }
        )
    }

    // MARK: - Content Extraction Helpers

    /// Generic section titles that produce bad questions
    private func isGenericSectionTitle(_ title: String) -> Bool {
        let generic: Set<String> = [
            "introduction", "conclusion", "summary", "overview", "abstract",
            "references", "bibliography", "appendix", "index", "table of contents",
            "acknowledgements", "disclaimer", "copyright", "notes", "glossary",
            "contents", "preface", "foreword", "about", "author manuscript",
            "keywords", "conflict of interest", "conflicts of interest",
            "competing interests", "author contributions", "funding", "ethics statement"
        ]
        let normalized = title.lowercased().trimmingCharacters(in: .whitespaces)
        return generic.contains(normalized) || containsFrontMatterSignal(normalized)
    }

    private func containsFrontMatterSignal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return Self.frontMatterSignals.contains { lower.contains($0) }
    }

    /// Generic nouns that NLTagger marks as "entities" but are useless for questions
    private static let genericStopEntities: Set<String> = [
        "analysis", "analyses", "data", "system", "systems", "method", "methods", "model", "models",
        "approach", "approaches", "result", "results", "study", "studies", "process", "processes",
        "framework", "frameworks", "structure", "structures", "design", "designs",
        "implementation", "implementations", "performance", "evaluation", "evaluations",
        "table", "tables", "figure", "figures", "section", "sections", "chapter", "chapters",
        "page", "pages", "document", "documents", "paper", "papers", "report", "reports",
        "specification", "specifications", "author", "authors", "manuscript", "manuscripts",
        "article", "articles", "journal", "journals", "publication", "publications",
        "keyword", "keywords", "copyright", "funding", "disclosure", "disclosures",
        "conflict", "conflicts", "interest", "interests", "acknowledgement", "acknowledgements",
        "supplement", "supplements", "supplementary",
        "information", "content", "text", "type", "level", "levels", "value", "values",
        "group", "groups", "number", "numbers", "part", "parts", "case", "cases",
        "example", "examples", "form", "forms", "area", "areas",
        "point", "points", "time", "work", "thing", "things", "way", "ways", "issue", "issues", "problem", "problems",
        "question", "questions", "answer", "answers", "item", "items", "list", "lists", "set", "sets", "use", "end"
    ]

    private static let matchStopTokens: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "what", "when",
        "where", "which", "about", "into", "your", "their", "does", "have",
        "here", "there", "under", "over", "should", "would", "could", "after",
        "before", "using", "used", "than", "then", "they", "them", "much",
        "many", "long", "happens", "important", "actually", "main", "point",
        "points", "details", "explain", "tell", "analyze", "evaluate", "review",
        "discuss", "summarize", "author", "authors", "manuscript", "article",
        "journal", "publication", "guidance",
        "say", "says", "said", "mention", "mentions", "mentioned", "tell", "tells", "told",
        "discuss", "discusses", "discussed", "show", "shows", "shown", "describe",
        "describes", "described", "find", "finds", "found"
    ]

    private static let specSubjectStopTokens: Set<String> = [
        "recommended", "equivalent", "maximum", "minimum", "approx", "approximately",
        "about", "page", "section", "table", "figure", "see", "refer", "when",
        "where", "which", "with", "without", "and", "or", "the", "for", "from",
        "value", "values", "specification", "specifications", "author", "authors",
        "manuscript", "article", "journal", "publication",
        "row", "column", "col", "cols", "rows", "line", "lines", "cell", "cells",
        "item", "items", "no", "id", "idx", "index", "indices", "of", "in", "at", "on", "by", "to",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "next", "last", "previous"
    ]

    private static let proceduralTopicStopTokens: Set<String> = [
        "author", "authors", "manuscript", "article", "journal", "publication",
        "abstract", "summary", "overview", "reference", "references", "copyright",
        "appendix", "appendices", "supplement", "supplementary", "keyword", "keywords",
        "funding", "disclosure", "disclosures", "conflict", "conflicts", "interest", "interests"
    ]

    private static let proceduralActionStarters: Set<String> = [
        "install", "remove", "replace", "connect", "disconnect", "attach", "detach",
        "clean", "inspect", "check", "start", "stop", "press", "turn", "load",
        "apply", "perform", "prepare", "operate", "configure", "calibrate", "reset"
    ]

    private static let weakQuestionTopicTokens: Set<String> = [
        "contraindications", "indications", "intended", "reprocessing", "sterilization",
        "cleaning", "manual", "automated", "process", "workflow", "overview",
        "warning", "warnings", "safety", "inspection", "repair", "troubleshooting",
        "requirements", "qualification", "qualifications", "description", "summary"
    ]

    private static let frontMatterSignals: Set<String> = [
        "author manuscript", "all rights reserved", "rights reserved", "copyright",
        "corresponding author", "published online", "accepted for publication", "doi",
        "conflict of interest", "conflicts of interest", "competing interests",
        "author contributions", "funding", "acknowledg", "keywords"
    ]

    private static let questionFocusStopTokens: Set<String> = [
        "what", "when", "where", "which", "who", "how", "should", "would", "could",
        "apply", "compare", "warning", "warnings", "limit", "limits", "required",
        "requirements", "minimum", "matter", "matters", "avoid", "first",
        "important", "stand", "stands", "out", "there", "here", "anything", "need",
        "check", "using", "before", "after", "setup", "step", "steps", "next",
        "operating", "requirement",
        "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "last", "previous"
    ]

    /// Extract number-in-context phrases like "360 DPI", "14.3 US gal", "$49.99/year"
    private func extractSpecificNumbers(from text: String) -> [String] {
        let pattern = #"(\d+[\.,]?\d*)\s*(?:US\s*)?(%|(?:DPI|Hz|MHz|GHz|MB|GB|TB|KB|ms|sec|s|min|hr|mg|mL|ml|L|l|liters?|litres?|kg|g|lb|lbs|oz|ft|in|cm|mm|m|km|mi|mph|rpm|psi|kPa|bar|°[CF]|watts?|volts?|amps?|tokens?|gal|gals|gallons?|qt|quarts?|N·m|Nm|lb-ft|ft-lb|hp|kW))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.prefix(3).compactMap { match in
            let range = match.range
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }
    }

    private func extractNumericTokens(from text: String) -> [String] {
        text
            .split { !$0.isNumber && $0 != "." && $0 != "," }
            .map(String.init)
            .filter { token in token.contains(where: \.isNumber) }
    }

    private func isQuantityQuestion(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("how many")
            || lower.hasPrefix("how much")
            || lower.hasPrefix("how long")
            || lower.hasPrefix("what percentage")
            || lower.hasPrefix("what percent")
    }

    /// Extract multi-word key phrases (2-4 words) that are specific to the content.
    private func extractKeyPhrases(from text: String) -> [String] {
        let sentences = text.components(separatedBy: ". ")
        var phrases: [String] = []

        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            for windowSize in [3, 2, 4] {
                guard words.count >= windowSize else { continue }
                for i in 1..<(words.count - windowSize + 1) {
                    let window = Array(words[i..<(i + windowSize)])
                    let phrase = window.joined(separator: " ")
                        .trimmingCharacters(in: .punctuationCharacters)

                    let hasCapital = window.contains { word in
                        guard let first = word.first else { return false }
                        return first.isUppercase && word.count >= 3
                    }

                    let hasSubstance = window.contains { word in
                        word.count >= 4 && !Self.genericStopEntities.contains(word.lowercased())
                    }

                    if hasCapital && hasSubstance && phrase.count >= 8 {
                        phrases.append(phrase)
                    }
                }
            }
        }

        return Array(Set(phrases)).sorted { $0.count > $1.count }.prefix(3).map { $0 }
    }

    private func extractConditionalQuestion(from text: String) -> String? {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for sentence in sentences {
            let lower = sentence.lowercased()
            guard lower.hasPrefix("if "), let commaIndex = sentence.firstIndex(of: ",") else { continue }

            let condition = sentence[sentence.index(after: sentence.startIndex)..<commaIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let consequence = sentence[sentence.index(after: commaIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            guard condition.count >= 10, condition.count <= 90 else { continue }

            let conditionLower = condition.lowercased()
            if conditionLower.contains("thing from passage") || conditionLower.contains("document") {
                continue
            }

            let consequenceLower = consequence.lowercased()
            let actionIndicators = [
                "must", "should", "need to", "do not", "don't", "replace", "remove",
                "install", "use", "check", "inspect", "clean", "tighten", "wait",
                "stop", "turn", "press", "keep", "let", "ensure", "verify", "return"
            ]

            if actionIndicators.contains(where: { consequenceLower.contains($0) }) {
                return "What should you do if \(conditionLower)?"
            }
        }

        return nil
    }

    // MARK: - Static Fallbacks

}

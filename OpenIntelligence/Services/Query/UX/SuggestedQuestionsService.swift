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
/// 4. Fall back to safe generic chat starters instead of fake-specific questions
///
/// **Why this is 10x:**
/// - Questions are generated FROM the actual text, not from loose entity labels
/// - "What is Analysis?" → "What is the fuel tank capacity?"
/// - Diversity is enforced at the chunk selection level, not post-hoc filtering
/// - Cache invalidates on document change, not never

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

        // Collect previously-shown questions so refresh can avoid repeats
        let previousTexts: [String] = forceRefresh
            ? (cachedQuestions[containerId]?.questions.map { $0.text } ?? [])
            : []

        // Check cache — but only if not forcing refresh, doc count unchanged, and cache fresh
        if !forceRefresh,
           let cached = cachedQuestions[containerId],
           cached.documentCount == documents.count,
           Date().timeIntervalSince(cached.generatedAt) < Self.cacheMaxAge,
           !cached.questions.isEmpty {
            Log.debug("[SuggestedQuestions] Returning \(cached.questions.count) cached questions for container")
            return Array(cached.questions.prefix(count))
        }

        guard !sampleChunks.isEmpty else {
            Log.debug("[SuggestedQuestions] No chunks available, returning empty")
            return []
        }

        // Step 1: Select diverse representative chunks
        // On refresh, shuffle the input to get different chunks for variety
        let inputChunks = forceRefresh ? sampleChunks.shuffled() : sampleChunks
        let diverseChunks = selectDiverseChunks(from: inputChunks, documents: documents, targetCount: 6)

        // Step 2: Build deterministic passage-grounded questions first.
        // The LLM can add variety, but these are the reliability floor.
        var questions: [SuggestedQuestion] = []
        let contentQuestions = generateFromContent(chunks: diverseChunks, documents: documents)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), !contentQuestions.isEmpty {
            let llmQuestions = await generateWithLLM(
                baseQuestions: contentQuestions,
                chunks: diverseChunks,
                documents: documents,
                avoidTexts: previousTexts
            )
            questions = llmQuestions.isEmpty
                ? contentQuestions
                : dedupeSuggestedQuestionsPreservingOrder(llmQuestions)
        }
        #endif

        // Step 3: Fall back to content-grounded extraction if LLM failed or unavailable
        if questions.isEmpty {
            questions = contentQuestions
        }

        // Step 4: Ensure diversity — no two questions from the same document
        let deduped = enforceDiversity(
            dedupeSuggestedQuestionsPreservingOrder(questions),
            count: max(count, 6)
        )
        let supplemented = supplementWithDocumentFallbacks(
            deduped,
            documents: documents,
            targetCount: max(count, 6)
        )

        // Cache
        cachedQuestions[containerId] = CachedEntry(
            questions: supplemented,
            documentCount: documents.count,
            generatedAt: Date()
        )
        Log.info("[SuggestedQuestions] Generated \(supplemented.count) questions for container (refresh: \(forceRefresh))")

        return Array(supplemented.prefix(count))
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
        if chunk.metadata.sectionTitle != nil { score += 1.0 }

        // Has list structure (procedures, specifications, comparisons)
        if chunk.metadata.hasListStructure { score += 1.5 }

        // Structured document content (tables, lists) — richer than plain paragraphs
        if let structType = chunk.metadata.structureType, structType != "paragraph" {
            score += 2.0
        }

        // Penalize very short chunks (likely headers or fragments)
        if wc < 15 { score -= 5.0 }

        // Down-rank boilerplate/front-matter chunks so research PDFs don't
        // produce junk prompts from copyright or author-manuscript text.
        score += frontMatterAdjustment(for: chunk)

        return score
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
        if let section = primarySectionLabel(for: chunk), isGenericSectionTitle(section) {
            return -5.0
        }

        let lower = groundedPassageContent(for: chunk).lowercased()
        if containsFrontMatterSignal(lower) {
            return -4.0
        }

        return 0
    }

    private func primarySectionLabel(for chunk: DocumentChunk) -> String? {
        if let section = chunk.metadata.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !section.isEmpty {
            return section
        }
        if let pathSection = chunk.metadata.sectionPath?.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pathSection.isEmpty {
            return pathSection
        }
        return nil
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

    private enum FallbackPromptProfile {
        case spreadsheet
        case media
        case code
        case research
        case manual
        case general
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

        let rewriteTargets = baseQuestions.compactMap { question -> (SuggestedQuestion, GroundedPassage)? in
            guard let groundedPassage = bestGroundingPassage(for: question.text, passages: passages) else {
                return nil
            }
            return (question, groundedPassage)
        }
        let limitedTargets = Array(rewriteTargets.prefix(6))
        guard limitedTargets.count >= 2 else { return [] }

        let candidateText = limitedTargets.enumerated().map { index, target in
            let question = target.0
            let passage = target.1
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
        - Do NOT ask about the documents themselves
        - Do NOT include square brackets, placeholders, bullets, numbering, or quotes
        - Return the SAME NUMBER of questions in the SAME ORDER as the candidates below
        \(avoidClause)
        CANDIDATES:
        \(candidateText)

        Return ONLY plain question strings through the schema. Do not number them. Do not add bullets or quotes.
        """

        do {
            let session = LanguageModelSession()
            // @Generable: typed [String] array — eliminates numbered-line regex parsing.
            // Constrained sampling enforces the declared schema at the token level.
            let response = try await session.respond(to: prompt, generating: SuggestedQuestionList.self)
            let rewrittenTexts = response.content.questions.compactMap { sanitizeGeneratedQuestion($0) }
            guard rewrittenTexts.count == limitedTargets.count else {
                Log.warning("[SuggestedQuestions] LLM rewrite count mismatch (\(rewrittenTexts.count) vs \(limitedTargets.count))")
                return []
            }

            let questions = zip(limitedTargets, rewrittenTexts).map { target, rewrittenText in
                let original = target.0
                let groundedPassage = target.1

                guard isFaithfulQuestionRewrite(original: original.text, rewritten: rewrittenText, passage: groundedPassage),
                      isUsableGeneratedQuestion(rewrittenText, passages: [groundedPassage]),
                      !isSelfAnsweringGeneratedQuestion(rewrittenText),
                      isAnswerableSuggestedQuestion(rewrittenText, passage: groundedPassage)
                else {
                    return original
                }

                return SuggestedQuestion(
                    id: UUID(),
                    text: rewrittenText,
                    category: original.category,
                    relevantDocuments: original.relevantDocuments,
                    sourceSections: original.sourceSections,
                    confidence: max(original.confidence, groundedConfidence(for: rewrittenText, passage: groundedPassage))
                )
            }

            let deduped = dedupeSuggestedQuestionsPreservingOrder(questions)
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
    #endif

    // MARK: - Step 3: Content-Grounded Fallback (no LLM)

    /// Generate questions from actual chunk content when LLM is unavailable.
    /// Extracts key phrases and specific details — NOT single-word entities.
    private func generateFromContent(
        chunks: [DocumentChunk],
        documents: [Document]
    ) -> [SuggestedQuestion] {

        var questions: [SuggestedQuestion] = []
        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: chunks.count)

        for passage in passages {
            for draft in deterministicQuestionDrafts(for: passage) {
                let questionText = draft.text.hasSuffix("?") ? draft.text : draft.text + "?"
                guard isUsableGeneratedQuestion(questionText, passages: [passage]),
                      !isSelfAnsweringGeneratedQuestion(questionText),
                      isAnswerableSuggestedQuestion(questionText, passage: passage)
                else {
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

        // If we cannot make source-grounded suggestions, return nothing and let the
        // chat screen show safe generic starter prompts instead of fake specificity.
        return dedupeSuggestedQuestionsPreservingOrder(questions)
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

        if let conditionalQuestion = extractConditionalQuestion(from: passage.content) {
            drafts.append(QuestionDraft(
                text: conditionalQuestion,
                category: conditionalQuestion.lowercased().hasPrefix("what should you do if") ? .procedural : .analytical,
                confidence: 0.88
            ))
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

        if let tableQuestion = extractTableTopicQuestion(from: passage) {
            drafts.append(QuestionDraft(
                text: tableQuestion,
                category: .factRetrieval,
                confidence: 0.82
            ))
        }

        return drafts
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
        guard let topic = concreteTopic(from: passage.sectionName ?? passage.chunk.metadata.tableTitle) else {
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
                return lower.count >= 2 && !Self.specSubjectStopTokens.contains(lower)
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

    private func concreteTopic(from text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard cleaned.count >= 4,
              cleaned.count <= 80,
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

    private func isGenericQuestionTopic(_ topic: String) -> Bool {
        let tokens = meaningfulTokens(from: topic)
        guard !tokens.isEmpty else { return true }
        if tokens.count == 1, let only = tokens.first {
            return Self.genericStopEntities.contains(only) || Self.specSubjectStopTokens.contains(only)
        }
        return tokens.allSatisfy { Self.genericStopEntities.contains($0) || Self.specSubjectStopTokens.contains($0) }
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

    private func supplementWithDocumentFallbacks(
        _ questions: [SuggestedQuestion],
        documents: [Document],
        targetCount: Int
    ) -> [SuggestedQuestion] {
        guard questions.count < targetCount else { return questions }

        let fallbackQuestions = documentAwareFallbackQuestions(from: documents)
        let merged = dedupeSuggestedQuestionsPreservingOrder(questions + fallbackQuestions)
        return Array(merged.prefix(targetCount))
    }

    private func documentAwareFallbackQuestions(from documents: [Document]) -> [SuggestedQuestion] {
        let sortedDocs = documents.sorted {
            if $0.totalChunks == $1.totalChunks {
                return $0.addedAt > $1.addedAt
            }
            return $0.totalChunks > $1.totalChunks
        }

        var fallbackQuestions: [SuggestedQuestion] = []

        for document in sortedDocs.prefix(3) {
            let documentName = displayDocumentName(document.filename)
            guard !documentName.isEmpty else { continue }

            for candidate in Self.fallbackCandidates(for: document, documentName: documentName) {
                fallbackQuestions.append(SuggestedQuestion(
                    id: UUID(),
                    text: candidate.text,
                    category: candidate.category,
                    relevantDocuments: [documentName],
                    sourceSections: [],
                    confidence: candidate.confidence
                ))
            }
        }

        return fallbackQuestions
    }

    private static func fallbackCandidates(
        for document: Document,
        documentName: String
    ) -> [(text: String, category: QuestionCategory, confidence: Double)] {
        let profile = Self.fallbackPromptProfile(for: document, documentName: documentName)
        let topics = Self.fallbackTopicPhrases(for: document, documentName: documentName)
        let hasStructuredSignals = Self.hasStructuredReferenceSignals(for: document)

        var candidates: [(text: String, category: QuestionCategory, confidence: Double)] = []

        for topic in topics.prefix(2) {
            candidates.append(contentsOf: Self.topicDrivenFallbackCandidates(
                profile: profile,
                topic: topic,
                documentName: documentName,
                hasStructuredSignals: hasStructuredSignals
            ))
        }

        if candidates.count < 3 {
            candidates.append(contentsOf: Self.genericFallbackCandidates(
                profile: profile,
                documentName: documentName,
                hasStructuredSignals: hasStructuredSignals
            ))
        }

        return Array(Self.dedupeFallbackCandidates(candidates).prefix(3))
    }

    static func starterFallbackPrompts(for document: Document, documentName: String) -> [String] {
        Self.fallbackCandidates(for: document, documentName: documentName).map(\.text)
    }

    private static func topicDrivenFallbackCandidates(
        profile: FallbackPromptProfile,
        topic: String,
        documentName: String,
        hasStructuredSignals: Bool
    ) -> [(text: String, category: QuestionCategory, confidence: Double)] {
        switch profile {
        case .spreadsheet:
            return [
                ("Which values in \(documentName) matter most for \(topic)?", .numerical, 0.61),
                ("Are there thresholds, outliers, or deltas around \(topic) in \(documentName)?", .numerical, 0.58),
                ("What changed most around \(topic) in \(documentName)?", .analytical, 0.55),
            ]
        case .media:
            return [
                ("What did people decide about \(topic) in \(documentName)?", .procedural, 0.61),
                ("What follow-up around \(topic) is mentioned in \(documentName)?", .procedural, 0.58),
                ("What still sounds unresolved about \(topic) in \(documentName)?", .analytical, 0.55),
            ]
        case .code:
            return [
                ("Where is \(topic) defined or configured in \(documentName)?", .factRetrieval, 0.61),
                ("What would changing \(topic) affect in \(documentName)?", .analytical, 0.58),
                ("Which setting tied to \(topic) is easiest to miss in \(documentName)?", .factRetrieval, 0.55),
            ]
        case .research:
            return [
                ("What does \(documentName) actually say about \(topic)?", .factRetrieval, 0.61),
                ("What result or evidence around \(topic) matters most in \(documentName)?", .analytical, 0.58),
                ("What caveats or limits around \(topic) show up in \(documentName)?", .analytical, 0.55),
            ]
        case .manual:
            let firstQuestion: (text: String, category: QuestionCategory, confidence: Double)
            if hasStructuredSignals {
                firstQuestion = ("Which specs or limits for \(topic) should I check in \(documentName)?", .factRetrieval, 0.61)
            } else {
                firstQuestion = ("What does \(documentName) say to do with \(topic)?", .procedural, 0.61)
            }

            return [
                firstQuestion,
                ("Are there any warnings or edge cases around \(topic) in \(documentName)?", .analytical, 0.58),
                ("What should I verify first about \(topic) in \(documentName)?", .factRetrieval, 0.55),
            ]
        case .general:
            let firstQuestion: (text: String, category: QuestionCategory, confidence: Double)
            if hasStructuredSignals {
                firstQuestion = ("Which numbers or limits around \(topic) stand out in \(documentName)?", .numerical, 0.61)
            } else {
                firstQuestion = ("What should I understand first about \(topic) in \(documentName)?", .factRetrieval, 0.61)
            }

            return [
                firstQuestion,
                ("What detail about \(topic) is easy to miss in \(documentName)?", .analytical, 0.58),
                ("What does \(documentName) make clear about \(topic)?", .factRetrieval, 0.55),
            ]
        }
    }

    private static func genericFallbackCandidates(
        profile: FallbackPromptProfile,
        documentName: String,
        hasStructuredSignals: Bool
    ) -> [(text: String, category: QuestionCategory, confidence: Double)] {
        switch profile {
        case .spreadsheet:
            return [
                ("Which specs, values, or deltas in \(documentName) matter most?", .numerical, 0.56),
                ("Where are the thresholds or outliers in \(documentName)?", .numerical, 0.53),
                ("What changed most inside \(documentName)?", .analytical, 0.50),
            ]
        case .media:
            return [
                ("What decisions or follow-up items came out of \(documentName)?", .procedural, 0.56),
                ("What does \(documentName) leave unresolved?", .analytical, 0.53),
                ("What should I act on after reading \(documentName)?", .procedural, 0.50),
            ]
        case .code:
            return [
                ("Which config or constant in \(documentName) is easiest to miss?", .factRetrieval, 0.56),
                ("What does \(documentName) actually control?", .factRetrieval, 0.53),
                ("What in \(documentName) looks risky to change?", .analytical, 0.50),
            ]
        case .research:
            return [
                ("What result in \(documentName) actually matters?", .factRetrieval, 0.56),
                ("What evidence in \(documentName) feels strongest?", .analytical, 0.53),
                ("What caveat or limitation should I keep in mind from \(documentName)?", .analytical, 0.50),
            ]
        case .manual:
            let firstQuestion: (text: String, category: QuestionCategory, confidence: Double)
            if hasStructuredSignals {
                firstQuestion = ("Which step, spec, or limit in \(documentName) should I check first?", .factRetrieval, 0.56)
            } else {
                firstQuestion = ("Which step or warning in \(documentName) should I check first?", .factRetrieval, 0.56)
            }

            return [
                firstQuestion,
                ("What does \(documentName) say to verify before moving on?", .procedural, 0.53),
                ("What detail in \(documentName) is easiest to miss?", .analytical, 0.50),
            ]
        case .general:
            let firstQuestion: (text: String, category: QuestionCategory, confidence: Double)
            if hasStructuredSignals {
                firstQuestion = ("Which specs, values, or limits in \(documentName) matter most?", .numerical, 0.56)
            } else {
                firstQuestion = ("Which part of \(documentName) deserves attention first?", .factRetrieval, 0.56)
            }

            return [
                firstQuestion,
                ("What in \(documentName) is easiest to miss the first time through?", .analytical, 0.53),
                ("What numbers, constraints, or tradeoffs stand out in \(documentName)?", .factRetrieval, 0.50),
            ]
        }
    }

    private static func fallbackTopicPhrases(for document: Document, documentName: String) -> [String] {
        var phrases: [String] = []

        if let tags = document.contentTags {
            phrases.append(contentsOf: tags.compactMap(Self.sanitizedFallbackTopic))
        }

        phrases.append(contentsOf: Self.filenameTopicPhrases(from: documentName))

        var seen: Set<String> = []
        return phrases.filter { phrase in
            seen.insert(phrase.lowercased()).inserted
        }
    }

    private static func filenameTopicPhrases(from documentName: String) -> [String] {
        let words = Self.humanizedDocumentName(documentName)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { token in
                let lower = token.lowercased()
                return lower.count >= 3
                    && !Self.genericStopEntities.contains(lower)
                    && !Self.matchStopTokens.contains(lower)
                    && !Self.researchFilenameSignals.contains(lower)
                    && !Self.manualFilenameSignals.contains(lower)
                    && !Self.filenameTopicNoiseTokens.contains(lower)
            }

        guard !words.isEmpty else { return [] }

        var candidates: [String] = []
        if words.count >= 2 {
            candidates.append(words.prefix(2).joined(separator: " "))
        }
        if words.count >= 3 {
            candidates.append(words.prefix(3).joined(separator: " "))
        }
        candidates.append(words[0])

        return candidates.compactMap(Self.sanitizedFallbackTopic)
    }

    private static func sanitizedFallbackTopic(_ rawValue: String) -> String? {
        let words = Self.humanizedDocumentName(rawValue)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { token in
                let lower = token.lowercased()
                return lower.count >= 3
                    && !Self.genericStopEntities.contains(lower)
                    && !Self.matchStopTokens.contains(lower)
                    && !Self.researchFilenameSignals.contains(lower)
                    && !Self.manualFilenameSignals.contains(lower)
                    && !Self.filenameTopicNoiseTokens.contains(lower)
            }

        guard !words.isEmpty else { return nil }
        return words.prefix(3).joined(separator: " ")
    }

    private static func hasStructuredReferenceSignals(for document: Document) -> Bool {
        if document.contentType == .excel || document.contentType == .numbers || document.contentType == .csv {
            return true
        }

        guard let metadata = document.processingMetadata else { return false }
        return metadata.documentCategory == .referenceTable
            || metadata.tablesExtracted > 0
            || metadata.tableRowsTotal > 0
            || metadata.tableColumnsMax > 0
    }

    private static func dedupeFallbackCandidates(
        _ candidates: [(text: String, category: QuestionCategory, confidence: Double)]
    ) -> [(text: String, category: QuestionCategory, confidence: Double)] {
        var seen: Set<String> = []
        return candidates.filter { candidate in
            seen.insert(candidate.text.lowercased()).inserted
        }
    }

    private static func fallbackPromptProfile(for document: Document, documentName: String) -> FallbackPromptProfile {
        if let category = document.processingMetadata?.documentCategory {
            switch category {
            case .referenceTable:
                return .spreadsheet
            case .scientificPaper:
                return .research
            case .technicalManual, .regulatory:
                return .manual
            case .general:
                break
            }
        }

        switch document.contentType {
        case .excel, .numbers, .csv:
            return .spreadsheet
        case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            return .media
        case .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc, .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code:
            return .code
        default:
            let lowerName = documentName.lowercased()
            if researchFilenameSignals.contains(where: { lowerName.contains($0) }) {
                return .research
            }
            if manualFilenameSignals.contains(where: { lowerName.contains($0) }) {
                return .manual
            }
            return .general
        }
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
            let content = groundedPassageContent(for: chunk)
            let searchable = [docName, sectionName, content]
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
                sectionTokens: meaningfulTokens(from: sectionName ?? ""),
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
        let combined = [chunk.contextualPrefix, baseContent]
            .compactMap { text in
                let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return cleaned.isEmpty ? nil : cleaned
            }
            .joined(separator: "\n")

        return String((combined.isEmpty ? chunk.content : combined).prefix(520))
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
        default:
            return false
        }
    }

    private func rankingScore(for question: SuggestedQuestion) -> Double {
        question.confidence + categoryBoost(for: question.category)
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
        Self.humanizedDocumentName(filename)
    }

    private static func humanizedDocumentName(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"([A-Z]+)([A-Z][a-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

    private func normalizedQuestionKey(_ question: String) -> String {
        question
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isUsableGeneratedQuestion(
        _ question: String,
        passages: [GroundedPassage]
    ) -> Bool {
        let lower = question.lowercased()
        if isBoilerplateQuestionTemplate(lower) {
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

        if isQuantityQuestion(original) && !isQuantityQuestion(rewritten) {
            return false
        }

        if rewrittenLower.hasPrefix("how long") && !passageContainsExplicitDuration(passage.content) {
            return false
        }

        if isCapabilityQuestionFraming(rewrittenLower) && passageLooksSafetyCritical(passage.content) {
            return false
        }

        return true
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

    private func naturalQuestionTopic(_ topic: String) -> String {
        let cleaned = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return topic }
        if cleaned == cleaned.uppercased() {
            return cleaned.lowercased()
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
        "analysis", "data", "system", "method", "model", "approach", "result",
        "study", "research", "process", "framework", "structure", "design",
        "implementation", "performance", "evaluation", "table", "figure",
        "section", "chapter", "page", "document", "paper", "report",
        "specification", "specifications",
        "author", "authors", "manuscript", "article", "journal", "publication",
        "keyword", "keywords", "copyright", "funding", "disclosure", "disclosures",
        "conflict", "conflicts", "interest", "interests", "acknowledgement", "acknowledgements",
        "supplement", "supplements", "supplementary",
        "information", "content", "text", "type", "level", "value",
        "group", "number", "part", "case", "example", "form", "area",
        "point", "time", "work", "thing", "way", "issue", "problem",
        "question", "answer", "item", "list", "set", "use", "end"
    ]

    private static let matchStopTokens: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "what", "when",
        "where", "which", "about", "into", "your", "their", "does", "have",
        "here", "there", "under", "over", "should", "would", "could", "after",
        "before", "using", "used", "than", "then", "they", "them", "much",
        "many", "long", "happens", "important", "actually", "main", "point",
        "points", "details", "explain", "tell", "analyze", "evaluate", "review",
        "discuss", "summarize", "author", "authors", "manuscript", "article",
        "journal", "publication", "guidance"
    ]

    private static let specSubjectStopTokens: Set<String> = [
        "recommended", "equivalent", "maximum", "minimum", "approx", "approximately",
        "about", "page", "section", "table", "figure", "see", "refer", "when",
        "where", "which", "with", "without", "and", "or", "the", "for", "from",
        "value", "values", "specification", "specifications", "author", "authors",
        "manuscript", "article", "journal", "publication"
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

    private static let researchFilenameSignals: Set<String> = [
        "study", "trial", "research", "paper", "manuscript", "journal", "abstract",
        "supplement", "supplementary", "review", "meta analysis", "preprint"
    ]

    private static let manualFilenameSignals: Set<String> = [
        "manual", "guide", "ifu", "instruction", "instructions", "handbook", "datasheet",
        "spec", "specification", "requirements", "protocol", "procedure", "sop", "reference"
    ]

    private static let frontMatterSignals: Set<String> = [
        "author manuscript", "all rights reserved", "rights reserved", "copyright",
        "corresponding author", "published online", "accepted for publication", "doi",
        "conflict of interest", "conflicts of interest", "competing interests",
        "author contributions", "funding", "acknowledg", "keywords"
    ]

    private static let filenameTopicNoiseTokens: Set<String> = [
        "trace", "response", "mode", "quality", "maximum", "minimum", "sample",
        "samples", "fixture", "fixtures", "final", "draft", "copy", "scan",
        "image", "photo", "validation", "deepthink", "latest", "output",
        "random", "test", "tests", "version"
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

    /// Questions shown when no documents are in the library
    static let emptyLibraryQuestions: [String] = [
        "Import a document from the Documents tab to get started.",
        "What file types can I import?",
        "How does the on-device search work?",
        "What kinds of questions can I ask?"
    ]

    /// Generic fallback questions (absolute last resort)
    static let genericQuestions: [String] = [
        "What should I pay attention to first?",
        "Is there anything easy to miss here?",
        "What warnings, limits, or caveats stand out?",
        "What number, date, or threshold matters most?"
    ]
}

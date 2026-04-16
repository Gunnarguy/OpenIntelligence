//
//  SuggestedQuestionsService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 2025.
//
//  LLM-first suggested question generation from actual document content.
//  Generates ultra-specific, grounded questions that showcase RAG capabilities.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service that generates contextual suggested questions from actual document content.
///
/// **Architecture (v2 — LLM-first, content-grounded):**
///
/// 1. Select diverse representative chunks across the library (different docs, sections, topics)
/// 2. Feed chunk TEXT directly to Apple FM with a constrained prompt
/// 3. Parse structured output into display-ready questions
/// 4. Fall back to content-phrase extraction when LLM is unavailable (Simulator)
///
/// **Why this is 10x:**
/// - Questions are generated FROM the actual text, not from entity labels
/// - "What is Analysis?" → "How does the Jaccard similarity threshold detect font-encoded PDFs?"
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
    /// Questions are generated directly from chunk content using Apple FM (LLM-first).
    /// Falls back to content-phrase extraction when LLM is unavailable.
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

        // Step 2: Try LLM generation first (iOS 26+)
        var questions: [SuggestedQuestion] = []

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            questions = await generateWithLLM(
                chunks: diverseChunks,
                documents: documents,
                avoidTexts: previousTexts
            )
        }
        #endif

        // Step 3: Fall back to content-grounded extraction if LLM failed or unavailable
        if questions.isEmpty {
            questions = generateFromContent(chunks: diverseChunks, documents: documents)
        }

        // Step 4: Ensure diversity — no two questions from the same document
        let deduped = enforceDiversity(questions, count: max(count, 6))

        // Cache
        cachedQuestions[containerId] = CachedEntry(
            questions: deduped,
            documentCount: documents.count,
            generatedAt: Date()
        )
        Log.info("[SuggestedQuestions] Generated \(deduped.count) questions for container (refresh: \(forceRefresh))")

        return Array(deduped.prefix(count))
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

        // Round-robin across documents, preferring chunks with:
        // 1. Rich content (higher word count, not just headers)
        // 2. Different sections (diverse sectionTitle)
        // 3. Interesting metadata (hasNumericData, entities, abbreviations)
        let docIds = Array(byDocument.keys)

        // Sort each document's chunks by "interestingness"
        for docId in docIds {
            byDocument[docId]?.sort { a, b in
                interestingnessScore(a) > interestingnessScore(b)
            }
        }

        // Round-robin: take best chunk from each doc, then second-best, etc.
        var round = 0
        while selected.count < targetCount {
            var addedThisRound = false
            for docId in docIds {
                guard selected.count < targetCount else { break }
                guard let docChunks = byDocument[docId], round < docChunks.count else { continue }

                let candidate = docChunks[round]
                let section = candidate.metadata.sectionTitle ?? "default_\(candidate.id.uuidString.prefix(4))"

                // Skip if we already have a chunk from this exact section (across all docs)
                if usedSections.contains(section) && selected.count >= docIds.count {
                    continue
                }

                selected.append(candidate)
                usedSections.insert(section)
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

        return score
    }

    // MARK: - Step 2: LLM Generation (iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithLLM(
        chunks: [DocumentChunk],
        documents: [Document],
        avoidTexts: [String] = []
    ) async -> [SuggestedQuestion] {

        guard SystemLanguageModel.default.isAvailable else {
            Log.debug("[SuggestedQuestions] Apple FM not available, falling back to content extraction")
            return []
        }

        // Build content passages from diverse chunks
        let passages = chunks.prefix(5).enumerated().map { index, chunk in
            let docName = documents.first(where: { $0.id == chunk.documentId })?.filename ?? "Document"
            let section = chunk.metadata.sectionTitle.map { " > \($0)" } ?? ""
            let content = String(chunk.content.prefix(400))
            return "[\(index + 1)] \(docName)\(section):\n\(content)"
        }
        let passageText = passages.joined(separator: "\n\n")

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
        You are writing suggested questions for a document Q&A app. Below are passages from the user's documents.

        Write 6 short questions that sound like a real person casually asking about their documents.

        Rules:
        - Every question MUST reference a specific detail FROM the passages below — a name, number, date, step, requirement, or spec that actually appears in the text
        - Sound natural and direct — under 12 words each
        - Mix question types: some "how much/many", some "what happens if", some "which", some "why"
        - Do NOT use phrases like "What role does", "What is the significance of", "What are the key", "Can you explain"
        - Do NOT ask about the documents themselves ("What does the document say about...")
        - Do NOT copy or rephrase any example below — your questions must come ONLY from the passages
        - Ask about the CONTENT as if you read it and want to know more

        Style guide (for tone only — do NOT reuse these topics):
        - "[specific thing from passage] — how does that work?"
        - "How many [unit] does [thing from passage] need?"
        - "What happens if [condition from passage]?"
        \(avoidClause)
        PASSAGES:
        \(passageText)

        Return ONLY the questions, one per line, numbered 1-6. No other text.
        """

        do {
            let session = LanguageModelSession()
            // @Generable: typed [String] array — eliminates numbered-line regex parsing.
            // Constrained sampling enforces the declared schema at the token level.
            let response = try await session.respond(to: prompt, generating: SuggestedQuestionList.self)
            let lines = response.content.questions
                .filter { !$0.isEmpty && $0.count >= 10 }

            guard lines.count >= 2 else {
                Log.warning("[SuggestedQuestions] LLM returned too few valid questions (\(lines.count))")
                return []
            }

            let categories: [QuestionCategory] = [.factRetrieval, .analytical, .procedural, .comparison, .summarization, .numerical]

            // Map each question to the passage/doc it most likely came from
            // (by index alignment with the passages we sent)
            let docNamesFromPassages = chunks.prefix(5).map { chunk in
                documents.first(where: { $0.id == chunk.documentId })?.filename ?? "Document"
            }

            let questions = lines.prefix(6).enumerated().map { index, text in
                let cleanText = text.hasSuffix("?") ? text : text + "?"
                // Assign to the passage doc at the corresponding index (wraps around)
                let sourceDoc = index < docNamesFromPassages.count
                    ? docNamesFromPassages[index]
                    : (docNamesFromPassages.first ?? "Document")
                return SuggestedQuestion(
                    id: UUID(),
                    text: cleanText,
                    category: categories[index % categories.count],
                    relevantDocuments: [sourceDoc],
                    confidence: 0.95
                )
            }

            Log.info("[SuggestedQuestions] LLM generated \(questions.count) grounded questions")
            return questions

        } catch {
            Log.warning("[SuggestedQuestions] LLM generation failed: \(error.localizedDescription)")
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

        for chunk in chunks {
            let docName = documents.first(where: { $0.id == chunk.documentId })?.filename ?? "Document"
            let content = chunk.content

            // Strategy 1: Questions from abbreviation definitions
            for (abbr, expansion) in chunk.metadata.abbreviations.prefix(2) {
                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: "What does \(abbr) (\(expansion)) do?",
                    category: .factRetrieval,
                    relevantDocuments: [docName],
                    confidence: 0.85
                ))
            }

            // Strategy 2: Questions from section titles (if specific enough)
            if let section = chunk.metadata.sectionTitle,
               section.count >= 8,
               !isGenericSectionTitle(section) {
                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: "What's covered under \(section.lowercased())?",
                    category: .summarization,
                    relevantDocuments: [docName],
                    confidence: 0.80
                ))
            }

            // Strategy 3: Questions from numeric data
            if chunk.metadata.hasNumericData {
                let numbers = extractSpecificNumbers(from: content)
                if let detail = numbers.first {
                    questions.append(SuggestedQuestion(
                        id: UUID(),
                        text: "Why is \(detail) important here?",
                        category: .numerical,
                        relevantDocuments: [docName],
                        confidence: 0.82
                    ))
                }
            }

            // Strategy 4: Questions from named entities (but only specific ones, not generic nouns)
            let specificEntities = chunk.metadata.entities.filter { entity in
                entity.count >= 4 &&
                !Self.genericStopEntities.contains(entity.lowercased()) &&
                entity.first?.isUppercase == true
            }
            if let entity = specificEntities.first {
                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: "What does \(entity) actually do?",
                    category: .factRetrieval,
                    relevantDocuments: [docName],
                    confidence: 0.78
                ))
            }

            // Strategy 5: Questions from key multi-word phrases in content
            let keyPhrases = extractKeyPhrases(from: content)
            if let phrase = keyPhrases.first {
                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: "How does \(phrase) work?",
                    category: .analytical,
                    relevantDocuments: [docName],
                    confidence: 0.75
                ))
            }

            // Strategy 6: Procedural questions for list-structured content
            if chunk.metadata.hasListStructure {
                let topic = chunk.metadata.sectionTitle ?? keyPhrases.first ?? docName
                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: "What are the steps for \(topic.lowercased())?",
                    category: .procedural,
                    relevantDocuments: [docName],
                    confidence: 0.77
                ))
            }
        }

        // If we got nothing useful (extremely sparse content), generate doc-level questions
        if questions.isEmpty {
            for doc in documents.prefix(4) {
                let cleanName = doc.filename
                    .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                questions.append(SuggestedQuestion(
                    id: UUID(),
                    text: "What's the main point of \(cleanName)?",
                    category: .summarization,
                    relevantDocuments: [doc.filename],
                    confidence: 0.60
                ))
            }
        }

        return questions
    }

    // MARK: - Step 4: Diversity Enforcement

    /// Ensure question diversity: spread categories, limit per-document concentration
    /// The per-doc cap scales with how many documents exist — a single-doc library
    /// can still produce 4+ questions without being artificially cut to 2.
    private func enforceDiversity(_ questions: [SuggestedQuestion], count: Int) -> [SuggestedQuestion] {
        var result: [SuggestedQuestion] = []
        var docCounts: [String: Int] = [:]
        var usedCategories: Set<QuestionCategory> = []

        // Dynamic per-doc cap: allow more questions from same doc when few docs exist
        let uniqueDocs = Set(questions.flatMap { $0.relevantDocuments })
        let perDocCap = uniqueDocs.count <= 2 ? count : max(2, count / uniqueDocs.count + 1)

        // First pass: pick one from each category
        for question in questions.sorted(by: { $0.confidence > $1.confidence }) {
            if !usedCategories.contains(question.category) {
                let docKey = question.relevantDocuments.first ?? ""
                if (docCounts[docKey] ?? 0) < perDocCap {
                    result.append(question)
                    usedCategories.insert(question.category)
                    docCounts[docKey, default: 0] += 1
                }
            }
            if result.count >= count { break }
        }

        // Second pass: fill remaining slots with highest-confidence
        if result.count < count {
            let usedIds = Set(result.map { $0.id })
            for question in questions.sorted(by: { $0.confidence > $1.confidence }) {
                guard !usedIds.contains(question.id) else { continue }
                let docKey = question.relevantDocuments.first ?? ""
                if (docCounts[docKey] ?? 0) < perDocCap {
                    result.append(question)
                    docCounts[docKey, default: 0] += 1
                }
                if result.count >= count { break }
            }
        }

        return result
    }

    // MARK: - Content Extraction Helpers

    /// Generic section titles that produce bad questions
    private func isGenericSectionTitle(_ title: String) -> Bool {
        let generic: Set<String> = [
            "introduction", "conclusion", "summary", "overview", "abstract",
            "references", "bibliography", "appendix", "index", "table of contents",
            "acknowledgements", "disclaimer", "copyright", "notes", "glossary",
            "contents", "preface", "foreword", "about"
        ]
        return generic.contains(title.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// Generic nouns that NLTagger marks as "entities" but are useless for questions
    private static let genericStopEntities: Set<String> = [
        "analysis", "data", "system", "method", "model", "approach", "result",
        "study", "research", "process", "framework", "structure", "design",
        "implementation", "performance", "evaluation", "table", "figure",
        "section", "chapter", "page", "document", "paper", "report",
        "information", "content", "text", "type", "level", "value",
        "group", "number", "part", "case", "example", "form", "area",
        "point", "time", "work", "thing", "way", "issue", "problem",
        "question", "answer", "item", "list", "set", "use", "end"
    ]

    /// Extract number-in-context phrases like "360 DPI", "0.15 threshold", "$49.99/year"
    private func extractSpecificNumbers(from text: String) -> [String] {
        let pattern = #"(\d+[\.,]?\d*)\s*(%|(?:DPI|Hz|MHz|GHz|MB|GB|TB|KB|ms|s|min|hr|mg|ml|kg|lb|oz|ft|in|cm|mm|m|km|mph|rpm|psi|°[CF]|watts?|volts?|amps?|tokens?))\b"#
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
        "What are the most important numbers or specs here?",
        "Are there any step-by-step instructions?",
        "Any warnings or safety info I should know about?",
        "What deadlines or dates are mentioned?"
    ]
}

//
//  SuggestedQuestionsService+ChunkSelection.swift
//  OpenIntelligence
//
//  Part of SuggestedQuestionsService, moved from SuggestedQuestionsService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

extension SuggestedQuestionsService {
    // MARK: - Step 1: Diverse Chunk Selection

    /// Select chunks that maximally span different documents, sections, and content types.
    /// This is the most critical step — question diversity is determined HERE, not by post-filtering.
    func selectDiverseChunks(
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
        var selectedIds = Set<UUID>()
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

        // Pass 1: Round-robin with strict section uniqueness de-duplication
        var round = 0
        let maxDocChunks = prioritizedDocIds.map { byDocument[$0]?.count ?? 0 }.max() ?? 0
        while selected.count < targetCount && round < maxDocChunks {
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
                selectedIds.insert(candidate.id)
                usedSections.insert(sectionKey)
            }
            round += 1
        }

        // Pass 2: If we still need more chunks, relax the section uniqueness check
        if selected.count < targetCount {
            round = 0
            while selected.count < targetCount && round < maxDocChunks {
                var addedThisRound = false
                for docId in prioritizedDocIds {
                    guard selected.count < targetCount else { break }
                    guard let docChunks = byDocument[docId], round < docChunks.count else { continue }

                    let candidate = docChunks[round]
                    if !selectedIds.contains(candidate.id) {
                        selected.append(candidate)
                        selectedIds.insert(candidate.id)
                        addedThisRound = true
                    }
                }
                round += 1
                if !addedThisRound { break }
            }
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

        if let section = primarySectionLabel(for: chunk), isHighValueSectionTitle(section) {
            score += 3.5
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

    /// Rejects the topics the templates turned into "What is nothing?", "What is the silicon?",
    /// "What is unlimited maximum?" and "What is the role of Product Guide?" on 2026-09-14: a lone
    /// abstract word, a phrase that is only an article plus such a word, or a phrase lifted from
    /// the document's own title. Applied on top of `isValidConceptualTopic`, which checks shape
    /// and never meaning. Pure and static so the four strings are pinned by a test.
    static func isAcceptableTemplateTopic(_ topic: String, documentName: String) -> Bool {
        let words = topic
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(separator: " ")
            .map { $0.lowercased() }
        guard !words.isEmpty else { return false }
        let articles: Set<String> = ["the", "a", "an", "this", "that", "these", "those", "its", "your", "our"]
        let content = words.filter { !articles.contains($0) }
        guard !content.isEmpty else { return false }
        // Words that name nothing in particular. A topic made only of these is not a subject.
        let abstractWords: Set<String> = [
            "nothing", "something", "everything", "anything", "none", "all", "more", "less", "most",
            "silicon", "device", "devices", "answer", "answers", "question", "questions", "work",
            "maximum", "minimum", "unlimited", "standard", "hybrid", "automatic", "fastest",
            "yes", "no", "today", "version", "versions", "step", "steps", "way", "ways", "thing", "things",
        ]
        if content.allSatisfy({ abstractWords.contains($0) }) { return false }
        // A phrase that is a run of the document's own title is the title, not a subject in it.
        let titleWords = documentName
            .replacingOccurrences(of: #"[-_.]"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { $0.lowercased() }
        if !titleWords.isEmpty, content.count <= 3, content.allSatisfy({ titleWords.contains($0) }) {
            return false
        }
        return true
    }

    func isValidConceptualTopic(_ topic: String) -> Bool {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // 1. Length constraint: 1 to 3 words
        guard words.count >= 1 && words.count <= 3 else {
            return false
        }
        
        // 2. Reject if the entire topic is uppercase (e.g. OCR noise or acronyms of length > 6)
        if trimmed == trimmed.uppercased() && trimmed.count > 6 {
            return false
        }
        
        // 3. Filter out words that contain punctuation/junk or numbers
        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard !clean.isEmpty else { return false }
            if clean.contains(where: { !$0.isLetter && $0 != "-" }) {
                return false
            }
        }
        
        // 4. Case-insensitive illegal words (pronouns, determiners, conjunctions, hanging prepositions, verbs, adverbs, citation terms, etc.)
        let illegalWords: Set<String> = [
            "that", "which", "who", "whom", "whose", "because", "although", "though", "since", "while", "if", "unless",
            "and", "or", "but", "so", "yet", "for", "nor",
            "many", "few", "several", "some", "any", "each", "every", "all", "both", "either", "neither", "no", "none",
            "my", "your", "his", "her", "its", "our", "their", "this", "these", "those", "what", "when", "where", "which", "who", "whose",
            "it", "they", "them", "he", "she", "him", "her", "us", "we", "you", "i", "me",
            "along", "about", "above", "across", "after", "against", "among", "around", "at", "before", "behind", "below",
            "beneath", "beside", "between", "beyond", "by", "down", "during", "except", "for", "from", "in", "inside", "into",
            "like", "near", "of", "off", "on", "onto", "out", "outside", "over", "past", "since", "through", "throughout", "to",
            "toward", "under", "underneath", "until", "up", "upon", "with", "within", "without", "via", "versus", "vs",
            "uncovered", "progressing", "running", "shows", "proved", "proves", "found", "finds", "demonstrated", "observed",
            "use", "using", "used", "study", "studies", "research", "paper", "article", "document", "documents", "evidence", "scholars",
            // Adverbs and meta words
            "simply", "merely", "only", "just", "actually", "really", "basically", "clearly", "obviously", "typically", "generally", "commonly",
            "usually", "frequently", "rarely", "seldom", "always", "never", "currently", "recently", "finally", "initially", "primarily",
            "principally", "mainly", "mostly", "partially", "partly", "fully", "completely", "totally", "entirely", "relatively", "comparatively",
            "specifically", "particularly", "especially", "virtually", "practically", "almost", "nearly", "approximately", "about", "slightly",
            "somewhat", "highly", "extremely", "deeply", "strongly", "greatly", "significantly", "substantially", "garbage", "rubbish", "trash",
            "header", "footer", "content", "untitled", "draft", "version", "anonymous", "et al", "et al.", "ibid", "op cit", "loc cit",
            // Citation words to filter PDF layout noise
            "press", "university", "journal", "proceedings", "conference", "editor", "edition", "publish", "publisher", "isbn", "issn", "vol",
            "volume", "page", "pages", "pp", "abstract", "introduction", "conclusions", "references", "bibliography", "oxford", "cambridge",
            "springer", "wiley", "elsevier", "ieee", "acm", "mit", "routledge", "pearson", "macmillan", "harper", "academic", "publishing",
            "books", "book", "translation", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "cited",
            // Generic adjectives/determiners
            "different", "similar", "same", "various", "multiple", "several", "other", "another", "such"
        ]
        
        for word in words {
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if illegalWords.contains(lower) {
                return false
            }
        }
        
        // Check first/last word illegal words
        if let first = words.first?.lowercased().trimmingCharacters(in: .punctuationCharacters), illegalWords.contains(first) {
            return false
        }
        if let last = words.last?.lowercased().trimmingCharacters(in: .punctuationCharacters), illegalWords.contains(last) {
            return false
        }
        
        // 5. Suffix check for common adverbs (ending in "ly")
        let adverbWhitelist: Set<String> = [
            "family", "assembly", "supply", "early", "daily", "orderly", "friendly", "lonely", "silly", "holy", 
            "likely", "unlikely", "bimonthly", "monthly", "weekly", "yearly", "monopoly", "ally", "belly", "jelly", 
            "rely", "comply", "imply", "multiply", "fly", "reply", "apply"
        ]
        for word in words {
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if lower.hasSuffix("ly") && !adverbWhitelist.contains(lower) {
                return false
            }
        }
        
        // 6. Part-of-speech tagging with NLTagger to reject verbs, pronouns, prepositions, conjunctions, adverbs
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = trimmed
        
        var hasVerb = false
        var hasPronounOrConjunctionOrPrepositionOrAdverb = false
        var hasPersonalName = false
        var lastWordTag: NLTag? = nil
        
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if let tag = tag {
                if tag == .verb {
                    hasVerb = true
                }
                if tag == .pronoun || tag == .conjunction || tag == .preposition || tag == .adverb {
                    hasPronounOrConjunctionOrPrepositionOrAdverb = true
                }
                lastWordTag = tag
            }
            return true
        }
        
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if let tag = tag {
                if tag == .personalName || tag == .placeName || tag == .organizationName {
                    hasPersonalName = true
                }
            }
            return true
        }
        
        if hasVerb || hasPronounOrConjunctionOrPrepositionOrAdverb || hasPersonalName {
            return false
        }
        
        // Reject if the last word is an adjective, adverb, or other non-noun tag
        if let lastTag = lastWordTag {
            let invalidLastTags: Set<NLTag> = [.adjective, .adverb, .verb, .pronoun, .conjunction, .preposition, .determiner, .particle, .interjection]
            if invalidLastTags.contains(lastTag) {
                return false
            }
        }
        
        let academicNamesBlacklist: Set<String> = [
            "piaget", "vygotsky", "chomsky", "freud", "skinner", "maslow", "kohlberg", "erikson", "pavlov", "bandura", "rogers", "jung", "watson"
        ]
        for word in words {
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if academicNamesBlacklist.contains(lower) {
                return false
            }
        }
        
        return true
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

        if let section = primarySectionLabel(for: chunk) {
            if isAdministrativeSectionTitle(section) {
                return -10.0
            }
        }

        let lower = groundedPassageContent(for: chunk).lowercased()
        if containsFrontMatterSignal(lower) {
            return -4.0
        }

        return 0
    }

    func primarySectionLabel(for chunk: DocumentChunk) -> String? {
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

    func sectionHierarchyLabel(for chunk: DocumentChunk) -> String? {
        let parts = (chunk.metadata.sectionPath ?? []).compactMap { cleanedMetadataValue($0, maxLength: 80) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " > ")
    }

    func cleanedMetadataValue(_ value: String?, maxLength: Int? = nil) -> String? {
        let cleaned = value?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) ?? ""

        guard !cleaned.isEmpty else { return nil }

        if let maxLength, cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    struct GroundedPassage: Sendable {
        let chunk: DocumentChunk
        let documentName: String
        let sectionName: String?
        let content: String
        let searchableText: String
        let documentTokens: Set<String>
        let sectionTokens: Set<String>
        let bodyTokens: Set<String>
    }

    struct QuestionDraft: Sendable {
        let text: String
        let category: QuestionCategory
        let confidence: Double
    }

}

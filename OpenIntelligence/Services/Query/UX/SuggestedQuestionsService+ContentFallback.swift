//
//  SuggestedQuestionsService+ContentFallback.swift
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
    // MARK: - Step 3: Content-Grounded Fallback (no LLM)

    /// Generate questions from actual chunk content when LLM is unavailable.
    /// Extracts key phrases and specific details — NOT single-word entities.
    func generateFromContent(
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
                    confidence: draft.confidence,
                    isLLMGenerated: false
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

        // Build grounded passages so fallbacks target real content, not vague templates
        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: 10)

        // 1. Generate questions from section titles — these are the best fallback
        //    because section headings literally describe what the content covers
        for passage in passages {
            guard let section = passage.sectionName else { continue }
            let cleanSection = section.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanSection.count >= 4, cleanSection.count <= 60 else { continue }

            // If the section title is already a question, use it directly
            if cleanSection.hasSuffix("?") {
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: cleanSection,
                    category: inferCategoryFromSectionTitle(cleanSection),
                    relevantDocuments: [passage.documentName],
                    sourceSections: [cleanSection],
                    confidence: 0.80,
                    isLLMGenerated: false
                ))
            } else {
                // Turn the section title into a targeted question
                let question = sectionTitleToQuestion(cleanSection, documentName: passage.documentName)
                if let question, question.count >= 10 {
                    addFallback(SuggestedQuestion(
                        id: UUID(),
                        text: question,
                        category: inferCategoryFromSectionTitle(cleanSection),
                        relevantDocuments: [passage.documentName],
                        sourceSections: [cleanSection],
                        confidence: 0.75,
                        isLLMGenerated: false
                    ))
                }
            }
        }

        // 2. Generate questions from extracted technical terms (no doc name in question text)
        var terms: [String] = []
        for passage in passages {
            terms.append(contentsOf: extractTechnicalTerms(from: passage.content, limit: 2))
        }
        let uniqueTerms = Array(Set(terms)).filter { $0.count >= 4 && $0.count <= 30 && isValidConceptualTopic($0) }

        for term in uniqueTerms.prefix(4) {
            if let passage = passages.first(where: { $0.content.contains(term) }) {
                addFallback(SuggestedQuestion(
                    id: UUID(),
                    text: "What is \(term)?",
                    category: .factRetrieval,
                    relevantDocuments: [passage.documentName],
                    sourceSections: passage.sectionName.map { [$0] } ?? [],
                    confidence: 0.65,
                    isLLMGenerated: false
                ))
            }
        }

        // Deduplicate and return
        let deduped = dedupeSuggestedQuestionsPreservingOrder(fallbacks)
        return Array(deduped.prefix(count))
    }

    /// Convert a section title into a natural question.
    /// Returns nil if the title is too generic to make a good question.
    private func sectionTitleToQuestion(_ title: String, documentName: String) -> String? {
        let lower = title.lowercased()

        // Skip generic section titles that would produce vague questions
        let genericTitles: Set<String> = [
            "introduction", "overview", "summary", "conclusion", "background",
            "discussion", "results", "methods", "methodology", "references",
            "appendix", "acknowledgments", "abstract", "table of contents",
            "getting started", "notes", "about"
        ]
        if genericTitles.contains(lower) { return nil }

        // "Plans" → "What plans are available?"
        // "Quality Modes" → "What are the quality modes?"
        // "The RAG Pipeline" → "How does the RAG pipeline work?"
        // "Privacy summary" → "What does the privacy summary cover?"

        if lower.hasPrefix("how") || lower.hasPrefix("what") || lower.hasPrefix("when") || lower.hasPrefix("why") {
            // Already question-shaped, just add a question mark
            return title + "?"
        }

        // Check if it describes a process or system
        let processWords = ["pipeline", "process", "workflow", "routing", "search", "verification"]
        if processWords.contains(where: { lower.contains($0) }) {
            return "How does \(title.lowercased()) work?"
        }

        // Default: "What are the [title]?"
        return "What are the \(title.lowercased())?"
    }

    private func inferCategoryFromSectionTitle(_ title: String) -> QuestionCategory {
        let lower = title.lowercased()
        if lower.contains("how") || lower.contains("step") || lower.contains("pipeline") || lower.contains("process") {
            return .procedural
        }
        if lower.contains("compare") || lower.contains("versus") || lower.contains("vs") || lower.contains("difference") {
            return .comparison
        }
        if lower.contains("why") {
            return .analytical
        }
        return .factRetrieval
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
        guard Self.isAcceptableTemplateTopic(topic, documentName: passage.documentName) else {
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
        // The category, and only the category. The word "study" appears in product prose ("study
        // your documents") and turned a product guide into "What does the study say about ...?".
        let researchLike = passage.chunk.metadata.documentCategory == .scientificPaper

        guard researchLike else { return nil }
        guard let topic = passageTopic(for: passage) ?? documentTopic(from: passage.documentName),
              Self.isAcceptableTemplateTopic(topic, documentName: passage.documentName) else {
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
        
        let sentences = passage.content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for term in terms {
            guard term.count >= 4 && term.count <= 40 else { continue }
            guard isValidConceptualTopic(term) else { continue }
            guard Self.isAcceptableTemplateTopic(term, documentName: passage.documentName) else { continue }
            
            // Find the sentence containing this term to extract context
            let matchingSentence = sentences.first { sentence in
                sentence.lowercased().contains(term.lowercased())
            }?.lowercased() ?? ""
            
            let isResearch = passage.chunk.metadata.documentCategory == .scientificPaper
                
            if isResearch {
                if matchingSentence.contains("limit") || matchingSentence.contains("caveat") || matchingSentence.contains("weakness") {
                    drafts.append(QuestionDraft(
                        text: "What limitations are mentioned regarding \(term)?",
                        category: .analytical,
                        confidence: 0.85
                    ))
                } else if matchingSentence.contains("find") || matchingSentence.contains("show") || matchingSentence.contains("observe") || matchingSentence.contains("result") {
                    drafts.append(QuestionDraft(
                        text: "What did the study observe regarding \(term)?",
                        category: .factRetrieval,
                        confidence: 0.85
                    ))
                } else {
                    drafts.append(QuestionDraft(
                        text: "What does the study say about \(term)?",
                        category: .factRetrieval,
                        confidence: 0.82
                    ))
                    drafts.append(QuestionDraft(
                        text: "How does \(term) impact the findings?",
                        category: .analytical,
                        confidence: 0.80
                    ))
                }
            } else {
                if matchingSentence.contains("prevent") || matchingSentence.contains("avoid") || matchingSentence.contains("protect") {
                    drafts.append(QuestionDraft(
                        text: "How does \(term) help prevent problems?",
                        category: .analytical,
                        confidence: 0.84
                    ))
                } else if matchingSentence.contains("improve") || matchingSentence.contains("enhance") || matchingSentence.contains("increase") || matchingSentence.contains("boost") {
                    drafts.append(QuestionDraft(
                        text: "How does \(term) improve results?",
                        category: .analytical,
                        confidence: 0.84
                    ))
                } else if matchingSentence.contains("reduce") || matchingSentence.contains("decrease") || matchingSentence.contains("minimize") {
                    drafts.append(QuestionDraft(
                        text: "How does \(term) help reduce negative effects?",
                        category: .analytical,
                        confidence: 0.84
                    ))
                } else if matchingSentence.contains("allow") || matchingSentence.contains("enable") || matchingSentence.contains("support") || matchingSentence.contains("permit") {
                    drafts.append(QuestionDraft(
                        text: "What does \(term) allow you to do?",
                        category: .factRetrieval,
                        confidence: 0.84
                    ))
                } else if matchingSentence.contains("cause") || matchingSentence.contains("lead") || matchingSentence.contains("trigger") || matchingSentence.contains("result") {
                    drafts.append(QuestionDraft(
                        text: "What does \(term) lead to?",
                        category: .analytical,
                        confidence: 0.84
                    ))
                } else if matchingSentence.contains("require") || matchingSentence.contains("need") || matchingSentence.contains("depend") {
                    drafts.append(QuestionDraft(
                        text: "What do you need for \(term)?",
                        category: .factRetrieval,
                        confidence: 0.84
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
                        if isValidConceptualTopic(phrase) {
                            candidates.append(phrase)
                        }
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
        let words = normalizedTopic.split(separator: " ").map(String.init)
        guard let firstWord = words.first else {
            return "How do you handle \(normalizedTopic)?"
        }
        
        let lowerFirst = firstWord.lowercased()
        
        // Map common gerunds to base form for cleaner phrasing
        let gerundMap = [
            "installing": "install",
            "replacing": "replace",
            "connecting": "connect",
            "disconnecting": "disconnect",
            "cleaning": "clean",
            "inspecting": "inspect",
            "operating": "operate",
            "baking": "bake",
            "cooking": "cook",
            "running": "run",
            "using": "use",
            "configuring": "configure",
            "preparing": "prepare",
            "testing": "test",
            "updating": "update",
            "restoring": "restore",
            "creating": "create",
            "building": "build",
            "loading": "load",
            "saving": "save",
            "rebuilding": "rebuild",
            "syncing": "sync",
            "managing": "manage",
            "handling": "handle",
            "removing": "remove",
            "deleting": "delete",
            "adding": "add",
            "inserting": "insert",
            "starting": "start",
            "stopping": "stop",
            "verifying": "verify",
            "checking": "check",
            "adjusting": "adjust",
            "assembling": "assemble",
            "disassembling": "disassemble",
            "mounting": "mount",
            "unmounting": "unmount"
        ]
        
        if let baseVerb = gerundMap[lowerFirst] {
            let remaining = words.dropFirst().joined(separator: " ")
            return remaining.isEmpty ? "How do you \(baseVerb)?" : "How do you \(baseVerb) \(remaining)?"
        }
        
        if Self.proceduralActionStarters.contains(lowerFirst) {
            return "How do you \(normalizedTopic)?"
        }
        
        if lowerFirst.hasSuffix("ing") {
            return "How do you handle \(normalizedTopic)?"
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
            guard isValidConceptualTopic(topic) else { continue }
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
            guard isValidConceptualTopic(topic) else { continue }
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
            if isValidConceptualTopic(topic) {
                return topic
            }
        }

        if let fallback = casePreservingTopic(from: documentName), !isWeakQuestionTopic(fallback) {
            if isValidConceptualTopic(fallback) {
                return fallback
            }
        }

        return nil
    }

    func isWeakQuestionTopic(_ topic: String) -> Bool {
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

    func isJunkString(_ text: String) -> Bool {
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

        // Phrasing cap. Spreading across documents does not stop every slot from being filled with
        // the same sentence frame, and a set where four of seven questions open "What is the role
        // of" reads as generated even when each question is individually fine. The cap is applied
        // as a preference, not a rule: the final pass below ignores it so the requested count is
        // still met when a library genuinely only supports one frame.
        var templateCounts: [String: Int] = [:]
        let templateCap = max(2, count / 3)

        // First pass: seed as many different documents as possible with the strongest,
        // most answerable questions instead of forcing one-per-category.
        for question in rankedQuestions {
            let docKey = question.relevantDocuments.first ?? ""
            guard !docsSeeded.contains(docKey) else { continue }
            guard (docCounts[docKey] ?? 0) < perDocCap else { continue }
            let templateKey = questionTemplateKey(question.text)
            guard (templateCounts[templateKey] ?? 0) < templateCap else { continue }

            result.append(question)
            selectedIds.insert(question.id)
            docsSeeded.insert(docKey)
            docCounts[docKey, default: 0] += 1
            templateCounts[templateKey, default: 0] += 1

            if result.count >= min(count, max(1, uniqueDocs.count)) { break }
        }

        // Second pass: fill remaining slots with the best remaining questions.
        if result.count < count {
            for question in rankedQuestions {
                guard !selectedIds.contains(question.id) else { continue }
                let docKey = question.relevantDocuments.first ?? ""
                let templateKey = questionTemplateKey(question.text)
                if (docCounts[docKey] ?? 0) < perDocCap,
                   (templateCounts[templateKey] ?? 0) < templateCap {
                    result.append(question)
                    selectedIds.insert(question.id)
                    docCounts[docKey, default: 0] += 1
                    templateCounts[templateKey, default: 0] += 1
                }
                if result.count >= count { break }
            }
        }

        // Final pass: the phrasing cap must never cost the caller a slot. If variety was not
        // available, fall back to the document cap alone rather than returning fewer questions.
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

    /// Collapse a question to its sentence frame so `enforceDiversity` can limit repetition.
    ///
    /// The first two words carry the frame for the forms this service generates: "What is",
    /// "How does", "Why did", "What are". Deliberately ignores the topic, because two questions
    /// about different topics in the same frame are the repetition being limited.
    private func questionTemplateKey(_ text: String) -> String {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }
        return words.prefix(2).joined(separator: " ")
    }

    // MARK: - Content Extraction Helpers

    func isHighValueSectionTitle(_ title: String) -> Bool {
        let highValue: Set<String> = [
            "abstract", "conclusion", "summary", "overview", "discussion",
            "results", "key findings", "methodology", "methods", "introduction",
            "executive summary", "key takeaways", "takeaways", "implications"
        ]
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return highValue.contains(normalized) || highValue.contains(where: { normalized.contains($0) })
    }

    func isAdministrativeSectionTitle(_ title: String) -> Bool {
        let admin: Set<String> = [
            "references", "bibliography", "appendix", "index", "table of contents",
            "acknowledgements", "disclaimer", "copyright", "notes", "glossary",
            "contents", "preface", "foreword", "about", "author manuscript",
            "keywords", "conflict of interest", "conflicts of interest",
            "competing interests", "author contributions", "funding", "ethics statement"
        ]
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return admin.contains(normalized) || containsFrontMatterSignal(normalized)
    }

    /// Generic section titles that produce bad questions
    private func isGenericSectionTitle(_ title: String) -> Bool {
        return isAdministrativeSectionTitle(title)
    }

    func containsFrontMatterSignal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return Self.frontMatterSignals.contains { lower.contains($0) }
    }

    /// Generic nouns that NLTagger marks as "entities" but are useless for questions
    static let genericStopEntities: Set<String> = [
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

    static let matchStopTokens: Set<String> = [
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

    static let specSubjectStopTokens: Set<String> = [
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

    static let weakQuestionTopicTokens: Set<String> = [
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

    static let questionFocusStopTokens: Set<String> = [
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

    func extractNumericTokens(from text: String) -> [String] {
        text
            .split { !$0.isNumber && $0 != "." && $0 != "," }
            .map(String.init)
            .filter { token in token.contains(where: \.isNumber) }
    }

    func isQuantityQuestion(_ text: String) -> Bool {
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

}

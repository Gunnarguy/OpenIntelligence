//
//  SuggestedQuestionsService+Grounding.swift
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
    // MARK: - Grounding Helpers

    private func regexMatchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        return regex.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    /// Detect a run of three or more consecutive `Surname AB,` entries with distinct surnames.
    ///
    /// The surname test is what separates an author list from a label list. "Phase A, Phase A,
    /// Phase B," matches the same shape as "Correia PA, Lottem E, Banerjee D," and a plain repeat
    /// count cannot tell them apart. Real author lists do not repeat a surname three times, while
    /// "Section A, Section B, Section C" and "Option A, Option B, Option C" are ordinary content in
    /// manuals, forms and agreements, which is exactly the material this feature must not demote.
    private func hasAuthorListRun(_ text: String) -> Bool {
        let entry = #"\b([A-Z][a-z]+)\s+[A-Z]{1,3}\s*,\s*"#
        guard let regex = try? NSRegularExpression(pattern: entry) else { return false }
        let full = NSRange(text.startIndex..., in: text)

        var runSurnames: [String] = []
        var previousEnd = -1

        for match in regex.matches(in: text, options: [], range: full) {
            guard let surnameRange = Range(match.range(at: 1), in: text) else { continue }
            // Consecutive means the next entry begins where the previous one ended. Anything else
            // is two separated mentions in prose rather than one list.
            if previousEnd >= 0 && match.range.location > previousEnd {
                runSurnames.removeAll()
            }
            runSurnames.append(String(text[surnameRange]))
            previousEnd = match.range.location + match.range.length

            if runSurnames.count >= 3 && Set(runSurnames).count >= 3 {
                return true
            }
        }
        return false
    }

    /// Score a chunk on how well it works as raw material for a question, independent of the
    /// question that gets written from it.
    ///
    /// Every filter that already exists in this file inspects the generated *question*:
    /// `isJunkString`, `sanitizeGeneratedQuestion`, `isUsableLLMGeneratedQuestion`,
    /// `isStructuralOrMetaQuestion`. That is why a reference list survives all of them. A
    /// bibliography entry is grammatical, dense with capitalised domain nouns, and yields a
    /// perfectly well formed question such as "What is the role of Neurosci Yagishita Transient?"
    /// which no question-level filter can distinguish from a real one. The only place the defect is
    /// visible is the passage, so this looks at the passage and never at the question.
    ///
    /// Returns a penalty. `0` means the text reads as document body. Higher means more furniture.
    /// The caller demotes rather than deletes, so a document made entirely of one of these forms
    /// still produces questions.
    private func questionSourcePenalty(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return 6 }

        var penalty = 0
        let lower = trimmed.lowercased()

        // Bibliography and reference blocks. Any two of these signals together is decisive; the
        // thresholds are set so a body paragraph that cites one or two works in passing survives.
        // A run of three or more "Surname AB," entries back to back is decisive on its own. It is
        // the shape of an author list and it does not occur in running prose.
        //
        // Two earlier signals were removed after being measured against 5,425 real chunks from the
        // library, where they hard-demoted ordinary body paragraphs:
        //
        //  - A parenthetical year, `\(\d{4}\)`, counted 3 or more times. That is the marker of an
        //    author-year citation *in running text*, so it fires hardest on the related-work
        //    paragraph, which is good question material. It is evidence against a bibliography, not
        //    for one, since a numbered reference list writes "2017;6:e20975" instead.
        //  - Author initials matched loosely as `[A-Z][a-z]{2,}\s+[A-Z]{1,3}[,.]`. Without requiring
        //    the entries to be consecutive it matches any capitalised word followed by an acronym,
        //    so "Detection DET." and "Twitter PHEME," scored as authors. In a paper whose body is
        //    full of acronyms it fired on nearly every paragraph.
        let authorRun = hasAuthorListRun(trimmed) ? 1 : 0

        var citationSignals = 0
        if regexMatchCount(#"\bet al\.?"#, in: trimmed) >= 4 { citationSignals += 1 }
        // Volume(issue):page and year;volume forms, which appear in journal metadata and not in prose.
        if regexMatchCount(#"\b\d+\s*\(\s*\d+\s*\)\s*:\s*\d+"#, in: trimmed) >= 2 { citationSignals += 1 }
        if regexMatchCount(#"\b\d{4}\s*;\s*\d+"#, in: trimmed) >= 2 { citationSignals += 1 }
        if regexMatchCount(#"\bdoi\s*:|doi\.org/"#, in: trimmed) >= 2 { citationSignals += 1 }
        // Numbered or bracketed citation lists.
        if regexMatchCount(#"(?m)^\s*\[?\d{1,3}[\].]\s+[A-Z]"#, in: trimmed) >= 3 { citationSignals += 1 }
        if authorRun >= 1 {
            penalty += 5
        } else if citationSignals >= 2 {
            penalty += 5
        } else if citationSignals == 1 {
            penalty += 2
        }

        // Table of contents and index furniture: dot leaders, or many lines that end in a bare
        // page number.
        if regexMatchCount(#"\.{4,}"#, in: trimmed) >= 2 { penalty += 5 }
        if regexMatchCount(#"(?m)\s\d{1,4}\s*$"#, in: trimmed) >= 4 { penalty += 3 }

        // Running headers, copyright lines, and access boilerplate. These are the short strips that
        // repeat on every page of a PDF.
        let boilerplate = [
            "all rights reserved", "downloaded from", "creative commons", "this article is protected",
            "author manuscript", "available in pmc", "terms and conditions", "wiley online library",
            "see discussions, stats", "the copyright holder for this preprint", "made available under",
            "issn", "isbn", "printed in the united states"
        ]
        if boilerplate.contains(where: { lower.contains($0) }) { penalty += 4 }

        // Character composition. A table dump or a coordinate list is mostly digits and punctuation,
        // and yields questions about numbers with no referent.
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        if letters > 0, Double(digits) / Double(letters + digits) > 0.35 { penalty += 4 }

        // OCR damage. Vowel-free alphabetic tokens are the reliable tell, and they are what produced
        // fragments like "-HT" surviving into a question.
        let words = trimmed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { $0.count >= 3 && $0.allSatisfy { ch in ch.isLetter } }
        if words.count >= 12 {
            let vowelless = words.filter { word in
                !word.lowercased().contains(where: { "aeiouy".contains($0) })
            }.count
            // 0.2 was measured too tight against the real library: a passage dense with legitimate
            // acronyms reaches it without being damaged text.
            if Double(vowelless) / Double(words.count) > 0.28 { penalty += 4 }
        }

        // Prose check. Body text has sentences. A list of names, headings, or fragments does not.
        let sentenceEnders = regexMatchCount(#"[.!?](\s|$)"#, in: trimmed)
        if sentenceEnders == 0 && trimmed.count > 200 { penalty += 3 }

        return penalty
    }

    /// Order chunks so that document body outranks document furniture, then take `limit`.
    ///
    /// This demotes rather than filters on purpose. A library whose only content is a reference
    /// list, a table, or a scanned page still needs suggestions, and a hard filter would return an
    /// empty set and silently disable the feature for exactly those documents.
    private func rankChunksForQuestionGeneration(
        _ chunks: [DocumentChunk],
        limit: Int
    ) -> [DocumentChunk] {
        guard chunks.count > limit else {
            return Array(chunks)
        }

        let scored = chunks.enumerated().map { index, chunk -> (chunk: DocumentChunk, penalty: Int, index: Int) in
            (chunk, questionSourcePenalty(for: chunk.contextText), index)
        }

        let clean = scored.filter { $0.penalty == 0 }
        if clean.count >= limit {
            return Array(clean.prefix(limit).map { $0.chunk })
        }

        // Stable sort by penalty, preserving the retrieval order the caller established within each
        // penalty band. Retrieval rank is still the primary quality signal among equally clean text.
        let ordered = scored.sorted { lhs, rhs in
            lhs.penalty == rhs.penalty ? lhs.index < rhs.index : lhs.penalty < rhs.penalty
        }
        return Array(ordered.prefix(limit).map { $0.chunk })
    }

    func buildGroundedPassages(
        from chunks: [DocumentChunk],
        documents: [Document],
        limit: Int
    ) -> [GroundedPassage] {
        rankChunksForQuestionGeneration(chunks, limit: limit).map { chunk in
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

    func bestGroundingPassage(
        for question: String,
        passages: [GroundedPassage]
    ) -> GroundedPassage? {
        passages.max { lhs, rhs in
            groundingScore(for: question, passage: lhs) < groundingScore(for: question, passage: rhs)
        }
    }

    func groundedConfidence(for question: String, passage: GroundedPassage) -> Double {
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

    func groundedPassageContent(for chunk: DocumentChunk) -> String {
        let baseContent = chunk.contextText
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

    func rankingScore(for question: SuggestedQuestion) -> Double {
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

    func isStructuralOrMetaQuestion(_ lower: String) -> Bool {
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

    func shouldSurfaceSuggestedQuestion(_ question: SuggestedQuestion) -> Bool {
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

        if question.isLLMGenerated {
            return true
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

    func isLikelySpecificSuggestionFocusToken(_ token: String) -> Bool {
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

    func displayDocumentName(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sanitizeGeneratedQuestion(_ text: String) -> String? {
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

    func isBoilerplateQuestionTemplate(_ question: String) -> Bool {
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

    func dedupeSuggestedQuestionsPreservingOrder(_ questions: [SuggestedQuestion]) -> [SuggestedQuestion] {
        var seen: Set<String> = []
        var deduped: [SuggestedQuestion] = []

        for question in questions {
            let key = normalizedQuestionKey(question.text)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            deduped.append(question)
        }

        return deduped
    }

    func pruneNearDuplicateQuestions(_ questions: [SuggestedQuestion]) -> [SuggestedQuestion] {
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

            let overlap = lhsTokens.intersection(rhsTokens).count
            let smallerCount = min(lhsTokens.count, rhsTokens.count)
            if smallerCount >= 2, Double(overlap) / Double(smallerCount) >= 0.70 {
                return true
            }

            if let lhsSection, let rhsSection, !lhsSection.isEmpty, lhsSection == rhsSection, overlap >= 2 {
                return true
            }
        }

        return false
    }

    func normalizedQuestionKey(_ question: String) -> String {
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

    func isUsableLLMGeneratedQuestion(
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
            "what are the key",
        ]

        if bannedFragments.contains(where: { lower.contains($0) }) {
            return false
        }

        if violatesPassageQuestionGuardrails(question, passage: passage) {
            return false
        }

        // Grounding must come from the passage, not from the filename.
        //
        // This check previously accepted one overlap token from the document name, the section
        // path, or the body, counted together. Document-name tokens made it vacuous: a question
        // sharing nothing but words from the filename passed as "grounded", which is how a library
        // of surgical IFUs produced questions aligned with titles rather than with what the
        // documents actually say. The owner's complaint was literal: it cannot just use the
        // document title. Body and section tokens still count, because section titles carry real
        // content; the filename no longer does.
        let tokens = meaningfulTokens(from: lower)
        guard !tokens.isEmpty else { return false }

        let contentOverlap = tokens.intersection(passage.bodyTokens).count
            + tokens.intersection(passage.sectionTokens).count

        return contentOverlap >= 1
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

    func isSelfAnsweringGeneratedQuestion(_ question: String) -> Bool {
        isQuantityQuestion(question) && !extractNumericTokens(from: question).isEmpty
    }

    func isFaithfulQuestionRewrite(
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

    func isProceduralQuestionFraming(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("how do you")
            || lower.hasPrefix("how do you handle")
            || lower.hasPrefix("what should you do if")
            || lower.hasPrefix("what do you do if")
    }

    func isSafetyOrRequirementQuestionFraming(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("what warnings apply to")
            || lower.hasPrefix("what should you avoid when")
            || lower.hasPrefix("what is required for")
            || lower.hasPrefix("what are the minimum requirements for")
    }

    func violatesPassageQuestionGuardrails(
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

        // A question that gestures at an entity instead of naming it is a riddle, not a question.
        //
        // Observed on a device capture of a surgical IFU library, 2026-08-16: "How does combining
        // certain parts affect performance?" and "What characteristic might affect device
        // reliability after sterilization?" Each is grammatical, on topic, and unanswerable as
        // posed, because the entity it asks about is hidden behind a placeholder. The passage names
        // the parts and the characteristic; a good question repeats them.
        let placeholderMarkers = [
            " certain ", "the nature of", "what characteristic might", "what characteristics might",
            "what aspect might", "what aspects might", "what factor might", "what factors might",
            "in what way might"
        ]
        if placeholderMarkers.contains(where: { lower.contains($0) }) {
            return true
        }

        // A question ending in a bare past participle is asking about the text, not the subject:
        // "What cleaning risks are highlighted?" means highlighted by the document. Matched only at
        // the end, because the same verbs are legitimate mid-question in this domain: "Which
        // vessels are highlighted by the fluorescent dye?" must survive.
        let trailingMetaParticiples = [
            "described?", "described", "highlighted?", "highlighted", "mentioned?", "mentioned",
            "discussed?", "discussed", "outlined?", "outlined", "listed?", "listed"
        ]
        let trimmedQuestion = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        if trailingMetaParticiples.contains(where: { trimmedQuestion.hasSuffix($0) }) {
            return true
        }

        // A question demanding a reason the passage never gives.
        //
        // This lives here, and not in the individual validators, because there are five of them and
        // two are dead code. Placing it in `isAnswerableSuggestedQuestion` first did nothing at all:
        // that function has zero call sites. Every live path routes through this one, so this is the
        // only placement that cannot be half-applied. Measured on a real lease: "Why can't the
        // Tenant rent out the space?" survived a guard placed in two other functions and reached the
        // user, against a clause that requires consent and never says why.
        if asksForAReason(lower) && !passageExplainsCause(passage.content) {
            return true
        }

        return false
    }

    func isCapabilityQuestionFraming(_ question: String) -> Bool {
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

    /// Does the passage actually give a reason, rather than merely state a rule?
    ///
    /// A "why" question is only answerable when the text explains itself, and most documents do not.
    /// A lease says rent is late after the fifth day; it never says why. A manual says do not
    /// immerse the unit; it rarely says what happens if you do. Asking "Why does rent become late
    /// after the fifth day?" produces a question that reads well, is clearly on topic, and has no
    /// answer anywhere in the document, which is the worst kind of suggestion because the user only
    /// discovers it after tapping.
    ///
    /// Same shape as the `how long` rule above it: the question names an answer *type*, and the
    /// passage has to actually contain that type. Deliberately excludes "since", which is causal
    /// about as often as it is temporal, and "as", which is mostly neither.
    private func passageExplainsCause(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Markers of an *explanation*, not of causation in general. Three were removed after being
        // measured against a real lease, where each matched text that explains nothing:
        // "the purpose" matched the boilerplate "for the purposes of this section", while
        // "caused by" and "causes" matched "damage caused by the animal", which describes what
        // damaged what and says nothing about why any rule exists.
        let causalSignals = [
            "because", "due to", "owing to", "as a result", "results in",
            "therefore", "thus", "consequently", "in order to", "so that", "so as to",
            "to ensure", "to prevent", "to avoid", "to protect", "to reduce", "to maintain",
            "the reason", "reason for", "reason is", "rationale", "purpose is",
            "intended to", "designed to", "aims to", "motivated by", "this allows", "which allows",
            "this enables", "which enables", "explains why"
        ]
        return causalSignals.contains(where: { lower.contains($0) })
    }

    /// Is this question demanding a reason the document may not carry?
    ///
    /// Matches the interrogative form only. "Why" anywhere in a sentence is not the same as a
    /// question asking for a cause, and "What is the reason for X" is, so both are handled here
    /// rather than by a bare prefix test.
    private func asksForAReason(_ lowercasedQuestion: String) -> Bool {
        if lowercasedQuestion.hasPrefix("why ") { return true }
        let reasonForms = [
            "what is the reason", "what are the reasons", "for what reason",
            "what is the rationale", "what is the purpose of requiring"
        ]
        return reasonForms.contains(where: { lowercasedQuestion.hasPrefix($0) })
    }

    func passageLooksSafetyCritical(_ text: String) -> Bool {
        let lower = text.lowercased()
        let safetySignals = [
            "warning", "caution", "danger", "contraindication", "do not", "must not",
            "single use", "steril", "reuse", "forbidden", "prohibit", "required", "ensure"
        ]
        return safetySignals.contains(where: { lower.contains($0) })
    }

    func passageContainsProhibition(_ text: String) -> Bool {
        let lower = text.lowercased()
        let prohibitionSignals = [
            "do not", "must not", "should not", "never", "avoid", "forbidden",
            "prohibit", "prohibited", "not allowed", "contraindication"
        ]
        return prohibitionSignals.contains(where: { lower.contains($0) })
    }

    func naturalQuestionTopic(_ topic: String) -> String {
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

    func meaningfulTokens(from text: String) -> Set<String> {
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

}

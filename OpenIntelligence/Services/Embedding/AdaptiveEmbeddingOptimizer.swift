//
//  AdaptiveEmbeddingOptimizer.swift
//  OpenIntelligence
//
//  Provides a single place to reason about the entire knowledge base.
//  It inspects corpus makeup, recommends chunking + embedding strategies,
//  and shares retrieval tuning guidance for downstream services.
//

import Foundation
import NaturalLanguage

/// Performs holistic corpus analysis so the rest of the stack can stay lean.
actor LibraryIntelligenceCenter {
    // MARK: - Public Data Models

    /// Snapshot of the content signals we derive from the current corpus.
    struct CorpusSignals: Sendable {
        let documentCount: Int
        let chunkCount: Int
        let avgWordsPerChunk: Double
        let multilingualScore: Double
        let vocabularyRichness: Double
        let technicalDensity: Double
        let semanticComplexity: Double
        let hasCode: Bool
        let hasMath: Bool
        let structuredRatio: Double
        let languageHypotheses: [NLLanguage: Double]
    }

    /// Recommended chunking configuration for ingestion.
    struct ChunkingPlan: Sendable {
        enum Strategy: String, Sendable {
            case balanced
            case densePrecision
            case elastic
        }

        let strategy: Strategy
        let targetWordWindow: Int
        let overlapWords: Int
        let rationales: [String]
    }

    /// Suggested embedding provider + dimension.
    struct EmbeddingPlan: Sendable {
        let providerId: String
        let dimension: Int
        let confidence: Double
        let rationale: String
        let requiresCloudConsent: Bool
    }

    /// Guidance for retrieval weighting + rerankers.
    struct RetrievalPlan: Sendable {
        enum FusionStyle: String, Sendable {
            case hybrid
            case vectorOnly
            case lexicalBoosted
        }

        enum RerankerStrategy: String, Sendable {
            case none
            case semantic
            case structural
        }

        let fusionStyle: FusionStyle
        let vectorWeight: Double
        let lexicalWeight: Double
        let mmrLambda: Double
        let reranker: RerankerStrategy
        let notes: [String]
    }

    /// Lightweight document descriptors injected into the report for UI context.
    struct DocumentProfile: Identifiable, Sendable {
        let id: UUID
        let name: String
        let descriptor: String
        let keyTopics: [String]
        let preview: String
        let addedAt: Date
    }

    /// Top-level report consumed by the pipeline.
    struct IntelligenceReport: Sendable {
        let corpus: CorpusSignals
        let chunking: ChunkingPlan
        let embedding: EmbeddingPlan
        let retrieval: RetrievalPlan
        let documents: [DocumentProfile]
        let alerts: [String]
    }

    // MARK: - Public API

    /// Primary entry point. Collapses the entire corpus into a single actionable report.
    func analyzeLibrary(
        documents: [Document],
        chunks: [DocumentChunk],
        recentQueries: [RAGQuery] = []
    ) async -> IntelligenceReport {
        let text = chunks.map { $0.content }.joined(separator: "\n")
        let languageHypotheses = detectLanguages(in: text)
        let multilingualScore = calculateMultilingualScore(languageHypotheses)
        let words = tokenizeWords(text)
        let uniqueWords = Set(words)
        let vocabularyRichness = words.isEmpty ? 0 : Double(uniqueWords.count) / Double(words.count)

        let technicalDensity = detectTechnicalDensity(words: words, uniqueWords: uniqueWords)
        let hasCode = detectCodeSnippets(in: text)
        let hasMath = detectMathematicalContent(in: text)
        let semanticComplexity = analyzeSemanticComplexity(text)
        let structuredRatio = calculateStructuredRatio(from: chunks)
        let chunkWordCounts = extractWordCounts(from: chunks, fallback: words)
        let avgWordsPerChunk = average(of: chunkWordCounts)
        let corpusSignals = CorpusSignals(
            documentCount: documents.count,
            chunkCount: chunks.count,
            avgWordsPerChunk: avgWordsPerChunk,
            multilingualScore: multilingualScore,
            vocabularyRichness: vocabularyRichness,
            technicalDensity: technicalDensity,
            semanticComplexity: semanticComplexity,
            hasCode: hasCode,
            hasMath: hasMath,
            structuredRatio: structuredRatio,
            languageHypotheses: languageHypotheses
        )

        let chunkingPlan = buildChunkingPlan(
            avgWords: avgWordsPerChunk,
            hasCode: hasCode,
            hasMath: hasMath,
            structuredRatio: structuredRatio,
            documents: documents,
            multilingualScore: multilingualScore
        )

        let embeddingPlan = recommendEmbeddingPlan(
            vocabularyRichness: vocabularyRichness,
            multilingualScore: multilingualScore,
            technicalDensity: technicalDensity,
            semanticComplexity: semanticComplexity,
            hasCode: hasCode,
            hasMath: hasMath,
            totalWords: words.count
        )

        let querySignals = analyzeQueries(recentQueries)
        let retrievalPlan = recommendRetrievalPlan(
            multilingualScore: multilingualScore,
            technicalDensity: technicalDensity,
            structuredRatio: structuredRatio,
            querySignals: querySignals
        )

        let alerts = makeAlerts(from: corpusSignals, embeddingPlan: embeddingPlan, documents: documents)
        let documentProfiles = buildDocumentProfiles(documents: documents, chunks: chunks)

        return IntelligenceReport(
            corpus: corpusSignals,
            chunking: chunkingPlan,
            embedding: embeddingPlan,
            retrieval: retrievalPlan,
            documents: documentProfiles,
            alerts: alerts
        )
    }

    // MARK: - Chunking

    private func buildChunkingPlan(
        avgWords: Double,
        hasCode: Bool,
        hasMath: Bool,
        structuredRatio: Double,
        documents: [Document],
        multilingualScore: Double
    ) -> ChunkingPlan {
        let window: Int
        var overlap = 60 // Base ~17% overlap - reduced from 80 for less redundancy
        var reasons: [String] = []
        var strategy: ChunkingPlan.Strategy = .balanced

        // Optimized: Larger chunks with less overlap = more unique context per retrieval
        if hasCode {
            strategy = .densePrecision
            window = 280 // Increased from 220 for more complete code blocks
            overlap = 50 // Reduced from 110 (~18% vs 50%)
            reasons.append("Code detected → balanced windows for syntax + context")
        } else if hasMath {
            strategy = .densePrecision
            window = 320 // Increased from 260 for complete equations
            overlap = 55
            reasons.append("Mathematical notation → larger chunks for complete derivations")
        } else if structuredRatio > 0.35 {
            strategy = .densePrecision
            window = 300 // Increased from 240
            overlap = 55
            reasons.append("Structured content → larger chunks to keep tables/lists intact")
        } else if multilingualScore > 0.6 {
            strategy = .elastic
            window = 380 // Increased from 320
            overlap = 65
            reasons.append("Multilingual corpus → larger context windows for coherence")
        } else {
            window = Int(max(300, min(420, avgWords.rounded()))) // Raised floor from 220→300
            reasons.append("Balanced prose → optimized for context efficiency")
        }

        if documents.contains(where: { isVisionAsset($0.contentType) }) {
            reasons.append("OCR assets present → slight overlap increase for extraction noise")
            overlap = max(overlap, 70) // Reduced from 120
        }

        return ChunkingPlan(
            strategy: strategy,
            targetWordWindow: window,
            overlapWords: overlap,
            rationales: reasons
        )
    }

    // MARK: - Embedding Recommendation

    private func recommendEmbeddingPlan(
        vocabularyRichness: Double,
        multilingualScore: Double,
        technicalDensity: Double,
        semanticComplexity: Double,
        hasCode: Bool,
        hasMath: Bool,
        totalWords: Int
    ) -> EmbeddingPlan {
        let (dimension, provider, confidence, reasoning) = recommendConfiguration(
            vocabularyRichness: vocabularyRichness,
            multilingualScore: multilingualScore,
            technicalDensity: technicalDensity,
            semanticComplexity: semanticComplexity,
            hasCode: hasCode,
            hasMath: hasMath,
            totalWords: totalWords
        )
        return EmbeddingPlan(
            providerId: provider,
            dimension: dimension,
            confidence: confidence,
            rationale: reasoning,
            requiresCloudConsent: provider == "apple_fm_embed"
        )
    }

    // MARK: - Retrieval Guidance

    private struct QuerySignals {
        let avgWords: Double
        let longFormRatio: Double
        let mostRecentAge: TimeInterval?
    }

    private func analyzeQueries(_ queries: [RAGQuery]) -> QuerySignals {
        guard !queries.isEmpty else {
            return QuerySignals(avgWords: 0, longFormRatio: 0, mostRecentAge: nil)
        }
        let wordCounts = queries.map { Double($0.query.split(separator: " ").count) }
        let avg = wordCounts.reduce(0, +) / Double(wordCounts.count)
        let longForm = Double(wordCounts.filter { $0 > 18 }.count) / Double(wordCounts.count)
        let latestTimestamp = queries.map { $0.timestamp }.max()
        let age = latestTimestamp.map { Date().timeIntervalSince($0) }
        return QuerySignals(avgWords: avg, longFormRatio: longForm, mostRecentAge: age)
    }

    private func recommendRetrievalPlan(
        multilingualScore: Double,
        technicalDensity: Double,
        structuredRatio: Double,
        querySignals: QuerySignals
    ) -> RetrievalPlan {
        var vectorWeight = 0.6
        var lexicalWeight = 0.4
        var mmrLambda = 0.35
        var fusionStyle: RetrievalPlan.FusionStyle = .hybrid
        var reranker: RetrievalPlan.RerankerStrategy = .semantic
        var notes = ["Hybrid weighting keeps vectors authoritative while reserving lexical fallbacks."]

        if technicalDensity > 0.45 {
            vectorWeight += 0.15
            mmrLambda = 0.4
            notes.append("High technical density → emphasize embeddings for acronym-heavy terms.")
        }

        if multilingualScore > 0.6 {
            vectorWeight += 0.1
            notes.append("Language diversity detected → rely on semantic space over keywords.")
        }

        if structuredRatio > 0.35 {
            reranker = .structural
            notes.append("List/table heavy corpus → structured reranker keeps headings aligned.")
        }

        if querySignals.longFormRatio > 0.5 {
            lexicalWeight += 0.1
            notes.append("Users ask long-form questions → keep BM25 weight for descriptive terms.")
        }

        if vectorWeight >= 0.8 {
            fusionStyle = .vectorOnly
            lexicalWeight = 1 - vectorWeight
            notes.append("Vectors dominate due to specialist corpus.")
        } else if lexicalWeight >= 0.55 {
            fusionStyle = .lexicalBoosted
        }

        return RetrievalPlan(
            fusionStyle: fusionStyle,
            vectorWeight: min(0.85, vectorWeight),
            lexicalWeight: max(0.15, lexicalWeight),
            mmrLambda: mmrLambda,
            reranker: reranker,
            notes: notes
        )
    }

    // MARK: - Alerts

    private func makeAlerts(
        from signals: CorpusSignals,
        embeddingPlan: EmbeddingPlan,
        documents: [Document]
    ) -> [String] {
        var alerts: [String] = []
        if signals.multilingualScore > 0.75 {
            alerts.append("High language diversity – consider container-per-language or translation review.")
        }
        if signals.hasCode, signals.hasMath {
            alerts.append("Mixed code + math corpus, enable precision QA before publishing responses.")
        } else if signals.hasCode {
            alerts.append("Code-heavy corpus detected – verify syntax highlighting in UI snippets.")
        }
        if embeddingPlan.requiresCloudConsent {
            alerts.append("Apple FM embeddings need PCC consent before first run.")
        }
        if documents.contains(where: { isVisionAsset($0.contentType) }) {
            alerts.append("OCR documents present – rerun ingestion if lighting artifacts change.")
        }
        return alerts
    }

    private func buildDocumentProfiles(
        documents: [Document],
        chunks: [DocumentChunk]
    ) -> [DocumentProfile] {
        guard !documents.isEmpty else { return [] }
        let groupedChunks = Dictionary(grouping: chunks, by: { $0.documentId })

        return documents.map { document in
            let docChunks = (groupedChunks[document.id] ?? [])
                .sorted(by: { $0.metadata.chunkIndex < $1.metadata.chunkIndex })
            let wordCount = estimateWordCount(for: document, chunks: docChunks)
            let descriptor = makeDescriptor(
                for: document,
                wordCount: wordCount,
                chunkCount: docChunks.count
            )
            let topics = extractTopics(from: docChunks)
            let preview = makePreview(from: docChunks)

            return DocumentProfile(
                id: document.id,
                name: document.filename,
                descriptor: descriptor,
                keyTopics: topics,
                preview: preview,
                addedAt: document.addedAt
            )
        }
        .sorted(by: { $0.addedAt > $1.addedAt })
    }

    private func estimateWordCount(for document: Document, chunks: [DocumentChunk]) -> Int {
        if let totalWords = document.processingMetadata?.totalWords, totalWords > 0 {
            return totalWords
        }
        let metadataSum = chunks.map { $0.metadata.wordCount }.reduce(0, +)
        if metadataSum > 0 {
            return metadataSum
        }
        let adhocText = chunks.map { $0.content }.joined(separator: " ")
        return tokenizeWords(adhocText).count
    }

    private func makeDescriptor(for document: Document, wordCount: Int, chunkCount: Int) -> String {
        var parts: [String] = [friendlyName(for: document.contentType)]
        if wordCount > 0 {
            parts.append("~\(formatCount(wordCount)) words")
        }
        let chunkLabel = chunkCount == 1 ? "chunk" : "chunks"
        parts.append("\(chunkCount) \(chunkLabel)")
        return parts.joined(separator: " • ")
    }

    private func extractTopics(from chunks: [DocumentChunk]) -> [String] {
        var keywordCounts: [String: Int] = [:]
        for chunk in chunks {
            for keyword in chunk.metadata.keywords {
                let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { continue }
                keywordCounts[normalized, default: 0] += 1
            }
        }

        if keywordCounts.isEmpty {
            let fallbackText = chunks.prefix(5).map { $0.content }.joined(separator: " ")
            keywordCounts = wordFrequencyMap(for: fallbackText)
        }

        return keywordCounts
            .sorted(by: { $0.value > $1.value })
            .prefix(3)
            .map { $0.key.capitalized }
    }

    private func makePreview(from chunks: [DocumentChunk]) -> String {
        guard let firstChunk = chunks.first else {
            return "Awaiting chunk extraction."
        }
        let cleaned = firstChunk.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return "Content indexed without an available preview."
        }
        if cleaned.count <= 160 {
            return cleaned
        }
        return "\(cleaned.prefix(160))…"
    }

    private func wordFrequencyMap(for text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for word in tokenizeWords(text) {
            let normalized = word.trimmingCharacters(in: .punctuationCharacters)
            guard !normalized.isEmpty, !topicStopWords.contains(normalized) else { continue }
            counts[normalized, default: 0] += 1
        }
        return counts
    }

    private func friendlyName(for type: DocumentType) -> String {
        switch type {
        case .pdf: return "PDF brief"
        case .markdown: return "Markdown note"
        case .text: return "Text file"
        case .rtf: return "Rich text"
        case .image, .png, .jpeg, .heic, .tiff, .gif: return "Scanned asset"
        case .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc, .go, .rust, .ruby, .php, .shell, .code:
            return "Code reference"
        case .html, .css, .xml: return "Web snippet"
        case .json, .yaml: return "Config/JSON"
        case .sql: return "Data script"
        case .word: return "Word doc"
        case .excel: return "Spreadsheet"
        case .powerpoint: return "Presentation"
        case .pages: return "Pages doc"
        case .numbers: return "Numbers sheet"
        case .keynote: return "Keynote deck"
        case .csv: return "CSV data"
        case .audio, .m4a, .mp3, .wav: return "Audio file"
        case .video, .mp4, .mov: return "Video file"
        case .unknown: return "Document"
        }
    }

    private func formatCount(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }
        if value < 10000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        if value < 1_000_000 {
            return String(format: "%.0fK", Double(value) / 1000.0)
        }
        return String(format: "%.1fM", Double(value) / 1_000_000.0)
    }

    private var topicStopWords: Set<String> {
        [
            "the", "and", "for", "with", "this", "that", "from", "have",
            "about", "your", "into", "also", "will", "their", "when",
            "shall", "should", "where", "while", "there", "which", "been",
            "were", "after", "before", "because", "through", "across", "upon",
            "each", "more", "most", "many", "much", "such", "other",
        ]
    }

    // MARK: - Shared Helpers

    private func detectLanguages(in text: String) -> [NLLanguage: Double] {
        guard !text.isEmpty else { return [:] }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 5)
    }

    private func calculateMultilingualScore(_ hypotheses: [NLLanguage: Double]) -> Double {
        guard !hypotheses.isEmpty else { return 0 }

        // Sort by confidence descending
        let sorted = hypotheses.sorted { $0.value > $1.value }
        guard let dominant = sorted.first else { return 0 }

        // If dominant language is highly confident (>70%), probably monolingual
        // Technical jargon causes low confidence + multiple hypotheses, but that's not "multilingual"
        if dominant.value > 0.70 {
            return 0.0  // High confidence single language = not multilingual
        }

        // Check if there's a genuine second language with meaningful confidence
        // (not just NLLanguageRecognizer hedging on technical content)
        let secondaryLanguages = sorted.dropFirst().filter { $0.value > 0.20 }

        if secondaryLanguages.isEmpty {
            // No secondary language with meaningful confidence
            // Low primary confidence + no alternatives = uncertain detection, not multilingual
            return 0.0
        }

        // There IS a genuine secondary language - calculate how multilingual
        let secondConfidence = secondaryLanguages.first?.value ?? 0
        let spread = 1.0 - (dominant.value - secondConfidence) // How close are top 2?

        // Scale: if dominant=50%, second=40% → spread=0.9 → high multilingual
        // If dominant=60%, second=25% → spread=0.65 → moderate multilingual
        return min(1.0, spread * 0.8)
    }

    private func tokenizeWords(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if word.count > 1 {
                words.append(word)
            }
            return true
        }
        return words
    }

    private func detectTechnicalDensity(words _: [String], uniqueWords: Set<String>) -> Double {
        guard !uniqueWords.isEmpty else { return 0 }
        let technicalPatterns = [
            "tion", "ment", "ness", "ism", "ity",
            "pre", "post", "anti", "inter", "trans",
            "proto", "meta", "hyper", "hypo", "para",
        ]
        var technicalWordCount = 0
        for word in uniqueWords {
            if word.count >= 10 {
                technicalWordCount += 1
                continue
            }
            if word.rangeOfCharacter(from: .decimalDigits) != nil {
                technicalWordCount += 1
                continue
            }
            if word == word.uppercased(), word.count >= 3 {
                technicalWordCount += 1
                continue
            }
            if technicalPatterns.contains(where: { word.contains($0) }) {
                technicalWordCount += 1
            }
        }
        return Double(technicalWordCount) / Double(uniqueWords.count)
    }

    private func detectCodeSnippets(in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let codePatterns = [
            "func ", "def ", "class ", "import ", "function", "const ", "let ", "var ",
            "return ", "if (", "} else", "public ", "private ", "void ", "int ", "String ",
            "```", "::", "#include", "switch (",
        ]
        if codePatterns.contains(where: { text.contains($0) }) {
            return true
        }
        let braceDensity = Double(text.filter { "{}[]".contains($0) }.count)
            / Double(max(1, text.count))
        return braceDensity > 0.02
    }

    private func detectMathematicalContent(in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let mathSymbols = ["∫", "∑", "π", "α", "β", "θ", "∞", "≈", "≤", "≥", "±", "√", "∂", "∇"]
        if mathSymbols.contains(where: { text.contains($0) }) {
            return true
        }
        if text.contains("\\frac") || text.contains("\\sum") || text.contains("\\int") {
            return true
        }
        let equationPattern = try? NSRegularExpression(
            pattern: "[a-zA-Z]\\([a-zA-Z]\\)\\s*=|[a-zA-Z]\\s*=\\s*[a-zA-Z]",
            options: .caseInsensitive
        )
        if let regex = equationPattern,
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        {
            return true
        }
        return false
    }

    private func analyzeSemanticComplexity(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text
        var sentenceLengths: [Int] = []
        var totalClauses = 0
        sentenceTokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentence = String(text[range])
            let words = sentence.split(separator: " ").count
            sentenceLengths.append(words)
            let clauseMarkers = sentence.filter { $0 == "," || $0 == ";" }.count
            totalClauses += clauseMarkers + 1
            return true
        }
        guard !sentenceLengths.isEmpty else { return 0 }
        let avgSentenceLength = Double(sentenceLengths.reduce(0, +)) / Double(sentenceLengths.count)
        let avgClausesPerSentence = Double(totalClauses) / Double(sentenceLengths.count)
        let mean = avgSentenceLength
        let variance = sentenceLengths
            .map { pow(Double($0) - mean, 2) }
            .reduce(0, +) / Double(sentenceLengths.count)
        let stdDev = sqrt(variance)
        let lengthScore = min(1.0, avgSentenceLength / 30.0)
        let clauseScore = min(1.0, max(0, avgClausesPerSentence - 1.0) / 2.0)
        let varianceScore = min(1.0, stdDev / 10.0)
        return (lengthScore + clauseScore + varianceScore) / 3.0
    }

    private func calculateStructuredRatio(from chunks: [DocumentChunk]) -> Double {
        guard !chunks.isEmpty else { return 0 }
        let structured = chunks.filter { $0.metadata.hasListStructure }.count
        return Double(structured) / Double(chunks.count)
    }

    private func extractWordCounts(from chunks: [DocumentChunk], fallback: [String]) -> [Int] {
        if chunks.isEmpty {
            return fallback.isEmpty ? [] : [fallback.count]
        }
        return chunks.map { chunk in
            if chunk.metadata.wordCount > 0 {
                return chunk.metadata.wordCount
            }
            return chunk.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        }
    }

    private func average(of values: [Int]) -> Double {
        guard !values.isEmpty else { return 280 }
        let total = values.reduce(0, +)
        return Double(total) / Double(values.count)
    }

    private func isVisionAsset(_ type: DocumentType) -> Bool {
        switch type {
        case .image, .png, .jpeg, .heic, .tiff, .gif:
            return true
        default:
            return false
        }
    }

    private func recommendConfiguration(
        vocabularyRichness: Double,
        multilingualScore: Double,
        technicalDensity: Double,
        semanticComplexity: Double,
        hasCode: Bool,
        hasMath: Bool,
        totalWords: Int
    ) -> (dimension: Int, provider: String, confidence: Double, reasoning: String) {
        var score384 = 0.0
        let score512 = 0.3
        var score512Contextual = 0.0 // NLContextualEmbedding (high-accuracy 512D)
        // NOTE: 768D removed - our CoreML model (MiniLM-L6-v2) only outputs 384D
        var score1024 = 0.0
        var reasoning: [String] = []

        if totalWords < 1000 {
            score384 += 0.3
            reasoning.append("Compact corpus → prioritize throughput over dimensionality.")
        }
        if vocabularyRichness > 0.5 {
            // Rich vocab: boost contextual and 1024D options (384 CoreML is still fast and good)
            score384 += 0.15  // CoreML 384D handles rich vocab well
            score1024 += 0.3
            score512Contextual += 0.25 // Rich vocab benefits from contextual embeddings
            reasoning.append("Rich vocabulary benefits from additional capacity.")
        } else if vocabularyRichness < 0.3 {
            score384 += 0.2
            reasoning.append("Limited vocabulary suits smaller spaces.")
        }
        if multilingualScore > 0.5 {
            score384 += 0.2  // MiniLM handles multilingual reasonably
            score1024 += 0.2
            score512Contextual += 0.2 // Contextual handles multilingual well
            reasoning.append("Multilingual corpus needs broader manifolds.")
        }
        if technicalDensity > 0.4 {
            score384 += 0.2  // Technical content works with 384D
            score1024 += 0.1
            score512Contextual += 0.3 // Technical content benefits from BERT-like context
            reasoning.append("Technical jargon rewards precision vectors.")
        }
        if semanticComplexity > 0.6 {
            score384 += 0.15
            score1024 += 0.3
            score512Contextual += 0.35 // Complex semantics = contextual embeddings excel
            reasoning.append("Long complex sentences call for expressive embeddings.")
        }
        if hasCode {
            score384 += 0.15
            score512Contextual += 0.2 // Contextual understands code structure
            reasoning.append("Code found → prefer models tuned for structured tokens.")
        }
        if hasMath {
            score384 += 0.1
            score1024 += 0.1
            reasoning.append("Math symbols push for higher fidelity.")
        }
        if totalWords > 50000 {
            score384 += 0.15  // Large corpus still works with 384D
            score1024 += 0.3
            score512Contextual += 0.15 // Large corpus can benefit from accuracy
            reasoning.append("Large corpus justifies research-grade dimensions.")
        }

        // NOTE: 768D option removed - CoreML MiniLM-L6-v2 only outputs 384D
        let scores = [
            (384, score384, "coreml_sentence_embedding"),
            (512, score512, "nl_embedding"),
            (512, score512Contextual, "nl_contextual_embedding"),
            (1024, score1024, "apple_fm_embed"),
        ]
        let winner = scores.max(by: { $0.1 < $1.1 }) ?? (384, 0.3, "coreml_sentence_embedding")
        let dimension = winner.0
        let confidence = min(1.0, winner.1 / 2.0)
        let provider = winner.2

        // Add provider-specific reasoning
        switch provider {
        case "apple_fm_embed":
            reasoning.append("Apple Foundation Models unlock the requested dimensionality.")
        case "nl_contextual_embedding":
            reasoning.append("NLContextualEmbedding provides 15-25% accuracy boost for semantic search.")
        case "coreml_sentence_embedding":
            reasoning.append("Core ML sentence encoder strikes balance for this profile.")
        default:
            reasoning.append("NaturalLanguage embeddings deliver speed with 512D coverage.")
        }
        return (dimension, provider, confidence, reasoning.joined(separator: "; "))
    }
}

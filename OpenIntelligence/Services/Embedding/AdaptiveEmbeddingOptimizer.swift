//
//  AdaptiveEmbeddingOptimizer.swift
//  OpenIntelligence
//
//  Provides a single place to reason about the entire knowledge base.
//  It inspects corpus makeup, recommends chunking + embedding strategies,
//  and shares retrieval tuning guidance for downstream services.
//

import CryptoKit
import Foundation
import NaturalLanguage

/// Performs holistic corpus analysis so the rest of the stack can stay lean.
actor LibraryIntelligenceCenter {
    // MARK: - Public Data Models

    /// The most passages one analysis reads. The analysis joins the text it is given, tokenises
    /// every word and every sentence of it, and is run when a library is opened and after each
    /// import. On 144,247 passages that measured 199 s, and 1,054 MB over what the process held
    /// before it started, on a Mac (11.4 s for 6,000, 43.4 s for 24,000; unoptimised build,
    /// `LibraryAnalysisScaleBenchmarkTests`, 2026-10-13). A library with more passages than this
    /// is analysed from at most this many, taken from across it (`samplePositions`).
    static let analysisPassageLimit = 4_000

    /// The real size of a library whose analysis is given a sample of its passages.
    struct LibrarySize: Sendable {
        let passages: Int
        let passagesByDocument: [UUID: Int]
    }

    /// Which passages an analysis reads when the library (`records`, in store order) and the
    /// passages about to be added to it (`newCount` of them) come to more than `limit`. Nil when
    /// everything fits and every passage is read.
    ///
    /// The two share `limit` in proportion to their sizes. Of the library's share, up to a
    /// quarter goes to the first passage of each document, in store order (a document's preview
    /// is its first passage; a library with more documents than that shows the earliest sampled
    /// passage for the rest), and the remainder to an even sample. The new passages get an even
    /// sample, which always holds their first. No more than `limit` passages are read in all
    /// (one more when `limit` is under 2), and the same library always gives the same positions.
    nonisolated static func samplePositions(
        records: [PassageRecord], newCount: Int, limit: Int
    ) -> (existing: [Int], new: [Int])? {
        let total = records.count + newCount
        guard limit > 0, total > limit else { return nil }
        var existingShare =
            records.isEmpty ? 0 : max(1, Int((Double(limit) * Double(records.count) / Double(total)).rounded()))
        if newCount > 0, !records.isEmpty { existingShare = max(1, min(existingShare, limit - 1)) }
        let newShare = newCount == 0 ? 0 : max(1, limit - existingShare)

        var firstOfDocument: [UUID: (index: Int, position: Int)] = [:]
        for (position, record) in records.enumerated() {
            if let seen = firstOfDocument[record.documentId], seen.index <= record.chunkIndex { continue }
            firstOfDocument[record.documentId] = (record.chunkIndex, position)
        }
        let firsts = firstOfDocument.values.map(\.position).sorted().prefix(existingShare / 4)
        var positions = Set(firsts)
        for position in RAGService.evenSampleIndices(count: records.count, limit: existingShare - firsts.count) {
            positions.insert(position)
        }
        return (positions.sorted(), RAGService.evenSampleIndices(count: newCount, limit: newShare))
    }

    /// Snapshot of the content signals we derive from the current corpus.
    struct CorpusSignals: Sendable {
        let documentCount: Int
        /// Passages in the library.
        let chunkCount: Int
        /// Passages the measurements below were made from: all of them, or an even sample when
        /// the library is past `analysisPassageLimit`.
        let analysedChunkCount: Int
        let avgWordsPerChunk: Double
        let multilingualScore: Double
        let vocabularyRichness: Double
        let technicalDensity: Double
        let semanticComplexity: Double
        let hasCode: Bool
        let hasMath: Bool
        let structuredRatio: Double
        let languageHypotheses: [NLLanguage: Double]

        /// The measurements come from a sample of the library and not from all of it.
        var isEstimate: Bool { analysedChunkCount < chunkCount }
    }

    /// Recommended chunking configuration for ingestion.
    struct ChunkingPlan: Sendable, Codable {
        enum Strategy: String, Sendable, Codable {
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
    struct EmbeddingPlan: Sendable, Codable {
        let providerId: String
        let dimension: Int
        let confidence: Double
        let rationale: String
        let requiresCloudConsent: Bool
    }

    /// Guidance for retrieval weighting + rerankers.
    struct RetrievalPlan: Sendable, Codable {
        enum FusionStyle: String, Sendable, Codable {
            case hybrid
            case vectorOnly
            case lexicalBoosted
        }

        enum RerankerStrategy: String, Sendable, Codable {
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
    struct DocumentProfile: Identifiable, Sendable, Codable {
        let id: UUID
        let name: String
        let descriptor: String
        let keyTopics: [String]
        let preview: String
        let addedAt: Date
    }

    /// Top-level report consumed by the pipeline.
    struct IntelligenceReport: Sendable, Codable {
        let corpus: CorpusSignals
        let chunking: ChunkingPlan
        let embedding: EmbeddingPlan
        let retrieval: RetrievalPlan
        let documents: [DocumentProfile]
        let alerts: [String]
    }

    // MARK: - Public API

    /// Primary entry point. Collapses the corpus into a single actionable report.
    ///
    /// `chunks` is every passage of the library, or, with `library` set, a sample of a library
    /// of that size (`samplePositions` says which). From a sample the ratios and averages are
    /// estimates, the passage counts are the library's real ones, and the word total the
    /// embedding plan looks at is scaled up to the library's size.
    func analyzeLibrary(
        documents: [Document],
        chunks: [DocumentChunk],
        recentQueries: [RAGQuery] = [],
        library: LibrarySize? = nil
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
        let libraryPassages = max(library?.passages ?? chunks.count, chunks.count)
        let totalWords =
            libraryPassages > chunks.count && !chunks.isEmpty
            ? Int(Double(words.count) * Double(libraryPassages) / Double(chunks.count)) : words.count
        let corpusSignals = CorpusSignals(
            documentCount: documents.count,
            chunkCount: libraryPassages,
            analysedChunkCount: chunks.count,
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
            totalWords: totalWords
        )

        let querySignals = analyzeQueries(recentQueries)
        let retrievalPlan = recommendRetrievalPlan(
            multilingualScore: multilingualScore,
            technicalDensity: technicalDensity,
            structuredRatio: structuredRatio,
            querySignals: querySignals
        )

        let alerts = makeAlerts(from: corpusSignals, embeddingPlan: embeddingPlan, documents: documents)
        let documentProfiles = buildDocumentProfiles(
            documents: documents, chunks: chunks, passagesByDocument: library?.passagesByDocument)

        return IntelligenceReport(
            corpus: corpusSignals,
            chunking: chunkingPlan,
            embedding: embeddingPlan,
            retrieval: retrievalPlan,
            documents: documentProfiles,
            alerts: alerts
        )
    }

    /// Recommends a chunking plan for a new document by analyzing its raw text before ingestion.
    func recommendChunkingPlan(forPreviewText text: String, contentType: DocumentType) -> ChunkingPlan {
        let languageHypotheses = detectLanguages(in: text)
        let multilingualScore = calculateMultilingualScore(languageHypotheses)
        let words = tokenizeWords(text)
        let uniqueWords = Set(words)
        _ = detectTechnicalDensity(words: words, uniqueWords: uniqueWords)
        let hasCode = detectCodeSnippets(in: text)
        let hasMath = detectMathematicalContent(in: text)
        _ = analyzeSemanticComplexity(text)
        
        // Estimated structured ratio based on line breaks, lists, or headers
        let lines = text.components(separatedBy: .newlines)
        let structuredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.starts(with: "-") || trimmed.starts(with: "*") || (trimmed.first?.isNumber ?? false)
        }
        let structuredRatio = lines.isEmpty ? 0.0 : Double(structuredLines.count) / Double(lines.count)
        
        // Assume baseline chunk average based on sample words count
        let avgWords = words.isEmpty ? 0.0 : Double(words.count) / 10.0
        
        let dummyDoc = Document(
            id: UUID(),
            filename: "temp",
            fileURL: URL(fileURLWithPath: "/tmp/dummy.pdf"),
            storageRelativePath: nil,
            fileHash: nil,
            contentType: contentType,
            addedAt: Date(),
            totalChunks: 0,
            processingMetadata: nil,
            containerId: nil,
            contentTags: nil
        )
        
        return buildChunkingPlan(
            avgWords: avgWords,
            hasCode: hasCode,
            hasMath: hasMath,
            structuredRatio: structuredRatio,
            documents: [dummyDoc],
            multilingualScore: multilingualScore
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

    /// `passagesByDocument` is given when `chunks` is a sample: it holds how many passages each
    /// document really has, for the count shown and to scale a word count summed from the sample.
    private func buildDocumentProfiles(
        documents: [Document],
        chunks: [DocumentChunk],
        passagesByDocument: [UUID: Int]? = nil
    ) -> [DocumentProfile] {
        guard !documents.isEmpty else { return [] }
        let groupedChunks = Dictionary(grouping: chunks, by: { $0.documentId })

        return documents.map { document in
            let docChunks = (groupedChunks[document.id] ?? [])
                .sorted(by: { $0.metadata.chunkIndex < $1.metadata.chunkIndex })
            let passageCount = max(passagesByDocument?[document.id] ?? docChunks.count, docChunks.count)
            var wordCount = estimateWordCount(for: document, chunks: docChunks)
            if passageCount > docChunks.count, !docChunks.isEmpty,
                (document.processingMetadata?.totalWords ?? 0) <= 0
            {
                wordCount = Int(Double(wordCount) * Double(passageCount) / Double(docChunks.count))
            }
            let descriptor = makeDescriptor(
                for: document,
                wordCount: wordCount,
                chunkCount: passageCount
            )
            let topics = extractTopics(from: docChunks)
            // A document none of whose passages is in the sample has passages; it is not
            // "awaiting chunk extraction", which is what an empty list gets. It is shown with
            // its name and counts and no preview.
            let preview = docChunks.isEmpty && passageCount > 0 ? "" : makePreview(from: docChunks)

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
        let strongPatterns = [
            "func ", "def ", "class ", "#include", "```", "switch (", "if (", "} else",
        ]
        let moderatePatterns = [
            "import ", "const ", "let ", "var ", "return ", "public ", "private ",
            "void ", "int ", "String ", "function", "::",
        ]

        let strongMatches = strongPatterns.filter { text.contains($0) }.count
        let moderateMatches = moderatePatterns.filter { text.contains($0) }.count
        let braceDensity = Double(text.filter { "{}[]".contains($0) }.count)
            / Double(max(1, text.count))
        let semicolonDensity = Double(text.filter { $0 == ";" }.count) / Double(max(1, text.count))

        if strongMatches >= 2 {
            return true
        }

        if strongMatches >= 1 && (braceDensity > 0.01 || semicolonDensity > 0.003) {
            return true
        }

        if moderateMatches >= 3 && braceDensity > 0.01 {
            return true
        }

        return braceDensity > 0.025 && semicolonDensity > 0.004
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
        let variance = sentenceLengths.reduce(0.0) { $0 + pow(Double($1) - mean, 2) }
            / Double(sentenceLengths.count)
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
        var provider = winner.2

        if provider == EmbeddingProviderDefaults.coreML {
            provider = EmbeddingProviderDefaults.preferredSentenceProviderId
        }

        // Add provider-specific reasoning
        switch provider {
        case "apple_fm_embed":
            reasoning.append("Apple Foundation Models unlock the requested dimensionality.")
        case "nl_contextual_embedding":
            reasoning.append("NLContextualEmbedding provides 15-25% accuracy boost for semantic search.")
        case "coreml_sentence_embedding":
            reasoning.append("Core ML sentence encoder strikes balance for this profile.")
        case "coreai_sentence_embedding":
            reasoning.append("Core AI sentence encoder strikes balance for this profile with Silicon-native acceleration.")
        default:
            reasoning.append("NaturalLanguage embeddings deliver speed with 512D coverage.")
        }
        return (dimension, provider, confidence, reasoning.joined(separator: "; "))
    }
}

// MARK: - Keeping a report

extension LibraryIntelligenceCenter.CorpusSignals: Codable {
    private enum CodingKeys: String, CodingKey {
        case documentCount, chunkCount, analysedChunkCount, avgWordsPerChunk, multilingualScore
        case vocabularyRichness, technicalDensity, semanticComplexity, hasCode, hasMath, structuredRatio
        case languageHypotheses
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let languages = try values.decode([String: Double].self, forKey: .languageHypotheses)
        self.init(
            documentCount: try values.decode(Int.self, forKey: .documentCount),
            chunkCount: try values.decode(Int.self, forKey: .chunkCount),
            analysedChunkCount: try values.decode(Int.self, forKey: .analysedChunkCount),
            avgWordsPerChunk: try values.decode(Double.self, forKey: .avgWordsPerChunk),
            multilingualScore: try values.decode(Double.self, forKey: .multilingualScore),
            vocabularyRichness: try values.decode(Double.self, forKey: .vocabularyRichness),
            technicalDensity: try values.decode(Double.self, forKey: .technicalDensity),
            semanticComplexity: try values.decode(Double.self, forKey: .semanticComplexity),
            hasCode: try values.decode(Bool.self, forKey: .hasCode),
            hasMath: try values.decode(Bool.self, forKey: .hasMath),
            structuredRatio: try values.decode(Double.self, forKey: .structuredRatio),
            languageHypotheses: Dictionary(
                uniqueKeysWithValues: languages.map { (NLLanguage(rawValue: $0.key), $0.value) })
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(documentCount, forKey: .documentCount)
        try values.encode(chunkCount, forKey: .chunkCount)
        try values.encode(analysedChunkCount, forKey: .analysedChunkCount)
        try values.encode(avgWordsPerChunk, forKey: .avgWordsPerChunk)
        try values.encode(multilingualScore, forKey: .multilingualScore)
        try values.encode(vocabularyRichness, forKey: .vocabularyRichness)
        try values.encode(technicalDensity, forKey: .technicalDensity)
        try values.encode(semanticComplexity, forKey: .semanticComplexity)
        try values.encode(hasCode, forKey: .hasCode)
        try values.encode(hasMath, forKey: .hasMath)
        try values.encode(structuredRatio, forKey: .structuredRatio)
        try values.encode(
            Dictionary(uniqueKeysWithValues: languageHypotheses.map { ($0.key.rawValue, $0.value) }),
            forKey: .languageHypotheses)
    }
}

/// Keeps each library's last analysis, and the vocabulary its first question builds, on disk
/// until the library changes.
///
/// Both follow from the library's documents and passages and from nothing else, so while those
/// are what they were, opening the app or switching to the library reads the kept file and no
/// passages. What a file was made from is in its name:
/// `<library id>.<report or vocabulary>.<hash of the documents>.<passages in the store>.json`.
/// A file is used only under the name the library has now, so a stale one is never read, and
/// which files are stale can be told from the folder's listing without opening one.
///
/// The files hold text taken from the documents (a preview of each, snippets for the
/// vocabulary). They live in the app's local cache folder, beside the keyword index, which
/// iCloud sync does not copy, and they are removed with what they came from: for one library
/// when its documents change (`removeStale`) or it is deleted (`remove`), and for every library
/// each time the documents are loaded (`sweep`), which is where a document or a library removed
/// on another device arrives.
nonisolated enum LibraryIntelligenceCache {
    /// Raise this when the analysis itself changes, so that reports made by the older analysis
    /// are not used.
    static let analysisVersion = 1

    /// What a kept file was made from.
    struct Signature: Equatable, Sendable {
        /// A hash of the library's documents and of the limits and versions the analysis and
        /// the vocabulary were made under (`documentsSignature`).
        let documents: String
        /// Passages in the library's vector store.
        let passages: Int
    }

    private enum Kind: String {
        case report
        case vocabulary
    }

    /// Where the files are kept. Every function below takes the folder as its last argument,
    /// with this as the default, so a test can work in a folder of its own.
    static var directory: URL {
        AppSupportPaths.localCacheDir().appendingPathComponent("LibraryIntelligence", isDirectory: true)
    }

    /// Thirty-two hexadecimal characters that change when the library's documents do: each
    /// document's id, file hash, passage count, date and name.
    static func documentsSignature(_ documents: [Document]) -> String {
        var text = "v\(analysisVersion)|analysis=\(LibraryIntelligenceCenter.analysisPassageLimit)"
        text += "|vocabulary=\(CorpusVocabulary.buildVersion),\(CorpusVocabulary.vocabularySampleLimit)"
        for document in documents.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            text += "|\(document.id.uuidString),\(document.fileHash ?? "-"),\(document.totalChunks),"
            text += "\(document.addedAt.timeIntervalSince1970),\(document.filename)"
        }
        return SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func signature(documents: [Document], passages: Int) -> Signature {
        Signature(documents: documentsSignature(documents), passages: passages)
    }

    private static func fileURL(_ containerId: UUID, _ kind: Kind, _ signature: Signature, in folder: URL) -> URL {
        folder.appendingPathComponent(
            "\(containerId.uuidString).\(kind.rawValue).\(signature.documents).\(signature.passages).json")
    }

    /// The parts of a kept file's name, or nil when the name is not one this type writes.
    private static func parts(of name: String) -> (containerId: UUID, kind: Kind, signature: Signature)? {
        let pieces = name.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 5, pieces[4] == "json",
            let containerId = UUID(uuidString: String(pieces[0])),
            let kind = Kind(rawValue: String(pieces[1])),
            let passages = Int(pieces[3])
        else { return nil }
        return (containerId, kind, Signature(documents: String(pieces[2]), passages: passages))
    }

    /// Removes every kept file `stale` says to, and anything else found in the folder.
    private static func removeFiles(
        in folder: URL, where stale: (_ containerId: UUID, _ kind: Kind, _ signature: Signature) -> Bool
    ) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names {
            if let file = parts(of: name), !stale(file.containerId, file.kind, file.signature) { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func read<Value: Decodable>(
        _ type: Value.Type, _ containerId: UUID, _ kind: Kind, _ signature: Signature, in folder: URL
    ) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(containerId, kind, signature, in: folder)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<Value: Encodable>(
        _ value: Value, _ containerId: UUID, _ kind: Kind, _ signature: Signature, in folder: URL
    ) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // One file of each kind for a library: the one being written replaces any other.
        removeFiles(in: folder) { id, fileKind, _ in id == containerId && fileKind == kind }
        // Written in place, not through a temporary file. An atomic write keeps its temporary
        // file beside the destination under another name (`<name>.sb-...` on macOS 27), and
        // `removeFiles`, which removes any name it does not know, can run while one is being
        // written. A write cut short leaves a file that does not decode, which reads as nothing
        // kept and is replaced by the next write.
        try? data.write(to: fileURL(containerId, kind, signature, in: folder))
    }

    // The four functions that read or write a file run on the concurrent pool, whoever calls
    // them: a report holds a profile of every document and a vocabulary a set of terms for
    // every keyword, and both are asked for from the main actor.

    @concurrent
    static func loadReport(
        containerId: UUID, signature: Signature, in folder: URL = directory
    ) async -> LibraryIntelligenceCenter.IntelligenceReport? {
        read(LibraryIntelligenceCenter.IntelligenceReport.self, containerId, .report, signature, in: folder)
    }

    @concurrent
    static func saveReport(
        _ report: LibraryIntelligenceCenter.IntelligenceReport, containerId: UUID, signature: Signature,
        in folder: URL = directory
    ) async {
        write(report, containerId, .report, signature, in: folder)
    }

    /// The vocabulary the first question builds from a library's passages (2.7 s for a library
    /// past its 4,000-passage sample, measured on a Mac with `LibraryAnalysisScaleBenchmarkTests`).
    @concurrent
    static func loadVocabulary(
        containerId: UUID, signature: Signature, in folder: URL = directory
    ) async -> CorpusVocabulary? {
        read(CorpusVocabulary.self, containerId, .vocabulary, signature, in: folder)
    }

    @concurrent
    static func saveVocabulary(
        _ vocabulary: CorpusVocabulary, containerId: UUID, signature: Signature, in folder: URL = directory
    ) async {
        write(vocabulary, containerId, .vocabulary, signature, in: folder)
    }

    /// Everything kept for one library.
    static func remove(containerId: UUID, in folder: URL = directory) {
        removeFiles(in: folder) { id, _, _ in id == containerId }
    }

    /// What is kept for one library and was made from other documents than it holds now.
    static func removeStale(containerId: UUID, documents: String, in folder: URL = directory) {
        removeFiles(in: folder) { id, _, signature in id == containerId && signature.documents != documents }
    }

    /// What is kept for any library that is not in `current` (it is gone, or has no documents)
    /// or was made from other documents than `current` gives for it.
    static func sweep(keeping current: [UUID: String], in folder: URL = directory) {
        removeFiles(in: folder) { id, _, signature in current[id] != signature.documents }
    }
}

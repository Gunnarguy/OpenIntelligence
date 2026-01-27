//
//  SuggestedQuestionsService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 2025.
//
//  Dynamically generates suggested questions based on library content.
//  Analyzes document titles, topics, and content to create relevant starter prompts.
//

import Foundation
import NaturalLanguage

/// Service that generates contextual suggested questions based on ingested documents.
/// Enables library-specific starter prompts that showcase RAG capabilities.
actor SuggestedQuestionsService {
    
    // MARK: - Types
    
    /// Category of question templates optimized for RAG demonstration
    enum QuestionCategory: String, CaseIterable {
        case factRetrieval = "fact"          // Direct fact lookup
        case comparison = "compare"           // Compare across documents
        case summarization = "summarize"      // Summarize content
        case procedural = "how"               // How-to questions
        case analytical = "analyze"           // Analysis/reasoning
        case numerical = "numeric"            // Specific numbers/data
    }
    
    /// A generated question with metadata for display
    struct SuggestedQuestion: Identifiable, Sendable {
        let id: UUID
        let text: String
        let category: QuestionCategory
        let relevantDocuments: [String]
        let confidence: Double  // 0-1 confidence this is a good question
    }
    
    /// Analysis result for a document collection
    struct LibraryAnalysis: Sendable {
        let documentTitles: [String]
        let topicKeywords: [String: Int]  // keyword -> frequency
        let entityMentions: [String: Int] // named entities -> frequency
        let hasNumericalData: Bool
        let hasProcedural: Bool           // contains how-to/steps
        let documentTypes: Set<DocumentType>
    }
    
    /// Detected document type for question templating
    enum DocumentType: String, Sendable {
        case manual = "manual"
        case report = "report"
        case article = "article"
        case specification = "spec"
        case guide = "guide"
        case policy = "policy"
        case financial = "financial"
        case technical = "technical"
        case unknown = "unknown"
    }
    
    // MARK: - Properties
    
    private var cachedAnalysis: [UUID: LibraryAnalysis] = [:]
    private var cachedQuestions: [UUID: [SuggestedQuestion]] = [:]
    private let nlTagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
    
    // MARK: - Public API
    
    /// Generate suggested questions for a specific library container
    /// - Parameters:
    ///   - containerId: The library container to analyze
    ///   - documents: Documents in the container
    ///   - sampleChunks: Representative chunks for content analysis
    ///   - count: Number of questions to generate (default 4)
    /// - Returns: Array of contextual suggested questions
    func generateQuestions(
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk],
        count: Int = 4
    ) async -> [SuggestedQuestion] {
        
        // Check cache first
        if let cached = cachedQuestions[containerId], !cached.isEmpty {
            Log.debug("[SuggestedQuestions] Returning \(cached.count) cached questions for container")
            return Array(cached.prefix(count))
        }
        
        // Analyze library content
        let analysis = await analyzeLibrary(
            containerId: containerId,
            documents: documents,
            sampleChunks: sampleChunks
        )
        
        // Generate questions based on analysis
        let questions = generateQuestionsFromAnalysis(analysis, documents: documents)
        
        // Cache and return
        cachedQuestions[containerId] = questions
        Log.info("[SuggestedQuestions] Generated \(questions.count) questions for container")
        
        return Array(questions.shuffled().prefix(count))
    }
    
    /// Invalidate cache when documents change
    func invalidateCache(for containerId: UUID) {
        cachedAnalysis.removeValue(forKey: containerId)
        cachedQuestions.removeValue(forKey: containerId)
        Log.debug("[SuggestedQuestions] Cache invalidated for container")
    }
    
    /// Clear all caches
    func clearAllCaches() {
        cachedAnalysis.removeAll()
        cachedQuestions.removeAll()
    }
    
    // MARK: - Analysis
    
    private func analyzeLibrary(
        containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk]
    ) async -> LibraryAnalysis {
        
        // Check cache
        if let cached = cachedAnalysis[containerId] {
            return cached
        }
        
        var topicKeywords: [String: Int] = [:]
        var entityMentions: [String: Int] = [:]
        var hasNumericalData = false
        var hasProcedural = false
        var documentTypes: Set<DocumentType> = []
        
        // Analyze document titles
        let titles = documents.map { $0.filename }
        for title in titles {
            let type = classifyDocumentType(title)
            documentTypes.insert(type)
            
            // Extract keywords from title
            let keywords = extractKeywords(from: title)
            for keyword in keywords {
                topicKeywords[keyword, default: 0] += 3  // Title keywords weighted higher
            }
        }
        
        // Analyze sample chunks for content patterns
        for chunk in sampleChunks.prefix(50) {  // Limit analysis to avoid performance issues
            let text = chunk.content
            
            // Check for numerical data
            if containsSignificantNumbers(text) {
                hasNumericalData = true
            }
            
            // Check for procedural content
            if containsProceduralIndicators(text) {
                hasProcedural = true
            }
            
            // Extract entities
            let entities = extractNamedEntities(from: text)
            for entity in entities {
                entityMentions[entity, default: 0] += 1
            }
            
            // Extract topic keywords
            let keywords = extractKeywords(from: text)
            for keyword in keywords {
                topicKeywords[keyword, default: 0] += 1
            }
        }
        
        let analysis = LibraryAnalysis(
            documentTitles: titles,
            topicKeywords: topicKeywords,
            entityMentions: entityMentions,
            hasNumericalData: hasNumericalData,
            hasProcedural: hasProcedural,
            documentTypes: documentTypes
        )
        
        cachedAnalysis[containerId] = analysis
        return analysis
    }
    
    // MARK: - Question Generation
    
    private func generateQuestionsFromAnalysis(
        _ analysis: LibraryAnalysis,
        documents: [Document]
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        
        // Get top entities and keywords
        let topEntities = analysis.entityMentions
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
        
        let topKeywords = analysis.topicKeywords
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { $0.key }
        
        // 1. Generate fact retrieval questions
        questions.append(contentsOf: generateFactQuestions(
            entities: topEntities,
            keywords: topKeywords,
            documents: documents
        ))
        
        // 2. Generate summarization questions
        questions.append(contentsOf: generateSummaryQuestions(
            documents: documents,
            documentTypes: analysis.documentTypes
        ))
        
        // 3. Generate numerical questions if data exists
        if analysis.hasNumericalData {
            questions.append(contentsOf: generateNumericalQuestions(
                keywords: topKeywords,
                entities: topEntities,
                documents: documents
            ))
        }
        
        // 4. Generate procedural questions if how-to content exists
        if analysis.hasProcedural {
            questions.append(contentsOf: generateProceduralQuestions(
                keywords: topKeywords,
                documents: documents
            ))
        }
        
        // 5. Generate comparison questions if multiple documents
        if documents.count > 1 {
            questions.append(contentsOf: generateComparisonQuestions(
                documents: documents,
                entities: topEntities
            ))
        }
        
        // 6. Generate analytical questions
        questions.append(contentsOf: generateAnalyticalQuestions(
            keywords: topKeywords,
            documentTypes: analysis.documentTypes,
            documents: documents
        ))
        
        return questions
    }
    
    // MARK: - Question Type Generators
    
    private func generateFactQuestions(
        entities: [String],
        keywords: [String],
        documents: [Document]
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        let templates = [
            "What is {entity}?",
            "Tell me about {entity}.",
            "What does {keyword} mean in this context?",
            "Define {entity} as described in the documents.",
            "What are the key details about {entity}?"
        ]
        
        // Generate questions from entities
        for entity in entities.prefix(3) {
            let template = templates.randomElement() ?? templates[0]
            let questionText = template.replacingOccurrences(of: "{entity}", with: entity)
                .replacingOccurrences(of: "{keyword}", with: entity)
            
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: questionText,
                category: .factRetrieval,
                relevantDocuments: findRelevantDocuments(for: entity, in: documents),
                confidence: 0.8
            ))
        }
        
        return questions
    }
    
    private func generateSummaryQuestions(
        documents: [Document],
        documentTypes: Set<DocumentType>
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        
        // Document-specific summaries
        for doc in documents.prefix(2) {
            let cleanName = cleanDocumentName(doc.filename)
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "Summarize the key points from \(cleanName).",
                category: .summarization,
                relevantDocuments: [doc.filename],
                confidence: 0.9
            ))
        }
        
        // Type-specific templates
        if documentTypes.contains(.manual) || documentTypes.contains(.guide) {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "What are the main features or capabilities described?",
                category: .summarization,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.85
            ))
        }
        
        if documentTypes.contains(.report) || documentTypes.contains(.financial) {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "What are the key findings or conclusions?",
                category: .summarization,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.85
            ))
        }
        
        return questions
    }
    
    private func generateNumericalQuestions(
        keywords: [String],
        entities: [String],
        documents: [Document]
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        let templates = [
            "What are the specific numbers mentioned for {topic}?",
            "List any statistics or figures related to {topic}.",
            "What quantitative data is provided about {entity}?",
            "What are the exact specifications for {topic}?"
        ]
        
        // Pick relevant topics for numerical questions
        let numericalKeywords = keywords.filter { kw in
            let lower = kw.lowercased()
            return lower.contains("price") || lower.contains("cost") ||
                   lower.contains("rate") || lower.contains("percent") ||
                   lower.contains("capacity") || lower.contains("speed") ||
                   lower.contains("size") || lower.contains("year") ||
                   lower.contains("revenue") || lower.contains("budget")
        }
        
        if let topic = numericalKeywords.first ?? entities.first {
            let template = templates.randomElement() ?? templates[0]
            let questionText = template
                .replacingOccurrences(of: "{topic}", with: topic)
                .replacingOccurrences(of: "{entity}", with: topic)
            
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: questionText,
                category: .numerical,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.75
            ))
        }
        
        return questions
    }
    
    private func generateProceduralQuestions(
        keywords: [String],
        documents: [Document]
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        
        // Find procedural keywords
        let proceduralTopics = keywords.filter { kw in
            let lower = kw.lowercased()
            return lower.contains("install") || lower.contains("setup") ||
                   lower.contains("config") || lower.contains("connect") ||
                   lower.contains("start") || lower.contains("create") ||
                   lower.contains("troubleshoot") || lower.contains("repair") ||
                   lower.contains("maintain") || lower.contains("charge")
        }
        
        let templates = [
            "How do I {action}?",
            "What are the steps to {action}?",
            "Walk me through the process of {action}.",
            "What's the procedure for {action}?"
        ]
        
        for topic in proceduralTopics.prefix(2) {
            // Convert keyword to action phrase
            let action = topic.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            
            let template = templates.randomElement() ?? templates[0]
            let questionText = template.replacingOccurrences(of: "{action}", with: action)
            
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: questionText,
                category: .procedural,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.8
            ))
        }
        
        // Generic procedural if no specific topics found
        if proceduralTopics.isEmpty {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "Are there any step-by-step instructions in the documents?",
                category: .procedural,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.6
            ))
        }
        
        return questions
    }
    
    private func generateComparisonQuestions(
        documents: [Document],
        entities: [String]
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        
        if documents.count >= 2 {
            let doc1 = cleanDocumentName(documents[0].filename)
            let doc2 = cleanDocumentName(documents[1].filename)
            
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "Compare the information in \(doc1) and \(doc2).",
                category: .comparison,
                relevantDocuments: [documents[0].filename, documents[1].filename],
                confidence: 0.7
            ))
        }
        
        if let entity = entities.first, documents.count > 1 {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "What do different documents say about \(entity)?",
                category: .comparison,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.7
            ))
        }
        
        return questions
    }
    
    private func generateAnalyticalQuestions(
        keywords: [String],
        documentTypes: Set<DocumentType>,
        documents: [Document]
    ) -> [SuggestedQuestion] {
        
        var questions: [SuggestedQuestion] = []
        
        if documentTypes.contains(.report) || documentTypes.contains(.financial) {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "What trends or patterns are identified in the documents?",
                category: .analytical,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.75
            ))
        }
        
        if documentTypes.contains(.manual) || documentTypes.contains(.technical) {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "What are the limitations or warnings mentioned?",
                category: .analytical,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.75
            ))
        }
        
        if let topic = keywords.first {
            questions.append(SuggestedQuestion(
                id: UUID(),
                text: "What are the implications of \(topic) as discussed?",
                category: .analytical,
                relevantDocuments: documents.map { $0.filename },
                confidence: 0.65
            ))
        }
        
        return questions
    }
    
    // MARK: - Text Analysis Helpers
    
    private func extractKeywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var keywords: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            if let tag = tag, tag == .noun || tag == .verb {
                let word = String(text[range])
                if word.count >= 4 && !isStopWord(word) {
                    keywords.append(word.capitalized)
                }
            }
            return true
        }
        
        return keywords
    }
    
    private func extractNamedEntities(from text: String) -> [String] {
        nlTagger.string = text
        
        var entities: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        nlTagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            if let tag = tag, tag == .personalName || tag == .organizationName || tag == .placeName {
                let entity = String(text[range])
                if entity.count >= 2 {
                    entities.append(entity)
                }
            }
            return true
        }
        
        return entities
    }
    
    private func containsSignificantNumbers(_ text: String) -> Bool {
        // Look for numbers with context (not just page numbers)
        let patterns = [
            #"\$[\d,]+(?:\.\d{2})?"#,           // Currency
            #"\d+(?:\.\d+)?%"#,                  // Percentages
            #"\d{4}"#,                           // Years
            #"\d+(?:,\d{3})+"#,                  // Large numbers with commas
            #"\d+\s*(?:mph|kw|kwh|miles|km|hours|minutes|seconds)"#  // Measurements
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
    
    private func containsProceduralIndicators(_ text: String) -> Bool {
        let indicators = [
            "step 1", "step one", "first,", "1.", "1)", 
            "how to", "instructions", "procedure", "process",
            "install", "setup", "configure", "connect",
            "follow these", "begin by", "start with",
            "warning:", "caution:", "note:", "important:"
        ]
        
        let lower = text.lowercased()
        return indicators.contains { lower.contains($0) }
    }
    
    private func classifyDocumentType(_ filename: String) -> DocumentType {
        let lower = filename.lowercased()
        
        if lower.contains("manual") || lower.contains("owner") {
            return .manual
        } else if lower.contains("guide") || lower.contains("user") {
            return .guide
        } else if lower.contains("report") || lower.contains("annual") {
            return .report
        } else if lower.contains("spec") || lower.contains("technical") {
            return .specification
        } else if lower.contains("policy") || lower.contains("procedure") {
            return .policy
        } else if lower.contains("financial") || lower.contains("budget") || lower.contains("revenue") {
            return .financial
        } else if lower.contains("article") || lower.contains("blog") {
            return .article
        }
        
        return .unknown
    }
    
    private func cleanDocumentName(_ filename: String) -> String {
        // Remove extension and clean up
        var name = filename
        if let dotIndex = name.lastIndex(of: ".") {
            name = String(name[..<dotIndex])
        }
        
        // Replace underscores/hyphens with spaces
        name = name.replacingOccurrences(of: "_", with: " ")
                   .replacingOccurrences(of: "-", with: " ")
        
        // Truncate if too long
        if name.count > 40 {
            name = String(name.prefix(37)) + "..."
        }
        
        return name
    }
    
    private func findRelevantDocuments(for entity: String, in documents: [Document]) -> [String] {
        // Simple heuristic - return all docs for now
        // Could be enhanced to actually search chunk content
        return documents.map { $0.filename }
    }
    
    private func isStopWord(_ word: String) -> Bool {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
            "be", "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "must", "shall", "can", "this",
            "that", "these", "those", "it", "its", "they", "them", "their",
            "we", "us", "our", "you", "your", "he", "she", "him", "her", "his",
            "which", "who", "whom", "what", "when", "where", "why", "how",
            "all", "each", "every", "both", "few", "more", "most", "other",
            "some", "such", "no", "not", "only", "same", "so", "than", "too",
            "very", "just", "also", "now", "here", "there", "then", "once"
        ]
        return stopWords.contains(word.lowercased())
    }
}

// MARK: - Fallback Questions

extension SuggestedQuestionsService {
    
    /// Default questions when no documents are ingested
    static let emptyLibraryQuestions: [String] = [
        "Import documents from the Documents tab to get started.",
        "What types of documents can I add to my library?",
        "How does the search and retrieval system work?"
    ]
    
    /// Generic fallback questions for any library
    static let genericQuestions: [String] = [
        "Summarize the main topics covered in my documents.",
        "What are the most important facts I should know?",
        "List the key entities or subjects mentioned.",
        "What questions can these documents answer?"
    ]
}

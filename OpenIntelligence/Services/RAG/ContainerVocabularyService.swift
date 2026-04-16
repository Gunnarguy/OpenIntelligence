//
//  ContainerVocabularyService.swift
//  OpenIntelligence
//
//  Per-container vocabulary learning from ingested documents.
//  This is Phase 1 of domain adaptation - no model training required.
//
//  How it works:
//  1. During ingestion, extract domain-specific terms (specs, codes, entities)
//  2. Store vocabulary per container (persisted to disk)
//  3. Boost these terms in BM25 search (IDF weighting)
//  4. Use for query expansion (add synonyms/related terms)
//
//  Future (Phase 2-3): Use this vocabulary to train adapter layers
//  when we have user feedback signals (thumbs up/down on answers).
//

import Foundation
import NaturalLanguage

/// Represents learned vocabulary for a container
/// Marked nonisolated to allow Codable operations from actor context
nonisolated struct ContainerVocabulary: Codable, Sendable {
    let containerId: UUID
    var lastUpdated: Date

    /// Domain-specific terms with frequency counts
    /// Key: normalized term, Value: occurrence count across all chunks
    var termFrequencies: [String: Int]

    /// Specification codes detected (ISO 9001, API SN, ASTM D-975, etc.)
    var specificationCodes: Set<String>

    /// Named entities (organizations, products, people)
    var namedEntities: Set<String>

    /// Technical phrases (multi-word domain terms)
    var technicalPhrases: Set<String>

    /// Document count for IDF calculation
    var documentCount: Int

    /// Chunk count for statistics
    var chunkCount: Int

    // MARK: - Computed Properties

    /// Top N most frequent terms (for query expansion)
    func topTerms(_ n: Int = 50) -> [String] {
        termFrequencies
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { $0.key }
    }

    /// Calculate IDF weight for a term (higher = more specific to this container)
    func idfWeight(for term: String) -> Float {
        guard documentCount > 0 else { return 1.0 }
        let tf = Float(termFrequencies[term.lowercased()] ?? 0)
        guard tf > 0 else { return 0.0 }

        // Smoothed IDF: log((N + 1) / (df + 1)) + 1
        // For per-container, we use term frequency as proxy for document frequency
        let smoothedIdf = log(Float(chunkCount + 1) / (tf + 1)) + 1
        return smoothedIdf
    }

    /// Check if term is a known specification code
    func isSpecificationCode(_ term: String) -> Bool {
        specificationCodes.contains(term.uppercased())
    }
}

/// Service for learning and managing per-container vocabularies
actor ContainerVocabularyService {

    static let shared = ContainerVocabularyService()

    private var vocabularies: [UUID: ContainerVocabulary] = [:]
    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        storageURL = appSupport.appendingPathComponent("ContainerVocabularies", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        // Load existing vocabularies
        Task {
            await loadAllVocabularies()
        }
    }

    // MARK: - Public API

    /// Get vocabulary for a container (creates empty if not exists)
    func vocabulary(for containerId: UUID) -> ContainerVocabulary {
        if let existing = vocabularies[containerId] {
            return existing
        }
        let new = ContainerVocabulary(
            containerId: containerId,
            lastUpdated: Date(),
            termFrequencies: [:],
            specificationCodes: [],
            namedEntities: [],
            technicalPhrases: [],
            documentCount: 0,
            chunkCount: 0
        )
        vocabularies[containerId] = new
        return new
    }

    /// Learn vocabulary from a newly ingested chunk
    /// Called during document ingestion
    func learnFromChunk(_ text: String, containerId: UUID) async {
        var vocab = vocabulary(for: containerId)

        // 1. Extract and count terms
        let terms = extractTerms(from: text)
        for term in terms {
            vocab.termFrequencies[term, default: 0] += 1
        }

        // 2. Detect specification codes
        let specs = SpecificationDetector.detectSpecifications(in: text)
        for spec in specs {
            vocab.specificationCodes.insert(spec.value.uppercased())
        }

        // 3. Extract named entities
        let entities = extractNamedEntities(from: text)
        for entity in entities {
            vocab.namedEntities.insert(entity)
        }

        // 4. Extract technical phrases
        let phrases = extractTechnicalPhrases(from: text)
        for phrase in phrases {
            vocab.technicalPhrases.insert(phrase)
        }

        vocab.chunkCount += 1
        vocab.lastUpdated = Date()
        vocabularies[containerId] = vocab
    }

    /// Learn from Vision-detected entities (emails, phones, dates, URLs, etc.)
    /// Called when structured document parsing extracts entities from tables
    func learnFromDetectedEntities(_ entities: [(type: String, value: String)], containerId: UUID) async {
        guard !entities.isEmpty else { return }

        var vocab = vocabulary(for: containerId)

        for entity in entities {
            // Add entity values to named entities
            vocab.namedEntities.insert(entity.value)

            // Also add to term frequencies for IDF boosting
            let normalizedValue = entity.value.lowercased()
            vocab.termFrequencies[normalizedValue, default: 0] += 2  // Double weight for detected entities
        }

        vocab.lastUpdated = Date()
        vocabularies[containerId] = vocab

        Log.debug("[ContainerVocabularyService] Learned \(entities.count) Vision-detected entities", category: .ingestion)
    }

    /// Mark document ingestion complete (for IDF calculation)
    func documentIngested(_ filename: String, containerId: UUID) async {
        guard var vocab = vocabularies[containerId] else { return }
        vocab.documentCount += 1
        vocab.lastUpdated = Date()
        vocabularies[containerId] = vocab

        // Persist after each document
        await saveVocabulary(vocab)
    }

    /// Expand a query with container-specific terms
    /// Returns additional terms to OR with the original query
    func expandQuery(_ query: String, containerId: UUID) -> [String] {
        let vocab = vocabulary(for: containerId)
        var expansions: [String] = []

        let queryTerms = Set(query.lowercased().split(separator: " ").map(String.init))
        let queryLower = query.lowercased()

        // Add matching specification codes
        for code in vocab.specificationCodes {
            if queryTerms.contains(where: { code.lowercased().contains($0) }) {
                expansions.append(code)
            }
        }

        // Add matching technical phrases
        for phrase in vocab.technicalPhrases {
            let phraseWords = Set(phrase.lowercased().split(separator: " ").map(String.init))
            if !queryTerms.isDisjoint(with: phraseWords) {
                expansions.append(phrase)
            }
        }

        // Add matching named entities (Vision-detected emails, phones, addresses, etc.)
        // This helps queries like "john's email" or "contact info" find detected entities
        for entity in vocab.namedEntities {
            let entityLower = entity.lowercased()
            // Match if query contains part of entity or entity contains query term
            if queryTerms.contains(where: { entityLower.contains($0) }) ||
               entityLower.contains(queryLower) {
                expansions.append(entity)
            }
        }

        // Add high-frequency related terms
        for term in vocab.topTerms(20) {
            if queryTerms.contains(where: { term.contains($0) || $0.contains(term) }) {
                expansions.append(term)
            }
        }

        return Array(Set(expansions)).prefix(15).map { $0 }  // Increased limit for entities
    }

    /// Get boost factor for a term in this container
    /// Higher = more important to this specific container
    func boostFactor(for term: String, containerId: UUID) -> Float {
        let vocab = vocabulary(for: containerId)

        // Specification codes get highest boost
        if vocab.isSpecificationCode(term) {
            return 3.0
        }

        // Named entities get moderate boost
        if vocab.namedEntities.contains(term) {
            return 2.0
        }

        // Technical phrases
        if vocab.technicalPhrases.contains(term.lowercased()) {
            return 2.0
        }

        // IDF-based boost for other terms
        let idf = vocab.idfWeight(for: term)
        return max(1.0, idf)
    }

    /// Clear vocabulary for a container (e.g., when container is deleted)
    func clearVocabulary(for containerId: UUID) async {
        vocabularies.removeValue(forKey: containerId)
        let fileURL = storageURL.appendingPathComponent("\(containerId.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Term Extraction

    private func extractTerms(from text: String) -> [String] {
        var terms: [String] = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            guard let tag = tag else { return true }

            // Keep nouns, verbs, adjectives (content words)
            switch tag {
            case .noun, .verb, .adjective:
                let word = String(text[range]).lowercased()
                if word.count >= 3 {
                    terms.append(word)
                }
            default:
                break
            }
            return true
        }

        return terms
    }

    private func extractNamedEntities(from text: String) -> [String] {
        var entities: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .joinNames]
        ) { tag, range in
            guard let tag = tag else { return true }

            switch tag {
            case .personalName, .organizationName, .placeName:
                let entity = String(text[range]).trimmingCharacters(in: .whitespaces)
                if entity.count >= 2 && entity.count <= 50 {
                    entities.append(entity)
                }
            default:
                break
            }
            return true
        }

        return entities
    }

    private func extractTechnicalPhrases(from text: String) -> [String] {
        var phrases: [String] = []

        // Capitalized multi-word phrases (e.g., "Engine Oil", "Brake Fluid")
        let pattern = #"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches.prefix(20) {
                if let swiftRange = Range(match.range, in: text) {
                    let phrase = String(text[swiftRange]).lowercased()
                    if phrase.count >= 5 && phrase.count <= 40 {
                        phrases.append(phrase)
                    }
                }
            }
        }

        return phrases
    }

    // MARK: - Persistence

    private func loadAllVocabularies() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let vocab = decodeVocabulary(from: data) {
                vocabularies[vocab.containerId] = vocab
            }
        }

        Log.debug("[ContainerVocabularyService] Loaded \(vocabularies.count) container vocabularies", category: .initialization)
    }

    private func saveVocabulary(_ vocab: ContainerVocabulary) async {
        let fileURL = storageURL.appendingPathComponent("\(vocab.containerId.uuidString).json")

        do {
            let data = try encodeVocabulary(vocab)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.error("[ContainerVocabularyService] Failed to save vocabulary: \(error)", category: .initialization)
        }
    }

    // MARK: - Codable Helpers
    // Actor-isolated methods that use Codable on the actor's context

    private func decodeVocabulary(from data: Data) -> ContainerVocabulary? {
        try? JSONDecoder().decode(ContainerVocabulary.self, from: data)
    }

    private func encodeVocabulary(_ vocab: ContainerVocabulary) throws -> Data {
        try JSONEncoder().encode(vocab)
    }
}

// MARK: - Future: MLUpdateTask Integration

/*
 Phase 3: On-Device Adapter Training

 When we have user feedback (thumbs up/down on answers), we can train small adapter layers:

 1. Create training pairs from user feedback:
    - Positive: (query, chunk that got thumbs up)
    - Negative: (query, chunk that got thumbs down)

 2. Use contrastive loss to train adapters:
    - Adapter output should increase similarity for positive pairs
    - Decrease similarity for negative pairs

 3. Store trained adapter weights per-container

 Example (pseudocode):

 func trainAdapter(for containerId: UUID, feedback: [(query: String, chunk: String, isPositive: Bool)]) async {
     // 1. Prepare MLBatchProvider with training data
     let batchProvider = ContrastiveBatchProvider(feedback)

     // 2. Load updatable adapter model
     guard let modelURL = Bundle.main.url(forResource: "EmbeddingAdapter", withExtension: "mlmodelc") else { return }

     // 3. Create update task
     let updateTask = try MLUpdateTask(
         forModelAt: modelURL,
         trainingData: batchProvider,
         configuration: nil,
         completionHandler: { context in
             // Save updated model for this container
             let containerModelURL = self.adapterURL(for: containerId)
             try? context.model.write(to: containerModelURL)
         }
     )

     // 4. Run training
     updateTask.resume()
 }

 This requires:
 - Designing an updatable adapter model (small MLP or LoRA layers)
 - Collecting enough feedback (~100+ examples per container)
 - Background training when device is charging
 */

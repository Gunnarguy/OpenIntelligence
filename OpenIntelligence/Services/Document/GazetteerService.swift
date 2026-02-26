//
//  GazetteerService.swift
//  OpenIntelligence
//
//  NLGazetteer-based custom entity recognition for domain-specific terminology.
//  Builds custom gazetteers from ingested document vocabulary to improve NER
//  accuracy on technical terms, product names, and domain jargon.
//

import Foundation
import NaturalLanguage

/// A domain-specific term recognized by the gazetteer
struct GazetteerEntity: Sendable, Hashable {
    let term: String
    let label: String     // e.g., "Product", "Technical", "Organization"
    let source: String    // Document or container that introduced this term
}

/// Service for managing NLGazetteer custom entity dictionaries
/// Enhances NER accuracy by learning domain vocabulary from ingested documents
actor GazetteerService {
    static let shared = GazetteerService()

    // MARK: - State

    /// Custom vocabulary organized by label category
    private var vocabulary: [String: Set<String>] = [:]   // label → set of terms

    /// All known terms for quick lookup
    private var allTerms: Set<String> = []

    /// Compiled gazetteer (rebuilt when vocabulary changes)
    private var compiledGazetteer: NLGazetteer?

    /// Gazetteer data file for persistence
    private let gazetteersURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OpenIntelligence/Gazetteers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_gazetteer.json")
    }()

    private let compiledGazetteerURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OpenIntelligence/Gazetteers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("compiled_gazetteer.mlgazetteer")
    }()

    private init() {
        Task { await loadFromDisk() }
    }

    // MARK: - Vocabulary Management

    /// Add terms extracted from a document to the gazetteer vocabulary
    func addTerms(_ terms: [String], label: String, source: String = "document") {
        var existing = vocabulary[label] ?? []
        var addedCount = 0

        for term in terms {
            let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count >= 2, normalized.count <= 100 else { continue }
            guard !allTerms.contains(normalized.lowercased()) else { continue }

            existing.insert(normalized)
            allTerms.insert(normalized.lowercased())
            addedCount += 1
        }

        vocabulary[label] = existing

        if addedCount > 0 {
            Log.debug("[Gazetteer] Added \(addedCount) terms with label '\(label)' from \(source)", category: .ingestion)
            HardwareTelemetryReporter.pulse(.textChunking, intensity: 0.5, duration: 0.2)
            HardwareTelemetryReporter.reportCPUOperation()
            // Invalidate compiled gazetteer
            compiledGazetteer = nil
            Task { self.saveToDisk() }
        }
    }

    /// Extract domain terms from document text and add to gazetteer
    /// Uses NLTagger NER + heuristics for PascalCase, ACRONYMS, etc.
    func extractAndAddTerms(from text: String, source: String = "document") {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        HardwareTelemetryReporter.pulse(.queryProcessing, intensity: 0.6, duration: 0.3)

        var personNames: [String] = []
        var organizationNames: [String] = []
        var placeNames: [String] = []
        var technicalTerms: [String] = []

        // NER extraction
        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let term = String(text[range])
            guard term.count >= 2 else { return true }

            switch tag {
            case .personalName:
                personNames.append(term)
            case .organizationName:
                organizationNames.append(term)
            case .placeName:
                placeNames.append(term)
            default:
                break
            }
            return true
        }

        // Heuristic extraction: PascalCase and ACRONYMS
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            guard cleaned.count >= 2 else { continue }

            // PascalCase compound words (e.g., CoreML, UIViewController)
            if cleaned.first?.isUppercase == true,
               cleaned.contains(where: { $0.isLowercase }),
               cleaned.dropFirst().contains(where: { $0.isUppercase })
            {
                technicalTerms.append(cleaned)
            }

            // ALL-CAPS acronyms (e.g., HNSW, BM25, RRF)
            if cleaned.count >= 2, cleaned.count <= 10,
               cleaned.allSatisfy({ $0.isUppercase || $0.isNumber })
            {
                technicalTerms.append(cleaned)
            }
        }

        addTerms(personNames, label: "Person", source: source)
        addTerms(organizationNames, label: "Organization", source: source)
        addTerms(placeNames, label: "Place", source: source)
        addTerms(technicalTerms, label: "Technical", source: source)
    }

    // MARK: - Gazetteer Compilation

    /// Compile the current vocabulary into an NLGazetteer for fast lookup
    func compileGazetteer() throws -> NLGazetteer? {
        guard !vocabulary.isEmpty else { return nil }

        // Build the gazetteer data dictionary: [label: [term]]
        var data: [String: [String]] = [:]
        for (label, terms) in vocabulary {
            data[label] = Array(terms)
        }

        // Write training data to temporary JSON for NLGazetteer
        let trainingData = try JSONSerialization.data(withJSONObject: data)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("gazetteer_training.json")
        try trainingData.write(to: tempURL)

        // Compile the gazetteer
        let gazetteer = try NLGazetteer(contentsOf: tempURL)
        compiledGazetteer = gazetteer
        HardwareTelemetryReporter.reportCPUOperation()

        Log.info("[Gazetteer] Compiled gazetteer with \(allTerms.count) terms across \(vocabulary.count) labels", category: .ingestion)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        return gazetteer
    }

    /// Get the compiled gazetteer, compiling if necessary
    func getGazetteer() throws -> NLGazetteer? {
        if let existing = compiledGazetteer {
            return existing
        }
        return try compileGazetteer()
    }

    // MARK: - Entity Recognition with Gazetteer

    /// Recognize entities in text using the custom gazetteer
    /// Returns entities matching domain vocabulary
    func recognizeEntities(in text: String) -> [GazetteerEntity] {
        guard let gazetteer = try? getGazetteer() else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setGazetteers([gazetteer], for: .nameType)

        var entities: [GazetteerEntity] = []

        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if let tag = tag {
                let term = String(text[range])
                entities.append(GazetteerEntity(
                    term: term,
                    label: tag.rawValue,
                    source: "gazetteer"
                ))
            }
            return true
        }

        return entities
    }

    // MARK: - Query Enhancement

    /// Check if a query term matches any gazetteer entries
    /// Used to boost entity-based retrieval
    func matchingTerms(for query: String) -> [GazetteerEntity] {
        let queryWords = query.lowercased().components(separatedBy: .whitespacesAndNewlines)
        var matches: [GazetteerEntity] = []

        for (label, terms) in vocabulary {
            for term in terms {
                if queryWords.contains(term.lowercased()) || query.lowercased().contains(term.lowercased()) {
                    matches.append(GazetteerEntity(term: term, label: label, source: "gazetteer"))
                }
            }
        }

        return matches
    }

    // MARK: - Statistics

    var termCount: Int { allTerms.count }
    var labelCount: Int { vocabulary.count }

    func termCounts() -> [String: Int] {
        vocabulary.mapValues { $0.count }
    }

    // MARK: - Container Scoping

    /// Remove all terms associated with a specific source
    func removeTerms(source: String) {
        for (label, _) in vocabulary {
            vocabulary[label]?.removeAll()
        }
        allTerms.removeAll()
        compiledGazetteer = nil
        Task { self.saveToDisk() }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let vocabData: [String: [String]] = vocabulary.mapValues { Array($0) }
            let data = try JSONEncoder().encode(vocabData)
            try data.write(to: gazetteersURL, options: .atomic)
            Log.debug("[Gazetteer] Saved \(allTerms.count) terms to disk", category: .ingestion)
        } catch {
            Log.error("[Gazetteer] Failed to save: \(error.localizedDescription)", category: .ingestion)
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: gazetteersURL.path) else { return }
        do {
            let data = try Data(contentsOf: gazetteersURL)
            let vocabData = try JSONDecoder().decode([String: [String]].self, from: data)
            vocabulary = vocabData.mapValues { Set($0) }
            allTerms = Set(vocabulary.values.flatMap { $0.map { $0.lowercased() } })
            Log.info("[Gazetteer] Loaded \(allTerms.count) terms from disk", category: .ingestion)
        } catch {
            Log.error("[Gazetteer] Failed to load: \(error.localizedDescription)", category: .ingestion)
        }
    }
}

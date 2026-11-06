//
//  SuggestedQuestionsService+Bank.swift
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
    // MARK: - Persistent Suggested Questions Bank

    /// Load the persisted question bank for a container from disk.
    func loadQuestionBank(for containerId: UUID) -> [SuggestedQuestion] {
        let url = AppSupportPaths.suggestedQuestionsURL(containerId: containerId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let bank = try decoder.decode([SuggestedQuestion].self, from: data)
            return bank
        } catch {
            Log.error("[SuggestedQuestions] Failed to load question bank for \(containerId.uuidString): \(error.localizedDescription)")
            return []
        }
    }

    /// Save the question bank for a container to disk.
    func saveQuestionBank(_ bank: [SuggestedQuestion], for containerId: UUID) {
        let url = AppSupportPaths.suggestedQuestionsURL(containerId: containerId)
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(bank)
            try data.write(to: url, options: .atomic)
            Log.info("[SuggestedQuestions] Saved \(bank.count) questions to bank for \(containerId.uuidString)")
        } catch {
            Log.error("[SuggestedQuestions] Failed to save question bank for \(containerId.uuidString): \(error.localizedDescription)")
        }
    }

    /// Remove questions associated with a document from the container's bank.
    func removeQuestions(for documentId: UUID, in containerId: UUID) {
        var bank = loadQuestionBank(for: containerId)
        bank.removeAll { question in
            question.relevantDocumentIds?.contains(documentId) == true
        }
        saveQuestionBank(bank, for: containerId)
        invalidateCache(for: containerId)
    }

    /// Clear all questions for a container (called when container is cleared)
    func clearQuestionBank(for containerId: UUID) {
        let url = AppSupportPaths.suggestedQuestionsURL(containerId: containerId)
        try? FileManager.default.removeItem(at: url)
        invalidateCache(for: containerId)
    }

    /// Generate suggested questions for a newly ingested document during the ingestion process.
    func generateQuestionsForIngestedDocument(
        _ document: Document,
        chunks: [DocumentChunk],
        in containerId: UUID
    ) async {
        let isSample = Self.sampleIdentity(for: document.filename) != nil
        if isSample {
            Log.info("[SuggestedQuestions] Skipping question generation for sample document '\(document.filename)' during ingestion.")
            return
        }

        Log.info("[SuggestedQuestions] Generating questions for '\(document.filename)' during ingestion...")
        let questions = await generateQuestionsForDocumentOnly(document, chunks: chunks)
        Log.info("[SuggestedQuestions] Generated \(questions.count) questions for '\(document.filename)'. Merging into bank...")
        mergeIntoPersistedBank(newQuestions: questions, for: containerId)
    }

    #if canImport(FoundationModels)
    @MainActor
    var isSystemLLMAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }
    #else
    @MainActor
    var isSystemLLMAvailable: Bool {
        return false
    }
    #endif

    private func generateQuestionsForDocumentOnly(
        _ document: Document,
        chunks: [DocumentChunk]
    ) async -> [SuggestedQuestion] {
        let diverseChunks = selectDiverseChunks(from: chunks, documents: [document], targetCount: 12)
        guard !diverseChunks.isEmpty else { return [] }

        var questions: [SuggestedQuestion] = []

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), await isSystemLLMAvailable {
            let llmQuestions = await generateDirectlyWithLLM(
                chunks: diverseChunks,
                documents: [document],
                avoidTexts: []
            )
            if llmQuestions.count >= 2 {
                questions = llmQuestions
            }
        }
        #endif

        if questions.isEmpty {
            let contentQuestions = generateFromContent(chunks: diverseChunks, documents: [document], avoidTexts: [])
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), await isSystemLLMAvailable, !contentQuestions.isEmpty {
                let polishedQuestions = await generateWithLLM(
                    baseQuestions: contentQuestions,
                    chunks: diverseChunks,
                    documents: [document],
                    avoidTexts: []
                )
                // Fail closed. The header of this file promises that weak document-shaped prompts
                // are dropped rather than padded, and until 2026-09-14 this line did the opposite:
                // when the model declined every template, the raw templates shipped, which is
                // where "What is the silicon?" came from. With the model present, its silence is
                // the answer. The raw templates survive only below, for a device with no model.
                questions = polishedQuestions
                if questions.isEmpty {
                    Log.info("[SuggestedQuestions] Model produced no grounded question for '\(document.filename)'; showing none rather than templates")
                }
            } else {
                questions = contentQuestions
            }
            #else
            questions = contentQuestions
            #endif
        }

        let mapped = questions.map { q in
            SuggestedQuestion(
                id: q.id,
                text: q.text,
                category: q.category,
                relevantDocuments: q.relevantDocuments,
                relevantDocumentIds: [document.id],
                sourceSections: q.sourceSections,
                confidence: q.confidence,
                isLLMGenerated: q.isLLMGenerated
            )
        }

        return mapped.filter { shouldSurfaceSuggestedQuestion($0) }
    }

    private func mergeIntoPersistedBank(newQuestions: [SuggestedQuestion], for containerId: UUID) {
        var bank = loadQuestionBank(for: containerId)
        bank.append(contentsOf: newQuestions)
        bank = dedupeSuggestedQuestionsPreservingOrder(bank)
        bank = pruneNearDuplicateQuestions(bank)
        bank = enforceBankDiversity(bank, maxCount: 25)
        saveQuestionBank(bank, for: containerId)
        invalidateCache(for: containerId)
    }

    private func enforceBankDiversity(_ questions: [SuggestedQuestion], maxCount: Int) -> [SuggestedQuestion] {
        guard questions.count > maxCount else { return questions }
        
        var byDoc: [String: [SuggestedQuestion]] = [:]
        for q in questions {
            let docKey = q.relevantDocuments.first ?? "unknown"
            byDoc[docKey, default: []].append(q)
        }
        
        for key in byDoc.keys {
            byDoc[key]?.sort { a, b in
                if a.isLLMGenerated != b.isLLMGenerated {
                    return a.isLLMGenerated
                }
                return a.confidence > b.confidence
            }
        }
        
        var selected: [SuggestedQuestion] = []
        let docKeys = Array(byDoc.keys).sorted()
        
        var round = 0
        while selected.count < maxCount {
            var addedThisRound = false
            for key in docKeys {
                guard selected.count < maxCount else { break }
                guard let docQs = byDoc[key], round < docQs.count else { continue }
                selected.append(docQs[round])
                addedThisRound = true
            }
            round += 1
            if !addedThisRound { break }
        }
        
        return selected
    }

    private func generateInitialBank(
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk]
    ) async -> [SuggestedQuestion] {
        Log.info("[SuggestedQuestions] Bank is empty, generating initial set on-demand...")
        var generated: [SuggestedQuestion] = []
        for doc in documents {
            let docChunks = sampleChunks.filter { $0.documentId == doc.id }
            if !docChunks.isEmpty {
                let docQs = await generateQuestionsForDocumentOnly(doc, chunks: docChunks)
                generated.append(contentsOf: docQs)
            }
        }
        let deduped = dedupeSuggestedQuestionsPreservingOrder(generated)
        let pruned = pruneNearDuplicateQuestions(deduped)
        let bank = enforceBankDiversity(pruned, maxCount: 25)
        saveQuestionBank(bank, for: containerId)
        return bank
    }

    // MARK: - Public API

    /// Generate suggested questions for a specific library container.
    ///
    /// Questions are retrieved from the persisted library question bank.
    /// Shuffled/shuffled subsets are returned to keep the chips fresh.
    ///
    /// - Parameters:
    ///   - containerId: Active container UUID
    ///   - documents: Documents in the container
    ///   - sampleChunks: Representative chunks (up to 50)
    ///   - count: Number of questions to return
    ///   - forceRefresh: Shuffle and pick different questions from the bank
    func generateQuestions(
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk],
        count: Int = 4,
        forceRefresh: Bool = false
    ) async -> [SuggestedQuestion] {

        let existingCached = cachedQuestions[containerId]

        // Fast path: a library of sample documents gets their hand-written questions, which
        // skip all generation.
        if let curated = Self.curatedSampleQuestions(forFilenames: documents.map(\.filename)) {
            if forceRefresh {
                // On refresh, shuffle and pick a different subset
                let shuffled = curated.shuffled()
                let selected = Array(shuffled.prefix(count))
                cachedQuestions[containerId] = CachedEntry(
                    questions: selected,
                    documentCount: documents.count,
                    generatedAt: Date()
                )
                Log.info("[SuggestedQuestions] Returning \(selected.count) curated sample workspace questions (refreshed)")
                return selected
            }
            if let cached = existingCached,
               cached.documentCount == documents.count,
               Date().timeIntervalSince(cached.generatedAt) < Self.cacheMaxAge {
                return Array(cached.questions.prefix(count))
            }
            let selected = Array(curated.prefix(count))
            cachedQuestions[containerId] = CachedEntry(
                questions: selected,
                documentCount: documents.count,
                generatedAt: Date()
            )
            Log.info("[SuggestedQuestions] Returning \(selected.count) curated sample workspace questions")
            return selected
        }

        // Check cache — but only if not forcing refresh, doc count unchanged, and cache fresh
        if !forceRefresh,
           let cached = existingCached,
           cached.documentCount == documents.count,
           Date().timeIntervalSince(cached.generatedAt) < Self.cacheMaxAge {
            Log.debug("[SuggestedQuestions] Returning \(cached.questions.count) cached questions for container")
            return Array(cached.questions.prefix(count))
        }

        // Load the bank from disk
        var bank = loadQuestionBank(for: containerId)

        // Fallback: if bank is empty but we have documents, generate the initial bank on-demand
        if bank.isEmpty && !documents.isEmpty && !sampleChunks.isEmpty {
            bank = await generateInitialBank(for: containerId, documents: documents, sampleChunks: sampleChunks)
        }

        // A bank generated while the model was unavailable is all templates, and until 2026-09-14
        // it was served forever: nothing ever asked again. The sample library hits this exactly,
        // because its bank is built on first launch, when Apple Intelligence is least likely to be
        // ready. Rebuild once per launch when the model is here and the bank has never seen it.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           !documents.isEmpty, !sampleChunks.isEmpty,
           !bankRebuildAttempted.contains(containerId),
           Self.shouldRebuildBank(bank, modelAvailable: await isSystemLLMAvailable) {
            bankRebuildAttempted.insert(containerId)
            Log.info("[SuggestedQuestions] Bank of \(bank.count) has no model-written question and the model is available; rebuilding once")
            // `generateInitialBank` has already saved the rebuilt bank, empty or not, so the
            // in-memory copy must agree with the disk: an empty rebuild means no chips, which is
            // the fail-closed contract, not a reason to keep serving the templates it replaced.
            bank = await generateInitialBank(for: containerId, documents: documents, sampleChunks: sampleChunks)
        }
        #endif

        // Filter out questions for documents that no longer exist
        let docNames = Set(documents.map { displayDocumentName($0.filename) })
        bank = bank.filter { q in
            guard let primaryDoc = q.relevantDocuments.first else { return false }
            return docNames.contains(primaryDoc)
        }

        guard !bank.isEmpty else {
            Log.debug("[SuggestedQuestions] No questions in bank, returning empty")
            return []
        }

        // Select a shuffled subset prioritizing fresh ones (not currently shown in cache)
        let previousTexts = Set(existingCached?.questions.map { $0.text } ?? [])
        let freshQuestions = bank.filter { !previousTexts.contains($0.text) }
        
        let pool = freshQuestions.isEmpty ? bank : freshQuestions
        let selected = selectDiverseSubset(pool, count: count)

        cachedQuestions[containerId] = CachedEntry(
            questions: selected,
            documentCount: documents.count,
            generatedAt: Date()
        )

        Log.info("[SuggestedQuestions] Returning \(selected.count) questions from bank (refresh: \(forceRefresh))")
        return selected
    }

    private func selectDiverseSubset(_ questions: [SuggestedQuestion], count: Int) -> [SuggestedQuestion] {
        guard questions.count > count else { return questions }
        
        let pool = questions.shuffled()
        var selected: [SuggestedQuestion] = []
        
        var selectedDocuments = Set<String>()
        var selectedCategories = Set<QuestionCategory>()
        var selectedStartWords = Set<String>()
        
        func startWord(of text: String) -> String {
            let words = text.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
            return words.first?.trimmingCharacters(in: .punctuationCharacters) ?? ""
        }
        
        // Pass 1: Strict diversity — only add if the document, category, and start word are all unique.
        for q in pool {
            guard selected.count < count else { break }
            let doc = q.relevantDocuments.first ?? ""
            let cat = q.category
            let sw = startWord(of: q.text)
            
            if !selectedDocuments.contains(doc) && !selectedCategories.contains(cat) && !selectedStartWords.contains(sw) {
                selected.append(q)
                selectedDocuments.insert(doc)
                selectedCategories.insert(cat)
                selectedStartWords.insert(sw)
            }
        }
        
        // Pass 2: Relaxed document/category uniqueness — allow repeating documents/categories if needed, but keep start words unique.
        for q in pool {
            guard selected.count < count else { break }
            guard !selected.contains(where: { $0.id == q.id }) else { continue }
            let sw = startWord(of: q.text)
            
            if !selectedStartWords.contains(sw) {
                selected.append(q)
                selectedDocuments.insert(q.relevantDocuments.first ?? "")
                selectedCategories.insert(q.category)
                selectedStartWords.insert(sw)
            }
        }
        
        // Pass 3: Fill up the remaining slots with whatever is left.
        for q in pool {
            guard selected.count < count else { break }
            guard !selected.contains(where: { $0.id == q.id }) else { continue }
            selected.append(q)
        }
        
        return selected
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

    /// Check if a valid, fresh cache exists for the container.
    func hasValidCache(for containerId: UUID, documentCount: Int) -> Bool {
        guard let cached = cachedQuestions[containerId] else { return false }
        guard cached.documentCount == documentCount else { return false }
        if cached.questions.isEmpty && documentCount > 0 {
            return false
        }
        return Date().timeIntervalSince(cached.generatedAt) < Self.cacheMaxAge
    }

    private enum TimeoutError: Error {
        case timedOut
    }

    func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut
            }
            
            let result = try await group.next()
            group.cancelAll()
            if let result {
                return result
            } else {
                throw TimeoutError.timedOut
            }
        }
    }

}

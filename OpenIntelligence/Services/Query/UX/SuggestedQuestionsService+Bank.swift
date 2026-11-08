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
        ingestionQuestionsInFlight.insert(document.id)
        defer { ingestionQuestionsInFlight.remove(document.id) }
        // A run cancelled or timed out (iOS ending the import's background task, the model busy) saves nothing, and
        // Chat writes this file's questions when it next shows the library (`fillMissingQuestions`). Until 5.8 it was
        // saved as "no questions" and nothing asked again (owner's iPhone, 2026-11-07).
        guard let questions = await generateQuestionsForDocumentOnly(document, chunks: chunks) else {
            Log.info(
                "[SuggestedQuestions] Questions for '\(document.filename)' were interrupted during ingestion; nothing saved, Chat writes them later"
            )
            return
        }
        Log.info("[SuggestedQuestions] Generated \(questions.count) questions for '\(document.filename)'. Merging into bank...")
        mergeIntoPersistedBank(newQuestions: questions, for: containerId)
    }

    #if canImport(FoundationModels)
    @MainActor
    var isSystemLLMAvailable: Bool {
        if #available(iOS 26.0, *) {
            return !DirectModelCallsForTesting.isOn && SystemLanguageModel.default.isAvailable
        }
        return false
    }
    #else
    @MainActor
    var isSystemLLMAvailable: Bool {
        return false
    }
    #endif

    /// The questions for one document, or nil when a model call was cancelled or timed out and nothing came of the
    /// run: that is not the model's answer, so the caller saves nothing and the file is asked about again (5.8).
    private func generateQuestionsForDocumentOnly(
        _ document: Document,
        chunks: [DocumentChunk]
    ) async -> [SuggestedQuestion]? {
        let diverseChunks = selectDiverseChunks(from: chunks, documents: [document], targetCount: 12)
        guard !diverseChunks.isEmpty else {
            Log.info(
                "[SuggestedQuestions] None of the \(chunks.count) passage(s) given for '\(document.filename)' is usable for a question; none written"
            )
            return []
        }

        var questions: [SuggestedQuestion] = []
        var interrupted = false

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), await isSystemLLMAvailable {
            let llmQuestions = await generateDirectlyWithLLM(
                chunks: diverseChunks,
                documents: [document],
                avoidTexts: [],
                interrupted: &interrupted
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
                    avoidTexts: [],
                    interrupted: &interrupted
                )
                // Fail closed. The header of this file promises that weak document-shaped prompts
                // are dropped rather than padded, and until 2026-09-14 this line did the opposite:
                // when the model declined every template, the raw templates shipped, which is
                // where "What is the silicon?" came from. With the model present, its silence is
                // the answer. The raw templates survive only below, for a device with no model.
                questions = polishedQuestions
                if questions.isEmpty, !interrupted, !Task.isCancelled {
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

        let surfaced = mapped.filter { shouldSurfaceSuggestedQuestion($0) }
        if surfaced.isEmpty, interrupted || Task.isCancelled { return nil }
        return surfaced
    }

    /// A cancelled task or a timed-out model call (5.8).
    nonisolated static func isInterruption(_ error: Error) -> Bool {
        error is CancellationError || error is TimeoutError || Task.isCancelled
    }

    /// The files that get questions written when Chat shows a library (5.8): those with none in the bank, whose
    /// import is not still adding its own, that have not had a finished run this launch, and whose runs have not been
    /// interrupted `maxInterruptedFillAttempts` times. A finished run that wrote none counts as finished: no
    /// templates in place of the model's silence.
    nonisolated static func documentsNeedingQuestions(
        bankDocumentNames: Set<String>,
        documents: [(id: UUID, name: String)],
        skip: Set<UUID>,
        interruptedAttempts: [UUID: Int]
    ) -> [UUID] {
        documents.filter { document in
            !bankDocumentNames.contains(document.name) && !skip.contains(document.id)
                && interruptedAttempts[document.id, default: 0] < maxInterruptedFillAttempts
        }.map(\.id)
    }

    nonisolated static let maxInterruptedFillAttempts = 3
    /// The most questions a library's bank keeps, spread across its files (`enforceBankDiversity`).
    nonisolated static let maxBankSize = 25
    /// Files written per refresh, so a large library fills over a few visits instead of holding the model for minutes.
    nonisolated static let maxFilesFilledPerRefresh = 3

    /// Writes questions for the files of `documents` that have none in `bank`, merges them into the saved bank and
    /// returns it. Until 5.8 questions were written here only when the whole bank was empty, and every cancelled run
    /// (a library switch, a tab change) saved an empty bank: a two-file library on the owner's iPhone showed none for a
    /// minute on 2026-11-07, and a file whose import-time run was cancelled never got any.
    private func fillMissingQuestions(
        in bank: [SuggestedQuestion],
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk],
        passagesForDocument: (@Sendable (UUID) async -> [DocumentChunk])?
    ) async -> [SuggestedQuestion] {
        // A full bank has no room: a library of more files than it holds questions keeps some files without any.
        guard bank.count < Self.maxBankSize else { return bank }
        let pendingImport = Set(RAGService.deferredEnrichments().map(\.document))
        let skip = pendingImport.union(ingestionQuestionsInFlight).union(questionFillSettled).union(questionFillInFlight)
        let missingIds = Set(
            Self.documentsNeedingQuestions(
                bankDocumentNames: Set(bank.compactMap { $0.relevantDocuments.first }),
                documents: documents.map { (id: $0.id, name: displayDocumentName($0.filename)) },
                skip: skip,
                interruptedAttempts: questionFillAttempts
            ))
        let missing = Array(documents.filter { missingIds.contains($0.id) }.prefix(Self.maxFilesFilledPerRefresh))
        guard !missing.isEmpty else { return bank }
        if bank.isEmpty {
            Log.info("[SuggestedQuestions] Bank is empty, generating initial set on-demand...")
        } else {
            Log.info("[SuggestedQuestions] \(missing.count) file(s) have no question in the bank; writing theirs")
        }

        var written: [SuggestedQuestion] = []
        for document in missing {
            guard !Task.isCancelled else {
                Log.info("[SuggestedQuestions] Fill cancelled before '\(document.filename)'; nothing saved for it")
                break
            }
            // The file's own passages, read from the store (`passagesForDocument`); the library's sample only when
            // there is no reader or it found none (5.8).
            questionFillInFlight.insert(document.id)
            var documentChunks: [DocumentChunk] = []
            if let passagesForDocument { documentChunks = await passagesForDocument(document.id) }
            if documentChunks.isEmpty { documentChunks = sampleChunks.filter { $0.documentId == document.id } }
            guard !documentChunks.isEmpty else {
                questionFillInFlight.remove(document.id)
                Log.info("[SuggestedQuestions] No passage of '\(document.filename)' was found to write questions from")
                continue
            }
            let questions = await generateQuestionsForDocumentOnly(document, chunks: documentChunks)
            questionFillInFlight.remove(document.id)
            guard let questions else {
                questionFillAttempts[document.id, default: 0] += 1
                Log.info("[SuggestedQuestions] Questions for '\(document.filename)' were interrupted; nothing saved")
                continue
            }
            questionFillSettled.insert(document.id)
            Log.info(
                "[SuggestedQuestions] Wrote \(questions.count) question(s) for '\(document.filename)' from \(documentChunks.count) of its passages"
            )
            written.append(contentsOf: questions)
        }
        guard !written.isEmpty else { return bank }
        mergeIntoPersistedBank(newQuestions: written, for: containerId)
        return loadQuestionBank(for: containerId)
    }

    private func mergeIntoPersistedBank(newQuestions: [SuggestedQuestion], for containerId: UUID) {
        var bank = loadQuestionBank(for: containerId)
        bank.append(contentsOf: newQuestions)
        bank = dedupeSuggestedQuestionsPreservingOrder(bank)
        bank = pruneNearDuplicateQuestions(bank)
        bank = enforceBankDiversity(bank, maxCount: Self.maxBankSize)
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

    /// Rebuilds a template-only bank with the model, or returns nil and saves nothing when a run was interrupted (5.8).
    private func generateInitialBank(
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk]
    ) async -> [SuggestedQuestion]? {
        var generated: [SuggestedQuestion] = []
        for doc in documents {
            let docChunks = sampleChunks.filter { $0.documentId == doc.id }
            if !docChunks.isEmpty {
                guard let docQs = await generateQuestionsForDocumentOnly(doc, chunks: docChunks) else {
                    Log.info("[SuggestedQuestions] Rebuild interrupted at '\(doc.filename)'; the saved bank stays as it was")
                    return nil
                }
                generated.append(contentsOf: docQs)
            }
        }
        let deduped = dedupeSuggestedQuestionsPreservingOrder(generated)
        let pruned = pruneNearDuplicateQuestions(deduped)
        let bank = enforceBankDiversity(pruned, maxCount: Self.maxBankSize)
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
    ///   - passagesForDocument: Reads one document's passages for a file with no questions yet (5.8)
    func generateQuestions(
        for containerId: UUID,
        documents: [Document],
        sampleChunks: [DocumentChunk],
        count: Int = 4,
        forceRefresh: Bool = false,
        passagesForDocument: (@Sendable (UUID) async -> [DocumentChunk])? = nil
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

        // Write questions for each file that has none yet (5.8; until then only for an empty bank).
        if !documents.isEmpty && !sampleChunks.isEmpty {
            bank = await fillMissingQuestions(
                in: bank, for: containerId, documents: documents, sampleChunks: sampleChunks,
                passagesForDocument: passagesForDocument)
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
            if let rebuilt = await generateInitialBank(
                for: containerId, documents: documents, sampleChunks: sampleChunks)
            {
                bank = rebuilt
            } else {
                bankRebuildAttempted.remove(containerId)
            }
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

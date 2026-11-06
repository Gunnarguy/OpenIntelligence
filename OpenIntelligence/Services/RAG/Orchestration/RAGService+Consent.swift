//
//  RAGService+Consent.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Cloud Consent

    func loadPersistedConsentStates() -> [CloudProvider: CloudConsentState] {
        var states: [CloudProvider: CloudConsentState] = [:]
        states.reserveCapacity(CloudProvider.allCases.count)
        for provider in CloudProvider.allCases {
            let key = ConsentDefaults.key(for: provider)
            if let raw = UserDefaults.standard.string(forKey: key),
                let state = CloudConsentState(rawValue: raw)
            {
                states[provider] = state
            } else {
                states[provider] = .notDetermined
            }
        }
        return states
    }

    private func persistConsentState(_ state: CloudConsentState, for provider: CloudProvider) {
        let defaults = UserDefaults.standard
        let key = ConsentDefaults.key(for: provider)
        if state == .notDetermined {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(state.rawValue, forKey: key)
        }
        // Force immediate sync to disk - important for dev builds where Xcode may kill app quickly
        defaults.synchronize()
        Log.info("[Consent] Persisted \(provider.shortName) = \(state.rawValue)", category: .initialization)
    }

    /// The settings the app's screens use, once `registerSettingsStore` has run. An action changes
    /// these so the open chat follows at once (`SetAnswerModeIntent`, 5.7).
    @MainActor
    var registeredSettingsStore: SettingsStore? { settingsStore }

    @MainActor
    func registerSettingsStore(_ store: SettingsStore) {
        settingsStore = store
        queryRuntimeCoordinator = QueryRuntimeCoordinator(settingsStore: store)
        // Defer sync so SwiftUI finishes its current view update before we publish changes.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyInitialCloudConsent(from: store)
        }
    }

    /// Rebuild search indexes from the canonical list of documents.
    @MainActor
    func rebuildDatabase() async -> Bool {
        return await rebuildLocalSearchIndexesFromCanonicalState(documents: self.documents)
    }

    /// Rebuild the active LLM service and fallback chain from the current SettingsStore.
    /// This keeps runtime routing aligned with Settings without requiring app restart.
    @MainActor
    func rebuildLLMServicesFromSettings() async {
        guard let store = settingsStore else { return }

        let primaryKey = store.selectedModel.rawValue
        var primary: LLMService =
            Self.instantiateService(for: primaryKey, entitlementStore: entitlementStore)
            ?? AppleFoundationLLMServiceUnavailable()

        var fallbacks: [LLMService] = []
        fallbacks.reserveCapacity(2)

        if store.enableFirstFallback {
            if let service = Self.instantiateService(
                for: store.firstFallback.rawValue, entitlementStore: entitlementStore),
                service.modelName != primary.modelName
            {
                fallbacks.append(service)
            }
        }

        if store.enableSecondFallback {
            if let service = Self.instantiateService(
                for: store.secondFallback.rawValue, entitlementStore: entitlementStore),
                service.modelName != primary.modelName,
                !fallbacks.contains(where: { $0.modelName == service.modelName })
            {
                fallbacks.append(service)
            }
        }

        // Ensure tool handler remains connected for agentic RAG.
        primary.toolHandler = self
        for i in fallbacks.indices {
            fallbacks[i].toolHandler = self
        }

        updateLLMService(primary, fallbacks: fallbacks)
    }

    @MainActor
    private func applyInitialCloudConsent(from store: SettingsStore) {
        if cloudConsent[.applePCC] != store.applePCCConsent {
            setCloudConsentState(
                store.applePCCConsent,
                for: .applePCC,
                propagateToSettings: false
            )
        }
    }

    /// Brings this engine's copy of the stored consent choices up to date (5.7). Each engine reads
    /// them when it is made; a choice changed in Settings, or made in a sheet another engine showed,
    /// reached only the app's own engine until a relaunch.
    @MainActor
    func refreshCloudConsentFromDefaults() {
        for (provider, state) in loadPersistedConsentStates() where (cloudConsent[provider] ?? .notDetermined) != state {
            cloudConsent[provider] = state
            transientConsentGrants.remove(provider)
        }
    }

    @MainActor
    func setCloudConsentState(
        _ state: CloudConsentState,
        for provider: CloudProvider,
        propagateToSettings: Bool = true
    ) {
        cloudConsent[provider] = state
        transientConsentGrants.remove(provider)
        persistConsentState(state, for: provider)
        if propagateToSettings {
            settingsStore?.setCloudConsent(state, for: provider, propagateToRAG: false)
        }
    }

    @MainActor
    func resolveCloudConsent(decision: CloudConsentDecision) async {
        guard let record = pendingCloudConsent else {
            Log.warning("resolveCloudConsent called with no pending record", category: .pipeline)
            return
        }
        let provider = record.provider
        let continuation = pendingConsentContinuation
        pendingConsentContinuation = nil
        pendingCloudConsent = nil

        switch decision {
        case .allowOnce:
            await recordTransmission(record, grant: "allow_once")
            continuation?.resume(returning: .allowOnce)
        case .allowAndRemember:
            setCloudConsentState(.allowed, for: provider)
            await recordTransmission(record, grant: "remembered")
            continuation?.resume(returning: .allowAndRemember)
        case .deny:
            setCloudConsentState(.denied, for: provider)
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Cloud call denied",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                    "chars": "\(record.promptCharacterCount)",
                    "chunks": "\(record.contextChunkCount)",
                    "planID": record.planID?.uuidString ?? "legacy",
                ]
            )
            continuation?.resume(returning: .deny)
        }
    }

    /// A consent sheet no window showed (`CloudConsentRelay`): the question goes on without Private
    /// Cloud Compute and nothing is remembered, unlike Don't Allow. Only the request it names: a newer
    /// one on this engine is left alone.
    @MainActor
    func abandonCloudConsentRequest(_ id: UUID) {
        guard pendingCloudConsent?.id == id else { return }
        let continuation = pendingConsentContinuation
        pendingConsentContinuation = nil
        pendingCloudConsent = nil
        consentRequestWentUnseen = true
        VerificationJournal.record(
            "consent.refused", ["reason": "unseen", "relay": "\(asksThroughRelay)", "background": "\(Self.appIsInBackground)"])
        CloudConsentRelay.shared.withdraw(id)
        continuation?.resume(returning: .deny)
    }

    func makeTransmissionRecord(
        provider: CloudProvider,
        modelName: String,
        prompt: String,
        context: String?,
        chunks: [DocumentChunk],
        modelExecutionPlan: ModelExecutionPlan? = nil
    ) -> CloudTransmissionRecord {
        let sanitizedPrompt = prompt.replacingOccurrences(of: "\n", with: " ")
        let preview = String(sanitizedPrompt.prefix(160))
        let estimatedBytes = prompt.utf8.count + (context?.utf8.count ?? 0)

        var hashes: [String] = []
        hashes.reserveCapacity(min(chunks.count, 12))
        for chunk in chunks.prefix(12) {
            let data = Data(chunk.content.utf8)
            let digest = SHA256.hash(data: data)
            hashes.append(hexString(from: digest))
        }

        return CloudTransmissionRecord(
            provider: provider,
            modelName: modelName,
            promptPreview: preview,
            promptCharacterCount: prompt.count,
            contextCharacterCount: context?.count ?? 0,
            contextChunkCount: chunks.count,
            contextHashes: hashes,
            estimatedBytes: estimatedBytes,
            planID: modelExecutionPlan?.id,
            routeReason: modelExecutionPlan?.stages.first(where: { $0.role == .synthesize })?.reason
        )
    }

    func hexString(from digest: SHA256.Digest) -> String {
        var result = String()
        result.reserveCapacity(SHA256Digest.byteCount * 2)
        for byte in digest {
            result.append(String(format: "%02x", byte))
        }
        return result
    }

    func cloudProvider(for service: LLMService) -> CloudProvider? {
        switch service {
        #if canImport(FoundationModels)
            case is AppleFoundationLLMService:
                return .applePCC
        #endif
        default:
            return nil
        }
    }

    func getLaunchArgumentValue(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        let prefix = "--\(key)="
        if let arg = args.first(where: { $0.hasPrefix(prefix) }) {
            return String(arg.dropFirst(prefix.count))
        }
        let fullKey = "--\(key)"
        if let idx = args.firstIndex(of: fullKey) {
            let nextIdx = args.index(after: idx)
            if nextIdx < args.endIndex {
                let val = args[nextIdx]
                if !val.hasPrefix("--") {
                    return val
                }
            }
        }
        return nil
    }

    // MARK: - Universal Pipeline Tracing

    /// Log chunk content previews at each pipeline stage for debugging
    /// Shows first 100 chars of each chunk with score and page info
    func logChunkTrace(_ chunks: [RetrievedChunk], stage: String, query: String) {
        #if DEBUG
            guard Log.pipelineTraceEnabled else { return }

            let separator = String(repeating: "─", count: 60)
            print("\n\(separator)")
            print("📊 CHUNK TRACE: \(stage) (\(chunks.count) chunks)")
            print("   Query: \(query.prefix(50))\(query.count > 50 ? "..." : "")")
            print(separator)

            // Extract key terms from query for highlighting
            let queryTerms = extractQueryTerms(query)

            for (idx, chunk) in chunks.prefix(10).enumerated() {
                let content = chunk.chunk.contextText
                let preview = String(content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                let score = String(format: "%.3f", chunk.similarityScore)
                let page = chunk.pageNumber.map { "p.\($0)" } ?? "?"
                let section = chunk.chunk.metadata.sectionTitle ?? "—"

                // Check if chunk contains any query terms
                let contentLower = content.lowercased()
                let matchedTerms = queryTerms.filter { contentLower.contains($0) }
                let termMatch = matchedTerms.isEmpty ? "" : " ✓[\(matchedTerms.joined(separator: ","))]"

                print("  [\(idx)] score=\(score) \(page) §\(section.prefix(20))\(termMatch)")
                print("       \"\(preview)...\"")
            }

            if chunks.count > 10 {
                print("  ... and \(chunks.count - 10) more chunks")
            }
            print(separator)
        #endif
    }

    /// Log final assembled context with keyword analysis
    func logFinalContext(_ context: String, actualChunksUsed: Int, query: String) {
        #if DEBUG
            guard Log.pipelineTraceEnabled else { return }

            let separator = String(repeating: "═", count: 60)
            print("\n\(separator)")
            print("📝 FINAL CONTEXT SENT TO LLM")
            print("   Query: \(query)")
            print("   Context: \(context.count) chars, \(actualChunksUsed) chunks")
            print(separator)

            // Extract key terms and check coverage
            let queryTerms = extractQueryTerms(query)
            let contextLower = context.lowercased()

            var foundTerms: [String] = []
            var missingTerms: [String] = []

            for term in queryTerms {
                if contextLower.contains(term) {
                    foundTerms.append(term)
                } else {
                    missingTerms.append(term)
                }
            }

            print("   Query terms found: \(foundTerms.joined(separator: ", "))")
            if !missingTerms.isEmpty {
                print("   ⚠️ Missing terms: \(missingTerms.joined(separator: ", "))")
            }

            // Show first 500 chars preview
            let preview = String(context.prefix(500)).replacingOccurrences(of: "\n", with: "↵")
            print("   Preview: \"\(preview)...\"")
            print(separator)
        #endif
    }

    /// Scan all chunks for specification patterns and report findings
    /// This helps diagnose whether specs are present in the corpus
    func runViscosityScan(_ allChunks: [DocumentChunk], query: String) async {
        #if DEBUG
            guard Log.pipelineTraceEnabled else { return }

            let separator = String(repeating: "═", count: 60)
            print("\n\(separator)")
            print("🔍 CORPUS SPECIFICATION SCAN")
            print("   Query: \(query)")
            print("   Total chunks: \(allChunks.count)")
            print(separator)

            // Scan for specification patterns (numbers with units, codes, grades)
            let specPattern = #"\b\d+(?:\.\d+)?\s*(?:W-\d+|L|ml|mm|cm|kg|g|psi|kPa|°[CF])\b"#
            var specChunks: [(idx: Int, page: Int?, match: String, preview: String)] = []

            for (idx, chunk) in allChunks.enumerated() {
                let content = chunk.content
                if let range = content.range(of: specPattern, options: .regularExpression) {
                    let match = String(content[range])
                    let preview = String(content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                    specChunks.append((idx, chunk.metadata.pageNumber, match, preview))
                }
            }

            if specChunks.isEmpty {
                print("   ⚠️ NO SPECIFICATION PATTERNS FOUND")
                print("   Specifications may be in images/tables not extracted as text")
            } else {
                print("   ✅ Found \(specChunks.count) chunks with specification patterns:")
                for sc in specChunks.prefix(8) {
                    let section = allChunks[sc.idx].metadata.sectionTitle ?? "—"
                    print("   [\(sc.idx)] p.\(sc.page ?? 0) §\(section.prefix(25))")
                    print("       Match: \(sc.match)")
                    print("       \"\(sc.preview)...\"")
                }
                if specChunks.count > 8 {
                    print("   ... and \(specChunks.count - 8) more")
                }
            }
            print(separator)
        #endif
    }

}

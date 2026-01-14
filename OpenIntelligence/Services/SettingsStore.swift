//
//  SettingsStore.swift
//  OpenIntelligence
//
//  Centralized settings state and persistence.
//  Bridges SwiftUI bindings to UserDefaults-backed storage keys used across the app.
//  Debounces change notifications for downstream application (e.g., model switching).
//
//  NOTE: Local model support (GGUF, CoreML, MLX) has been removed.
//  The app now uses Apple Intelligence and On-Device Analysis only.
//

import Combine
import Foundation
import SwiftUI

/// Central settings state shared across the app.
/// - Persists values to `UserDefaults` so SwiftUI `@AppStorage` bindings stay in sync.
/// - Emits debounced apply notifications once related settings change.
@MainActor
final class SettingsStore: ObservableObject {
    // MARK: - Keys (mirror existing @AppStorage in SettingsRootView.swift)

    /// Backing keys for settings stored in `UserDefaults`.
    private enum Keys {
        static let selectedModel = "selectedLLMModel" // LLMModelType.rawValue
        static let execContext = "executionContext" // "automatic" | "onDeviceOnly" | "preferCloud" | "cloudOnly"
        static let temperature = "llmTemperature" // Double
        static let maxTokens = "llmMaxTokens" // Int
        static let contextLength = "llmContextLength" // Int
        static let topP = "llmTopP" // Double
        static let frequencyPenalty = "llmFrequencyPenalty" // Double
        static let presencePenalty = "llmPresencePenalty" // Double
        static let repetitionPenalty = "llmRepetitionPenalty" // Double
        static let systemPrompt = "llmSystemPrompt" // String
        static let lenient = "lenientRetrievalMode" // Bool
        static let enableFB1 = "enableFirstFallback" // Bool
        static let enableFB2 = "enableSecondFallback" // Bool
        static let firstFB = "firstFallbackModel" // LLMModelType.rawValue
        static let secondFB = "secondFallbackModel" // LLMModelType.rawValue
        static let primaryModelUserOverride = "primaryModelUserOverride"

        // Reviewer & consent
        static let reviewerModeEnabled = "reviewerModeEnabled"
        static let applePCCConsent = "cloudConsent.applePCC"

        // Developer tuning
        static let developerRAGTuning = "developer.ragAdvancedTuning"
        static let reliabilityModeEnabled = "ragReliabilityModeEnabled"

        // Embedding provider
        static let defaultEmbeddingProvider = "defaultEmbeddingProvider"
        static let useHighAccuracyEmbeddings = "useHighAccuracyEmbeddings"

        // Quality mode - "standard" | "deepThink" (legacy: "fast" | "balanced" | "thorough" | "agentic")
        static let ragQualityMode = "ragQualityMode"

        // Advanced RAG Intelligence (all enabled by default, controlled by mode)
        static let enableQueryRewriting = "enableQueryRewriting"
        static let enableIterativeRetrieval = "enableIterativeRetrieval"
        static let enableHyDE = "enableHyDE"
        static let enableContextualCompression = "enableContextualCompression"
        static let enableParentDocumentRetrieval = "enableParentDocumentRetrieval"
        static let enableConversationMemory = "enableConversationMemory"

        // Appearance
        static let appAccentColorHex = "appAccentColorHex" // nil = system default
    }

    // MARK: - Published Settings (bind from UI)

    /// Primary inference pathway the user selected.
    @Published var selectedModel: LLMModelType

    /// Active execution strategy describing how queries are routed.
    @Published var executionContext: ExecutionContext

    /// Temperature applied to generative models.
    @Published var temperature: Double
    /// Response length ceiling for the active model.
    @Published var maxTokens: Int
    /// Context window size (if supported by backend).
    @Published var contextLength: Int
    /// Nucleus sampling probability.
    @Published var topP: Double
    /// Frequency penalty (0.0 - 2.0).
    @Published var frequencyPenalty: Double
    /// Presence penalty (0.0 - 2.0).
    @Published var presencePenalty: Double
    /// Repetition penalty (1.0 - 2.0).
    @Published var repetitionPenalty: Double
    /// System prompt to prepend to conversations.
    @Published var systemPrompt: String

    /// Loosens similarity thresholds during retrieval when enabled.
    @Published var lenientRetrievalMode: Bool

    /// Controls whether the first fallback model participates in routing.
    @Published var enableFirstFallback: Bool
    /// Controls whether the second fallback model participates in routing.
    @Published var enableSecondFallback: Bool
    /// Model used when the primary pathway fails.
    @Published var firstFallback: LLMModelType
    /// Secondary fallback when both primary and first fallback are unavailable.
    @Published var secondFallback: LLMModelType

    /// Reviewer utilities toggle (exposes advanced controls in Settings).
    @Published var reviewerModeEnabled: Bool
    /// Saved consent preference for Apple PCC transmissions.
    @Published var applePCCConsent: CloudConsentState

    /// Developer-only: allow advanced RAG tuning controls.
    @Published var developerRAGTuningEnabled: Bool
    /// Reliability-first behavior: never surface user-facing errors; prefer best-effort fallbacks.
    @Published var reliabilityModeEnabled: Bool

    // MARK: - Embedding Settings

    /// Default embedding provider for new containers.
    /// Primary: "coreml_sentence_embedding" (384D, Neural Engine accelerated)
    /// Legacy: "nl_embedding", "nl_contextual_embedding" (for existing containers)
    @Published var defaultEmbeddingProvider: String
    /// Legacy setting - no longer affects provider selection (CoreML is always used).
    /// Kept for backward compatibility with existing user defaults.
    @Published var useHighAccuracyEmbeddings: Bool

    // MARK: - Advanced RAG Intelligence

    /// Enable LLM-powered query rewriting before retrieval.
    /// Rewrites vague queries ("press this button") into specific domain queries.
    @Published var enableQueryRewriting: Bool

    /// Enable iterative retrieval (retrieve → assess → refine → retrieve more).
    /// When enabled, the system will perform multiple retrieval passes until confident.
    @Published var enableIterativeRetrieval: Bool

    /// Enable HyDE (Hypothetical Document Embeddings) for better retrieval.
    /// Generates a hypothetical answer first, then embeds that for search.
    /// Most effective for factual queries where question vocab differs from answer vocab.
    @Published var enableHyDE: Bool

    /// Enable contextual compression to extract only query-relevant content from chunks.
    /// Reduces token usage and improves answer quality by filtering irrelevant sentences.
    @Published var enableContextualCompression: Bool

    /// Enable parent document retrieval to expand matched chunks with sibling context.
    /// When a chunk matches, include surrounding chunks from the same section/page.
    /// Improves coherence for multi-paragraph answers.
    @Published var enableParentDocumentRetrieval: Bool

    /// Enable conversation memory for multi-turn context awareness.
    /// Summarizes long conversations and injects relevant context into queries.
    /// Improves follow-up questions and pronoun resolution.
    @Published var enableConversationMemory: Bool

    // MARK: - Quality Mode

    /// Controls the accuracy/speed tradeoff for RAG queries.
    /// - fast: Quick responses with basic retrieval
    /// - balanced: Good accuracy with smart context selection (default)
    /// - thorough: Maximum accuracy with multi-pass verification
    @Published var ragQualityMode: RAGQualityMode

    // MARK: - Appearance

    /// App-wide accent color. nil = use system default.
    /// When set, overrides the tint color throughout the app.
    @Published var appAccentColorHex: String?

    // MARK: - Infra

    private let defaults: UserDefaults
    private let ragService: RAGService
    private let deviceCapabilities: DeviceCapabilities
    private var cancellables = Set<AnyCancellable>()
    private let applySubject = PassthroughSubject<Void, Never>()
    /// Tracks whether the user manually picked a primary model (vs. auto-selection).
    @Published private(set) var hasUserPrimaryOverride: Bool
    private var isApplyingProgrammaticSelection = false

    // MARK: - Model Availability

    /// Models that can be shown in the primary picker given current hardware.
    /// Primary LLM choices available to the user.
    var primaryModelOptions: [LLMModelType] {
        var options: [LLMModelType] = []

        if deviceCapabilities.supportsAppleIntelligence
            || deviceCapabilities.supportsFoundationModels
        {
            options.append(.appleIntelligence)
        }

        // On-Device Analysis is always available
        options.append(.onDeviceAnalysis)

        return options
    }

    /// Canonical fallback order.
    private var fallbackBaseOptions: [LLMModelType] {
        var ordered: [LLMModelType] = []
        var seen = Set<LLMModelType>()

        func append(_ type: LLMModelType) {
            guard !seen.contains(type) else { return }
            seen.insert(type)
            ordered.append(type)
        }

        // Always prioritize Apple Intelligence first on capable devices
        if deviceCapabilities.supportsAppleIntelligence || deviceCapabilities.supportsFoundationModels {
            append(.appleIntelligence)
        }

        // On-device analysis is always the ultimate fallback
        append(.onDeviceAnalysis)

        return ordered
    }

    /// Ordered fallback candidates filtered by the provided exclusion list.
    func fallbackOptions(excluding disallowed: Set<LLMModelType>) -> [LLMModelType] {
        var ordered: [LLMModelType] = []
        var seen = Set<LLMModelType>()

        func appendIfNeeded(_ type: LLMModelType) {
            guard !disallowed.contains(type), !seen.contains(type) else { return }
            seen.insert(type)
            ordered.append(type)
        }

        fallbackBaseOptions.forEach { appendIfNeeded($0) }
        appendIfNeeded(firstFallback)
        appendIfNeeded(secondFallback)

        return ordered
    }

    /// Updates the selected model without marking the change as a user override.
    private func setSelectedModelProgrammatically(_ newValue: LLMModelType) {
        guard selectedModel != newValue else { return }
        isApplyingProgrammaticSelection = true
        selectedModel = newValue
        isApplyingProgrammaticSelection = false
    }

    /// Validates that a given model can run on the current hardware/configuration.
    private func isPrimarySelectionAvailable(_ selection: LLMModelType) -> Bool {
        switch selection {
        case .appleIntelligence:
            return deviceCapabilities.supportsAppleIntelligence
                || deviceCapabilities.supportsFoundationModels
        case .onDeviceAnalysis:
            return true
        }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard, ragService: RAGService) {
        self.defaults = defaults
        self.ragService = ragService
        deviceCapabilities = RAGService.checkDeviceCapabilities()

        // Load persisted values with sensible defaults
        // Migrate deprecated model types to Apple Intelligence
        if let raw = defaults.string(forKey: Keys.selectedModel) {
            selectedModel = LLMModelType.migrate(from: raw)
        } else {
            // Default to Apple Intelligence on capable devices, otherwise On-Device Analysis
            if deviceCapabilities.supportsAppleIntelligence || deviceCapabilities.supportsFoundationModels {
                selectedModel = .appleIntelligence
            } else {
                selectedModel = .onDeviceAnalysis
            }
        }

        let execRaw = defaults.string(forKey: Keys.execContext) ?? "automatic"
        executionContext = ExecutionContext.from(raw: execRaw)

        temperature = (defaults.object(forKey: Keys.temperature) as? Double) ?? 0.7
        maxTokens = (defaults.object(forKey: Keys.maxTokens) as? Int) ?? 2048
        contextLength = (defaults.object(forKey: Keys.contextLength) as? Int) ?? 4096
        topP = (defaults.object(forKey: Keys.topP) as? Double) ?? 0.9
        frequencyPenalty = (defaults.object(forKey: Keys.frequencyPenalty) as? Double) ?? 0.0
        presencePenalty = (defaults.object(forKey: Keys.presencePenalty) as? Double) ?? 0.0
        repetitionPenalty = (defaults.object(forKey: Keys.repetitionPenalty) as? Double) ?? 1.0
        systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? "You are a helpful assistant."

        lenientRetrievalMode = defaults.object(forKey: Keys.lenient) as? Bool ?? false

        enableFirstFallback = defaults.object(forKey: Keys.enableFB1) as? Bool ?? true
        enableSecondFallback = defaults.object(forKey: Keys.enableFB2) as? Bool ?? true

        // Migrate deprecated fallback selections
        if let raw1 = defaults.string(forKey: Keys.firstFB) {
            firstFallback = LLMModelType.migrate(from: raw1)
        } else {
            firstFallback = .onDeviceAnalysis
        }

        if let raw2 = defaults.string(forKey: Keys.secondFB) {
            secondFallback = LLMModelType.migrate(from: raw2)
        } else {
            secondFallback = .onDeviceAnalysis
        }

        reviewerModeEnabled =
            defaults.object(forKey: Keys.reviewerModeEnabled) as? Bool ?? false
        #if !DEBUG
            // Release builds must never persist reviewer mode; force-disable.
            reviewerModeEnabled = false
            defaults.set(false, forKey: Keys.reviewerModeEnabled)
        #endif
        let appleConsentRaw = defaults.string(forKey: Keys.applePCCConsent)
        applePCCConsent =
            CloudConsentState(rawValue: appleConsentRaw ?? "") ?? .notDetermined
        hasUserPrimaryOverride =
            defaults.object(forKey: Keys.primaryModelUserOverride) as? Bool ?? false
        developerRAGTuningEnabled = false
        defaults.set(false, forKey: Keys.developerRAGTuning)
        reliabilityModeEnabled =
            defaults.object(forKey: Keys.reliabilityModeEnabled) as? Bool ?? true

        // Embedding provider settings (CoreML is the primary provider)
        defaultEmbeddingProvider = defaults.string(forKey: Keys.defaultEmbeddingProvider) ?? "coreml_sentence_embedding"
        useHighAccuracyEmbeddings = defaults.object(forKey: Keys.useHighAccuracyEmbeddings) as? Bool ?? true

        // Advanced RAG Intelligence settings
        // Query rewriting defaults to true (enabled) for better understanding
        enableQueryRewriting = defaults.object(forKey: Keys.enableQueryRewriting) as? Bool ?? true
        // Iterative retrieval defaults to false (controlled by quality mode)
        enableIterativeRetrieval = defaults.object(forKey: Keys.enableIterativeRetrieval) as? Bool ?? false
        // HyDE defaults to true - significant retrieval improvement for factual queries
        enableHyDE = defaults.object(forKey: Keys.enableHyDE) as? Bool ?? true
        // Contextual compression defaults to true - saves tokens and improves quality
        enableContextualCompression = defaults.object(forKey: Keys.enableContextualCompression) as? Bool ?? true
        // Parent document retrieval defaults to true - improves multi-paragraph coherence
        enableParentDocumentRetrieval = defaults.object(forKey: Keys.enableParentDocumentRetrieval) as? Bool ?? true
        // Conversation memory defaults to true - enables multi-turn context awareness
        enableConversationMemory = defaults.object(forKey: Keys.enableConversationMemory) as? Bool ?? true

        // Appearance settings
        // Accent color - nil means use system default
        appAccentColorHex = defaults.string(forKey: Keys.appAccentColorHex)

        // Quality mode - load from UserDefaults or default to standard
        if let savedMode = defaults.string(forKey: Keys.ragQualityMode),
           let mode = RAGQualityMode(rawValue: savedMode)
        {
            ragQualityMode = mode
        } else {
            ragQualityMode = .standard
            defaults.set(RAGQualityMode.standard.rawValue, forKey: Keys.ragQualityMode)
        }
        lenientRetrievalMode = false
        defaults.set(false, forKey: Keys.lenient)

        // Auto-upgrade from On-Device Analysis to Apple Intelligence if device is capable
        if selectedModel == .onDeviceAnalysis,
           !hasUserPrimaryOverride,
           isPrimarySelectionAvailable(.appleIntelligence)
        {
            setSelectedModelProgrammatically(.appleIntelligence)
        }

        sanitizeModelSelectionForPlatform()
        setupPipelines()
        ragService.registerSettingsStore(self)
    }

    // MARK: - Pipelines

    /// Wires change observers so `@Published` values stay persisted and applied.
    private func setupPipelines() {
        $selectedModel
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isApplyingProgrammaticSelection { return }
                if !self.hasUserPrimaryOverride {
                    self.hasUserPrimaryOverride = true
                    self.defaults.set(true, forKey: Keys.primaryModelUserOverride)
                }
            }
            .store(in: &cancellables)

        // Persist each setting change; coalesce downstream apply
        let publishers: [AnyPublisher<Void, Never>] = [
            $selectedModel.map { _ in () }.eraseToAnyPublisher(),
            $executionContext.map { _ in () }.eraseToAnyPublisher(),
            $temperature.map { _ in () }.eraseToAnyPublisher(),
            $maxTokens.map { _ in () }.eraseToAnyPublisher(),
            $contextLength.map { _ in () }.eraseToAnyPublisher(),
            $topP.map { _ in () }.eraseToAnyPublisher(),
            $frequencyPenalty.map { _ in () }.eraseToAnyPublisher(),
            $presencePenalty.map { _ in () }.eraseToAnyPublisher(),
            $repetitionPenalty.map { _ in () }.eraseToAnyPublisher(),
            $systemPrompt.map { _ in () }.eraseToAnyPublisher(),
            $lenientRetrievalMode.map { _ in () }.eraseToAnyPublisher(),
            $enableFirstFallback.map { _ in () }.eraseToAnyPublisher(),
            $enableSecondFallback.map { _ in () }.eraseToAnyPublisher(),
            $firstFallback.map { _ in () }.eraseToAnyPublisher(),
            $secondFallback.map { _ in () }.eraseToAnyPublisher(),
            $reviewerModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            $applePCCConsent.map { _ in () }.eraseToAnyPublisher(),
            $reliabilityModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            $defaultEmbeddingProvider.map { _ in () }.eraseToAnyPublisher(),
            $useHighAccuracyEmbeddings.map { _ in () }.eraseToAnyPublisher(),
            $enableQueryRewriting.map { _ in () }.eraseToAnyPublisher(),
            $enableIterativeRetrieval.map { _ in () }.eraseToAnyPublisher(),
            $enableHyDE.map { _ in () }.eraseToAnyPublisher(),
            $enableContextualCompression.map { _ in () }.eraseToAnyPublisher(),
            $enableParentDocumentRetrieval.map { _ in () }.eraseToAnyPublisher(),
            $enableConversationMemory.map { _ in () }.eraseToAnyPublisher(),
            $appAccentColorHex.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(publishers)
            .sink { [weak self] in
                guard let self else { return }
                self.persistAll()
                self.applySubject.send()
            }
            .store(in: &cancellables)

        $reviewerModeEnabled
            .dropFirst()
            .sink { [weak self] _ in
                self?.sanitizeModelSelectionForPlatform()
            }
            .store(in: &cancellables)

        $developerRAGTuningEnabled
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                // Developer tuning is deprecated - always disabled
                if self.developerRAGTuningEnabled {
                    self.developerRAGTuningEnabled = false
                }
                if self.lenientRetrievalMode {
                    self.lenientRetrievalMode = false
                }
                self.defaults.set(false, forKey: Keys.developerRAGTuning)
                self.defaults.set(false, forKey: Keys.lenient)
            }
            .store(in: &cancellables)

        $ragQualityMode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                self.defaults.set(mode.rawValue, forKey: Keys.ragQualityMode)
            }
            .store(in: &cancellables)

        #if !DEBUG
            // Guardrail: ignore any reviewer mode toggles in release builds.
            $reviewerModeEnabled
                .dropFirst()
                .sink { [weak self] enabled in
                    guard let self, enabled else { return }
                    self.reviewerModeEnabled = false
                }
                .store(in: &cancellables)
        #endif

        // Sync high-accuracy toggle with embedding provider selection
        // CoreML Sentence Embedding is the only provider, so this is a no-op now
        // Kept for backward compatibility with existing settings
        $useHighAccuracyEmbeddings
            .dropFirst()
.sink { [weak self] _ in
                guard let self else { return }
                // Always use CoreML - it's the only supported provider
                self.defaultEmbeddingProvider = "coreml_sentence_embedding"
            }
            .store(in: &cancellables)

        // Debounced apply (lightweight for now; can be expanded to actually swap services)
        applySubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.applySettingsDebounced()
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    /// Writes the current in-memory values to `UserDefaults`.
    private func persistAll() {
        defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel)
        defaults.set(executionContext.rawString, forKey: Keys.execContext)

        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(maxTokens, forKey: Keys.maxTokens)
        defaults.set(contextLength, forKey: Keys.contextLength)
        defaults.set(topP, forKey: Keys.topP)
        defaults.set(frequencyPenalty, forKey: Keys.frequencyPenalty)
        defaults.set(presencePenalty, forKey: Keys.presencePenalty)
        defaults.set(repetitionPenalty, forKey: Keys.repetitionPenalty)
        defaults.set(systemPrompt, forKey: Keys.systemPrompt)

        defaults.set(lenientRetrievalMode, forKey: Keys.lenient)

        defaults.set(enableFirstFallback, forKey: Keys.enableFB1)
        defaults.set(enableSecondFallback, forKey: Keys.enableFB2)
        defaults.set(firstFallback.rawValue, forKey: Keys.firstFB)
        defaults.set(secondFallback.rawValue, forKey: Keys.secondFB)
        defaults.set(reviewerModeEnabled, forKey: Keys.reviewerModeEnabled)
        defaults.set(applePCCConsent.rawValue, forKey: Keys.applePCCConsent)
        defaults.set(hasUserPrimaryOverride, forKey: Keys.primaryModelUserOverride)
        defaults.set(developerRAGTuningEnabled, forKey: Keys.developerRAGTuning)

        // Embedding provider settings
        defaults.set(defaultEmbeddingProvider, forKey: Keys.defaultEmbeddingProvider)
        defaults.set(useHighAccuracyEmbeddings, forKey: Keys.useHighAccuracyEmbeddings)

        // Quality mode
        defaults.set(ragQualityMode.rawValue, forKey: Keys.ragQualityMode)
        defaults.set(reliabilityModeEnabled, forKey: Keys.reliabilityModeEnabled)

        // Advanced RAG Intelligence
        defaults.set(enableQueryRewriting, forKey: Keys.enableQueryRewriting)
        defaults.set(enableIterativeRetrieval, forKey: Keys.enableIterativeRetrieval)
        defaults.set(enableHyDE, forKey: Keys.enableHyDE)
        defaults.set(enableContextualCompression, forKey: Keys.enableContextualCompression)
        defaults.set(enableParentDocumentRetrieval, forKey: Keys.enableParentDocumentRetrieval)
        defaults.set(enableConversationMemory, forKey: Keys.enableConversationMemory)

        // Appearance
        defaults.set(appAccentColorHex, forKey: Keys.appAccentColorHex)
    }

    // MARK: - Side Effects (Debounced)

    /// Emits telemetry once a batch of setting changes has settled.
    private func applySettingsDebounced() {
        TelemetryCenter.emit(
            .system, title: "Settings changed",
            metadata: [
                "model": selectedModel.rawValue,
                "exec": executionContext.rawString,
                "fallbacks":
                    "\(enableFirstFallback ? "1" : "0")\(enableSecondFallback ? "+1" : "")",
            ]
        )

        // Apply model/fallback routing changes to the active RAG pipeline.
        // This keeps the UI picker in sync with the runtime service.
        // GUARD: Don't swap LLM services mid-query - can cause freezes or undefined behavior
        Task { @MainActor [weak ragService] in
            guard let ragService = ragService else { return }
            guard !ragService.isProcessing else {
                Log.debug("[SettingsStore] Skipping LLM rebuild - query in progress", category: .initialization)
                return
            }

            await ragService.rebuildLLMServicesFromSettings()
        }
    }
}

// MARK: - Consent Utilities

extension SettingsStore {
    func cloudConsent(for provider: CloudProvider) -> CloudConsentState {
        switch provider {
        case .applePCC:
            return applePCCConsent
        }
    }

    func setCloudConsent(
        _ state: CloudConsentState,
        for provider: CloudProvider,
        propagateToRAG: Bool = true
    ) {
        switch provider {
        case .applePCC:
            applePCCConsent = state
        }
        if propagateToRAG {
            ragService.setCloudConsentState(state, for: provider, propagateToSettings: false)
        }
    }
}

// MARK: - Platform Normalisation

private extension SettingsStore { 
    /// Ensures persisted selections remain valid for the running platform.
    func sanitizeModelSelectionForPlatform() { 
        let primaryOptions = primaryModelOptions
        let fallbackUniverse = fallbackBaseOptions

        if primaryOptions.isEmpty {
            setSelectedModelProgrammatically(fallbackUniverse.first ?? .onDeviceAnalysis)
        } else if !isPrimarySelectionAvailable(selectedModel) {
            if let firstValid = primaryOptions.first(where: { isPrimarySelectionAvailable($0) }) {
                setSelectedModelProgrammatically(firstValid)
            } else {
                setSelectedModelProgrammatically(fallbackUniverse.first ?? .onDeviceAnalysis)
            }
        } else if !hasUserPrimaryOverride,
                  selectedModel != .appleIntelligence,
                  isPrimarySelectionAvailable(.appleIntelligence)
        {
            setSelectedModelProgrammatically(.appleIntelligence)
        }

        let firstCandidates = fallbackUniverse.filter { $0 != selectedModel }
        if firstCandidates.isEmpty {
            firstFallback = selectedModel
            enableFirstFallback = false
        } else if !firstCandidates.contains(firstFallback) {
            firstFallback = firstCandidates.first!
        }

        let secondCandidates = fallbackUniverse.filter { $0 != selectedModel && $0 != firstFallback }
        if secondCandidates.isEmpty {
            secondFallback = firstFallback
            enableSecondFallback = false
        } else if !secondCandidates.contains(secondFallback) {
            secondFallback = secondCandidates.first!
        }
    }
}

// MARK: - Model Clarity Properties

extension SettingsStore {
    /// Human-readable description of why this model is active
    var modelSelectionReason: String {
        if hasUserPrimaryOverride {
            return "Selected by you"
        }

        switch selectedModel {
        case .appleIntelligence:
            return "Auto-selected (best available for this device)"
        case .onDeviceAnalysis:
            return "Fallback (always available)"
        }
    }

    /// Description of where inference will run
    var executionPathDescription: String {
        switch selectedModel {
        case .appleIntelligence:
            switch executionContext {
            case .automatic:
                return "Reliability-first auto routing (prefers PCC for library queries; falls back on-device)"
            case .onDeviceOnly:
                return "On-device only (may fail for complex queries)"
            case .preferCloud:
                return "Prefer Private Cloud Compute (higher quality)"
            case .cloudOnly:
                return "Private Cloud Compute only (requires network)"
            }

        case .onDeviceAnalysis:
            return "Fully on-device (never leaves your device)"
        }
    }

    /// Privacy badge for the current configuration
    var privacyBadge: (emoji: String, text: String) {
        switch selectedModel {
        case .onDeviceAnalysis:
            return ("🔒", "Data stays on device")

        case .appleIntelligence:
            if executionContext == .onDeviceOnly {
                return ("🔒", "Data stays on device")
            }
            return ("🔐", "E2E encrypted, zero retention")
        }
    }

    /// Whether the current config may send data off-device
    var mayTransmitData: Bool {
        switch selectedModel {
        case .onDeviceAnalysis:
            return false
        case .appleIntelligence:
            return executionContext != .onDeviceOnly
        }
    }
}

// MARK: - ExecutionContext Raw Mapping

private extension ExecutionContext {
    /// Persists the enum as a raw string for `UserDefaults`.
    var rawString: String {
        switch self {
        case .automatic: return "automatic"
        case .onDeviceOnly: return "onDeviceOnly"
        case .preferCloud: return "preferCloud"
        case .cloudOnly: return "cloudOnly"
        }
    }

    /// Restores an `ExecutionContext` instance from a stored raw value.
    static func from(raw: String) -> ExecutionContext {
        switch raw {
        case "onDeviceOnly": return .onDeviceOnly
        case "preferCloud": return .preferCloud
        case "cloudOnly": return .cloudOnly
        default: return .automatic
        }
    }
}

//
//  SettingsStore.swift
//  OpenIntelligence
//
//  Centralized settings state and persistence.
//  Bridges SwiftUI bindings to UserDefaults-backed storage keys used across the app.
//  Debounces change notifications for downstream application (e.g., model switching).
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
        static let selectedModel = "selectedLLMModel"  // LLMModelType.rawValue
        static let openaiAPIKey = "openaiAPIKey"
        static let openaiModel = "openaiModel"
        static let preferPCC = "preferPrivateCloudCompute"
        static let allowPCC = "allowPrivateCloudCompute"
        static let execContext = "executionContext"  // "automatic" | "onDeviceOnly" | "preferCloud" | "cloudOnly"
        static let temperature = "llmTemperature"  // Double
        static let maxTokens = "llmMaxTokens"  // Int
        static let topK = "retrievalTopK"  // Int
        static let lenient = "lenientRetrievalMode"  // Bool
        static let enableFB1 = "enableFirstFallback"  // Bool
        static let enableFB2 = "enableSecondFallback"  // Bool
        static let firstFB = "firstFallbackModel"  // LLMModelType.rawValue
        static let secondFB = "secondFallbackModel"  // LLMModelType.rawValue
        static let primaryModelUserOverride = "primaryModelUserOverride"
        static let localComputePreference = "ggufLocalComputePreference"

        // Responses API options
        static let responsesIncludeReasoning = "responsesIncludeReasoning"
        static let responsesIncludeVerbosity = "responsesIncludeVerbosity"
        static let responsesIncludeCoT = "responsesIncludeCoT"
        static let responsesIncludeMaxTokens = "responsesIncludeMaxTokens"

        // Reviewer & consent
        static let reviewerModeEnabled = "reviewerModeEnabled"
        static let applePCCConsent = "cloudConsent.applePCC"
        static let openAIConsent = "cloudConsent.openAI"
    }

    // MARK: - Published Settings (bind from UI)
    /// Primary inference pathway the user selected.
    @Published var selectedModel: LLMModelType
    /// Stored OpenAI API key (macOS only in the current build).
    @Published var openaiAPIKey: String
    /// Selected OpenAI model identifier.
    @Published var openaiModel: String
    /// Normalised API key value used for availability checks.
    private var trimmedAPIKey: String {
        openaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether Private Cloud Compute should be preferred when available.
    @Published var preferPrivateCloudCompute: Bool
    /// Whether Private Cloud Compute requests are allowed at all.
    @Published var allowPrivateCloudCompute: Bool
    /// Active execution strategy describing how queries are routed.
    @Published var executionContext: ExecutionContext

    /// Temperature applied to generative models.
    @Published var temperature: Double
    /// Response length ceiling for the active model.
    @Published var maxTokens: Int
    /// Number of retrieved chunks per query.
    @Published var topK: Int

    /// Loosens similarity thresholds during retrieval when enabled.
    @Published var lenientRetrievalMode: Bool

    /// Preferred compute units for local inference backends (GGUF/Core ML).
    @Published var localComputePreference: LocalComputePreference

    /// Controls whether the first fallback model participates in routing.
    @Published var enableFirstFallback: Bool
    /// Controls whether the second fallback model participates in routing.
    @Published var enableSecondFallback: Bool
    /// Model used when the primary pathway fails.
    @Published var firstFallback: LLMModelType
    /// Secondary fallback when both primary and first fallback are unavailable.
    @Published var secondFallback: LLMModelType

    // Responses API (OpenAI) options
    /// Whether to send the ``reasoning`` flag to OpenAI Responses API.
    @Published var responsesIncludeReasoning: Bool
    /// Whether to request verbose traces from OpenAI Responses API.
    @Published var responsesIncludeVerbosity: Bool
    /// Whether to connect prior chain-of-thought traces when enabled upstream.
    @Published var responsesIncludeCoT: Bool
    /// Whether to explicitly enforce max token counts with the Responses API.
    @Published var responsesIncludeMaxTokens: Bool

    /// Reviewer utilities toggle (exposes advanced controls in Settings).
    @Published var reviewerModeEnabled: Bool
    /// Saved consent preference for Apple PCC transmissions.
    @Published var applePCCConsent: CloudConsentState
    /// Saved consent preference for OpenAI Direct transmissions.
    @Published var openAIConsent: CloudConsentState


    // MARK: - Infra
    private let defaults: UserDefaults
    private let ragService: RAGService
    private let deviceCapabilities: DeviceCapabilities
    private var cancellables = Set<AnyCancellable>()
    private let applySubject = PassthroughSubject<Void, Never>()
    /// Tracks whether the user manually picked a primary model (vs. auto-selection).
    private var hasUserPrimaryOverride: Bool
    private var isApplyingProgrammaticSelection = false

    // MARK: - Model Availability
    /// Models that can be shown in the primary picker given current hardware and installs.
    var primaryModelOptions: [LLMModelType] {
        var options: [LLMModelType] = []

        if deviceCapabilities.supportsAppleIntelligence
            || deviceCapabilities.supportsFoundationModels
        {
            options.append(.appleIntelligence)
        }


        #if os(iOS)
            // Include GGUF Local if runtime is available OR if a GGUF model is installed
            // This prevents the Picker from going blank when a model is activated
            if LlamaCPPiOSLLMService.runtimeAvailable
                || !ModelRegistry.shared.installed.filter({ $0.backend == .gguf }).isEmpty
            {
                options.append(.ggufLocal)
            }
            if reviewerModeEnabled {
                options.append(.openAIDirect)
            }
        #endif

        if deviceCapabilities.supportsCoreML {
            #if os(iOS)
                let hasCoreMLCartridge = ModelRegistry.shared.installed.contains {
                    $0.backend == .coreML
                }
                if hasCoreMLCartridge || CoreMLLLMService.selectionIsReady() {
                    options.append(.coreMLLocal)
                }
            #else
                options.append(.coreMLLocal)
            #endif
        }

        if !options.contains(selectedModel) {
            options.append(selectedModel)
        }

        return options
    }

    /// Canonical fallback order before user-specific exclusions are applied.
    private var fallbackBaseOptions: [LLMModelType] {
        var ordered: [LLMModelType] = []
        var seen = Set<LLMModelType>()

        func append(_ type: LLMModelType) {
            guard !seen.contains(type) else { return }
            seen.insert(type)
            ordered.append(type)
        }

        primaryModelOptions.forEach { append($0) }
        append(.onDeviceAnalysis)

        #if os(iOS)
            if deviceCapabilities.supportsAppleIntelligence {
                append(.chatGPTExtension)
            }
        #else
            if deviceCapabilities.supportsAppleIntelligence {
                append(.chatGPTExtension)
            }
        #endif

        #if os(macOS)
            append(.openAIDirect)
        #elseif os(iOS)
            if reviewerModeEnabled {
                append(.openAIDirect)
            }
        #endif

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
        case .ggufLocal:
            #if os(iOS)
                let hasInstalledGGUF = ModelRegistry.shared.installed.contains { $0.backend == .gguf }
                return LlamaCPPiOSLLMService.runtimeAvailable && hasInstalledGGUF
            #else
                return false
            #endif
        case .coreMLLocal:
            guard deviceCapabilities.supportsCoreML else { return false }
            #if os(iOS)
                let hasCoreMLCartridge = ModelRegistry.shared.installed.contains { $0.backend == .coreML }
                return hasCoreMLCartridge || CoreMLLLMService.selectionIsReady()
            #else
                return true
            #endif
        case .chatGPTExtension:
            #if os(iOS)
                return deviceCapabilities.supportsAppleIntelligence
            #else
                return false
            #endif
        case .openAIDirect:
            #if os(macOS)
                return !trimmedAPIKey.isEmpty
            #elseif os(iOS)
                return reviewerModeEnabled && !trimmedAPIKey.isEmpty
            #else
                return false
            #endif
        case .onDeviceAnalysis:
            return true
        @unknown default:
            return true
        }
    }

    // MARK: - Init
    init(defaults: UserDefaults = .standard, ragService: RAGService) {
        self.defaults = defaults
        self.ragService = ragService
        self.deviceCapabilities = RAGService.checkDeviceCapabilities()

        // Load persisted values with sensible defaults
        if let raw = defaults.string(forKey: Keys.selectedModel),
            let t = LLMModelType(rawValue: raw)
        {
            self.selectedModel = t
        } else {
            self.selectedModel = .appleIntelligence
        }

        if let stored = KeychainStorage.string(forKey: Keys.openaiAPIKey), !stored.isEmpty {
            self.openaiAPIKey = stored
        } else {
            let legacy = defaults.string(forKey: Keys.openaiAPIKey) ?? ""
            self.openaiAPIKey = legacy
            if !legacy.isEmpty {
                KeychainStorage.setString(legacy, forKey: Keys.openaiAPIKey)
                defaults.removeObject(forKey: Keys.openaiAPIKey)
            }
        }
        self.openaiModel = defaults.string(forKey: Keys.openaiModel) ?? "gpt-4o-mini"

        self.preferPrivateCloudCompute = defaults.bool(forKey: Keys.preferPCC)
        self.allowPrivateCloudCompute = defaults.object(forKey: Keys.allowPCC) as? Bool ?? true

        let execRaw = defaults.string(forKey: Keys.execContext) ?? "automatic"
        self.executionContext = ExecutionContext.from(raw: execRaw)

        self.temperature = (defaults.object(forKey: Keys.temperature) as? Double) ?? 0.7
        self.maxTokens = (defaults.object(forKey: Keys.maxTokens) as? Int) ?? 500
        self.topK = (defaults.object(forKey: Keys.topK) as? Int) ?? 3

        self.lenientRetrievalMode = defaults.object(forKey: Keys.lenient) as? Bool ?? false
        self.localComputePreference = LocalComputePreference.load(
            from: defaults, key: Keys.localComputePreference, fallback: .automatic)

        self.enableFirstFallback = defaults.object(forKey: Keys.enableFB1) as? Bool ?? true
        self.enableSecondFallback = defaults.object(forKey: Keys.enableFB2) as? Bool ?? true

        if let raw1 = defaults.string(forKey: Keys.firstFB),
            let t1 = LLMModelType(rawValue: raw1)
        {
            self.firstFallback = t1
        } else {
            self.firstFallback = .onDeviceAnalysis
        }

        if let raw2 = defaults.string(forKey: Keys.secondFB),
            let t2 = LLMModelType(rawValue: raw2)
        {
            self.secondFallback = t2
        } else {
            #if os(iOS)
                self.secondFallback = .chatGPTExtension
            #else
                self.secondFallback = .onDeviceAnalysis
            #endif
        }

        self.responsesIncludeReasoning =
            defaults.object(forKey: Keys.responsesIncludeReasoning) as? Bool ?? true
        self.responsesIncludeVerbosity =
            defaults.object(forKey: Keys.responsesIncludeVerbosity) as? Bool ?? true
        self.responsesIncludeCoT =
            defaults.object(forKey: Keys.responsesIncludeCoT) as? Bool ?? true
        self.responsesIncludeMaxTokens =
            defaults.object(forKey: Keys.responsesIncludeMaxTokens) as? Bool ?? true

        self.reviewerModeEnabled =
            defaults.object(forKey: Keys.reviewerModeEnabled) as? Bool ?? false
        let appleConsentRaw = defaults.string(forKey: Keys.applePCCConsent)
        self.applePCCConsent =
            CloudConsentState(rawValue: appleConsentRaw ?? "") ?? .notDetermined
        let openAIConsentRaw = defaults.string(forKey: Keys.openAIConsent)
        self.openAIConsent =
            CloudConsentState(rawValue: openAIConsentRaw ?? "") ?? .notDetermined
        self.hasUserPrimaryOverride =
            defaults.object(forKey: Keys.primaryModelUserOverride) as? Bool ?? false

        if selectedModel == .ggufLocal,
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
            $openaiAPIKey.map { _ in () }.eraseToAnyPublisher(),
            $openaiModel.map { _ in () }.eraseToAnyPublisher(),
            $preferPrivateCloudCompute.map { _ in () }.eraseToAnyPublisher(),
            $allowPrivateCloudCompute.map { _ in () }.eraseToAnyPublisher(),
            $executionContext.map { _ in () }.eraseToAnyPublisher(),
            $temperature.map { _ in () }.eraseToAnyPublisher(),
            $maxTokens.map { _ in () }.eraseToAnyPublisher(),
            $topK.map { _ in () }.eraseToAnyPublisher(),
            $lenientRetrievalMode.map { _ in () }.eraseToAnyPublisher(),
            $enableFirstFallback.map { _ in () }.eraseToAnyPublisher(),
            $enableSecondFallback.map { _ in () }.eraseToAnyPublisher(),
            $firstFallback.map { _ in () }.eraseToAnyPublisher(),
            $secondFallback.map { _ in () }.eraseToAnyPublisher(),
            $localComputePreference.map { _ in () }.eraseToAnyPublisher(),
            $responsesIncludeReasoning.map { _ in () }.eraseToAnyPublisher(),
            $responsesIncludeVerbosity.map { _ in () }.eraseToAnyPublisher(),
            $responsesIncludeCoT.map { _ in () }.eraseToAnyPublisher(),
            $responsesIncludeMaxTokens.map { _ in () }.eraseToAnyPublisher(),
            $reviewerModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            $applePCCConsent.map { _ in () }.eraseToAnyPublisher(),
            $openAIConsent.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(publishers)
            .sink { [weak self] in
                guard let self else { return }
                self.persistAll()
                self.applySubject.send()
            }
            .store(in: &cancellables)

        // Observe ModelRegistry changes to refresh available model options
        ModelRegistry.shared.$installed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Normalise selections before invalidating views so Pickers never render stale tags.
                self.sanitizeModelSelectionForPlatform()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .installedModelAutoSelected)
            .compactMap { notification -> ModelBackend? in
                guard
                    let raw = notification.userInfo?[ModelAutoSelectionPayload.backend] as? String,
                    let backend = ModelBackend(rawValue: raw)
                else { return nil }
                return backend
            }
            .sink { [weak self] backend in
                guard let self else { return }
                self.applyAutoSelectionIfEligible(for: backend)
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
        if openaiAPIKey.isEmpty {
            KeychainStorage.removeValue(forKey: Keys.openaiAPIKey)
        } else {
            _ = KeychainStorage.setString(openaiAPIKey, forKey: Keys.openaiAPIKey)
        }
        defaults.set(openaiModel, forKey: Keys.openaiModel)

        defaults.set(preferPrivateCloudCompute, forKey: Keys.preferPCC)
        defaults.set(allowPrivateCloudCompute, forKey: Keys.allowPCC)
        defaults.set(executionContext.rawString, forKey: Keys.execContext)

        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(maxTokens, forKey: Keys.maxTokens)
        defaults.set(topK, forKey: Keys.topK)

        defaults.set(lenientRetrievalMode, forKey: Keys.lenient)

        defaults.set(enableFirstFallback, forKey: Keys.enableFB1)
        defaults.set(enableSecondFallback, forKey: Keys.enableFB2)
        defaults.set(firstFallback.rawValue, forKey: Keys.firstFB)
        defaults.set(secondFallback.rawValue, forKey: Keys.secondFB)
        localComputePreference.persist(in: defaults, key: Keys.localComputePreference)

        defaults.set(responsesIncludeReasoning, forKey: Keys.responsesIncludeReasoning)
        defaults.set(responsesIncludeVerbosity, forKey: Keys.responsesIncludeVerbosity)
        defaults.set(responsesIncludeCoT, forKey: Keys.responsesIncludeCoT)
        defaults.set(responsesIncludeMaxTokens, forKey: Keys.responsesIncludeMaxTokens)
        defaults.set(reviewerModeEnabled, forKey: Keys.reviewerModeEnabled)
        defaults.set(applePCCConsent.rawValue, forKey: Keys.applePCCConsent)
        defaults.set(openAIConsent.rawValue, forKey: Keys.openAIConsent)
        defaults.set(hasUserPrimaryOverride, forKey: Keys.primaryModelUserOverride)
    }

    // MARK: - Side Effects (Debounced)
    /// Emits telemetry once a batch of setting changes has settled.
    private func applySettingsDebounced() {
        // Phase 1: Emit lightweight telemetry and return
        // Phase 2: Wire model switching here (extract shared logic from SettingsRootView)
        TelemetryCenter.emit(
            .system, title: "Settings changed",
            metadata: [
                "model": selectedModel.rawValue,
                "exec": executionContext.rawString,
                "localCompute": localComputePreference.rawValue,
                "openaiModel": openaiModel,
                "fallbacks":
                    "\(enableFirstFallback ? "1" : "0")\(enableSecondFallback ? "+1" : "")",
            ])
    }
}

// MARK: - Consent Utilities

extension SettingsStore {
    func cloudConsent(for provider: CloudProvider) -> CloudConsentState {
        switch provider {
        case .applePCC:
            return applePCCConsent
        case .openAI:
            return openAIConsent
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
        case .openAI:
            openAIConsent = state
        }
        if propagateToRAG {
            ragService.setCloudConsentState(state, for: provider, propagateToSettings: false)
        }
    }
}

// MARK: - Platform Normalisation

extension SettingsStore {
    /// Ensures persisted selections remain valid for the running platform.
    /// Ensures persisted selections remain valid for the running platform.
    fileprivate func sanitizeModelSelectionForPlatform() {
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

    /// Aligns UI selection with auto-selected cartridges when the user has not made an explicit override.
    /// Aligns UI selection with auto-selected cartridges when the user has not made an explicit override.
    private func applyAutoSelectionIfEligible(for backend: ModelBackend) {
        if isPrimarySelectionAvailable(selectedModel) {
            return
        }
        if hasUserPrimaryOverride {
            return
        }
        switch backend {
        case .gguf:
            guard selectedModel != .ggufLocal else { return }
            guard primaryModelOptions.contains(.ggufLocal) else { return }
            let autoEligible: Set<LLMModelType> = [.appleIntelligence, .onDeviceAnalysis]
            guard autoEligible.contains(selectedModel) else { return }
            setSelectedModelProgrammatically(.ggufLocal)
            AutoTuneService.tuneForSelection(selectedModel: .ggufLocal)
        case .coreML:
            guard selectedModel != .coreMLLocal else { return }
            guard primaryModelOptions.contains(.coreMLLocal) else { return }
            let autoEligible: Set<LLMModelType> = [.appleIntelligence, .onDeviceAnalysis]
            guard autoEligible.contains(selectedModel) else { return }
            setSelectedModelProgrammatically(.coreMLLocal)
            AutoTuneService.tuneForSelection(selectedModel: .coreMLLocal)
        case .mlxServer:
            Log.info("Ignoring auto-selection for legacy MLX server", category: .llm)
        }
    }
}

// MARK: - ExecutionContext Raw Mapping

extension ExecutionContext {
    /// Persists the enum as a raw string for `UserDefaults`.
    fileprivate var rawString: String {
        switch self {
        case .automatic: return "automatic"
        case .onDeviceOnly: return "onDeviceOnly"
        case .preferCloud: return "preferCloud"
        case .cloudOnly: return "cloudOnly"
        }
    }

    /// Restores an `ExecutionContext` instance from a stored raw value.
    fileprivate static func from(raw: String) -> ExecutionContext {
        switch raw {
        case "onDeviceOnly": return .onDeviceOnly
        case "preferCloud": return .preferCloud
        case "cloudOnly": return .cloudOnly
        default: return .automatic
        }
    }
}

//
//  ModelResolutionService.swift
//  OpenIntelligence
//
//  Centralizes model resolution logic to provide transparency about:
//  - What model the user selected
//  - What model is actually running
//  - Why (auto-selection, fallback, etc.)
//
//  This eliminates the confusion around which model is active.
//

import Combine
import Foundation
import SwiftUI

// NOTE: This file is not currently included in the Xcode project (pbxproj), so SourceKit
// doesn't have module context for types like `LLMModelType`/`ModelResolutionState`.
// Keep the implementation here for future wiring, but don't typecheck it for now.
#if false

    /// Observable service that tracks the resolved model state.
    /// Use this as the single source of truth for model status UI.
    @MainActor
    final class ModelResolutionService: ObservableObject {
        // MARK: - Published State

        /// The current resolved model state - use this for UI
        @Published private(set) var currentState: ModelResolutionState

        /// History of resolution changes for debugging/transparency
        @Published private(set) var resolutionHistory: [ResolutionEvent] = []

        // MARK: - Dependencies

        private weak var ragService: RAGService?
        private weak var settingsStore: SettingsStore?
        private var cancellables = Set<AnyCancellable>()

        // MARK: - Resolution Event

        struct ResolutionEvent: Identifiable {
            let id = UUID()
            let timestamp: Date
            let from: LLMModelType?
            let to: LLMModelType
            let reason: ModelResolutionState.ResolutionReason
            let activeModelName: String
        }

        // MARK: - Init

        init(ragService: RAGService? = nil, settingsStore: SettingsStore? = nil) {
            self.ragService = ragService
            self.settingsStore = settingsStore

            // Initialize with default state
            currentState = ModelResolutionState(
                selectedType: settingsStore?.selectedModel ?? .appleIntelligence,
                activeModelName: ragService?.activeModelName ?? "Loading...",
                resolutionReason: .systemDefault,
                executionPath: .hybridAutomatic,
                status: .loading(progress: nil),
                localModelInfo: nil,
                activeParameters: Self.extractParameters(from: settingsStore)
            )

            setupObservers()
        }

        // MARK: - Setup

        private func setupObservers() {
            // Observe settings changes (primary driver of model resolution)
            if let settingsStore {
                settingsStore.$selectedModel
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in
                        self?.resolveCurrentModel()
                    }
                    .store(in: &cancellables)

                // Also observe execution context changes
                settingsStore.$executionContext
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in
                        self?.resolveCurrentModel()
                    }
                    .store(in: &cancellables)

                // Observe parameter changes
                Publishers.CombineLatest4(
                    settingsStore.$temperature,
                    settingsStore.$maxTokens,
                    settingsStore.$topP,
                    settingsStore.$contextLength
                )
                .receive(on: RunLoop.main)
                .sink { [weak self] _, _, _, _ in
                    self?.updateParameters()
                }
                .store(in: &cancellables)
            }

            // Listen for auto-selection notifications
            NotificationCenter.default.publisher(for: .installedModelAutoSelected)
                .receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    self?.handleAutoSelection(notification)
                }
                .store(in: &cancellables)
        }

        // MARK: - Resolution Logic

        /// Resolves the current model and updates state
        func resolveCurrentModel() {
            guard let settingsStore, let ragService else {
                Log.warning("ModelResolutionService: Missing dependencies", category: .initialization)
                return
            }

            let selectedType = settingsStore.selectedModel
            let actualModelName = ragService.activeModelName

            // Determine resolution reason
            let reason = determineResolutionReason(
                selected: selectedType,
                actual: actualModelName,
                hasUserOverride: settingsStore.hasUserPrimaryOverride
            )

            // Determine execution path
            let executionPath = determineExecutionPath(for: selectedType, settings: settingsStore)

            // Get local model info if applicable
            let localInfo = extractLocalModelInfo(for: selectedType)

            // Determine status
            let status = determineModelStatus(for: selectedType, ragService: ragService)

            let newState = ModelResolutionState(
                selectedType: selectedType,
                activeModelName: actualModelName,
                resolutionReason: reason,
                executionPath: executionPath,
                status: status,
                localModelInfo: localInfo,
                activeParameters: Self.extractParameters(from: settingsStore)
            )

            // Only update if changed
            if newState != currentState {
                let previousType = currentState.selectedType
                currentState = newState

                // Record history
                resolutionHistory.append(ResolutionEvent(
                    timestamp: Date(),
                    from: previousType,
                    to: selectedType,
                    reason: reason,
                    activeModelName: actualModelName
                ))

                // Keep history bounded
                if resolutionHistory.count > 50 {
                    resolutionHistory.removeFirst(resolutionHistory.count - 50)
                }

                Log.info(
                    "Model resolved: \(actualModelName) (\(reason.displayText))",
                    category: .initialization
                )
            }
        }

        /// Force refresh the resolution state
        func refresh() {
            resolveCurrentModel()
        }

        // MARK: - Resolution Helpers

        private func determineResolutionReason(
            selected: LLMModelType,
            actual: String,
            hasUserOverride: Bool
        ) -> ModelResolutionState.ResolutionReason {
            // Check if we're using a fallback
            if isFallbackActive(selected: selected, actualName: actual) {
                return .fallback(from: selected, reason: "Primary model unavailable")
            }

            // Check if auto-selected
            if !hasUserOverride {
                switch selected {
                case .appleIntelligence:
                    return .autoSelected(reason: "Best available on this device")
                case .ggufLocal, .coreMLLocal:
                    return .autoSelected(reason: "First installed local model")
                default:
                    return .systemDefault
                }
            }

            return .userSelected
        }

        private func isFallbackActive(selected: LLMModelType, actualName: String) -> Bool {
            // If the actual model name doesn't match what we expect for the selected type
            switch selected {
            case .appleIntelligence:
                return !actualName.contains("Apple") && !actualName.contains("Foundation")
            case .ggufLocal:
                return !actualName.contains("GGUF") && !actualName.contains(".gguf")
            case .coreMLLocal:
                return !actualName.contains("Core ML") && !actualName.contains("CoreML")
            case .openAIDirect:
                return !actualName.contains("GPT") && !actualName.contains("OpenAI")
            case .chatGPTExtension:
                // Apple Intelligence's ChatGPT integration isn't available as a public in-app API.
                // If this legacy selection appears (e.g. from older persisted settings), always treat
                // it as falling back to whatever model actually ran.
                return true
            case .mlxLocal:
                return !actualName.contains("MLX")
            case .onDeviceAnalysis:
                return !actualName.contains("On-Device") && !actualName.contains("Extractive")
            }
        }

        private func determineExecutionPath(
            for type: LLMModelType,
            settings: SettingsStore
        ) -> ModelResolutionState.ExecutionPath {
            switch type {
            case .appleIntelligence:
                // Apple Intelligence uses hybrid by default
                switch settings.executionContext {
                case .onDeviceOnly:
                    return .onDevice
                case .cloudOnly, .preferCloud:
                    return .privateCloudCompute
                case .automatic:
                    return .hybridAutomatic
                }

            case .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
                return .onDevice

            case .mlxLocal:
                return .localServer(endpoint: "localhost:8080")

            case .openAIDirect:
                return .cloudAPI(provider: "OpenAI")

            case .chatGPTExtension:
                return .privateCloudCompute
            }
        }

        private func extractLocalModelInfo(for type: LLMModelType) -> ModelResolutionState.LocalModelInfo? {
            switch type {
            case .ggufLocal:
                // Get selected GGUF model info
                guard let idString = UserDefaults.standard.string(
                    forKey: LlamaCPPiOSLLMService.selectedModelIdKey
                ),
                    let uuid = UUID(uuidString: idString),
                    let model = ModelRegistry.shared.model(id: uuid)
                else {
                    return nil
                }
                return ModelResolutionState.LocalModelInfo(
                    fileName: model.name,
                    fileSize: model.sizeBytes,
                    quantization: model.quantization,
                    backend: .gguf
                )

            case .coreMLLocal:
                guard let idString = UserDefaults.standard.string(
                    forKey: CoreMLLLMService.selectedModelIdKey
                ),
                    let uuid = UUID(uuidString: idString),
                    let model = ModelRegistry.shared.model(id: uuid)
                else {
                    return nil
                }
                return ModelResolutionState.LocalModelInfo(
                    fileName: model.name,
                    fileSize: model.sizeBytes,
                    quantization: nil,
                    backend: .coreML
                )

            default:
                return nil
            }
        }

        private func determineModelStatus(
            for type: LLMModelType,
            ragService: RAGService
        ) -> ModelResolutionState.ModelStatus {
            // Check if model is available
            guard ragService.isLLMAvailable else {
                return .unavailable(reason: "Model not available")
            }

            // Check specific conditions
            switch type {
            case .ggufLocal:
                #if os(iOS)
                    if !LlamaCPPiOSLLMService.runtimeAvailable {
                        return .unavailable(reason: "GGUF runtime not available")
                    }
                    if UserDefaults.standard.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey) == nil {
                        return .unavailable(reason: "No GGUF model selected")
                    }
                #endif

            case .coreMLLocal:
                if !CoreMLLLMService.selectionIsReady() {
                    return .unavailable(reason: "No Core ML model loaded")
                }

            case .appleIntelligence:
                // Check if Foundation Models available
                let capabilities = RAGService.checkDeviceCapabilities()
                if !capabilities.supportsFoundationModels {
                    return .unavailable(reason: "Requires iOS 26+ with Apple Silicon")
                }

            default:
                break
            }

            return .ready
        }

        private static func extractParameters(from settings: SettingsStore?) -> ModelResolutionState.ActiveParameters {
            guard let settings else {
                return ModelResolutionState.ActiveParameters(
                    temperature: 0.7,
                    maxTokens: 512,
                    topP: 0.9,
                    contextLength: 2048
                )
            }
            return ModelResolutionState.ActiveParameters(
                temperature: settings.temperature,
                maxTokens: settings.maxTokens,
                topP: settings.topP,
                contextLength: settings.contextLength
            )
        }

        private func updateParameters() {
            guard let settingsStore else { return }
            let newParams = Self.extractParameters(from: settingsStore)

            if currentState.activeParameters != newParams {
                currentState = ModelResolutionState(
                    selectedType: currentState.selectedType,
                    activeModelName: currentState.activeModelName,
                    resolutionReason: currentState.resolutionReason,
                    executionPath: currentState.executionPath,
                    status: currentState.status,
                    localModelInfo: currentState.localModelInfo,
                    activeParameters: newParams
                )
            }
        }

        private func handleAutoSelection(_ notification: Notification) {
            guard let backendRaw = notification.userInfo?[ModelAutoSelectionPayload.backend] as? String,
                  let _ = ModelBackend(rawValue: backendRaw)
            else {
                return
            }

            // Refresh resolution after auto-selection
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay for state to settle
                resolveCurrentModel()
            }
        }
    }

    // MARK: - Environment Key

    private struct ModelResolutionServiceKey: EnvironmentKey {
        static let defaultValue: ModelResolutionService? = nil
    }

    extension EnvironmentValues {
        var modelResolution: ModelResolutionService? {
            get { self[ModelResolutionServiceKey.self] }
            set { self[ModelResolutionServiceKey.self] = newValue }
        }
    }

    // MARK: - Convenience Accessors

    extension ModelResolutionService {
        /// Quick check if using a local model
        var isUsingLocalModel: Bool {
            currentState.executionPath == .onDevice
        }

        /// Quick check if data may leave device
        var mayUseCloud: Bool {
            switch currentState.executionPath {
            case .onDevice, .localServer:
                return false
            default:
                return true
            }
        }

        /// Display-ready model name
        var displayModelName: String {
            currentState.activeModelName
        }

        /// Display-ready execution badge
        var executionBadge: String {
            "\(currentState.executionPath.emoji) \(currentState.executionPath.displayName)"
        }
    }

#endif

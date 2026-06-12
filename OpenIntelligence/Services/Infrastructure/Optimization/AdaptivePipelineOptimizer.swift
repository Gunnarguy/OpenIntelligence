//
//  AdaptivePipelineOptimizer.swift
//  OpenIntelligence
//
//  Runtime optimization of RAG pipeline based on device state:
//  - Thermal state (critical, serious, fair, nominal)
//  - Battery level and charging state
//  - Memory pressure
//  - Device capability tier
//
//  Automatically adjusts pipeline parameters to balance performance vs efficiency.
//

import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pipeline Optimization Level

/// Describes how aggressively to optimize the pipeline
enum PipelineOptimizationLevel: String, Sendable, CaseIterable {
    case full // All features enabled, max quality
    case balanced // Smart feature selection based on query
    case efficient // Reduced features for battery/thermal
    case minimal // Essential features only (emergency mode)

    var displayName: String {
        switch self {
        case .full: return "Full Quality"
        case .balanced: return "Balanced"
        case .efficient: return "Power Saver"
        case .minimal: return "Emergency"
        }
    }
}

// MARK: - Device Runtime State

/// Current runtime state of the device
struct DeviceRuntimeState: Sendable {
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float // 0.0 - 1.0
    let isCharging: Bool
    let memoryPressure: MemoryPressure
    let timestamp: Date

    enum MemoryPressure: String, Sendable {
        case nominal
        case warning
        case critical
    }

    /// Computed optimization level based on current state
    var recommendedOptimizationLevel: PipelineOptimizationLevel {
        // Critical thermal = minimal mode (device protection)
        if thermalState == .critical {
            return .minimal
        }

        // Serious thermal = no longer throttles (keeps full performance unless critical)
        // Memory pressure = reduce features to prevent OOM
        if memoryPressure == .critical {
            return .efficient
        }

        // Full blast for everything else - user preference
        // Battery level no longer triggers degradation
        return .full
    }

    /// Whether this is a "constrained" state requiring caution
    var isConstrained: Bool {
        // On Mac, only thermal and memory matter (battery API is unreliable)
        let isMac = DeviceCapabilityService.shared.isMac || ProcessInfo.processInfo.isiOSAppOnMac

        if isMac {
            return thermalState != .nominal || memoryPressure != .nominal
        }

        // On real iOS devices, also consider battery
        return thermalState != .nominal ||
            memoryPressure != .nominal ||
            (batteryLevel < 0.20 && !isCharging)
    }
}

// MARK: - Pipeline Configuration

/// Configuration for a single RAG query, adjusted based on device state
struct AdaptivePipelineConfig: Sendable {
    // Feature toggles
    let enableHyDE: Bool
    let enableParentDocumentRetrieval: Bool
    let enableContextualCompression: Bool
    let enableIterativeRetrieval: Bool
    let enableQueryRewriting: Bool

    // Numeric limits
    let maxRetrievalCandidates: Int
    let maxContextTokens: Int
    let rerankBatchSize: Int
    let maxAgenticSteps: Int

    // Timing
    let stepCooldownMs: UInt64
    let maxQueryTimeoutSeconds: Double

    // Quality
    let minSimilarityThreshold: Float
    let mmrLambda: Float

    /// Base configuration for device tier (before runtime adjustments)
    static func base(for tier: DeviceCapabilityTier) -> AdaptivePipelineConfig {
        switch tier {
        case .unsupported:
            return AdaptivePipelineConfig(
                enableHyDE: false,
                enableParentDocumentRetrieval: false,
                enableContextualCompression: false,
                enableIterativeRetrieval: false,
                enableQueryRewriting: true,
                maxRetrievalCandidates: 40, // Minimum viable for large docs
                maxContextTokens: 2000,
                rerankBatchSize: 5,
                maxAgenticSteps: 0,
                stepCooldownMs: 0,
                maxQueryTimeoutSeconds: 15,
                minSimilarityThreshold: 0.35,
                mmrLambda: 0.7
            )

        case .baseline: // A17 Pro
            return AdaptivePipelineConfig(
                enableHyDE: true,
                enableParentDocumentRetrieval: true,
                enableContextualCompression: true,
                enableIterativeRetrieval: false, // Too expensive for baseline
                enableQueryRewriting: true,
                maxRetrievalCandidates: 75, // Increased from 20 for large doc support
                maxContextTokens: 3000,
                rerankBatchSize: 10,
                maxAgenticSteps: 4,
                stepCooldownMs: 200,
                maxQueryTimeoutSeconds: 30,
                minSimilarityThreshold: 0.32,
                mmrLambda: 0.75
            )

        case .enhanced: // A18
            return AdaptivePipelineConfig(
                enableHyDE: true,
                enableParentDocumentRetrieval: true,
                enableContextualCompression: true,
                enableIterativeRetrieval: true,
                enableQueryRewriting: true,
                maxRetrievalCandidates: 100, // Increased from 30 for large document support
                maxContextTokens: 3500,
                rerankBatchSize: 15,
                maxAgenticSteps: 6,
                stepCooldownMs: 100,
                maxQueryTimeoutSeconds: 45,
                minSimilarityThreshold: 0.30,
                mmrLambda: 0.75
            )

        case .advanced: // A19
            return AdaptivePipelineConfig(
                enableHyDE: true,
                enableParentDocumentRetrieval: true,
                enableContextualCompression: true,
                enableIterativeRetrieval: true,
                enableQueryRewriting: true,
                maxRetrievalCandidates: 150, // Increased from 40 for large document support
                maxContextTokens: 3800,
                rerankBatchSize: 20,
                maxAgenticSteps: 8,
                stepCooldownMs: 50,
                maxQueryTimeoutSeconds: 60,
                minSimilarityThreshold: 0.28,
                mmrLambda: 0.80
            )

        case .ultraAdvanced: // M-series
            return AdaptivePipelineConfig(
                enableHyDE: true,
                enableParentDocumentRetrieval: true,
                enableContextualCompression: true,
                enableIterativeRetrieval: true,
                enableQueryRewriting: true,
                maxRetrievalCandidates: 250, // Increased from 50 for large document support (10K+ chunks)
                maxContextTokens: 4000,
                rerankBatchSize: 25,
                maxAgenticSteps: 10,
                stepCooldownMs: 0,
                maxQueryTimeoutSeconds: 90,
                minSimilarityThreshold: 0.25,
                mmrLambda: 0.85
            )
        }
    }

    /// Adjust configuration based on optimization level
    func adjusted(for level: PipelineOptimizationLevel) -> AdaptivePipelineConfig {
        switch level {
        case .full:
            return self

        case .balanced:
            return AdaptivePipelineConfig(
                enableHyDE: enableHyDE,
                enableParentDocumentRetrieval: enableParentDocumentRetrieval,
                enableContextualCompression: enableContextualCompression,
                enableIterativeRetrieval: false, // Disable multi-pass
                enableQueryRewriting: enableQueryRewriting,
                maxRetrievalCandidates: Int(Double(maxRetrievalCandidates) * 0.8),
                maxContextTokens: Int(Double(maxContextTokens) * 0.9),
                rerankBatchSize: Int(Double(rerankBatchSize) * 0.8),
                maxAgenticSteps: max(3, maxAgenticSteps - 2),
                stepCooldownMs: stepCooldownMs + 50,
                maxQueryTimeoutSeconds: maxQueryTimeoutSeconds * 0.8,
                minSimilarityThreshold: minSimilarityThreshold + 0.02,
                mmrLambda: mmrLambda
            )

        case .efficient:
            return AdaptivePipelineConfig(
                enableHyDE: false, // Skip hypothetical doc generation
                enableParentDocumentRetrieval: enableParentDocumentRetrieval,
                enableContextualCompression: false, // Skip LLM-based compression
                enableIterativeRetrieval: false,
                enableQueryRewriting: true, // Keep lightweight rewriting
                maxRetrievalCandidates: Int(Double(maxRetrievalCandidates) * 0.5),
                maxContextTokens: Int(Double(maxContextTokens) * 0.7),
                rerankBatchSize: min(8, rerankBatchSize),
                maxAgenticSteps: min(2, maxAgenticSteps),
                stepCooldownMs: stepCooldownMs + 150,
                maxQueryTimeoutSeconds: maxQueryTimeoutSeconds * 0.5,
                minSimilarityThreshold: minSimilarityThreshold + 0.05,
                mmrLambda: 0.6 // Favor relevance over diversity
            )

        case .minimal:
            return AdaptivePipelineConfig(
                enableHyDE: false,
                enableParentDocumentRetrieval: false,
                enableContextualCompression: false,
                enableIterativeRetrieval: false,
                enableQueryRewriting: false, // Skip all preprocessing
                maxRetrievalCandidates: 10,
                maxContextTokens: Int(Double(maxContextTokens) * 0.5),
                rerankBatchSize: 5,
                maxAgenticSteps: 0, // No agentic mode
                stepCooldownMs: 300,
                maxQueryTimeoutSeconds: 15,
                minSimilarityThreshold: 0.40, // Higher threshold = fewer results
                mmrLambda: 0.5
            )
        }
    }
}

// MARK: - Adaptive Pipeline Optimizer

/// Main service for runtime pipeline optimization
@MainActor
final class AdaptivePipelineOptimizer: ObservableObject {
    // MARK: - Singleton

    static let shared = AdaptivePipelineOptimizer()

    // MARK: - Published State

    @Published private(set) var currentState: DeviceRuntimeState
    @Published private(set) var currentOptimizationLevel: PipelineOptimizationLevel
    @Published private(set) var currentConfig: AdaptivePipelineConfig

    /// Whether the user has manually overridden optimization level
    @Published var userOverrideLevel: PipelineOptimizationLevel?

    // MARK: - Private

    private let deviceTier: DeviceCapabilityTier
    private var thermalObserver: NSObjectProtocol?
    private var batteryObserver: NSObjectProtocol?
    private var memoryObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        deviceTier = DeviceCapabilityService.shared.tier

        // Initialize with current state
        let initialState = Self.captureCurrentState()
        currentState = initialState

        // Must initialize all stored properties before using self
        let level = initialState.recommendedOptimizationLevel
        currentOptimizationLevel = level
        currentConfig = AdaptivePipelineConfig.base(for: deviceTier)
            .adjusted(for: level)

        setupObservers()
        enableBatteryMonitoring()
    }

    deinit {
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = batteryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = memoryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// Get optimized configuration for current query
    func configForQuery(complexity: QueryComplexity = .standard) -> AdaptivePipelineConfig {
        let baseConfig: AdaptivePipelineConfig
        let level = userOverrideLevel ?? currentOptimizationLevel

        // Start with tier-appropriate base
        baseConfig = AdaptivePipelineConfig.base(for: deviceTier)

        // Adjust for runtime state
        var adjusted = baseConfig.adjusted(for: level)

        // Further adjust for query complexity
        switch complexity {
        case .trivial:
            // Simple queries don't need full pipeline
            adjusted = AdaptivePipelineConfig(
                enableHyDE: false,
                enableParentDocumentRetrieval: false,
                enableContextualCompression: false,
                enableIterativeRetrieval: false,
                enableQueryRewriting: false,
                maxRetrievalCandidates: min(10, adjusted.maxRetrievalCandidates),
                maxContextTokens: min(1500, adjusted.maxContextTokens),
                rerankBatchSize: min(5, adjusted.rerankBatchSize),
                maxAgenticSteps: 0,
                stepCooldownMs: adjusted.stepCooldownMs,
                maxQueryTimeoutSeconds: 10,
                minSimilarityThreshold: adjusted.minSimilarityThreshold,
                mmrLambda: adjusted.mmrLambda
            )

        case .standard:
            // Use adjusted config as-is
            break

        case .complex:
            // Complex queries get more resources if available
            if level == .full {
                adjusted = AdaptivePipelineConfig(
                    enableHyDE: true,
                    enableParentDocumentRetrieval: true,
                    enableContextualCompression: true,
                    enableIterativeRetrieval: deviceTier >= .enhanced,
                    enableQueryRewriting: true,
                    maxRetrievalCandidates: min(50, adjusted.maxRetrievalCandidates + 10),
                    maxContextTokens: adjusted.maxContextTokens,
                    rerankBatchSize: adjusted.rerankBatchSize,
                    maxAgenticSteps: adjusted.maxAgenticSteps,
                    stepCooldownMs: adjusted.stepCooldownMs,
                    maxQueryTimeoutSeconds: adjusted.maxQueryTimeoutSeconds * 1.5,
                    minSimilarityThreshold: max(0.25, adjusted.minSimilarityThreshold - 0.03),
                    mmrLambda: adjusted.mmrLambda
                )
            }

        case .agentic:
            // Agentic queries need full power
            if level != .minimal {
                adjusted = AdaptivePipelineConfig(
                    enableHyDE: level != .efficient,
                    enableParentDocumentRetrieval: true,
                    enableContextualCompression: level != .efficient,
                    enableIterativeRetrieval: level == .full && deviceTier >= .enhanced,
                    enableQueryRewriting: true,
                    maxRetrievalCandidates: adjusted.maxRetrievalCandidates,
                    maxContextTokens: adjusted.maxContextTokens,
                    rerankBatchSize: adjusted.rerankBatchSize,
                    maxAgenticSteps: adjusted.maxAgenticSteps,
                    stepCooldownMs: adjusted.stepCooldownMs,
                    maxQueryTimeoutSeconds: adjusted.maxQueryTimeoutSeconds * 2,
                    minSimilarityThreshold: adjusted.minSimilarityThreshold,
                    mmrLambda: adjusted.mmrLambda
                )
            }
        }

        return adjusted
    }

    /// Whether a cooldown should be applied before next step
    func shouldApplyCooldown() -> Bool {
        currentState.thermalState != .nominal || currentConfig.stepCooldownMs > 0
    }

    /// Apply cooldown between pipeline steps
    func applyCooldown() async {
        let cooldownMs = currentConfig.stepCooldownMs
        guard cooldownMs > 0 else { return }

        try? await Task.sleep(nanoseconds: cooldownMs * 1_000_000)
    }

    /// Log current optimization state
    func logCurrentState() {
        Log.info("""
        [AdaptivePipeline] Runtime State:
        • Thermal: \(currentState.thermalState.displayName)
        • Battery: \(Int(currentState.batteryLevel * 100))%\(currentState.isCharging ? " ⚡" : "")
        • Memory: \(currentState.memoryPressure.rawValue)
        • Optimization: \(currentOptimizationLevel.displayName)\(userOverrideLevel != nil ? " (override)" : "")
        • Device: \(deviceTier.displayName) (\(DeviceCapabilityService.shared.chipName))
        """, category: .performance)
    }

    // MARK: - Private Helpers

    private static func captureCurrentState() -> DeviceRuntimeState {
        let thermal = ProcessInfo.processInfo.thermalState
        let isMac = DeviceCapabilityService.shared.isMac || ProcessInfo.processInfo.isiOSAppOnMac

        let battery: Float
        let charging: Bool

#if canImport(UIKit)
        let rawBattery = UIDevice.current.batteryLevel
        let rawBatteryState = UIDevice.current.batteryState

        if isMac {
            let looksLikeGarbage = rawBatteryState == .unknown ||
                rawBattery < 0 ||
                (rawBattery < 0.05 && rawBatteryState != .unplugged)

            if looksLikeGarbage {
                battery = 1.0
                charging = true
            } else {
                battery = rawBattery
                charging = rawBatteryState == .charging || rawBatteryState == .full
            }
        } else {
            battery = rawBattery >= 0 ? rawBattery : 1.0
            charging = rawBatteryState == .charging || rawBatteryState == .full
        }
#else
        // macOS native: assume full/charging
        battery = 1.0
        charging = true
        let _ = isMac
#endif

        // Memory pressure detection
        let memoryPressure: DeviceRuntimeState.MemoryPressure
        let availableMemory: UInt64
        #if os(iOS)
        availableMemory = UInt64(os_proc_available_memory())
        #else
        availableMemory = SystemStateMonitor.macAvailableMemory()
        #endif
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryRatio = Double(availableMemory) / Double(totalMemory)

        if memoryRatio < 0.10 {
            memoryPressure = .critical
        } else if memoryRatio < 0.20 {
            memoryPressure = .warning
        } else {
            memoryPressure = .nominal
        }

        return DeviceRuntimeState(
            thermalState: thermal,
            batteryLevel: battery,
            isCharging: charging,
            memoryPressure: memoryPressure,
            timestamp: Date()
        )
    }

    private func enableBatteryMonitoring() {
#if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
#endif
    }

    private func setupObservers() {
        // Thermal state changes
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.updateState()
            }
        }

        // Battery level/state changes (iOS only)
#if canImport(UIKit)
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.updateState()
            }
        }
#endif

        // Memory warnings (iOS only)
#if canImport(UIKit)
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.handleMemoryWarning()
            }
        }
#endif
    }

    private func updateState() {
        let newState = Self.captureCurrentState()
        currentState = newState

        // Only update optimization level if no user override
        if userOverrideLevel == nil {
            let newLevel = newState.recommendedOptimizationLevel
            if newLevel != currentOptimizationLevel {
                currentOptimizationLevel = newLevel
                currentConfig = AdaptivePipelineConfig.base(for: deviceTier)
                    .adjusted(for: newLevel)

                Log.info(
                    "[AdaptivePipeline] Optimization level changed to \(newLevel.displayName) due to: thermal=\(newState.thermalState.displayName), battery=\(Int(newState.batteryLevel * 100))%",
                    category: .performance
                )

                TelemetryCenter.emit(
                    .system,
                    title: "Pipeline optimization adjusted",
                    metadata: [
                        "level": newLevel.rawValue,
                        "thermal": newState.thermalState.displayName,
                        "battery": "\(Int(newState.batteryLevel * 100))%",
                    ]
                )
            }
        }
    }

    private func handleMemoryWarning() {
        var newState = currentState
        newState = DeviceRuntimeState(
            thermalState: newState.thermalState,
            batteryLevel: newState.batteryLevel,
            isCharging: newState.isCharging,
            memoryPressure: .critical,
            timestamp: Date()
        )
        currentState = newState

        // Force efficient mode on memory warning
        if userOverrideLevel == nil, currentOptimizationLevel != .minimal {
            currentOptimizationLevel = .efficient
            currentConfig = AdaptivePipelineConfig.base(for: deviceTier)
                .adjusted(for: .efficient)

            Log.warning(
                "[AdaptivePipeline] Memory warning - switching to efficient mode",
                category: .performance
            )
        }
    }
}

// MARK: - Query Complexity

enum QueryComplexity: String, Sendable {
    case trivial // "hi", "thanks", single word
    case standard // Normal questions
    case complex // Multi-part, technical, requires reasoning
    case agentic // Explicitly agentic mode

    /// Estimate complexity from query text
    static func estimate(from query: String) -> QueryComplexity {
        let words = query.split(separator: " ").count
        let hasQuestionMark = query.contains("?")
        let hasMultipleParts = query.contains(" and ") ||
            query.contains(" or ") ||
            query.contains(";") ||
            query.contains("\n")

        // Very short queries are trivial
        if words <= 3 && !hasQuestionMark {
            return .trivial
        }

        // Multi-part or long queries are complex
        if hasMultipleParts || words > 25 {
            return .complex
        }

        // Technical indicators
        let technicalKeywords = ["explain", "compare", "analyze", "summarize",
                                 "calculate", "derive", "prove", "why", "how does"]
        let queryLower = query.lowercased()
        if technicalKeywords.contains(where: { queryLower.contains($0) }) {
            return .complex
        }

        return .standard
    }
}

// MARK: - Thermal State Extension

extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

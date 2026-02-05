//
//  HardwareTelemetryState.swift
//  OpenIntelligence
//
//  Real-time hardware activity state manager for the Motherboard HUD visualization.
//  Tracks Neural Engine (ANE), GPU, and CPU activity as services execute work.
//
//  This is a "reactive inference" system - instead of polling hardware sensors
//  (which is battery-intensive or restricted), we hook into the app's own event
//  loop. We know exactly when we request an Embedding (ANE), an Image Generation
//  (GPU), or an LLM Token (CPU/ANE). We drive visualization based on software
//  state, which is a perfect proxy for hardware usage.
//
//  Component Mapping (A17 Pro / A18 Pro SoC):
//  ┌─────────────────────────────────────────┐
//  │           Apple Silicon SoC             │
//  │  ┌─────────┐ ┌─────────┐ ┌───────────┐  │
//  │  │   CPU   │ │   GPU   │ │   ANE     │  │
//  │  │ Orange  │ │  Cyan   │ │  Purple   │  │
//  │  └─────────┘ └─────────┘ └───────────┘  │
//  └─────────────────────────────────────────┘
//

import Foundation
import SwiftUI
import Combine

// MARK: - Hardware Component Types

/// Represents different hardware components in the SoC
enum HardwareComponent: String, CaseIterable, Sendable {
    case neuralEngine = "Neural Engine"
    case gpu = "GPU"
    case cpu = "CPU"

    /// The signature color for this component
    var color: Color {
        switch self {
        case .neuralEngine:
            return Color(red: 0.69, green: 0.32, blue: 0.87) // Neon Purple #AF52DE
        case .gpu:
            return Color(red: 0.20, green: 0.68, blue: 0.90) // Neon Cyan #32ADE6
        case .cpu:
            return Color(red: 1.0, green: 0.58, blue: 0.0)   // Electric Orange #FF9500
        }
    }

    /// Relative position on the SoC visualization (normalized 0-1)
    /// These are approximate positions within the A-series chip die
    var relativePosition: CGPoint {
        switch self {
        case .neuralEngine:
            // ANE is typically in the bottom-right quadrant of the die
            return CGPoint(x: 0.65, y: 0.60)
        case .gpu:
            // GPU cores are typically in the top-left/center area
            return CGPoint(x: 0.35, y: 0.40)
        case .cpu:
            // CPU cores are typically in the top portion
            return CGPoint(x: 0.50, y: 0.30)
        }
    }
}

// MARK: - Activity Event Types

/// Types of hardware activity that can be reported
enum HardwareActivityType: String, Sendable {
    // Neural Engine (ANE) activities
    case embeddingGeneration = "Embedding"
    case llmInference = "LLM Inference"
    case reranking = "ReRanking"
    case tokenization = "Tokenization"

    // GPU activities
    case vectorSimilarity = "Vector Similarity"
    case mmrComputation = "MMR Diversity"
    case metalCompute = "Metal Compute"
    case imageProcessing = "Image Processing"

    // CPU activities
    case queryProcessing = "Query Processing"
    case ragOrchestration = "RAG Pipeline"
    case textChunking = "Text Chunking"
    case bm25Scoring = "BM25 Scoring"
    case dataDecoding = "Data Decoding"

    /// Which hardware component this activity primarily uses
    var primaryComponent: HardwareComponent {
        switch self {
        case .embeddingGeneration, .llmInference, .reranking, .tokenization:
            return .neuralEngine
        case .vectorSimilarity, .mmrComputation, .metalCompute, .imageProcessing:
            return .gpu
        case .queryProcessing, .ragOrchestration, .textChunking, .bm25Scoring, .dataDecoding:
            return .cpu
        }
    }
}

// MARK: - Hardware Telemetry State

/// Central state manager for hardware activity visualization
/// Singleton that can be updated from any service to drive the HUD
@MainActor
final class HardwareTelemetryState: ObservableObject {

    // MARK: - Shared Instance

    static let shared = HardwareTelemetryState()

    // MARK: - Published State (0.0 to 1.0 intensity)

    /// Neural Engine (ANE) activity intensity
    @Published private(set) var aneIntensity: Double = 0.0

    /// GPU activity intensity
    @Published private(set) var gpuIntensity: Double = 0.0

    /// CPU activity intensity
    @Published private(set) var cpuIntensity: Double = 0.0

    /// Current activity label for display
    @Published private(set) var currentActivityLabel: String = ""

    /// Whether any component is currently active
    @Published private(set) var isActive: Bool = false

    /// History of recent activity for sparkline visualizations
    @Published private(set) var aneHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var cpuHistory: [Double] = []

    // MARK: - Internal State

    private var sustainedActivities: Set<HardwareActivityType> = []
    private var decayTimers: [HardwareComponent: Task<Void, Never>] = [:]
    private var historyTimer: Task<Void, Never>?

    /// Maximum history entries to keep
    private let maxHistoryEntries = 30

    // MARK: - Initialization

    private init() {
        startHistoryRecording()
    }

    deinit {
        historyTimer?.cancel()
        decayTimers.values.forEach { $0.cancel() }
    }

    // MARK: - Public API: Pulse Events

    /// Report a brief hardware activity pulse
    /// Use for short, discrete operations like single embedding generation
    /// - Parameters:
    ///   - activity: The type of activity being performed
    ///   - intensity: How intense the activity is (0.0-1.0), defaults to 1.0
    ///   - duration: How long to show the pulse before decay, defaults to 0.15s
    func pulse(
        _ activity: HardwareActivityType,
        intensity: Double = 1.0,
        duration: TimeInterval = 0.15
    ) {
        let component = activity.primaryComponent
        let clampedIntensity = min(1.0, max(0.0, intensity))

        // Cancel any existing decay timer for this component
        decayTimers[component]?.cancel()

        // Set intensity with animation
        withAnimation(.easeOut(duration: 0.08)) {
            setIntensity(clampedIntensity, for: component)
            currentActivityLabel = activity.rawValue
            isActive = true
        }

        // Schedule decay
        decayTimers[component] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard !Task.isCancelled else { return }
            self?.decay(component)
        }

        Log.verbose("[HardwareTelemetry] Pulse \(activity.rawValue) @ \(Int(clampedIntensity * 100))%", category: .telemetry)
    }

    /// Report a sustained hardware activity (stays active until explicitly stopped)
    /// Use for streaming operations like LLM token generation
    /// - Parameters:
    ///   - activity: The type of activity
    ///   - active: Whether to start or stop the sustained activity
    ///   - intensity: Intensity level while sustained
    func sustain(
        _ activity: HardwareActivityType,
        active: Bool,
        intensity: Double = 0.85
    ) {
        let component = activity.primaryComponent

        if active {
            sustainedActivities.insert(activity)
            decayTimers[component]?.cancel()

            withAnimation(.easeInOut(duration: 0.15)) {
                setIntensity(intensity, for: component)
                currentActivityLabel = activity.rawValue
                isActive = true
            }

            Log.verbose("[HardwareTelemetry] Sustain START \(activity.rawValue)", category: .telemetry)
        } else {
            sustainedActivities.remove(activity)

            // Only decay if no other sustained activities for this component
            let hasOtherSustained = sustainedActivities.contains { $0.primaryComponent == component }
            if !hasOtherSustained {
                decayTimers[component] = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    self?.decay(component)
                }
            }

            Log.verbose("[HardwareTelemetry] Sustain STOP \(activity.rawValue)", category: .telemetry)
        }
    }

    /// Report batch processing activity with progress
    /// Provides a pulsing effect during batch operations
    /// - Parameters:
    ///   - activity: The type of activity
    ///   - progress: Current progress (0.0-1.0)
    ///   - isComplete: Whether the batch is complete
    func batchProgress(
        _ activity: HardwareActivityType,
        progress: Double,
        isComplete: Bool
    ) {
        let component = activity.primaryComponent

        if isComplete {
            // Final pulse then decay
            withAnimation(.easeOut(duration: 0.1)) {
                setIntensity(1.0, for: component)
            }

            decayTimers[component] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.decay(component)
            }
        } else {
            // Pulsing effect based on progress
            let pulseIntensity = 0.5 + (0.5 * sin(progress * .pi * 8))
            withAnimation(.easeInOut(duration: 0.1)) {
                setIntensity(pulseIntensity, for: component)
                currentActivityLabel = "\(activity.rawValue) \(Int(progress * 100))%"
                isActive = true
            }
        }
    }

    /// Reset all intensities to zero
    func reset() {
        sustainedActivities.removeAll()
        decayTimers.values.forEach { $0.cancel() }
        decayTimers.removeAll()

        withAnimation(.easeOut(duration: 0.3)) {
            aneIntensity = 0.0
            gpuIntensity = 0.0
            cpuIntensity = 0.0
            currentActivityLabel = ""
            isActive = false
        }
    }

    // MARK: - Convenience Methods for Common Operations

    /// Quick method for embedding operations (used by EmbeddingService)
    func reportEmbedding(count: Int = 1) {
        let intensity = min(1.0, 0.6 + Double(count) * 0.1)
        pulse(.embeddingGeneration, intensity: intensity, duration: 0.2)
    }

    /// Quick method for LLM inference (sustained while generating)
    func reportLLMInference(active: Bool) {
        sustain(.llmInference, active: active)
    }

    /// Quick method for GPU vector operations
    func reportGPUCompute(operation: HardwareActivityType = .vectorSimilarity) {
        pulse(operation, intensity: 0.9, duration: 0.25)
    }

    /// Quick method for RAG pipeline orchestration
    func reportRAGPipeline(stage: String) {
        currentActivityLabel = stage
        pulse(.ragOrchestration, intensity: 0.7, duration: 0.3)
    }

    // MARK: - Private Helpers

    private func setIntensity(_ value: Double, for component: HardwareComponent) {
        switch component {
        case .neuralEngine:
            aneIntensity = value
        case .gpu:
            gpuIntensity = value
        case .cpu:
            cpuIntensity = value
        }
    }

    private func decay(_ component: HardwareComponent) {
        withAnimation(.easeIn(duration: 0.4)) {
            setIntensity(0.0, for: component)
        }

        // Check if all components are now idle
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if aneIntensity < 0.01 && gpuIntensity < 0.01 && cpuIntensity < 0.01 {
                withAnimation {
                    isActive = false
                    currentActivityLabel = ""
                }
            }
        }
    }

    private func startHistoryRecording() {
        historyTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.recordHistory()
            }
        }
    }

    private func recordHistory() {
        // Append current values to history
        aneHistory.append(aneIntensity)
        gpuHistory.append(gpuIntensity)
        cpuHistory.append(cpuIntensity)

        // Trim to max entries
        if aneHistory.count > maxHistoryEntries {
            aneHistory.removeFirst(aneHistory.count - maxHistoryEntries)
        }
        if gpuHistory.count > maxHistoryEntries {
            gpuHistory.removeFirst(gpuHistory.count - maxHistoryEntries)
        }
        if cpuHistory.count > maxHistoryEntries {
            cpuHistory.removeFirst(cpuHistory.count - maxHistoryEntries)
        }
    }

    // MARK: - Debug / Demo Methods

    #if DEBUG
    /// Demo mode: Cycle through all components for testing
    func runDemo() {
        Task {
            // Neural Engine burst
            pulse(.embeddingGeneration, intensity: 1.0, duration: 0.3)
            try? await Task.sleep(for: .milliseconds(500))

            // GPU burst
            pulse(.vectorSimilarity, intensity: 0.9, duration: 0.3)
            try? await Task.sleep(for: .milliseconds(500))

            // CPU burst
            pulse(.ragOrchestration, intensity: 0.8, duration: 0.3)
            try? await Task.sleep(for: .milliseconds(500))

            // Sustained LLM inference
            sustain(.llmInference, active: true)
            try? await Task.sleep(for: .seconds(2))
            sustain(.llmInference, active: false)
        }
    }
    #endif
}

// MARK: - Non-Isolated Access for Background Services

/// Thread-safe wrapper for reporting telemetry from background actors/threads
/// Services that are actors or run on background threads should use this
enum HardwareTelemetryReporter {

    /// Report a pulse event from any thread
    static func pulse(
        _ activity: HardwareActivityType,
        intensity: Double = 1.0,
        duration: TimeInterval = 0.15
    ) {
        Task { @MainActor in
            HardwareTelemetryState.shared.pulse(activity, intensity: intensity, duration: duration)
        }
    }

    /// Report sustained activity from any thread
    static func sustain(
        _ activity: HardwareActivityType,
        active: Bool,
        intensity: Double = 0.85
    ) {
        Task { @MainActor in
            HardwareTelemetryState.shared.sustain(activity, active: active, intensity: intensity)
        }
    }

    /// Report batch progress from any thread
    static func batchProgress(
        _ activity: HardwareActivityType,
        progress: Double,
        isComplete: Bool
    ) {
        Task { @MainActor in
            HardwareTelemetryState.shared.batchProgress(activity, progress: progress, isComplete: isComplete)
        }
    }

    /// Quick embedding report from any thread
    static func reportEmbedding(count: Int = 1) {
        Task { @MainActor in
            HardwareTelemetryState.shared.reportEmbedding(count: count)
        }
    }

    /// Quick LLM inference report from any thread
    static func reportLLMInference(active: Bool) {
        Task { @MainActor in
            HardwareTelemetryState.shared.reportLLMInference(active: active)
        }
    }

    /// Quick GPU compute report from any thread
    static func reportGPUCompute(operation: HardwareActivityType = .vectorSimilarity) {
        Task { @MainActor in
            HardwareTelemetryState.shared.reportGPUCompute(operation: operation)
        }
    }

    /// Quick RAG pipeline report from any thread
    static func reportRAGPipeline(stage: String) {
        Task { @MainActor in
            HardwareTelemetryState.shared.reportRAGPipeline(stage: stage)
        }
    }
}

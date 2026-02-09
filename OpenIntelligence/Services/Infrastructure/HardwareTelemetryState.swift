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
//  ALSO exposes REAL hardware metrics where Apple APIs permit:
//  - CPU time consumed by this process (mach_task_info)
//  - Available memory (os_proc_available_memory)
//  - GPU memory allocated (MTLDevice.currentAllocatedSize)
//  - Thermal state (ProcessInfo.thermalState)
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
import Metal

// MARK: - Hardware Component Types

/// Represents different hardware components in the device
enum HardwareComponent: String, CaseIterable, Sendable {
    case neuralEngine = "Neural Engine"
    case gpu = "GPU"
    case cpu = "CPU"
    case haptic = "Taptic Engine"

    /// The signature color for this component
    var color: Color {
        switch self {
        case .neuralEngine:
            return Color(red: 0.69, green: 0.32, blue: 0.87) // Neon Purple #AF52DE
        case .gpu:
            return Color(red: 0.20, green: 0.68, blue: 0.90) // Neon Cyan #32ADE6
        case .cpu:
            return Color(red: 1.0, green: 0.58, blue: 0.0)   // Electric Orange #FF9500
        case .haptic:
            return Color(red: 1.0, green: 0.84, blue: 0.88)  // Soft Pink #FFD6E0
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
        case .haptic:
            // Taptic Engine at bottom of device, left of center
            return CGPoint(x: 0.40, y: 0.90)
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

    /// Haptic (Taptic Engine) activity intensity
    @Published private(set) var hapticIntensity: Double = 0.0

    /// Current activity label for display
    @Published private(set) var currentActivityLabel: String = ""

    /// Whether any component is currently active
    @Published private(set) var isActive: Bool = false

    /// History of recent activity for sparkline visualizations
    @Published private(set) var aneHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var hapticHistory: [Double] = []

    // MARK: - Real Hardware Metrics (Actual Measurements)

    /// Operations counter - ANE (Neural Engine) inference operations
    @Published private(set) var aneOperationCount: Int = 0

    /// Operations counter - GPU compute dispatches
    @Published private(set) var gpuOperationCount: Int = 0

    /// Operations counter - CPU-bound operations (BM25, chunking, etc.)
    @Published private(set) var cpuOperationCount: Int = 0

    /// Total embeddings generated this session
    @Published private(set) var totalEmbeddingsGenerated: Int = 0

    /// Total LLM tokens generated this session
    @Published private(set) var totalLLMTokensGenerated: Int = 0

    /// Last embedding latency in milliseconds
    @Published private(set) var lastEmbeddingLatencyMs: Double = 0

    /// Last LLM token latency in milliseconds (time per token)
    @Published private(set) var lastLLMTokenLatencyMs: Double = 0

    /// Last GPU operation latency in milliseconds
    @Published private(set) var lastGPULatencyMs: Double = 0

    /// GPU memory allocated (bytes) - from MTLDevice
    @Published private(set) var gpuMemoryAllocated: UInt64 = 0

    /// CPU time consumed by this process (seconds) - from mach_task_info
    @Published private(set) var cpuTimeConsumed: Double = 0

    /// Detailed metrics string for display
    @Published private(set) var detailedMetricsString: String = ""

    // MARK: - REAL CPU Usage (from Mach APIs via SystemStateMonitor)

    /// Real system-wide CPU usage (0-100%) - same as Xcode Energy Impact shows
    @Published private(set) var realSystemCpuPercent: Double = 0

    /// Real process (our app) CPU usage (0-100%) - how much CPU WE are using
    @Published private(set) var realProcessCpuPercent: Double = 0

    /// Session start time for metrics
    private let sessionStartTime = Date()

    // MARK: - Per-Component Active Time Tracking

    /// Cumulative active time per component (seconds)
    @Published private(set) var aneActiveTime: TimeInterval = 0
    @Published private(set) var gpuActiveTime: TimeInterval = 0
    @Published private(set) var cpuActiveTime: TimeInterval = 0
    @Published private(set) var hapticFireCount: Int = 0

    /// Timestamps when each component last became active (for intensity tracking)
    private var aneActiveStart: Date?
    private var gpuActiveStart: Date?
    private var cpuActiveStart: Date?

    /// Wall-clock timestamp of first operation per component (for session uptime)
    private var aneFirstOp: Date?
    private var gpuFirstOp: Date?
    private var cpuFirstOp: Date?
    private var hapticFirstOp: Date?

    /// Structured component activity for legend display
    struct ComponentActivity: Equatable {
        let name: String
        let color: String // "purple", "cyan", "orange", "pink"
        let isActive: Bool
        let percentage: Double  // 0.0-100.0 - REAL CPU% from Mach APIs, inferred for ANE/GPU
        let opsCount: Int
    }

    /// All triggered components with their stats (for legend) - updated every 500ms
    /// CPU: REAL % from Mach APIs (same as Xcode Energy Impact)
    /// ANE/GPU: Activity-based indicators (Apple doesn't expose utilization %)
    @Published private(set) var componentActivities: [ComponentActivity] = []

    /// Cached previous values to avoid publishing identical arrays
    private var lastPublishedActivities: [ComponentActivity] = []

    /// Rebuild the component activities array (stable order, only publish on change)
    /// NOW USES REAL CPU % from Mach APIs (same as Xcode Energy Impact)
    /// ANE/GPU show activity-based indicators since Apple doesn't expose their utilization
    /// Taptic is shown separately — it's an output device, not a compute unit.
    private func rebuildComponentActivities() {
        var activities: [ComponentActivity] = []

        // CPU - ALWAYS SHOW with REAL percentage from Mach APIs
        // This is the SAME metric Xcode Energy Impact uses
        let realCpuPct = realProcessCpuPercent
        activities.append(ComponentActivity(
            name: "CPU",
            color: "orange",
            isActive: realCpuPct > 1.0 || cpuIntensity > 0.01,
            percentage: realCpuPct,
            opsCount: cpuOperationCount
        ))

        // ANE (Neural Engine) - ALWAYS SHOW (it's part of the SoC)
        // Apple doesn't expose ANE utilization %, so we use activity intensity
        let anePct = aneIntensity * 100.0
        activities.append(ComponentActivity(
            name: "ANE",
            color: "purple",
            isActive: aneIntensity > 0.01,
            percentage: anePct,
            opsCount: aneOperationCount
        ))

        // GPU - ALWAYS SHOW (it's part of the SoC)
        // Apple doesn't expose GPU utilization % directly
        let gpuPct = gpuIntensity * 100.0
        activities.append(ComponentActivity(
            name: "GPU",
            color: "cyan",
            isActive: gpuIntensity > 0.01,
            percentage: gpuPct,
            opsCount: gpuOperationCount
        ))

        // Taptic shown separately in the legend — not part of compute %
        if hapticFireCount > 0 {
            activities.append(ComponentActivity(
                name: "Taptic",
                color: "pink",
                isActive: hapticIntensity > 0.01,
                percentage: -1, // sentinel: not a compute component
                opsCount: hapticFireCount
            ))
        }

        // Only publish if something meaningful changed (prevents layout thrash)
        var structuralChange = activities.count != lastPublishedActivities.count
        if !structuralChange {
            for i in 0..<activities.count {
                let a = activities[i]
                let b = lastPublishedActivities[i]
                if a.name != b.name || a.opsCount != b.opsCount || a.isActive != b.isActive {
                    structuralChange = true
                    break
                }
            }
        }
        // Check percentage drift (>1% change)
        var pctDrift = false
        if !structuralChange {
            for i in 0..<activities.count {
                let newPct: Double = activities[i].percentage
                let oldPct: Double = lastPublishedActivities[i].percentage
                let delta: Double = newPct - oldPct
                if delta >= 1.0 || delta <= -1.0 {
                    pctDrift = true
                    break
                }
            }
        }

        if structuralChange || pctDrift || lastPublishedActivities.isEmpty {
            componentActivities = activities
            lastPublishedActivities = activities
        }
    }

    // MARK: - Internal State

    private var sustainedActivities: Set<HardwareActivityType> = []
    private var decayTimers: [HardwareComponent: Task<Void, Never>] = [:]
    private var historyTimer: Task<Void, Never>?
    private var cpuMonitorTask: Task<Void, Never>?
    private var systemStateSubscription: AnyCancellable?

    /// Maximum history entries to keep
    private let maxHistoryEntries = 30

    // MARK: - Initialization

    private init() {
        startHistoryRecording()
        startRealCPUMonitoring()
    }

    deinit {
        historyTimer?.cancel()
        cpuMonitorTask?.cancel()
        systemStateSubscription?.cancel()
        decayTimers.values.forEach { $0.cancel() }
    }

    // MARK: - Real CPU Monitoring

    /// Continuously monitor real CPU usage from SystemStateMonitor (Mach APIs)
    private func startRealCPUMonitoring() {
        // Subscribe to SystemStateMonitor updates
        systemStateSubscription = SystemStateMonitor.shared.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.realSystemCpuPercent = state.systemCpuUsage
                self?.realProcessCpuPercent = state.processCpuUsage
            }

        // Also poll more frequently for smoother HUD updates (SystemStateMonitor updates every 2s)
        cpuMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self = self else { break }

                // Get fresh CPU readings
                let systemCpu = MachCPUMonitor.getSystemCPUUsage()
                let processCpu = MachCPUMonitor.getProcessCPUUsage()

                await MainActor.run {
                    self.realSystemCpuPercent = systemCpu
                    self.realProcessCpuPercent = processCpu
                    self.rebuildComponentActivities()
                }
            }
        }
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

        // Set intensity with FAST animation for real-time profiler feel
        withAnimation(.linear(duration: 0.015)) {
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
    /// NOW WITH PULSING ANIMATION - keeps the HUD "dancing" during generation
    /// - Parameters:
    ///   - activity: The type of activity
    ///   - active: Whether to start or stop the sustained activity
    ///   - intensity: Base intensity level while sustained
    func sustain(
        _ activity: HardwareActivityType,
        active: Bool,
        intensity: Double = 0.85
    ) {
        let component = activity.primaryComponent

        if active {
            sustainedActivities.insert(activity)
            decayTimers[component]?.cancel()

            // Set initial intensity
            withAnimation(.linear(duration: 0.02)) {
                setIntensity(intensity, for: component)
                currentActivityLabel = activity.rawValue
                isActive = true
            }

            // START PULSING ANIMATION - keeps HUD "dancing" during sustained activity
            startSustainedPulse(activity: activity, baseIntensity: intensity)

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

    /// Pulsing animation for sustained activities - keeps HUD "dancing"
    private var sustainedPulseTasks: [HardwareActivityType: Task<Void, Never>] = [:]

    private func startSustainedPulse(activity: HardwareActivityType, baseIntensity: Double) {
        // Cancel existing pulse for this activity
        sustainedPulseTasks[activity]?.cancel()

        sustainedPulseTasks[activity] = Task { [weak self] in
            var phase: Double = 0
            while !Task.isCancelled {
                guard let self = self, self.sustainedActivities.contains(activity) else { break }

                // Sine wave pulsing: oscillates between 0.6x and 1.0x of base intensity
                let pulseMultiplier = 0.8 + 0.2 * sin(phase)
                let pulsedIntensity = min(1.0, baseIntensity * pulseMultiplier)

                await MainActor.run {
                    // Fast update without animation for smooth pulsing
                    self.setIntensity(pulsedIntensity, for: activity.primaryComponent)
                }

                phase += 0.15 // ~40ms per frame ≈ 25fps pulse
                try? await Task.sleep(for: .milliseconds(40))
            }
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
            // Final pulse then decay - FAST for real-time feel
            withAnimation(.linear(duration: 0.015)) {
                setIntensity(1.0, for: component)
            }

            decayTimers[component] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self?.decay(component)
            }
        } else {
            // Pulsing effect based on progress - FAST updates
            let pulseIntensity = 0.5 + (0.5 * sin(progress * .pi * 8))
            withAnimation(.linear(duration: 0.02)) {
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

        withAnimation(.linear(duration: 0.1)) {
            aneIntensity = 0.0
            gpuIntensity = 0.0
            cpuIntensity = 0.0
            hapticIntensity = 0.0
            currentActivityLabel = ""
            isActive = false
        }
    }

    // MARK: - Haptic Feedback Reporting

    /// Report haptic feedback activity (Taptic Engine)
    /// Called by DSHaptics when haptic feedback is triggered
    /// - Parameter style: The style of haptic (light, medium, selection, etc.)
    func reportHaptic(style: String = "impact") {
        // Haptic feedback is very brief - short pulse
        decayTimers[.haptic]?.cancel()
        if hapticFirstOp == nil { hapticFirstOp = Date() }
        hapticFireCount += 1
        rebuildComponentActivities()

        // INSTANT rise for real-time feel
        withAnimation(.linear(duration: 0.01)) {
            hapticIntensity = 1.0
            isActive = true
        }

        // Hold bright then fade - long enough to actually SEE the glow
        decayTimers[.haptic] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.hapticIntensity = 0.0
                }
            }
        }

        Log.verbose("[HardwareTelemetry] Haptic pulse: \(style)", category: .telemetry)
    }

    /// Report keyboard typing activity (visualizes system keyboard haptics)
    /// Called on each character typed - doesn't generate new haptics, just visualizes
    /// iOS keyboard already fires Taptic Engine - we just show it in the HUD
    func reportKeyboardTap() {
        // Very brief pulse - keyboard haptics are tiny and rapid
        decayTimers[.haptic]?.cancel()
        if hapticFirstOp == nil { hapticFirstOp = Date() }
        hapticFireCount += 1
        rebuildComponentActivities()

        // Keyboard haptics: visible but lighter than explicit haptics
        withAnimation(.linear(duration: 0.01)) {
            hapticIntensity = 0.8
            isActive = true
        }

        // Brief hold then fade - visible per-keystroke flash
        decayTimers[.haptic] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.15)) {
                    self?.hapticIntensity = 0.0
                }
            }
        }
    }

    // MARK: - Private Counter Helpers

    /// Increment the operation counter and set firstOp timestamp for a component
    private func incrementCounter(for component: HardwareComponent) {
        switch component {
        case .neuralEngine:
            if aneFirstOp == nil { aneFirstOp = Date() }
            aneOperationCount += 1
        case .gpu:
            if gpuFirstOp == nil { gpuFirstOp = Date() }
            gpuOperationCount += 1
        case .cpu:
            if cpuFirstOp == nil { cpuFirstOp = Date() }
            cpuOperationCount += 1
        case .haptic:
            break // Haptic is handled separately in reportHaptic
        }
        rebuildComponentActivities()
    }

    /// Public counter increment for ANE (used when pulse is already called separately)
    func incrementANECounter() {
        incrementCounter(for: .neuralEngine)
    }

    // MARK: - Convenience Methods for Common Operations

    /// Quick method for embedding operations (used by EmbeddingService)
    func reportEmbedding(count: Int = 1) {
        let intensity = min(1.0, 0.6 + Double(count) * 0.1)
        pulse(.embeddingGeneration, intensity: intensity, duration: 0.2)
        incrementCounter(for: .neuralEngine)
        totalEmbeddingsGenerated += count
    }

    /// Report embedding with measured latency
    func reportEmbeddingWithLatency(count: Int = 1, latencyMs: Double) {
        reportEmbedding(count: count)
        lastEmbeddingLatencyMs = latencyMs
        updateDetailedMetrics()
    }

    /// Quick method for LLM inference (sustained while generating)
    func reportLLMInference(active: Bool) {
        sustain(.llmInference, active: active)
        if active {
            incrementCounter(for: .neuralEngine)
        }
    }

    /// Report LLM token generation with stats
    func reportLLMToken(tokenLatencyMs: Double) {
        totalLLMTokensGenerated += 1
        lastLLMTokenLatencyMs = tokenLatencyMs
        // Light pulse for each token — no counter increment per token
        pulse(.llmInference, intensity: 0.7, duration: 0.08)
    }

    /// Quick method for GPU vector operations
    func reportGPUCompute(operation: HardwareActivityType = .vectorSimilarity) {
        pulse(operation, intensity: 0.9, duration: 0.25)
        incrementCounter(for: .gpu)
    }

    /// Report GPU compute with measured latency
    func reportGPUComputeWithLatency(operation: HardwareActivityType = .vectorSimilarity, latencyMs: Double) {
        reportGPUCompute(operation: operation)
        lastGPULatencyMs = latencyMs
        updateDetailedMetrics()
    }

    /// Report CPU-bound operation
    func reportCPUOperation() {
        pulse(.queryProcessing, intensity: 0.5, duration: 0.1)
        incrementCounter(for: .cpu)
    }

    /// Quick method for RAG pipeline orchestration (CPU-bound work)
    func reportRAGPipeline(stage: String) {
        currentActivityLabel = stage
        pulse(.ragOrchestration, intensity: 0.7, duration: 0.3)
        incrementCounter(for: .cpu)
    }

    // MARK: - Private Helpers

    private func setIntensity(_ value: Double, for component: HardwareComponent) {
        switch component {
        case .neuralEngine:
            // Track active time
            if value > 0.01 && aneActiveStart == nil {
                aneActiveStart = Date()
            } else if value <= 0.01, let start = aneActiveStart {
                aneActiveTime += Date().timeIntervalSince(start)
                aneActiveStart = nil
            }
            aneIntensity = value
        case .gpu:
            if value > 0.01 && gpuActiveStart == nil {
                gpuActiveStart = Date()
            } else if value <= 0.01, let start = gpuActiveStart {
                gpuActiveTime += Date().timeIntervalSince(start)
                gpuActiveStart = nil
            }
            gpuIntensity = value
        case .cpu:
            if value > 0.01 && cpuActiveStart == nil {
                cpuActiveStart = Date()
            } else if value <= 0.01, let start = cpuActiveStart {
                cpuActiveTime += Date().timeIntervalSince(start)
                cpuActiveStart = nil
            }
            cpuIntensity = value
        case .haptic:
            hapticIntensity = value
        }
    }

    private func decay(_ component: HardwareComponent) {
        // FAST decay for real-time profiler feel
        withAnimation(.linear(duration: 0.1)) {
            setIntensity(0.0, for: component)
        }

        // Check if all components are now idle
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            if aneIntensity < 0.01 && gpuIntensity < 0.01 && cpuIntensity < 0.01 && hapticIntensity < 0.01 {
                withAnimation(.linear(duration: 0.05)) {
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
        hapticHistory.append(hapticIntensity)

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
        if hapticHistory.count > maxHistoryEntries {
            hapticHistory.removeFirst(hapticHistory.count - maxHistoryEntries)
        }

        // Periodically update real hardware metrics
        updateRealHardwareMetrics()

        // Rebuild published component activities so legend stays current
        rebuildComponentActivities()
    }

    // MARK: - Real Hardware Metrics Collection

    /// Update CPU time from mach_task_info (actual kernel metric)
    private func updateRealHardwareMetrics() {
        // Get CPU time consumed by this task
        cpuTimeConsumed = Self.getTaskCPUTime()

        // Get GPU memory allocated
        gpuMemoryAllocated = Self.getGPUMemoryAllocated()

        // Update detailed metrics string (rate limited to every 1s via history)
        updateDetailedMetrics()
    }

    /// Get total CPU time consumed by this process (user + system time)
    /// Uses mach_task_info which is a public API on iOS
    private static func getTaskCPUTime() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        // user_time and system_time are in time_value_t (seconds + microseconds)
        let userSeconds = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let systemSeconds = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return userSeconds + systemSeconds
    }

    /// Get GPU memory currently allocated by Metal
    private static func getGPUMemoryAllocated() -> UInt64 {
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }
        return UInt64(device.currentAllocatedSize)
    }

    /// Update the detailed metrics display string
    private func updateDetailedMetrics() {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        let minutes = Int(sessionDuration) / 60
        let seconds = Int(sessionDuration) % 60

        var parts: [String] = []

        // Operation counts
        if totalEmbeddingsGenerated > 0 {
            parts.append("📊 \(totalEmbeddingsGenerated) emb")
        }
        if totalLLMTokensGenerated > 0 {
            parts.append("💬 \(totalLLMTokensGenerated) tok")
        }
        if gpuOperationCount > 0 {
            parts.append("⚡ \(gpuOperationCount) gpu")
        }

        // Latencies
        if lastEmbeddingLatencyMs > 0 {
            parts.append(String(format: "⏱️%.0fms/emb", lastEmbeddingLatencyMs))
        }
        if lastLLMTokenLatencyMs > 0 {
            parts.append(String(format: "%.0fms/tok", lastLLMTokenLatencyMs))
        }

        // CPU time
        if cpuTimeConsumed > 0.1 {
            parts.append(String(format: "🔥%.1fs cpu", cpuTimeConsumed))
        }

        // GPU memory (if significant)
        if gpuMemoryAllocated > 1_000_000 { // > 1MB
            let mb = Double(gpuMemoryAllocated) / 1_000_000
            parts.append(String(format: "🎮%.0fMB", mb))
        }

        // Session duration
        parts.append("⏰\(minutes):\(String(format: "%02d", seconds))")

        detailedMetricsString = parts.joined(separator: " ")
    }

    /// Summary metrics for HUD display (compact)
    /// Shows LIVE activity state + cumulative stats
    var compactMetricsSummary: String {
        var summary: [String] = []

        // Live activity state - what's firing RIGHT NOW
        var liveComponents: [String] = []
        if aneIntensity > 0.01 { liveComponents.append("ANE") }
        if gpuIntensity > 0.01 { liveComponents.append("GPU") }
        if cpuIntensity > 0.01 { liveComponents.append("CPU") }

        if !liveComponents.isEmpty {
            summary.append(liveComponents.joined(separator: "+"))
        }

        // Show current activity label if present
        if !currentActivityLabel.isEmpty && liveComponents.isEmpty {
            summary.append(currentActivityLabel)
        }

        // Cumulative stats (only if we have them)
        if totalEmbeddingsGenerated > 0 {
            summary.append("\(totalEmbeddingsGenerated) emb")
        }
        if totalLLMTokensGenerated > 0 {
            summary.append("\(totalLLMTokensGenerated) tok")
        }
        if gpuOperationCount > 0 {
            summary.append("\(gpuOperationCount) ops")
        }

        return summary.isEmpty ? "" : summary.joined(separator: " · ")
    }

    /// Operations per second estimate
    var opsPerSecond: Double {
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        guard elapsed > 0 else { return 0 }
        let totalOps = Double(aneOperationCount + gpuOperationCount + cpuOperationCount)
        return totalOps / elapsed
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
/// Uses HIGH PRIORITY dispatch for real-time profiler responsiveness
/// All methods are nonisolated and safe to call from any context
enum HardwareTelemetryReporter {

    /// Report a pulse event from any thread - HIGH PRIORITY for real-time feel
    nonisolated static func pulse(
        _ activity: HardwareActivityType,
        intensity: Double = 1.0,
        duration: TimeInterval = 0.15
    ) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.pulse(activity, intensity: intensity, duration: duration)
        }
    }

    /// Report sustained activity from any thread - HIGH PRIORITY
    nonisolated static func sustain(
        _ activity: HardwareActivityType,
        active: Bool,
        intensity: Double = 0.85
    ) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.sustain(activity, active: active, intensity: intensity)
        }
    }

    /// Report batch progress from any thread - HIGH PRIORITY
    nonisolated static func batchProgress(
        _ activity: HardwareActivityType,
        progress: Double,
        isComplete: Bool
    ) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.batchProgress(activity, progress: progress, isComplete: isComplete)
        }
    }

    /// Quick embedding report from any thread - HIGH PRIORITY
    nonisolated static func reportEmbedding(count: Int = 1) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportEmbedding(count: count)
        }
    }

    /// Quick LLM inference report from any thread - HIGH PRIORITY
    nonisolated static func reportLLMInference(active: Bool) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportLLMInference(active: active)
        }
    }

    /// Quick GPU compute report from any thread - HIGH PRIORITY
    nonisolated static func reportGPUCompute(operation: HardwareActivityType = .vectorSimilarity) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportGPUCompute(operation: operation)
        }
    }

    /// Quick RAG pipeline report from any thread - HIGH PRIORITY
    nonisolated static func reportRAGPipeline(stage: String) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportRAGPipeline(stage: stage)
        }
    }

    /// Report embedding with measured latency from any thread - HIGH PRIORITY
    nonisolated static func reportEmbeddingWithLatency(count: Int = 1, latencyMs: Double) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportEmbeddingWithLatency(count: count, latencyMs: latencyMs)
        }
    }

    /// Report LLM token with latency from any thread - HIGH PRIORITY
    nonisolated static func reportLLMToken(tokenLatencyMs: Double) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportLLMToken(tokenLatencyMs: tokenLatencyMs)
        }
    }

    /// Report GPU compute with latency from any thread - HIGH PRIORITY
    nonisolated static func reportGPUComputeWithLatency(operation: HardwareActivityType = .vectorSimilarity, latencyMs: Double) {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportGPUComputeWithLatency(operation: operation, latencyMs: latencyMs)
        }
    }

    /// Report CPU-bound operation from any thread - HIGH PRIORITY
    nonisolated static func reportCPUOperation() {
        Task(priority: .high) { @MainActor in
            HardwareTelemetryState.shared.reportCPUOperation()
        }
    }
}

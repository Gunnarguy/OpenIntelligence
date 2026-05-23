//
//  SystemStateMonitor.swift
//  OpenIntelligence
//
//  Centralized real-time monitoring of all device state metrics.
//  Exposes every relevant Apple API metric for transparency.
//
//  NOW WITH REAL CPU UTILIZATION via Mach APIs (same as Xcode Energy Impact)
//

import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Darwin.Mach

// MARK: - System State Snapshot

/// Complete snapshot of current device state
struct SystemStateSnapshot: Sendable, Equatable {
    // Thermal
    let thermalState: ProcessInfo.ThermalState
    let thermalStateName: String

    // Battery
    let batteryLevel: Float // 0.0-1.0, -1 if unknown
#if canImport(UIKit)
    let batteryState: UIDevice.BatteryState
#else
    let batteryState: MacBatteryState
#endif
    let isCharging: Bool
    let isFullyCharged: Bool

    // Memory
    let availableMemoryBytes: UInt64
    let totalMemoryBytes: UInt64
    let memoryUsageRatio: Double
    let memoryPressure: MemoryPressureLevel

    // CPU/Performance
    let processorCount: Int
    let activeProcessorCount: Int
    let isLowPowerModeEnabled: Bool

    // REAL CPU Utilization (via Mach APIs - same as Xcode Energy Impact)
    let systemCpuUsage: Double      // System-wide CPU % (0.0-100.0)
    let processCpuUsage: Double     // Our app's CPU % (0.0-100.0)

    // System
    let systemUptime: TimeInterval
    let osVersion: String
    let deviceModel: String

    // Pipeline optimization
    let optimizationLevel: PipelineOptimizationLevel
    let isConstrained: Bool

    // Computed
    var batteryPercent: Int {
        batteryLevel >= 0 ? Int(batteryLevel * 100) : -1
    }

    /// Display string for battery - handles Mac/desktop where battery info unavailable
    var batteryDisplayString: String {
        if batteryLevel < 0 {
            // On Mac or devices without battery info
            return "Plugged In"
        }
        return "\(batteryPercent)%"
    }

    var availableMemoryMB: Int {
        Int(availableMemoryBytes / 1024 / 1024)
    }

    var memoryUsagePercent: Int {
        Int(memoryUsageRatio * 100)
    }

    /// System CPU usage as integer percent (0-100)
    var systemCpuPercent: Int {
        Int(systemCpuUsage.rounded())
    }

    /// Process (our app) CPU usage as integer percent (0-100)
    var processCpuPercent: Int {
        Int(processCpuUsage.rounded())
    }

    /// Human-readable summary
    var summary: String {
        var parts: [String] = []
        parts.append("🌡️ \(thermalStateName)")
        if batteryLevel >= 0 {
            parts.append("🔋 \(batteryPercent)%\(isCharging ? "⚡" : "")")
        } else {
            // Mac or device without battery - show as plugged in
            parts.append("🔌 Plugged In")
        }
        parts.append("💾 \(availableMemoryMB)MB free")
        if isLowPowerModeEnabled {
            parts.append("🔅 LPM")
        }
        return parts.joined(separator: " • ")
    }

    /// Whether any metric is in a warning/critical state
    var hasWarning: Bool {
        thermalState == .serious ||
            thermalState == .critical ||
            memoryPressure == .warning ||
            memoryPressure == .critical ||
            (batteryLevel >= 0 && batteryLevel < 0.10 && !isCharging) ||
            isLowPowerModeEnabled
    }

    /// Whether any metric is in a critical state
    var hasCritical: Bool {
        thermalState == .critical ||
            memoryPressure == .critical ||
            (batteryLevel >= 0 && batteryLevel < 0.05 && !isCharging)
    }
}

// MARK: - Real CPU Monitoring via Mach APIs

/// Measures REAL CPU utilization using the same APIs Xcode Energy Impact uses
/// This is NOT simulated - it's actual kernel-level CPU accounting
enum MachCPUMonitor {

    // Track previous CPU ticks for delta calculation
    private static var previousSystemTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private static var previousProcessTime: UInt64?
    private static var previousMeasureTime: CFAbsoluteTime?

    /// Get system-wide CPU usage (0.0-100.0) - same metric as Xcode shows
    /// Uses host_statistics to get CPU ticks across all cores
    static func getSystemCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info_data_t()
        // HOST_CPU_LOAD_INFO_COUNT macro not available in Swift - calculate manually
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.0 }

        let userTicks = UInt64(cpuInfo.cpu_ticks.0)    // CPU_STATE_USER
        let systemTicks = UInt64(cpuInfo.cpu_ticks.1)  // CPU_STATE_SYSTEM
        let idleTicks = UInt64(cpuInfo.cpu_ticks.2)    // CPU_STATE_IDLE
        let niceTicks = UInt64(cpuInfo.cpu_ticks.3)    // CPU_STATE_NICE

        guard let prev = previousSystemTicks else {
            // First call - store baseline and return 0
            previousSystemTicks = (userTicks, systemTicks, idleTicks, niceTicks)
            return 0.0
        }

        let userDelta = userTicks - prev.user
        let systemDelta = systemTicks - prev.system
        let idleDelta = idleTicks - prev.idle
        let niceDelta = niceTicks - prev.nice

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return 0.0 }

        let usedDelta = userDelta + systemDelta + niceDelta
        let usage = (Double(usedDelta) / Double(totalDelta)) * 100.0

        // Update baseline for next call
        previousSystemTicks = (userTicks, systemTicks, idleTicks, niceTicks)

        return min(100.0, max(0.0, usage))
    }

    /// Get this app's process CPU usage (0.0-100.0)
    /// Uses task_info to get actual CPU time consumed by our process
    static func getProcessCPUUsage() -> Double {
        var taskInfo = task_basic_info()
        // TASK_BASIC_INFO_COUNT macro not available in Swift - calculate manually
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.0 }

        // CPU time = user time + system time (in microseconds)
        let userTimeUs = UInt64(taskInfo.user_time.seconds) * 1_000_000 + UInt64(taskInfo.user_time.microseconds)
        let systemTimeUs = UInt64(taskInfo.system_time.seconds) * 1_000_000 + UInt64(taskInfo.system_time.microseconds)
        let totalCPUTimeUs = userTimeUs + systemTimeUs

        let now = CFAbsoluteTimeGetCurrent()

        guard let prevTime = previousProcessTime, let prevMeasure = previousMeasureTime else {
            // First call - store baseline
            previousProcessTime = totalCPUTimeUs
            previousMeasureTime = now
            return 0.0
        }

        let cpuDeltaUs = Double(totalCPUTimeUs - prevTime)
        let wallDeltaUs = (now - prevMeasure) * 1_000_000  // Convert to microseconds

        guard wallDeltaUs > 0 else { return 0.0 }

        // CPU% = (CPU time used / wall time) * 100, divided by core count for single-core equivalent
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let usage = (cpuDeltaUs / wallDeltaUs) * 100.0 / Double(processorCount)

        // Update baseline
        previousProcessTime = totalCPUTimeUs
        previousMeasureTime = now

        return min(100.0, max(0.0, usage))
    }

    /// Reset baselines (call when app comes to foreground)
    static func reset() {
        previousSystemTicks = nil
        previousProcessTime = nil
        previousMeasureTime = nil
    }
}

// MARK: - Memory Pressure Level

enum MemoryPressureLevel: String, Sendable {
    case nominal = "Nominal"
    case warning = "Warning"
    case critical = "Critical"

    var icon: String {
        switch self {
        case .nominal: return "memorychip"
        case .warning: return "memorychip.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .nominal: return "green"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
}

// MARK: - System State Monitor

/// Real-time monitor for all device state metrics
@MainActor
final class SystemStateMonitor: ObservableObject {
    // MARK: - Singleton

    static let shared = SystemStateMonitor()

    // MARK: - Published State

    @Published private(set) var currentState: SystemStateSnapshot
    @Published private(set) var stateHistory: [SystemStateSnapshot] = []

    /// How often to capture state (seconds)
    private let captureInterval: TimeInterval = 2.0
    private let maxHistoryCount = 60 // Keep last 2 minutes

    // MARK: - Private

    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var batteryLevelObserver: NSObjectProtocol?
    private var batteryStateObserver: NSObjectProtocol?
    private var lowPowerObserver: NSObjectProtocol?
    private var memoryObserver: NSObjectProtocol?

    // MARK: - Initialization

    private init() {
        // Enable battery monitoring (iOS only)
#if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
#endif

        // Capture initial state
        currentState = Self.captureState()

        // Setup observers
        setupObservers()

        // Start periodic capture
        startPeriodicCapture()
    }

    deinit {
        timer?.invalidate()
        [thermalObserver, batteryLevelObserver, batteryStateObserver, lowPowerObserver, memoryObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Public API

    /// Force refresh of state
    func refresh() {
        updateState()
    }

    /// Get thermal state color
    static func thermalColor(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "green"
        case .fair: return "blue"
        case .serious: return "orange"
        case .critical: return "red"
        @unknown default: return "gray"
        }
    }

    /// Get thermal icon
    static func thermalIcon(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "thermometer.sun.fill"
        @unknown default: return "thermometer"
        }
    }

    /// Get battery icon
    static func batteryIcon(level: Float, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        if level < 0 {
            return "battery.0percent"
        }
        if level < 0.10 {
            return "battery.0percent"
        }
        if level < 0.25 {
            return "battery.25percent"
        }
        if level < 0.50 {
            return "battery.50percent"
        }
        if level < 0.75 {
            return "battery.75percent"
        }
        return "battery.100percent"
    }

    // MARK: - Private Helpers

    private static func captureState() -> SystemStateSnapshot {
        let processInfo = ProcessInfo.processInfo

        // Thermal
        let thermal = processInfo.thermalState
        let thermalName: String = {
            switch thermal {
            case .nominal: return "Nominal"
            case .fair: return "Fair"
            case .serious: return "Serious"
            case .critical: return "Critical"
            @unknown default: return "Unknown"
            }
        }()

        // Battery - Mac detection needed because iOS battery API often returns garbage on Mac
        let isMac = DeviceCapabilityService.shared.isMac || processInfo.isiOSAppOnMac

#if canImport(UIKit)
        let device = UIDevice.current
        let rawBatteryLevel = device.batteryLevel
        let rawBatteryState = device.batteryState

        let batteryLevel: Float
        let batteryState: UIDevice.BatteryState
        let isCharging: Bool
        let isFullyCharged: Bool

        if isMac {
            // On Mac, check if battery values look like garbage
            let looksLikeGarbage = rawBatteryState == .unknown ||
                rawBatteryLevel < 0 ||
                (rawBatteryLevel < 0.05 && rawBatteryState != .unplugged)

            if looksLikeGarbage {
                // Garbage values - assume full power (desktop Mac or broken API)
                batteryLevel = 1.0
                batteryState = .full
                isCharging = true
                isFullyCharged = true
            } else {
                // Values look plausible - trust them (MacBook with working battery API)
                batteryLevel = rawBatteryLevel
                batteryState = rawBatteryState
                isCharging = rawBatteryState == .charging || rawBatteryState == .full
                isFullyCharged = rawBatteryState == .full
            }
        } else {
            batteryLevel = rawBatteryLevel
            batteryState = rawBatteryState
            isCharging = rawBatteryState == .charging || rawBatteryState == .full
            isFullyCharged = rawBatteryState == .full
        }
#else
        // macOS: assume plugged in / full
        let batteryLevel: Float = 1.0
        let batteryState: MacBatteryState = .full
        let isCharging = true
        let isFullyCharged = true
        let _ = isMac // suppress unused warning
#endif

        // Memory
        let availableMemory: UInt64
        #if os(iOS)
        availableMemory = UInt64(os_proc_available_memory())
        #else
        availableMemory = Self.macAvailableMemory()
        #endif
        let totalMemory = processInfo.physicalMemory
        let memoryRatio = 1.0 - (Double(availableMemory) / Double(totalMemory))

        let memoryPressure: MemoryPressureLevel
        let availableRatio = Double(availableMemory) / Double(totalMemory)
        if availableRatio < 0.10 {
            memoryPressure = .critical
        } else if availableRatio < 0.20 {
            memoryPressure = .warning
        } else {
            memoryPressure = .nominal
        }

        // CPU
        let processorCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        let isLowPowerMode = processInfo.isLowPowerModeEnabled

        // System
        let uptime = processInfo.systemUptime
        let osVersion = "\(processInfo.operatingSystemVersionString)"
#if canImport(UIKit)
        let deviceModel = UIDevice.current.model
#else
        let deviceModel = "Mac"
#endif

        // Pipeline
        let optimizer = AdaptivePipelineOptimizer.shared
        let optimizationLevel = optimizer.currentOptimizationLevel
        let isConstrained = optimizer.currentState.isConstrained

        // REAL CPU Utilization via Mach APIs (same as Xcode Energy Impact)
        let systemCpuUsage = MachCPUMonitor.getSystemCPUUsage()
        let processCpuUsage = MachCPUMonitor.getProcessCPUUsage()

        return SystemStateSnapshot(
            thermalState: thermal,
            thermalStateName: thermalName,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            availableMemoryBytes: availableMemory,
            totalMemoryBytes: totalMemory,
            memoryUsageRatio: memoryRatio,
            memoryPressure: memoryPressure,
            processorCount: processorCount,
            activeProcessorCount: activeProcessorCount,
            isLowPowerModeEnabled: isLowPowerMode,
            systemCpuUsage: systemCpuUsage,
            processCpuUsage: processCpuUsage,
            systemUptime: uptime,
            osVersion: osVersion,
            deviceModel: deviceModel,
            optimizationLevel: optimizationLevel,
            isConstrained: isConstrained
        )
    }

    static func macAvailableMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let freePages = UInt64(stats.free_count)
            let inactivePages = UInt64(stats.inactive_count)
            return (freePages + inactivePages) * pageSize
        }
        return ProcessInfo.processInfo.physicalMemory / 2
    }

    private func updateState() {
        let newState = Self.captureState()
        currentState = newState

        // Add to history
        stateHistory.append(newState)
        if stateHistory.count > maxHistoryCount {
            stateHistory.removeFirst(stateHistory.count - maxHistoryCount)
        }
    }

    private func setupObservers() {
        // Thermal state changes (immediate update)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                let oldThermal = self?.currentState.thermalState
                self?.updateState()
                // Haptic feedback for thermal state changes
                if let newThermal = self?.currentState.thermalState, oldThermal != newThermal {
                    self?.triggerThermalHaptic(for: newThermal)
                }
            }
        }

        // Battery level changes (iOS only)
#if canImport(UIKit)
        batteryLevelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                let oldLevel = self?.currentState.batteryLevel ?? 0
                self?.updateState()
                // Haptic for battery milestones (every 10%)
                if let newLevel = self?.currentState.batteryLevel {
                    let oldTens = Int(oldLevel * 10)
                    let newTens = Int(newLevel * 10)
                    if oldTens != newTens && newLevel >= 0 {
                        DSHaptics.tick()
                    }
                }
            }
        }

        // Battery state changes (charging, unplugged)
        batteryStateObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                let oldCharging = self?.currentState.isCharging ?? false
                self?.updateState()
                // Haptic for charger connect/disconnect
                if let newCharging = self?.currentState.isCharging, oldCharging != newCharging {
                    if newCharging {
                        DSHaptics.success() // Connected
                    } else {
                        DSHaptics.soft() // Disconnected
                    }
                }
            }
        }
#endif


        // Low power mode changes
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                let wasLPM = self?.currentState.isLowPowerModeEnabled ?? false
                self?.updateState()
                // Haptic for low power mode toggle
                if let isLPM = self?.currentState.isLowPowerModeEnabled, wasLPM != isLPM {
                    DSHaptics.toggle()
                }
            }
        }

        // Memory warnings
#if canImport(UIKit)
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
                // Distinct warning haptic for memory pressure
                DSHaptics.warning()
            }
        }
#endif
    }

    /// Haptic feedback based on thermal state
    private func triggerThermalHaptic(for state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            DSHaptics.soft() // Cooling down - gentle
        case .fair:
            DSHaptics.thermalPulse(intensity: 0.4) // Getting warm
        case .serious:
            DSHaptics.thermalPulse(intensity: 0.7) // Hot
        case .critical:
            DSHaptics.warning() // Critical warning
        @unknown default:
            break
        }
    }

    private func startPeriodicCapture() {
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }
    }
}

// MARK: - Extensions

extension ProcessInfo.ThermalState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

#if canImport(UIKit)
extension UIDevice.BatteryState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }
}
#else
/// macOS battery state stub (no UIDevice available on macOS native target)
enum MacBatteryState: Sendable, Equatable, CustomStringConvertible {
    case unknown, unplugged, charging, full
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        }
    }
}
#endif
